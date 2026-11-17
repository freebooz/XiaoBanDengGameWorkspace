package httpapi

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
)

type mahjongReferenceFixture struct {
	hub         *mahjongHub
	rooms       []string
	connections [][]*websocket.Conn
	clients     [][]*mahjongClient
	url         string
	captured    chan *mahjongClient
}

// Keep matchmaking, seat binding, room membership and websocket serialization real.
func referenceMahjongServer(t *testing.T, roomCount, connectedPerRoom int) *mahjongReferenceFixture {
	t.Helper()
	matches := matchmaking.NewManager(room.NewManager())
	f := &mahjongReferenceFixture{hub: newMahjongHub(matches), rooms: make([]string, roomCount), captured: make(chan *mahjongClient, 1)}
	for index := range f.rooms {
		for seat := 0; seat < 4; seat++ {
			result, err := matches.QuickMatch(matchmaking.QuickMatchRequest{
				ProductID: "xbd_mahjong", GameID: "mahjong", RuleSetID: "guiyang", RuleVersion: "2.0.0", AccountID: fmt.Sprintf("mahjong-reference-%d-%d", index, seat),
			})
			if err != nil {
				t.Fatal(err)
			}
			f.rooms[index] = result.RoomID
		}
		for seat := 0; seat < 4; seat++ {
			if _, err := matches.Ready(matchmaking.RoomReadyRequest{RoomID: f.rooms[index], AccountID: fmt.Sprintf("mahjong-reference-%d-%d", index, seat)}); err != nil {
				t.Fatal(err)
			}
		}
	}
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		// Joining must support the maximum permitted PCM frame even with a small initial limit.
		conn.SetReadLimit(4096)
		client := newMahjongClient(newChessClient(conn))
		f.captured <- client
		defer f.hub.disconnect(client)
		for {
			var message map[string]any
			if conn.ReadJSON(&message) != nil {
				return
			}
			if !f.hub.handle(client, message) {
				_ = client.wire.writeJSON(map[string]any{"type": "ack", "payload": message})
			}
		}
	}))
	f.url = "ws" + strings.TrimPrefix(server.URL, "http")
	t.Cleanup(server.Close)
	f.connections = make([][]*websocket.Conn, roomCount)
	f.clients = make([][]*mahjongClient, roomCount)
	for index := range f.rooms {
		for seat := 0; seat < connectedPerRoom; seat++ {
			conn, client := f.connect(t)
			f.connections[index] = append(f.connections[index], conn)
			f.clients[index] = append(f.clients[index], client)
			referenceSend(t, conn, map[string]any{"type": "mahjong_join", "room_id": f.rooms[index], "client_id": fmt.Sprintf("mahjong-reference-%d-%d", index, seat)})
			mahjongReferenceRead(t, conn, "mahjong_joined")
			mahjongReferenceRead(t, conn, "mahjong_state")
		}
	}
	t.Cleanup(func() {
		f.hub.mu.Lock()
		defer f.hub.mu.Unlock()
		for _, r := range f.hub.rooms {
			r.mu.Lock()
			if r.timer != nil {
				r.timer.Stop()
			}
			r.closed = true
			r.mu.Unlock()
		}
	})
	return f
}

func (f *mahjongReferenceFixture) connect(t *testing.T) (*websocket.Conn, *mahjongClient) {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial(f.url, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn, <-f.captured
}

func mahjongReferenceRead(t *testing.T, conn *websocket.Conn, kind string) map[string]any {
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
		if message["type"] != "mahjong_state" {
			t.Fatalf("expected %s, received %v", kind, message)
		}
	}
}

