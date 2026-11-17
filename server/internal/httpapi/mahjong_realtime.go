package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"slices"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
)

const (
	mahjongReactionTimeout = 15 * time.Second
	mahjongTrainingTimeout = 45 * time.Second
	mahjongBotDelay        = 350 * time.Millisecond
	mahjongEntryTimeout    = 30 * time.Second
)

type mahjongHub struct {
	stopping            atomic.Bool
	monitor             *monitorSignal
	mu                  sync.Mutex
	rooms               map[string]*mahjongRoom
	matches             *matchmaking.Manager
	entries             map[string]*mahjongEntry
	entryTimeout        time.Duration
	lobbyMu             sync.Mutex
	lobbyClients        map[*mahjongClient]*mahjongLobbySubscription
	spectators          mahjongSpectators
	waitingGrace        time.Duration
	waitingDisconnects  map[string]*mahjongWaitingDisconnect
	recordHistory       func(context.Context, mahjonghistory.Result) error
	checkpoints         mahjongCheckpointStore
	saveHistory         func(context.Context, pgx.Tx, mahjonghistory.Result) error
	friendStore         mahjongFriendStore
	friendHeads         sync.Map // Room ID to an immutable persisted image.
	moderation          mahjongReportStore
	seatWallets         func(context.Context, []string) (map[string]wallet.EggProfile, error)
	settlementEggDeltas func(context.Context, string) (*[4]int64, error)
}

type mahjongRoom struct {
	mu              sync.Mutex
	monitor         *monitorSignal
	spectators      *mahjongSpectators
	id              string
	createdAt       time.Time
	completedRounds int
	matchID         string
	kind            string
	rule            guiyang.RuleDescriptor
	game            *guiyang.Game
	clients         map[*mahjongClient]struct{}
	started         bool
	startedAt       time.Time
	closed          bool
	retained        bool
	timer           *time.Timer
	lastActionAt    time.Time
	decisionID      string
	decisionStart   time.Time
	social          [4]landlordSocialBudget
	assignment      matchmaking.MahjongAssignment
	revision        int64
	commands        []mahjongCommand
	persistPending  bool
	pendingCommand  mahjongCommand
	seatProfiles    [4]mahjongSeatProfile
	profilesLoaded  bool
	eggDeltas       *[4]int64
	joinedSeats     [4]bool
}

type mahjongClient struct {
	wire         *chessClient // 共享同一 WebSocket 的写锁，避免消息帧交错。
	principal    string
	displayName  string
	room         *mahjongRoom
	accountID    string
	seat         int
	lobbyAccount string
	lobbyWriteMu sync.Mutex
	spectator    *mahjongSpectator
}

func newMahjongHub(matches *matchmaking.Manager) *mahjongHub {
	return &mahjongHub{
		rooms: map[string]*mahjongRoom{}, matches: matches,
		entries: map[string]*mahjongEntry{}, entryTimeout: mahjongEntryTimeout,
		lobbyClients: map[*mahjongClient]*mahjongLobbySubscription{},
		waitingGrace: mahjongWaitingGrace, waitingDisconnects: map[string]*mahjongWaitingDisconnect{},
	}
}

func newMahjongClient(wire *chessClient) *mahjongClient { return &mahjongClient{wire: wire, seat: -1} }

func (c *mahjongClient) resolveAccount(message map[string]any) string {
	value, supplied := message["client_id"]
	claimed, _ := value.(string)
	if c.principal != "" {
		if supplied && claimed != c.principal {
			return ""
		}
		return c.principal
	}
	// In-process game fixtures can exercise room logic without an HTTP server.
	return claimed
}

