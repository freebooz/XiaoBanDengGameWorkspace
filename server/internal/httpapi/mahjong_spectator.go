package httpapi

import (
	"errors"
	"slices"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

// The spectator registry is acquired after hub and room locks when they are
// needed. Its subscriptions are independent of the four player connections.
type mahjongSpectators struct {
	mu    sync.Mutex
	rooms map[string]*mahjongRoomSpectators
}

type mahjongRoomSpectators struct {
	createdAt time.Time
	allowed   map[string]bool
	seats     [4]*mahjongSpectator
}

type mahjongSpectator struct {
	roomID    string
	createdAt time.Time
	accountID string
	target    string
	seat      int
	wake      chan struct{}
	done      chan struct{}
	// Written once before done is closed.
	endMessage string
	finalState *mahjongWatchState
}

func (s *mahjongSpectators) roomLocked(roomID string, createdAt time.Time) *mahjongRoomSpectators {
	if room := s.rooms[roomID]; room != nil && room.createdAt.Equal(createdAt) {
		return room
	}
	return nil
}

func (s *mahjongSpectators) activeCount(roomID string, createdAt time.Time) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(roomID, createdAt)
	if room == nil {
		return 0
	}
	count := 0
	for _, watcher := range room.seats {
		if watcher != nil {
			count++
		}
	}
	return count
}

func (s *mahjongSpectators) playerStatus(roomID string, createdAt time.Time, player string) (allowed, occupied bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(roomID, createdAt)
	if room == nil || !room.allowed[player] {
		return false, false
	}
	for _, watcher := range room.seats {
		if watcher != nil && watcher.target == player {
			return true, true
		}
	}
	return true, false
}

func (s *mahjongSpectators) setPermission(current matchmaking.MahjongAssignment, player string, enabled bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(current.RoomID, current.Room.CreatedAt)
	if enabled {
		if room == nil {
			if previous := s.rooms[current.RoomID]; previous != nil {
				for seat, watcher := range previous.seats {
					if watcher != nil {
						previous.endLocked(seat, "原观战房间已关闭", nil)
					}
				}
			}
			if s.rooms == nil {
				s.rooms = make(map[string]*mahjongRoomSpectators)
			}
			room = &mahjongRoomSpectators{createdAt: current.Room.CreatedAt, allowed: make(map[string]bool)}
			s.rooms[current.RoomID] = room
		}
		room.allowed[player] = true
		return
	}
	if room == nil {
		return
	}
	delete(room.allowed, player)
	for seat, watcher := range room.seats {
		if watcher != nil && watcher.target == player {
			room.endLocked(seat, "该座位已关闭观战", nil)
		}
	}
	if len(room.allowed) == 0 {
		delete(s.rooms, current.RoomID)
	}
}

func (s *mahjongSpectators) reconcileRoster(roomID string, createdAt time.Time, players []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(roomID, createdAt)
	if room == nil {
		return
	}
	for player := range room.allowed {
		if !slices.Contains(players, player) {
			delete(room.allowed, player)
		}
	}
	for seat, watcher := range room.seats {
		if watcher != nil && (seat >= len(players) || players[seat] != watcher.target) {
			room.endLocked(seat, "该观战座位的玩家已离开或换位", nil)
		}
	}
	if len(room.allowed) == 0 {
		delete(s.rooms, roomID)
	}
}

func (s *mahjongSpectators) watchableSeats(current matchmaking.MahjongAssignment) []int {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(current.RoomID, current.Room.CreatedAt)
	if room == nil {
		return nil
	}
	var seats []int
	for seat, player := range current.PlayerAccountIDs {
		if room.allowed[player] && room.seats[seat] == nil {
			seats = append(seats, seat)
		}
	}
	return seats
}

// A nil watcher performs the same validation without reserving the slot.
func (s *mahjongSpectators) admit(current matchmaking.MahjongAssignment, seat int, watcher *mahjongSpectator) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(current.RoomID, current.Room.CreatedAt)
	if seat >= len(current.PlayerAccountIDs) || room == nil || !room.allowed[current.PlayerAccountIDs[seat]] {
		return errors.New("该座位尚未允许观战")
	}
	if room.seats[seat] != nil {
		return errors.New("该座位已有观战者")
	}
	if watcher != nil {
		watcher.createdAt = current.Room.CreatedAt
		watcher.target = current.PlayerAccountIDs[seat]
		room.seats[seat] = watcher
	}
	return nil
}

func (s *mahjongSpectators) release(watcher *mahjongSpectator, message string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(watcher.roomID, watcher.createdAt)
	if room == nil || room.seats[watcher.seat] != watcher {
		return false
	}
	room.endLocked(watcher.seat, message, nil)
	return true
}

