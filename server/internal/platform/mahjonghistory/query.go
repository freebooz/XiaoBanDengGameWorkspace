package mahjonghistory

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"slices"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var ErrInvalidCursor = errors.New("无效的麻将战绩分页标识")
var ErrReplayUnavailable = errors.New("该局没有可用的复盘记录")

type Page struct {
	Matches    []Summary `json:"matches"`
	NextCursor string    `json:"next_cursor,omitempty"`
}

const ownHistoryQuery = `SELECT r.public_match_id,r.room_id,r.kind,r.effective_rule,m.started_at,m.finished_at,
	r.scores,r.winners,r.win_from,r.win_kind,r.reason,p.seat,r.score_breakdown,
	(SELECT array_agg(l.delta ORDER BY member.seat) FROM mahjong_match_members member
	 JOIN wallet_ledger l ON l.account_id=member.account_id AND l.reference_id=r.public_match_id
	 AND l.reason='mahjong_settlement_eggs' AND l.asset_id='xbd_egg' AND l.scope='family' WHERE member.match_id=r.match_id)
	FROM mahjong_match_members p JOIN mahjong_match_results r USING (match_id) JOIN game_matches m USING (match_id)
	WHERE p.account_id=$1`

func scanSummary(row pgx.Row) (Summary, error) {
	var item Summary
	var deltas []int64
	err := row.Scan(&item.MatchID, &item.RoomID, &item.Kind, &item.Rule, &item.StartedAt, &item.FinishedAt,
		&item.Scores, &item.Winners, &item.WinFrom, &item.WinKind, &item.Reason, &item.YourSeat, &item.Breakdown, &deltas)
	if len(deltas) == 4 {
		item.EggDeltas = (*[4]int64)(deltas)
	}
	return item, err
}

// EggDeltas is an internal committed-settlement lookup. Older results and
// training have no egg postings and remain unknown, rather than inventing zero.
func (s *Service) EggDeltas(ctx context.Context, matchID string) (*[4]int64, error) {
	var deltas []int64
	err := s.db.QueryRow(ctx, `SELECT array_agg(l.delta ORDER BY member.seat)
		FROM mahjong_match_results r JOIN mahjong_match_members member USING(match_id)
		JOIN wallet_ledger l ON l.account_id=member.account_id AND l.reference_id=r.public_match_id
		AND l.reason='mahjong_settlement_eggs' AND l.asset_id='xbd_egg' AND l.scope='family'
		WHERE r.public_match_id=$1`, matchID).Scan(&deltas)
	if err != nil {
		return nil, err
	}
	if len(deltas) == 0 {
		return nil, nil
	}
	if len(deltas) != 4 {
		return nil, errors.New("鸡蛋结算账本不完整")
	}
	return (*[4]int64)(deltas), nil
}

func (s *Service) GetOwn(ctx context.Context, accountID, matchID string) (Summary, error) {
	if s.db == nil {
		return Summary{}, errors.New("麻将战绩数据库不可用")
	}
	id, ok := validHistorySubject(accountID, matchID)
	if !ok {
		return Summary{}, pgx.ErrNoRows
	}
	return scanSummary(s.db.QueryRow(ctx, ownHistoryQuery+` AND r.public_match_id=$2`, id, matchID))
}

func (s *Service) GetOwnReplay(ctx context.Context, accountID, matchID string) (guiyang.Replay, error) {
	if s.db == nil {
		return guiyang.Replay{}, errors.New("麻将战绩数据库不可用")
	}
	id, ok := validHistorySubject(accountID, matchID)
	if !ok {
		return guiyang.Replay{}, pgx.ErrNoRows
	}
	var replay *guiyang.Replay
	var reason string
	var winners []int
	err := s.db.QueryRow(ctx, `SELECT r.public_replay,r.reason,r.winners FROM mahjong_match_members p
		JOIN mahjong_match_results r USING (match_id) WHERE p.account_id=$1 AND r.public_match_id=$2`, id, matchID).Scan(&replay, &reason, &winners)
	if err != nil {
		return guiyang.Replay{}, err
	}
	if replay == nil {
		return guiyang.Replay{}, ErrReplayUnavailable
	}
	board, err := replay.Project(len(replay.Events))
	if err != nil || board.Reason == "" || board.Reason != reason || !slices.Equal(board.Winners, winners) {
		return guiyang.Replay{}, ErrReplayUnavailable
	}
	return *replay, nil
}

func validHistorySubject(accountID, matchID string) (uuid.UUID, bool) {
	id, err := uuid.Parse(accountID)
	return id, err == nil && id != uuid.Nil && matchID != "" && len(matchID) <= 128 && !strings.Contains(matchID, "/")
}

func (s *Service) ListOwn(ctx context.Context, accountID string, limit int) ([]Summary, error) {
	page, err := s.ListOwnPage(ctx, accountID, limit, "")
	return page.Matches, err
}

func (s *Service) ListOwnPage(ctx context.Context, accountID string, limit int, cursor string) (Page, error) {
	if s.db == nil {
		return Page{}, errors.New("麻将战绩数据库不可用")
	}
	id, err := uuid.Parse(accountID)
	if err != nil || id == uuid.Nil || limit < 1 || limit > 100 {
		return Page{}, errors.New("无效的麻将战绩查询")
	}
	query := ownHistoryQuery
	args := []any{id, limit + 1}
	if cursor != "" {
		finished, matchID, err := parseHistoryCursor(cursor)
		if err != nil {
			return Page{}, err
		}
		query += ` AND (m.finished_at,m.match_id)<($3,$4)`
		args = append(args, finished, matchID)
	}
	query += ` ORDER BY m.finished_at DESC,m.match_id DESC LIMIT $2`
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return Page{}, err
	}
	defer rows.Close()
	page := Page{Matches: make([]Summary, 0, limit)}
	for rows.Next() {
		item, err := scanSummary(rows)
		if err != nil {
			return Page{}, err
		}
		if len(page.Matches) == limit {
			last := page.Matches[limit-1]
			page.NextCursor = historyCursor(last.FinishedAt, historyMatchID(last.MatchID))
			break
		}
		page.Matches = append(page.Matches, item)
	}
	return page, rows.Err()
}

const historyCursorSize = 1 + 8 + 16 // version, finish time in Unix microseconds, stored match UUID

func historyCursor(finished time.Time, matchID uuid.UUID) string {
	var raw [historyCursorSize]byte
	raw[0] = 1
	binary.BigEndian.PutUint64(raw[1:9], uint64(finished.UnixMicro()))
	copy(raw[9:], matchID[:])
	return base64.RawURLEncoding.EncodeToString(raw[:])
}

func parseHistoryCursor(cursor string) (time.Time, uuid.UUID, error) {
	if len(cursor) != base64.RawURLEncoding.EncodedLen(historyCursorSize) {
		return time.Time{}, uuid.Nil, ErrInvalidCursor
	}
	raw, err := base64.RawURLEncoding.Strict().DecodeString(cursor)
	if err != nil || len(raw) != historyCursorSize || raw[0] != 1 {
		return time.Time{}, uuid.Nil, ErrInvalidCursor
	}
	finished := time.UnixMicro(int64(binary.BigEndian.Uint64(raw[1:9]))).UTC()
	matchID := uuid.UUID(raw[9:])
	if finished.Year() < 1 || finished.Year() > 9999 || matchID == uuid.Nil {
		return time.Time{}, uuid.Nil, ErrInvalidCursor
	}
	return finished, matchID, nil
}
