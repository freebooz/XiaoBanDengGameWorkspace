// Package mahjongrooms stores owner, roster and rules for friend room recovery.
package mahjongrooms

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrConflict = errors.New("麻将好友房代次、版本或内容不匹配")

const MaxPayloadBytes = 128 << 10

type Snapshot struct {
	RoomID    string
	CreatedAt time.Time
	Revision  int64
	Payload   json.RawMessage
}

type Service struct{ db *pgxpool.Pool }

func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

func (s *Service) Save(ctx context.Context, snapshot Snapshot) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error { return s.SaveTx(ctx, tx, snapshot) })
}

// SaveTx creates revision one or compares and advances the existing revision.
// Repeating the identical generation, revision and JSONB state is safe.
func (s *Service) SaveTx(ctx context.Context, tx pgx.Tx, snapshot Snapshot) error {
	payload := bytes.TrimSpace(snapshot.Payload)
	if !validIdentity(snapshot.RoomID, snapshot.CreatedAt, snapshot.Revision) || len(snapshot.Payload) > MaxPayloadBytes || len(payload) == 0 || payload[0] != '{' || !json.Valid(payload) {
		return errors.New("无效的麻将好友房快照")
	}
	if err := lockRoom(ctx, tx, snapshot.RoomID); err != nil {
		return err
	}
	generation := snapshot.CreatedAt.UnixNano()
	var result pgconn.CommandTag
	var err error
	if snapshot.Revision == 1 {
		result, err = tx.Exec(ctx, `INSERT INTO mahjong_friend_rooms (room_id,generation,revision,payload)
			VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING`, snapshot.RoomID, generation, snapshot.Revision, snapshot.Payload)
	} else {
		result, err = tx.Exec(ctx, `UPDATE mahjong_friend_rooms SET revision=$3,payload=$4
			WHERE room_id=$1 AND generation=$2 AND revision=$3-1`, snapshot.RoomID, generation, snapshot.Revision, snapshot.Payload)
	}
	if err != nil || result.RowsAffected() == 1 {
		return err
	}
	var same bool
	err = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM mahjong_friend_rooms
		WHERE room_id=$1 AND generation=$2 AND revision=$3 AND payload=$4)`, snapshot.RoomID, generation, snapshot.Revision, snapshot.Payload).Scan(&same)
	if err != nil || same {
		return err
	}
	return ErrConflict
}

func (s *Service) List(ctx context.Context) ([]Snapshot, error) {
	rows, err := s.db.Query(ctx, `SELECT room_id,generation,revision,payload FROM mahjong_friend_rooms ORDER BY room_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	snapshots := []Snapshot{}
	for rows.Next() {
		snapshot, err := scanSnapshot(rows)
		if err != nil {
			return nil, err
		}
		snapshots = append(snapshots, snapshot)
	}
	return snapshots, rows.Err()
}

func (s *Service) Load(ctx context.Context, roomID string) (Snapshot, error) {
	return scanSnapshot(s.db.QueryRow(ctx, `SELECT room_id,generation,revision,payload FROM mahjong_friend_rooms WHERE room_id=$1`, roomID))
}

func scanSnapshot(row pgx.Row) (Snapshot, error) {
	var snapshot Snapshot
	var generation int64
	if err := row.Scan(&snapshot.RoomID, &generation, &snapshot.Revision, &snapshot.Payload); err != nil {
		return Snapshot{}, err
	}
	snapshot.CreatedAt = time.Unix(0, generation).UTC()
	return snapshot, nil
}

func (s *Service) Delete(ctx context.Context, roomID string, createdAt time.Time, expectedRevision int64) error {
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error { return s.DeleteTx(ctx, tx, roomID, createdAt, expectedRevision) })
}

// DeleteTx removes only the supplied room incarnation and revision. An absent
// room indicates that there is nothing to delete, even when replaying a commit.
func (s *Service) DeleteTx(ctx context.Context, tx pgx.Tx, roomID string, createdAt time.Time, expectedRevision int64) error {
	if !validIdentity(roomID, createdAt, expectedRevision) {
		return errors.New("无效的麻将好友房标识")
	}
	if err := lockRoom(ctx, tx, roomID); err != nil {
		return err
	}
	tag, err := tx.Exec(ctx, `DELETE FROM mahjong_friend_rooms WHERE room_id=$1 AND generation=$2 AND revision=$3`, roomID, createdAt.UnixNano(), expectedRevision)
	if err != nil || tag.RowsAffected() == 1 {
		return err
	}
	var exists bool
	err = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM mahjong_friend_rooms WHERE room_id=$1)`, roomID).Scan(&exists)
	if err != nil || !exists {
		return err
	}
	return ErrConflict
}

func validIdentity(roomID string, createdAt time.Time, revision int64) bool {
	generation := createdAt.UnixNano()
	return roomID != "" && revision > 0 && generation > 0 && createdAt.Equal(time.Unix(0, generation))
}

func lockRoom(ctx context.Context, tx pgx.Tx, roomID string) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('xbd_mahjong_friend_room:' || $1, 0))`, roomID)
	return err
}
