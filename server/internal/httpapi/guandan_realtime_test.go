package httpapi

import (
	"fmt"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestGuandanRealtimeFourSeatsPrivacyReconnectAndLeave(t *testing.T) {
	for _, joinedCount := range []int{1, 4} {
		t.Run(fmt.Sprintf("connected_%d", joinedCount), func(t *testing.T) {
			matches := matchmaking.NewManager(room.NewManager())
			base := matchmaking.QuickMatchRequest{ProductID: "xbd_guandan", GameID: "guandan", RuleSetID: "classic_partnership", RuleVersion: "1.0.0"}
			roomID := ""
			for seat := 0; seat < 4; seat++ {
				base.AccountID = fmt.Sprintf("gd-%d", seat)
				result, err := matches.QuickMatch(base)
				if err != nil {
					t.Fatal(err)
				}
				roomID = result.RoomID
				if result.Capacity != 4 {
					t.Fatal("wrong capacity")
				}
			}
			for seat := 0; seat < 4; seat++ {
				_, err := matches.Ready(matchmaking.RoomReadyRequest{AccountID: fmt.Sprintf("gd-%d", seat), RoomID: roomID})
				if err != nil {
					t.Fatal(err)
				}
			}
			hub := newGuandanHub(matches)
			upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, err := upgrader.Upgrade(w, r, nil)
				if err != nil {
					return
				}
				defer conn.Close()
				client := newGuandanClient(newChessClient(conn))
				defer hub.disconnect(client)
				for {
					var message map[string]any
					if conn.ReadJSON(&message) != nil {
						return
					}
					hub.handle(client, message)
				}
			}))
			defer server.Close()
			url := "ws" + strings.TrimPrefix(server.URL, "http")
			connections := make([]*websocket.Conn, 4)
			join := func(seat int) *websocket.Conn {
				conn, _, err := websocket.DefaultDialer.Dial(url, nil)
				if err != nil {
					t.Fatal(err)
				}
				_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
				if err := conn.WriteJSON(map[string]any{"type": "guandan_join", "room_id": roomID, "client_id": fmt.Sprintf("gd-%d", seat)}); err != nil {
					t.Fatal(err)
				}
				var joined, state map[string]any
				if err := conn.ReadJSON(&joined); err != nil {
					t.Fatal(err)
				}
				if err := conn.ReadJSON(&state); err != nil {
					t.Fatal(err)
				}
				if joined["type"] != "guandan_joined" || len(state["hand"].([]any)) != 27 {
					t.Fatalf("bad initial state %+v", state)
				}
				if _, ok := state["hands_revealed"]; ok {
					t.Fatal("private hands leaked")
				}
				return conn
			}
			for seat := 0; seat < joinedCount; seat++ {
				connections[seat] = join(seat)
				defer connections[seat].Close()
			}
			replacement := join(joinedCount - 1)
			defer replacement.Close()
			if err := replacement.WriteJSON(map[string]any{"type": "guandan_action", "action": "leave"}); err != nil {
				t.Fatal(err)
			}
			for {
				var finished map[string]any
				if err := replacement.ReadJSON(&finished); err != nil {
					t.Fatal(err)
				}
				if finished["phase"] == "finished" {
					break
				}
			}
			hub.mu.Lock()
			activeRoom := hub.rooms[roomID]
			hub.mu.Unlock()
			activeRoom.mu.Lock()
			activeRoom.mu.Unlock()
			if _, ok := matches.GuandanPlayersFor(roomID); ok {
				t.Fatal("room was not released")
			}
		})
	}
}