func (h *mahjongHub) handle(client *mahjongClient, message map[string]any) bool {
	if h.stopping.Load() {
		return true
	}
	if client.spectator != nil {
		mahjongSpectatorError(client, "watch", errors.New("观战连接只支持查看牌局"))
		return true
	}
	switch message["type"] {
	case "mahjong_lobby_subscribe":
		h.subscribeLobby(client, message)
		return true
	case "mahjong_lobby_command":
		h.lobbyCommand(client, message)
		return true
	case "mahjong_room_directory":
		h.setLobbyDirectory(client, message)
		return true
	case "mahjong_join":
		client.wire.conn.SetReadLimit(256 << 10)
		h.join(client, message)
		return true
	case "mahjong_watch_join":
		h.joinSpectator(client, message)
		return true
	case "mahjong_spectator_permission":
		h.boardSpectatorPermission(client, message)
		return true
	case "mahjong_action":
		h.action(client, message)
		return true
	case "mahjong_social":
		h.social(client, message)
		return true
	case "mahjong_report":
		h.report(client, message)
		return true
	default:
		return false
	}
}

func (c *mahjongClient) fail(message string) {
	_ = c.writeJSON(map[string]any{"type": "mahjong_error", "message": message})
}

func (h *mahjongHub) roomForLocked(current matchmaking.MahjongAssignment, rule guiyang.RuleDescriptor) *mahjongRoom {
	if existing := h.rooms[current.RoomID]; existing != nil && existing.belongsToRound(current) {
		return existing
	}
	var seedBytes [8]byte
	if _, err := rand.Read(seedBytes[:]); err != nil {
		binary.LittleEndian.PutUint64(seedBytes[:], uint64(time.Now().UnixNano()))
	}
	created := &mahjongRoom{
		monitor: h.monitor, spectators: &h.spectators,
		id: current.RoomID, createdAt: current.Room.CreatedAt, completedRounds: current.CompletedRounds, kind: current.Kind, rule: rule,
		matchID: uuid.NewString(), assignment: current,
		game:    guiyang.NewGameWithDealer([4]string(current.PlayerAccountIDs), int64(binary.LittleEndian.Uint64(seedBytes[:])), rule.RuleSet(), current.OpeningDealer()),
		clients: map[*mahjongClient]struct{}{},
	}
	if head := h.friendHead(current.RoomID); head != nil && head.image.EntryMatchID != "" {
		created.matchID = head.image.EntryMatchID
	}
	h.rooms[current.RoomID] = created
	return created
}

func (r *mahjongRoom) belongsToRound(current matchmaking.MahjongAssignment) bool {
	return r.id == current.RoomID && r.createdAt.Equal(current.Room.CreatedAt) && r.completedRounds == current.CompletedRounds
}

func (h *mahjongHub) join(client *mahjongClient, message map[string]any) {
	roomID, _ := message["room_id"].(string)
	accountID := client.resolveAccount(message)
	expectedMatchID, validMatchID := message["match_id"].(string)
	if _, supplied := message["match_id"]; supplied && (!validMatchID || expectedMatchID == "") {
		client.fail("加入麻将房间的 match_id 必须为非空文本")
		return
	}
	if roomID == "" || accountID == "" || (client.lobbyAccount != "" && client.lobbyAccount != accountID) {
		client.fail("加入麻将房间必须提供 room_id 和 client_id")
		return
	}
	if h.matches == nil {
		client.fail("缺少权威匹配服务")
		return
	}
	room, seat, err := h.lockRoomForJoin(client, roomID, accountID, expectedMatchID)
	if err != nil {
		_ = client.writeJSON(map[string]any{"type": "mahjong_error", "operation": "join", "message": err.Error()})
		return
	}
	started := false
	defer func() {
		room.mu.Unlock()
		if started {
			h.stopEntryTimeout(room)
		}
	}()
	for old := range room.clients {
		if old != client && old.seat == seat {
			delete(room.clients, old)
			_ = old.wire.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "seat_replaced"), time.Now().Add(250*time.Millisecond))
			_ = old.wire.conn.Close()
		}
	}
	client.room, client.accountID, client.seat = room, accountID, seat
	room.clients[client] = struct{}{}
	joined := map[string]any{"type": "mahjong_joined", "room_id": roomID, "your_seat": seat}
	room.addRuleMetadata(joined)
	if client.writeJSON(joined) != nil {
		delete(room.clients, client)
		h.monitor.notify()
		return
	}
	if client.principal != "" && (!room.profilesLoaded || room.joinedSeats[seat]) {
		room.refreshSeatProfilesLocked(h)
	}
	room.joinedSeats[seat] = true
	if room.closed {
		room.sendSnapshotLocked(client, room.connectedSeatFlags(), time.Now().UTC().UnixMilli())
		h.monitor.notify()
		return
	}
	if !room.started && !room.persistPending && room.connectedSeats() == 4 {
		room.startedAt = time.Now().UTC()
		room.commitLocked(h, room.game, room.startedAt, nil, mahjongCommand{}, func() {
			room.started = true
		})
		started = room.started
		if started {
			return
		}
	}
	room.broadcastLocked()
}

