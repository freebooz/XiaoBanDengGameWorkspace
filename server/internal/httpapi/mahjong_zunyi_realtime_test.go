package httpapi

import (
	"fmt"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
)

func TestZunyiFourSeatsSelectPrivatelyAndReconnect(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	var peers [4]*websocket.Conn
	var accountsBySeat [4]string
	for seat := range peers {
		accountsBySeat[seat] = fmt.Sprintf("zunyi-peer-%d", seat)
		peers[seat] = lobbySocket(t, server, accounts, accountsBySeat[seat])
	}

	lobbyCommand(t, peers[0], "quick", "", "zunyi_dingque", "1.0.0", false)
	referenceSend(t, peers[0], map[string]any{
		"type": "mahjong_lobby_command", "command_id": "trial-room", "action": "create",
		"rule_set_id": "zunyi_dingque", "rule_version": "1.0.0",
		"options": map[string]any{"version": "2.0.0", "chicken": false},
	})
	if result := lobbyRead(t, peers[0], "mahjong_lobby_result", nil); result["ok"] != true {
		t.Fatalf("trial room creation failed: %v", result)
	}
	waiting := lobbyState(t, peers[0], "waiting", 1, 0)
	roomID := waiting["room_id"].(string)
	lockedRule := waiting["rule"].(map[string]any)
	if lockedRule["quick_match"] != false || lockedRule["dingque"] != true || !reflect.DeepEqual(lockedRule["options"], map[string]any{"version": "2.0.0", "chicken": false, "rob_kong": true}) {
		t.Fatalf("trial room has invalid effective rule: %v", lockedRule)
	}
	for _, peer := range peers[1:] {
		lobbyCommand(t, peer, "join", roomID, "", "", true)
	}
	for _, peer := range peers {
		lobbyCommand(t, peer, "ready", roomID, "", "", true)
	}
	for _, peer := range peers {
		referenceSend(t, peer, map[string]any{"type": "mahjong_join", "room_id": roomID})
		lobbyRead(t, peer, "mahjong_joined", nil)
	}

	var choices [4]string
	var matchID string
	var deadline float64
	var dealer int
	for seat, peer := range peers {
		state := lobbyRead(t, peer, "mahjong_state", func(packet map[string]any) bool { return packet["status"] == "playing" })
		if state["phase"] != "dingque" || state["your_seat"] != float64(seat) || state["remaining"] != float64(55) || state["missing_suits"] != nil ||
			len(state["options"].([]any)) != 3 || !reflect.DeepEqual(state["rule"], lockedRule) {
			t.Fatalf("seat %d received invalid private selection state: %v", seat, state)
		}
		if seat == 0 {
			matchID = state["match_id"].(string)
			deadline = state["action_deadline_ms"].(float64)
			dealer = int(state["dealer"].(float64))
		}
		choices[seat] = state["hand"].([]any)[0].(map[string]any)["suit"].(string)
	}
	submit := func(peer *websocket.Conn, id, suit string, wantOK bool) {
		t.Helper()
		referenceSend(t, peer, map[string]any{"type": "mahjong_action", "match_id": matchID, "command_id": id, "action": "dingque", "suit": suit})
		if result := lobbyRead(t, peer, "mahjong_action_result", nil); result["ok"] != wantOK || result["command_id"] != id {
			t.Fatalf("unexpected selection result: %v", result)
		}
	}
	submit(peers[0], "bad-suit", "honor", false)
	submit(peers[0], "first-choice", choices[0], true)
	selected := lobbyRead(t, peers[0], "mahjong_state", func(packet map[string]any) bool {
		return packet["phase"] == "dingque" && len(packet["options"].([]any)) == 0
	})
	if selected["missing_suits"] != nil || selected["action_deadline_ms"] != deadline {
		t.Fatalf("first choice exposed the missing suit or reset the shared deadline: %v", selected)
	}
	_ = peers[0].Close()
	endpoint := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/v1/mahjong/ws"
	resumed, _, err := websocket.DefaultDialer.Dial(endpoint, accounts.header(t, accountsBySeat[0]))
	if err != nil {
		t.Fatal(err)
	}
	defer resumed.Close()
	peers[0] = resumed
	referenceSend(t, resumed, map[string]any{"type": "mahjong_join", "room_id": roomID, "match_id": matchID})
	lobbyRead(t, resumed, "mahjong_joined", nil)
	back := lobbyRead(t, resumed, "mahjong_state", nil)
	if back["match_id"] != matchID || back["your_seat"] != float64(0) || back["phase"] != "dingque" || back["missing_suits"] != nil ||
		back["action_deadline_ms"] != deadline || len(back["options"].([]any)) != 0 {
		t.Fatalf("reconnect did not preserve a private committed choice: %v", back)
	}
	submit(resumed, "first-choice", choices[0], true)
	submit(resumed, "first-choice", "changed", false)
	for seat := 1; seat < 4; seat++ {
		submit(peers[seat], fmt.Sprintf("choice-%d", seat), choices[seat], true)
	}

	for seat, peer := range peers {
		state := lobbyRead(t, peer, "mahjong_state", func(packet map[string]any) bool { return packet["phase"] == "turn" })
		want := []any{choices[0], choices[1], choices[2], choices[3]}
		if !reflect.DeepEqual(state["missing_suits"], want) || state["turn"] != float64(dealer) || state["remaining"] != float64(55) {
			t.Fatalf("seat %d did not receive the public selection: %v", seat, state)
		}
		if seat != dealer {
			continue
		}
		legal := map[float64]bool{}
		for _, raw := range state["options"].([]any) {
			option := raw.(map[string]any)
			if option["type"] == "play" {
				legal[option["tile_id"].(float64)] = true
			}
		}
		for _, raw := range state["hand"].([]any) {
			tile := raw.(map[string]any)
			if legal[tile["id"].(float64)] != (tile["suit"] == choices[seat]) {
				t.Fatalf("dealer's legal discards do not enforce the missing suit: %v", state)
			}
		}
	}
}
