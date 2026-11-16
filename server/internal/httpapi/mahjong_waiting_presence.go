package httpapi

import (
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

const mahjongWaitingGrace = 30 * time.Second

type mahjongWaitingDisconnect struct {
	assignment matchmaking.MahjongAssignment
	timer      *time.Timer
}

func waitingMahjongAssignment(assignment matchmaking.MahjongAssignment) bool {
	return !assignment.Start &&
		(assignment.Kind == matchmaking.MahjongFriend || assignment.Kind == matchmaking.MahjongQuick) &&
		(assignment.Status == matchmaking.StatusWaiting || assignment.Status == matchmaking.StatusMatched)
}

func sameWaitingMahjongRoom(current, expected matchmaking.MahjongAssignment) bool {
	return waitingMahjongAssignment(current) && current.RoomID == expected.RoomID &&
		current.Room.CreatedAt.Equal(expected.Room.CreatedAt) &&
		current.CompletedRounds == expected.CompletedRounds
}

// restoreWaitingPresenceLocked runs when an authenticated lobby socket subscribes.
// The identity check in expireWaitingPresence also covers an already-fired timer.
func (h *mahjongHub) restoreWaitingPresenceLocked(accountID string) string {
	disconnected := h.waitingDisconnects[accountID]
	if disconnected == nil {
		return ""
	}
	delete(h.waitingDisconnects, accountID)
	disconnected.timer.Stop()
	return disconnected.assignment.RoomID
}

func (h *mahjongHub) disconnectLobby(client *mahjongClient) {
	h.lobbyMu.Lock()
	subscription := h.lobbyClients[client]
	if subscription == nil {
		h.lobbyMu.Unlock()
		return
	}
	delete(h.lobbyClients, client)
	close(subscription.done)
	h.monitor.notify()
	accountID := subscription.accountID
	for _, active := range h.lobbyClients {
		if active.accountID == accountID {
			h.lobbyMu.Unlock()
			return
		}
	}
	current, assigned := h.matches.MahjongAssignment(accountID)
	if !assigned || !waitingMahjongAssignment(current) {
		h.lobbyMu.Unlock()
		return
	}
	h.startWaitingGraceLocked(accountID, current)
	h.lobbyMu.Unlock()
	h.publishLobby(current.RoomID)
}

func (h *mahjongHub) startWaitingGraceLocked(accountID string, current matchmaking.MahjongAssignment) {
	if h.stopping.Load() {
		return
	}
	if old := h.waitingDisconnects[accountID]; old != nil {
		if sameWaitingMahjongRoom(current, old.assignment) {
			return
		}
		old.timer.Stop()
	}
	disconnected := &mahjongWaitingDisconnect{assignment: current}
	h.waitingDisconnects[accountID] = disconnected
	disconnected.timer = time.AfterFunc(h.waitingGrace, func() {
		h.expireWaitingPresence(accountID, disconnected)
	})
}

// Reestablish bounded presence for seats whose sockets were lost on a
// restart, or while their room was playing and could not release seats.
func (h *mahjongHub) startAbsentFriendGrace(current matchmaking.MahjongAssignment) {
	if current.Kind != matchmaking.MahjongFriend || !waitingMahjongAssignment(current) {
		return
	}
	h.lobbyMu.Lock()
	defer h.lobbyMu.Unlock()
	connected := make(map[string]bool, len(h.lobbyClients))
	for _, subscriber := range h.lobbyClients {
		connected[subscriber.accountID] = true
	}
	for _, accountID := range current.PlayerAccountIDs {
		if !connected[accountID] {
			h.startWaitingGraceLocked(accountID, current)
		}
	}
}

func (h *mahjongHub) expireWaitingPresence(accountID string, disconnected *mahjongWaitingDisconnect) {
	expected := disconnected.assignment
	// Follow the settlement lock order. Settlement may publish while holding
	// the room lock, so never acquire the hub or room locks under lobbyMu.
	h.mu.Lock()
	active := h.rooms[expected.RoomID]
	if active != nil && (!active.createdAt.Equal(expected.Room.CreatedAt) ||
		expected.PreviousMatchID == "" || active.matchID != expected.PreviousMatchID) {
		active = nil
	}
	if active != nil {
		active.mu.Lock()
	}
	h.lobbyMu.Lock()
	var removed bool
	if !h.stopping.Load() && h.waitingDisconnects[accountID] == disconnected {
		delete(h.waitingDisconnects, accountID)
		current, assigned := h.matches.MahjongAssignment(accountID)
		if assigned && sameWaitingMahjongRoom(current, expected) {
			retained, err := h.leavePersistedFriendLocked(accountID, expected)
			if err == nil {
				removed = true
			} else if expected.Kind == matchmaking.MahjongFriend {
				h.waitingDisconnects[accountID] = disconnected
				disconnected.timer = time.AfterFunc(time.Second, func() { h.expireWaitingPresence(accountID, disconnected) })
			}
			if removed && active != nil {
				for client := range active.clients {
					if client.accountID == accountID {
						delete(active.clients, client)
					}
				}
				if !retained {
					delete(h.rooms, expected.RoomID)
				}
			}
		}
	}
	h.lobbyMu.Unlock()
	if active != nil {
		active.mu.Unlock()
	}
	h.mu.Unlock()
	if removed {
		h.publishLobby(expected.RoomID, accountID)
	}
}

func (h *mahjongHub) reconnectingWaitingPlayers(current matchmaking.MahjongAssignment) []string {
	reconnecting := []string{}
	if !waitingMahjongAssignment(current) {
		return reconnecting
	}
	h.lobbyMu.Lock()
	defer h.lobbyMu.Unlock()
	for _, accountID := range current.PlayerAccountIDs {
		if disconnected := h.waitingDisconnects[accountID]; disconnected != nil &&
			sameWaitingMahjongRoom(current, disconnected.assignment) {
			reconnecting = append(reconnecting, accountID)
		}
	}
	return reconnecting
}
