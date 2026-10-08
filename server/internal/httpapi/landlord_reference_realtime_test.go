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

// Exercise the real websocket handler, including seat assignment and private state.
func referenceLandlordServer(t *testing.T, roomCount int) (*landlordHub, [][]*websocket.Conn, []string) {
	t.Helper()
	matches := matchmaking.NewManager(room.NewManager())
	ids := make([]string, roomCount)
	for index := 0; index < roomCount; index++ {
		for seat := 0; seat < 3; seat++ {
			account := fmt.Sprintf("reference-%d-%d", index, seat)
			result, err := matches.QuickMatch(matchmaking.QuickMatchRequest{ProductID: "xbd_landlord", GameID: "landlord", RuleSetID: "classic_three_player", RuleVersion: "1.0.0", AccountID: account})
			if err != nil { t.Fatal(err) }
			ids[index] = result.RoomID
		}
		for seat := 0; seat < 3; seat++ {
			if _, err := matches.Ready(matchmaking.RoomReadyRequest{RoomID: ids[index], AccountID: fmt.Sprintf("reference-%d-%d", index, seat)}); err != nil { t.Fatal(err) }
		}
	}
	hub := newLandlordHub(matches)
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil { return }
		defer conn.Close()
		client := newLandlordClient(newChessClient(conn))
		defer hub.disconnect(client)
		for {
			var message map[string]any
			if conn.ReadJSON(&message) != nil { return }
			hub.handle(client, message)
		}
	}))
	t.Cleanup(server.Close)
	connect := func() *websocket.Conn {
		conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
		if err != nil { t.Fatal(err) }
		t.Cleanup(func(){ _ = conn.Close() })
		return conn
	}
	connections := make([][]*websocket.Conn, roomCount)
	if roomCount == 0 {
		connections = [][]*websocket.Conn{{connect()}}
	} else {
		for index := range connections {
			for seat := 0; seat < 3; seat++ {
				conn := connect()
				connections[index] = append(connections[index], conn)
				referenceSend(t, conn, map[string]any{"type":"landlord_join", "room_id":ids[index], "client_id":fmt.Sprintf("reference-%d-%d", index, seat)})
				referenceRead(t, conn, "landlord_joined")
				referenceRead(t, conn, "landlord_state")
			}
		}
	}
	t.Cleanup(func(){
		for _, r := range hub.rooms {
			r.mu.Lock()
			if r.timer != nil { r.timer.Stop() }
			r.closed = true
			r.mu.Unlock()
		}
	})
	return hub, connections, ids
}

func referenceSend(t *testing.T, conn *websocket.Conn, message map[string]any) {
	t.Helper()
	if err := conn.WriteJSON(message); err != nil { t.Fatal(err) }
}

func referenceRead(t *testing.T, conn *websocket.Conn, kind string) map[string]any {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(3*time.Second))
	for {
		var message map[string]any
		if err := conn.ReadJSON(&message); err != nil { t.Fatal(err) }
		if message["type"] == kind { return message }
		if message["type"] == "landlord_error" { t.Fatalf("unexpected error: %v", message) }
	}
}

func TestLandlordReferenceTrainingDoubleHintAndCountdown(t *testing.T) {
	_, connections, _ := referenceLandlordServer(t, 0)
	conn := connections[0][0]
	referenceSend(t, conn, map[string]any{"type":"landlord_training_start"})
	referenceRead(t, conn, "landlord_state")
	referenceSend(t, conn, map[string]any{"type":"landlord_action", "action":"bid", "amount":3})
	state := referenceRead(t, conn, "landlord_state")
	if state["phase"] != "double" { t.Fatalf("bidding skipped requested doubling decision: %v", state["phase"]) }
	now := state["server_now_ms"].(float64)
	deadline := state["action_deadline_ms"].(float64)
	if state["action_timeout_seconds"] != float64(30) || deadline-now < 29000 || deadline-now > 30000 { t.Fatalf("invalid authoritative countdown: %v", state) }
	referenceSend(t, conn, map[string]any{"type":"landlord_action", "action":"double", "enabled":false})
	state = referenceRead(t, conn, "landlord_state")
	if state["phase"] != "play" || state["turn"] != float64(0) || state["multiplier"] != float64(1) { t.Fatalf("training bots failed to decline doubling: %v", state) }
	for _, decided := range state["double_decided"].([]any) { if decided != true { t.Fatalf("missing doubling decision: %v", state) } }
	referenceSend(t, conn, map[string]any{"type":"landlord_action", "action":"hint"})
	hint := referenceRead(t, conn, "landlord_hint")
	ids := hint["card_ids"].([]any)
	if len(ids) == 0 { t.Fatal("legal opening hint missing") }
	owned := map[float64]bool{}
	for _, raw := range state["hand"].([]any) { owned[raw.(map[string]any)["id"].(float64)] = true }
	for _, id := range ids { if !owned[id.(float64)] { t.Fatal("hint leaked or invented a private card") } }
	if _, leaked := hint["hands"]; leaked { t.Fatal("hint leaked opponents") }
}
