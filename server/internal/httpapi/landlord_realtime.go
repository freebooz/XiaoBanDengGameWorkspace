package httpapi

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/landlord"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

const landlordActionTimeout = 30 * time.Second

var landlordQuickChats = map[string]string{
	"hello":       "大家好，很高兴一起玩！",
	"hurry":       "快点吧，我等到花儿都谢了！",
	"well_played": "这手牌打得漂亮！",
	"thanks":      "谢谢！",
	"good_game":   "好牌，好局！",
}
var landlordEmotes = map[string]bool{"smile": true, "laugh": true, "thumbs_up": true, "cry": true, "angry": true}
var landlordProps = map[string]bool{"flower": true, "egg": true, "tomato": true, "cheers": true}

type landlordHub struct {
	mu      sync.Mutex
	rooms   map[string]*landlordRoom
	matches *matchmaking.Manager
	monitor *monitorSignal
}
type landlordRoom struct {
	mu              sync.Mutex
	id              string
	game            *landlord.Game
	clients         map[*landlordClient]struct{}
	started, closed bool
	timer           *time.Timer
	lastActionAt    time.Time
	social          [3]landlordSocialBudget
	monitor         *monitorSignal
}
type landlordClient struct {
	trainingMu       sync.Mutex
	wire             *chessClient
	room             *landlordRoom
	accountID        string
	seat             int
	trainingGame     *landlord.Game
	trainingTimer    *time.Timer
	trainingDeadline time.Time
	disconnected     bool
	social           landlordSocialBudget
}

type landlordSocialBudget struct {
	mu     sync.Mutex
	lastAt time.Time
	ids    map[string]time.Time
}

func newLandlordHub(matches *matchmaking.Manager) *landlordHub {
	return &landlordHub{rooms: map[string]*landlordRoom{}, matches: matches}
}
func newLandlordClient(wire *chessClient) *landlordClient {
	return &landlordClient{wire: wire, seat: -1}
}
func (c *landlordClient) fail(message string) {
	_ = c.wire.writeJSON(map[string]any{"type": "landlord_error", "message": message})
}

func (h *landlordHub) handle(client *landlordClient, message map[string]any) bool {
	switch message["type"] {
	case "landlord_join":
		client.wire.conn.SetReadLimit(256 * 1024)
		h.join(client, message)
		return true
	case "landlord_training_start":
		client.wire.conn.SetReadLimit(256 * 1024)
		h.startTraining(client)
		return true
	case "landlord_action":
		h.action(client, message)
		return true
	case "landlord_social":
		h.social(client, message)
		return true
	}
	return false
}

func (h *landlordHub) roomFor(id string, players [3]string, versions ...string) *landlordRoom {
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
	var seed [8]byte
	if _, err := rand.Read(seed[:]); err != nil {
		binary.LittleEndian.PutUint64(seed[:], uint64(time.Now().UnixNano()))
	}
	created := &landlordRoom{id: id, game: landlord.NewGame(players, int64(binary.LittleEndian.Uint64(seed[:]))), clients: map[*landlordClient]struct{}{}, monitor: h.monitor}
	// Old callers and immutable 1.0.0 rooms keep the original bid -> play rules.
	created.game.EnableDoubling = len(versions) > 0 && versions[0] == landlord.RuleVersionDoubling
	h.rooms[id] = created
	return created
}