// lockRoomForJoin returns the selected game with its lock held. A reconnect
// can request the just-finished friend round while the room is between games.
func (h *mahjongHub) lockRoomForJoin(client *mahjongClient, roomID, accountID, expectedMatchID string) (*mahjongRoom, int, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.stopping.Load() {
		return nil, -1, errors.New("服务正在交接，请稍后重连")
	}
	current, ok := h.matches.MahjongAssignment(accountID)
	if !ok || current.RoomID != roomID || current.SeatIndex < 0 || current.SeatIndex >= 4 {
		return nil, -1, errors.New("玩家不属于该麻将房间")
	}
	room := h.rooms[roomID]
	restoring := !current.Start && current.Kind == matchmaking.MahjongFriend && expectedMatchID != "" && expectedMatchID == current.PreviousMatchID
	if !restoring && (!current.Start || len(current.PlayerAccountIDs) != 4) {
		return nil, -1, errors.New("四人尚未准备完成或座位失效")
	}
	predeal := h.friendHead(roomID)
	reserved := !restoring && predeal != nil && predeal.image.EntryMatchID == expectedMatchID && (room == nil || !room.belongsToRound(current))
	if expectedMatchID != "" && !reserved && (room == nil || room.matchID != expectedMatchID || !room.createdAt.Equal(current.Room.CreatedAt) || (!restoring && !room.belongsToRound(current))) {
		return nil, -1, errors.New("此对局已失效，请返回大厅")
	}
	rule := current.Rule
	if rule.ID == "" {
		return nil, -1, errors.New("未知的麻将玩法或版本")
	}
	if old := client.room; old != nil && ((restoring && old != room) || (!restoring && !old.belongsToRound(current))) {
		old.mu.Lock()
		if !old.closed {
			old.mu.Unlock()
			return nil, -1, errors.New("此连接已经加入其他麻将房间")
		}
		h.detachLocked(client, old)
		old.mu.Unlock()
	}
	if !restoring {
		room = h.roomForLocked(current, rule)
	}
	room.mu.Lock()
	if restoring {
		// A waiting roster can compact after a leave. Use the original seat
		// for the private snapshot and reject newly invited players.
		seat := slices.Index(room.game.Players[:], accountID)
		if room.closed && room.retained && room.game.Phase == guiyang.PhaseFinished && seat >= 0 {
			return room, seat, nil
		}
		room.mu.Unlock()
		return nil, -1, errors.New("无法恢复此对局的结算")
	}
	if room.closed {
		room.mu.Unlock()
		return nil, -1, errors.New("此麻将房间已经结束")
	}
	return room, current.SeatIndex, nil
}

func (r *mahjongRoom) connectedSeatFlags() [4]bool {
	var seats [4]bool
	if r.kind == matchmaking.MahjongTraining {
		seats = [4]bool{false, true, true, true}
	}
	for client := range r.clients {
		if client.room == r && client.seat >= 0 && client.seat < 4 && r.game.Players[client.seat] == client.accountID {
			seats[client.seat] = true
		}
	}
	return seats
}

