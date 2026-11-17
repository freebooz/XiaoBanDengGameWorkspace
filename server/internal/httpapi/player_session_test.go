package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/gorilla/websocket"
)

func TestPlayerRoomCommandsRequireMatchingSession(t *testing.T) {
	accounts := &fixtureAccounts{}
	handler := newServer(config.Config{}, nil, nil, accounts)
	for _, tc := range []struct {
		name string
		path string
		body string
	}{
		{"quick", "/api/v1/matchmaking/quick", `{"account_id":"another-player","product_id":"xbd_chinese_chess","game_id":"chinese_chess","rule_set_id":"standard","rule_version":"1.0.0"}`},
		{"ready", "/api/v1/matchmaking/ready", `{"account_id":"another-player","room_id":"1234"}`},
		{"cancel", "/api/v1/matchmaking/cancel", `{"account_id":"another-player"}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(tc.body))
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != http.StatusUnauthorized {
				t.Errorf("missing session got status %d; want 401", res.Code)
			}
			req = httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(tc.body))
			req.Header = accounts.header(t, "current-player")
			res = httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != http.StatusForbidden {
				t.Errorf("unrelated session got status %d; want 403", res.Code)
			}
			padded := strings.Replace(tc.body, "another-player", " current-player ", 1)
			req = httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(padded))
			req.Header = accounts.header(t, "current-player")
			res = httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != http.StatusForbidden {
				t.Errorf("noncanonical account ID got status %d; want 403", res.Code)
			}
		})
	}
}

func TestSharedWebsocketBindsPlayerSession(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(newServer(config.Config{}, nil, nil, accounts))
	defer server.Close()
	endpoint := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"
	if conn, response, err := websocket.DefaultDialer.Dial(endpoint, nil); err == nil {
		conn.Close()
		t.Error("shared websocket accepted an unauthenticated upgrade")
	} else if response == nil || response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("missing session upgrade returned %v; want 401", response)
	}
	conn, _, err := websocket.DefaultDialer.Dial(endpoint, accounts.header(t, "current-player"))
	if err != nil {
		t.Fatal("authenticated upgrade failed:", err)
	}
	defer conn.Close()
	readUntilType(t, conn, "connected", nil)
	for _, game := range []string{"chess", "landlord", "guandan"} {
		mustWriteJSON(t, conn, map[string]any{"type": game + "_join", "room_id": "1234", "client_id": "another-player"})
		response := readUntilType(t, conn, game+"_error", nil)
		if response["code"] != "account_mismatch" {
			t.Errorf("%s join did not reject the unrelated account at the session boundary", game)
		}
	}
}

func TestChessSocketRejectsWrongProductAndUnreadyRoom(t *testing.T) {
	for _, tc := range []struct {
		name string
		matchmaking.QuickMatchRequest
		capacity int
		ready    bool
	}{
		{"unready", matchmaking.QuickMatchRequest{ProductID: "xbd_chinese_chess", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0"}, 2, false},
		{"other product", matchmaking.QuickMatchRequest{ProductID: "xbd_landlord", GameID: "landlord", RuleSetID: "classic_three_player", RuleVersion: "2.0.0"}, 3, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			accounts := &fixtureAccounts{}
			app := buildServer(config.Config{}, nil, nil, accounts)
			players := []string{"test-first", "test-second", "test-third"}[:tc.capacity]
			var roomID string
			for _, player := range players {
				input := tc.QuickMatchRequest
				input.AccountID = player
				matched, err := app.matchmaking.QuickMatch(input)
				if err != nil {
					t.Fatal(err)
				}
				roomID = matched.RoomID
			}
			if tc.ready {
				for _, player := range players {
					if _, err := app.matchmaking.Ready(matchmaking.RoomReadyRequest{RoomID: roomID, AccountID: player}); err != nil {
						t.Fatal(err)
					}
				}
			}
			server := httptest.NewServer(app.routes())
			defer server.Close()
			endpoint := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"
			conn, _, err := websocket.DefaultDialer.Dial(endpoint, accounts.header(t, players[0]))
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			readUntilType(t, conn, "connected", nil)
			mustWriteJSON(t, conn, map[string]any{"type": "chess_join", "room_id": roomID, "client_id": players[0]})
			_ = conn.SetReadDeadline(time.Now().Add(time.Second))
			var response map[string]any
			if err := conn.ReadJSON(&response); err != nil {
				t.Fatal(err)
			}
			if response["type"] != "chess_error" || app.chess.findRoom(roomID) != nil {
				t.Fatal("only ready chess matches should allocate a chess board")
			}
		})
	}
}

func TestRoomCreationRequiresSession(t *testing.T) {
	handler := newServer(config.Config{}, nil, nil, &fixtureAccounts{})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/rooms", strings.NewReader(
		`{"product_id":"xbd_chinese_chess","game_id":"chinese_chess","rule_set_id":"standard","rule_version":"1.0.0"}`))
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Errorf("missing session got status %d; want 401", res.Code)
	}
}
