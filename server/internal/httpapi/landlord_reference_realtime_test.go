package httpapi

import (
	"encoding/base64"
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
func referenceLandlordServer(t *testing.T, roomCount int, captured ...chan *landlordClient) (*landlordHub, [][]*websocket.Conn, []string) {
	t.Helper()
	return referenceLandlordVersionServer(t, roomCount, "2.0.0", captured...)
}

func referenceLandlordVersionServer(t *testing.T, roomCount int, version string, captured ...chan *landlordClient) (*landlordHub, [][]*websocket.Conn, []string) {
	t.Helper()
	matches := matchmaking.NewManager(room.NewManager())
	ids := make([]string, roomCount)
	for index := 0; index < roomCount; index++ {
		for seat := 0; seat < 3; seat++ {
			account := fmt.Sprintf("reference-%d-%d", index, seat)
			result, err := matches.QuickMatch(matchmaking.QuickMatchRequest{ProductID: "xbd_landlord", GameID: "landlord", RuleSetID: "classic_three_player", RuleVersion: version, AccountID: account})
			if err != nil {
				t.Fatal(err)
			}
			ids[index] = result.RoomID
		}
		for seat := 0; seat < 3; seat++ {
			if _, err := matches.Ready(matchmaking.RoomReadyRequest{RoomID: ids[index], AccountID: fmt.Sprintf("reference-%d-%d", index, seat)}); err != nil {
				t.Fatal(err)
			}
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
		if len(captured) > 0 {
			captured[0] <- client
		}
		defer hub.disconnect(client)
		for {
			var message map[string]any
			if conn.ReadJSON(&message) != nil {
				return
			}
			hub.handle(client, message)
		}
	}))
	t.Cleanup(server.Close)
	connect := func() *websocket.Conn {
		conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = conn.Close() })
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
				referenceSend(t, conn, map[string]any{"type": "landlord_join", "room_id": ids[index], "client_id": fmt.Sprintf("reference-%d-%d", index, seat), "rule_version": "untrusted-client-version"})
				referenceRead(t, conn, "landlord_joined")
				referenceRead(t, conn, "landlord_state")
			}
		}
	}
	t.Cleanup(func() {
		for _, r := range hub.rooms {
			r.mu.Lock()
			if r.timer != nil {
				r.timer.Stop()
			}
			r.closed = true
			r.mu.Unlock()
		}
	})
	return hub, connections, ids
}

func referenceSend(t *testing.T, conn *websocket.Conn, message map[string]any) {
	t.Helper()
	if err := conn.WriteJSON(message); err != nil {
		t.Fatal(err)
	}
}

func referenceRead(t *testing.T, conn *websocket.Conn, kind string) map[string]any {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		var message map[string]any
		if err := conn.ReadJSON(&message); err != nil {
			t.Fatal(err)
		}
		if message["type"] == kind {
			return message
		}
		if message["type"] == "landlord_error" {
			t.Fatalf("unexpected error: %v", message)
		}
	}
}

