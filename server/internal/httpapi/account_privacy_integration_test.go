package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongmoderation"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

func TestMahjongGuestPrivacyClosesLiveSessions(t *testing.T) {
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
	logoutGuest := loadRestartGuest(t, endpoint, "")
	deleteGuest := loadRestartGuest(t, endpoint, "")
	untouchedGuest := loadRestartGuest(t, endpoint, "")
	open := func(guest restartGuest) *websocket.Conn {
		t.Helper()
		socket := restartSocket(t, endpoint, guest)
		lobbyRead(t, socket, "connected", nil)
		return socket
	}
	logoutSockets := []*websocket.Conn{open(logoutGuest), open(logoutGuest)}
	deleteSockets := []*websocket.Conn{open(deleteGuest), open(deleteGuest)}
	untouched := open(untouchedGuest)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, postgresURL)
	if err != nil {
		t.Fatal("could not connect to disposable privacy database")
	}
	defer db.Close()
	report := mahjongmoderation.Report{MatchID: uuid.NewString(), RoomID: "4321", ReporterAccountID: deleteGuest.ID,
		TargetAccountID: untouchedGuest.ID, ReporterSeat: 0, TargetSeat: 1, Reason: "spam"}
	if err := mahjongmoderation.NewService(db).Save(ctx, report); err != nil {
		t.Fatal("could not prepare account-linked audit fixture")
	}

	client := &http.Client{Timeout: 4 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	request := func(method, route, token string, wantStatus int, result any) {
		t.Helper()
		req, err := http.NewRequest(method, endpoint+route, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
		response, err := client.Do(req)
		if err != nil {
			t.Fatalf("privacy request %s failed: %v", route, err)
		}
		defer response.Body.Close()
		if response.StatusCode != wantStatus {
			t.Fatalf("privacy request %s returned %d, want %d", route, response.StatusCode, wantStatus)
		}
		if result != nil && json.NewDecoder(response.Body).Decode(result) != nil {
			t.Fatalf("privacy request %s did not return a receipt", route)
		}
	}
	verifyRevoked := func(token string, sockets []*websocket.Conn) {
		t.Helper()
		for _, socket := range sockets {
			_ = socket.SetReadDeadline(time.Now().Add(3 * time.Second))
			_, _, err := socket.ReadMessage()
			var closeError *websocket.CloseError
			if !errors.As(err, &closeError) || closeError.Code != websocket.ClosePolicyViolation || closeError.Text != "session_expired" {
				t.Fatalf("expected revocation close on existing socket, got %v", err)
			}
		}
		request(http.MethodGet, "/api/v1/auth/session", token, http.StatusUnauthorized, nil)
		socket, response, err := (&websocket.Dialer{HandshakeTimeout: 3 * time.Second}).Dial("ws"+strings.TrimPrefix(endpoint, "http")+"/api/v1/mahjong/ws",
			http.Header{"Authorization": {"Bearer " + token}})
		if socket != nil {
			socket.Close()
		}
		if response != nil {
			response.Body.Close()
		}
		if err == nil || response == nil || response.StatusCode != http.StatusUnauthorized {
			t.Fatal("revoked session could open a new WebSocket")
		}
	}

	request(http.MethodPost, "/api/v1/auth/logout", logoutGuest.Token, http.StatusNoContent, nil)
	verifyRevoked(logoutGuest.Token, logoutSockets)
	referenceSend(t, deleteSockets[0], map[string]any{"type": "mahjong_lobby_subscribe"})
	lobbyState(t, deleteSockets[0], "idle", 0, 0)
	var receipt account.DeletionReceipt
	request(http.MethodPost, "/api/v1/auth/delete-request", deleteGuest.Token, http.StatusAccepted, &receipt)
	if _, err := uuid.Parse(receipt.RequestID); err != nil || receipt.AccountID != deleteGuest.ID || receipt.Status != "pending_retention_review" || receipt.RequestedAt.IsZero() {
		t.Fatal("delete request did not return the account's pending retention-review receipt")
	}
	verifyRevoked(deleteGuest.Token, deleteSockets)
	request(http.MethodGet, "/api/v1/auth/session", untouchedGuest.Token, http.StatusOK, nil)
	referenceSend(t, untouched, map[string]any{"type": "mahjong_lobby_subscribe"})
	lobbyState(t, untouched, "idle", 0, 0)
	var retained int
	if err := db.QueryRow(ctx, `SELECT COUNT(*) FROM mahjong_table_reports WHERE match_id=$1 AND reporter_account_id=$2::uuid`, report.MatchID, deleteGuest.ID).Scan(&retained); err != nil || retained != 1 {
		t.Fatalf("account-linked moderation evidence should be retained: rows=%d err=%v", retained, err)
	}
	t.Log("real API 204 logout and 202 delete closed already-upgraded sockets, rejected reauth, retained audit, and preserved another guest")
}
