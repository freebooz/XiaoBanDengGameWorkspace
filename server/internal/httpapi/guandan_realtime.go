package httpapi

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/guandan"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"sync"
	"time"
)

const guandanActionTimeout = 30 * time.Second

type guandanHub struct {
	mu      sync.Mutex
	rooms   map[string]*guandanRoom
	matches *matchmaking.Manager
	monitor *monitorSignal
}
type guandanRoom struct {
	mu              sync.Mutex
	id              string
	game            *guandan.Game
	clients         map[*guandanClient]struct{}
	started, closed bool
	timer           *time.Timer
	lastActionAt    time.Time
	monitor         *monitorSignal
}
type guandanClient struct {
	wire         *chessClient
	room         *guandanRoom
	seat         int
	trainingGame *guandan.Game
}

func newGuandanHub(matches *matchmaking.Manager) *guandanHub {
	return &guandanHub{rooms: map[string]*guandanRoom{}, matches: matches}
}
func newGuandanClient(wire *chessClient) *guandanClient { return &guandanClient{wire: wire, seat: -1} }
func (c *guandanClient) fail(message string) {
	_ = c.wire.writeJSON(map[string]any{"type": "guandan_error", "message": message})
}
func guandanSeed() int64 {
	var seed [8]byte
	if _, err := rand.Read(seed[:]); err != nil {
		return time.Now().UnixNano()
	}
	return int64(binary.LittleEndian.Uint64(seed[:]))
}

func (h *guandanHub) handle(c *guandanClient, message map[string]any) bool {
	switch message["type"] {
	case "guandan_join":
		h.join(c, message)
	case "guandan_training_start":
		if c.room != nil {
			c.fail("房间对局中不能开启训练")
			return true
		}
		c.trainingGame = guandan.NewGame([4]string{"我", "电脑一", "我的搭档", "电脑二"}, guandanSeed())
		c.trainingGame.Turn = 0
		c.seat = 0
		c.sendTraining()
	case "guandan_action":
		h.action(c, message)
	default:
		return false
	}
	return true
}

func (h *guandanHub) roomFor(id string, players [4]string) *guandanRoom {
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
	created := &guandanRoom{id: id, game: guandan.NewGame(players, guandanSeed()), clients: map[*guandanClient]struct{}{}, monitor: h.monitor}
	h.rooms[id] = created
	return created
}

func (h *guandanHub) join(c *guandanClient, message map[string]any) {
	roomID, _ := message["room_id"].(string)
	accountID, _ := message["client_id"].(string)
	if h.matches == nil || roomID == "" || accountID == "" {
		c.fail("需要有效房间与账号")
		return
	}
	seat, ok := h.matches.SeatIndexFor(roomID, accountID)
	players, ready := h.matches.GuandanPlayersFor(roomID)
	if !ok || !ready || seat < 0 || seat >= 4 || players[seat] != accountID {
		c.fail("四人尚未准备完成或座位无效")
		return
	}
	room := h.roomFor(roomID, players)
	room.mu.Lock()
	defer room.mu.Unlock()
	if c.room != nil && c.room != room || c.trainingGame != nil {
		c.fail("此连接已经参加其他对局")
		return
	}
	for old := range room.clients {
		if old != c && old.seat == seat {
			delete(room.clients, old)
			_ = old.wire.conn.Close()
		}
	}
	c.room = room
	c.seat = seat
	room.clients[c] = struct{}{}
	_ = c.wire.writeJSON(map[string]any{"type": "guandan_joined", "room_id": roomID, "your_seat": seat})
	if !room.started && room.connectedSeats() == 4 {
		room.started = true
		room.lastActionAt = time.Now().UTC()
		room.scheduleLocked(h)
	}
	room.broadcastLocked()
}

func applyGuandanAction(g *guandan.Game, seat int, message map[string]any) error {
	action, _ := message["action"].(string)
	switch action {
	case "play":
		raw, ok := message["card_ids"].([]any)
		if !ok || len(raw) > 10 {
			return errors.New("card_ids须为最多10个编号的数组")
		}
		ids := []int{}
		for _, value := range raw {
			id, ok := jsonInt(value)
			if !ok {
				return errors.New("牌编号须为整数")
			}
			ids = append(ids, id)
		}
		return g.PlayCards(seat, ids)
	case "pass":
		return g.Pass(seat)
	case "tribute", "return":
		id, ok := jsonInt(message["card_id"])
		if !ok {
			return errors.New("牌编号须为整数")
		}
		if action == "tribute" {
			return g.SubmitTribute(seat, id)
		}
		return g.ReturnCard(seat, id)
	case "next_round":
		return g.ReadyNextRound(seat)
	case "leave":
		return g.Leave(seat)
	default:
		return errors.New("未知掼蛋动作")
	}
}