func TestLandlordReferenceTrainingDoubleHintAndCountdown(t *testing.T) {
	_, connections, _ := referenceLandlordServer(t, 0)
	conn := connections[0][0]
	referenceSend(t, conn, map[string]any{"type": "landlord_training_start"})
	referenceRead(t, conn, "landlord_state")
	referenceSend(t, conn, map[string]any{"type": "landlord_action", "action": "bid", "amount": 3})
	state := referenceRead(t, conn, "landlord_state")
	if state["phase"] != "double" {
		t.Fatalf("bidding skipped requested doubling decision: %v", state["phase"])
	}
	if state["rule_version"] != "2.0.0" {
		t.Fatalf("current training rule version missing: %v", state["rule_version"])
	}
	now := state["server_now_ms"].(float64)
	deadline := state["action_deadline_ms"].(float64)
	if state["action_timeout_seconds"] != float64(30) || deadline-now < 29000 || deadline-now > 30000 {
		t.Fatalf("invalid authoritative countdown: %v", state)
	}
	referenceSend(t, conn, map[string]any{"type": "landlord_action", "action": "double", "enabled": false})
	state = referenceRead(t, conn, "landlord_state")
	if state["phase"] != "play" || state["turn"] != float64(0) || state["multiplier"] != float64(1) {
		t.Fatalf("training bots failed to decline doubling: %v", state)
	}
	for _, decided := range state["double_decided"].([]any) {
		if decided != true {
			t.Fatalf("missing doubling decision: %v", state)
		}
	}
	referenceSend(t, conn, map[string]any{"type": "landlord_action", "action": "hint"})
	hint := referenceRead(t, conn, "landlord_hint")
	ids := hint["card_ids"].([]any)
	if len(ids) == 0 {
		t.Fatal("legal opening hint missing")
	}
	owned := map[float64]bool{}
	for _, raw := range state["hand"].([]any) {
		owned[raw.(map[string]any)["id"].(float64)] = true
	}
	for _, id := range ids {
		if !owned[id.(float64)] {
			t.Fatal("hint leaked or invented a private card")
		}
	}
	if _, leaked := hint["hands"]; leaked {
		t.Fatal("hint leaked opponents")
	}
}

func referenceState(t *testing.T, conn *websocket.Conn, phase string, turn int) map[string]any {
	t.Helper()
	for {
		state := referenceRead(t, conn, "landlord_state")
		if state["phase"] == phase && state["turn"] == float64(turn) {
			return state
		}
	}
}

func TestLandlordReferenceRoomDoublingAndHintDoNotExposeOtherHands(t *testing.T) {
	_, connections, _ := referenceLandlordServer(t, 1)
	seats := connections[0]
	referenceSend(t, seats[0], map[string]any{"type": "landlord_action", "action": "bid", "amount": 3})
	referenceState(t, seats[0], "double", 0)
	referenceSend(t, seats[0], map[string]any{"type": "landlord_action", "action": "double", "enabled": true})
	state := referenceState(t, seats[1], "double", 1)
	if state["rule_version"] != "2.0.0" {
		t.Fatal("authoritative new room version missing")
	}
	if state["multiplier"] != float64(2) {
		t.Fatal("first affirmative decision failed to double table")
	}
	referenceSend(t, seats[1], map[string]any{"type": "landlord_action", "action": "double", "enabled": false})
	referenceState(t, seats[2], "double", 2)
	referenceSend(t, seats[2], map[string]any{"type": "landlord_action", "action": "double", "enabled": true})
	state = referenceState(t, seats[0], "play", 0)
	if state["multiplier"] != float64(4) {
		t.Fatal("second affirmative decision failed to multiply table again")
	}
	if _, leaked := state["hands_revealed"]; leaked {
		t.Fatal("double state revealed private hands")
	}
	deadline := state["action_deadline_ms"]
	referenceSend(t, seats[0], map[string]any{"type": "landlord_action", "action": "hint"})
	hint := referenceRead(t, seats[0], "landlord_hint")
	if len(hint["card_ids"].([]any)) == 0 {
		t.Fatal("opening hint missing")
	}
	referenceSend(t, seats[1], map[string]any{"type": "landlord_action", "action": "hint"})
	referenceRead(t, seats[1], "landlord_error")
	referenceSend(t, seats[0], map[string]any{"type": "landlord_action", "action": "double", "enabled": true})
	referenceRead(t, seats[0], "landlord_error")
	referenceSend(t, seats[0], map[string]any{"type": "landlord_action", "action": "play", "card_ids": hint["card_ids"]})
	after := referenceState(t, seats[0], "play", 1)
	if after["action_deadline_ms"].(float64) < deadline.(float64) || len(after["hand"].([]any)) != len(state["hand"].([]any))-len(hint["card_ids"].([]any)) {
		t.Fatal("hint was not a real playable recommendation")
	}
}