func TestMahjongSocialBroadcastUsesBoundSeatAndRoom(t *testing.T) {
	f := referenceMahjongServer(t, 2, 4)
	r := f.hub.rooms[f.rooms[0]]
	r.mu.Lock()
	beforeEpoch, beforeWall, beforeDeadline := r.game.Epoch, r.game.NextWall, r.lastActionAt
	r.mu.Unlock()
	referenceSend(t, f.connections[0][0], map[string]any{
		"type": "mahjong_social", "action": "chat", "message_id": "chat-a", "quick_chat": "hello",
		"seat": 3, "room_id": f.rooms[1], "client_id": "spoofed", "text": "spoofed", "hand": []int{108},
	})
	for _, conn := range f.connections[0] {
		event := mahjongReferenceRead(t, conn, "mahjong_social")
		if event["room_id"] != f.rooms[0] || event["seat"] != float64(0) || event["text"] != "大家好，很高兴一起玩！" || event["server_now_ms"].(float64) <= 0 {
			t.Fatalf("untrusted social metadata or chat: %v", event)
		}
		if _, leaked := event["client_id"]; leaked {
			t.Fatal("client-supplied identity was broadcast")
		}
		if _, leaked := event["hand"]; leaked {
			t.Fatal("unrelated client data was broadcast")
		}
	}
	// A B event is a queue barrier: any leaked A event would arrive first.
	referenceSend(t, f.connections[1][1], map[string]any{"type": "mahjong_social", "action": "emote", "message_id": "emote-b", "emote": "smile"})
	for _, conn := range f.connections[1] {
		event := mahjongReferenceRead(t, conn, "mahjong_social")
		if event["room_id"] != f.rooms[1] || event["seat"] != float64(1) || event["action"] != "emote" || event["emote"] != "smile" {
			t.Fatalf("social message crossed rooms: %v", event)
		}
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.game.Epoch != beforeEpoch || r.game.NextWall != beforeWall || !r.lastActionAt.Equal(beforeDeadline) {
		t.Fatal("social message changed game state or postponed the authoritative action deadline")
	}
}

func TestMahjongSocialRequiresJoinedStartedActiveSeat(t *testing.T) {
	f := referenceMahjongServer(t, 1, 1)
	conn, _ := f.connect(t)
	message := map[string]any{"type": "mahjong_social", "action": "chat", "message_id": "membership", "quick_chat": "hello"}
	referenceSend(t, conn, message)
	if !strings.Contains(mahjongReferenceRead(t, conn, "mahjong_error")["message"].(string), "尚未加入") {
		t.Fatal("unjoined connection could send social messages")
	}
	referenceSend(t, f.connections[0][0], message)
	if !strings.Contains(mahjongReferenceRead(t, f.connections[0][0], "mahjong_error")["message"].(string), "等待四位") {
		t.Fatal("waiting room accepted social messages before the four-seat start")
	}
	f = referenceMahjongServer(t, 1, 4)
	r := f.hub.rooms[f.rooms[0]]
	r.mu.Lock()
	delete(r.clients, f.clients[0][0])
	r.mu.Unlock()
	referenceSend(t, f.connections[0][0], message)
	mahjongReferenceRead(t, f.connections[0][0], "mahjong_error")
	// A forged bound account must fail even when a client remains in the room map.
	r.mu.Lock()
	f.clients[0][1].accountID = "forged-bound-account"
	r.mu.Unlock()
	referenceSend(t, f.connections[0][1], message)
	mahjongReferenceRead(t, f.connections[0][1], "mahjong_error")
	referenceSend(t, f.connections[0][2], message)
	for _, seat := range []int{2, 3} {
		if event := mahjongReferenceRead(t, f.connections[0][seat], "mahjong_social"); event["seat"] != float64(2) {
			t.Fatalf("inactive sender injected an event: %v", event)
		}
	}
}

func TestMahjongSocialRejectsInvalidPayloadWithoutConsumingID(t *testing.T) {
	f := referenceMahjongServer(t, 1, 4)
	conn := f.connections[0][0]
	invalid := []map[string]any{
		{"action": "chat", "quick_chat": "arbitrary-text"},
		{"action": "emote", "emote": "unknown"},
		{"action": "prop", "prop": "flower", "target_seat": 1},
		{"action": "voice", "sample_rate": 44100, "duration_ms": 100, "pcm_base64": "AAAA"},
		{"action": "voice", "sample_rate": 8000.5, "duration_ms": 100, "pcm_base64": "AAAA"},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 99, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1584))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 5001, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 80016))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100.5, "pcm_base64": "AAAA"},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": "invalid-base64"},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1601))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 3200))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 5000, "pcm_base64": strings.Repeat("A", 106672)},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": ""},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "channels": 2, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1600))},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "format": "mp3", "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1600))},
		{"action": "unknown"},
	}
	for index, message := range invalid {
		message["type"], message["message_id"] = "mahjong_social", "retry-id"
		referenceSend(t, conn, message)
		if event := mahjongReferenceRead(t, conn, "mahjong_error"); event["message"] == "" {
			t.Fatalf("invalid payload %d was accepted", index)
		}
	}
	for _, id := range []any{nil, "", strings.Repeat("a", 65), "含中文", "has space", "x.y", 3} {
		referenceSend(t, conn, map[string]any{"type": "mahjong_social", "action": "chat", "message_id": id, "quick_chat": "hello"})
		mahjongReferenceRead(t, conn, "mahjong_error")
	}
	referenceSend(t, conn, map[string]any{"type": "mahjong_social", "action": "chat", "message_id": "retry-id", "quick_chat": "thanks"})
	for _, peer := range f.connections[0] {
		if event := mahjongReferenceRead(t, peer, "mahjong_social"); event["message_id"] != "retry-id" || event["text"] != "谢谢！" {
			t.Fatal("invalid payload consumed an id/rate limit or reached peers")
		}
	}
}

