package httpapi

import (
	"fmt"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/gorilla/websocket"
)

func spectatorSocket(t *testing.T, server *httptest.Server, accounts *fixtureAccounts, id string) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/mahjong/ws", accounts.header(t, id))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	readUntilType(t, conn, "connected", nil)
	return conn
}

func spectatorLobbyCommand(t *testing.T, conn *websocket.Conn, action string, data map[string]any) map[string]any {
	t.Helper()
	data["type"], data["action"], data["command_id"] = "mahjong_lobby_command", action, action
	referenceSend(t, conn, data)
	return lobbyRead(t, conn, "mahjong_lobby_result", func(packet map[string]any) bool { return packet["command_id"] == action })
}

func spectatorCreate(t *testing.T, conn *websocket.Conn, data map[string]any) map[string]any {
	t.Helper()
	data["rule_set_id"], data["rule_version"] = "basic_108", "1.0.0"
	result := spectatorLobbyCommand(t, conn, "create", data)
	if result["ok"] != true {
		t.Fatalf("friend room creation failed: %v", result)
	}
	return result["state"].(map[string]any)
}

func spectatorPermission(t *testing.T, conn *websocket.Conn, roomID string, enabled, wantOK bool) map[string]any {
	t.Helper()
	result := spectatorLobbyCommand(t, conn, "set_spectator_permission", map[string]any{
		"room_id": roomID, "enabled": enabled, "watch_seat": 1,
	})
	if result["ok"] != wantOK {
		t.Fatalf("seat consent success did not equal %t: %v", wantOK, result)
	}
	return result
}

func spectatorRequest(t *testing.T, conn *websocket.Conn, roomID, accountID string, seat int, password string) {
	t.Helper()
	referenceSend(t, conn, map[string]any{
		"type": "mahjong_watch_join", "room_id": roomID, "client_id": accountID, "watch_seat": seat, "password": password,
	})
}

func TestMahjongSpectatorDefaultAndSeatConsent(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	host := lobbySocket(t, server, accounts, "host")
	peer := lobbySocket(t, server, accounts, "peer")
	observer := lobbySocket(t, server, accounts, "observer")
	defaultRoom := spectatorCreate(t, host, map[string]any{})
	packet := lobbyRead(t, host, "mahjong_lobby_state", func(packet map[string]any) bool {
		return packet["state"].(map[string]any)["status"] == "waiting"
	})
	if packet["spectator_supported"] != true {
		t.Fatalf("lobby capability missing: %v", packet)
	}
	defaultID := defaultRoom["room_id"].(string)
	if defaultRoom["allow_spectators"] != false {
		t.Fatalf("room unexpectedly allows spectators by default: %v", defaultRoom)
	}
	spectatorPermission(t, host, defaultID, true, false)
	lobbyCommand(t, host, "leave", defaultID, "", "", true)
	room := spectatorCreate(t, host, map[string]any{"allow_spectators": true})
	roomID := room["room_id"].(string)
	if room["allow_spectators"] != true || room["spectator_allowed"] != false {
		t.Fatalf("room setting unexpectedly gives consent: %v", room)
	}
	lobbyCommand(t, peer, "join", roomID, "", "", true)
	if response := spectatorLobbyCommand(t, observer, "watch", map[string]any{"room_id": roomID, "watch_seat": 0}); response["ok"] != false {
		t.Fatalf("watch admitted before seat consent: %v", response)
	}
	if state := spectatorPermission(t, host, roomID, true, true)["state"].(map[string]any); state["spectator_allowed"] != true {
		t.Fatalf("consent did not apply to the authenticated seat: %v", state)
	}
	referenceSend(t, observer, map[string]any{"type": "mahjong_room_directory", "open": true, "request_id": "available"})
	directory := lobbyRead(t, observer, "mahjong_lobby_state", func(packet map[string]any) bool {
		return packet["directory_request_id"] == "available"
	})
	row := directory["public_rooms"].([]any)[0].(map[string]any)
	if row["room_id"] != roomID || !reflect.DeepEqual(row["watchable_seats"], []any{float64(0)}) {
		t.Fatalf("opt in unexpectedly targeted a different seat: %v", row)
	}
	conn := spectatorSocket(t, server, accounts, "peer")
	spectatorRequest(t, conn, roomID, "peer", 0, "")
	if denied := readUntilType(t, conn, "mahjong_error", nil); denied["operation"] != "watch" {
		t.Fatalf("seated account joined a read-only slot: %v", denied)
	}
}