func TestLandlordLegacyRoomForDefaultsToOriginalRules(t *testing.T) {
	hub := newLandlordHub(nil)
	r := hub.roomFor("legacy-default", [3]string{"a", "b", "c"})
	if r.game.EnableDoubling {
		t.Fatal("default legacy room was silently migrated to new rules")
	}
	if err := r.game.Bid(0, 3); err != nil {
		t.Fatal(err)
	}
	state := r.game.SnapshotFor(0)
	if state["phase"] != "play" || state["rule_version"] != "1.0.0" {
		t.Fatalf("legacy room did not preserve original play: %v", state)
	}
}

func TestLandlordLegacyRealtimeCannotBeUpgradedByClientVersion(t *testing.T) {
	_, connections, _ := referenceLandlordVersionServer(t, 1, "1.0.0")
	conn := connections[0][0]
	referenceSend(t, conn, map[string]any{"type": "landlord_action", "action": "bid", "amount": 3, "rule_version": "2.0.0"})
	state := referenceState(t, conn, "play", 0)
	if state["rule_version"] != "1.0.0" || state["multiplier"] != float64(1) {
		t.Fatalf("old room rules were overridden: %v", state)
	}
	referenceSend(t, conn, map[string]any{"type": "landlord_action", "action": "double", "enabled": true})
	referenceRead(t, conn, "landlord_error")
}

func TestLandlordSocialBroadcastUsesBoundSeatAndRoom(t *testing.T) {
	_, connections, rooms := referenceLandlordServer(t, 2)
	referenceSend(t, connections[0][0], map[string]any{"type": "landlord_social", "action": "chat", "message_id": "chat-a", "quick_chat": "hello", "seat": 2, "room_id": rooms[1], "text": "spoofed"})
	for _, conn := range connections[0] {
		event := referenceRead(t, conn, "landlord_social")
		if event["room_id"] != rooms[0] || event["seat"] != float64(0) || event["quick_chat"] != "hello" || event["text"] == "spoofed" || event["server_now_ms"].(float64) <= 0 {
			t.Fatalf("untrusted metadata or payload broadcast: %v", event)
		}
	}
	// A room B event is a barrier: a leaked A event would arrive first in B's queue.
	referenceSend(t, connections[1][0], map[string]any{"type": "landlord_social", "action": "emote", "message_id": "emote-b", "emote": "smile"})
	for _, conn := range connections[1] {
		event := referenceRead(t, conn, "landlord_social")
		if event["room_id"] != rooms[1] || event["action"] != "emote" {
			t.Fatalf("social message crossed rooms: %v", event)
		}
	}
}

func TestLandlordSocialTrainingEchoDuplicateAndRateLimit(t *testing.T) {
	_, connections, _ := referenceLandlordServer(t, 0)
	conn := connections[0][0]
	referenceSend(t, conn, map[string]any{"type": "landlord_training_start"})
	referenceRead(t, conn, "landlord_state")
	message := map[string]any{"type": "landlord_social", "action": "prop", "message_id": "prop-1", "prop": "flower", "target_seat": 1, "seat": 2}
	referenceSend(t, conn, message)
	event := referenceRead(t, conn, "landlord_social")
	if event["room_id"] != "训练" || event["seat"] != float64(0) || event["target_seat"] != float64(1) {
		t.Fatalf("invalid training echo: %v", event)
	}
	referenceSend(t, conn, message)
	if !strings.Contains(referenceRead(t, conn, "landlord_error")["message"].(string), "重复") {
		t.Fatal("duplicate social message not detected")
	}
	message["message_id"] = "prop-2"
	referenceSend(t, conn, message)
	if !strings.Contains(referenceRead(t, conn, "landlord_error")["message"].(string), "频繁") {
		t.Fatal("social flood was not limited")
	}
	time.Sleep(1100 * time.Millisecond)
	referenceSend(t, conn, message)
	if referenceRead(t, conn, "landlord_social")["message_id"] != "prop-2" {
		t.Fatal("rate limit consumed a rejected message id")
	}
}

