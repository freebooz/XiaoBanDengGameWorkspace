package httpapi

import (
	"errors"
	"math"
	"strings"
	"sync/atomic"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"golang.org/x/crypto/bcrypt"
)

const mahjongWriteTimeout = 2 * time.Second

type mahjongLobbySubscription struct {
	accountID string
	wake      chan struct{}
	done      chan struct{}
	directory atomic.Bool
	// Guarded by the subscribing client's lobbyWriteMu.
	directoryRequestID string
}

func (s *mahjongLobbySubscription) notify() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

type mahjongLobbyState struct {
	Status                 string                  `json:"status"`
	Kind                   string                  `json:"kind"`
	RoomID                 string                  `json:"room_id"`
	RuleSetID              string                  `json:"rule_set_id"`
	RuleVersion            string                  `json:"rule_version"`
	PlayerAccountIDs       []string                `json:"player_account_ids"`
	ReadyAccountIDs        []string                `json:"ready_account_ids"`
	ReconnectingAccountIDs []string                `json:"reconnecting_account_ids"`
	ReadyPlayers           int                     `json:"ready_players"`
	Capacity               int                     `json:"capacity"`
	Start                  bool                    `json:"start"`
	SeatIndex              int                     `json:"seat_index"`
	CompletedRounds        int                     `json:"completed_rounds"`
	RoundLimit             int                     `json:"round_limit,omitempty"`
	TurnTimeoutSeconds     int                     `json:"turn_timeout_seconds,omitempty"`
	PreviousMatchID        string                  `json:"previous_match_id"`
	Rule                   *guiyang.RuleDescriptor `json:"rule,omitempty"`
}

func (h *mahjongHub) lobbyStateLocked(accountID string) mahjongLobbyState {
	current, exists := h.matches.MahjongAssignment(accountID)
	if !exists {
		return mahjongLobbyState{Status: "idle", PlayerAccountIDs: []string{}, ReadyAccountIDs: []string{}, ReconnectingAccountIDs: []string{}, Capacity: 4, SeatIndex: -1}
	}
	status := current.Status
	if current.Start {
		status = "playing"
	}
	state := mahjongLobbyState{
		Status: status, Kind: current.Kind, RoomID: current.RoomID, RuleSetID: current.RuleSetID, RuleVersion: current.RuleVersion,
		PlayerAccountIDs: current.PlayerAccountIDs, ReadyAccountIDs: current.ReadyAccountIDs, ReadyPlayers: current.ReadyPlayers,
		ReconnectingAccountIDs: h.reconnectingWaitingPlayers(current),
		Capacity:               current.Capacity, Start: current.Start, SeatIndex: current.SeatIndex,
		CompletedRounds: current.CompletedRounds, RoundLimit: current.Settings.RoundLimit, PreviousMatchID: current.PreviousMatchID, Rule: &current.Rule,
	}
	if current.Kind == matchmaking.MahjongFriend {
		state.TurnTimeoutSeconds = current.Settings.EffectiveTurnTimeoutSeconds()
	}
	return state
}

func (h *mahjongHub) subscribeLobby(client *mahjongClient, message map[string]any) {
	accountID := strings.TrimSpace(client.resolveAccount(message))
	if h.matches == nil || accountID == "" || (client.lobbyAccount != "" && client.lobbyAccount != accountID) || (client.accountID != "" && client.accountID != accountID) {
		_ = client.writeJSON(map[string]any{"type": "mahjong_error", "message": "麻将大厅连接需要有效的玩家账号"})
		return
	}
	client.lobbyAccount = accountID
	h.lobbyMu.Lock()
	subscription := h.lobbyClients[client]
	if subscription == nil {
		subscription = &mahjongLobbySubscription{accountID: accountID, wake: make(chan struct{}, 1), done: make(chan struct{})}
		h.lobbyClients[client] = subscription
		go h.writeLobbySnapshots(client, subscription)
	}
	reconnectedRoom := h.restoreWaitingPresenceLocked(accountID)
	h.lobbyMu.Unlock()
	subscription.notify()
	h.monitor.notify()
	if reconnectedRoom != "" {
		h.publishLobby(reconnectedRoom)
	}
}

