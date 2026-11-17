package httpapi

import (
	"bytes"
	"context"
	"errors"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestMahjongSingleWriterRejectsOverlapAndResumesLiveTable(t *testing.T) {
	if os.Getenv("XBD_MAHJONG_TEST_WRITER_SWITCH") != "1" {
		t.Skip("set XBD_MAHJONG_TEST_WRITER_SWITCH=1 and disposable restart API/DB endpoints")
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
	// Allocate simultaneous listeners first, ensuring that B cannot accidentally
	// use A's HTTP port and appear to lose a database lock it acquired.
	listeners := [2]net.Listener{}
	var addresses [2]string
	for i := range listeners {
		listeners[i], err = net.Listen("tcp4", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { listeners[i].Close() })
		addresses[i] = listeners[i].Addr().String()
	}
	for _, listener := range listeners {
		listener.Close()
	}
	common := []string{
		"POSTGRES_URL=" + postgres.String(), "REDIS_ADDR=" + redis,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"), "REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
		"XBD_MAHJONG_SINGLE_WRITER=1",
	}
	firstEnv := append(append([]string{}, common...), "HTTP_ADDR="+addresses[0])
	secondEnv := append(append([]string{}, common...), "HTTP_ADDR="+addresses[1])
	firstEndpoint, secondEndpoint := "http://"+addresses[0], "http://"+addresses[1]
	first := launchRestartAPI(t, binary, firstEndpoint, firstEnv)

	var guests [4]restartGuest
	var lobby [4]*websocket.Conn
	for seat := range guests {
		guests[seat] = loadRestartGuest(t, firstEndpoint, "")
		lobby[seat] = subscribeFriendRestartLobby(t, firstEndpoint, guests[seat])
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
	board, states, matchID := startFriendRestartRound(t, firstEndpoint, guests, roomID, "", options)
	turn := int(states[0]["turn"].(float64))
	tile := states[turn]["hand"].([]any)[0].(map[string]any)["id"]
	const discardID = "writer-switch-discard"
	referenceSend(t, board[turn], restartAction(roomID, matchID, discardID, "play", tile))
	waitRestartAction(t, board[turn], discardID)
	for seat, conn := range board {
		states[seat] = lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return restartHasDiscard(msg, turn, tile) })
	}
	rejectedPID := assertMahjongWriterRejectsOverlap(t, binary, addresses[1], secondEnv)
	for seat, conn := range board {
		referenceSend(t, conn, map[string]any{"type": "mahjong_join", "room_id": roomID, "match_id": matchID})
		lobbyRead(t, conn, "mahjong_joined", nil)
		compareRestartTable(t, states[seat], lobbyRead(t, conn, "mahjong_state", nil), seat)
	}
	stopMode := stopOwnedWriter(t, first)
	if err := board[0].SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	for {
		if _, _, err := board[0].ReadMessage(); err != nil {
			if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
				t.Fatal("old writer exited without closing its websocket")
			}
			break
		}
	}

	second := launchRestartAPI(t, binary, secondEndpoint, secondEnv)
	if second.cmd.Process.Pid == first.cmd.Process.Pid || second.cmd.Process.Pid == rejectedPID {
		t.Fatal("writer switch did not start a distinct replacement process")
	}
	var restored [4]map[string]any
	for seat, guest := range guests {
		if loadRestartGuest(t, secondEndpoint, guest.Token).ID != guest.ID {
			t.Fatalf("replacement writer changed guest identity at seat %d", seat)
		}
		lobby[seat] = subscribeFriendRestartLobby(t, secondEndpoint, guest)
		snapshot := lobbyState(t, lobby[seat], "playing", 4, 4)
		if snapshot["room_id"] != roomID || snapshot["seat_index"] != float64(seat) {
			t.Fatalf("replacement writer changed room assignment at seat %d", seat)
		}
		board[seat] = joinRestartBoard(t, secondEndpoint, guest, roomID, matchID, seat)
		restored[seat] = lobbyRead(t, board[seat], "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "playing" })
		verifyRestartIdentity(t, restored[seat], guests, roomID, matchID, seat, options)
		compareRestartTable(t, states[seat], restored[seat], seat)
	}
	seat, kind, nextTile := chooseFriendRestartAction(restored)
	if seat < 0 {
		t.Fatal("replacement writer did not restore a live decision")
	}
	const nextID = "replacement-writer-action"
	referenceSend(t, board[seat], restartAction(roomID, matchID, nextID, kind, nextTile))
	waitRestartAction(t, board[seat], nextID)
	lobbyRead(t, board[seat], "mahjong_state", func(msg map[string]any) bool { return msg["epoch"].(float64) > restored[seat]["epoch"].(float64) })
	t.Logf("MAHJONG_SINGLE_WRITER_SWITCH_OK first_pid=%d rejected_pid=%d next_pid=%d stop=%s room=%s match=%s seats=4 next_action=%s",
		first.cmd.Process.Pid, rejectedPID, second.cmd.Process.Pid, stopMode, roomID, matchID, kind)
}

func assertMahjongWriterRejectsOverlap(t *testing.T, binary, address string, env []string) int {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, binary)
	cmd.Env = append(os.Environ(), env...)
	var diagnostic bytes.Buffer
	cmd.Stdout, cmd.Stderr = &diagnostic, &diagnostic
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() { result <- cmd.Wait(); close(result) }()
	t.Cleanup(func() { _ = cmd.Process.Kill(); <-result })
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		if conn, err := net.DialTimeout("tcp4", address, 50*time.Millisecond); err == nil {
			conn.Close()
			t.Fatal("overlapping writer began listening with the same database")
		}
		select {
		case err := <-result:
			var exit *exec.ExitError
			if ctx.Err() != nil || !errors.As(err, &exit) || exit.ExitCode() <= 0 || !bytes.Contains(diagnostic.Bytes(), []byte("已有麻将服务持有数据库写入锁")) {
				t.Fatal("overlapping writer was not refused by API startup")
			}
			return cmd.Process.Pid
		case <-ctx.Done():
			t.Fatal("overlapping writer did not exit after startup refusal")
		case <-ticker.C:
		}
	}
}

func stopOwnedWriter(t *testing.T, api *restartTestAPI) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		api.stop(t)
		return "kill"
	}
	if err := api.cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-api.done:
		api.stopped = true
		if err != nil {
			t.Fatalf("owned API did not exit gracefully: %v", err)
		}
		return "sigterm"
	case <-time.After(8 * time.Second):
		t.Fatal("owned API did not exit after SIGTERM")
		return ""
	}
}
