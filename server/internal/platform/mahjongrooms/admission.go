package mahjongrooms

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type AdmissionChange struct {
	RequestID        uuid.UUID
	RoomID           string
	RoomGeneration   time.Time
	ExpectedRevision int64
	Paused           bool
	Reason           string
	AdminName        string
}

type AdmissionOperation struct {
	RequestID         uuid.UUID `json:"request_id"`
	RoomID            string    `json:"room_id"`
	RoomGeneration    time.Time `json:"room_generation"`
	AdmissionRevision int64     `json:"admission_revision"`
	Paused            bool      `json:"paused"`
	Reason            string    `json:"reason"`
	AdminName         string    `json:"admin_name"`
	CreatedAt         time.Time `json:"created_at"`
}

func (o AdmissionOperation) Matches(change AdmissionChange) bool {
	return o.RequestID == change.RequestID && o.RoomID == change.RoomID && o.RoomGeneration.Equal(change.RoomGeneration) &&
		o.AdmissionRevision-1 == change.ExpectedRevision && o.Paused == change.Paused && o.Reason == change.Reason && o.AdminName == change.AdminName
}

const admissionOperationColumns = "request_id,room_id,generation,admission_revision,paused,reason,admin_name,created_at"
const selectAdmissionOperation = "SELECT " + admissionOperationColumns + " FROM mahjong_room_admission_operations WHERE request_id=$1"

func (s *Service) FindAdmissionOperation(ctx context.Context, requestID uuid.UUID) (AdmissionOperation, error) {
	return scanAdmissionOperation(s.db.QueryRow(ctx, selectAdmissionOperation, requestID))
}

// CommitAdmission records a receipt and its matching friend snapshot in the
// same transaction. If a receipt already exists it can only be replayed with
// the original actor and payload.
func (s *Service) CommitAdmission(ctx context.Context, change AdmissionChange, snapshot Snapshot) (AdmissionOperation, error) {
	if change.RoomID != snapshot.RoomID || !change.RoomGeneration.Equal(snapshot.CreatedAt) || snapshot.Revision < 2 ||
		change.ExpectedRevision < 0 || change.ExpectedRevision == math.MaxInt64 {
		return AdmissionOperation{}, ErrConflict
	}
	var operation AdmissionOperation
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var err error
		operation, err = scanAdmissionOperation(tx.QueryRow(ctx, `
			INSERT INTO mahjong_room_admission_operations
				(request_id, room_id, generation, admission_revision, paused, reason, admin_name)
			VALUES ($1,$2,$3,$4,$5,$6,$7)
			ON CONFLICT DO NOTHING
			RETURNING `+admissionOperationColumns,
			change.RequestID, change.RoomID, change.RoomGeneration.UnixNano(), change.ExpectedRevision+1,
			change.Paused, change.Reason, change.AdminName))
		if errors.Is(err, pgx.ErrNoRows) {
			operation, err = scanAdmissionOperation(tx.QueryRow(ctx, selectAdmissionOperation, change.RequestID))
			if errors.Is(err, pgx.ErrNoRows) || (err == nil && !operation.Matches(change)) {
				return ErrConflict
			}
			return err
		}
		if err != nil {
			return err
		}
		return s.SaveTx(ctx, tx, snapshot)
	})
	if err != nil {
		return AdmissionOperation{}, err
	}
	return operation, nil
}

func (s *Service) ListAdmissionOperations(ctx context.Context, roomID string, generation time.Time) ([]AdmissionOperation, error) {
	rows, err := s.db.Query(ctx, "SELECT "+admissionOperationColumns+` FROM mahjong_room_admission_operations
		WHERE room_id=$1 AND generation=$2 ORDER BY admission_revision DESC LIMIT 20`, roomID, generation.UnixNano())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []AdmissionOperation{}
	for rows.Next() {
		operation, err := scanAdmissionOperation(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, operation)
	}
	return items, rows.Err()
}

func scanAdmissionOperation(row pgx.Row) (AdmissionOperation, error) {
	var operation AdmissionOperation
	var generation int64
	if err := row.Scan(&operation.RequestID, &operation.RoomID, &generation, &operation.AdmissionRevision,
		&operation.Paused, &operation.Reason, &operation.AdminName, &operation.CreatedAt); err != nil {
		return AdmissionOperation{}, err
	}
	operation.RoomGeneration = time.Unix(0, generation).UTC()
	operation.CreatedAt = operation.CreatedAt.UTC()
	return operation, nil
}
