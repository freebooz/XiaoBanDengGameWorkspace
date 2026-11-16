package httpapi

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
)

func TestMahjongRealtimeJoinsFourSeatsAndKeepsHandsPrivate(t *testing.T) {
	matches := matchmaking.NewManager(room.NewManager())
	base := matchmaking.QuickMatchRequest{ProductID: "xbd_mahjong", GameID: "mahjong", RuleSetID: "guiyang", RuleVersion: "2.0.0"}
	roomID := ""
	for seat := 0; seat < 4; seat++ {
		base.AccountID = fmt.Sprintf("mahjong-socket-%d", seat)
		matched, err := matches.QuickMatch(base)
		if err != nil {
			t.Fatal(err)
		}
		roomID = matched.RoomID
	}
	for seat := 0; seat < 4; seat++ {
		if _, err := matches.Ready(matchmaking.RoomReadyRequest{AccountID: fmt.Sprintf("mahjong-socket-%d", seat), RoomID: roomID}); err != nil {
			t.Fatal(err)
		}
	}
	hub := newMahjongHub(matches)
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		client := newMahjongClient(newChessClient(conn))
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
	for seat := 0; seat < 4; seat++ {
		conn, _, err := websocket.DefaultDialer.Dial(url, nil)
		if err != nil {
			t.Fatal(err)
		}
		connections[seat] = conn
		_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
		defer conn.Close()
		if err := conn.WriteJSON(map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": fmt.Sprintf("mahjong-socket-%d", seat)}); err != nil {
			t.Fatal(err)
		}
		var joined map[string]any
		if err := conn.ReadJSON(&joined); err != nil {
			t.Fatal(err)
		}
		if joined["type"] != "mahjong_joined" || int(joined["your_seat"].(float64)) != seat {
			t.Fatalf("加入座位错误: %+v", joined)
		}
		var state map[string]any
		if err := conn.ReadJSON(&state); err != nil {
			t.Fatal(err)
		}
		want := 0
		if seat == 3 {
			want = 13
		}
		if state["type"] != "mahjong_state" || len(state["hand"].([]any)) != want {
			t.Fatalf("首个快照错误: %+v", state)
		}
		if _, hasWall := state["wall"]; hasWall {
			t.Fatal("不能公开牌墙")
		}
	}
	dealt := lobbyRead(t, connections[2], "mahjong_state", func(message map[string]any) bool { return message["status"] == "playing" })
	originalSeatTwoHand := dealt["hand"].([]any)
	if len(originalSeatTwoHand) != 13 {
		t.Fatalf("deferred deal must contain 13 tiles for seat two: %v", dealt)
	}
	before := hub.rooms[roomID].game.NextWall
	reconnected, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer reconnected.Close()
	_ = reconnected.SetReadDeadline(time.Now().Add(3 * time.Second))
	if err := reconnected.WriteJSON(map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": "mahjong-socket-2"}); err != nil {
		t.Fatal(err)
	}
	var joined, state map[string]any
	if err := reconnected.ReadJSON(&joined); err != nil {
		t.Fatal(err)
	}
	if err := reconnected.ReadJSON(&state); err != nil {
		t.Fatal(err)
	}
	if int(joined["your_seat"].(float64)) != 2 || !reflect.DeepEqual(state["hand"], originalSeatTwoHand) || hub.rooms[roomID].game.NextWall != before {
		t.Fatalf("重连必须保留原座位、手牌和牌墙位置: joined=%+v state=%+v", joined, state)
	}
	for {
		if _, _, err = connections[2].ReadMessage(); err != nil {
			break
		}
	}
	closeErr, ok := err.(*websocket.CloseError)
	if !ok || closeErr.Code != websocket.ClosePolicyViolation || closeErr.Text != "seat_replaced" {
		t.Fatalf("old seat needs a terminal close reason instead of retrying: %v", err)
	}
}
