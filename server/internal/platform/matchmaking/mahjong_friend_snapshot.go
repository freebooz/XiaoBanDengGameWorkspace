package matchmaking

import (
	"errors"
	"math"
	"strings"
	"time"
)

// MahjongFriendRoomSnapshot returns a room image independent of which player
// requested it. The seat-relative fields always describe the first seat.
func (m *Manager) MahjongFriendRoomSnapshot(roomID string) (MahjongAssignment, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.mahjongFriendRoomSnapshotLocked(roomID)
}

func (m *Manager) mahjongFriendRoomSnapshotLocked(roomID string) (MahjongAssignment, bool) {
	players := m.playersByRoom[roomID]
	if m.mahjongKinds[roomID] != MahjongFriend || len(players) == 0 {
		return MahjongAssignment{}, false
	}
	snapshot, exists := m.mahjongAssignmentLocked(players[0])
	return snapshot, exists && snapshot.RoomID == roomID
}

// ProjectMahjongFriendSettlement describes the retained room after the given
// round, leaving current matchmaking state untouched until persistence commits.
func (m *Manager) ProjectMahjongFriendSettlement(roomID string, createdAt time.Time, completedRounds int, matchID string) (MahjongAssignment, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.projectMahjongFriendSettlementLocked(roomID, createdAt, completedRounds, matchID)
}

func (m *Manager) projectMahjongFriendSettlementLocked(roomID string, createdAt time.Time, completedRounds int, matchID string) (MahjongAssignment, bool) {
	current, exists := m.mahjongFriendRoomSnapshotLocked(roomID)
	if !exists || !current.Start || !current.Room.CreatedAt.Equal(createdAt) || current.CompletedRounds != completedRounds ||
		completedRounds == math.MaxInt || matchID == "" || matchID == current.PreviousMatchID || strings.TrimSpace(matchID) != matchID {
		return MahjongAssignment{}, false
	}
	current.Room.State = "matched"
	if !current.CanPlayAnotherRound() {
		current.Room.State = "closed"
	}
	current.Start = false
	current.ReadyPlayers = 0
	current.ReadyAccountIDs = []string{}
	current.CompletedRounds++
	current.PreviousMatchID = matchID
	return current, true
}

// ReconcileMahjongFriendRoom applies a persisted image or rolls back a failed
// write, provided the exact expected room incarnation, roster, and state still
// hold. Nil represents absence. The caller serializes with other persistence.
func (m *Manager) ReconcileMahjongFriendRoom(expected, desired *MahjongAssignment) error {
	if expected == nil && desired == nil {
		return errors.New("缺少好友房快照")
	}
	var roomID string
	var ready map[string]bool
	for _, snapshot := range []*MahjongAssignment{expected, desired} {
		if snapshot == nil {
			continue
		}
		if snapshot.Kind != MahjongFriend {
			return errors.New("只能校正好友房")
		}
		validatedReady, _, err := validateMahjongRestore(*snapshot)
		if err != nil {
			return err
		}
		if snapshot == desired {
			ready = validatedReady
		}
		roomID = snapshot.RoomID
	}
	if expected != nil && desired != nil {
		oldRoom, newRoom := expected.Room, desired.Room
		if !oldRoom.CreatedAt.Equal(newRoom.CreatedAt) || expected.Rule != desired.Rule || expected.Settings != desired.Settings {
			return errors.New("不能更改好友房身份或规则")
		}
		oldRoom.CreatedAt, oldRoom.State = newRoom.CreatedAt, newRoom.State
		if oldRoom != newRoom {
			return errors.New("不能更改好友房身份或规则")
		}
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if expected == nil {
		if err := m.insertMahjongRoomLocked(*desired, desired.PlayerAccountIDs); err != nil {
			return err
		}
	} else {
		current, exists := m.mahjongFriendRoomSnapshotLocked(roomID)
		if !exists || !sameMahjongRoomImage(current, *expected) {
			return errors.New("好友房已变化，不能校正")
		}
		if desired == nil {
			m.finishRoomLocked(roomID)
			return nil
		}
		if !m.mahjongRosterAvailableLocked(desired.PlayerAccountIDs, roomID) || !m.rooms.SetState(roomID, desired.Room.State) {
			return errors.New("好友房玩家已有活动房间或房间已失效")
		}
		for _, player := range current.PlayerAccountIDs {
			if m.assignments[player].RoomID == roomID {
				delete(m.assignments, player)
			}
		}
	}
	m.installMahjongRoomLocked(*desired, desired.PlayerAccountIDs, "", ready)
	return nil
}