func (h *landlordHub) join(client *landlordClient, message map[string]any) {
	client.trainingMu.Lock()
	training := client.trainingGame != nil
	client.trainingMu.Unlock()
	if training {
		client.fail("训练连接不能同时加入房间")
		return
	}
	roomID, _ := message["room_id"].(string)
	accountID, _ := message["client_id"].(string)
	if roomID == "" || accountID == "" {
		client.fail("加入斗地主房间需要 room_id 和 client_id")
		return
	}
	if h.matches == nil {
		client.fail("缺少权威匹配服务")
		return
	}
	seat, ok := h.matches.SeatIndexFor(roomID, accountID)
	players, ready := h.matches.LandlordPlayersFor(roomID)
	if !ok || !ready || seat < 0 || seat >= 3 || players[seat] != accountID {
		client.fail("三人尚未准备完成或座位无效")
		return
	}
	version, valid := h.matches.RuleVersionFor(roomID)
	if !valid || (version != landlord.RuleVersionLegacy && version != landlord.RuleVersionDoubling) {
		client.fail("房间规则版本无效或尚不支持")
		return
	}
	room := h.roomFor(roomID, players, version)
	room.mu.Lock()
	defer room.mu.Unlock()
	if client.room != nil && client.room != room {
		client.fail("此连接已经加入其他房间")
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
	_ = client.wire.writeJSON(map[string]any{"type": "landlord_joined", "room_id": roomID, "your_seat": seat})
	if !room.started && room.connectedSeats() == 3 {
		room.started = true
		room.lastActionAt = time.Now().UTC()
		room.scheduleTimeoutLocked(h)
	}
	room.broadcastLocked()
}

// validateLandlordSocial builds a fresh allowlisted payload; client-supplied seat,
// room, display text and unrelated fields never pass into a broadcast.
func validateLandlordSocial(message map[string]any) (map[string]any, error) {
	id, ok := message["message_id"].(string)
	if !ok || len(id) == 0 || len(id) > 64 {
		return nil, errors.New("互动消息需要有效 message_id")
	}
	for _, value := range id {
		if !(value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value >= '0' && value <= '9' || value == '-' || value == '_') {
			return nil, errors.New("message_id 仅允许字母、数字、横线和下划线")
		}
	}
	action, _ := message["action"].(string)
	event := map[string]any{"type": "landlord_social", "action": action, "message_id": id}
	switch action {
	case "chat":
		key, _ := message["quick_chat"].(string)
		text, valid := landlordQuickChats[key]
		if !valid {
			return nil, errors.New("请选择预置快捷聊天")
		}
		event["quick_chat"], event["text"] = key, text
	case "emote":
		key, _ := message["emote"].(string)
		if !landlordEmotes[key] {
			return nil, errors.New("未知表情")
		}
		event["emote"] = key
	case "prop":
		key, _ := message["prop"].(string)
		seat, valid := jsonInt(message["target_seat"])
		if !landlordProps[key] || !valid || seat < 0 || seat >= 3 {
			return nil, errors.New("道具或目标座位无效")
		}
		event["prop"], event["target_seat"] = key, seat
	case "voice":
		rate, valid := jsonInt(message["sample_rate"])
		if !valid || (rate != 8000 && rate != 16000) {
			return nil, errors.New("语音须为 8000 或 16000Hz 单声道 PCM16")
		}
		duration, valid := jsonInt(message["duration_ms"])
		if !valid || duration < 100 || duration > 5000 {
			return nil, errors.New("语音时长须为 100 到 5000 毫秒")
		}
		if raw, supplied := message["channels"]; supplied {
			channels, valid := jsonInt(raw)
			if !valid || channels != 1 {
				return nil, errors.New("语音仅支持单声道")
			}
		}
		if raw, supplied := message["format"]; supplied && raw != "pcm_s16le" {
			return nil, errors.New("语音仅支持 PCM16LE")
		}
		encoded, valid := message["pcm_base64"].(string)
		maximum := rate * 10 // five seconds, two bytes per sample
		if !valid || len(encoded) == 0 || len(encoded) > base64.StdEncoding.EncodedLen(maximum) {
			return nil, errors.New("语音载荷过大或为空")
		}
		pcm, err := base64.StdEncoding.Strict().DecodeString(encoded)
		if err != nil || len(pcm)%2 != 0 || len(pcm) < rate/5 || len(pcm) > maximum || len(pcm)*500/rate != duration {
			return nil, errors.New("语音编码、采样长度或时长不匹配")
		}
		event["sample_rate"], event["duration_ms"], event["pcm_base64"] = rate, duration, base64.StdEncoding.EncodeToString(pcm)
		event["channels"], event["format"] = 1, "pcm_s16le"
	default:
		return nil, errors.New("未知互动动作")
	}
	return event, nil
}

func (b *landlordSocialBudget) accept(event map[string]any, now time.Time) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.ids == nil {
		b.ids = map[string]time.Time{}
	}
	for id, sent := range b.ids {
		if now.Sub(sent) >= 2*time.Minute {
			delete(b.ids, id)
		}
	}
	id := event["message_id"].(string)
	if _, repeated := b.ids[id]; repeated {
		return errors.New("重复互动消息已忽略")
	}
	if now.Sub(b.lastAt) < time.Second || len(b.ids) >= 128 {
		return errors.New("互动过于频繁，请稍后再试")
	}
	b.lastAt, b.ids[id] = now, now
	return nil
}

