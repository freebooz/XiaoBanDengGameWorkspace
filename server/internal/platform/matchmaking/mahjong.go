package matchmaking

import (
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"golang.org/x/crypto/bcrypt"
)

const (
	MahjongQuick    = "quick"
	MahjongFriend   = "friend"
	MahjongTraining = "training"

	DefaultMahjongTurnTimeoutSeconds = 15
	MaxMahjongTurnTimeoutSeconds     = 60
)

type MahjongAssignment struct {
	QuickMatchResult
	Room              room.Room
	Kind              string
	Rule              guiyang.RuleDescriptor
	ReadyAccountIDs   []string
	CompletedRounds   int
	PreviousMatchID   string
	NextDealer        int    `json:",omitempty"`
	NextDealerAccount string `json:",omitempty"`
	Series            MahjongSeries
	Settings          MahjongRoomSettings
}

type MahjongRoomSettings struct {
	RoundLimit         int    `json:"round_limit,omitempty"`
	TurnTimeoutSeconds int    `json:"turn_timeout_seconds,omitempty"`
	PasswordHash       string `json:"password_hash,omitempty"`
	AllowSpectators    bool   `json:"allow_spectators,omitempty"`
	AdmissionPaused    bool   `json:"admission_paused,omitempty"`
	AdmissionRevision  int64  `json:"admission_revision,omitempty"`
}

var (
	ErrMahjongRoomNotFound          = errors.New("好友房不存在或已关闭")
	ErrMahjongRoomPassword          = errors.New("请输入正确的四位房间密码")
	ErrMahjongRoomAdmissionPaused   = errors.New("该好友房已暂停新玩家入座")
	ErrMahjongRoomAdmissionConflict = errors.New("房间状态已变化或当前不允许调整入座")
)

func ValidMahjongRoundLimit(limit int) bool {
	return limit == 0 || limit == 8 || limit == 16 || limit == 24
}

func (s MahjongRoomSettings) validTurnTimeout() bool {
	return s.TurnTimeoutSeconds >= 0 && s.TurnTimeoutSeconds <= MaxMahjongTurnTimeoutSeconds
}

func (s MahjongRoomSettings) EffectiveTurnTimeoutSeconds() int {
	if s.TurnTimeoutSeconds == 0 {
		return DefaultMahjongTurnTimeoutSeconds
	}
	return s.TurnTimeoutSeconds
}

func (s MahjongRoomSettings) VerifyPassword(password string) error {
	if s.PasswordHash != "" && (len(password) != 4 || bcrypt.CompareHashAndPassword([]byte(s.PasswordHash), []byte(password)) != nil) {
		return ErrMahjongRoomPassword
	}
	return nil
}

func (a MahjongAssignment) CanPlayAnotherRound() bool {
	return a.Kind == MahjongFriend && (a.Settings.RoundLimit == 0 || a.CompletedRounds < a.Settings.RoundLimit-1)
}

type MahjongPublicRoom struct {
	RoomID          string `json:"room_id"`
	RuleSetID       string `json:"rule_set_id"`
	RuleName        string `json:"rule_name"`
	Players         int    `json:"players"`
	Capacity        int    `json:"capacity"`
	RoundLimit      int    `json:"round_limit"`
	AdmissionPaused bool   `json:"admission_paused"`
	Joinable        bool   `json:"joinable"`
	WatchableSeats  []int  `json:"watchable_seats,omitempty"`
}

func (m *Manager) MahjongPublicRooms() []MahjongPublicRoom {
	m.mu.Lock()
	defer m.mu.Unlock()
	rooms := []MahjongPublicRoom{}
	for _, item := range m.rooms.List() {
		settings := m.mahjongSettings[item.RoomID]
		if m.mahjongKinds[item.RoomID] != MahjongFriend || settings.PasswordHash != "" {
			continue
		}
		count := len(m.playersByRoom[item.RoomID])
		if count == 0 || (item.State != "waiting" && item.State != "matched" && item.State != "playing") {
			continue
		}
		capacity := capacityFor(item.GameID)
		rooms = append(rooms, MahjongPublicRoom{
			RoomID: item.RoomID, RuleSetID: item.RuleSetID, RuleName: m.mahjongRules[item.RoomID].Name,
			Players: count, Capacity: capacity, RoundLimit: settings.RoundLimit, AdmissionPaused: settings.AdmissionPaused,
			Joinable: item.State == "waiting" && count < capacity && !settings.AdmissionPaused,
		})
	}
	return rooms
}

