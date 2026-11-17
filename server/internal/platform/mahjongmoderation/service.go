// Package mahjongmoderation stores the minimal account-linked table report audit.
package mahjongmoderation

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Report struct {
	MatchID           string    `json:"match_id"`
	RoomID            string    `json:"room_id"`
	ReporterAccountID string    `json:"reporter_account_id"`
	TargetAccountID   string    `json:"target_account_id"`
	ReporterSeat      int       `json:"reporter_seat"`
	TargetSeat        int       `json:"target_seat"`
	Reason            string    `json:"reason"`
	CreatedAt         time.Time `json:"created_at"`
}

func ValidReason(reason string) bool {
	switch reason {
	case "abusive_chat", "spam", "voice_abuse", "other":
		return true
	default:
		return false
	}
}

type Service struct{ db *pgxpool.Pool }

func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

// Save retains the first allowed reason. Retrying after an ambiguous commit
// does not create another report for the same people and match.
func (s *Service) Save(ctx context.Context, report Report) error {
	if s.db == nil {
		return errors.New("举报服务暂时不可用")
	}
	reporter, reporterErr := uuid.Parse(report.ReporterAccountID)
	target, targetErr := uuid.Parse(report.TargetAccountID)
	if reporterErr != nil || targetErr != nil || reporter == uuid.Nil || target == uuid.Nil || reporter == target ||
		report.ReporterSeat < 0 || report.ReporterSeat >= 4 || report.TargetSeat < 0 || report.TargetSeat >= 4 || report.ReporterSeat == report.TargetSeat ||
		report.MatchID == "" || len(report.MatchID) > 128 || report.RoomID == "" || len(report.RoomID) > 16 || !ValidReason(report.Reason) {
		return errors.New("无效的麻将举报")
	}
	_, err := s.db.Exec(ctx, `INSERT INTO mahjong_table_reports
		(match_id,room_id,reporter_account_id,target_account_id,reporter_seat,target_seat,reason)
		VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (match_id,reporter_account_id,target_account_id) DO NOTHING`,
		report.MatchID, report.RoomID, reporter, target, report.ReporterSeat, report.TargetSeat, report.Reason)
	return err
}

// List is for internal moderation use. Authorization belongs to its caller.
func (s *Service) List(ctx context.Context, limit int) ([]Report, error) {
	if s.db == nil || limit < 1 || limit > 100 {
		return nil, errors.New("无效的举报审计查询")
	}
	rows, err := s.db.Query(ctx, `SELECT match_id,room_id,reporter_account_id::text,target_account_id::text,reporter_seat,target_seat,reason,created_at
		FROM mahjong_table_reports ORDER BY created_at DESC,match_id,reporter_account_id,target_account_id LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	reports := []Report{}
	for rows.Next() {
		var report Report
		if err := rows.Scan(&report.MatchID, &report.RoomID, &report.ReporterAccountID, &report.TargetAccountID, &report.ReporterSeat, &report.TargetSeat, &report.Reason, &report.CreatedAt); err != nil {
			return nil, err
		}
		reports = append(reports, report)
	}
	return reports, rows.Err()
}
