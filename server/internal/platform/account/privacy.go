package account

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var ErrDeletionUnavailable = errors.New("此账号无法通过游客入口申请删除")

type DeletionReceipt struct {
	RequestID   string    `json:"request_id"`
	AccountID   string    `json:"account_id"`
	Status      string    `json:"status"`
	RequestedAt time.Time `json:"requested_at"`
}

// RevokeSession ends only the supplied active credential. It does not require
// callers to first perform a separate read that could race with revocation.
func (s *Service) RevokeSession(ctx context.Context, token string) error {
	hash, err := digestSessionToken(token)
	if err != nil {
		return err
	}
	if s.db == nil {
		return errors.New("账号数据库不可用")
	}
	tag, err := s.db.Exec(ctx, `DELETE FROM account_sessions s USING accounts a
		WHERE s.account_id=a.account_id AND s.token_hash=$1 AND s.expires_at>clock_timestamp() AND a.status='active'`, hash[:])
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInvalidSession
	}
	return nil
}

// RequestDeletion is called with an authenticated account identity. It
// disables the guest and queues retention review without erasing linked data.
func (s *Service) RequestDeletion(ctx context.Context, accountID string) (DeletionReceipt, error) {
	id, err := uuid.Parse(accountID)
	if err != nil || id == uuid.Nil {
		return DeletionReceipt{}, ErrDeletionUnavailable
	}
	if s.db == nil {
		return DeletionReceipt{}, errors.New("账号数据库不可用")
	}
	var receipt DeletionReceipt
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		var accountType, status string
		err := tx.QueryRow(ctx, `SELECT account_type,status FROM accounts WHERE account_id=$1 FOR UPDATE`, id).Scan(&accountType, &status)
		if errors.Is(err, pgx.ErrNoRows) || (err == nil && accountType != "guest") {
			return ErrDeletionUnavailable
		}
		if err != nil {
			return err
		}
		if status == "active" {
			if _, err := tx.Exec(ctx, `INSERT INTO guest_account_deletion_requests(account_id) VALUES ($1) ON CONFLICT (account_id) DO NOTHING`, id); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `UPDATE accounts SET display_name='已停用游客',status='deactivated' WHERE account_id=$1`, id); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `DELETE FROM account_sessions WHERE account_id=$1`, id); err != nil {
				return err
			}
		} else if status != "deactivated" {
			return ErrDeletionUnavailable
		}
		err = tx.QueryRow(ctx, `SELECT request_id::text,account_id::text,status,requested_at FROM guest_account_deletion_requests WHERE account_id=$1`, id).
			Scan(&receipt.RequestID, &receipt.AccountID, &receipt.Status, &receipt.RequestedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrDeletionUnavailable
		}
		return err
	})
	if err != nil {
		return DeletionReceipt{}, err
	}
	receipt.RequestedAt = receipt.RequestedAt.UTC()
	return receipt, nil
}
