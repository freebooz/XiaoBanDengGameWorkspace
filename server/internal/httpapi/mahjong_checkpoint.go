package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/jackc/pgx/v5"
)

type mahjongCheckpointStore interface {
	InsertCommitted(context.Context, mahjongactive.Snapshot) (time.Time, error)
	UpdateCommitted(context.Context, mahjongactive.Snapshot) (time.Time, error)
	CommittedAt(context.Context, mahjongactive.Snapshot) (time.Time, error)
	List(context.Context) ([]mahjongactive.Snapshot, error)
	Complete(context.Context, string, int64, [32]byte, func(context.Context, pgx.Tx) error) error
}

type mahjongCommand struct {
	ID       string
	Seat     int
	Action   string
	TileID   int
	Suit     string `json:",omitempty"`
	WindowID string `json:",omitempty"`
}

type mahjongCheckpoint struct {
	Version      int
	Assignment   matchmaking.MahjongAssignment
	Game         json.RawMessage
	StartedAt    time.Time
	LastActionAt time.Time
	Commands     []mahjongCommand
	// A subsequent write within the same decision carries forward its
	// opening stamp. The opening write uses its own committed_at instead.
	DecisionStart *time.Time `json:",omitempty"`
}

func (h *mahjongHub) restore(ctx context.Context) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	rows, err := h.checkpoints.List(ctx)
	if err != nil {
		return err
	}
	active := make(map[string]bool, len(rows))
	for _, row := range rows {
		active[row.RoomID] = true
	}
	if err := h.restoreFriendRooms(ctx, active); err != nil {
		return err
	}
	for _, row := range rows {
		var saved mahjongCheckpoint
		if err := json.Unmarshal(row.Payload, &saved); err != nil {
			return err
		}
		assignment := saved.Assignment
		assignment.Rule = guiyang.UpgradeStoredRuleDescriptor(assignment.Rule)
		if saved.Version != 1 || row.RoomID != assignment.RoomID || row.Revision < 1 ||
			saved.StartedAt.IsZero() || saved.LastActionAt.Before(saved.StartedAt) || h.rooms[row.RoomID] != nil {
			return fmt.Errorf("invalid active Mahjong checkpoint %s", row.MatchID)
		}
		game, err := guiyang.RestoreCheckpoint(saved.Game, assignment.Rule.RuleSet())
		if err != nil || game.Phase == guiyang.PhaseFinished || !slices.Equal(game.Players[:], assignment.PlayerAccountIDs) {
			return fmt.Errorf("invalid active Mahjong game %s", row.MatchID)
		}
		if err := h.matches.RestoreMahjongAssignment(assignment); err != nil {
			return fmt.Errorf("restore Mahjong match %s: %w", row.MatchID, err)
		}
		clockStart := saved.LastActionAt
		if !row.CommittedAt.IsZero() {
			clockStart = row.CommittedAt
		}
		decisionStart := clockStart
		if saved.DecisionStart != nil {
			if saved.DecisionStart.IsZero() {
				return fmt.Errorf("invalid Mahjong decision clock %s", row.MatchID)
			}
			decisionStart = *saved.DecisionStart
		} else if game.Phase == guiyang.PhaseDingque {
			decisionStart = saved.LastActionAt
		}
		if h.friendStore != nil && assignment.Kind == matchmaking.MahjongFriend {
			head := h.friendHead(row.RoomID)
			if head == nil {
				// Upgrade active friend hands created before room persistence.
				image := mahjongFriendImage{Assignment: assignment, EntryDeadline: saved.StartedAt.Add(h.entryTimeout), EntryMatchID: row.MatchID}
				head, err = newMahjongFriendHead(image, nil)
				if err != nil {
					return err
				}
				if err := h.friendStore.Save(ctx, head.row); err != nil {
					return err
				}
				h.friendHeads.Store(row.RoomID, head)
			} else if head.image.EntryMatchID != row.MatchID {
				return fmt.Errorf("active Mahjong match identity conflicts with friend room %s", row.RoomID)
			}
		}
		h.rooms[row.RoomID] = &mahjongRoom{
			monitor: h.monitor, spectators: &h.spectators,
			id: row.RoomID, matchID: row.MatchID, kind: assignment.Kind, rule: assignment.Rule,
			createdAt: assignment.Room.CreatedAt, completedRounds: assignment.CompletedRounds,
			game: game, clients: map[*mahjongClient]struct{}{}, started: true,
			startedAt: saved.StartedAt, lastActionAt: clockStart, revision: row.Revision,
			decisionID: mahjongDecisionID(row.MatchID, game), decisionStart: decisionStart,
			assignment: assignment, commands: saved.Commands,
		}
	}
	for _, r := range h.rooms {
		r.mu.Lock()
		r.scheduleTimeoutLocked(h)
		r.mu.Unlock()
	}
	h.friendHeads.Range(func(key, value any) bool {
		head := value.(*mahjongFriendHead)
		assignment := head.image.Assignment
		if assignment.Start && !active[assignment.RoomID] {
			h.scheduleEntryLocked(assignment, h.rooms[assignment.RoomID], head.image.EntryDeadline)
		}
		h.startAbsentFriendGrace(assignment)
		return true
	})
	return nil
}

