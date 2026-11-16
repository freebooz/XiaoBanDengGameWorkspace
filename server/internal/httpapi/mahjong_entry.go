package httpapi

import (
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

type mahjongEntry struct {
	assignment matchmaking.MahjongAssignment
	previous   *mahjongRoom
	timer      *time.Timer
}

func (h *mahjongHub) ready(req matchmaking.RoomReadyRequest) (matchmaking.RoomReadyResult, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	before := h.friendAssignment(req.RoomID)
	result, err := h.matches.Ready(req)
	if err == nil {
		err = h.persistFriendMutationLocked(req.RoomID, before)
	}
	if err != nil || !result.Start || h.entries[result.RoomID] != nil {
		return result, err
	}
	current, assigned := h.matches.MahjongAssignment(req.AccountID)
	if !assigned || !current.Start || current.Kind == matchmaking.MahjongTraining {
		return result, err
	}
	existing := h.rooms[result.RoomID]
	if existing != nil && existing.belongsToRound(current) {
		return result, err
	}
	deadline := time.Now().Add(h.entryTimeout)
	if head := h.friendHead(current.RoomID); head != nil && !head.image.EntryDeadline.IsZero() {
		deadline = head.image.EntryDeadline
	}
	h.scheduleEntryLocked(current, existing, deadline)
	return result, nil
}

func (h *mahjongHub) scheduleEntryLocked(current matchmaking.MahjongAssignment, existing *mahjongRoom, deadline time.Time) {
	entry := &mahjongEntry{assignment: current}
	if existing != nil && existing.matchID == current.PreviousMatchID && existing.createdAt.Equal(current.Room.CreatedAt) {
		entry.previous = existing
	}
	h.entries[current.RoomID] = entry
	entry.timer = time.AfterFunc(time.Until(deadline), func() { h.expireEntry(entry) })
}

func (h *mahjongHub) stopEntryTimeout(room *mahjongRoom) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if entry := h.entries[room.id]; entry != nil && h.rooms[room.id] == room && room.belongsToRound(entry.assignment) {
		delete(h.entries, room.id)
		entry.timer.Stop()
	}
}

func (h *mahjongHub) expireEntry(entry *mahjongEntry) {
	roomID := entry.assignment.RoomID
	h.mu.Lock()
	if h.stopping.Load() || h.entries[roomID] != entry {
		h.mu.Unlock()
		return
	}
	delete(h.entries, roomID)
	room := h.rooms[roomID]
	if room != nil && !room.belongsToRound(entry.assignment) {
		room = nil
	}
	if room != nil {
		room.mu.Lock()
		if room.started || room.persistPending {
			room.mu.Unlock()
			h.mu.Unlock()
			return
		}
	}
	before := h.friendAssignment(roomID)
	players, expired := h.matches.ExpireMahjongEntry(entry.assignment)
	if expired && h.persistFriendMutationLocked(roomID, before) != nil {
		h.entries[roomID] = entry
		entry.timer = time.AfterFunc(time.Second, func() { h.expireEntry(entry) })
		expired = false
	}
	if expired && h.friendStore != nil {
		if current := h.friendAssignment(roomID); current != nil {
			h.startAbsentFriendGrace(*current)
		}
	}
	var joined []*mahjongClient
	if room != nil {
		if expired {
			room.closeLocked()
			delete(h.rooms, roomID)
			if entry.previous != nil {
				h.rooms[roomID] = entry.previous
			}
			for client := range room.clients {
				joined = append(joined, client)
			}
		}
		room.mu.Unlock()
	}
	h.mu.Unlock()
	if !expired {
		return
	}
	h.publishLobby(roomID, players...)
	for _, client := range joined {
		_ = client.writeJSON(map[string]any{
			"type": "mahjong_entry_cancelled", "room_id": roomID, "match_id": room.matchID,
			"message": "有人未及时入桌，请重新准备或匹配",
		})
	}
}