func (h *guandanHub) action(c *guandanClient, message map[string]any) {
	if c.trainingGame != nil {
		if message["action"] == "hint" {
			_ = c.wire.writeJSON(map[string]any{"type": "guandan_hint", "card_ids": c.trainingGame.SuggestedCards(0)})
			return
		}
		if err := applyGuandanAction(c.trainingGame, 0, message); err != nil {
			c.fail(err.Error())
			return
		}
		if message["action"] == "next_round" {
			for seat := 1; seat < 4 && c.trainingGame.Phase == guandan.PhaseRoundFinished; seat++ {
				_ = c.trainingGame.ReadyNextRound(seat)
			}
		}
		for steps := 0; steps < 1000; steps++ {
			pending := c.trainingGame.PendingSeats()
			bot := -1
			for _, seat := range pending {
				if seat != 0 {
					bot = seat
					break
				}
			}
			if bot < 0 {
				break
			}
			if err := c.trainingGame.AutoAction(bot); err != nil {
				c.fail(err.Error())
				break
			}
		}
		c.sendTraining()
		return
	}
	room := c.room
	if room == nil {
		c.fail("尚未加入掼蛋房间")
		return
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, ok := room.clients[c]; !ok {
		c.fail("连接已被新的连接接管")
		return
	}
	if !room.started && message["action"] != "leave" {
		c.fail("等待四名玩家连接")
		return
	}
	if message["action"] == "hint" {
		_ = c.wire.writeJSON(map[string]any{"type": "guandan_hint", "card_ids": room.game.SuggestedCards(c.seat)})
		return
	}
	if room.closed {
		c.fail("比赛已结束")
		return
	}
	if err := applyGuandanAction(room.game, c.seat, message); err != nil {
		c.fail(err.Error())
		return
	}
	room.lastActionAt = time.Now().UTC()
	room.scheduleLocked(h)
	room.broadcastLocked()
	room.finishLocked(h)
}

func (c *guandanClient) sendTraining() {
	state := c.trainingGame.SnapshotFor(0)
	state["room_id"] = "训练"
	state["status"] = "playing"
	state["connected_players"] = 4
	if c.trainingGame.Phase == guandan.PhaseFinished {
		state["status"] = "finished"
	}
	_ = c.wire.writeJSON(state)
}
func (r *guandanRoom) connectedSeats() int {
	seats := map[int]bool{}
	for c := range r.clients {
		seats[c.seat] = true
	}
	return len(seats)
}
func (r *guandanRoom) broadcastLocked() {
	r.monitor.notify()
	for c := range r.clients {
		state := r.game.SnapshotFor(c.seat)
		state["room_id"] = r.id
		state["status"] = "playing"
		if !r.started {
			state["status"] = "waiting"
		}
		if r.game.Phase == guandan.PhaseFinished {
			state["status"] = "finished"
		}
		state["connected_players"] = r.connectedSeats()
		state["action_deadline_ms"] = r.lastActionAt.Add(guandanActionTimeout).UnixMilli()
		_ = c.wire.writeJSON(state)
	}
}
func (r *guandanRoom) scheduleLocked(h *guandanHub) {
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
	if !r.started || r.closed || len(r.game.PendingSeats()) == 0 {
		return
	}
	epoch := r.game.Epoch
	r.timer = time.AfterFunc(guandanActionTimeout, func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		if r.closed || r.game.Epoch != epoch {
			return
		}
		pending := r.game.PendingSeats()
		for _, seat := range pending {
			_ = r.game.AutoAction(seat)
		}
		r.lastActionAt = time.Now().UTC()
		r.scheduleLocked(h)
		r.broadcastLocked()
		r.finishLocked(h)
	})
}
func (r *guandanRoom) finishLocked(h *guandanHub) {
	if r.closed || r.game.Phase != guandan.PhaseFinished {
		return
	}
	r.closed = true
	if r.timer != nil {
		r.timer.Stop()
	}
	h.matches.FinishRoom(r.id)
}
func (h *guandanHub) disconnect(c *guandanClient) {
	if c == nil || c.room == nil {
		return
	}
	r := c.room
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.clients, c)
	r.broadcastLocked()
}