type mahjongRoundHistory struct {
	completedRounds   int
	previousMatchID   string
	nextDealer        int
	nextDealerAccount string
	series            MahjongSeries
}

func (m *Manager) MahjongAssignment(accountID string) (MahjongAssignment, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.mahjongAssignmentLocked(accountID)
}

func (m *Manager) mahjongAssignmentLocked(accountID string) (MahjongAssignment, bool) {
	current, assigned := m.assignments[accountID]
	if !assigned {
		return MahjongAssignment{}, false
	}
	item, exists := m.rooms.Get(current.RoomID)
	if !exists || item.GameID != string(domain.GameMahjong) {
		return MahjongAssignment{}, false
	}
	result := m.resultLocked(current.RoomID, accountID)
	kind := m.mahjongKinds[current.RoomID]
	if kind == "" {
		kind = MahjongQuick
	}
	ready := []string{}
	for _, player := range result.PlayerAccountIDs {
		if m.readyByRoom[current.RoomID][player] {
			ready = append(ready, player)
		}
	}
	history := m.mahjongRounds[current.RoomID]
	rule, hasLockedRule := m.mahjongRules[current.RoomID]
	if !hasLockedRule {
		rule, _ = guiyang.FindRuleDescriptor(item.RuleSetID, item.RuleVersion)
	}
	return MahjongAssignment{
		QuickMatchResult: result, Room: item, Kind: kind, Rule: rule, ReadyAccountIDs: ready,
		CompletedRounds: history.completedRounds, PreviousMatchID: history.previousMatchID, NextDealer: history.nextDealer,
		NextDealerAccount: history.nextDealerAccount,
		Series:            MahjongSeries{Rounds: history.series.Rounds, Scores: slices.Clone(history.series.Scores)},
		Settings:          m.mahjongSettings[item.RoomID],
	}, true
}

// SettleMahjongRound checks the room incarnation and the round being settled.
// It reports whether the friend room was retained with no ready seats.
func (m *Manager) SettleMahjongRound(roomID string, createdAt time.Time, completedRounds int, matchID string, nextDealer int, scores ...[4]int) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	item, exists := m.rooms.Get(roomID)
	if !exists || item.GameID != string(domain.GameMahjong) || item.State != "playing" || !item.CreatedAt.Equal(createdAt) {
		return false
	}
	history := m.mahjongRounds[roomID]
	if completedRounds != history.completedRounds || matchID == "" || matchID == history.previousMatchID {
		return false
	}
	if m.mahjongKinds[roomID] != MahjongFriend {
		m.finishRoomLocked(roomID)
		return false
	}
	projected, ok := m.projectMahjongFriendSettlementLocked(roomID, createdAt, completedRounds, matchID, nextDealer, scores...)
	if !ok {
		return false
	}
	if projected.Room.State == "closed" {
		m.finishRoomLocked(roomID)
		return false
	}
	if !m.rooms.SetState(roomID, projected.Room.State) {
		return false
	}
	delete(m.readyByRoom, roomID)
	m.mahjongRounds[roomID] = projected.roundHistory()
	return true
}

func (m *Manager) CreateMahjongRoom(req QuickMatchRequest, kind string, options *guiyang.RuleOptions) (string, error) {
	return m.CreateMahjongRoomWithSettings(req, kind, options, "", MahjongRoomSettings{})
}

