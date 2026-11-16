package httpapi

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
)

func presenceFixture(t *testing.T, grace time.Duration) (*fixtureAccounts, *httptest.Server) {
	t.Helper()
	accounts := &fixtureAccounts{}
	handler := &Server{
		accounts: accounts, mahjong: newMahjongHub(matchmaking.NewManager(room.NewManager())),
	}
	handler.mahjong.waitingGrace = grace
	server := httptest.NewServer(http.HandlerFunc(handler.mahjongWebSocket))
	t.Cleanup(server.Close)
	return accounts, server
}

func presenceSocket(t *testing.T, server *httptest.Server, accounts *fixtureAccounts, id string, wantStatus string) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/api/v1/mahjong/ws", accounts.header(t, id))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	referenceSend(t, conn, map[string]any{"type": "mahjong_lobby_subscribe", "client_id": id})
	lobbyRead(t, conn, "mahjong_lobby_state", func(message map[string]any) bool {
		return message["state"].(map[string]any)["status"] == wantStatus
	})
	return conn
}

func hasReconnectingAccount(message map[string]any, id string) bool {
	state := message["state"].(map[string]any)
	ids, _ := state["reconnecting_account_ids"].([]any)
	return slices.Contains(ids, any(id))
}

func TestMahjongWaitingPresenceMultipleSocketsAndReconnect(t *testing.T) {
	accounts, server := presenceFixture(t, 250*time.Millisecond)
	host := lobbySocket(t, server, accounts, "host")
	lobbyCommand(t, host, "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, host, "waiting", 1, 0)["room_id"].(string)
	friend := lobbySocket(t, server, accounts, "friend")
	lobbyCommand(t, friend, "join", roomID, "", "", true)
	lobbyState(t, host, "waiting", 2, 0)

	secondSocket := presenceSocket(t, server, accounts, "friend", "waiting")
	_ = friend.Close()

	// Expiry of a separate guest proves at least one full grace window passed.
	clock := lobbySocket(t, server, accounts, "clock")
	lobbyCommand(t, clock, "join", roomID, "", "", true)
	lobbyState(t, host, "waiting", 3, 0)
	_ = clock.Close()
	lobbyRead(t, host, "mahjong_lobby_state", func(message map[string]any) bool {
		return hasReconnectingAccount(message, "clock")
	})
	lobbyState(t, host, "waiting", 2, 0)

	_ = secondSocket.Close()
	lobbyRead(t, host, "mahjong_lobby_state", func(message map[string]any) bool {
		return hasReconnectingAccount(message, "friend")
	})
	reconnected := presenceSocket(t, server, accounts, "friend", "waiting")
	lobbyRead(t, host, "mahjong_lobby_state", func(message map[string]any) bool {
		return !hasReconnectingAccount(message, "friend")
	})

	clock = lobbySocket(t, server, accounts, "clock")
	lobbyCommand(t, clock, "join", roomID, "", "", true)
	lobbyState(t, host, "waiting", 3, 0)
	_ = clock.Close()
	lobbyState(t, host, "waiting", 2, 0)
	lobbyCommand(t, reconnected, "leave", roomID, "", "", true)
	lobbyState(t, host, "waiting", 1, 0)
}

func TestMahjongWaitingPresenceExpiresQuickSeat(t *testing.T) {
	accounts, server := presenceFixture(t, 200*time.Millisecond)
	first := lobbySocket(t, server, accounts, "first")
	second := lobbySocket(t, server, accounts, "second")
	lobbyCommand(t, first, "quick", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, first, "waiting", 1, 0)["room_id"].(string)
	lobbyCommand(t, second, "quick", "", "guiyang", "2.0.0", true)
	lobbyState(t, first, "waiting", 2, 0)
	_ = second.Close()
	lobbyRead(t, first, "mahjong_lobby_state", func(message map[string]any) bool {
		return hasReconnectingAccount(message, "second")
	})
	if state := lobbyState(t, first, "waiting", 1, 0); state["room_id"] != roomID {
		t.Fatalf("remaining player lost the waiting room after a peer expired: %v", state)
	}
	_ = presenceSocket(t, server, accounts, "second", "idle")
}

func TestMahjongWaitingPresenceDoesNotEvictPlayingAccount(t *testing.T) {
	accounts, server := presenceFixture(t, 200*time.Millisecond)
	host := lobbySocket(t, server, accounts, "host")
	lobbyCommand(t, host, "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, host, "waiting", 1, 0)["room_id"].(string)
	players := []*websocket.Conn{host}
	for seat := 1; seat < 4; seat++ {
		peer := lobbySocket(t, server, accounts, fmt.Sprintf("peer-%d", seat))
		lobbyCommand(t, peer, "join", roomID, "", "", true)
		players = append(players, peer)
	}
	for _, peer := range players {
		lobbyCommand(t, peer, "ready", roomID, "", "", true)
	}
	lobbyState(t, host, "playing", 4, 4)
	referenceSend(t, host, map[string]any{"type": "mahjong_join", "client_id": "host", "room_id": roomID})
	lobbyRead(t, host, "mahjong_joined", nil)
	lobbyRead(t, host, "mahjong_state", nil)
	_ = players[3].Close()

	// A quick room expiry provides an observable grace period before checking
	// that the friend table still belongs to the disconnected player.
	clock := lobbySocket(t, server, accounts, "clock")
	watcher := lobbySocket(t, server, accounts, "watcher")
	lobbyCommand(t, clock, "quick", "", "guiyang", "2.0.0", true)
	lobbyCommand(t, watcher, "quick", "", "guiyang", "2.0.0", true)
	lobbyState(t, watcher, "waiting", 2, 0)
	_ = clock.Close()
	lobbyState(t, watcher, "waiting", 1, 0)

	peer := presenceSocket(t, server, accounts, "peer-3", "playing")
	referenceSend(t, peer, map[string]any{"type": "mahjong_join", "client_id": "peer-3", "room_id": roomID})
	lobbyRead(t, peer, "mahjong_joined", nil)
}
