package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// This test owns both cmd/api processes. Only local, disposable PostgreSQL and
// Redis instances are supported, and their processes are left running.
func TestMahjongReleaseServiceRestart(t *testing.T) {
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
	restartEnv := []string{
		"HTTP_ADDR=" + addr,
		"POSTGRES_URL=" + postgresURL,
		"REDIS_ADDR=" + redisAddr,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"),
		"REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
	}
	first := launchRestartAPI(t, binary, endpoint, restartEnv)
	var users [4]restartGuest
	var lobby, board [4]*websocket.Conn
	for seat := range users {
		users[seat] = loadRestartGuest(t, endpoint, "")
		lobby[seat] = restartSocket(t, endpoint, users[seat])
		referenceSend(t, lobby[seat], map[string]any{"type": "mahjong_lobby_subscribe"})
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": false, "black_eight": false, "requires_kong_to_claim": true, "rob_kong": false}
	referenceSend(t, lobby[0], map[string]any{"type": "mahjong_lobby_command", "action": "create", "command_id": "restart-create",
		"rule_set_id": "guiyang", "rule_version": "2.0.0", "options": options})
	if ack := lobbyRead(t, lobby[0], "mahjong_lobby_result", nil); ack["ok"] != true {
		t.Fatal("custom room creation failed")
	}
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for seat := 1; seat < 4; seat++ {
		lobbyCommand(t, lobby[seat], "join", roomID, "", "", true)
	}
	for seat := range lobby {
		lobbyCommand(t, lobby[seat], "ready", roomID, "", "", true)
	}
	for seat := range board {
		board[seat] = joinRestartBoard(t, endpoint, users[seat], roomID, "", seat)
	}
	var initial [4]map[string]any
	seenTiles := map[any]bool{}
	matchID := ""
	for seat, conn := range board {
		state := lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "playing" })
		if seat == 0 {
			matchID, _ = state["match_id"].(string)
		}
		verifyRestartIdentity(t, state, users, roomID, matchID, seat, options)
		for _, value := range state["hand"].([]any) {
			id := value.(map[string]any)["id"]
			if seenTiles[id] {
				t.Fatal("private starting hands contain overlapping tile IDs")
			}
			seenTiles[id] = true
		}
		initial[seat] = state
	}
	if len(seenTiles) != 53 {
		t.Fatalf("initial private deal had %d unique tiles, want 53", len(seenTiles))
	}
	turn := int(initial[0]["turn"].(float64))
	tile := initial[turn]["hand"].([]any)[0].(map[string]any)["id"]
	command := restartAction(roomID, matchID, "restart-first-discard", "play", tile)
	referenceSend(t, board[turn], command)
	accepted := waitRestartAction(t, board[turn], "restart-first-discard")
	var committed [4]map[string]any
	for seat, conn := range board {
		committed[seat] = lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool {
			return restartHasDiscard(msg, turn, tile)
		})
	}
	first.stop(t)
	if err := board[0].SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	for {
		if _, _, err := board[0].ReadMessage(); err != nil {
			if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
				t.Fatal("the first API process stopped without closing its board socket")
			}
			break
		}
	}
	second := launchRestartAPI(t, binary, endpoint, restartEnv)
	if first.cmd.Process.Pid == second.cmd.Process.Pid {
		t.Fatal("expected a new cmd/api process")
	}
	var restored [4]map[string]any
	for seat, guest := range users {
		if account := loadRestartGuest(t, endpoint, guest.Token); account.ID != guest.ID {
			t.Fatalf("seat %d did not restore the original session identity", seat)
		}
		lobby[seat] = restartSocket(t, endpoint, guest)
		referenceSend(t, lobby[seat], map[string]any{"type": "mahjong_lobby_subscribe"})
		room := lobbyState(t, lobby[seat], "playing", 4, 4)
		if room["room_id"] != roomID || room["seat_index"] != float64(seat) {
			t.Fatalf("seat %d restored different lobby room or seat", seat)
		}
		board[seat] = joinRestartBoard(t, endpoint, guest, roomID, matchID, seat)
		restored[seat] = lobbyRead(t, board[seat], "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "playing" })
		verifyRestartIdentity(t, restored[seat], users, roomID, matchID, seat, options)
		compareRestartTable(t, committed[seat], restored[seat], seat)
	}
	referenceSend(t, board[turn], command)
	if replay := waitRestartAction(t, board[turn], "restart-first-discard"); !reflect.DeepEqual(accepted, replay) {
		t.Fatal("replayed discard did not return the original acknowledgement")
	}
	board[turn].Close()
	board[turn] = joinRestartBoard(t, endpoint, users[turn], roomID, matchID, turn)
	afterReplay := lobbyRead(t, board[turn], "mahjong_state", nil)
	compareRestartTable(t, committed[turn], afterReplay, turn)
	for seat, state := range restored {
		for _, entry := range state["options"].([]any) {
			option := entry.(map[string]any)
			kind, _ := option["type"].(string)
			if kind != "play" && kind != "pass" {
				continue
			}
			nextTile := option["tile_id"]
			if kind == "play" {
				nextTile = state["hand"].([]any)[0].(map[string]any)["id"]
			}
			referenceSend(t, board[seat], restartAction(roomID, matchID, "restart-continue", kind, nextTile))
			waitRestartAction(t, board[seat], "restart-continue")
			lobbyRead(t, board[seat], "mahjong_state", func(msg map[string]any) bool {
				return msg["epoch"].(float64) > state["epoch"].(float64)
			})
			t.Logf("MAHJONG_REAL_API_RESTART_OK first_pid=%d second_pid=%d room=%s match=%s seats=4 private_deal=53 replay_deduplicated=true next_action=%s",
				first.cmd.Process.Pid, second.cmd.Process.Pid, roomID, matchID, kind)
			return
		}
	}
	t.Fatal("no legal continuation after the restored discard")
}