func TestMahjongSocialCanonicalQuickChatsAndEmotes(t *testing.T) {
	chats := map[string]string{
		"hello": "大家好，很高兴一起玩！", "hurry": "快点吧，我等到花儿都谢了！", "well_played": "这手牌打得漂亮！", "thanks": "谢谢！", "good_game": "好牌，好局！",
	}
	for id, text := range chats {
		t.Run("chat-"+id, func(t *testing.T) {
			f := referenceMahjongServer(t, 1, 4)
			referenceSend(t, f.connections[0][3], map[string]any{"type": "mahjong_social", "action": "chat", "message_id": "Az_09-" + id, "quick_chat": id, "text": "spoofed"})
			for _, conn := range f.connections[0] {
				event := mahjongReferenceRead(t, conn, "mahjong_social")
				if event["text"] != text || event["quick_chat"] != id || event["seat"] != float64(3) {
					t.Fatalf("canonical quick chat was not broadcast: %v", event)
				}
			}
		})
	}
	for _, id := range []string{"smile", "laugh", "thumbs_up", "cry", "angry"} {
		t.Run("emote-"+id, func(t *testing.T) {
			f := referenceMahjongServer(t, 1, 4)
			referenceSend(t, f.connections[0][2], map[string]any{"type": "mahjong_social", "action": "emote", "message_id": strings.Repeat("a", 64), "emote": id})
			for _, conn := range f.connections[0] {
				if event := mahjongReferenceRead(t, conn, "mahjong_social"); event["emote"] != id || event["seat"] != float64(2) {
					t.Fatalf("valid emote was not broadcast: %v", event)
				}
			}
		})
	}
}

func TestMahjongSocialRateDedupAndReconnectRemainPerSeat(t *testing.T) {
	f := referenceMahjongServer(t, 1, 4)
	message := map[string]any{"type": "mahjong_social", "action": "chat", "message_id": "replay", "quick_chat": "hello"}
	referenceSend(t, f.connections[0][0], message)
	for _, conn := range f.connections[0] {
		mahjongReferenceRead(t, conn, "mahjong_social")
	}
	referenceSend(t, f.connections[0][0], message)
	if !strings.Contains(mahjongReferenceRead(t, f.connections[0][0], "mahjong_error")["message"].(string), "重复") {
		t.Fatal("duplicate message was not rejected")
	}
	message["message_id"] = "retry-after-rate"
	referenceSend(t, f.connections[0][0], message)
	if !strings.Contains(mahjongReferenceRead(t, f.connections[0][0], "mahjong_error")["message"].(string), "频繁") {
		t.Fatal("rapid messages were not rejected")
	}
	// Another seat can send the same id immediately; budgets are per authoritative seat.
	referenceSend(t, f.connections[0][1], message)
	for _, conn := range f.connections[0] {
		if event := mahjongReferenceRead(t, conn, "mahjong_social"); event["seat"] != float64(1) {
			t.Fatal("a seat's budget was applied to another seat")
		}
	}
	time.Sleep(1100 * time.Millisecond)
	referenceSend(t, f.connections[0][0], message)
	for _, conn := range f.connections[0] {
		if event := mahjongReferenceRead(t, conn, "mahjong_social"); event["message_id"] != "retry-after-rate" {
			t.Fatal("rate-rejected message consumed its id")
		}
	}
	replacement, _ := f.connect(t)
	referenceSend(t, replacement, map[string]any{"type": "mahjong_join", "room_id": f.rooms[0], "client_id": "mahjong-reference-0-0"})
	mahjongReferenceRead(t, replacement, "mahjong_joined")
	mahjongReferenceRead(t, replacement, "mahjong_state")
	referenceSend(t, replacement, message)
	if !strings.Contains(mahjongReferenceRead(t, replacement, "mahjong_error")["message"].(string), "重复") {
		t.Fatal("reconnecting bypassed replay protection")
	}
	message["message_id"] = "reconnect-new"
	referenceSend(t, replacement, message)
	if !strings.Contains(mahjongReferenceRead(t, replacement, "mahjong_error")["message"].(string), "频繁") {
		t.Fatal("reconnecting bypassed rate protection")
	}
}

func TestMahjongSocialVoiceBroadcastsMaximumPCMAtBothRates(t *testing.T) {
	for _, rate := range []int{8000, 16000} {
		t.Run(fmt.Sprint(rate), func(t *testing.T) {
			f := referenceMahjongServer(t, 1, 4)
			pcm := make([]byte, rate*10)
			pcm[0], pcm[len(pcm)-1] = 0x7f, 0xff
			data := base64.StdEncoding.EncodeToString(pcm)
			referenceSend(t, f.connections[0][0], map[string]any{"type": "mahjong_social", "action": "voice", "message_id": "voice-max", "sample_rate": rate, "duration_ms": 5000, "pcm_base64": data})
			for _, conn := range f.connections[0] {
				event := mahjongReferenceRead(t, conn, "mahjong_social")
				if event["seat"] != float64(0) || event["sample_rate"] != float64(rate) || event["duration_ms"] != float64(5000) || event["pcm_base64"] != data || event["format"] != "pcm_s16le" || event["channels"] != float64(1) {
					t.Fatal("maximum permitted PCM was not broadcast faithfully")
				}
			}
		})
	}
}

