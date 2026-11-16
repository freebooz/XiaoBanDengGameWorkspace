package httpapi

import (
	"context"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/gorilla/websocket"
)

func TestMahjongModerationRealFourGuests(t *testing.T) {
	binary := os.Getenv("XBD_MAHJONG_RESTART_API")
	if binary == "" {
		t.Skip("set XBD_MAHJONG_RESTART_API and disposable loopback PostgreSQL/Redis endpoints")
	}
	if info, err := os.Stat(binary); !filepath.IsAbs(binary) || err != nil || !info.Mode().IsRegular() {
		t.Fatal("XBD_MAHJONG_RESTART_API must point to compiled cmd/api")
	}
	postgresURL := os.Getenv("XBD_MAHJONG_TEST_POSTGRES_URL")
	redisAddr := os.Getenv("XBD_MAHJONG_TEST_REDIS_ADDR")
	parsed, err := url.Parse(postgresURL)
	if err != nil || (parsed.Scheme != "postgres" && parsed.Scheme != "postgresql") || !restartLoopback(parsed.Host) || parsed.RawQuery != "sslmode=disable" || len(parsed.Path) < 2 || !restartLoopback(redisAddr) {
		t.Fatal("set disposable PostgreSQL and Redis endpoints bound to numeric loopback")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close()
	endpoint := "http://" + addr
	launchRestartAPI(t, binary, endpoint, []string{
		"HTTP_ADDR=" + addr, "POSTGRES_URL=" + postgresURL, "REDIS_ADDR=" + redisAddr,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"), "REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
	})
	conn, response, err := (&websocket.Dialer{HandshakeTimeout: 3 * time.Second}).Dial("ws"+strings.TrimPrefix(endpoint, "http")+"/api/v1/mahjong/ws", nil)
	if conn != nil {
		conn.Close()
	}
	if response != nil {
		response.Body.Close()
	}
	if err == nil || response == nil || response.StatusCode != http.StatusUnauthorized {
		t.Fatal("anonymous WebSocket was not rejected before upgrade")
	}

	var guests [4]restartGuest
	var lobby, board [4]*websocket.Conn
	for seat := range guests {
		guests[seat] = loadRestartGuest(t, endpoint, "")
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guests[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	lobbyCommand(t, lobby[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for seat := 1; seat < 4; seat++ {
		lobbyCommand(t, lobby[seat], "join", roomID, "", "", true)
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	for seat, guest := range guests {
		board[seat] = joinRestartBoard(t, endpoint, guest, roomID, "", seat)
	}
	var matchID string
	for seat, conn := range board {
		state := lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "playing" })
		if seat == 0 {
			matchID, _ = state["match_id"].(string)
		}
		if matchID == "" || state["match_id"] != matchID || state["your_seat"] != float64(seat) {
			t.Fatal("four guests did not start the same authoritative table")
		}
	}

	submit := func(id, reason string, target int, wantOK bool) {
		t.Helper()
		referenceSend(t, board[0], map[string]any{
			"type": "mahjong_report", "command_id": id, "match_id": matchID, "target_seat": target, "reason": reason,
			"reporter_account_id": guests[2].ID, "target_account_id": guests[3].ID, "room_id": "bogus", "text": "must not be retained",
		})
		ack := mahjongReferenceRead(t, board[0], "mahjong_report_result")
		if ack["command_id"] != id || ack["ok"] != wantOK {
			t.Fatalf("unexpected report acknowledgment for %s", id)
		}
	}
	submit("self", "other", 0, false)
	submit("report", "voice_abuse", 1, true)
	submit("retry", "spam", 1, true)

	// A later public social message is an ordered marker on each board socket.
	// The strict reader fails if any unsolicited report frame preceded it.
	referenceSend(t, board[0], map[string]any{"type": "mahjong_social", "action": "chat", "quick_chat": "hello", "message_id": "audit-barrier", "match_id": matchID})
	for seat, conn := range board {
		if marker := mahjongReferenceRead(t, conn, "mahjong_social"); marker["message_id"] != "audit-barrier" {
			t.Fatalf("seat %d did not receive the ordered marker", seat)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, postgresURL)
	if err != nil {
		t.Fatal("could not connect to disposable report audit database")
	}
	defer db.Close()
	rows, err := db.Query(ctx, `SELECT room_id,reporter_account_id::text,target_account_id::text,reporter_seat,target_seat,reason,created_at
		FROM mahjong_table_reports WHERE match_id=$1`, matchID)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	if !rows.Next() {
		t.Fatalf("accepted live report has no durable audit row: %v", rows.Err())
	}
	var savedRoom, reporter, target, reason string
	var reporterSeat, targetSeat int
	var createdAt time.Time
	if err := rows.Scan(&savedRoom, &reporter, &target, &reporterSeat, &targetSeat, &reason, &createdAt); err != nil {
		t.Fatal(err)
	}
	if savedRoom != roomID || reporter != guests[0].ID || target != guests[1].ID || reporterSeat != 0 || targetSeat != 1 || reason != "voice_abuse" || createdAt.IsZero() {
		t.Fatal("audit did not preserve first reason and authenticated seat identities")
	}
	if rows.Next() || rows.Err() != nil {
		t.Fatalf("retry or denied report created another audit row: %v", rows.Err())
	}
	t.Log("four real guests: anonymous and self denied; accepted report + retry; peer sockets quiet; one authoritative PostgreSQL audit row")
}
