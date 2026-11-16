package matchmaking

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
)

// RestoreMahjongAssignment reconstructs a live room from an authoritative
// snapshot. Replaying the same image is safe if the room has not moved on.
func (m *Manager) RestoreMahjongAssignment(saved MahjongAssignment) error {
	ready, humanCount, err := validateMahjongRestore(saved)
	if err != nil {
		return err
	}
	roomID := saved.RoomID
	humanPlayers := saved.PlayerAccountIDs[:humanCount]
	key := ""
	if saved.Kind == MahjongQuick {
		key = queueKey(QuickMatchRequest{ProductID: saved.ProductID, GameID: saved.GameID, RuleSetID: saved.RuleSetID, RuleVersion: saved.RuleVersion})
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	if _, exists := m.rooms.Get(roomID); exists {
		if m.isRestoredMahjongAssignment(saved, humanPlayers) {
			return nil
		}
		return errors.New("麻将恢复房间与活动房间冲突")
	}
	if err := m.insertMahjongRoomLocked(saved, humanPlayers); err != nil {
		return err
	}
	m.installMahjongRoomLocked(saved, humanPlayers, key, ready)
	return nil
}

func (m *Manager) installMahjongRoomLocked(saved MahjongAssignment, humanPlayers []string, key string, ready map[string]bool) {
	roomID := saved.RoomID
	for _, accountID := range humanPlayers {
		m.assignments[accountID] = assignment{RoomID: roomID, Key: key}
	}
	m.playersByRoom[roomID] = slices.Clone(saved.PlayerAccountIDs)
	m.readyByRoom[roomID] = ready
	m.mahjongKinds[roomID] = saved.Kind
	m.mahjongRules[roomID] = saved.Rule
	m.mahjongSettings[roomID] = saved.Settings
	m.mahjongRounds[roomID] = mahjongRoundHistory{completedRounds: saved.CompletedRounds, previousMatchID: saved.PreviousMatchID}
}

func (m *Manager) insertMahjongRoomLocked(saved MahjongAssignment, humanPlayers []string) error {
	if len(m.playersByRoom[saved.RoomID]) != 0 {
		return errors.New("麻将恢复房间号已有座位记录")
	}
	if !m.mahjongRosterAvailableLocked(humanPlayers, saved.RoomID) {
		return errors.New("麻将恢复玩家已有活动房间")
	}
	return m.rooms.Restore(saved.Room)
}

func (m *Manager) mahjongRosterAvailableLocked(roster []string, roomID string) bool {
	for _, accountID := range roster {
		if current, assigned := m.assignments[accountID]; assigned && current.RoomID != roomID {
			if _, exists := m.rooms.Get(current.RoomID); exists {
				return false
			}
		}
	}
	return true
}

func (m *Manager) isRestoredMahjongAssignment(saved MahjongAssignment, humanPlayers []string) bool {
	current, exists := m.mahjongAssignmentLocked(humanPlayers[0])
	if !exists || current.RoomID != saved.RoomID || !current.Room.CreatedAt.Equal(saved.Room.CreatedAt) {
		return false
	}
	if !sameMahjongRoomImage(current, saved) {
		return false
	}
	for _, accountID := range humanPlayers {
		if m.assignments[accountID].RoomID != saved.RoomID {
			return false
		}
	}
	return true
}

func validateMahjongRestore(saved MahjongAssignment) (map[string]bool, int, error) {
	const seats = 4
	item := saved.Room
	playersCount := len(saved.PlayerAccountIDs)
	readyCount := len(saved.ReadyAccountIDs)
	if item.RoomID != saved.RoomID || item.ProductID != saved.ProductID || item.GameID != saved.GameID ||
		item.RuleSetID != saved.RuleSetID || item.RuleVersion != saved.RuleVersion ||
		saved.Capacity != seats || saved.Players != playersCount || saved.ReadyPlayers != readyCount || readyCount > playersCount {
		return nil, 0, errors.New("无效的麻将活动房间快照")
	}
	validState := false
	switch item.State {
	case "waiting":
		validState = saved.Kind == MahjongFriend && saved.Status == StatusWaiting && !saved.Start && playersCount > 0 && playersCount < seats
	case "matched":
		validState = saved.Kind == MahjongFriend && saved.Status == StatusMatched && !saved.Start && playersCount == seats && readyCount < seats
	case "playing":
		validState = saved.Status == StatusMatched && saved.Start && playersCount == seats && readyCount == seats
	}
	if !validState {
		return nil, 0, errors.New("无效的麻将恢复房间阶段")
	}
	if err := ValidateMahjongRule(saved.ProductID, saved.GameID, saved.RuleSetID, saved.RuleVersion); err != nil {
		return nil, 0, err
	}
	humanCount := playersCount
	if !ValidMahjongRoundLimit(saved.Settings.RoundLimit) || !saved.Settings.validTurnTimeout() ||
		(saved.Kind != MahjongFriend && saved.Settings != (MahjongRoomSettings{})) ||
		(saved.Settings.RoundLimit > 0 && saved.CompletedRounds >= saved.Settings.RoundLimit) {
		return nil, 0, errors.New("无效的麻将恢复房间设置")
	}
	var options *guiyang.RuleOptions
	switch saved.Kind {
	case MahjongFriend:
		options = &saved.Rule.Options
	case MahjongQuick:
	case MahjongTraining:
		humanCount = 1
	default:
		return nil, 0, errors.New("无效的麻将恢复房间类型")
	}
	if saved.CompletedRounds < 0 || (saved.CompletedRounds == 0) != (saved.PreviousMatchID == "") ||
		(saved.Kind != MahjongFriend && saved.CompletedRounds != 0) || strings.TrimSpace(saved.PreviousMatchID) != saved.PreviousMatchID {
		return nil, 0, errors.New("无效的麻将恢复轮次")
	}
	rule, err := guiyang.ResolveRuleDescriptor(saved.RuleSetID, saved.RuleVersion, options)
	if err != nil || rule != saved.Rule {
		return nil, 0, errors.New("无效的麻将恢复规则")
	}
	players := make(map[string]bool, seats)
	for seat, accountID := range saved.PlayerAccountIDs {
		if accountID == "" || strings.TrimSpace(accountID) != accountID || players[accountID] {
			return nil, 0, errors.New("无效的麻将恢复座位")
		}
		isBot := accountID == "电脑1" || accountID == "电脑2" || accountID == "电脑3"
		if (seat < humanCount && isBot) || (seat >= humanCount && accountID != fmt.Sprintf("电脑%d", seat)) {
			return nil, 0, errors.New("无效的麻将恢复训练座位")
		}
		players[accountID] = true
	}
	ready := make(map[string]bool, seats)
	for _, accountID := range saved.ReadyAccountIDs {
		if !players[accountID] || ready[accountID] {
			return nil, 0, errors.New("无效的麻将恢复准备状态")
		}
		ready[accountID] = true
	}
	return ready, humanCount, nil
}

func sameMahjongRoomImage(current, expected MahjongAssignment) bool {
	if !current.Room.CreatedAt.Equal(expected.Room.CreatedAt) {
		return false
	}
	current.Room.CreatedAt = expected.Room.CreatedAt
	return current.Room == expected.Room && current.Kind == expected.Kind && current.Rule == expected.Rule && current.Settings == expected.Settings && current.Start == expected.Start &&
		slices.Equal(current.PlayerAccountIDs, expected.PlayerAccountIDs) && slices.Equal(current.ReadyAccountIDs, expected.ReadyAccountIDs) &&
		current.CompletedRounds == expected.CompletedRounds && current.PreviousMatchID == expected.PreviousMatchID
}
