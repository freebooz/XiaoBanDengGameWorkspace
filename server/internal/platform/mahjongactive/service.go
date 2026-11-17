// Package mahjongactive stores private authoritative state for server recovery.
package mahjongactive

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

var ErrConflict = errors.New("麻将牌局不存在、房间已占用或版本不匹配")

// MaxPayloadBytes bounds a recovery snapshot before PostgreSQL decodes it.
const MaxPayloadBytes = 1 << 20

type Snapshot struct {
	MatchID     string
	RoomID      string
	Revision    int64
	Payload     json.RawMessage
	CommittedAt time.Time
}

type Service struct{ db *pgxpool.Pool }

func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

// Insert persists the first deal with revision 1 and never replaces a match.
func (s *Service) Insert(ctx context.Context, snapshot Snapshot) error {
	_, err := s.InsertCommitted(ctx, snapshot)
	return err
}

// InsertCommitted returns the database clock stamp stored for the first revision.
func (s *Service) InsertCommitted(ctx context.Context, snapshot Snapshot) (time.Time, error) {
	if !validSnapshot(snapshot) || snapshot.Revision != 1 {
		return time.Time{}, errors.New("无效的麻将首发快照")
	}
	var committedAt time.Time
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if err := lockMatch(ctx, tx, snapshot.MatchID); err != nil {
			return err
		}
		return tx.QueryRow(ctx, `INSERT INTO mahjong_active_matches (match_id,room_id,revision,payload,committed_at)
			SELECT $1,$2,$3::BIGINT,$4::JSONB,clock_timestamp() WHERE NOT EXISTS (SELECT 1 FROM mahjong_active_completions WHERE match_id=$1)
			ON CONFLICT DO NOTHING RETURNING committed_at`, snapshot.MatchID, snapshot.RoomID, snapshot.Revision, snapshot.Payload).Scan(&committedAt)
	})
	return committedTimestamp(committedAt, err)
}

// Update installs the next revision only when the same match and room still
// hold the immediately preceding revision.
func (s *Service) Update(ctx context.Context, snapshot Snapshot) error {
	_, err := s.UpdateCommitted(ctx, snapshot)
	return err
}

// UpdateCommitted advances the revision and returns its database clock stamp.
func (s *Service) UpdateCommitted(ctx context.Context, snapshot Snapshot) (time.Time, error) {
	if !validSnapshot(snapshot) || snapshot.Revision < 2 {
		return time.Time{}, errors.New("无效的麻将更新快照")
	}
	var committedAt time.Time
	err := s.db.QueryRow(ctx, `UPDATE mahjong_active_matches SET revision=$3,payload=$4,committed_at=clock_timestamp()
		WHERE match_id=$1 AND room_id=$2 AND revision=$5 RETURNING committed_at`, snapshot.MatchID, snapshot.RoomID, snapshot.Revision, snapshot.Payload, snapshot.Revision-1).Scan(&committedAt)
	return committedTimestamp(committedAt, err)
}

func committedTimestamp(stamp time.Time, err error) (time.Time, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, ErrConflict
	}
	if err != nil {
		return time.Time{}, err
	}
	return stamp.UTC(), nil
}

// Matches verifies whether an insert/update took effect after the connection
// failed before reporting its result. PostgreSQL compares the parsed JSON.
func (s *Service) Matches(ctx context.Context, snapshot Snapshot) (bool, error) {
	_, err := s.CommittedAt(ctx, snapshot)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// CommittedAt reads the stored stamp only for the exact revision and JSONB
// payload. Legacy snapshots return zero time, while a mismatch returns ErrNoRows.
func (s *Service) CommittedAt(ctx context.Context, snapshot Snapshot) (time.Time, error) {
	if !validSnapshot(snapshot) {
		return time.Time{}, errors.New("无效的麻将确认快照")
	}
	var stamp *time.Time
	err := s.db.QueryRow(ctx, `SELECT committed_at FROM mahjong_active_matches
		WHERE match_id=$1 AND room_id=$2 AND revision=$3 AND payload=$4`, snapshot.MatchID, snapshot.RoomID, snapshot.Revision, snapshot.Payload).Scan(&stamp)
	if err != nil || stamp == nil {
		return time.Time{}, err
	}
	return stamp.UTC(), nil
}

func validSnapshot(snapshot Snapshot) bool {
	if snapshot.MatchID == "" || snapshot.RoomID == "" || snapshot.Revision < 1 || len(snapshot.Payload) > MaxPayloadBytes {
		return false
	}
	payload := bytes.TrimSpace(snapshot.Payload)
	return len(payload) > 0 && payload[0] == '{' && json.Valid(payload)
}

func (s *Service) List(ctx context.Context) ([]Snapshot, error) {
	rows, err := s.db.Query(ctx, `SELECT match_id,room_id,revision,payload,committed_at FROM mahjong_active_matches ORDER BY room_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	snapshots := []Snapshot{}
	for rows.Next() {
		var snapshot Snapshot
		var stamp *time.Time
		if err := rows.Scan(&snapshot.MatchID, &snapshot.RoomID, &snapshot.Revision, &snapshot.Payload, &stamp); err != nil {
			return nil, err
		}
		if stamp != nil {
			snapshot.CommittedAt = stamp.UTC()
		}
		snapshots = append(snapshots, snapshot)
	}
	return snapshots, rows.Err()
}

func (s *Service) Delete(ctx context.Context, matchID string, expectedRevision int64) error {
	return deleteSnapshot(ctx, s.db, matchID, expectedRevision)
}

// Complete removes a matching private snapshot and commits the caller's public
// history in the same transaction. Success can be replayed only with the same
// fingerprint, without invoking saveHistory again. A failed write leaves recovery intact.
func (s *Service) Complete(ctx context.Context, matchID string, expectedRevision int64, fingerprint [32]byte, saveHistory func(context.Context, pgx.Tx) error) error {
	if saveHistory == nil {
		return errors.New("缺少麻将结算记录写入")
	}
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if err := lockMatch(ctx, tx, matchID); err != nil {
			return err
		}
		if err := deleteSnapshot(ctx, tx, matchID, expectedRevision); err != nil {
			if !errors.Is(err, ErrConflict) {
				return err
			}
			var completed bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM mahjong_active_completions
				WHERE match_id=$1 AND revision=$2 AND fingerprint=$3)`, matchID, expectedRevision, fingerprint[:]).Scan(&completed); err != nil {
				return err
			}
			if completed {
				return nil
			}
			return ErrConflict
		}
		if err := saveHistory(ctx, tx); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO mahjong_active_completions (match_id,revision,fingerprint) VALUES ($1,$2,$3)`, matchID, expectedRevision, fingerprint[:])
		return err
	})
}

// A concurrent first-deal retry must observe the completion receipt even if
// it began waiting on the original active row before the completion committed.
func lockMatch(ctx context.Context, tx pgx.Tx, matchID string) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('xbd_mahjong_active:' || $1, 0))`, matchID)
	return err
}

type executor interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}

func deleteSnapshot(ctx context.Context, query executor, matchID string, revision int64) error {
	if matchID == "" || revision < 1 {
		return errors.New("无效的麻将快照标识")
	}
	return changed(query.Exec(ctx, `DELETE FROM mahjong_active_matches WHERE match_id=$1 AND revision=$2`, matchID, revision))
}

func changed(result pgconn.CommandTag, err error) error {
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return ErrConflict
	}
	return nil
}
