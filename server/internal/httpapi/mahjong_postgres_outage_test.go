package httpapi

import (
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// The API process and its PostgreSQL path are isolated. The database and Redis
// keep running so only the affected API experiences this outage.
func TestMahjongReleasePreservesDecisionTimeAfterPostgresOutage(t *testing.T) {
	if os.Getenv("XBD_MAHJONG_TEST_DB_OUTAGE") != "1" {
		t.Skip("set XBD_MAHJONG_TEST_DB_OUTAGE=1 and the disposable restart API/DB endpoints")
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
	proxy := newMahjongOutageProxy(t, postgres.Host)
	postgres.Host = proxy.listener.Addr().String()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close()
	endpoint := "http://" + addr
	launchRestartAPI(t, binary, endpoint, []string{
		"HTTP_ADDR=" + addr, "POSTGRES_URL=" + postgres.String(), "REDIS_ADDR=" + redis,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"),
		"REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
	})
	var guests [4]restartGuest
	var lobby [4]*websocket.Conn
	for seat := range guests {
		guests[seat] = loadRestartGuest(t, endpoint, "")
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guests[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true, "requires_kong_to_claim": true, "rob_kong": true}
	lobbyCommand(t, lobby[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for _, conn := range lobby[1:] {
		lobbyCommand(t, conn, "join", roomID, "", "", true)
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	board, initial, matchID := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	turn := int(initial[0]["turn"].(float64))
	tile := initial[turn]["hand"].([]any)[0].(map[string]any)["id"]
	if initial[turn]["action_timeout_seconds"] != float64(15) {
		t.Fatal("expected the normal 15-second turn budget")
	}
	if proxy.pause() == 0 {
		t.Fatal("PostgreSQL proxy closed no active API connections")
	}
	outageStarted := time.Now()
	referenceSend(t, board[turn], restartAction(roomID, matchID, "outage-play", "play", tile))
	for seat, conn := range board {
		saving := readMahjongOutageState(t, conn, 8*time.Second, func(msg map[string]any) bool { return msg["saving"] == true })
		checkMahjongSavingSnapshot(t, saving, initial[seat], seat)
	}
	// A second submission must receive a rejection while the first is pending.
	// This also reads the original seat's queued packets and detects early acks.
	referenceSend(t, board[turn], restartAction(roomID, matchID, "outage-probe", "play", tile))
	if ack := lobbyRead(t, board[turn], "mahjong_action_result", nil); ack["command_id"] != "outage-probe" || ack["ok"] != false {
		t.Fatal("pending action was accepted or board accepted another action while saving")
	}
	// Poll the current board through the outage. Reading these replies also
	// handles the WebSocket pings on the same four connections.
	until := outageStarted.Add(16 * time.Second)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		for seat, conn := range board {
			referenceSend(t, conn, map[string]any{"type": "mahjong_join", "room_id": roomID, "match_id": matchID})
			lobbyRead(t, conn, "mahjong_joined", nil)
			saving := readMahjongOutageState(t, conn, 5*time.Second, func(msg map[string]any) bool { return msg["saving"] == true })
			checkMahjongSavingSnapshot(t, saving, initial[seat], seat)
		}
		if !time.Now().Before(until) {
			break
		}
		<-ticker.C
	}
	outageDuration := time.Since(outageStarted)
	proxy.resume()
	waitRestartAction(t, board[turn], "outage-play")
	var committed [4]map[string]any
	for seat, conn := range board {
		committed[seat] = readMahjongOutageState(t, conn, 8*time.Second, func(msg map[string]any) bool {
			return msg["saving"] != true && restartHasDiscard(msg, turn, tile)
		})
		if len(committed[seat]["discards"].([]any)) != 1 || committed[seat]["epoch"].(float64) <= initial[seat]["epoch"].(float64) {
			t.Fatalf("seat %d lost original discard or advanced another turn before recovery", seat)
		}
	}
	seat, kind, nextTile := chooseFriendRestartAction(committed)
	if seat < 0 {
		t.Fatal("recovered board has no legal next decision")
	}
	next := committed[seat]
	deadline, _ := next["action_deadline_ms"].(float64)
	remaining := int64(deadline) - time.Now().UnixMilli()
	if remaining <= 13000 || remaining > 15500 || deadline-next["server_now_ms"].(float64) <= 13000 {
		t.Fatalf("decision after outage had %dms left, want a fresh 15s budget", remaining)
	}
	referenceSend(t, board[seat], restartAction(roomID, matchID, "after-outage", kind, nextTile))
	waitRestartAction(t, board[seat], "after-outage")
	readMahjongOutageState(t, board[seat], 5*time.Second, func(msg map[string]any) bool { return msg["epoch"].(float64) > next["epoch"].(float64) })
	t.Logf("MAHJONG_POSTGRES_OUTAGE_OK room=%s match=%s outage_ms=%d fresh_decision_ms=%d next_action=%s", roomID, matchID, outageDuration.Milliseconds(), remaining, kind)
}

func checkMahjongSavingSnapshot(t *testing.T, saving, initial map[string]any, seat int) {
	t.Helper()
	options, validOptions := saving["options"].([]any)
	if saving["saving"] != true || !validOptions || len(options) != 0 || saving["action_deadline_ms"] != float64(0) {
		t.Fatalf("seat %d could act while action awaited persistence", seat)
	}
	for _, key := range []string{"room_id", "match_id", "your_seat", "epoch", "phase", "turn", "hand", "hand_counts", "discards", "remaining", "melds", "scores"} {
		if !reflect.DeepEqual(saving[key], initial[key]) {
			t.Fatalf("seat %d saw uncommitted change of %s", seat, key)
		}
	}
}

func readMahjongOutageState(t *testing.T, conn *websocket.Conn, wait time.Duration, accept func(map[string]any) bool) map[string]any {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(wait)); err != nil {
		t.Fatal(err)
	}
	for {
		var msg map[string]any
		if err := conn.ReadJSON(&msg); err != nil {
			t.Fatalf("waiting for PostgreSQL outage board state: %v", err)
		}
		if msg["type"] == "mahjong_error" {
			t.Fatalf("unexpected board error: %v", msg["message"])
		}
		if msg["type"] == "mahjong_state" && accept(msg) {
			return msg
		}
	}
}

type mahjongOutageProxy struct {
	listener net.Listener
	mu       sync.Mutex
	active   map[net.Conn]net.Conn
	paused   bool
	workers  sync.WaitGroup
}

func newMahjongOutageProxy(t *testing.T, upstream string) *mahjongOutageProxy {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := &mahjongOutageProxy{listener: listener, active: make(map[net.Conn]net.Conn)}
	p.workers.Add(1)
	go func() {
		defer p.workers.Done()
		for {
			client, err := listener.Accept()
			if err != nil {
				return
			}
			p.mu.Lock()
			if p.paused {
				p.mu.Unlock()
				client.Close()
				continue
			}
			server, err := net.DialTimeout("tcp", upstream, 500*time.Millisecond)
			if err != nil {
				p.mu.Unlock()
				client.Close()
				continue
			}
			p.active[client] = server
			p.mu.Unlock()
			p.workers.Add(1)
			go p.forward(client, server)
		}
	}()
	t.Cleanup(func() {
		listener.Close()
		p.pause()
		p.workers.Wait()
	})
	return p
}

func (p *mahjongOutageProxy) forward(client, server net.Conn) {
	defer p.workers.Done()
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = io.Copy(server, client)
		client.Close()
		server.Close()
	}()
	_, _ = io.Copy(client, server)
	client.Close()
	server.Close()
	<-done
	p.mu.Lock()
	delete(p.active, client)
	p.mu.Unlock()
}

func (p *mahjongOutageProxy) pause() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.paused = true
	for client, server := range p.active {
		client.Close()
		server.Close()
	}
	return len(p.active)
}

func (p *mahjongOutageProxy) resume() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.paused = false
}
