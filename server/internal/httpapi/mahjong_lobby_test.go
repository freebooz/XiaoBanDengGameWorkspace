package httpapi

import (
	"bytes"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/gorilla/websocket"
)

func lobbySocket(t *testing.T, server *httptest.Server, accounts *fixtureAccounts, id string) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/mahjong/ws", accounts.header(t, id))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	referenceSend(t, conn, map[string]any{"type": "mahjong_lobby_subscribe", "client_id": id})
	lobbyRead(t, conn, "mahjong_lobby_state", func(message map[string]any) bool {
		return len(message["presets"].([]any)) == 2 && message["state"].(map[string]any)["status"] == "idle"
	})
	return conn
}

func lobbyRead(t *testing.T, conn *websocket.Conn, kind string, accept func(map[string]any) bool) map[string]any {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		var message map[string]any
		if err := conn.ReadJSON(&message); err != nil {
			t.Fatalf("waiting for %s: %v", kind, err)
		}
		if message["type"] == kind && (accept == nil || accept(message)) {
			return message
		}
		if message["type"] == "ack" || message["type"] == "mahjong_error" {
			t.Fatalf("waiting for %s, received %v", kind, message)
		}
	}
}

func lobbyCommand(t *testing.T, conn *websocket.Conn, action, roomID, rule, version string, wantOK bool) {
	t.Helper()
	referenceSend(t, conn, map[string]any{"type": "mahjong_lobby_command", "command_id": action, "action": action, "room_id": roomID, "rule_set_id": rule, "rule_version": version})
	result := lobbyRead(t, conn, "mahjong_lobby_result", nil)
	if result["command_id"] != action || result["ok"] != wantOK {
		t.Fatalf("unexpected result for %s: %v", action, result)
	}
}

func lobbyState(t *testing.T, conn *websocket.Conn, status string, players int, ready int) map[string]any {
	t.Helper()
	message := lobbyRead(t, conn, "mahjong_lobby_state", func(message map[string]any) bool {
		state := message["state"].(map[string]any)
		return state["status"] == status && len(state["player_account_ids"].([]any)) == players && len(state["ready_account_ids"].([]any)) == ready
	})
	return message["state"].(map[string]any)
}

