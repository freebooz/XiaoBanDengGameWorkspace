package httpapi

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
)

func TestLandlordRealtimeThreeSeatsAndPrivateCards(t *testing.T) {
	matches := matchmaking.NewManager(room.NewManager())
	base := matchmaking.QuickMatchRequest{ProductID: "xbd_landlord", GameID: "landlord", RuleSetID: "classic_three_player", RuleVersion: "1.0.0"}
	roomID := ""
	for seat := 0; seat < 3; seat++ {
		base.AccountID = fmt.Sprintf("p%d", seat)
		result, err := matches.QuickMatch(base)
		if err != nil {
			t.Fatal(err)
		}
		roomID = result.RoomID
	}
	for seat := 0; seat < 3; seat++ {
		if _, err := matches.Ready(matchmaking.RoomReadyRequest{AccountID: fmt.Sprintf("p%d", seat), RoomID: roomID}); err != nil {
			t.Fatal(err)
		}
	}
	hub := newLandlordHub(matches)
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		client := newLandlordClient(newChessClient(conn))
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
	connections := make([]*websocket.Conn, 3)
	for seat := 0; seat < 3; seat++ {
		conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
		if err != nil {
			t.Fatal(err)
		}
		connections[seat] = conn
		defer conn.Close()
		_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
		if err := conn.WriteJSON(map[string]any{"type": "landlord_join", "room_id": roomID, "client_id": fmt.Sprintf("p%d", seat)}); err != nil {
			t.Fatal(err)
		}
		var joined, state map[string]any
		if err := conn.ReadJSON(&joined); err != nil {
			t.Fatal(err)
		}
		if err := conn.ReadJSON(&state); err != nil {
			t.Fatal(err)
		}
		if joined["type"] != "landlord_joined" || int(joined["your_seat"].(float64)) != seat {
			t.Fatalf("bad join %+v", joined)
		}
		if state["type"] != "landlord_state" || len(state["hand"].([]any)) != 17 || len(state["bottom"].([]any)) != 0 {
			t.Fatalf("hidden cards leaked %+v", state)
		}
		if _, ok := state["hands_revealed"]; ok {
			t.Fatal("opponent hands leaked")
		}
	}
	if hub.rooms[roomID].connectedSeats() != 3 || !hub.rooms[roomID].started {
		t.Fatal("three player room did not start")
	}
	_ = connections[0].WriteJSON(map[string]any{"type": "landlord_action", "action": "bid", "amount": 1})
	for i := 0; i < 4; i++ {
		var state map[string]any
		if err := connections[0].ReadJSON(&state); err != nil {
			t.Fatal(err)
		}
		if state["type"] == "landlord_state" && int(state["turn"].(float64)) == 1 && int(state["highest_bid"].(float64)) == 1 {
			return
		}
	}
	t.Fatal("bid was not applied through the realtime protocol")
}

func TestLandlordTrainingUsesSameRules(t *testing.T) {
	hub := newLandlordHub(nil)
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		client := newLandlordClient(newChessClient(conn))
		for {
			var message map[string]any
			if conn.ReadJSON(&message) != nil {
				return
			}
			hub.handle(client, message)
		}
	}))
	defer server.Close()
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	if err := conn.WriteJSON(map[string]any{"type": "landlord_training_start"}); err != nil {
		t.Fatal(err)
	}
	var state map[string]any
	if err := conn.ReadJSON(&state); err != nil {
		t.Fatal(err)
	}
	if state["phase"] != "bid" || len(state["hand"].([]any)) != 17 {
		t.Fatalf("invalid training start %+v", state)
	}
	if err := conn.WriteJSON(map[string]any{"type": "landlord_action", "action": "bid", "amount": 1}); err != nil {
		t.Fatal(err)
	}
	if err := conn.ReadJSON(&state); err != nil {
		t.Fatal(err)
	}
	if state["phase"] != "double" || int(state["landlord"].(float64)) != 0 || len(state["hand"].([]any)) != 20 {
		t.Fatalf("training bots did not finish bid %+v", state)
	}
	if err := conn.WriteJSON(map[string]any{"type": "landlord_action", "action": "double", "enabled": false}); err != nil {
		t.Fatal(err)
	}
	if err := conn.ReadJSON(&state); err != nil {
		t.Fatal(err)
	}
	if state["phase"] != "play" || int(state["turn"].(float64)) != 0 {
		t.Fatalf("training doubling did not begin play %+v", state)
	}
}