func (r *mahjongRoomSpectators) endLocked(seat int, message string, final *mahjongWatchState) {
	watcher := r.seats[seat]
	r.seats[seat] = nil
	watcher.endMessage, watcher.finalState = message, final
	close(watcher.done)
}

func (s *mahjongSpectators) finishRound(board *mahjongRoom) {
	s.mu.Lock()
	defer s.mu.Unlock()
	room := s.roomLocked(board.id, board.createdAt)
	if room == nil {
		return
	}
	for seat, watcher := range room.seats {
		if watcher != nil {
			final := board.watchStateLocked(watcher.seat)
			room.endLocked(seat, "本局观战已结束", &final)
		}
	}
}

func (s *mahjongSpectator) notify() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

func (s *mahjongSpectators) notifyRoom(roomID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if room := s.rooms[roomID]; room != nil {
		for _, watcher := range room.seats {
			if watcher != nil {
				watcher.notify()
			}
		}
	}
}

func (s *mahjongSpectators) notifyAccounts(changed map[string]bool) {
	if len(changed) == 0 {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, room := range s.rooms {
		for _, watcher := range room.seats {
			if watcher != nil && changed[watcher.accountID] {
				watcher.notify()
			}
		}
	}
}

func mahjongSpectatorError(client *mahjongClient, operation string, err error) {
	message := map[string]any{"type": "mahjong_error", "operation": operation, "message": err.Error()}
	if errors.Is(err, matchmaking.ErrMahjongRoomPassword) {
		message["code"] = "room_password_required"
	} else if errors.Is(err, matchmaking.ErrMahjongRoomNotFound) {
		message["code"] = "room_not_found"
	}
	_ = client.writeJSON(message)
}

func (h *mahjongHub) lockWatchRoom(roomID string) (*mahjongRoom, func()) {
	h.mu.Lock()
	room := h.rooms[roomID]
	if room != nil {
		room.mu.Lock()
	}
	return room, func() {
		if room != nil {
			room.mu.Unlock()
		}
		h.mu.Unlock()
	}
}

func (h *mahjongHub) admitSpectator(accountID, roomID, password string, seat int, watcher *mahjongSpectator) error {
	if h.matches == nil || accountID == "" || roomID == "" || seat < 0 || seat >= 4 {
		return errors.New("需要有效的账号、房间号和观战座位")
	}
	before, exists := h.matches.MahjongFriendRoomSnapshot(roomID)
	if !exists {
		return matchmaking.ErrMahjongRoomNotFound
	}
	// Password verification is intentionally outside gameplay locks. Check
	// the same room generation again before admitting the watcher.
	if err := before.Settings.VerifyPassword(password); err != nil {
		return err
	}
	board, unlock := h.lockWatchRoom(roomID)
	defer unlock()
	current, exists := h.matches.MahjongFriendRoomSnapshot(roomID)
	if h.stopping.Load() || !exists || !current.Room.CreatedAt.Equal(before.Room.CreatedAt) ||
		(current.Start && board != nil && board.belongsToRound(current) && board.closed) {
		return matchmaking.ErrMahjongRoomNotFound
	}
	if !current.Settings.AllowSpectators {
		return errors.New("该房间未开放观战")
	}
	if _, busy := h.matches.MahjongAssignment(accountID); busy {
		return errors.New("请先退出当前麻将房间")
	}
	return h.spectators.admit(current, seat, watcher)
}

func (h *mahjongHub) joinSpectator(client *mahjongClient, message map[string]any) {
	accountID := client.resolveAccount(message)
	if client.principal == "" || accountID == "" || client.lobbyAccount != "" || client.room != nil {
		mahjongSpectatorError(client, "watch", errors.New("请使用独立的已登录观战连接"))
		return
	}
	roomID, _ := message["room_id"].(string)
	seat, valid := jsonInt(message["watch_seat"])
	if !valid {
		mahjongSpectatorError(client, "watch", errors.New("观战座位必须为 0 至 3 的整数"))
		return
	}
	password, err := mahjongRoomPassword(message, "watch")
	if err != nil {
		mahjongSpectatorError(client, "watch", err)
		return
	}
	watcher := &mahjongSpectator{
		roomID: roomID, accountID: accountID, seat: seat, wake: make(chan struct{}, 1), done: make(chan struct{}),
	}
	if err := h.admitSpectator(accountID, roomID, password, seat, watcher); err != nil {
		mahjongSpectatorError(client, "watch", err)
		return
	}
	client.spectator = watcher
	if client.writeJSON(map[string]any{"type": "mahjong_watch_joined", "room_id": roomID, "watch_seat": seat}) != nil {
		return
	}
	watcher.notify()
	go h.writeSpectatorSnapshots(client, watcher)
	h.publishSpectatorOccupancy(watcher)
}

func (h *mahjongHub) setSpectatorPermission(client *mahjongClient, message map[string]any, seated bool) (matchmaking.MahjongAssignment, error) {
	accountID := client.resolveAccount(message)
	roomID, _ := message["room_id"].(string)
	enabled, valid := message["enabled"].(bool)
	if h.matches == nil || client.principal == "" || accountID == "" || roomID == "" || !valid || (!seated && client.lobbyAccount != accountID) {
		return matchmaking.MahjongAssignment{}, errors.New("需要当前座位的已登录账号、房间号和观战开关")
	}
	room, unlock := h.lockWatchRoom(roomID)
	defer unlock()
	if seated {
		if room == nil || client.room != room || room.closed || client.seat < 0 || client.seat >= 4 ||
			room.game.Players[client.seat] != accountID {
			return matchmaking.MahjongAssignment{}, errors.New("此连接没有当前牌局的有效座位")
		}
		if _, active := room.clients[client]; !active {
			return matchmaking.MahjongAssignment{}, errors.New("此连接没有当前牌局的有效座位")
		}
	}
	current, assigned := h.matches.MahjongAssignment(accountID)
	if h.stopping.Load() || !assigned || current.RoomID != roomID || current.SeatIndex < 0 || current.SeatIndex >= 4 ||
		current.Kind != matchmaking.MahjongFriend || !current.Settings.AllowSpectators ||
		(seated && !room.belongsToRound(current)) ||
		(current.Start && room != nil && room.belongsToRound(current) && room.closed) {
		return matchmaking.MahjongAssignment{}, errors.New("此座位无法更改观战权限")
	}
	h.spectators.setPermission(current, accountID, enabled)
	return current, nil
}

func (h *mahjongHub) boardSpectatorPermission(client *mahjongClient, message map[string]any) {
	current, err := h.setSpectatorPermission(client, message, true)
	if err != nil {
		mahjongSpectatorError(client, "spectator_permission", err)
		return
	}
	h.publishLobby(current.RoomID, client.principal)
	h.sendSpectatorSeatState(current.RoomID, current.Room.CreatedAt, client.principal)
}

func (h *mahjongHub) reconcileSpectatorsAfterLeave(previous matchmaking.MahjongAssignment) {
	if !previous.Settings.AllowSpectators {
		return
	}
	var players []string
	if current := h.friendAssignment(previous.RoomID); current != nil && current.Room.CreatedAt.Equal(previous.Room.CreatedAt) {
		players = current.PlayerAccountIDs
	}
	h.spectators.reconcileRoster(previous.RoomID, previous.Room.CreatedAt, players)
}

func (h *mahjongHub) publishSpectatorOccupancy(watcher *mahjongSpectator) {
	if h.stopping.Load() {
		return
	}
	h.publishLobby(watcher.roomID, watcher.target)
	h.sendSpectatorSeatState(watcher.roomID, watcher.createdAt, watcher.target)
}

func (h *mahjongHub) sendSpectatorSeatState(roomID string, createdAt time.Time, player string) {
	h.mu.Lock()
	room := h.rooms[roomID]
	if room == nil || !room.createdAt.Equal(createdAt) {
		h.mu.Unlock()
		return
	}
	room.mu.Lock()
	h.mu.Unlock()
	defer room.mu.Unlock()
	if !room.closed {
		for client := range room.clients {
			if client.accountID == player {
				room.sendSnapshotLocked(client, room.connectedSeatFlags(), time.Now().UnixMilli())
				break
			}
		}
	}
}

// Watchers receive a separate allowlisted wire type. The watch writer runs
// independently of the room and serializes only detached snapshots.
type mahjongWatchState struct {
	guiyang.PublicBoardSnapshot
	Type             string                 `json:"type"`
	RoomID           string                 `json:"room_id"`
	WatchSeat        int                    `json:"watch_seat"`
	MatchID          string                 `json:"match_id,omitempty"`
	Status           string                 `json:"status"`
	ConnectedSeats   [4]bool                `json:"connected_seats"`
	OccupiedSeats    [4]bool                `json:"occupied_seats"`
	PlayerNames      [4]string              `json:"player_names"`
	ServerNowMS      int64                  `json:"server_now_ms"`
	ActionDeadlineMS int64                  `json:"action_deadline_ms"`
	RuleSetID        string                 `json:"rule_set_id"`
	RuleVersion      string                 `json:"rule_version"`
	Rule             guiyang.RuleDescriptor `json:"rule"`
}

func (r *mahjongRoom) watchStateLocked(seat int) mahjongWatchState {
	state := mahjongWatchState{
		Type: "mahjong_watch_state", RoomID: r.id, WatchSeat: seat, MatchID: r.matchID, Status: "playing",
		PublicBoardSnapshot: r.game.PublicBoard(), ServerNowMS: time.Now().UnixMilli(),
		RuleSetID: r.rule.ID, RuleVersion: r.rule.Version, Rule: r.rule,
	}
	if r.game.Phase == guiyang.PhaseFinished {
		state.Status = "finished"
	} else if !r.persistPending && !r.closed && r.decisionID != "" {
		state.ActionDeadlineMS = r.actionDeadline().UnixMilli()
	}
	r.addWatchSeatMetadataLocked(&state)
	return state
}

func (r *mahjongRoom) addWatchSeatMetadataLocked(state *mahjongWatchState) {
	state.ConnectedSeats = r.connectedSeatFlags()
	for seat, player := range r.game.Players {
		state.OccupiedSeats[seat] = player != ""
		state.PlayerNames[seat] = r.seatProfiles[seat].DisplayName
	}
	for client := range r.clients {
		if client.seat >= 0 && client.seat < 4 && r.game.Players[client.seat] == client.accountID && state.PlayerNames[client.seat] == "" {
			state.PlayerNames[client.seat] = client.displayName
		}
	}
}

func (h *mahjongHub) spectatorSnapshot(watcher *mahjongSpectator) (mahjongWatchState, error) {
	board, unlock := h.lockWatchRoom(watcher.roomID)
	defer unlock()
	current, exists := h.matches.MahjongFriendRoomSnapshot(watcher.roomID)
	if !exists || !current.Room.CreatedAt.Equal(watcher.createdAt) ||
		(current.Start && board != nil && board.belongsToRound(current) && board.closed) {
		return mahjongWatchState{}, matchmaking.ErrMahjongRoomNotFound
	}
	if _, busy := h.matches.MahjongAssignment(watcher.accountID); busy {
		return mahjongWatchState{}, errors.New("观战账号已加入麻将房间")
	}
	if watcher.seat >= len(current.PlayerAccountIDs) || current.PlayerAccountIDs[watcher.seat] != watcher.target {
		return mahjongWatchState{}, errors.New("该观战座位的玩家已离开或换位")
	}
	if board != nil && board.belongsToRound(current) && board.started && current.Start {
		return board.watchStateLocked(watcher.seat), nil
	}
	state := mahjongWatchState{
		Type: "mahjong_watch_state", RoomID: current.RoomID, WatchSeat: watcher.seat, Status: "waiting",
		PublicBoardSnapshot: guiyang.PublicBoardSnapshot{
			Turn: -1, Dealer: -1, Melds: [4][]guiyang.Meld{{}, {}, {}, {}},
			Discards: []guiyang.Discard{}, ActionEvents: []guiyang.ActionEvent{},
		},
		ServerNowMS: time.Now().UnixMilli(), RuleSetID: current.RuleSetID, RuleVersion: current.RuleVersion, Rule: current.Rule,
	}
	if board != nil && current.Start && board.belongsToRound(current) {
		board.addWatchSeatMetadataLocked(&state)
	}
	h.lobbyMu.Lock()
	defer h.lobbyMu.Unlock()
	for seat, player := range current.PlayerAccountIDs {
		state.OccupiedSeats[seat] = true
		for client, lobby := range h.lobbyClients {
			if lobby.accountID == player {
				state.ConnectedSeats[seat] = true
				if state.PlayerNames[seat] == "" {
					state.PlayerNames[seat] = client.displayName
				}
				break
			}
		}
	}
	return state, nil
}

func (h *mahjongHub) writeSpectatorSnapshots(client *mahjongClient, watcher *mahjongSpectator) {
	for {
		select {
		case <-watcher.done:
			if watcher.finalState != nil && client.writeJSON(watcher.finalState) != nil {
				return
			}
			if watcher.endMessage != "" {
				_ = client.writeJSON(map[string]any{
					"type": "mahjong_watch_ended", "room_id": watcher.roomID, "message": watcher.endMessage,
				})
				_ = client.wire.conn.Close()
			}
			return
		case <-watcher.wake:
			state, err := h.spectatorSnapshot(watcher)
			if err != nil {
				if h.spectators.release(watcher, err.Error()) {
					defer h.publishSpectatorOccupancy(watcher)
				}
				continue
			}
			select {
			case <-watcher.done:
				continue
			default:
			}
			if client.writeJSON(state) != nil {
				return
			}
		}
	}
}