func (h *mahjongHub) writeLobbySnapshots(client *mahjongClient, subscription *mahjongLobbySubscription) {
	for {
		select {
		case <-subscription.done:
			return
		case <-subscription.wake:
		}
		client.lobbyWriteMu.Lock()
		select {
		case <-subscription.done:
			client.lobbyWriteMu.Unlock()
			return
		default:
		}
		h.mu.Lock()
		state := h.lobbyStateLocked(subscription.accountID)
		message := map[string]any{
			"type": "mahjong_lobby_state", "state": state, "presets": guiyang.RuleDescriptors(),
			"room_directory": true, "room_directory_requests": true,
		}
		if state.Status == "idle" && subscription.directory.Load() {
			message["public_rooms"] = h.matches.MahjongPublicRooms()
			message["directory_request_id"] = subscription.directoryRequestID
		}
		h.mu.Unlock()
		err := client.writeJSON(message)
		client.lobbyWriteMu.Unlock()
		if err != nil {
			return
		}
	}
}

func (h *mahjongHub) setLobbyDirectory(client *mahjongClient, message map[string]any) {
	open, valid := message["open"].(bool)
	requestID, _ := message["request_id"].(string)
	if !valid || len(requestID) > 128 {
		return
	}
	h.lobbyMu.Lock()
	subscription := h.lobbyClients[client]
	h.lobbyMu.Unlock()
	if subscription != nil {
		client.lobbyWriteMu.Lock()
		defer client.lobbyWriteMu.Unlock()
		subscription.directoryRequestID = requestID
		subscription.directory.Store(open)
		if open {
			subscription.notify()
		}
	}
}

func (c *mahjongClient) writeJSON(message map[string]any) error {
	// Closing the socket interrupts either this write or the shared wire writer
	// ahead of it. The timeout covers time spent waiting for that writer as well.
	timeout := time.AfterFunc(mahjongWriteTimeout, func() { _ = c.wire.conn.Close() })
	defer timeout.Stop()
	err := c.wire.writeJSON(message)
	if err != nil {
		_ = c.wire.conn.Close()
	}
	return err
}

// Room settlement and commands only wake subscribers. Each subscriber writes
// its own latest snapshot and never puts network backpressure on the room.
func (h *mahjongHub) publishLobby(roomID string, changedAccounts ...string) {
	h.monitor.notify()
	h.lobbyMu.Lock()
	subscriptions := make([]*mahjongLobbySubscription, 0, len(h.lobbyClients))
	for _, subscription := range h.lobbyClients {
		subscriptions = append(subscriptions, subscription)
	}
	h.lobbyMu.Unlock()
	changed := make(map[string]bool, len(changedAccounts))
	for _, accountID := range changedAccounts {
		changed[accountID] = true
	}
	for _, subscription := range subscriptions {
		assignment, _ := h.matches.MahjongAssignment(subscription.accountID)
		if changed[subscription.accountID] || (roomID != "" && (assignment.RoomID == roomID || subscription.directory.Load())) {
			subscription.notify()
		}
	}
}

func (h *mahjongHub) lobbyCommand(client *mahjongClient, message map[string]any) {
	// This connection sees its command result before any snapshot that can
	// observe the mutation. Other subscribers can receive the state immediately.
	client.lobbyWriteMu.Lock()
	defer client.lobbyWriteMu.Unlock()
	commandID, _ := message["command_id"].(string)
	result := map[string]any{"type": "mahjong_lobby_result", "command_id": commandID, "ok": false, "message": ""}
	roomID, err := h.applyLobbyCommand(client, message, commandID)
	if err != nil {
		result["message"] = err.Error()
		switch {
		case errors.Is(err, matchmaking.ErrMahjongRoomPassword):
			result["code"] = "room_password_required"
		case errors.Is(err, matchmaking.ErrMahjongRoomNotFound):
			result["code"] = "room_not_found"
		}
	} else {
		result["ok"] = true
		h.mu.Lock()
		result["state"] = h.lobbyStateLocked(client.lobbyAccount)
		h.mu.Unlock()
	}
	// Also publish the ordinary state for subscribers and clients that only
	// consume the separate lobby snapshot.
	_ = client.writeJSON(result)
	if client.lobbyAccount != "" {
		h.publishLobby(roomID, client.lobbyAccount)
	}
}

