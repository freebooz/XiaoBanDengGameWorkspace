package httpapi

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// TestMahjongReleaseMultiTableCapacity starts one disposable API and exercises
// bounded concurrent gameplay through normal authenticated clients.
func TestMahjongReleaseMultiTableCapacity(t *testing.T) {
	if os.Getenv("XBD_MAHJONG_TEST_MULTI_TABLE") != "1" {
		t.Skip("set XBD_MAHJONG_TEST_MULTI_TABLE=1 and disposable restart API/DB endpoints")
	}
	count := 8
	if value := os.Getenv("XBD_MAHJONG_TEST_MULTI_TABLES"); value != "" {
		var err error
		count, err = strconv.Atoi(value)
		if err != nil || count < 2 || count > 12 {
			t.Fatal("XBD_MAHJONG_TEST_MULTI_TABLES must be between 2 and 12")
		}
	}
	binary := os.Getenv("XBD_MAHJONG_RESTART_API")
	if info, err := os.Stat(binary); !filepath.IsAbs(binary) || err != nil || !info.Mode().IsRegular() {
		t.Fatal("XBD_MAHJONG_RESTART_API must name an absolute path to the compiled cmd/api executable")
	}
	postgres, err := url.Parse(os.Getenv("XBD_MAHJONG_TEST_POSTGRES_URL"))
	redis := os.Getenv("XBD_MAHJONG_TEST_REDIS_ADDR")
	if err != nil || (postgres.Scheme != "postgres" && postgres.Scheme != "postgresql") || !restartLoopback(postgres.Host) || postgres.RawQuery != "sslmode=disable" || len(postgres.Path) < 2 || !restartLoopback(redis) {
		t.Fatal("set disposable loopback PostgreSQL URL (?sslmode=disable) and Redis host:port")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close()
	endpoint := "http://" + addr
	launchRestartAPI(t, binary, endpoint, []string{
		"HTTP_ADDR=" + addr, "POSTGRES_URL=" + postgres.String(), "REDIS_ADDR=" + redis,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"), "REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
	})
	type table struct {
		roomID  string
		matchID string
		guests  [4]restartGuest
		lobby   [4]*websocket.Conn
		samples []time.Duration
	}
	tables := make([]table, count)
	accounts := make(map[string]bool, count*4)
	rooms := make(map[string]bool, count)
	for index := range tables {
		table := &tables[index]
		for seat := range table.guests {
			guest := loadRestartGuest(t, endpoint, "")
			if accounts[guest.ID] {
				t.Fatal("production guest login reused a concurrent table identity")
			}
			accounts[guest.ID] = true
			table.guests[seat] = guest
			table.lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
			lobbyState(t, table.lobby[seat], "idle", 0, 0)
		}
		if index == 0 {
			verifyMahjongQuickCancelRejoin(t, table.lobby[0])
		}
		lobbyCommand(t, table.lobby[0], "create", "", "guiyang", "2.0.0", true)
		table.roomID = lobbyState(t, table.lobby[0], "waiting", 1, 0)["room_id"].(string)
		if rooms[table.roomID] {
			t.Fatal("concurrent rooms shared a number")
		}
		rooms[table.roomID] = true
		for _, conn := range table.lobby[1:] {
			lobbyCommand(t, conn, "join", table.roomID, "", "", true)
		}
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true, "requires_kong_to_claim": true, "rob_kong": true}
	if !t.Run("concurrent tables", func(t *testing.T) {
		for index := range tables {
			t.Run(fmt.Sprintf("table-%02d", index+1), func(t *testing.T) {
				t.Parallel()
				item := &tables[index]
				otherRoom := tables[(index+1)%count].roomID
				probe := restartSocket(t, endpoint, item.guests[0])
				referenceSend(t, probe, map[string]any{"type": "mahjong_join", "room_id": otherRoom})
				lobbyRead(t, probe, "mahjong_error", nil)
				probe.Close()
				for _, conn := range item.lobby {
					lobbyCommand(t, conn, "ready", item.roomID, "", "", true)
					// The board has its own socket. Close this idle lobby stream
					// instead of leaving it unattended during a full game.
					conn.Close()
				}
				board, states, matchID := startFriendRestartRound(t, endpoint, item.guests, item.roomID, "", options)
				item.matchID = matchID
				item.samples = playMultiTableMahjong(t, item.roomID, matchID, item.guests, options, board, states)
			})
		}
	}) {
		return
	}
	matches := make(map[string]bool, count)
	var samples []time.Duration
	for _, table := range tables {
		if table.matchID == "" || matches[table.matchID] || len(table.samples) == 0 {
			t.Fatal("concurrent tables shared a match ID or did not complete")
		}
		matches[table.matchID] = true
		samples = append(samples, table.samples...)
	}
	slices.Sort(samples)
	percentile := func(p int) time.Duration { return samples[(len(samples)*p+99)/100-1] }
	t.Logf("MAHJONG_MULTI_TABLE_OK tables=%d guest_accounts=%d settled=%d commands=%d ack_p50=%s ack_p95=%s ack_max=%s quick_cancel_requeue=true cross_room_denied=true",
		count, len(accounts), len(matches), len(samples), percentile(50), percentile(95), samples[len(samples)-1])
}

func verifyMahjongQuickCancelRejoin(t *testing.T, lobby *websocket.Conn) {
	t.Helper()
	for range 2 {
		lobbyCommand(t, lobby, "quick", "", "guiyang", "2.0.0", true)
		waiting := lobbyState(t, lobby, "waiting", 1, 0)
		if waiting["kind"] != "quick" || waiting["seat_index"] != float64(0) || waiting["room_id"] == "" {
			t.Fatal("quick queue did not assign the only waiting account")
		}
		lobbyCommand(t, lobby, "leave", waiting["room_id"].(string), "", "", true)
		idle := lobbyState(t, lobby, "idle", 0, 0)
		if idle["room_id"] != "" || idle["seat_index"] != float64(-1) {
			t.Fatal("cancelling quick match retained the stale assignment")
		}
	}
}

func playMultiTableMahjong(t *testing.T, roomID, matchID string, guests [4]restartGuest, options map[string]any, board [4]*websocket.Conn, states [4]map[string]any) []time.Duration {
	t.Helper()
	var samples []time.Duration
	for step := 1; step <= 120; step++ {
		seat, kind, tile := chooseFriendRestartAction(states)
		if seat < 0 {
			t.Fatal("active board has no legal action")
		}
		id := fmt.Sprintf("multi-table-action-%d", step)
		started := time.Now()
		referenceSend(t, board[seat], restartAction(roomID, matchID, id, kind, tile))
		waitRestartAction(t, board[seat], id)
		samples = append(samples, time.Since(started))
		for peer, conn := range board {
			epoch := states[peer]["epoch"].(float64)
			states[peer] = lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool {
				// Inspect every snapshot, including events already in the queue.
				verifyRestartIdentity(t, msg, guests, roomID, matchID, peer, options)
				return msg["epoch"].(float64) > epoch
			})
		}
		if states[0]["status"] == "finished" {
			var total float64
			for _, score := range states[0]["scores"].([]any) {
				total += score.(float64)
			}
			for peer, state := range states {
				if state["status"] != "finished" || !reflect.DeepEqual(state["scores"], states[0]["scores"]) || total != 0 {
					t.Fatalf("seat %d received an inconsistent settlement", peer)
				}
			}
			return samples
		}
	}
	t.Fatal("active table failed to finish after 120 legal actions")
	return nil
}