func TestMahjongSpectatorPasswordPreflightAndSocket(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	host := lobbySocket(t, server, accounts, "host")
	observer := lobbySocket(t, server, accounts, "observer")
	roomID := spectatorCreate(t, host, map[string]any{"allow_spectators": true, "password": "0317"})["room_id"].(string)
	spectatorPermission(t, host, roomID, true, true)
	for _, password := range []string{"", "7183", "0317"} {
		result := spectatorLobbyCommand(t, observer, "watch", map[string]any{"room_id": roomID, "watch_seat": 0, "password": password})
		if password == "0317" {
			if result["ok"] != true || result["state"].(map[string]any)["status"] != "idle" {
				t.Fatalf("preflight should keep the observer idle: %v", result)
			}
		} else if result["ok"] != false || result["code"] != "room_password_required" {
			t.Fatalf("wrong password outcome: %v", result)
		}
	}
	referenceSend(t, observer, map[string]any{"type": "mahjong_room_directory", "open": true, "request_id": "protected"})
	directory := lobbyRead(t, observer, "mahjong_lobby_state", func(packet map[string]any) bool {
		return packet["directory_request_id"] == "protected"
	})
	if rooms := directory["public_rooms"].([]any); len(rooms) != 0 {
		t.Fatalf("password room became public: %v", rooms)
	}
	conn := spectatorSocket(t, server, accounts, "observer")
	spectatorRequest(t, conn, roomID, "observer", 0, "7183")
	if response := readUntilType(t, conn, "mahjong_error", nil); response["operation"] != "watch" || response["code"] != "room_password_required" {
		t.Fatalf("socket accepted preflight as authorization: %v", response)
	}
	spectatorRequest(t, conn, roomID, "host", 0, "0317")
	readUntilType(t, conn, "mahjong_error", nil)
	spectatorRequest(t, conn, roomID, "observer", 0, "0317")
	lobbyRead(t, conn, "mahjong_watch_joined", nil)
}

func TestMahjongSpectatorOnlyOneSocketPerSeat(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	host := lobbySocket(t, server, accounts, "seat-owner")
	roomID := spectatorCreate(t, host, map[string]any{"allow_spectators": true})["room_id"].(string)
	spectatorPermission(t, host, roomID, true, true)
	for _, id := range []string{"watch-0", "watch-1"} {
		lobby := lobbySocket(t, server, accounts, id)
		if result := spectatorLobbyCommand(t, lobby, "watch", map[string]any{"room_id": roomID, "watch_seat": 0}); result["ok"] != true {
			t.Fatalf("preflight reserved the seat: %v", result)
		}
	}
	type outcome struct {
		conn *websocket.Conn
		kind any
		err  error
	}
	start, outcomes := make(chan struct{}), make(chan outcome, 2)
	for i := 0; i < 2; i++ {
		id := fmt.Sprintf("watch-%d", i)
		conn := spectatorSocket(t, server, accounts, id)
		go func() {
			<-start
			err := conn.WriteJSON(map[string]any{"type": "mahjong_watch_join", "room_id": roomID, "client_id": id, "watch_seat": 0})
			var packet map[string]any
			if err == nil {
				err = conn.ReadJSON(&packet)
			}
			outcomes <- outcome{conn: conn, kind: packet["type"], err: err}
		}()
	}
	close(start)
	var winner *websocket.Conn
	for i := 0; i < 2; i++ {
		got := <-outcomes
		if got.err != nil {
			t.Fatal(got.err)
		}
		switch got.kind {
		case "mahjong_watch_joined":
			if winner != nil {
				t.Fatal("two sockets reserved a single seat")
			}
			winner = got.conn
		case "mahjong_error":
		default:
			t.Fatalf("unexpected admission packet %v", got.kind)
		}
	}
	if winner == nil {
		t.Fatal("no spectator joined")
	}
	waiting := lobbyRead(t, winner, "mahjong_watch_state", nil)
	if waiting["status"] != "waiting" || !reflect.DeepEqual(waiting["occupied_seats"], []any{true, false, false, false}) {
		t.Fatalf("observer changed the room roster: %v", waiting)
	}
	for _, kind := range []string{"mahjong_lobby_subscribe", "mahjong_join", "mahjong_action", "mahjong_spectator_permission"} {
		referenceSend(t, winner, map[string]any{"type": kind, "room_id": roomID})
		if response := readUntilType(t, winner, "mahjong_error", nil); response["operation"] != "watch" {
			t.Fatalf("watching socket accepted %s: %v", kind, response)
		}
	}
	lobbyRead(t, host, "mahjong_lobby_state", func(packet map[string]any) bool {
		return packet["state"].(map[string]any)["spectator_occupied"] == true
	})
	_ = winner.Close()
	lobbyRead(t, host, "mahjong_lobby_state", func(packet map[string]any) bool {
		state := packet["state"].(map[string]any)
		return state["spectator_allowed"] == true && state["spectator_occupied"] == false
	})
	next := spectatorSocket(t, server, accounts, "replacement")
	spectatorRequest(t, next, roomID, "replacement", 0, "")
	lobbyRead(t, next, "mahjong_watch_joined", nil)
	spectatorPermission(t, host, roomID, false, true)
	lobbyRead(t, next, "mahjong_watch_ended", nil)
}