func (h *mahjongHub) applyLobbyCommand(client *mahjongClient, message map[string]any, commandID string) (string, error) {
	if client.lobbyAccount == "" || h.matches == nil {
		return "", errors.New("请先订阅麻将大厅")
	}
	if strings.TrimSpace(commandID) == "" || len(commandID) > 128 {
		return "", errors.New("缺少有效的命令编号")
	}
	for _, key := range []string{"room_id", "rule_set_id", "rule_version"} {
		if value, present := message[key]; present {
			if _, ok := value.(string); !ok {
				return "", errors.New("房间号和玩法版本必须为文本")
			}
		}
	}
	roomID, _ := message["room_id"].(string)
	ruleID, _ := message["rule_set_id"].(string)
	version, _ := message["rule_version"].(string)
	req := matchmaking.QuickMatchRequest{
		AccountID: client.lobbyAccount, ProductID: string(domain.ProductMahjong), GameID: string(domain.GameMahjong),
		RuleSetID: ruleID, RuleVersion: version,
	}
	action, _ := message["action"].(string)
	password, err := mahjongRoomPassword(message, action)
	if err != nil {
		return "", err
	}
	var options *guiyang.RuleOptions
	if raw, present := message["options"]; present {
		if action != "create" {
			return "", errors.New("自定义规则仅用于创建好友房")
		}
		var err error
		options, err = decodeMahjongRuleOptions(raw)
		if err != nil {
			return "", err
		}
	}
	switch action {
	case "quick":
		result, err := h.quickMatch(req)
		return result.RoomID, err
	case "create":
		settings, err := decodeMahjongRoomSettings(message, password)
		if err != nil {
			return "", err
		}
		h.mu.Lock()
		defer h.mu.Unlock()
		id, err := h.matches.CreateMahjongRoomWithSettings(req, matchmaking.MahjongFriend, options, roomID, settings)
		if err == nil {
			err = h.persistFriendMutationLocked(id, nil)
		}
		return id, err
	case "join":
		h.mu.Lock()
		defer h.mu.Unlock()
		before := h.friendAssignment(roomID)
		err := h.matches.JoinMahjongFriendRoomWithPassword(req, roomID, password)
		if err == nil {
			err = h.persistFriendMutationLocked(roomID, before)
		}
		return roomID, err
	case "training":
		h.mu.Lock()
		defer h.mu.Unlock()
		return h.matches.CreateMahjongRoom(req, matchmaking.MahjongTraining, nil)
	case "ready", "unready", "leave":
		current, ok := h.matches.MahjongAssignment(req.AccountID)
		if !ok || (roomID != "" && current.RoomID != roomID) {
			return "", errors.New("玩家不属于该麻将房间")
		}
		if action == "leave" {
			return current.RoomID, h.leaveLobbyRoom(req.AccountID, current)
		}
		readiness := matchmaking.RoomReadyRequest{AccountID: req.AccountID, RoomID: current.RoomID}
		if action == "unready" {
			h.mu.Lock()
			defer h.mu.Unlock()
			before := h.friendAssignment(current.RoomID)
			err := h.matches.UnreadyMahjong(readiness)
			if err == nil {
				err = h.persistFriendMutationLocked(current.RoomID, before)
			}
			return current.RoomID, err
		}
		result, err := h.ready(readiness)
		return result.RoomID, err
	default:
		return "", errors.New("未知麻将大厅操作")
	}
}

