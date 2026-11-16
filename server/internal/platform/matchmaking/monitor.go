package matchmaking

import "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"

// RoomMonitorState is a detached view of a room's assigned seats.
type RoomMonitorState struct {
	Room            room.Room
	Accounts        []string
	Capacity        int
	ReadyPlayers    int
	Kind            string
	CompletedRounds int
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
		states[id] = RoomMonitorState{
			Room: item, Accounts: append([]string(nil), accounts...), Capacity: capacityFor(item.GameID),
			ReadyPlayers: m.readyCountLocked(id), Kind: m.mahjongKinds[id],
			CompletedRounds: m.mahjongRounds[id].completedRounds,
		}
	}
	return states
}