func TestMahjongSpectatorEndsWhenTargetSeatChanges(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	host := lobbySocket(t, server, accounts, "seat-zero")
	guest := lobbySocket(t, server, accounts, "seat-one")
	observer := lobbySocket(t, server, accounts, "onlooker")
	roomID := spectatorCreate(t, host, map[string]any{"allow_spectators": true, "room_id": "6836"})["room_id"].(string)
	lobbyCommand(t, guest, "join", roomID, "", "", true)
	spectatorPermission(t, guest, roomID, true, true)
	conn := spectatorSocket(t, server, accounts, "onlooker")
	spectatorRequest(t, conn, roomID, "onlooker", 1, "")
	lobbyRead(t, conn, "mahjong_watch_joined", nil)

	lobbyCommand(t, host, "leave", roomID, "", "", true)
	lobbyRead(t, conn, "mahjong_watch_ended", func(packet map[string]any) bool { return packet["room_id"] == roomID })
	if response := spectatorLobbyCommand(t, observer, "watch", map[string]any{"room_id": roomID, "watch_seat": 1}); response["ok"] != false {
		t.Fatalf("empty seat retained admission: %v", response)
	}
	next := spectatorSocket(t, server, accounts, "onlooker")
	spectatorRequest(t, next, roomID, "onlooker", 0, "")
	lobbyRead(t, next, "mahjong_watch_joined", nil)

	lobbyCommand(t, guest, "leave", roomID, "", "", true)
	lobbyRead(t, next, "mahjong_watch_ended", nil)
	reused := spectatorCreate(t, guest, map[string]any{"allow_spectators": true, "room_id": roomID})
	if reused["room_id"] != roomID || reused["spectator_allowed"] != false {
		t.Fatalf("reused room inherited consent: %v", reused)
	}
	if response := spectatorLobbyCommand(t, observer, "watch", map[string]any{"room_id": roomID, "watch_seat": 0}); response["ok"] != false {
		t.Fatalf("reused room admitted against old consent: %v", response)
	}
}

