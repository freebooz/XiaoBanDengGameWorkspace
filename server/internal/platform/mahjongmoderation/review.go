package mahjongmoderation

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const (
	StatusPending   = "pending"
	StatusDismissed = "dismissed"
	StatusUpheld    = "upheld"
)

var (
	ErrInvalidReview = errors.New("无效的举报审核参数")
	ErrNotFound      = errors.New("未找到该举报")
	ErrConflict      = errors.New("该举报已有不同的审核结果")
)

type Review struct {
	Report
	ID         string     `json:"report_id"`
	Status     string     `json:"status"`
	Analyst    string     `json:"analyst,omitempty"`
	ReviewedAt *time.Time `json:"reviewed_at,omitempty"`
	Note       string     `json:"note,omitempty"`
}

const reviewColumns = `r.match_id,r.room_id,r.reporter_account_id::text,r.target_account_id::text,r.reporter_seat,r.target_seat,r.reason,r.created_at,
	r.report_id::text,COALESCE(d.status_after,'pending'),COALESCE(d.analyst,''),d.reviewed_at,COALESCE(d.note_after,'')`

const reviewRelation = ` FROM mahjong_table_reports r LEFT JOIN mahjong_table_report_reviews d USING (report_id)`

func scanReview(row pgx.Row) (Review, error) {
	var item Review
	err := row.Scan(&item.MatchID, &item.RoomID, &item.ReporterAccountID, &item.TargetAccountID, &item.ReporterSeat, &item.TargetSeat, &item.Reason, &item.CreatedAt,
		&item.ID, &item.Status, &item.Analyst, &item.ReviewedAt, &item.Note)
	return item, err
}

func (s *Service) ListReviews(ctx context.Context, status string, limit, offset int) ([]Review, int, error) {
	if limit < 1 || limit > 100 || offset < 0 || (status != "" && status != StatusPending && status != StatusDismissed && status != StatusUpheld) {
		return nil, 0, ErrInvalidReview
	}
	if s.db == nil {
		return nil, 0, errors.New("举报服务暂时不可用")
	}
	items := []Review{}
	var total int
	const filter = ` WHERE ($1='' OR COALESCE(d.status_after,'pending')=$1)`
	err := pgx.BeginTxFunc(ctx, s.db, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT count(*)`+reviewRelation+filter, status).Scan(&total); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT `+reviewColumns+reviewRelation+filter+` ORDER BY r.created_at DESC,r.report_id DESC LIMIT $2 OFFSET $3`, status, limit, offset)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			item, err := scanReview(rows)
			if err != nil {
				return err
			}
			items = append(items, item)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// Resolve saves one terminal disposition and its before/after audit in the
// same row. A retry must match the analyst, status and normalized note.
func (s *Service) Resolve(ctx context.Context, id, actor, status, note string) (Review, error) {
	reportID, err := uuid.Parse(id)
	if err != nil || reportID == uuid.Nil || !validAnalyst(actor) || (status != StatusDismissed && status != StatusUpheld) || !validReviewNote(note) {
		return Review{}, ErrInvalidReview
	}
	if s.db == nil {
		return Review{}, errors.New("举报服务暂时不可用")
	}
	note = strings.TrimSpace(note)
	var current Review
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		// Lock the base report first. A later statement then sees the winning
		// disposition if this request had to wait for a competing reviewer.
		var present int
		err := tx.QueryRow(ctx, `SELECT 1 FROM mahjong_table_reports WHERE report_id=$1 FOR UPDATE`, reportID).Scan(&present)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		current, err = scanReview(tx.QueryRow(ctx, `SELECT `+reviewColumns+reviewRelation+` WHERE r.report_id=$1`, reportID))
		if err != nil {
			return err
		}
		if current.Status != StatusPending {
			if current.Analyst == actor && current.Status == status && current.Note == note {
				return nil
			}
			return ErrConflict
		}
		var reviewedAt time.Time
		if err := tx.QueryRow(ctx, `INSERT INTO mahjong_table_report_reviews (report_id,status_before,status_after,analyst,note_before,note_after)
			VALUES ($1,$2,$3,$4,$5,$6) RETURNING reviewed_at`, reportID, current.Status, status, actor, current.Note, note).Scan(&reviewedAt); err != nil {
			return err
		}
		current.Status, current.Analyst, current.Note, current.ReviewedAt = status, actor, note, &reviewedAt
		return nil
	})
	if err != nil {
		return Review{}, err
	}
	return current, nil
}

func validAnalyst(actor string) bool {
	if len(actor) == 0 || len(actor) > 128 {
		return false
	}
	for _, char := range actor {
		if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || strings.ContainsRune("._-@", char)) {
			return false
		}
	}
	return true
}

func validReviewNote(note string) bool {
	if !utf8.ValidString(note) || utf8.RuneCountInString(note) > 240 {
		return false
	}
	for _, char := range note {
		if !(unicode.IsLetter(char) || unicode.IsMark(char) || unicode.IsNumber(char) || strings.ContainsRune(" .,!?:;()-。，！？：；、（）—", char)) {
			return false
		}
	}
	return true
}