func (m *Manager) CreateMahjongRoomWithSettings(req QuickMatchRequest, kind string, options *guiyang.RuleOptions, roomID string, settings MahjongRoomSettings) (string, error) {
	if err := validateRequest(req); err != nil {
		return "", err
	}
	if req.GameID != string(domain.GameMahjong) || (kind != MahjongFriend && kind != MahjongTraining) {
		return "", errors.New("未知的麻将房间类型")
	}
	if options != nil && kind != MahjongFriend {
		return "", errors.New("自定义规则仅用于创建好友房")
	}
	if !ValidMahjongRoundLimit(settings.RoundLimit) || !settings.validTurnTimeout() || settings.AdmissionPaused || settings.AdmissionRevision != 0 ||
		(kind != MahjongFriend && (roomID != "" || settings != (MahjongRoomSettings{}))) {
		return "", errors.New("无效的麻将房间设置")
	}
	rule, err := guiyang.ResolveRuleDescriptor(req.RuleSetID, req.RuleVersion, options)
	if err != nil {
		return "", err
	}
	if kind == MahjongTraining && (req.AccountID == "电脑1" || req.AccountID == "电脑2" || req.AccountID == "电脑3") {
		return "", errors.New("无效的训练玩家账号")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if current, assigned := m.assignments[req.AccountID]; assigned {
		if _, exists := m.rooms.Get(current.RoomID); exists {
			return "", errors.New("请先退出当前房间")
		}
	}
	created, err := m.rooms.Create(room.CreateRequest{
		ProductID: req.ProductID, GameID: req.GameID, RuleSetID: req.RuleSetID, RuleVersion: req.RuleVersion,
		RequestedRoomID: roomID,
	})
	if err != nil {
		return "", err
	}
	players := []string{req.AccountID}
	ready := map[string]bool{}
	if kind == MahjongTraining {
		for seat := 1; seat < 4; seat++ {
			players = append(players, fmt.Sprintf("电脑%d", seat))
		}
		for _, player := range players {
			ready[player] = true
		}
		m.rooms.SetState(created.RoomID, "playing")
	}
	m.assignments[req.AccountID] = assignment{RoomID: created.RoomID}
	m.playersByRoom[created.RoomID] = players
	m.readyByRoom[created.RoomID] = ready
	m.mahjongKinds[created.RoomID] = kind
	m.mahjongRules[created.RoomID] = rule
	m.mahjongSettings[created.RoomID] = settings
	return created.RoomID, nil
}

func (m *Manager) JoinMahjongFriendRoom(req QuickMatchRequest, roomID string) error {
	return m.JoinMahjongFriendRoomWithPassword(req, roomID, "")
}

func (m *Manager) JoinMahjongFriendRoomWithPassword(req QuickMatchRequest, roomID, password string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if strings.TrimSpace(req.AccountID) == "" {
		return errors.New("缺少玩家账号")
	}
	item, exists := m.rooms.Get(roomID)
	if !exists || item.State == "closed" || m.mahjongKinds[roomID] != MahjongFriend {
		return ErrMahjongRoomNotFound
	}
	if (req.RuleSetID != "" || req.RuleVersion != "") && (item.RuleSetID != req.RuleSetID || item.RuleVersion != req.RuleVersion) {
		return errors.New("房间玩法与所选玩法不一致")
	}
	if current, assigned := m.assignments[req.AccountID]; assigned {
		if current.RoomID == roomID {
			return nil
		}
		if _, exists := m.rooms.Get(current.RoomID); exists {
			return errors.New("请先退出当前房间")
		}
	}
	players := m.playersByRoom[roomID]
	if item.State != "waiting" || len(players) >= capacityFor(item.GameID) {
		return errors.New("好友房已满或已经开局")
	}
	settings := m.mahjongSettings[roomID]
	if settings.AdmissionPaused {
		return ErrMahjongRoomAdmissionPaused
	}
	if err := settings.VerifyPassword(password); err != nil {
		return err
	}
	// Older waiting snapshots could still name a dealer who had already left.
	if history := m.mahjongRounds[roomID]; len(players) > 0 && history.nextDealerAccount != "" && !slices.Contains(players, history.nextDealerAccount) {
		history.nextDealer, history.nextDealerAccount = 0, players[0]
		m.mahjongRounds[roomID] = history
	}
	players = append(players, req.AccountID)
	m.playersByRoom[roomID] = players
	m.assignments[req.AccountID] = assignment{RoomID: roomID}
	if len(players) == capacityFor(item.GameID) {
		m.rooms.SetState(roomID, "matched")
	}
	return nil
}

// CommitMahjongFriendAdmission compares the room generation and admission
// revision under the roster lock. The callback persists the projected image
// before readers and seat commands can observe it.
func (m *Manager) CommitMahjongFriendAdmission(roomID string, generation time.Time, expectedRevision int64, paused bool, commit func(MahjongAssignment) error) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	current, exists := m.mahjongFriendRoomSnapshotLocked(roomID)
	if !exists {
		return ErrMahjongRoomNotFound
	}
	if !current.Room.CreatedAt.Equal(generation) || current.Room.State != "waiting" || current.Players >= current.Capacity ||
		current.Settings.AdmissionRevision != expectedRevision || expectedRevision == math.MaxInt64 || current.Settings.AdmissionPaused == paused {
		return ErrMahjongRoomAdmissionConflict
	}
	current.Settings.AdmissionPaused = paused
	current.Settings.AdmissionRevision++
	if err := commit(current); err != nil {
		return err
	}
	m.mahjongSettings[roomID] = current.Settings
	return nil
}