func TestLandlordSocialRejectsInvalidPayloadsWithoutConsumingID(t *testing.T) {
	_, connections, _ := referenceLandlordServer(t, 0)
	conn := connections[0][0]
	referenceSend(t, conn, map[string]any{"type": "landlord_training_start"})
	referenceRead(t, conn, "landlord_state")
	invalid := []map[string]any{
		{"action": "chat", "quick_chat": "arbitrary-text"},
		{"action": "emote", "emote": "unknown"},
		{"action": "prop", "prop": "tomato", "target_seat": 3},
		{"action": "prop", "prop": "tomato", "target_seat": 1.5},
		{"action": "voice", "sample_rate": 44100, "duration_ms": 100, "pcm_base64": "AAAA"},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 99, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1584))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 5001, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 80016))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": "invalid-base64"},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1601))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 3200))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 5000, "pcm_base64": strings.Repeat("A", 106672)},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "channels": 2, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1600))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "format": "mp3", "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1600))},
		{"action": "unknown"},
	}
	for index, message := range invalid {
		message["type"], message["message_id"] = "landlord_social", "retry-id"
		referenceSend(t, conn, message)
		if referenceRead(t, conn, "landlord_error")["message"] == "" {
			t.Fatalf("invalid payload %d accepted", index)
		}
	}
	referenceSend(t, conn, map[string]any{"type": "landlord_social", "action": "chat", "message_id": "retry-id", "quick_chat": "thanks"})
	if referenceRead(t, conn, "landlord_social")["quick_chat"] != "thanks" {
		t.Fatal("invalid payload consumed rate limit or id")
	}
}

func TestLandlordSocialVoiceChecksDecodedPayloadAtBothSampleRates(t *testing.T) {
	for _, rate := range []int{8000, 16000} {
		t.Run(fmt.Sprint(rate), func(t *testing.T) {
			_, connections, _ := referenceLandlordServer(t, 0)
			conn := connections[0][0]
			referenceSend(t, conn, map[string]any{"type": "landlord_training_start"})
			referenceRead(t, conn, "landlord_state")
			data := base64.StdEncoding.EncodeToString(make([]byte, rate*10))
			referenceSend(t, conn, map[string]any{"type": "landlord_social", "action": "voice", "message_id": "voice-1", "sample_rate": rate, "duration_ms": 5000, "pcm_base64": data, "seat": 2})
			event := referenceRead(t, conn, "landlord_social")
			if event["seat"] != float64(0) || event["sample_rate"] != float64(rate) || event["duration_ms"] != float64(5000) || event["pcm_base64"] != data {
				t.Fatal("valid PCM voice did not echo faithfully")
			}
		})
	}
}

func TestLandlordSocialRequiresActiveMembershipAndMessageID(t *testing.T) {
	_, connections, _ := referenceLandlordServer(t, 0)
	conn := connections[0][0]
	referenceSend(t, conn, map[string]any{"type": "landlord_social", "action": "chat", "message_id": "unbound", "quick_chat": "hello"})
	referenceRead(t, conn, "landlord_error")
	referenceSend(t, conn, map[string]any{"type": "landlord_training_start"})
	referenceRead(t, conn, "landlord_state")
	for _, id := range []string{"", strings.Repeat("a", 65), "含中文", "has space"} {
		referenceSend(t, conn, map[string]any{"type": "landlord_social", "action": "chat", "message_id": id, "quick_chat": "hello"})
		referenceRead(t, conn, "landlord_error")
	}
}