func TestMahjongReferenceSnapshotConnectedSeatsDealerAndClock(t *testing.T) {
	f := referenceMahjongServer(t, 1, 1)
	referenceSend(t, f.connections[0][0], map[string]any{"type": "mahjong_join", "room_id": f.rooms[0], "client_id": "mahjong-reference-0-0"})
	mahjongReferenceRead(t, f.connections[0][0], "mahjong_joined")
	state := mahjongReferenceRead(t, f.connections[0][0], "mahjong_state")
	if state["status"] != "waiting" || state["action_deadline_ms"] != float64(0) || !reflect.DeepEqual(state["connected_seats"], []any{true, false, false, false}) {
		t.Fatalf("waiting snapshot has invalid seat/deadline metadata: %v", state)
	}
	f = referenceMahjongServer(t, 1, 4)
	for seat := 0; seat < 4; seat++ {
		referenceSend(t, f.connections[0][seat], map[string]any{"type": "mahjong_join", "room_id": f.rooms[0], "client_id": fmt.Sprintf("mahjong-reference-0-%d", seat)})
		mahjongReferenceRead(t, f.connections[0][seat], "mahjong_joined")
		state = mahjongReferenceRead(t, f.connections[0][seat], "mahjong_state")
		now, ok := state["server_now_ms"].(float64)
		if !ok || state["server_time_ms"] != now || state["action_timeout_seconds"] != float64(15) || state["dealer"] != float64(0) || !reflect.DeepEqual(state["connected_seats"], []any{true, true, true, true}) {
			t.Fatalf("snapshot is missing authoritative seats/dealer/clock: %v", state)
		}
		remaining := state["action_deadline_ms"].(float64) - now
		if remaining < 14000 || remaining > 15000 || state["connected_players"] != float64(4) {
			t.Fatalf("invalid 15-second action deadline: %v", state)
		}
		if _, leaked := state["hands"]; leaked {
			t.Fatal("snapshot revealed opponents' hands")
		}
	}
	_ = f.connections[0][2].Close()
	for {
		state = mahjongReferenceRead(t, f.connections[0][0], "mahjong_state")
		if state["connected_players"] == float64(3) {
			break
		}
	}
	if !reflect.DeepEqual(state["connected_seats"], []any{true, true, false, true}) {
		t.Fatalf("disconnect was assigned to the wrong seat: %v", state["connected_seats"])
	}
}

func TestMahjongSocialRemainsAvailableToFinishedRoomConnections(t *testing.T) {
	f := referenceMahjongServer(t, 1, 4)
	r := f.hub.rooms[f.rooms[0]]
	r.mu.Lock()
	for step := 0; step < 2000 && r.game.Phase != guiyang.PhaseFinished; step++ {
		r.game.Timeout()
	}
	if r.game.Phase != guiyang.PhaseFinished {
		r.mu.Unlock()
		t.Fatal("real timeout play failed to finish fixture")
	}
	r.finishIfNeededLocked(f.hub)
	r.broadcastLocked()
	r.mu.Unlock()
	for _, conn := range f.connections[0] {
		for {
			state := mahjongReferenceRead(t, conn, "mahjong_state")
			if state["status"] == "finished" {
				if state["action_deadline_ms"] != float64(0) {
					t.Fatal("finished room retained an active action countdown")
				}
				break
			}
		}
	}
	// Existing seated players can still exchange all supported social actions at settlement.
	for seat, message := range []map[string]any{
		{"action": "chat", "quick_chat": "good_game"},
		{"action": "emote", "emote": "thumbs_up"},
		{"action": "voice", "sample_rate": 8000, "duration_ms": 100, "pcm_base64": base64.StdEncoding.EncodeToString(make([]byte, 1600))},
	} {
		message["type"], message["message_id"] = "mahjong_social", "finished"
		referenceSend(t, f.connections[0][seat], message)
		for _, conn := range f.connections[0] {
			if event := mahjongReferenceRead(t, conn, "mahjong_social"); event["seat"] != float64(seat) || event["action"] != message["action"] {
				t.Fatalf("finished room lost social support: %v", event)
			}
		}
	}
}

func TestMahjongHubDoesNotRouteOtherGameSocialMessages(t *testing.T) {
	hub := newMahjongHub(nil)
	if hub.handle(newMahjongClient(nil), map[string]any{"type": "landlord_social", "action": "chat", "message_id": "other-game", "quick_chat": "hello"}) {
		t.Fatal("Mahjong hub claimed another game's social protocol")
	}
}
