package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"reflect"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type mahjongFriendStore interface {
	List(context.Context) ([]mahjongrooms.Snapshot, error)
	Load(context.Context, string) (mahjongrooms.Snapshot, error)
	Save(context.Context, mahjongrooms.Snapshot) error
	SaveTx(context.Context, pgx.Tx, mahjongrooms.Snapshot) error
	Delete(context.Context, string, time.Time, int64) error
	DeleteTx(context.Context, pgx.Tx, string, time.Time, int64) error
}

type mahjongFriendImage struct {
	Version       int
	Assignment    matchmaking.MahjongAssignment
	EntryDeadline time.Time
	EntryMatchID  string
	Settlement    *mahjongCheckpoint `json:",omitempty"`
}

type mahjongFriendHead struct {
	row   mahjongrooms.Snapshot
	image mahjongFriendImage
}

func (h *mahjongHub) friendHead(roomID string) *mahjongFriendHead {
	value, _ := h.friendHeads.Load(roomID)
	head, _ := value.(*mahjongFriendHead)
	return head
}

func newMahjongFriendHead(image mahjongFriendImage, prior *mahjongFriendHead) (*mahjongFriendHead, error) {
	image.Version = 1
	payload, err := json.Marshal(image)
	if err != nil {
		return nil, err
	}
	revision := int64(1)
	if prior != nil {
		revision = prior.row.Revision + 1
	}
	item := image.Assignment.Room
	return &mahjongFriendHead{mahjongrooms.Snapshot{RoomID: item.RoomID, CreatedAt: item.CreatedAt, Revision: revision, Payload: payload}, image}, nil
}

func (h *mahjongHub) friendAssignment(roomID string) *matchmaking.MahjongAssignment {
	if image, ok := h.matches.MahjongFriendRoomSnapshot(roomID); ok {
		return &image
	}
	return nil
}

// Keep ownership of the room number and every existing seat until the durable
// leave commits, including when the final player is leaving.
func (h *mahjongHub) leavePersistedFriendLocked(accountID string, expected matchmaking.MahjongAssignment) (bool, error) {
	if h.friendStore == nil || expected.Kind != matchmaking.MahjongFriend {
		return h.matches.LeaveMahjong(accountID, expected)
	}
	before := h.friendAssignment(expected.RoomID)
	if before == nil || !before.Room.CreatedAt.Equal(expected.Room.CreatedAt) || before.CompletedRounds != expected.CompletedRounds || !slices.Contains(before.PlayerAccountIDs, accountID) {
		return false, errors.New("玩家不属于该麻将房间")
	}
	if before.Start {
		return false, errors.New("对局已经开始，不能退出匹配房间")
	}
	after := *before
	after.PlayerAccountIDs = slices.DeleteFunc(slices.Clone(before.PlayerAccountIDs), func(player string) bool { return player == accountID })
	var desired *matchmaking.MahjongAssignment
	if len(after.PlayerAccountIDs) != 0 {
		after.Players = len(after.PlayerAccountIDs)
		after.ReadyPlayers = 0
		after.ReadyAccountIDs = []string{}
		after.Room.State = "waiting"
		after.Status = matchmaking.StatusWaiting
		desired = &after
	}
	if err := h.writeFriendImageLocked(expected.RoomID, desired); err != nil {
		return false, err
	}
	if err := h.matches.ReconcileMahjongFriendRoom(before, desired); err != nil {
		return false, err
	}
	return desired != nil, nil
}

// persistFriendMutationLocked is called with hub.mu held. A failed write
// restores the previous matchmaking state before another command can see it.
func (h *mahjongHub) persistFriendMutationLocked(roomID string, before *matchmaking.MahjongAssignment) error {
	if h.friendStore == nil {
		return nil
	}
	after := h.friendAssignment(roomID)
	if before == nil && after == nil {
		return nil
	}
	if before != nil && after != nil && before.Room == after.Room &&
		slices.Equal(before.PlayerAccountIDs, after.PlayerAccountIDs) && slices.Equal(before.ReadyAccountIDs, after.ReadyAccountIDs) {
		return nil
	}
	if err := h.writeFriendImageLocked(roomID, after); err != nil {
		if restoreErr := h.matches.ReconcileMahjongFriendRoom(after, before); restoreErr != nil {
			log.Printf("Mahjong friend room rollback failed for %s: %v", roomID, restoreErr)
		}
		return err
	}
	return nil
}

