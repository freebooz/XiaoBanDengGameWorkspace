package httpapi

import (
	"net/http/httptest"
	"testing"
)

func TestMahjongRoomDirectoryAndAdmission(t *testing.T) {
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()
	host := lobbySocket(t, server, accounts, "directory-host")
	viewer := lobbySocket(t, server, accounts, "directory-viewer")
	private := lobbySocket(t, server, accounts, "directory-private")
	send := func(action, id string, details map[string]any) map[string]any {
		packet := map[string]any{"type": "mahjong_lobby_command", "action": action, "command_id": id}
		for key, value := range details {
			packet[key] = value
		}
		conn := host
		if action == "join" || id == "collision" {
			conn = viewer
		} else if id == "private" {
			conn = private
		}
		referenceSend(t, conn, packet)
		return lobbyRead(t, conn, "mahjong_lobby_result", func(message map[string]any) bool { return message["command_id"] == id })
	}
	readDirectory := func(count int, requestID string) []any {
		packet := lobbyRead(t, viewer, "mahjong_lobby_state", func(message map[string]any) bool {
			rooms, ok := message["public_rooms"].([]any)
			return ok && len(rooms) == count
		})
		if packet["room_directory_requests"] != true || packet["directory_request_id"] != requestID {
			t.Fatalf("room directory did not acknowledge request %q: %v", requestID, packet)
		}
		return packet["public_rooms"].([]any)
	}
	referenceSend(t, viewer, map[string]any{"type": "mahjong_room_directory", "open": true, "request_id": "first"})
	readDirectory(0, "first")
	if result := send("create", "private", map[string]any{"rule_set_id": "guiyang", "rule_version": "2.0.0", "room_id": "6832", "round_limit": 16, "password": "0190"}); result["ok"] != true {
		t.Fatalf("private create failed: %v", result)
	}
	if result := send("create", "collision", map[string]any{"rule_set_id": "guiyang", "rule_version": "2.0.0", "room_id": "6832"}); result["ok"] != false {
		t.Fatal("server allocated an occupied room number")
	}
	if result := send("create", "public", map[string]any{"rule_set_id": "basic_108", "rule_version": "1.0.0", "room_id": "7158", "round_limit": 8}); result["ok"] != true {
		t.Fatalf("public create failed: %v", result)
	}
	row := readDirectory(1, "first")[0].(map[string]any)
	if row["room_id"] != "7158" || row["players"] != float64(1) || row["capacity"] != float64(4) || row["round_limit"] != float64(8) || row["joinable"] != true || row["rule_set_id"] != "basic_108" {
		t.Fatalf("unexpected public room: %v", row)
	}
	for _, secret := range []string{"password", "password_hash", "player_account_ids"} {
		if _, exposed := row[secret]; exposed {
			t.Errorf("public room exposed %s", secret)
		}
	}
	lobbyCommand(t, host, "leave", "7158", "", "", true)
	readDirectory(0, "first")
	referenceSend(t, viewer, map[string]any{"type": "mahjong_room_directory", "open": true, "request_id": "refresh"})
	readDirectory(0, "refresh")
	if result := send("join", "closed", map[string]any{"room_id": "7158"}); result["ok"] != false || result["code"] != "room_not_found" {
		t.Fatalf("closed room did not return a typed error: %v", result)
	}
	for _, password := range []string{"", "0000", "0190"} {
		result := send("join", "join-"+password, map[string]any{"room_id": "6832", "password": password})
		if result["ok"] != (password == "0190") {
			t.Fatal("protected room admission did not check its password")
		}
	}
	state := lobbyState(t, viewer, "waiting", 2, 0)
	if state["room_id"] != "6832" || state["round_limit"] != float64(16) {
		t.Fatalf("wrong admission snapshot: %v", state)
	}
}