type restartGuest struct {
	ID    string `json:"account_id"`
	Token string `json:"session_token"`
}

func loadRestartGuest(t *testing.T, endpoint, token string) restartGuest {
	t.Helper()
	method, route, status := http.MethodPost, "/api/v1/auth/guest", http.StatusCreated
	if token != "" {
		method, route, status = http.MethodGet, "/api/v1/auth/session", http.StatusOK
	}
	req, err := http.NewRequest(method, endpoint+route, nil)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	client := &http.Client{Timeout: 3 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(req)
	if err != nil {
		t.Fatalf("auth %s: %v", route, err)
	}
	defer response.Body.Close()
	var result restartGuest
	if response.StatusCode != status || json.NewDecoder(response.Body).Decode(&result) != nil || result.ID == "" || (token == "" && result.Token == "") {
		t.Fatalf("auth %s failed (HTTP %d)", route, response.StatusCode)
	}
	return result
}

func restartSocket(t *testing.T, endpoint string, guest restartGuest) *websocket.Conn {
	t.Helper()
	dialer := &websocket.Dialer{HandshakeTimeout: 3 * time.Second}
	conn, response, err := dialer.Dial("ws"+strings.TrimPrefix(endpoint, "http")+"/api/v1/mahjong/ws",
		http.Header{"Authorization": []string{"Bearer " + guest.Token}})
	if err != nil {
		if response != nil {
			response.Body.Close()
		}
		t.Fatalf("open authenticated Mahjong socket: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

func joinRestartBoard(t *testing.T, endpoint string, guest restartGuest, roomID, matchID string, seat int) *websocket.Conn {
	t.Helper()
	conn := restartSocket(t, endpoint, guest)
	join := map[string]any{"type": "mahjong_join", "room_id": roomID}
	if matchID != "" {
		join["match_id"] = matchID
	}
	referenceSend(t, conn, join)
	if result := lobbyRead(t, conn, "mahjong_joined", nil); result["your_seat"] != float64(seat) || result["room_id"] != roomID {
		t.Fatalf("seat %d did not join its original room/seat", seat)
	}
	return conn
}

func restartAction(roomID, matchID, commandID, action string, tile any) map[string]any {
	message := map[string]any{"type": "mahjong_action", "room_id": roomID, "match_id": matchID, "command_id": commandID, "action": action}
	if tile != nil {
		message["tile_id"] = tile
	}
	return message
}

func waitRestartAction(t *testing.T, conn *websocket.Conn, commandID string) map[string]any {
	t.Helper()
	ack := lobbyRead(t, conn, "mahjong_action_result", func(msg map[string]any) bool { return msg["command_id"] == commandID })
	if ack["ok"] != true {
		t.Fatalf("command %s rejected: %v", commandID, ack["message"])
	}
	return ack
}

func restartHasDiscard(state map[string]any, seat int, tile any) bool {
	for _, entry := range state["discards"].([]any) {
		discard := entry.(map[string]any)
		if discard["seat"] == float64(seat) && discard["tile"].(map[string]any)["id"] == tile {
			return true
		}
	}
	return false
}

func verifyRestartIdentity(t *testing.T, state map[string]any, guests [4]restartGuest, roomID, matchID string, seat int, options map[string]any) {
	t.Helper()
	rule, _ := state["rule"].(map[string]any)
	players, _ := state["players"].([]any)
	if matchID == "" || state["room_id"] != roomID || state["match_id"] != matchID || state["your_seat"] != float64(seat) ||
		state["rule_set_id"] != "guiyang" || state["rule_version"] != "2.0.0" || !reflect.DeepEqual(rule["options"], options) ||
		len(players) != 4 || state["wall"] != nil || state["hands"] != nil {
		t.Fatalf("seat %d received inconsistent table identity, rules or private projection", seat)
	}
	for index, guest := range guests {
		if players[index] != guest.ID {
			t.Fatalf("seat %d changed occupant after recovery", index)
		}
	}
}

func compareRestartTable(t *testing.T, want, got map[string]any, seat int) {
	t.Helper()
	for _, key := range []string{"room_id", "match_id", "your_seat", "rule", "hand", "hand_counts", "turn", "phase", "epoch", "remaining", "discards", "melds", "options", "scores"} {
		if !reflect.DeepEqual(want[key], got[key]) {
			t.Fatalf("seat %d changed %s across restart or replay", seat, key)
		}
	}
}

type restartTestAPI struct {
	cmd     *exec.Cmd
	done    chan error
	stopped bool
}

func launchRestartAPI(t *testing.T, binary, endpoint string, env []string) *restartTestAPI {
	t.Helper()
	cmd := exec.Command(binary)
	cmd.Env = append(os.Environ(), env...)
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	api := &restartTestAPI{cmd: cmd, done: make(chan error, 1)}
	go func() { api.done <- cmd.Wait(); close(api.done) }()
	t.Cleanup(func() { api.stop(t) })
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	client := &http.Client{Timeout: time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	ticker := time.NewTicker(25 * time.Millisecond)
	defer ticker.Stop()
	for {
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint+"/health", nil)
		if response, err := client.Do(req); err == nil {
			var health map[string]string
			err := json.NewDecoder(response.Body).Decode(&health)
			response.Body.Close()
			if err == nil && response.StatusCode == http.StatusOK && health["service"] == "ok" && health["postgres"] == "ok" && health["redis"] == "ok" {
				return api
			}
		}
		select {
		case <-ctx.Done():
			t.Fatal("owned cmd/api did not become healthy with PostgreSQL and Redis")
		case err := <-api.done:
			t.Fatalf("owned cmd/api exited before its health check passed: %v", err)
		case <-ticker.C:
		}
	}
}

func (api *restartTestAPI) stop(t *testing.T) {
	t.Helper()
	if api.stopped {
		return
	}
	if err := api.cmd.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
		t.Errorf("stop owned cmd/api: %v", err)
	}
	select {
	case <-api.done:
		api.stopped = true
	case <-time.After(5 * time.Second):
		t.Error("owned cmd/api did not stop after kill")
	}
}

func restartLoopback(address string) bool {
	host, port, err := net.SplitHostPort(address)
	return err == nil && port != "" && net.ParseIP(host).IsLoopback()
}