func TestMahjongSpectatorPublicStateHidesAllConcealedTiles(t *testing.T) {
	accounts := &fixtureAccounts{}
	app := buildServer(config.Config{}, nil, nil, accounts)
	server := httptest.NewServer(app.routes())
	defer server.Close()
	var peers [4]*websocket.Conn
	var ids [4]string
	for seat := range peers {
		ids[seat] = fmt.Sprintf("private-seat-%d", seat)
		peers[seat] = lobbySocket(t, server, accounts, ids[seat])
	}
	roomID := spectatorCreate(t, peers[0], map[string]any{"allow_spectators": true})["room_id"].(string)
	for _, peer := range peers[1:] {
		lobbyCommand(t, peer, "join", roomID, "", "", true)
	}
	for _, peer := range peers {
		lobbyCommand(t, peer, "ready", roomID, "", "", true)
	}
	for seat, peer := range peers {
		referenceSend(t, peer, map[string]any{"type": "mahjong_join", "room_id": roomID, "client_id": ids[seat]})
		lobbyRead(t, peer, "mahjong_joined", nil)
	}
	lobbyRead(t, peers[0], "mahjong_state", func(packet map[string]any) bool { return packet["status"] == "playing" })
	referenceSend(t, peers[0], map[string]any{"type": "mahjong_spectator_permission", "room_id": roomID, "enabled": true})
	private := lobbyRead(t, peers[0], "mahjong_state", func(packet map[string]any) bool { return packet["spectator_allowed"] == true })
	if private["allow_spectators"] != true || private["spectator_occupied"] != false {
		t.Fatalf("board permission acknowledgement is incomplete: %v", private)
	}

	app.mahjong.mu.Lock()
	r := app.mahjong.rooms[roomID]
	r.mu.Lock()
	// Inject a concealed kong with distinctive values to exercise the server's
	// wire projection without relying on a randomly dealt kong.
	r.game.Melds[0] = []guiyang.Meld{{Kind: "an_gang", FromSeat: 0, Tiles: []guiyang.Tile{
		{ID: 481, Suit: "tong", Rank: 1}, {ID: 482, Suit: "tong", Rank: 1},
		{ID: 483, Suit: "tong", Rank: 1}, {ID: 484, Suit: "tong", Rank: 1},
	}}}
	r.mu.Unlock()
	app.mahjong.mu.Unlock()
	watcher := spectatorSocket(t, server, accounts, "wide-view")
	spectatorRequest(t, watcher, roomID, "wide-view", 0, "")
	lobbyRead(t, watcher, "mahjong_watch_joined", nil)
	public := lobbyRead(t, watcher, "mahjong_watch_state", nil)
	for _, key := range []string{"hand", "hands", "drawn_tile_id", "last_discard", "options", "players", "player_account_ids", "egg_counts", "egg_deltas", "wall", "your_seat"} {
		if _, leaked := public[key]; leaked {
			t.Errorf("public state leaked %s", key)
		}
	}
	if public["status"] != "playing" || public["match_id"] != private["match_id"] ||
		!reflect.DeepEqual(public["hand_counts"], private["hand_counts"]) || !reflect.DeepEqual(public["player_names"], []any{
		"牌友 private-seat-0", "牌友 private-seat-1", "牌友 private-seat-2", "牌友 private-seat-3",
	}) {
		t.Fatalf("unexpected public state: %v", public)
	}
	tiles := public["melds"].([]any)[0].([]any)[0].(map[string]any)["tiles"].([]any)
	if len(tiles) != 4 {
		t.Fatalf("concealed kong did not show four tile backs: %v", tiles)
	}
	for _, raw := range tiles {
		tile := raw.(map[string]any)
		if tile["id"] != float64(0) || tile["rank"] != float64(0) || tile["suit"] != "" {
			t.Fatalf("concealed kong leaked a tile: %v", tile)
		}
	}
	lobbyRead(t, peers[0], "mahjong_state", func(packet map[string]any) bool { return packet["spectator_occupied"] == true })
	turn := int(private["turn"].(float64))
	turnState := private
	if turn != 0 {
		turnState = lobbyRead(t, peers[turn], "mahjong_state", func(packet map[string]any) bool { return packet["status"] == "playing" })
	}
	tileID := turnState["hand"].([]any)[0].(map[string]any)["id"]
	referenceSend(t, peers[turn], map[string]any{"type": "mahjong_action", "command_id": "spectated-discard", "action": "play", "tile_id": tileID})
	if result := lobbyRead(t, peers[turn], "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("observer prevented a seated action: %v", result)
	}
	changed := lobbyRead(t, watcher, "mahjong_watch_state", func(packet map[string]any) bool {
		return len(packet["discards"].([]any)) != 0
	})
	discard := changed["discards"].([]any)[0].(map[string]any)
	if discard["tile"].(map[string]any)["id"] != tileID || changed["epoch"].(float64) <= public["epoch"].(float64) {
		t.Fatalf("public action was not delivered: %v", changed)
	}

	r.mu.Lock()
	for i := 0; i < 220 && r.game.Phase != guiyang.PhaseFinished; i++ {
		r.game.Timeout()
	}
	r.advanceLocked(app.mahjong)
	r.mu.Unlock()
	lobbyRead(t, watcher, "mahjong_watch_state", func(packet map[string]any) bool { return packet["status"] == "finished" })
	lobbyRead(t, watcher, "mahjong_watch_ended", nil)
	snapshot := lobbyState(t, peers[0], "matched", 4, 0)
	if snapshot["spectator_allowed"] != true || snapshot["spectator_occupied"] != false {
		t.Fatalf("settlement did not release the occupied slot: %v", snapshot)
	}
}
