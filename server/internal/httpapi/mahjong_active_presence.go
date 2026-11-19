package httpapi

import (
	"context"
	"errors"
	"log"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/jackc/pgx/v5"
)

const mahjongDisconnectMessage = "有玩家断线超过5分钟，本局已解散"

var errMahjongMatchCancelled = errors.New(mahjongDisconnectMessage)
var errMahjongMatchUnavailable = errors.New("此对局已失效，请返回大厅")

// Recent notices support a late authenticated board join without retaining
// a game, connection or timer. Older requests still get match_unavailable.
type mahjongCancelledMatch struct {
	room, match string
	players     [4]string
}

func (h *mahjongHub) wasCancelledLocked(roomID, matchID, accountID string) bool {
	for _, notice := range h.recentDisconnects {
		if notice.match == matchID && notice.room == roomID && slices.Contains(notice.players[:], accountID) {
			return true
		}
	}
	return false
}

func mahjongCancellationMessage(roomID, matchID string) map[string]any {
	return map[string]any{"type": "mahjong_match_cancelled", "room_id": roomID, "match_id": matchID,
		"reason": "disconnect_timeout", "message": mahjongDisconnectMessage}
}

func (h *mahjongHub) boundBoard(client *mahjongClient) *mahjongRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	return client.room
}

func (r *mahjongRoom) playing() bool {
	return r.started && !r.closed && r.game.Phase != guiyang.PhaseFinished
}

func (r *mahjongRoom) openingDealPending() bool {
	return !r.closed && !r.started && r.persistPending
}

func (r *mahjongRoom) firstDisconnectDeadline() int64 {
	var earliest int64
	for _, deadline := range r.disconnectDeadlines {
		if deadline > 0 && (earliest == 0 || deadline < earliest) {
			earliest = deadline
		}
	}
	return earliest
}

func (r *mahjongRoom) disconnectExpired(now time.Time) bool {
	deadline := r.firstDisconnectDeadline()
	return (r.playing() || r.openingDealPending()) && deadline > 0 && now.UnixMilli() >= deadline
}

func (r *mahjongRoom) savePresenceLocked(h *mahjongHub) error {
	if !r.durable(h) || (r.revision == 0 && !r.openingDealPending()) {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	err := h.checkpoints.SetDisconnectDeadlines(ctx, r.matchID, r.id, r.disconnectDeadlines)
	r.presenceDirty = err != nil
	if err != nil {
		log.Printf("Mahjong board presence pending for match %s: %v", r.matchID, err)
	}
	return err
}

func (r *mahjongRoom) reconnectSeatLocked(h *mahjongHub, seat int) error {
	previous := r.disconnectDeadlines[seat]
	r.disconnectDeadlines[seat] = 0
	err := r.savePresenceLocked(h)
	if err != nil {
		// A lost commit acknowledgement is ambiguous. Retry the last confirmed
		// presence until the player can establish a durable new binding.
		r.disconnectDeadlines[seat] = previous
	}
	r.scheduleDisconnectLocked(h, false)
	return err
}

func (r *mahjongRoom) disconnectSeatLocked(h *mahjongHub, seat int, previous int64) {
	if h.stopping.Load() || (!r.playing() && !r.openingDealPending()) || seat < 0 || seat >= 4 ||
		r.connectedSeatFlags()[seat] || r.disconnectDeadlines[seat] != 0 {
		return
	}
	if previous == 0 {
		previous = time.Now().Add(h.disconnectGrace).UnixMilli()
	}
	r.disconnectDeadlines[seat] = previous
	_ = r.savePresenceLocked(h)
	r.scheduleDisconnectLocked(h, false)
}

// A restored process has no sockets. Preserve recorded outages and give
// previously connected humans one bounded opportunity to attach again.
func (r *mahjongRoom) markAbsentSeats(h *mahjongHub, present [4]bool) bool {
	changed := false
	deadline := time.Now().Add(h.disconnectGrace).UnixMilli()
	for seat := range r.game.Players {
		if (r.kind != matchmaking.MahjongTraining || seat == 0) && !present[seat] && r.disconnectDeadlines[seat] == 0 {
			r.disconnectDeadlines[seat] = deadline
			changed = true
		}
	}
	return changed
}

// One room timer covers all human seats. A failed write retries the same
// deadlines without extending any disconnected player's grace.
func (r *mahjongRoom) scheduleDisconnectLocked(h *mahjongHub, retryExpired bool) {
	if r.disconnectTimer != nil {
		r.disconnectTimer.Stop()
		r.disconnectTimer = nil
	}
	if h.stopping.Load() || !r.playing() {
		return
	}
	deadline := r.firstDisconnectDeadline()
	if deadline == 0 && !r.presenceDirty {
		return
	}
	delay := time.Until(time.UnixMilli(deadline))
	if retryExpired || (r.presenceDirty && (deadline == 0 || delay > time.Second)) {
		delay = time.Second
	}
	var timer *time.Timer
	timer = time.AfterFunc(delay, func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		r.mu.Lock()
		defer r.mu.Unlock()
		h.checkDisconnectedLocked(r, timer)
	})
	r.disconnectTimer = timer
}