func TestMahjongLobbyFriendRoomReadinessAndQuickIsolation(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	host := lobbySocket(t, server, accounts, "host")
	lobbyCommand(t, host, "create", "", "basic_108", "unknown", false)
	lobbyCommand(t, host, "create", "", "basic_108", "1.0.0", true)
	state := lobbyState(t, host, "waiting", 1, 0)
	roomID := state["room_id"].(string)
	if len(roomID) != 4 || state["kind"] != "friend" || state["rule_set_id"] != "basic_108" {
		t.Fatalf("unexpected friend room state: %v", state)
	}
	lobbyCommand(t, host, "ready", roomID, "", "", true)
	if waiting := lobbyState(t, host, "waiting", 1, 1); waiting["start"] != false {
		t.Fatalf("one ready player caused early start: %v", waiting)
	}
	lobbyCommand(t, host, "unready", roomID, "", "", true)
	lobbyState(t, host, "waiting", 1, 0)
	lobbyCommand(t, host, "ready", roomID, "", "", true)
	lobbyState(t, host, "waiting", 1, 1)
	lobbyCommand(t, host, "quick", "", "basic_108", "1.0.0", false)
	outsider := lobbySocket(t, server, accounts, "outsider")
	lobbyCommand(t, outsider, "quick", "", "basic_108", "1.0.0", true)
	if state := lobbyState(t, outsider, "waiting", 1, 0); state["kind"] != "quick" || state["room_id"] == roomID {
		t.Fatalf("quick match entered invite room: %v", state)
	}
	lobbyCommand(t, outsider, "join", roomID, "", "", false)
	players := []*websocket.Conn{host}
	for seat := 1; seat <= 3; seat++ {
		guest := lobbySocket(t, server, accounts, fmt.Sprintf("friend-%d", seat))
		if seat == 1 {
			lobbyCommand(t, guest, "join", roomID, "guiyang", "2.0.0", false)
		}
		lobbyCommand(t, guest, "join", roomID, "", "", true)
		players = append(players, guest)
	}
	lobbyState(t, host, "matched", 4, 1)
	lobbyCommand(t, players[3], "leave", roomID, "", "", true)
	lobbyState(t, host, "waiting", 3, 0)
	lobbyState(t, players[3], "idle", 0, 0)
	for _, player := range players[:3] {
		lobbyCommand(t, player, "ready", roomID, "", "", true)
	}
	lobbyState(t, host, "waiting", 3, 3)
	lobbyCommand(t, players[3], "join", roomID, "", "", true)
	lobbyState(t, host, "matched", 4, 3)
	lobbyCommand(t, players[3], "ready", roomID, "", "", true)
	state = lobbyState(t, host, "playing", 4, 4)
	if state["start"] != true || state["ready_players"] != float64(4) {
		t.Fatalf("ready roster failed to start: %v", state)
	}
	late := lobbySocket(t, server, accounts, "late")
	lobbyCommand(t, late, "join", roomID, "", "", false)
	referenceSend(t, host, map[string]any{"type": "mahjong_join", "client_id": "host", "room_id": roomID})
	joined := lobbyRead(t, host, "mahjong_joined", nil)
	game := lobbyRead(t, host, "mahjong_state", nil)
	if joined["kind"] != "friend" || game["rule_set_id"] != "basic_108" || game["rule_version"] != "1.0.0" || game["match_id"] == "" || game["rule"].(map[string]any)["chicken"] != false {
		t.Fatalf("game omitted room rule or identity: joined=%v game=%v", joined, game)
	}
}

func TestMahjongLobbyTrainingActionsAndAbandon(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	conn := lobbySocket(t, server, accounts, "learner")
	lobbyCommand(t, conn, "training", "", "basic_108", "1.0.0", true)
	state := lobbyState(t, conn, "playing", 4, 4)
	roomID := state["room_id"].(string)
	referenceSend(t, conn, map[string]any{"type": "mahjong_join", "client_id": "learner", "room_id": roomID})
	lobbyRead(t, conn, "mahjong_joined", nil)
	initial := lobbyRead(t, conn, "mahjong_state", nil)
	if initial["status"] != "playing" || initial["kind"] != "training" || initial["turn"] != float64(0) || len(initial["hand"].([]any)) != 14 || initial["action_timeout_seconds"] != float64(45) {
		t.Fatalf("training did not start with a private dealer hand: %v", initial)
	}
	if _, leaked := initial["hands"]; leaked {
		t.Fatal("training leaked opponents' hands")
	}
	referenceSend(t, conn, map[string]any{"type": "mahjong_action", "command_id": "bad", "action": "play", "tile_id": 0})
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != false || result["command_id"] != "bad" {
		t.Fatalf("rejection was not associated with command: %v", result)
	}
	tileID := initial["hand"].([]any)[0].(map[string]any)["id"]
	referenceSend(t, conn, map[string]any{"type": "mahjong_action", "command_id": "play", "action": "play", "tile_id": tileID})
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != true || result["command_id"] != "play" {
		t.Fatalf("legal discard was not associated with command: %v", result)
	}
	progress := lobbyRead(t, conn, "mahjong_state", func(message map[string]any) bool {
		return len(message["discards"].([]any)) >= 2 || message["status"] == "finished"
	})
	if progress["status"] != "finished" {
		lobbyCommand(t, conn, "leave", roomID, "", "", true)
	}
	lobbyState(t, conn, "idle", 0, 0)
	lobbyCommand(t, conn, "training", "", "guiyang", "2.0.0", true)
	newState := lobbyState(t, conn, "playing", 4, 4)
	referenceSend(t, conn, map[string]any{"type": "mahjong_join", "client_id": "learner", "room_id": newState["room_id"]})
	lobbyRead(t, conn, "mahjong_joined", nil)
	second := lobbyRead(t, conn, "mahjong_state", nil)
	if second["match_id"] == initial["match_id"] || second["rule_set_id"] != "guiyang" {
		t.Fatalf("new training reused prior game state: %v", second)
	}
	lobbyCommand(t, conn, "leave", newState["room_id"].(string), "", "", true)
	lobbyState(t, conn, "idle", 0, 0)
}

