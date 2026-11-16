package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/gorilla/websocket"
)

type fixtureAccounts struct {
	mu       sync.Mutex
	sessions map[string]account.Session
	created  int
}

func (a *fixtureAccounts) issue(id string, expiresAt time.Time) (account.GuestLogin, error) {
	var bytes [32]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return account.GuestLogin{}, err
	}
	login := account.GuestLogin{Session: account.Session{GuestAccount: domain.GuestAccount{
		AccountID: id, DisplayName: "牌友 " + id, CreatedAt: time.Now().UTC(),
	}, ExpiresAt: expiresAt}, Token: base64.RawURLEncoding.EncodeToString(bytes[:])}
	if a.sessions == nil {
		a.sessions = make(map[string]account.Session)
	}
	a.sessions[login.Token] = login.Session
	return login, nil
}

func (a *fixtureAccounts) CreateGuest(_ context.Context) (account.GuestLogin, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.created++
	return a.issue(fmt.Sprintf("fixture-%d", a.created), time.Now().Add(time.Hour))
}

func (a *fixtureAccounts) Session(_ context.Context, token string) (account.Session, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	session, ok := a.sessions[token]
	if !ok {
		return account.Session{}, account.ErrInvalidSession
	}
	return session, nil
}

func (a *fixtureAccounts) count() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.created
}

func (a *fixtureAccounts) header(t *testing.T, id string) http.Header {
	t.Helper()
	a.mu.Lock()
	defer a.mu.Unlock()
	for token, session := range a.sessions {
		if session.AccountID == id {
			return http.Header{"Authorization": {"Bearer " + token}}
		}
	}
	login, err := a.issue(id, time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	return http.Header{"Authorization": {"Bearer " + login.Token}}
}

func mahjongAccountFixture(accounts *fixtureAccounts) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.Handle("/", newServer(config.Config{}, nil, nil, accounts))
	return mux
}

func TestMahjongSessionRequiredAtPublicEntryPoints(t *testing.T) {
	handler := New(config.Config{}, nil, nil)
	for _, tc := range []struct {
		name, method, path, body string
	}{
		{"identity lookup", http.MethodGet, "/api/v1/auth/session", ""},
		{"plate connection", http.MethodGet, "/api/v1/mahjong/ws", ""},
		{"compatibility matchmaking", http.MethodPost, "/api/v1/matchmaking/quick", `{"account_id":"test-account","product_id":"xbd_mahjong","game_id":"mahjong","rule_set_id":"guiyang","rule_version":"2.0.0"}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
			result := httptest.NewRecorder()
			handler.ServeHTTP(result, req)
			if result.Code != http.StatusUnauthorized {
				t.Fatalf("unverified request got status %d; want 401", result.Code)
			}
		})
	}
}

func TestMahjongSessionBindsLobbyAndBoard(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	owner := lobbySocket(t, server, accounts, "owner")
	lobbyCommand(t, owner, "training", "", "guiyang", "2.0.0", true)
	state := lobbyState(t, owner, "playing", 4, 4)
	roomID := state["room_id"].(string)
	endpoint := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/v1/mahjong/ws"
	peer, _, err := websocket.DefaultDialer.Dial(endpoint, accounts.header(t, "other"))
	if err != nil {
		t.Fatal(err)
	}
	defer peer.Close()
	readUntilType(t, peer, "connected", nil)
	referenceSend(t, peer, map[string]any{"type": "mahjong_lobby_subscribe", "client_id": "owner"})
	readUntilType(t, peer, "mahjong_error", nil)
	referenceSend(t, peer, map[string]any{"type": "mahjong_join", "client_id": "owner", "room_id": roomID})
	readUntilType(t, peer, "mahjong_error", nil)
	referenceSend(t, peer, map[string]any{"type": "mahjong_join", "room_id": roomID})
	readUntilType(t, peer, "mahjong_error", nil)
	referenceSend(t, owner, map[string]any{"type": "mahjong_join", "room_id": roomID})
	lobbyRead(t, owner, "mahjong_joined", nil)
	lobbyRead(t, owner, "mahjong_state", nil)

	legacy := dialTestWebSocket(t, "ws"+strings.TrimPrefix(server.URL, "http")+"/ws")
	defer legacy.Close()
	readUntilType(t, legacy, "connected", nil)
	referenceSend(t, legacy, map[string]any{"type": "mahjong_join", "client_id": "owner", "room_id": roomID})
	readUntilType(t, legacy, "mahjong_error", nil)

	for _, path := range []string{"ready", "cancel"} {
		req, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/matchmaking/"+path, strings.NewReader(fmt.Sprintf(`{"account_id":"owner","room_id":%q}`, roomID)))
		if err != nil {
			t.Fatal(err)
		}
		req.Header = accounts.header(t, "other")
		resp, err := server.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("account mismatch in %s: HTTP %d", path, resp.StatusCode)
		}
	}
	lobbyCommand(t, owner, "leave", roomID, "", "", true)
}

func TestGuestSessionRestoresIdentityAndExpires(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	response, err := server.Client().Post(server.URL+"/api/v1/auth/guest", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	var guest account.GuestLogin
	err = json.NewDecoder(response.Body).Decode(&guest)
	response.Body.Close()
	if err != nil || response.StatusCode != http.StatusCreated || len(guest.Token) != 43 || response.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("guest login did not issue a non-cacheable session")
	}
	restore := func(want int) {
		t.Helper()
		req, err := http.NewRequest(http.MethodGet, server.URL+"/api/v1/auth/session", nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer "+guest.Token)
		response, err := server.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != want {
			t.Fatalf("restore status %d, want %d", response.StatusCode, want)
		}
		if want == http.StatusOK {
			var restored account.GuestLogin
			if json.NewDecoder(response.Body).Decode(&restored) != nil || restored.AccountID != guest.AccountID || restored.Token != "" || accounts.count() != 1 {
				t.Fatal("restore did not keep identity or returned a credential")
			}
		}
	}
	restore(http.StatusOK)
	accounts.mu.Lock()
	short := guest.Session
	short.ExpiresAt = time.Now().Add(200 * time.Millisecond)
	accounts.sessions[guest.Token] = short
	accounts.mu.Unlock()
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/mahjong/ws", http.Header{"Authorization": {"Bearer " + guest.Token}})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	readUntilType(t, conn, "connected", nil)
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, _, err = conn.ReadMessage()
	closeErr, ok := err.(*websocket.CloseError)
	if !ok || closeErr.Code != websocket.ClosePolicyViolation || closeErr.Text != "session_expired" {
		t.Fatalf("session expiry did not terminate live connection: %v", err)
	}
	restore(http.StatusUnauthorized)
}
