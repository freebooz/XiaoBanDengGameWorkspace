package matchmaking

import (
	"maps"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

// RoomMonitorState is a detached view of a room's assigned seats.
type RoomMonitorState struct {
	Room              room.Room
	Accounts          []string
	Capacity          int
	ReadyPlayers      int
	ReadyAccounts     map[string]bool
	Kind              string
	CompletedRounds   int
	RoundLimit        int
	AdmissionPaused   bool
	AdmissionRevision int64
}

// RoomMonitorStates copies rosters while holding the assignment lock so
// moving a seat cannot leave a partially updated roster in a monitor view.
func (m *Manager) RoomMonitorStates() map[string]RoomMonitorState {
	m.mu.Lock()
	defer m.mu.Unlock()
	states := make(map[string]RoomMonitorState, len(m.playersByRoom))
	for id, accounts := range m.playersByRoom {
		item, exists := m.rooms.Get(id)
		if !exists {
			continue
		}
		settings := m.mahjongSettings[id]
		states[id] = RoomMonitorState{
			Room: item, Accounts: append([]string(nil), accounts...), Capacity: capacityFor(item.GameID),
			ReadyPlayers: m.readyCountLocked(id), ReadyAccounts: maps.Clone(m.readyByRoom[id]), Kind: m.mahjongKinds[id],
			CompletedRounds: m.mahjongRounds[id].completedRounds, RoundLimit: settings.RoundLimit,
			AdmissionPaused: settings.AdmissionPaused, AdmissionRevision: settings.AdmissionRevision,
		}
	}
	return states
}