func TestMahjongLobbyUndoReadyBeforeEntry(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	var peers [4]*websocket.Conn
	for seat := range peers {
		peers[seat] = lobbySocket(t, server, accounts, fmt.Sprintf("ready-peer-%d", seat))
	}
	lobbyCommand(t, peers[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, peers[0], "waiting", 1, 0)["room_id"].(string)
	for _, peer := range peers[1:] {
		lobbyCommand(t, peer, "join", roomID, "", "", true)
	}
	lobbyState(t, peers[0], "matched", 4, 0)
	lobbyCommand(t, peers[0], "ready", roomID, "", "", true)
	lobbyState(t, peers[1], "matched", 4, 1)
	lobbyCommand(t, peers[0], "unready", roomID, "", "", true)
	lobbyState(t, peers[1], "matched", 4, 0)
	for _, peer := range peers[1:] {
		lobbyCommand(t, peer, "ready", roomID, "", "", true)
	}
	lobbyState(t, peers[0], "matched", 4, 3)
	lobbyCommand(t, peers[0], "ready", roomID, "", "", true)
	lobbyState(t, peers[0], "playing", 4, 4)
	lobbyCommand(t, peers[1], "unready", roomID, "", "", false)
	lobbyState(t, peers[1], "playing", 4, 4)
}

func TestMahjongFriendRoomLocksCustomRuleOptions(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	var peers [4]*websocket.Conn
	for seat := range peers {
		peers[seat] = lobbySocket(t, server, accounts, fmt.Sprintf("custom-%d", seat))
	}
	custom := guiyang.RuleOptions{Version: guiyang.RuleOptionsVersion, Chicken: true, ChargeChicken: false, BlackEight: false, RequiresKongToClaim: false, RobKong: false}
	request := map[string]any{
		"type": "mahjong_lobby_command", "command_id": "custom-create", "action": "create",
		"rule_set_id": "guiyang", "rule_version": "2.0.0", "options": custom,
	}
	referenceSend(t, peers[0], request)
	if result := lobbyRead(t, peers[0], "mahjong_lobby_result", nil); result["ok"] != true {
		t.Fatalf("custom rules were rejected: %v", result)
	}
	assertRule := func(packet map[string]any) {
		t.Helper()
		rule, ok := packet["rule"].(map[string]any)
		if !ok {
			t.Fatalf("missing effective room rule: %v", packet)
		}
		options, ok := rule["options"].(map[string]any)
		if !ok || options["version"] != guiyang.RuleOptionsVersion || options["chicken"] != true || options["charge_chicken"] != false ||
			options["black_eight"] != false || options["requires_kong_to_claim"] != true || options["rob_kong"] != false || rule["requires_kong_to_claim"] != true {
			t.Fatalf("unexpected effective rules: %v", rule)
		}
	}
	created := lobbyState(t, peers[0], "waiting", 1, 0)
	assertRule(created)
	roomID := created["room_id"].(string)
	request["action"], request["room_id"], request["command_id"] = "join", roomID, "override-after-creation"
	referenceSend(t, peers[1], request)
	if result := lobbyRead(t, peers[1], "mahjong_lobby_result", nil); result["ok"] != false {
		t.Fatalf("existing room accepted a new set of rules: %v", result)
	}
	for _, peer := range peers[1:] {
		lobbyCommand(t, peer, "join", roomID, "", "", true)
	}
	assertRule(lobbyState(t, peers[3], "matched", 4, 0))
	for _, peer := range peers {
		lobbyCommand(t, peer, "ready", roomID, "", "", true)
	}
	for seat, peer := range peers {
		referenceSend(t, peer, map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": fmt.Sprintf("custom-%d", seat)})
		assertRule(lobbyRead(t, peer, "mahjong_joined", nil))
	}
	for _, peer := range peers {
		assertRule(lobbyRead(t, peer, "mahjong_state", func(packet map[string]any) bool { return packet["status"] == "playing" }))
	}
}

func TestMahjongRuleOptionsRequireCompleteKnownVersion(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	player := lobbySocket(t, server, accounts, "bad-options")
	for _, options := range []any{nil, true, map[string]any{"version": guiyang.RuleOptionsVersion, "chicken": true}, guiyang.RuleOptions{Version: "unknown"}} {
		referenceSend(t, player, map[string]any{
			"type": "mahjong_lobby_command", "command_id": "bad-create", "action": "create",
			"rule_set_id": "guiyang", "rule_version": "2.0.0", "options": options,
		})
		if result := lobbyRead(t, player, "mahjong_lobby_result", nil); result["ok"] != false {
			t.Fatalf("invalid option packet accepted: %v", options)
		}
		lobbyState(t, player, "idle", 0, 0)
	}
}

func TestMahjongLobbyEntryTimeoutPublishesFinalState(t *testing.T) {
	for _, kind := range []string{"friend", "quick"} {
		t.Run(kind, func(t *testing.T) {
			fixture := referenceMahjongServer(t, 0, 0)
			fixture.hub.entryTimeout = 500 * time.Millisecond
			var peers [4]*websocket.Conn
			for seat := range peers {
				peers[seat], _ = fixture.connect(t)
				referenceSend(t, peers[seat], map[string]any{"type": "mahjong_lobby_subscribe", "client_id": fmt.Sprintf("entry-%d", seat)})
				lobbyState(t, peers[seat], "idle", 0, 0)
			}
			operation := "quick"
			if kind == "friend" {
				operation = "create"
			}
			lobbyCommand(t, peers[0], operation, "", "guiyang", "2.0.0", true)
			roomID := lobbyState(t, peers[0], "waiting", 1, 0)["room_id"].(string)
			for _, peer := range peers[1:] {
				if kind == "friend" {
					lobbyCommand(t, peer, "join", roomID, "", "", true)
				} else {
					lobbyCommand(t, peer, "quick", "", "guiyang", "2.0.0", true)
				}
			}
			for _, peer := range peers {
				lobbyCommand(t, peer, "ready", roomID, "", "", true)
			}
			lobbyState(t, peers[0], "playing", 4, 4)
			if kind == "friend" {
				board, _ := fixture.connect(t)
				referenceSend(t, board, map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": "entry-0"})
				joined := mahjongReferenceRead(t, board, "mahjong_joined")
				waiting := mahjongReferenceRead(t, board, "mahjong_state")
				if waiting["status"] != "waiting" || len(waiting["hand"].([]any)) != 0 || len(waiting["options"].([]any)) != 0 {
					t.Fatalf("partially seated table exposed a hand or action: %v", waiting)
				}
				expired := mahjongReferenceRead(t, board, "mahjong_entry_cancelled")
				if expired["room_id"] != roomID || expired["match_id"] != joined["match_id"] {
					t.Fatalf("board did not receive a scoped cancellation: %v", expired)
				}
				state := lobbyState(t, peers[0], "matched", 4, 0)
				if state["room_id"] != roomID || state["completed_rounds"] != float64(0) {
					t.Fatalf("expired entry must preserve the friend room and round number: %v", state)
				}
				for _, peer := range peers {
					lobbyCommand(t, peer, "ready", roomID, "", "", true)
				}
				lobbyState(t, peers[0], "playing", 4, 4)
				referenceSend(t, board, map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": "entry-0"})
				if retried := mahjongReferenceRead(t, board, "mahjong_joined"); retried["match_id"] == joined["match_id"] {
					t.Fatalf("readied retry retained the cancelled match: %v", retried)
				}
			} else {
				for _, peer := range peers {
					lobbyState(t, peer, "idle", 0, 0)
				}
			}
		})
	}
}

func TestMahjongLobbyReturnsToIdleAfterSettlement(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	observer, _ := fixture.connect(t)
	referenceSend(t, observer, map[string]any{"type": "mahjong_lobby_subscribe", "client_id": "mahjong-reference-0-0"})
	lobbyState(t, observer, "playing", 4, 4)
	gameRoom := fixture.hub.rooms[fixture.rooms[0]]
	gameRoom.mu.Lock()
	for step := 0; step < 120 && gameRoom.game.Phase != guiyang.PhaseFinished; step++ {
		gameRoom.game.Timeout()
	}
	gameRoom.finishIfNeededLocked(fixture.hub)
	gameRoom.mu.Unlock()
	lobbyState(t, observer, "idle", 0, 0)
}

func TestMahjongTurnTimeoutBoundsAndPhase(t *testing.T) {
	legacy, err := decodeMahjongRoomSettings(nil, "")
	if err != nil || legacy.EffectiveTurnTimeoutSeconds() != 15 {
		t.Fatalf("missing setting must use 15 seconds: %v %v", legacy, err)
	}
	for _, raw := range []any{float64(0), float64(-1), float64(61), 15.5, "60", nil} {
		if _, err := decodeMahjongRoomSettings(map[string]any{"turn_timeout_seconds": raw}, ""); err == nil {
			t.Errorf("accepted invalid turn timeout %v", raw)
		}
	}
	for _, seconds := range []int{1, 15, 37, 60} {
		settings, err := decodeMahjongRoomSettings(map[string]any{"turn_timeout_seconds": float64(seconds)}, "")
		if err != nil {
			t.Fatalf("%d seconds: %v", seconds, err)
		}
		game := &mahjongRoom{
			kind: matchmaking.MahjongFriend, assignment: matchmaking.MahjongAssignment{Settings: settings},
			game: &guiyang.Game{Phase: guiyang.PhaseTurn},
		}
		if got := game.actionTimeout(); got != time.Duration(seconds)*time.Second {
			t.Errorf("turn timeout was %s, want %d seconds", got, seconds)
		}
		game.game.Phase = guiyang.PhaseReaction
		if got := game.actionTimeout(); got != 15*time.Second {
			t.Errorf("reaction timeout changed to %s", got)
		}
	}
}

func TestMahjongLobbyFriendRoomPlaysAnotherRound(t *testing.T) {
	fixture := referenceMahjongServer(t, 0, 0)
	var accounts [4]string
	var lobby, firstGame, secondGame [4]*websocket.Conn
	for seat := range accounts {
		accounts[seat] = fmt.Sprintf("rematch-player-%d", seat)
		lobby[seat], _ = fixture.connect(t)
		referenceSend(t, lobby[seat], map[string]any{"type": "mahjong_lobby_subscribe", "client_id": accounts[seat]})
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	referenceSend(t, lobby[0], map[string]any{"type": "mahjong_lobby_command", "command_id": "create-timed-room",
		"action": "create", "rule_set_id": "guiyang", "rule_version": "2.0.0", "turn_timeout_seconds": 60})
	if created := lobbyRead(t, lobby[0], "mahjong_lobby_result", nil); created["ok"] != true {
		t.Fatalf("creating a 60-second room failed: %v", created)
	}
	waiting := lobbyState(t, lobby[0], "waiting", 1, 0)
	if waiting["turn_timeout_seconds"] != float64(60) {
		t.Fatalf("lobby omitted the room's 60-second time: %v", waiting)
	}
	roomID := waiting["room_id"].(string)
	for seat := 1; seat < 4; seat++ {
		lobbyCommand(t, lobby[seat], "join", roomID, "", "", true)
	}
	join := func(conn *websocket.Conn, seat int) {
		t.Helper()
		referenceSend(t, conn, map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": accounts[seat]})
		if joined := lobbyRead(t, conn, "mahjong_joined", nil); joined["your_seat"] != float64(seat) {
			t.Fatalf("seat %d changed: %v", seat, joined)
		}
	}
	playing := func(conn *websocket.Conn) map[string]any {
		t.Helper()
		state := lobbyRead(t, conn, "mahjong_state", func(message map[string]any) bool { return message["status"] == "playing" })
		deadline, _ := state["action_deadline_ms"].(float64)
		serverNow, _ := state["server_now_ms"].(float64)
		if state["action_timeout_seconds"] != float64(60) || state["turn_timeout_seconds"] != float64(60) ||
			deadline-serverNow < 55000 || deadline-serverNow > 60000 {
			t.Fatalf("wrong configured turn deadline: %v", state)
		}
		return state
	}
	settle := func() {
		t.Helper()
		fixture.hub.mu.Lock()
		gameRoom := fixture.hub.rooms[roomID]
		fixture.hub.mu.Unlock()
		gameRoom.mu.Lock()
		defer gameRoom.mu.Unlock()
		for step := 0; step < 120 && gameRoom.game.Phase != guiyang.PhaseFinished; step++ {
			gameRoom.game.Timeout()
		}
		if gameRoom.game.Phase != guiyang.PhaseFinished {
			t.Fatal("round did not reach legitimate settlement")
		}
		gameRoom.advanceLocked(fixture.hub)
	}
	for seat := range accounts {
		lobbyCommand(t, lobby[seat], "ready", roomID, "", "", true)
	}
	for seat := range accounts {
		firstGame[seat], _ = fixture.connect(t)
		join(firstGame[seat], seat)
	}
	first := playing(firstGame[0])
	playing(firstGame[2])
	_ = firstGame[2].Close()
	settle()
	for seat := range accounts {
		state := lobbyState(t, lobby[seat], "matched", 4, 0)
		if seat == 2 {
			firstGame[seat], _ = fixture.connect(t)
			referenceSend(t, firstGame[seat], map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": accounts[seat], "match_id": "stale-id"})
			lobbyRead(t, firstGame[seat], "mahjong_error", nil)
			referenceSend(t, firstGame[seat], map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": accounts[seat], "match_id": first["match_id"]})
			joined := lobbyRead(t, firstGame[seat], "mahjong_joined", nil)
			if joined["match_id"] != first["match_id"] || joined["your_seat"] != float64(seat) {
				t.Fatalf("settlement reconnect joined the wrong match or seat: %v", joined)
			}
		}
		finished := lobbyRead(t, firstGame[seat], "mahjong_state", func(message map[string]any) bool { return message["status"] == "finished" })
		if _, leaked := finished["hands"]; leaked || finished["your_seat"] != float64(seat) {
			t.Fatalf("settlement snapshot was not private for seat %d", seat)
		}
		if finished["can_rematch"] != true || state["room_id"] != roomID || state["start"] != false || state["completed_rounds"] != float64(1) || state["previous_match_id"] != first["match_id"] || finished["match_id"] != first["match_id"] || state["seat_index"] != float64(seat) || state["rule_set_id"] != "guiyang" || state["rule_version"] != "2.0.0" {
			t.Fatalf("seat %d did not return to same friend room: %v", seat, state)
		}
	}
	for seat := 0; seat < 3; seat++ {
		lobbyCommand(t, lobby[seat], "ready", roomID, "", "", true)
	}
	lobbyState(t, lobby[0], "matched", 4, 3)
	secondGame[0], _ = fixture.connect(t)
	referenceSend(t, secondGame[0], map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": accounts[0]})
	lobbyRead(t, secondGame[0], "mahjong_error", nil)
	lobbyCommand(t, lobby[3], "ready", roomID, "", "", true)
	lobbyState(t, lobby[0], "playing", 4, 4)
	referenceSend(t, secondGame[0], map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": accounts[0], "match_id": first["match_id"]})
	lobbyRead(t, secondGame[0], "mahjong_error", nil)
	for seat := range accounts {
		switch seat {
		case 0:
		case 3:
			secondGame[seat] = firstGame[seat] // An explicit join also works on the prior connection.
		default:
			secondGame[seat], _ = fixture.connect(t)
		}
		join(secondGame[seat], seat)
	}
	second := playing(secondGame[0])
	if second["match_id"] == "" || second["match_id"] == first["match_id"] || len(second["hand"].([]any)) != 14 || len(second["discards"].([]any)) != 0 || second["remaining"] != first["remaining"] {
		t.Fatalf("next round did not start with a fresh deal: %v", second)
	}
	for _, key := range []string{"hands", "wall", "seed"} {
		if _, leaked := second[key]; leaked {
			t.Fatalf("next round exposed %s", key)
		}
	}
	social := map[string]any{"type": "mahjong_social", "action": "chat", "message_id": "old-round", "quick_chat": "good_game"}
	referenceSend(t, firstGame[0], social)
	lobbyRead(t, firstGame[0], "mahjong_error", nil)
	move := map[string]any{"type": "mahjong_action", "command_id": "discard", "action": "play", "tile_id": second["hand"].([]any)[0].(map[string]any)["id"]}
	for _, conn := range []*websocket.Conn{firstGame[0], secondGame[0]} {
		move["match_id"] = first["match_id"]
		referenceSend(t, conn, move)
		if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != false {
			t.Fatalf("second round accepted a stale command: %v", result)
		}
	}
	move["match_id"] = second["match_id"]
	referenceSend(t, secondGame[0], move)
	if result := lobbyRead(t, secondGame[0], "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("second round rejected its own valid command: %v", result)
	}
	settle()
	state := lobbyState(t, lobby[0], "matched", 4, 0)
	if state["completed_rounds"] != float64(2) || state["previous_match_id"] != second["match_id"] {
		t.Fatalf("second settlement did not advance the completed round: %v", state)
	}
	fixture.hub.mu.Lock()
	finishedRoom := fixture.hub.rooms[roomID]
	fixture.hub.mu.Unlock()
	for _, conn := range secondGame {
		_ = conn.Close()
	}
	deadline := time.Now().Add(3 * time.Second)
	for {
		finishedRoom.mu.Lock()
		connected := len(finishedRoom.clients)
		finishedRoom.mu.Unlock()
		if connected == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("server did not release the disconnected sockets")
		}
		time.Sleep(time.Millisecond)
	}
	secondGame[0], _ = fixture.connect(t)
	restore := map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": accounts[0], "match_id": second["match_id"]}
	referenceSend(t, secondGame[0], restore)
	lobbyRead(t, secondGame[0], "mahjong_joined", nil)
	if restored := lobbyRead(t, secondGame[0], "mahjong_state", nil); restored["status"] != "finished" || restored["match_id"] != second["match_id"] || restored["action_deadline_ms"] != float64(0) {
		t.Fatalf("lost the finished round after all four sockets disconnected: %v", restored)
	}
	for seat := range accounts {
		lobbyCommand(t, lobby[seat], "leave", roomID, "", "", true)
		lobbyState(t, lobby[seat], "idle", 0, 0)
		if seat == 0 {
			lobbyState(t, lobby[1], "waiting", 3, 0)
			lobbyCommand(t, lobby[seat], "ready", roomID, "", "", false)
			referenceSend(t, secondGame[seat], social)
			lobbyRead(t, secondGame[seat], "mahjong_error", nil)
			referenceSend(t, secondGame[seat], restore)
			lobbyRead(t, secondGame[seat], "mahjong_error", nil)
		}
	}
	lobbyCommand(t, lobby[0], "join", roomID, "", "", false)
	fixture.hub.mu.Lock()
	_, retained := fixture.hub.rooms[roomID]
	fixture.hub.mu.Unlock()
	if retained {
		t.Fatal("empty friend room retained its old game despite every seat leaving")
	}
}

func TestMahjongLobbySettlementDoesNotWaitForStalledSubscriber(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	stalledConn, stalled := fixture.connect(t)
	healthy, _ := fixture.connect(t)
	for _, conn := range []*websocket.Conn{stalledConn, healthy} {
		referenceSend(t, conn, map[string]any{"type": "mahjong_lobby_subscribe", "client_id": "mahjong-reference-0-0"})
		lobbyState(t, conn, "playing", 4, 4)
	}
	// Hold the per-connection publication lock as a stalled write would, without
	// depending on OS socket-buffer sizes or filling the socket with test data.
	stalled.lobbyWriteMu.Lock()
	defer stalled.lobbyWriteMu.Unlock()
	gameRoom := fixture.hub.rooms[fixture.rooms[0]]
	settled := make(chan struct{})
	go func() {
		gameRoom.mu.Lock()
		defer gameRoom.mu.Unlock()
		for step := 0; step < 120 && gameRoom.game.Phase != guiyang.PhaseFinished; step++ {
			gameRoom.game.Timeout()
		}
		gameRoom.finishIfNeededLocked(fixture.hub)
		close(settled)
	}()
	select {
	case <-settled:
	case <-time.After(time.Second):
		t.Fatal("game settlement waited for a stalled lobby subscriber")
	}
	lobbyState(t, healthy, "idle", 0, 0)
}

func TestMahjongLobbyCommandResultPrecedesNewAssignment(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	conn := lobbySocket(t, server, accounts, "host")
	referenceSend(t, conn, map[string]any{
		"type": "mahjong_lobby_command", "command_id": "invite", "action": "create", "rule_set_id": "guiyang", "rule_version": "2.0.0",
	})
	var message map[string]any
	if err := conn.ReadJSON(&message); err != nil {
		t.Fatal(err)
	}
	if message["type"] != "mahjong_lobby_result" || message["command_id"] != "invite" || message["ok"] != true {
		t.Fatalf("expected the successful result before the room state, got %v", message)
	}
	state := lobbyState(t, conn, "waiting", 1, 0)
	confirmed, ok := message["state"].(map[string]any)
	if !ok || confirmed["status"] != "waiting" || confirmed["room_id"] != state["room_id"] {
		t.Fatalf("create receipt did not carry the confirmed room: %v", message)
	}
	referenceSend(t, conn, map[string]any{
		"type": "mahjong_lobby_command", "command_id": "release", "action": "leave", "room_id": state["room_id"],
	})
	message = lobbyRead(t, conn, "mahjong_lobby_result", nil)
	confirmed, ok = message["state"].(map[string]any)
	if message["command_id"] != "release" || message["ok"] != true || !ok || confirmed["status"] != "idle" || confirmed["room_id"] != "" {
		t.Fatalf("leave receipt did not release the seat: %v", message)
	}
}

func TestMahjongLobbyReceivesLegacyQuickAndCancelChanges(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	conn := lobbySocket(t, server, accounts, "legacy")
	post := func(route, body string, wantStatus int) {
		t.Helper()
		request, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/matchmaking/"+route, bytes.NewBufferString(body))
		if err != nil {
			t.Fatal(err)
		}
		request.Header = accounts.header(t, "legacy")
		response, err := server.Client().Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != wantStatus {
			t.Fatalf("%s: got %d want %d", route, response.StatusCode, wantStatus)
		}
	}
	post("quick", `{"account_id":"legacy","product_id":"xbd_mahjong","game_id":"mahjong","rule_set_id":"guiyang","rule_version":"unknown"}`, 400)
	post("quick", `{"account_id":"legacy","product_id":"xbd_mahjong","game_id":"mahjong","rule_set_id":"guiyang","rule_version":"2.0.0"}`, 200)
	lobbyState(t, conn, "waiting", 1, 0)
	post("cancel", `{"account_id":"legacy"}`, http.StatusOK)
	lobbyState(t, conn, "idle", 0, 0)
}