func (r *mahjongRoom) durable(h *mahjongHub) bool {
	return h.checkpoints != nil && r.kind != matchmaking.MahjongTraining
}

func (r *mahjongRoom) persistLocked(h *mahjongHub, next *guiyang.Game, when time.Time, commands []mahjongCommand, decisionStart *time.Time) (time.Time, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if !r.durable(h) {
		if err := h.recordHistory(ctx, r.historyResult(next, when)); err != nil {
			return time.Time{}, err
		}
		if r.kind != matchmaking.MahjongTraining {
			_, err := r.loadSeatProfilesLocked(h, true)
			return when, err
		}
		return when, nil
	}
	game, err := next.MarshalCheckpoint()
	if err != nil {
		return time.Time{}, err
	}
	saved := mahjongCheckpoint{
		Version: 1, Assignment: r.assignment, Game: game, StartedAt: r.startedAt,
		LastActionAt: when, Commands: commands, DecisionStart: decisionStart,
	}
	payload, err := json.Marshal(saved)
	if err != nil {
		return time.Time{}, err
	}
	if next.Phase == guiyang.PhaseFinished {
		var friend *mahjongFriendHead
		var closedFriend *mahjongFriendHead
		if h.friendStore != nil && r.kind == matchmaking.MahjongFriend {
			assignment, ok := h.matches.ProjectMahjongFriendSettlement(r.id, r.createdAt, r.completedRounds, r.matchID, next.NextDealer(), next.Scores)
			prior := h.friendHead(r.id)
			if !ok || prior == nil {
				return time.Time{}, mahjongactive.ErrConflict
			}
			if assignment.Room.State == "closed" {
				closedFriend = prior
			} else {
				friend, err = newMahjongFriendHead(mahjongFriendImage{Assignment: assignment, Settlement: &saved}, prior)
				if err != nil {
					return time.Time{}, err
				}
			}
		}
		err := h.checkpoints.Complete(ctx, r.matchID, r.revision, sha256.Sum256(payload), func(ctx context.Context, tx pgx.Tx) error {
			if friend != nil {
				if err := h.friendStore.SaveTx(ctx, tx, friend.row); err != nil {
					return err
				}
			}
			if closedFriend != nil {
				if err := h.friendStore.DeleteTx(ctx, tx, r.id, closedFriend.row.CreatedAt, closedFriend.row.Revision); err != nil {
					return err
				}
			}
			return h.saveHistory(ctx, tx, r.historyResult(next, when))
		})
		if err == nil {
			// Never publish the old opening balance with a new terminal game.
			// Completed receipts skip all writes on a retry after a lost reply.
			_, err = r.loadSeatProfilesLocked(h, true)
		}
		if err == nil && friend != nil {
			h.friendHeads.Store(r.id, friend)
		}
		if err == nil && closedFriend != nil {
			h.friendHeads.Delete(r.id)
		}
		return when, err
	}
	snapshot := mahjongactive.Snapshot{MatchID: r.matchID, RoomID: r.id, Revision: r.revision + 1, Payload: payload}
	var committed time.Time
	if r.revision == 0 {
		committed, err = h.checkpoints.InsertCommitted(ctx, snapshot)
	} else {
		committed, err = h.checkpoints.UpdateCommitted(ctx, snapshot)
	}
	if err == nil {
		return committed, nil
	}
	readCtx, readCancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer readCancel()
	committed, readErr := h.checkpoints.CommittedAt(readCtx, snapshot)
	if readErr == nil {
		return committed, nil
	}
	if !errors.Is(readErr, pgx.ErrNoRows) {
		return time.Time{}, fmt.Errorf("could not verify Mahjong checkpoint: %v: %w", err, readErr)
	}
	return time.Time{}, err
}

