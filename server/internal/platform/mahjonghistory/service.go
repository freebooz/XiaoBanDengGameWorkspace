package mahjonghistory

import (
	"context"
	"errors"
	"fmt"
	"math"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Result contains the immutable public settlement. Members are used only for
// authorization and are never serialized in history responses.
type Result struct {
	MatchID    string                  `json:"match_id"`
	RoomID     string                  `json:"room_id"`
	Kind       string                  `json:"kind"`
	Rule       guiyang.RuleDescriptor  `json:"rule"`
	StartedAt  time.Time               `json:"started_at"`
	FinishedAt time.Time               `json:"finished_at"`
	Scores     [4]int                  `json:"scores"`
	EggDeltas  *[4]int64               `json:"egg_deltas,omitempty"`
	Winners    []int                   `json:"winners"`
	WinFrom    int                     `json:"win_from"`
	WinKind    string                  `json:"win_kind"`
	Reason     string                  `json:"reason"`
	Breakdown  *guiyang.ScoreBreakdown `json:"score_breakdown,omitempty"`
	Replay     *guiyang.Replay         `json:"-"`
	Members    [4]string               `json:"-"`
}

type Summary struct {
	Result
	YourSeat int `json:"your_seat"`
}

type Service struct{ db *pgxpool.Pool }

func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

// Save atomically persists the result and every human seat. Repeating Save
// for the same public match leaves the first completed snapshot intact.
func (s *Service) Save(ctx context.Context, result Result) error {
	if s.db == nil {
		return errors.New("麻将战绩数据库不可用")
	}
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		return s.SaveTx(ctx, tx, result)
	})
}

// SaveTx stores a settlement in the caller's transaction.
func (s *Service) SaveTx(ctx context.Context, tx pgx.Tx, result Result) error {
	seatCount := 4
	switch result.Kind {
	case "friend", "quick":
	case "training":
		seatCount = 1
	default:
		return errors.New("无效的麻将战绩模式")
	}
	if result.MatchID == "" || result.RoomID == "" || result.Rule.ID == "" || result.Rule.Version == "" || result.Reason == "" || result.StartedAt.IsZero() || result.FinishedAt.Before(result.StartedAt) {
		return errors.New("无效的麻将结算摘要")
	}
	if !validBreakdown(result.Scores, result.Breakdown) {
		return errors.New("麻将计分明细与总分不一致")
	}
	if result.Replay != nil {
		board, err := result.Replay.Project(len(result.Replay.Events))
		if err != nil || board.Reason == "" || board.Reason != result.Reason || !slices.Equal(board.Winners, result.Winners) {
			return errors.New("麻将公开复盘与结算不一致")
		}
	}
	memberIDs := make([]uuid.UUID, seatCount)
	for seat, member := range result.Members[:seatCount] {
		id, err := uuid.Parse(member)
		if err != nil || id == uuid.Nil {
			return fmt.Errorf("麻将结算座位 %d 缺少有效账号", seat)
		}
		memberIDs[seat] = id
	}
	matchID := historyMatchID(result.MatchID)
	_, err := tx.Exec(ctx, `INSERT INTO game_matches
			(match_id,product_id,game_id,rule_set_id,rule_version,status,started_at,finished_at,created_at)
			VALUES ($1,$2,$3,$4,$5,'finished',$6,$7,$6) ON CONFLICT (match_id) DO NOTHING`,
		matchID, string(domain.ProductMahjong), string(domain.GameMahjong), result.Rule.ID, result.Rule.Version, result.StartedAt, result.FinishedAt)
	if err != nil {
		return err
	}
	inserted, err := tx.Exec(ctx, `INSERT INTO mahjong_match_results
			(match_id,public_match_id,room_id,kind,effective_rule,scores,winners,win_from,win_kind,reason,score_breakdown,public_replay)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT (match_id) DO NOTHING`,
		matchID, result.MatchID, result.RoomID, result.Kind, result.Rule, result.Scores[:], append([]int{}, result.Winners...), result.WinFrom, result.WinKind, result.Reason, result.Breakdown, result.Replay)
	if err != nil || inserted.RowsAffected() == 0 {
		return err
	}
	for seat, id := range memberIDs {
		if _, err := tx.Exec(ctx, `INSERT INTO mahjong_match_members(match_id,seat,account_id) VALUES ($1,$2,$3)`, matchID, seat, id); err != nil {
			return err
		}
	}
	if seatCount == 4 {
		return wallet.SettleMahjongEggsTx(ctx, tx, result.MatchID, result.Members, result.Scores)
	}
	return nil
}

func historyMatchID(publicID string) uuid.UUID {
	return uuid.NewSHA1(uuid.NameSpaceURL, []byte("urn:xbd:mahjong:match:"+publicID))
}

func validBreakdown(scores [4]int, breakdown *guiyang.ScoreBreakdown) bool {
	if breakdown == nil {
		return true // Older match records only have the total scores.
	}
	var hu, gang, ji int64
	for seat, score := range scores {
		a, b, c := int64(breakdown.Hu[seat]), int64(breakdown.Gang[seat]), int64(breakdown.Ji[seat])
		for _, value := range []int64{a, b, c} {
			if value < math.MinInt32 || value > math.MaxInt32 {
				return false
			}
		}
		if a+b+c != int64(score) {
			return false
		}
		hu, gang, ji = hu+a, gang+b, ji+c
	}
	return hu == 0 && gang == 0 && ji == 0
}