func TestLandlordReferenceTrainingTimeoutDeclinesDoubleAndDisconnectStopsTimer(t *testing.T) {
	captured := make(chan *landlordClient, 1)
	hub, connections, _ := referenceLandlordServer(t, 0, captured)
	client, conn := <-captured, connections[0][0]
	referenceSend(t, conn, map[string]any{"type": "landlord_training_start"})
	referenceRead(t, conn, "landlord_state")
	referenceSend(t, conn, map[string]any{"type": "landlord_action", "action": "bid", "amount": 3})
	referenceState(t, conn, "double", 0)
	// Fire the real registered timer callback promptly instead of waiting 30 seconds.
	client.trainingMu.Lock()
	client.trainingTimer.Reset(time.Millisecond)
	client.trainingMu.Unlock()
	state := referenceState(t, conn, "play", 0)
	if state["multiplier"] != float64(1) {
		t.Fatal("timeout doubled the training game")
	}
	for _, value := range state["doubled"].([]any) {
		if value != false {
			t.Fatal("automatic doubling decision was affirmative")
		}
	}
	client.trainingMu.Lock()
	timer, epoch := client.trainingTimer, client.trainingGame.Epoch
	client.trainingMu.Unlock()
	hub.disconnect(client)
	// Even a callback that races Stop must observe the disconnected guard.
	timer.Reset(time.Millisecond)
	time.Sleep(15 * time.Millisecond)
	client.trainingMu.Lock()
	defer client.trainingMu.Unlock()
	if client.trainingTimer != nil || client.trainingGame.Epoch != epoch {
		t.Fatal("disconnected training continued advancing")
	}
}

func TestLandlordSocialRejectsRemovedConnection(t *testing.T) {
	captured := make(chan *landlordClient, 3)
	hub, connections, rooms := referenceLandlordServer(t, 1, captured)
	client := <-captured
	r := hub.rooms[rooms[0]]
	r.mu.Lock()
	delete(r.clients, client)
	r.mu.Unlock()
	referenceSend(t, connections[0][0], map[string]any{"type": "landlord_social", "action": "chat", "message_id": "removed", "quick_chat": "hello"})
	referenceRead(t, connections[0][0], "landlord_error")
	referenceSend(t, connections[0][1], map[string]any{"type": "landlord_social", "action": "chat", "message_id": "active", "quick_chat": "hello"})
	for _, conn := range connections[0][1:] {
		if referenceRead(t, conn, "landlord_social")["seat"] != float64(1) {
			t.Fatal("removed connection injected a social event")
		}
	}
}

func TestLandlordSocialReconnectRetainsSeatDuplicateAndRateLimits(t *testing.T) {
	_, connections, rooms := referenceLandlordServer(t, 1)
	message := map[string]any{"type": "landlord_social", "action": "chat", "message_id": "reconnect-replay", "quick_chat": "hello"}
	referenceSend(t, connections[0][0], message)
	for _, conn := range connections[0] {
		referenceRead(t, conn, "landlord_social")
	}
	replacement, _, err := websocket.DefaultDialer.Dial("ws://"+connections[0][0].RemoteAddr().String(), nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = replacement.Close() })
	referenceSend(t, replacement, map[string]any{"type": "landlord_join", "room_id": rooms[0], "client_id": "reference-0-0"})
	referenceRead(t, replacement, "landlord_joined")
	referenceRead(t, replacement, "landlord_state")
	referenceSend(t, replacement, message)
	_ = replacement.SetReadDeadline(time.Now().Add(3 * time.Second))
	var response map[string]any
	if err := replacement.ReadJSON(&response); err != nil {
		t.Fatal(err)
	}
	if response["type"] != "landlord_error" || !strings.Contains(response["message"].(string), "重复") {
		t.Fatalf("reconnecting bypassed duplicate protection: %v", response)
	}
	message["message_id"] = "reconnect-new"
	referenceSend(t, replacement, message)
	if !strings.Contains(referenceRead(t, replacement, "landlord_error")["message"].(string), "频繁") {
		t.Fatal("reconnecting bypassed seat rate limit")
	}
}