func (h *mahjongHub) checkDisconnectedLocked(r *mahjongRoom, timer *time.Timer) {
	if h.stopping.Load() || h.rooms[r.id] != r || !r.playing() || r.disconnectTimer != timer {
		return
	}
	if !r.disconnectExpired(time.Now()) {
		if r.presenceDirty {
			_ = r.savePresenceLocked(h)
		}
		r.scheduleDisconnectLocked(h, false)
		return
	}
	// A lost reply on an earlier game write must resolve first. In particular,
	// a settlement already committed before this deadline owns the result.
	if r.persistPending {
		r.scheduleDisconnectLocked(h, true)
		return
	}
	if err := h.abandonBoardLocked(r); err != nil {
		log.Printf("Mahjong disconnect expiry pending for match %s: %v", r.matchID, err)
		r.scheduleDisconnectLocked(h, true)
	}
}

func (h *mahjongHub) abandonBoardLocked(r *mahjongRoom) error {
	current, ok := h.matches.MahjongAssignment(r.game.Players[0])
	if h.rooms[r.id] != r || !ok || !current.Start || !r.belongsToRound(current) ||
		current.Kind != r.kind || current.PreviousMatchID != r.assignment.PreviousMatchID ||
		!slices.Equal(current.PlayerAccountIDs, r.game.Players[:]) {
		return mahjongactive.ErrConflict
	}
	var retireFriend func(context.Context, pgx.Tx) error
	var head *mahjongFriendHead
	if r.kind == matchmaking.MahjongFriend && h.friendStore != nil {
		head = h.friendHead(r.id)
		if head == nil || head.image.EntryMatchID != r.matchID || !r.belongsToRound(head.image.Assignment) {
			return mahjongactive.ErrConflict
		}
		retireFriend = func(ctx context.Context, tx pgx.Tx) error {
			return h.friendStore.DeleteTx(ctx, tx, r.id, head.row.CreatedAt, head.row.Revision)
		}
	}
	if r.durable(h) {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := h.checkpoints.Abandon(ctx, r.matchID, r.id, r.revision, retireFriend); err != nil {
			return err
		}
	} else if head != nil {
		if err := h.writeFriendImageLocked(r.id, nil); err != nil {
			return err
		}
	}
	if !h.matches.CancelActiveMahjongRound(current) {
		return mahjongactive.ErrConflict
	}
	if head != nil {
		h.friendHeads.CompareAndDelete(r.id, head)
	}
	if entry := h.entries[r.id]; entry != nil && r.belongsToRound(entry.assignment) {
		delete(h.entries, r.id)
		entry.timer.Stop()
	}
	r.closeLocked()
	h.spectators.cancelRound(r)
	delete(h.rooms, r.id)
	recipients := make(map[*mahjongClient]bool)
	for client := range r.clients {
		recipients[client] = true
		h.detachLocked(client, r)
	}
	h.lobbyMu.Lock()
	for client, subscription := range h.lobbyClients {
		if client.principal == subscription.accountID && slices.Contains(r.game.Players[:], client.principal) {
			recipients[client] = true
		}
	}
	h.lobbyMu.Unlock()
	if len(h.recentDisconnects) == 256 {
		h.recentDisconnects = slices.Delete(h.recentDisconnects, 0, 1)
	}
	h.recentDisconnects = append(h.recentDisconnects, mahjongCancelledMatch{r.id, r.matchID, r.game.Players})
	h.publishLobby(r.id, r.game.Players[:]...)
	message := mahjongCancellationMessage(r.id, r.matchID)
	for client := range recipients {
		go client.writeJSON(message)
	}
	return nil
}
