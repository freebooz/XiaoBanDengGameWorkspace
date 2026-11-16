package httpapi

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/gorilla/websocket"
)

func TestAdminMonitorStreamObservesLiveMahjong(t *testing.T) {
	accounts := &fixtureAccounts{}
	s := buildServer(config.Config{}, nil, nil, accounts)
	readToken := base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("r", 32)))
	reviewToken := base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("v", 32)))
	s.adminPrincipals = []adminPrincipal{
		{Name: "reader", Capabilities: []string{adminPlatformRead}, digest: sha256.Sum256([]byte(readToken))},
		{Name: "reviewer", Capabilities: []string{adminMahjongReview}, digest: sha256.Sum256([]byte(reviewToken))},
	}
	runtime := &Runtime{Handler: s.routes(), server: s}
	server := httptest.NewServer(runtime)
	defer server.Close()
	defer runtime.Drain()
	for _, path := range []string{"/api/v1/admin/monitor/snapshot", "/api/v1/admin/monitor/stream"} {
		for _, test := range []struct {
			header string
			code   int
		}{
			{"", http.StatusUnauthorized},
			{accounts.header(t, "guest").Get("Authorization"), http.StatusUnauthorized},
			{"Bearer " + reviewToken, http.StatusForbidden},
		} {
			req := httptest.NewRequest(http.MethodGet, path, nil)
			req.Header.Set("Authorization", test.header)
			result := httptest.NewRecorder()
			runtime.ServeHTTP(result, req)
			if result.Code != test.code || result.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("%s returned %d; want %d and no-store", path, result.Code, test.code)
			}
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 7*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+"/api/v1/admin/monitor/stream", nil)
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Authorization", "Bearer "+readToken)
	response, err := server.Client().Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK || !strings.HasPrefix(response.Header.Get("Content-Type"), "text/event-stream") || response.Header.Get("X-Accel-Buffering") != "no" {
		t.Fatalf("unexpected stream headers: %d %v", response.StatusCode, response.Header)
	}
	reader := bufio.NewReader(response.Body)
	initial := readMonitorTestState(t, reader, func(m monitorSnapshot) bool { return len(m.Players) == 0 })
	if len(initial.Lobbies) != 4 || len(initial.Rooms) != 0 || initial.Rooms == nil || initial.Services[1].Status != "unavailable" || initial.Services[2].Status != "unavailable" {
		t.Fatalf("empty state or dependency health is incorrect: %+v", initial)
	}

	host := lobbySocket(t, server, accounts, "monitor-host")
	defer host.Close()
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Players) == 1 && m.Players[0].Status == "lobby" && m.Players[0].Connected && m.Players[0].DisplayName == "牌友 monitor-host"
	})
	lobbyCommand(t, host, "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, host, "waiting", 1, 0)["room_id"].(string)
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].RoomID == roomID && m.Rooms[0].Players == 1 &&
			m.Rooms[0].Status == "waiting" && m.Rooms[0].ConnectedPlayers == 1
	})

	peers := []*websocket.Conn{host}
	for seat := 1; seat < 4; seat++ {
		peer := lobbySocket(t, server, accounts, fmt.Sprintf("monitor-peer-%d", seat))
		defer peer.Close()
		lobbyCommand(t, peer, "join", roomID, "", "", true)
		peers = append(peers, peer)
	}
	for _, peer := range peers {
		lobbyCommand(t, peer, "ready", roomID, "", "", true)
	}
	for _, peer := range peers {
		referenceSend(t, peer, map[string]any{"type": "mahjong_join", "room_id": roomID})
		lobbyRead(t, peer, "mahjong_joined", nil)
	}
	playing := readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].RoomID == roomID && m.Rooms[0].ConnectedPlayers == 4 &&
			m.Rooms[0].ReadyPlayers == 4 && m.Rooms[0].Status == "playing"
	})
	for _, player := range playing.Players {
		if player.Seat == nil || !player.Connected || player.Status != "playing" || player.RoomID != roomID {
			t.Fatalf("incorrect live seat: %+v", player)
		}
	}
	board := lobbyRead(t, host, "mahjong_state", func(message map[string]any) bool { return message["status"] == "playing" })
	turn := int(board["turn"].(float64))
	if turn != 0 {
		board = lobbyRead(t, peers[turn], "mahjong_state", func(message map[string]any) bool { return message["status"] == "playing" })
	}
	hand := board["hand"].([]any)
	referenceSend(t, peers[turn], map[string]any{
		"type": "mahjong_action", "action": "play", "tile_id": hand[0].(map[string]any)["id"],
		"command_id": "admin-monitor-discard", "match_id": board["match_id"],
	})
	if result := lobbyRead(t, peers[turn], "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("discard rejected: %v", result)
	}
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].UpdatedAt.After(playing.Rooms[0].UpdatedAt)
	})
	_ = peers[3].Close()
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		if len(m.Rooms) != 1 || m.Rooms[0].ConnectedPlayers != 3 {
			return false
		}
		for _, player := range m.Players {
			if player.AccountID == "monitor-peer-3" {
				return !player.Connected && player.Status == "reconnecting" && player.Seat != nil && *player.Seat == 3
			}
		}
		return false
	})
	guest := lobbySocket(t, server, accounts, "monitor-guest")
	defer guest.Close()
	lobbyCommand(t, guest, "create", "", "guiyang", "2.0.0", true)
	id := lobbyState(t, guest, "waiting", 1, 0)["room_id"].(string)
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool { return len(m.Rooms) == 2 })
	lobbyCommand(t, guest, "leave", id, "", "", true)
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool { return len(m.Rooms) == 1 && m.Rooms[0].RoomID == roomID })
	runtime.Drain()
	if _, err := reader.ReadByte(); !errors.Is(err, io.EOF) {
		t.Fatalf("stream did not close on drain: %v", err)
	}
}

func readMonitorTestState(t *testing.T, reader *bufio.Reader, match func(monitorSnapshot) bool) monitorSnapshot {
	t.Helper()
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("waiting for monitor state: %v", err)
		}
		data, isData := strings.CutPrefix(line, "data: ")
		if !isData {
			continue
		}
		var snap monitorSnapshot
		decoder := json.NewDecoder(strings.NewReader(data))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&snap); err != nil {
			t.Fatalf("monitor emitted fields outside its contract: %v", err)
		}
		// Consume the closing empty SSE line so drain can assert EOF cleanly.
		if end, err := reader.ReadString('\n'); end != "\n" || err != nil {
			t.Fatalf("incomplete monitor event: %q, %v", end, err)
		}
		if match(snap) {
			return snap
		}
	}
}
