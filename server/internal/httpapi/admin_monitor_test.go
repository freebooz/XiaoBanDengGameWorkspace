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
	creation := spectatorLobbyCommand(t, host, "create", map[string]any{
		"rule_set_id": "guiyang", "rule_version": "2.0.0", "round_limit": 8, "allow_spectators": true,
	})
	if creation["ok"] != true {
		t.Fatalf("create monitored friend room: %v", creation)
	}
	roomID := lobbyState(t, host, "waiting", 1, 0)["room_id"].(string)
	waiting := readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].RoomID == roomID && m.Rooms[0].Players == 1 &&
			m.Rooms[0].Status == "waiting" && m.Rooms[0].ConnectedPlayers == 1
	})
	room := waiting.Rooms[0]
	if room.RoomGeneration == "" || room.Mahjong == nil || room.Mahjong.RoundNumber != 1 || room.Mahjong.RoundLimit != 8 ||
		room.Mahjong.AdmissionPaused || room.Mahjong.Turn != nil || room.Mahjong.RemainingTiles != nil ||
		waiting.Players[0].RoomGeneration != room.RoomGeneration {
		t.Fatalf("incorrect room wait phase metadata: %+v %+v", room, room.Mahjong)
	}
	spectatorPermission(t, host, roomID, true, true)
	watcher := spectatorSocket(t, server, accounts, "monitor-watcher")
	spectatorRequest(t, watcher, roomID, "monitor-watcher", 0, "")
	lobbyRead(t, watcher, "mahjong_watch_joined", nil)
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].Mahjong.SpectatorCount == 1 && m.Rooms[0].ConnectedPlayers == 1
	})
	_ = watcher.Close()
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].Mahjong.SpectatorCount == 0
	})
	lobbyCommand(t, host, "ready", roomID, "", "", true)
	readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		if len(m.Rooms) != 1 || m.Rooms[0].ReadyPlayers != 1 || len(m.Players) != 1 || !m.Players[0].Connected {
			return false
		}
		return m.Players[0].Status == "ready" && m.Players[0].RoomID == roomID
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
	active := playing.Rooms[0].Mahjong
	if active.MatchID != board["match_id"] || active.Dealer == nil || float64(*active.Dealer) != board["dealer"] ||
		active.Turn == nil || float64(*active.Turn) != board["turn"] ||
		active.RemainingTiles == nil || float64(*active.RemainingTiles) != board["remaining"] ||
		active.ActionDeadlineMS == 0 || float64(active.ActionDeadlineMS) != board["action_deadline_ms"] ||
		active.CanSetAdmission || playing.Rooms[0].RoomGeneration != room.RoomGeneration {
		t.Fatalf("monitor and board disagree about opening: %+v vs %v", active, board)
	}
	turn := int(board["turn"].(float64))
	if turn != 0 {
		board = lobbyRead(t, peers[turn], "mahjong_state", func(message map[string]any) bool { return message["status"] == "playing" })
	}
	played := board["hand"].([]any)[0].(map[string]any)
	referenceSend(t, peers[turn], map[string]any{
		"type": "mahjong_action", "action": "play", "tile_id": played["id"],
		"command_id": "admin-monitor-discard", "match_id": board["match_id"],
	})
	if result := lobbyRead(t, peers[turn], "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("discard rejected: %v", result)
	}
	afterDiscard := readMonitorTestState(t, reader, func(m monitorSnapshot) bool {
		return len(m.Rooms) == 1 && m.Rooms[0].Mahjong.LastDiscard != nil
	})
	discard := afterDiscard.Rooms[0].Mahjong.LastDiscard
	if discard.Seat != turn || discard.Suit != played["suit"] || float64(discard.Rank) != played["rank"] ||
		!afterDiscard.Rooms[0].UpdatedAt.After(playing.Rooms[0].UpdatedAt) {
		t.Fatalf("monitor projected the wrong last discard: %+v", discard)
	}
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

func TestAdminMonitorCanceledProbeKeepsSharedHealthUncached(t *testing.T) {
	s := buildServer(config.Config{}, nil, nil, &fixtureAccounts{})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	s.monitorServices(ctx)
	if !s.monitor.health[0].CheckedAt.IsZero() {
		t.Fatal("canceled monitor request populated shared health cache")
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