func mahjongRoomPassword(message map[string]any, action string) (string, error) {
	value, present := message["password"]
	if !present {
		return "", nil
	}
	password, valid := value.(string)
	if !valid || (action != "create" && action != "join") {
		return "", errors.New("无效的麻将房间密码")
	}
	if password == "" {
		return "", nil
	}
	if len(password) == 4 && strings.Trim(password, "0123456789") == "" {
		return password, nil
	}
	return "", errors.New("房间密码须为四位数字")
}

func decodeMahjongRoomSettings(message map[string]any, password string) (matchmaking.MahjongRoomSettings, error) {
	var settings matchmaking.MahjongRoomSettings
	if raw, present := message["round_limit"]; present {
		limit, valid := raw.(float64)
		if !valid || math.Trunc(limit) != limit || limit < 0 || limit > 24 || !matchmaking.ValidMahjongRoundLimit(int(limit)) {
			return settings, errors.New("房间局数须为 8、16 或 24")
		}
		settings.RoundLimit = int(limit)
	}
	if raw, present := message["turn_timeout_seconds"]; present {
		seconds, valid := raw.(float64)
		if !valid || math.Trunc(seconds) != seconds || seconds < 1 || seconds > matchmaking.MaxMahjongTurnTimeoutSeconds {
			return settings, errors.New("出牌时限须为 1 至 60 秒的整数")
		}
		settings.TurnTimeoutSeconds = int(seconds)
	}
	if password != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err != nil {
			return settings, errors.New("无法设置房间密码，请重试")
		}
		settings.PasswordHash = string(hash)
	}
	return settings, nil
}

func (h *mahjongHub) quickMatch(req matchmaking.QuickMatchRequest) (matchmaking.QuickMatchResult, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.matches.QuickMatch(req)
}

func decodeMahjongRuleOptions(raw any) (*guiyang.RuleOptions, error) {
	fields, ok := raw.(map[string]any)
	if !ok || len(fields) != 6 {
		return nil, errors.New("请提交完整的麻将自定义规则")
	}
	version, ok := fields["version"].(string)
	if !ok || version != guiyang.RuleOptionsVersion {
		return nil, errors.New("未知的麻将自定义规则版本")
	}
	options := &guiyang.RuleOptions{Version: version}
	for key, target := range map[string]*bool{
		"chicken": &options.Chicken, "charge_chicken": &options.ChargeChicken,
		"black_eight": &options.BlackEight, "requires_kong_to_claim": &options.RequiresKongToClaim,
		"rob_kong": &options.RobKong,
	} {
		value, ok := fields[key].(bool)
		if !ok {
			return nil, errors.New("麻将自定义规则开关必须为布尔值")
		}
		*target = value
	}
	return options, nil
}

func (h *mahjongHub) leaveLobbyRoom(accountID string, current matchmaking.MahjongAssignment) error {
	training := current.Kind == matchmaking.MahjongTraining
	betweenFriendRounds := current.Kind == matchmaking.MahjongFriend && !current.Start && current.PreviousMatchID != ""
	if !training && current.Kind != matchmaking.MahjongFriend {
		_, err := h.matches.LeaveMahjong(accountID, current)
		return err
	}
	// Match creation and leave use the same hub-to-room lock order.
	h.mu.Lock()
	defer h.mu.Unlock()
	leave := func() (bool, error) {
		retained, err := h.leavePersistedFriendLocked(accountID, current)
		if err == nil {
			h.lobbyMu.Lock()
			h.restoreWaitingPresenceLocked(accountID)
			h.lobbyMu.Unlock()
		}
		return retained, err
	}
	active := h.rooms[current.RoomID]
	if active == nil || !active.createdAt.Equal(current.Room.CreatedAt) || (betweenFriendRounds && active.matchID != current.PreviousMatchID) {
		_, err := leave()
		return err
	}
	active.mu.Lock()
	defer active.mu.Unlock()
	retained, err := leave()
	if err != nil {
		return err
	}
	if training {
		active.closeLocked()
		delete(h.rooms, current.RoomID)
		return nil
	}
	for client := range active.clients {
		if client.accountID == accountID {
			delete(active.clients, client)
		}
	}
	if !retained {
		delete(h.rooms, current.RoomID)
	}
	return nil
}
