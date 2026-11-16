package httpapi

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/gorilla/websocket"
)

// TestMahjongFriendRoomAcrossAPIReboots owns its cmd/api processes and reuses
// the disposable database endpoints required by TestMahjongReleaseServiceRestart.
func TestMahjongFriendRoomAcrossAPIReboots(t *testing.T) {
	binary := os.Getenv("XBD_MAHJONG_RESTART_API")
	if binary == "" {
		t.Skip("set XBD_MAHJONG_RESTART_API and disposable loopback PostgreSQL/Redis endpoints")
	}
	if info, err := os.Stat(binary); !filepath.IsAbs(binary) || err != nil || !info.Mode().IsRegular() {
		t.Fatal("XBD_MAHJONG_RESTART_API must name an absolute path to the compiled cmd/api executable")
	}
	postgresURL := os.Getenv("XBD_MAHJONG_TEST_POSTGRES_URL")
	redisAddr := os.Getenv("XBD_MAHJONG_TEST_REDIS_ADDR")
	parsed, err := url.Parse(postgresURL)
	if err != nil || (parsed.Scheme != "postgres" && parsed.Scheme != "postgresql") || !restartLoopback(parsed.Host) || parsed.RawQuery != "sslmode=disable" || len(parsed.Path) < 2 || !restartLoopback(redisAddr) {
		t.Fatal("set disposable numeric loopback PostgreSQL URL (database path, explicit port, ?sslmode=disable) and Redis host:port")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close()
	endpoint := "http://" + addr
	apiEnv := []string{
		"HTTP_ADDR=" + addr, "POSTGRES_URL=" + postgresURL, "REDIS_ADDR=" + redisAddr,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"),
		"REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
	}
	firstAPI := launchRestartAPI(t, binary, endpoint, apiEnv)
	var guests [4]restartGuest
	var lobby [4]*websocket.Conn
	for seat := range guests {
		guests[seat] = loadRestartGuest(t, endpoint, "")
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guests[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": false, "black_eight": false, "requires_kong_to_claim": true, "rob_kong": false}
	referenceSend(t, lobby[0], map[string]any{"type": "mahjong_lobby_command", "action": "create", "command_id": "friend-restart-create",
		"rule_set_id": "guiyang", "rule_version": "2.0.0", "options": options})
	if ack := lobbyRead(t, lobby[0], "mahjong_lobby_result", nil); ack["ok"] != true {
		t.Fatal("custom friend room creation failed")
	}
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for seat := 1; seat < 4; seat++ {
		lobbyCommand(t, lobby[seat], "join", roomID, "", "", true)
	}
	for _, seat := range []int{0, 2} {
		lobbyCommand(t, lobby[seat], "ready", roomID, "", "", true)
	}
	readyAccounts := []any{guests[0].ID, guests[2].ID}
	for seat, conn := range lobby {
		state := lobbyState(t, conn, "matched", 4, 2)
		verifyFriendRestartLobby(t, state, guests, roomID, seat, 0, "", readyAccounts, options)
	}
	firstAPI.stop(t)
	secondAPI := launchRestartAPI(t, binary, endpoint, apiEnv)
	for seat, guest := range guests {
		if restored := loadRestartGuest(t, endpoint, guest.Token); restored.ID != guest.ID {
			t.Fatalf("partial room restart changed identity of seat %d", seat)
		}
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
		state := lobbyState(t, lobby[seat], "matched", 4, 2)
		verifyFriendRestartLobby(t, state, guests, roomID, seat, 0, "", readyAccounts, options)
	}
	lobbyCommand(t, lobby[3], "leave", roomID, "", "", true)
	lobbyState(t, lobby[3], "idle", 0, 0)
	secondAPI.stop(t)
	thirdAPI := launchRestartAPI(t, binary, endpoint, apiEnv)
	for seat, guest := range guests {
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
		if seat == 3 {
			lobbyState(t, lobby[seat], "idle", 0, 0)
			continue
		}
		state := lobbyState(t, lobby[seat], "waiting", 3, 0)
		if state["room_id"] != roomID || state["seat_index"] != float64(seat) || !reflect.DeepEqual(state["player_account_ids"], []any{guests[0].ID, guests[1].ID, guests[2].ID}) {
			t.Fatalf("seat %d did not retain the remaining roster after leave", seat)
		}
	}
	lobbyCommand(t, lobby[3], "join", roomID, "", "", true)
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	predeal := joinRestartBoard(t, endpoint, guests[0], roomID, "", 0)
	reserved := lobbyRead(t, predeal, "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "waiting" })
	reservedMatchID, _ := reserved["match_id"].(string)
	verifyRestartIdentity(t, reserved, guests, roomID, reservedMatchID, 0, options)
	thirdAPI.stop(t)
	fourthAPI := launchRestartAPI(t, binary, endpoint, apiEnv)
	for seat, guest := range guests {
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
		state := lobbyState(t, lobby[seat], "playing", 4, 4)
		if state["room_id"] != roomID || state["seat_index"] != float64(seat) || state["start"] != true {
			t.Fatalf("seat %d did not retain the committed pre-deal assignment", seat)
		}
	}
	firstBoard, states, firstMatchID := startFriendRestartRound(t, endpoint, guests, roomID, reservedMatchID, options)
	if firstMatchID != reservedMatchID {
		t.Fatal("first deal did not use the previously issued match ID")
	}
	finished, moves := playFriendRestartRound(t, firstBoard, states, roomID, firstMatchID)
	// All four received the authentic finish. Crash before any next-round command.
	fourthAPI.stop(t)
	fifthAPI := launchRestartAPI(t, binary, endpoint, apiEnv)
	pids := []int{firstAPI.cmd.Process.Pid, secondAPI.cmd.Process.Pid, thirdAPI.cmd.Process.Pid, fourthAPI.cmd.Process.Pid, fifthAPI.cmd.Process.Pid}
	seenPIDs := make(map[int]bool, len(pids))
	for _, pid := range pids {
		if seenPIDs[pid] {
			t.Fatal("expected five distinct owned cmd/api process IDs")
		}
		seenPIDs[pid] = true
	}
	for seat, guest := range guests {
		if restored := loadRestartGuest(t, endpoint, guest.Token); restored.ID != guest.ID {
			t.Fatalf("settlement restart changed identity of seat %d", seat)
		}
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
		state := lobbyState(t, lobby[seat], "matched", 4, 0)
		verifyFriendRestartLobby(t, state, guests, roomID, seat, 1, firstMatchID, []any{}, options)
		conn := joinRestartBoard(t, endpoint, guest, roomID, firstMatchID, seat)
		settled := lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "finished" })
		verifyRestartIdentity(t, settled, guests, roomID, firstMatchID, seat, options)
		compareRestartTable(t, finished[seat], settled, seat)
		for _, key := range []string{"winners", "reason", "win_kind", "flipped_ji", "ji_counts"} {
			if !reflect.DeepEqual(settled[key], finished[seat][key]) {
				t.Fatalf("seat %d restored different settlement %s", seat, key)
			}
		}
		if settled["can_rematch"] != true {
			t.Fatalf("seat %d cannot rematch from recovered settlement", seat)
		}
	}
	verifyRestartedFriendHistory(t, endpoint, guests, firstMatchID, finished[0])
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	secondBoard, next, secondMatchID := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	if firstMatchID == secondMatchID {
		t.Fatal("rematch reused the recovered match ID")
	}
	turn := int(next[0]["turn"].(float64))
	tile := next[turn]["hand"].([]any)[0].(map[string]any)["id"]
	referenceSend(t, secondBoard[turn], restartAction(roomID, secondMatchID, "friend-rematch-first-discard", "play", tile))
	waitRestartAction(t, secondBoard[turn], "friend-rematch-first-discard")
	lobbyRead(t, secondBoard[turn], "mahjong_state", func(msg map[string]any) bool { return restartHasDiscard(msg, turn, tile) })
	t.Logf("MAHJONG_FRIEND_ROOM_RESTART_OK pids=%v room=%s first=%s second=%s partial_ready=2 lobby_leave_restored=true reserved_match_restored=true restored_settlements=4 moves=%d",
		pids, roomID, firstMatchID, secondMatchID, moves)
}

func verifyRestartedFriendHistory(t *testing.T, endpoint string, guests [4]restartGuest, matchID string, state map[string]any) {
	t.Helper()
	request := func(guest restartGuest, suffix string, wantStatus int, into any) {
		t.Helper()
		client := http.Client{Timeout: 3 * time.Second}
		req, err := http.NewRequest(http.MethodGet, endpoint+"/api/v1/mahjong/history/"+matchID+suffix, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer "+guest.Token)
		response, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != wantStatus {
			t.Fatalf("history %s returned %d, want %d", suffix, response.StatusCode, wantStatus)
		}
		if into != nil {
			if err := json.NewDecoder(response.Body).Decode(into); err != nil {
				t.Fatal(err)
			}
		}
	}
	var expected guiyang.ScoreBreakdown
	raw, err := json.Marshal(state["score_breakdown"])
	if err != nil || json.Unmarshal(raw, &expected) != nil || state["score_breakdown"] == nil {
		t.Fatal("live settlement omitted its score breakdown")
	}
	var rawDiscards []guiyang.Discard
	discards, err := json.Marshal(state["discards"])
	if err != nil || json.Unmarshal(discards, &rawDiscards) != nil || len(rawDiscards) == 0 {
		t.Fatal("live settlement omitted public discards")
	}
	for seat, guest := range guests {
		var detail struct{ Match mahjonghistory.Summary }
		request(guest, "", http.StatusOK, &detail)
		if detail.Match.YourSeat != seat || detail.Match.Breakdown == nil || *detail.Match.Breakdown != expected {
			t.Fatalf("seat %d history does not match live settlement", seat)
		}
		var result struct{ Replay guiyang.Replay }
		request(guest, "/replay", http.StatusOK, &result)
		board, err := result.Replay.Project(len(result.Replay.Events))
		if err != nil || board.Reason != detail.Match.Reason || !reflect.DeepEqual(board.Discards, rawDiscards) {
			t.Fatalf("seat %d replay did not reconstruct the original public discards: %v", seat, err)
		}
	}
	outsider := loadRestartGuest(t, endpoint, "")
	request(outsider, "", http.StatusNotFound, nil)
	request(outsider, "/replay", http.StatusNotFound, nil)
	t.Log("MAHJONG_PERSISTED_REPLAY_OK seats=4 private_history=true score_breakdown=true public_discards_match=true")
}

func subscribeFriendRestartLobby(t *testing.T, endpoint string, guest restartGuest) *websocket.Conn {
	t.Helper()
	conn := restartSocket(t, endpoint, guest)
	referenceSend(t, conn, map[string]any{"type": "mahjong_lobby_subscribe"})
	return conn
}

func verifyFriendRestartLobby(t *testing.T, state map[string]any, guests [4]restartGuest, roomID string, seat, completed int, prior string, ready []any, options map[string]any) {
	t.Helper()
	rule, _ := state["rule"].(map[string]any)
	players := []any{guests[0].ID, guests[1].ID, guests[2].ID, guests[3].ID}
	if state["room_id"] != roomID || state["kind"] != "friend" || state["seat_index"] != float64(seat) || state["start"] != false ||
		state["rule_set_id"] != "guiyang" || state["rule_version"] != "2.0.0" || !reflect.DeepEqual(rule["options"], options) ||
		state["completed_rounds"] != float64(completed) || state["previous_match_id"] != prior ||
		!reflect.DeepEqual(state["player_account_ids"], players) || !reflect.DeepEqual(state["ready_account_ids"], ready) {
		t.Fatalf("seat %d received a different lobby room, rule, roster, readiness or round history", seat)
	}
}

func startFriendRestartRound(t *testing.T, endpoint string, guests [4]restartGuest, roomID, expectedMatchID string, options map[string]any) ([4]*websocket.Conn, [4]map[string]any, string) {
	t.Helper()
	var board [4]*websocket.Conn
	var states [4]map[string]any
	for seat, guest := range guests {
		board[seat] = joinRestartBoard(t, endpoint, guest, roomID, expectedMatchID, seat)
	}
	matchID := ""
	tiles := make(map[any]bool, 53)
	for seat, conn := range board {
		state := lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "playing" })
		if seat == 0 {
			matchID, _ = state["match_id"].(string)
		}
		verifyRestartIdentity(t, state, guests, roomID, matchID, seat, options)
		if len(state["discards"].([]any)) != 0 || state["remaining"] != float64(55) {
			t.Fatalf("seat %d joined without a fresh deal", seat)
		}
		for _, entry := range state["hand"].([]any) {
			id := entry.(map[string]any)["id"]
			if tiles[id] {
				t.Fatal("new round exposed duplicate private tiles")
			}
			tiles[id] = true
		}
		states[seat] = state
	}
	if len(tiles) != 53 {
		t.Fatalf("new round delivered %d private tile IDs, want 53", len(tiles))
	}
	return board, states, matchID
}

func playFriendRestartRound(t *testing.T, board [4]*websocket.Conn, states [4]map[string]any, roomID, matchID string) ([4]map[string]any, int) {
	t.Helper()
	for step := 1; step <= 120; step++ {
		seat, kind, tile := chooseFriendRestartAction(states)
		if seat < 0 {
			t.Fatal("no legal action in active round")
		}
		id := fmt.Sprintf("friend-restart-%d", step)
		referenceSend(t, board[seat], restartAction(roomID, matchID, id, kind, tile))
		waitRestartAction(t, board[seat], id)
		for peer, conn := range board {
			epoch := states[peer]["epoch"].(float64)
			states[peer] = lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return msg["epoch"].(float64) > epoch })
		}
		if states[0]["status"] == "finished" {
			for peer, state := range states {
				if state["status"] != "finished" || !reflect.DeepEqual(state["scores"], states[0]["scores"]) || state["can_rematch"] != true {
					t.Fatalf("seat %d received a different settlement", peer)
				}
			}
			return states, step
		}
	}
	t.Fatal("round did not settle after 120 legal actions")
	return states, 0
}

func chooseFriendRestartAction(states [4]map[string]any) (int, string, any) {
	for _, kind := range []string{"hu", "pass", "play"} {
		for seat, state := range states {
			for _, entry := range state["options"].([]any) {
				if entry.(map[string]any)["type"] != kind {
					continue
				}
				if kind == "play" {
					return seat, kind, state["hand"].([]any)[0].(map[string]any)["id"]
				}
				return seat, kind, nil
			}
		}
	}
	return -1, "", nil
}
