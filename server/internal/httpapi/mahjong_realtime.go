package httpapi

import (
	"crypto/rand"
	"encoding/binary"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

const mahjongActionTimeout = 15 * time.Second

type mahjongHub struct {
	mu      sync.Mutex
	rooms   map[string]*mahjongRoom
	matches *matchmaking.Manager
}

type mahjongRoom struct {
	mu           sync.Mutex
	id           string
	game         *guiyang.Game
	clients      map[*mahjongClient]struct{}
	started      bool
	closed       bool
	timer        *time.Timer
	lastActionAt time.Time
}

type mahjongClient struct {
	wire      *chessClient // 共享同一 WebSocket 的写锁，避免消息帧交错。
	room      *mahjongRoom
	accountID string
	seat      int
}

func newMahjongHub(matches *matchmaking.Manager) *mahjongHub {
	return &mahjongHub{rooms: map[string]*mahjongRoom{}, matches: matches}
}

func newMahjongClient(wire *chessClient) *mahjongClient { return &mahjongClient{wire: wire, seat: -1} }

func (h *mahjongHub) handle(client *mahjongClient, message map[string]any) bool {
	switch message["type"] {
	case "mahjong_join":
		h.join(client, message)
		return true
	case "mahjong_action":
		h.action(client, message)
		return true
	default:
		return false
	}
}

func (c *mahjongClient) fail(message string) {
	_ = c.wire.writeJSON(map[string]any{"type": "mahjong_error", "message": message})
}

func (h *mahjongHub) roomFor(id string, players [4]string) *mahjongRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	if existing := h.rooms[id]; existing != nil {
		existing.mu.Lock()
		closed := existing.closed
		existing.mu.Unlock()
		if !closed {
			return existing
		}
	}
	var seedBytes [8]byte
	if _, err := rand.Read(seedBytes[:]); err != nil {
		binary.LittleEndian.PutUint64(seedBytes[:], uint64(time.Now().UnixNano()))
	}
	created := &mahjongRoom{
		id: id, game: guiyang.NewGame(players, int64(binary.LittleEndian.Uint64(seedBytes[:]))),
		clients: map[*mahjongClient]struct{}{},
	}
	h.rooms[id] = created
	return created
}

func (h *mahjongHub) join(client *mahjongClient, message map[string]any) {
	roomID, _ := message["room_id"].(string)
	accountID, _ := message["client_id"].(string)
	if roomID == "" || accountID == "" {
		client.fail("加入麻将房间必须提供 room_id 和 client_id")
		return
	}
	if h.matches == nil {
		client.fail("缺少权威匹配服务")
		return
	}
	seat, ok := h.matches.SeatIndexFor(roomID, accountID)
	if !ok || seat < 0 || seat >= 4 {
		client.fail("玩家不属于该麻将房间")
		return
	}
	players, ok := h.matches.MahjongPlayersFor(roomID)
	if !ok || players[seat] != accountID {
		client.fail("四人尚未准备完成或座位失效")
		return
	}
	room := h.roomFor(roomID, players)
	room.mu.Lock()
	defer room.mu.Unlock()
	if client.room != nil && client.room != room {
		client.fail("此连接已经加入其他麻将房间")
		return
	}
	for old := range room.clients {
		if old != client && old.seat == seat {
			delete(room.clients, old)
			_ = old.wire.conn.Close()
		}
	}
	client.room, client.accountID, client.seat = room, accountID, seat
	room.clients[client] = struct{}{}
	_ = client.wire.writeJSON(map[string]any{"type": "mahjong_joined", "room_id": roomID, "your_seat": seat})
	if !room.started && room.connectedSeats() == 4 {
		room.started = true
		room.lastActionAt = time.Now().UTC()
		room.scheduleTimeoutLocked(h)
	}
	room.broadcastLocked()
}

func (r *mahjongRoom) connectedSeats() int {
	seats := map[int]bool{}
	for client := range r.clients {
		seats[client.seat] = true
	}
	return len(seats)
}

func (h *mahjongHub) action(client *mahjongClient, message map[string]any) {
	room := client.room
	if room == nil {
		client.fail("尚未加入麻将房间")
		return
	}
	action, _ := message["action"].(string)
	tileID := 0
	if raw, exists := message["tile_id"]; exists {
		var ok bool
		tileID, ok = jsonInt(raw)
		if !ok {
			client.fail("tile_id 必须为整数")
			return
		}
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, connected := room.clients[client]; !connected {
		client.fail("连接已由新连接接管")
		return
	}
	if !room.started {
		client.fail("等待四位玩家连接")
		return
	}
	if err := room.game.Apply(client.seat, action, tileID); err != nil {
		client.fail(err.Error())
		return
	}
	room.lastActionAt = time.Now().UTC()
	room.scheduleTimeoutLocked(h)
	room.broadcastLocked()
	room.finishIfNeededLocked(h)
}

func (r *mahjongRoom) scheduleTimeoutLocked(h *mahjongHub) {
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
	if !r.started || r.game.Phase == guiyang.PhaseFinished {
		return
	}
	expectedEpoch := r.game.Epoch
	r.timer = time.AfterFunc(mahjongActionTimeout, func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		if r.closed || !r.started || r.game.Epoch != expectedEpoch {
			return
		}
		r.game.Timeout()
		r.lastActionAt = time.Now().UTC()
		r.scheduleTimeoutLocked(h)
		r.broadcastLocked()
		r.finishIfNeededLocked(h)
	})
}

func (r *mahjongRoom) broadcastLocked() {
	for client := range r.clients {
		state := r.game.SnapshotFor(client.seat)
		state["room_id"] = r.id
		state["status"] = "playing"
		if !r.started {
			state["status"] = "waiting"
		}
		if r.game.Phase == guiyang.PhaseFinished {
			state["status"] = "finished"
		}
		state["connected_players"] = r.connectedSeats()
		state["action_deadline_ms"] = r.lastActionAt.Add(mahjongActionTimeout).UnixMilli()
		_ = client.wire.writeJSON(state)
	}
}

func (r *mahjongRoom) finishIfNeededLocked(h *mahjongHub) {
	if r.closed || r.game.Phase != guiyang.PhaseFinished {
		return
	}
	r.closed = true
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
	h.matches.FinishRoom(r.id)
}

func (h *mahjongHub) disconnect(client *mahjongClient) {
	if client == nil || client.room == nil {
		return
	}
	room := client.room
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, exists := room.clients[client]; !exists {
		return
	}
	delete(room.clients, client)
	room.broadcastLocked()
}