func (r *mahjongRoom) commitLocked(h *mahjongHub, next *guiyang.Game, when time.Time, commands []mahjongCommand, command mahjongCommand, accepted func()) {
	if h.stopping.Load() {
		return
	}
	clockStart := when
	decisionID := mahjongDecisionID(r.matchID, next)
	var decisionStart *time.Time
	if decisionID != "" && decisionID == r.decisionID {
		decisionStart = &r.decisionStart
	} else if next.Phase == guiyang.PhaseDingque {
		// Keep the application-side clock used by legacy Dingque snapshots.
		decisionStart = &when
	}
	durable := r.durable(h)
	if durable || (r.started && next.Phase == guiyang.PhaseFinished && h.recordHistory != nil) {
		committed, err := r.persistLocked(h, next, when, commands, decisionStart)
		if err != nil {
			if errors.Is(err, mahjongactive.ErrConflict) || errors.Is(err, mahjongrooms.ErrConflict) {
				log.Printf("Mahjong checkpoint version conflict for match %s", r.matchID)
				r.closeLocked()
				for client := range r.clients {
					_ = client.wire.conn.Close()
				}
				return
			}
			if !r.persistPending {
				log.Printf("Mahjong write pending for match %s: %v", r.matchID, err)
				r.persistPending = true
				r.pendingCommand = command
				r.broadcastLocked()
			}
			if r.timer != nil {
				r.timer.Stop()
			}
			r.timer = time.AfterFunc(time.Second, func() {
				r.mu.Lock()
				defer r.mu.Unlock()
				if !r.closed {
					r.commitLocked(h, next, when, commands, command, accepted)
				}
			})
			return
		}
		if durable {
			r.revision++
		}
		if !committed.IsZero() {
			clockStart = committed
		}
	}
	r.persistPending = false
	r.pendingCommand = mahjongCommand{}
	r.game, r.lastActionAt, r.commands = next, clockStart, commands
	if decisionStart != nil {
		clockStart = *decisionStart
	}
	r.decisionID, r.decisionStart = decisionID, clockStart
	accepted()
	r.advanceLocked(h)
}

func (r *mahjongRoom) copyForAction(h *mahjongHub) (*guiyang.Game, error) {
	if !r.durable(h) && h.recordHistory == nil {
		return r.game, nil
	}
	data, err := r.game.MarshalCheckpoint()
	if err != nil {
		return nil, err
	}
	return guiyang.RestoreCheckpoint(data, r.rule.RuleSet())
}

func (r *mahjongRoom) historyResult(game *guiyang.Game, when time.Time) mahjonghistory.Result {
	return mahjonghistory.Result{
		MatchID: r.matchID, RoomID: r.id, Kind: r.kind, Rule: r.rule,
		StartedAt: r.startedAt, FinishedAt: when, Members: game.Players,
		Scores: game.Scores, Winners: append([]int{}, game.Winners...),
		Breakdown: game.SettlementScoreBreakdown(),
		Replay:    game.SettlementReplay(),
		WinFrom:   game.WinFrom, WinKind: game.WinKind, Reason: game.Reason,
	}
}