func (h *mahjongHub) writeFriendImageLocked(roomID string, after *matchmaking.MahjongAssignment) error {
	prior := h.friendHead(roomID)
	var next *mahjongFriendHead
	var err error
	if after != nil {
		image := mahjongFriendImage{Assignment: *after}
		if prior != nil {
			image.Settlement = prior.image.Settlement
		}
		if after.Start {
			image.EntryDeadline = time.Now().UTC().Add(h.entryTimeout)
			image.EntryMatchID = uuid.NewString()
		}
		next, err = newMahjongFriendHead(image, prior)
	}
	if err == nil {
		write := func(ctx context.Context) error {
			if next == nil {
				return h.friendStore.Delete(ctx, roomID, prior.row.CreatedAt, prior.row.Revision)
			}
			return h.friendStore.Save(ctx, next.row)
		}
		if next != nil || prior != nil {
			for tries := 0; tries < 2; tries++ {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				err = write(ctx)
				cancel()
				if err == nil || errors.Is(err, mahjongrooms.ErrConflict) {
					break
				}
			}
		}
	}
	if err != nil && !errors.Is(err, mahjongrooms.ErrConflict) {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		loaded, readErr := h.friendStore.Load(ctx, roomID)
		cancel()
		switch {
		case next == nil && errors.Is(readErr, pgx.ErrNoRows):
			err = nil
		case next != nil && readErr == nil && loaded.CreatedAt.Equal(next.row.CreatedAt) && loaded.Revision == next.row.Revision:
			if equalMahjongFriendPayload(loaded.Payload, next.row.Payload) {
				err = nil
			}
		}
	}
	if err == nil {
		if next == nil {
			h.friendHeads.Delete(roomID)
		} else {
			h.friendHeads.Store(roomID, next)
		}
		return nil
	}
	log.Printf("Mahjong friend room save for %s failed: %v", roomID, err)
	return errors.New("服务器暂时无法保存好友房，请稍后重试")
}

func equalMahjongFriendPayload(left, right json.RawMessage) bool {
	decode := func(data json.RawMessage) (map[string]any, error) {
		decoder := json.NewDecoder(bytes.NewReader(data))
		decoder.UseNumber()
		var result map[string]any
		err := decoder.Decode(&result)
		return result, err
	}
	a, leftErr := decode(left)
	b, rightErr := decode(right)
	return leftErr == nil && rightErr == nil && reflect.DeepEqual(a, b)
}

func (h *mahjongHub) restoreFriendRooms(ctx context.Context, active map[string]bool) error {
	if h.friendStore == nil {
		return nil
	}
	rows, err := h.friendStore.List(ctx)
	if err != nil {
		return err
	}
	for _, row := range rows {
		var image mahjongFriendImage
		if err := json.Unmarshal(row.Payload, &image); err != nil {
			return err
		}
		a := image.Assignment
		if image.Version != 1 || a.Kind != matchmaking.MahjongFriend || a.RoomID != row.RoomID ||
			!a.Room.CreatedAt.Equal(row.CreatedAt) || a.Start != (image.EntryMatchID != "" && !image.EntryDeadline.IsZero()) {
			return fmt.Errorf("invalid Mahjong friend room %s", row.RoomID)
		}
		if active[a.RoomID] && !a.Start {
			return fmt.Errorf("active Mahjong checkpoint conflicts with friend room %s", row.RoomID)
		}
		if err := h.matches.RestoreMahjongAssignment(a); err != nil {
			return err
		}
		h.friendHeads.Store(row.RoomID, &mahjongFriendHead{row, image})
		if image.Settlement != nil && !active[a.RoomID] {
			s := image.Settlement
			game, err := guiyang.RestoreCheckpoint(s.Game, a.Rule.RuleSet())
			if err != nil || game.Phase != guiyang.PhaseFinished || a.PreviousMatchID == "" ||
				!s.Assignment.Room.CreatedAt.Equal(row.CreatedAt) || !slices.Equal(game.Players[:], s.Assignment.PlayerAccountIDs) {
				return fmt.Errorf("invalid retained Mahjong settlement %s", row.RoomID)
			}
			h.rooms[row.RoomID] = &mahjongRoom{
				monitor: h.monitor,
				id:      row.RoomID, createdAt: row.CreatedAt, kind: a.Kind, rule: a.Rule,
				completedRounds: a.CompletedRounds - 1, matchID: a.PreviousMatchID, game: game,
				clients: map[*mahjongClient]struct{}{}, started: true, startedAt: s.StartedAt,
				lastActionAt: s.LastActionAt, closed: true, retained: true, commands: s.Commands,
				assignment: s.Assignment,
			}
		}
	}
	return nil
}