func (r *mahjongRoom) connectedSeats() int {
	count := 0
	for _, connected := range r.connectedSeatFlags() {
		if connected {
			count++
		}
	}
	return count
}

// Reuse only the shared pure payload validation; Mahjong owns its protocol,
// memberships and four seat budgets, and does not support Landlord's props.
func validateMahjongSocial(message map[string]any) (map[string]any, error) {
	switch message["action"] {
	case "chat", "emote", "voice":
	default:
		return nil, errors.New("未知麻将互动动作")
	}
	event, err := validateLandlordSocial(message)
	if err != nil {
		return nil, err
	}
	event["type"] = "mahjong_social"
	return event, nil
}

func (h *mahjongHub) social(client *mahjongClient, message map[string]any) {
	event, err := validateMahjongSocial(message)
	if err != nil {
		client.fail(err.Error())
		return
	}
	room := client.room
	if room == nil {
		client.fail("尚未加入麻将房间")
		return
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, active := room.clients[client]; !active || client.seat < 0 || client.seat >= 4 || room.game.Players[client.seat] != client.accountID {
		client.fail("连接已由新连接接管或座位无效")
		return
	}
	if !room.started || (room.closed && room.game.Phase != guiyang.PhaseFinished) {
		client.fail("等待四位玩家连接")
		return
	}
	if matchID, supplied := message["match_id"]; supplied && matchID != room.matchID {
		client.fail("互动不属于当前对局")
		return
	}
	var retainedPlayers []string
	if room.closed && room.kind == matchmaking.MahjongFriend {
		current, assigned := h.matches.MahjongAssignment(client.accountID)
		if !assigned || current.RoomID != room.id || !current.Room.CreatedAt.Equal(room.createdAt) || current.PreviousMatchID != room.matchID || current.Start {
			client.fail("本局已经结束")
			return
		}
		retainedPlayers = current.PlayerAccountIDs
	}
	now := time.Now().UTC()
	// Budgets survive reconnects; settlement keeps social available to seated peers.
	if err := room.social[client.seat].accept(event, now); err != nil {
		client.fail(err.Error())
		return
	}
	event["seat"], event["room_id"], event["match_id"] = client.seat, room.id, room.matchID
	event["server_now_ms"], event["server_time_ms"] = now.UnixMilli(), now.UnixMilli()
	for peer := range room.clients {
		if retainedPlayers != nil && !slices.Contains(retainedPlayers, peer.accountID) {
			continue
		}
		if peer.room == room && peer.seat >= 0 && peer.seat < 4 && room.game.Players[peer.seat] == peer.accountID {
			_ = peer.writeJSON(event)
		}
	}
}

func (h *mahjongHub) action(client *mahjongClient, message map[string]any) {
	commandID, _ := message["command_id"].(string)
	if len(commandID) > 128 {
		client.fail("麻将命令编号过长")
		return
	}
	reply := func(err error) {
		if commandID == "" {
			if err != nil {
				client.fail(err.Error())
			}
			return
		}
		result := map[string]any{"type": "mahjong_action_result", "command_id": commandID, "ok": err == nil, "message": ""}
		if err != nil {
			result["message"] = err.Error()
		}
		_ = client.writeJSON(result)
	}
	room := client.room
	if room == nil {
		reply(errors.New("尚未加入麻将房间"))
		return
	}
	action, _ := message["action"].(string)
	tileID := 0
	if raw, exists := message["tile_id"]; exists {
		var ok bool
		tileID, ok = jsonInt(raw)
		if !ok {
			reply(errors.New("tile_id 必须为整数"))
			return
		}
	}
	suit := ""
	if action == "dingque" {
		var ok bool
		suit, ok = message["suit"].(string)
		if !ok || tileID != 0 {
			reply(errors.New("定缺须指定一个花色"))
			return
		}
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	if _, connected := room.clients[client]; !connected || client.seat < 0 || client.seat >= 4 || room.game.Players[client.seat] != client.accountID {
		reply(errors.New("连接已由新连接接管或座位无效"))
		return
	}
	if matchID, supplied := message["match_id"]; supplied && matchID != room.matchID {
		reply(errors.New("操作不属于当前对局"))
		return
	}
	windowID := ""
	if raw, supplied := message["action_window_id"]; supplied {
		var ok bool
		windowID, ok = raw.(string)
		if !ok || windowID == "" || len(windowID) > 128 {
			reply(errors.New("麻将操作窗口编号无效"))
			return
		}
	}
	command := mahjongCommand{ID: commandID, Seat: client.seat, Action: action, TileID: tileID, Suit: suit, WindowID: windowID}
	commands := room.commands
	if command.ID != "" {
		for _, recorded := range commands {
			if recorded.Seat == command.Seat && recorded.ID == command.ID {
				if recorded != command {
					reply(errors.New("麻将命令编号已用于另一项操作"))
				} else {
					reply(nil)
					room.sendSnapshotLocked(client, room.connectedSeatFlags(), time.Now().UTC().UnixMilli())
				}
				return
			}
		}
	}
	if room.persistPending {
		if command.ID == "" || room.pendingCommand != command {
			reply(errors.New("服务器正在保存牌局，请稍后重试"))
		}
		return
	}
	if room.closed {
		reply(errors.New("本局已经结束"))
		return
	}
	if !room.started {
		reply(errors.New("等待四位玩家连接"))
		return
	}
	if windowID != "" && windowID != room.decisionID {
		reply(errors.New("牌桌已进入新的操作窗口，请按当前选项继续"))
		return
	}
	when := time.Now().UTC()
	if !when.Before(room.actionDeadline()) {
		reply(errors.New("当前操作窗口已超时"))
		return
	}
	next, err := room.copyForAction(h)
	if err == nil {
		err = applyMahjongOption(next, client.seat, guiyang.ActionOption{Type: action, TileID: tileID, Suit: suit})
	}
	if err != nil {
		reply(err)
		return
	}
	if command.ID != "" {
		commands = append(slices.Clone(commands), command)
	}
	room.commitLocked(h, next, when, commands, command, func() { reply(nil) })
}

func applyMahjongOption(game *guiyang.Game, seat int, option guiyang.ActionOption) error {
	if option.Type == "dingque" {
		return game.ChooseMissingSuit(seat, option.Suit)
	}
	return game.Apply(seat, option.Type, option.TileID)
}

func (r *mahjongRoom) advanceLocked(h *mahjongHub) {
	r.scheduleTimeoutLocked(h)
	r.broadcastLocked()
	r.finishIfNeededLocked(h)
}

func (r *mahjongRoom) turnTimeout() time.Duration {
	if r.kind == matchmaking.MahjongTraining {
		return mahjongTrainingTimeout
	}
	return time.Duration(r.assignment.Settings.EffectiveTurnTimeoutSeconds()) * time.Second
}

func (r *mahjongRoom) actionTimeout() time.Duration {
	if r.kind == matchmaking.MahjongTraining || r.game.Phase == guiyang.PhaseTurn || r.game.Phase == guiyang.PhaseDingque {
		return r.turnTimeout()
	}
	return mahjongReactionTimeout
}

func mahjongDecisionID(matchID string, game *guiyang.Game) string {
	if game.Phase == guiyang.PhaseFinished {
		return ""
	}
	epoch := game.Epoch
	if game.Phase == guiyang.PhaseReaction {
		// The engine increments Epoch once per response. Subtracting the
		// accepted responses recovers the opening epoch, including on restore.
		epoch -= len(game.Submitted)
	}
	return matchID + ":" + strconv.Itoa(epoch)
}

func (r *mahjongRoom) actionDeadline() time.Time {
	return r.decisionStart.Add(r.actionTimeout())
}

func (r *mahjongRoom) botActionLocked() (int, guiyang.ActionOption) {
	if r.kind != matchmaking.MahjongTraining {
		return -1, guiyang.ActionOption{}
	}
	for seat := 1; seat < 4; seat++ {
		options := r.game.Options(seat)
		if len(options) == 0 {
			continue
		}
		chosen := options[0]
		if chosen.Type == "dingque" {
			chosen.Suit = r.game.DefaultMissingSuit(seat)
			return seat, chosen
		}
		for _, option := range options {
			switch option.Type {
			case "hu":
				return seat, option
			case "ming_gang", "an_gang", "bu_gang":
				chosen = option
			case "peng":
				if chosen.Type == "pass" {
					chosen = option
				}
			}
		}
		if chosen.Type == "play" && chosen.TileID == 0 {
			hand := r.game.Hands[seat]
			chosen.TileID = hand[len(hand)-1].ID
		}
		return seat, chosen
	}
	return -1, guiyang.ActionOption{}
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
	botSeat, botAction := r.botActionLocked()
	deadline := r.actionDeadline()
	runAt := deadline
	if botAt := r.lastActionAt.Add(mahjongBotDelay); botSeat >= 0 && botAt.Before(deadline) {
		runAt = botAt
	}
	var scheduled *time.Timer
	scheduled = time.AfterFunc(time.Until(runAt), func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		if r.closed || !r.started || r.persistPending || r.game.Epoch != expectedEpoch || r.timer != scheduled {
			return
		}
		next, err := r.copyForAction(h)
		if err != nil {
			return
		}
		when := time.Now().UTC()
		if botSeat < 0 || !when.Before(deadline) || applyMahjongOption(next, botSeat, botAction) != nil {
			next.Timeout()
		}
		r.commitLocked(h, next, when, r.commands, mahjongCommand{}, func() {})
	})
	r.timer = scheduled
}

func (r *mahjongRoom) broadcastLocked() {
	r.monitor.notify()
	if r.spectators != nil {
		r.spectators.notifyRoom(r.id)
	}
	now := time.Now().UTC().UnixMilli()
	connected := r.connectedSeatFlags()
	for client := range r.clients {
		r.sendSnapshotLocked(client, connected, now)
	}
}

func (r *mahjongRoom) sendSnapshotLocked(client *mahjongClient, connected [4]bool, now int64) {
	state := r.game.SnapshotFor(client.seat)
	if client.principal != "" && client.seat >= 0 && client.seat < len(r.game.Players) && r.game.Players[client.seat] == client.principal {
		r.addSeatProfilesLocked(state)
	}
	state["room_id"] = r.id
	state["allow_spectators"] = r.assignment.Settings.AllowSpectators
	allowed, occupied := false, false
	if r.spectators != nil && r.assignment.Settings.AllowSpectators {
		allowed, occupied = r.spectators.playerStatus(r.id, r.createdAt, client.accountID)
	}
	state["spectator_allowed"], state["spectator_occupied"] = allowed, occupied
	state["can_rematch"] = r.assignment.CanPlayAnotherRound()
	state["completed_rounds"] = r.completedRounds
	if r.kind == matchmaking.MahjongFriend {
		series := r.assignment.Series
		total := r.completedRounds
		if r.game.Phase == guiyang.PhaseFinished {
			series = series.WithRound(r.game.Players, r.game.Scores)
			total++
		}
		if series.Rounds > 0 {
			state["series_scores"], state["series_ranks"] = series.Scoreboard(r.game.Players[:])
			state["series_rounds"], state["series_total_rounds"] = series.Rounds, total
		}
	}
	if limit := r.assignment.Settings.RoundLimit; limit > 0 {
		state["round_limit"] = limit
	}
	r.addRuleMetadata(state)
	state["status"] = "playing"
	if !r.started {
		state["status"] = "waiting"
		state["hand"] = []guiyang.Tile{}
		state["options"] = []guiyang.ActionOption{}
	}
	if r.game.Phase == guiyang.PhaseFinished {
		state["status"] = "finished"
	}
	state["connected_players"] = r.connectedSeats()
	state["connected_seats"] = connected
	state["dealer"] = r.game.Dealer
	state["server_now_ms"], state["server_time_ms"] = now, now
	state["turn_timeout_seconds"] = int(r.turnTimeout() / time.Second)
	state["action_timeout_seconds"] = int(r.actionTimeout() / time.Second)
	state["action_deadline_ms"] = int64(0)
	if r.started && !r.closed && !r.persistPending && r.decisionID != "" {
		state["action_deadline_ms"] = r.actionDeadline().UnixMilli()
		state["action_window_id"] = r.decisionID
	}
	if r.persistPending {
		state["saving"] = true
		state["options"] = []guiyang.ActionOption{}
	}
	_ = client.writeJSON(state)
}

func (r *mahjongRoom) addRuleMetadata(message map[string]any) {
	message["kind"], message["match_id"] = r.kind, r.matchID
	message["rule_set_id"], message["rule_version"], message["rule"] = r.rule.ID, r.rule.Version, r.rule
}

func (r *mahjongRoom) finishIfNeededLocked(h *mahjongHub) {
	if r.closed || r.game.Phase != guiyang.PhaseFinished {
		return
	}
	r.closeLocked()
	h.spectators.finishRound(r)
	r.retained = h.matches.SettleMahjongRound(r.id, r.createdAt, r.completedRounds, r.matchID, r.game.NextDealer(), r.game.Scores)
	if !r.retained {
		h.spectators.reconcileRoster(r.id, r.createdAt, nil)
	}
	if r.retained && h.friendStore != nil {
		if current := h.friendAssignment(r.id); current != nil {
			h.startAbsentFriendGrace(*current)
		}
	}
	players := r.game.Players[:]
	if r.kind == matchmaking.MahjongTraining {
		players = players[:1]
	}
	h.publishLobby(r.id, players...)
	if !r.retained && len(r.clients) == 0 {
		go h.removeUnobservedSettlement(r)
	}
}

func (h *mahjongHub) removeUnobservedSettlement(r *mahjongRoom) {
	h.mu.Lock()
	defer h.mu.Unlock()
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.clients) == 0 && h.rooms[r.id] == r {
		delete(h.rooms, r.id)
		h.monitor.notify()
	}
}

func (r *mahjongRoom) closeLocked() {
	r.closed = true
	if r.spectators != nil {
		r.spectators.notifyRoom(r.id)
	}
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
}

func (h *mahjongHub) disconnect(client *mahjongClient) {
	if client == nil {
		return
	}
	if watcher := client.spectator; watcher != nil {
		if h.spectators.release(watcher, "") {
			h.publishSpectatorOccupancy(watcher)
		}
		return
	}
	h.disconnectLobby(client)
	if client.room == nil {
		return
	}
	h.mu.Lock()
	room := client.room
	room.mu.Lock()
	defer room.mu.Unlock()
	_, connected := room.clients[client]
	h.detachLocked(client, room)
	h.mu.Unlock()
	if connected && (!room.closed || (room.kind != matchmaking.MahjongFriend && room.game.Phase == guiyang.PhaseFinished)) {
		room.broadcastLocked()
	} else if connected {
		h.monitor.notify()
	}
}

func (h *mahjongHub) detachLocked(client *mahjongClient, room *mahjongRoom) {
	delete(room.clients, client)
	client.room, client.seat = nil, -1
	if room.closed && !room.retained && len(room.clients) == 0 && h.rooms[room.id] == room {
		delete(h.rooms, room.id)
	}
}