// UnreadyMahjong and Ready use the same lock so the last ready and a
// withdrawal have a single, authoritative order.
func (m *Manager) UnreadyMahjong(req RoomReadyRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	current, exists := m.mahjongAssignmentLocked(req.AccountID)
	if !exists || current.RoomID != req.RoomID {
		return errors.New("玩家不属于该麻将房间")
	}
	if current.Room.State != "matched" && (current.Room.State != "waiting" || current.Kind != MahjongFriend) {
		return errors.New("当前房间状态不允许取消准备")
	}
	delete(m.readyByRoom[req.RoomID], req.AccountID)
	return nil
}

// ExpireMahjongEntry releases a quick match or returns a friend room to
// preparation. The caller serializes expiry with the first deal.
func (m *Manager) ExpireMahjongEntry(expected MahjongAssignment) ([]string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	item, exists := m.rooms.Get(expected.RoomID)
	if !exists || item.GameID != string(domain.GameMahjong) || item.State != "playing" ||
		!item.CreatedAt.Equal(expected.Room.CreatedAt) || m.mahjongRounds[expected.RoomID].completedRounds != expected.CompletedRounds {
		return nil, false
	}
	players := append([]string(nil), m.playersByRoom[expected.RoomID]...)
	if expected.Kind == MahjongFriend {
		m.rooms.SetState(expected.RoomID, "matched")
		delete(m.readyByRoom, expected.RoomID)
	} else {
		m.finishRoomLocked(expected.RoomID)
	}
	return players, true
}

// LeaveMahjong limits a lobby command to the caller's current Mahjong room.
// Training seats have no separate human assignments, so ending the table is atomic.
// On success it reports whether the room still has assigned players.
func (m *Manager) LeaveMahjong(accountID string, expected MahjongAssignment) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	current, exists := m.mahjongAssignmentLocked(accountID)
	if !exists || current.RoomID != expected.RoomID || !current.Room.CreatedAt.Equal(expected.Room.CreatedAt) || current.CompletedRounds != expected.CompletedRounds {
		return false, errors.New("玩家不属于该麻将房间")
	}
	if current.Kind == MahjongTraining {
		m.finishRoomLocked(current.RoomID)
		return false, nil
	}
	if err := m.cancelLocked(accountID); err != nil {
		return false, err
	}
	remaining := m.playersByRoom[current.RoomID]
	if current.Kind == MahjongFriend && len(remaining) > 0 {
		history := m.mahjongRounds[current.RoomID]
		history.nextDealer, history.nextDealerAccount = current.NextDealerAfterLeave(remaining)
		m.mahjongRounds[current.RoomID] = history
	}
	return len(remaining) > 0, nil
}