func (h *landlordHub) social(client *landlordClient, message map[string]any) {
	event, err := validateLandlordSocial(message)
	if err != nil {
		client.fail(err.Error())
		return
	}
	client.trainingMu.Lock()
	if client.trainingGame != nil {
		defer client.trainingMu.Unlock()
		if client.disconnected {
			client.fail("连接已关闭")
			return
		}
		now := time.Now().UTC()
		if err := client.social.accept(event, now); err != nil {
			client.fail(err.Error())
			return
		}
		event["seat"], event["room_id"], event["server_now_ms"] = 0, "训练", now.UnixMilli()
		_ = client.wire.writeJSON(event)
		return
	}
	client.trainingMu.Unlock()
	room := client.room
	if room == nil {
		client.fail("尚未加入斗地主房间")
		return
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, active := room.clients[client]; !active || client.seat < 0 || client.seat >= 3 || room.game.Players[client.seat] != client.accountID {
		client.fail("连接已由新连接接管或座位无效")
		return
	}
	now := time.Now().UTC()
	// The room owns each seat's budget so reconnecting cannot replay or flood events.
	if err := room.social[client.seat].accept(event, now); err != nil {
		client.fail(err.Error())
		return
	}
	event["seat"], event["room_id"], event["server_now_ms"] = client.seat, room.id, now.UnixMilli()
	for peer := range room.clients {
		if peer.room == room && peer.seat >= 0 && peer.seat < 3 && room.game.Players[peer.seat] == peer.accountID {
			_ = peer.wire.writeJSON(event)
		}
	}
}

func (r *landlordRoom) connectedSeats() int {
	seats := map[int]bool{}
	for client := range r.clients {
		seats[client.seat] = true
	}
	return len(seats)
}

func (h *landlordHub) action(client *landlordClient, message map[string]any) {
	client.trainingMu.Lock()
	training := client.trainingGame != nil
	client.trainingMu.Unlock()
	if training {
		h.trainingAction(client, message)
		return
	}
	room := client.room
	if room == nil {
		client.fail("尚未加入斗地主房间")
		return
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, ok := room.clients[client]; !ok {
		client.fail("连接已由新连接接管")
		return
	}
	if !room.started {
		client.fail("等待三位玩家连接")
		return
	}
	if room.game.Phase == landlord.PhaseFinished {
		client.fail("本局已经结束")
		return
	}
	action, _ := message["action"].(string)
	var err error
	switch action {
	case "hint":
		if room.game.Phase != landlord.PhasePlay || room.game.Turn != client.seat {
			client.fail("现在不是你的出牌回合")
			return
		}
		_ = client.wire.writeJSON(map[string]any{"type": "landlord_hint", "card_ids": room.game.SuggestedCards(client.seat)})
		return
	case "double":
		enabled, valid := message["enabled"].(bool)
		if !valid {
			client.fail("加倍选择须为布尔值")
			return
		}
		err = room.game.Double(client.seat, enabled)
	case "bid":
		amount, valid := jsonInt(message["amount"])
		if !valid {
			client.fail("叫分须为整数")
			return
		}
		err = room.game.Bid(client.seat, amount)
	case "play":
		raw, valid := message["card_ids"].([]any)
		if !valid {
			client.fail("card_ids 须为数组")
			return
		}
		ids := make([]int, 0, len(raw))
		for _, value := range raw {
			id, ok := jsonInt(value)
			if !ok {
				client.fail("牌编号须为整数")
				return
			}
			ids = append(ids, id)
		}
		err = room.game.PlayCards(client.seat, ids)
	case "pass":
		err = room.game.Pass(client.seat)
	default:
		client.fail("未知动作")
		return
	}
	if err != nil {
		client.fail(err.Error())
		return
	}
	room.lastActionAt = time.Now().UTC()
	room.scheduleTimeoutLocked(h)
	room.broadcastLocked()
	room.finishIfNeededLocked(h)
}

func (h *landlordHub) startTraining(client *landlordClient) {
	client.trainingMu.Lock()
	defer client.trainingMu.Unlock()
	if client.room != nil {
		client.fail("房间对局中不能开启训练")
		return
	}
	var seed [8]byte
	if _, err := rand.Read(seed[:]); err != nil {
		binary.LittleEndian.PutUint64(seed[:], uint64(time.Now().UnixNano()))
	}
	client.trainingGame = landlord.NewGame([3]string{"我", "电脑一", "电脑二"}, int64(binary.LittleEndian.Uint64(seed[:])))
	client.trainingGame.EnableDoubling = true
	client.seat = 0
	client.disconnected = false
	client.scheduleTrainingTimeoutLocked(h)
	client.sendTraining()
}

func (c *landlordClient) sendTraining() {
	state := c.trainingGame.SnapshotFor(0)
	state["room_id"] = "训练"
	state["status"] = "playing"
	if c.trainingGame.Phase == landlord.PhaseFinished {
		state["status"] = "finished"
	}
	state["connected_players"] = 3
	state["action_timeout_seconds"] = int(landlordActionTimeout / time.Second)
	state["server_now_ms"] = time.Now().UTC().UnixMilli()
	state["action_deadline_ms"] = int64(0)
	if c.trainingGame.Phase != landlord.PhaseFinished {
		state["action_deadline_ms"] = c.trainingDeadline.UnixMilli()
	}
	_ = c.wire.writeJSON(state)
}

func (h *landlordHub) trainingAction(client *landlordClient, message map[string]any) {
	client.trainingMu.Lock()
	defer client.trainingMu.Unlock()
	g := client.trainingGame
	if g == nil {
		return
	}
	action, _ := message["action"].(string)
	var err error
	switch action {
	case "hint":
		if g.Phase != landlord.PhasePlay || g.Turn != 0 {
			client.fail("现在不是你的出牌回合")
			return
		}
		_ = client.wire.writeJSON(map[string]any{"type": "landlord_hint", "card_ids": g.SuggestedCards(0)})
		return
	case "double":
		enabled, valid := message["enabled"].(bool)
		if !valid {
			client.fail("加倍选择须为布尔值")
			return
		}
		err = g.Double(0, enabled)
	case "bid":
		amount, ok := jsonInt(message["amount"])
		if !ok {
			client.fail("叫分须为整数")
			return
		}
		err = g.Bid(0, amount)
	case "pass":
		err = g.Pass(0)
	case "play":
		raw, ok := message["card_ids"].([]any)
		if !ok {
			client.fail("card_ids 须为数组")
			return
		}
		ids := make([]int, 0, len(raw))
		for _, v := range raw {
			id, valid := jsonInt(v)
			if !valid {
				client.fail("牌编号须为整数")
				return
			}
			ids = append(ids, id)
		}
		err = g.PlayCards(0, ids)
	default:
		client.fail("未知动作")
		return
	}
	if err != nil {
		client.fail(err.Error())
		return
	}
	for steps := 0; steps < 4 && g.Phase != landlord.PhaseFinished && g.Turn != 0; steps++ {
		if err := g.BotTurn(g.Turn); err != nil {
			break
		}
	}
	client.scheduleTrainingTimeoutLocked(h)
	client.sendTraining()
}

func (c *landlordClient) scheduleTrainingTimeoutLocked(h *landlordHub) {
	if c.trainingTimer != nil {
		c.trainingTimer.Stop()
		c.trainingTimer = nil
	}
	if c.disconnected || c.trainingGame == nil || c.trainingGame.Phase == landlord.PhaseFinished {
		return
	}
	c.trainingDeadline = time.Now().UTC().Add(landlordActionTimeout)
	g, epoch := c.trainingGame, c.trainingGame.Epoch
	c.trainingTimer = time.AfterFunc(landlordActionTimeout, func() {
		c.trainingMu.Lock()
		defer c.trainingMu.Unlock()
		if c.disconnected || c.trainingGame != g || g.Epoch != epoch {
			return
		}
		g.Timeout()
		for steps := 0; steps < 4 && g.Phase != landlord.PhaseFinished && g.Turn != 0; steps++ {
			if g.BotTurn(g.Turn) != nil {
				break
			}
		}
		c.scheduleTrainingTimeoutLocked(h)
		c.sendTraining()
	})
}

func (r *landlordRoom) scheduleTimeoutLocked(h *landlordHub) {
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
	if !r.started || r.game.Phase == landlord.PhaseFinished {
		return
	}
	epoch := r.game.Epoch
	r.timer = time.AfterFunc(landlordActionTimeout, func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		if r.closed || !r.started || r.game.Epoch != epoch {
			return
		}
		r.game.Timeout()
		r.lastActionAt = time.Now().UTC()
		r.scheduleTimeoutLocked(h)
		r.broadcastLocked()
		r.finishIfNeededLocked(h)
	})
}

func (r *landlordRoom) broadcastLocked() {
	r.monitor.notify()
	for client := range r.clients {
		state := r.game.SnapshotFor(client.seat)
		state["room_id"] = r.id
		state["status"] = "playing"
		if !r.started {
			state["status"] = "waiting"
		}
		if r.game.Phase == landlord.PhaseFinished {
			state["status"] = "finished"
		}
		state["connected_players"] = r.connectedSeats()
		state["action_timeout_seconds"] = int(landlordActionTimeout / time.Second)
		state["server_now_ms"] = time.Now().UTC().UnixMilli()
		state["action_deadline_ms"] = int64(0)
		if r.started && r.game.Phase != landlord.PhaseFinished {
			state["action_deadline_ms"] = r.lastActionAt.Add(landlordActionTimeout).UnixMilli()
		}
		_ = client.wire.writeJSON(state)
	}
}

func (r *landlordRoom) finishIfNeededLocked(h *landlordHub) {
	if r.closed || r.game.Phase != landlord.PhaseFinished {
		return
	}
	r.closed = true
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
	h.matches.FinishRoom(r.id)
}

func (h *landlordHub) disconnect(client *landlordClient) {
	if client == nil {
		return
	}
	client.trainingMu.Lock()
	client.disconnected = true
	if client.trainingTimer != nil {
		client.trainingTimer.Stop()
		client.trainingTimer = nil
	}
	client.trainingMu.Unlock()
	if client.room == nil {
		return
	}
	room := client.room
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, ok := room.clients[client]; !ok {
		return
	}
	delete(room.clients, client)
	room.broadcastLocked()
}
