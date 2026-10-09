// Package matchrecord 提供对局写入仓储，HTTP与游戏规则均不进入数据库层。
package matchrecord

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Player 保存历史座位，不把客户端标识当成认证账号。
type Player struct {
	ClientID string
	Seat     string
}

type Match struct {
	MatchID     string
	RoomID      string
	ProductID   string
	GameID      string
	RuleSetID   string
	RuleVersion string
	Source      string
	StartedAt   time.Time
	Players     []Player
	Snapshot    json.RawMessage
}

// Change 把事件、快照与结果放入同一个数据库事务。
type Change struct {
	MatchID      string
	Sequence     int64
	EventType    string
	Payload      json.RawMessage
	Snapshot     json.RawMessage
	Status       string
	Winner       string
	ResultReason string
	OccurredAt   time.Time
}

type Store interface {
	CreateMatch(context.Context, Match) error
	AppendChange(context.Context, Change) error
}

type beginner interface {
	Begin(context.Context) (pgx.Tx, error)
}

type PostgresStore struct{ db beginner }

func NewPostgresStore(db *pgxpool.Pool) *PostgresStore {
	if db == nil {
		return &PostgresStore{}
	}
	return &PostgresStore{db: db}
}

// CreateMatch 原子创建索引、两席玩家与 sequence=0 的标准开局快照。
func (s *PostgresStore) CreateMatch(ctx context.Context, match Match) error {
	if match.MatchID == "" || match.RoomID == "" || len(match.Players) != 2 || !json.Valid(match.Snapshot) {
		return errors.New("对局初始记录不完整")
	}
	if s.db == nil {
		return errors.New("对局数据库不可用")
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("开启对局事务: %w", err)
	}
	defer tx.Rollback(context.Background())
	if _, err := tx.Exec(ctx, "INSERT INTO game_matches(match_id,room_id,product_id,game_id,rule_set_id,rule_version,status,started_at,created_at,source,last_sequence) VALUES($1,$2,$3,$4,$5,$6,'playing',$7,$7,$8,0)", match.MatchID, match.RoomID, match.ProductID, match.GameID, match.RuleSetID, match.RuleVersion, match.StartedAt, match.Source); err != nil {
		return fmt.Errorf("创建对局索引: %w", err)
	}
	for _, player := range match.Players {
		if _, err := tx.Exec(ctx, "INSERT INTO game_match_players(match_id,client_id,seat,joined_at) VALUES($1,$2,$3,$4)", match.MatchID, player.ClientID, player.Seat, match.StartedAt); err != nil {
			return fmt.Errorf("创建对局玩家: %w", err)
		}
	}
	if _, err := tx.Exec(ctx, "INSERT INTO game_snapshots(match_id,sequence,snapshot,created_at) VALUES($1,0,$2,$3)", match.MatchID, []byte(match.Snapshot), match.StartedAt); err != nil {
		return fmt.Errorf("创建初始快照: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("提交对局事务: %w", err)
	}
	return nil
}

// AppendChange 用序号与playing状态校验串行提交；失败时事件与快照一起回滚。
func (s *PostgresStore) AppendChange(ctx context.Context, change Change) error {
	if change.Sequence < 1 || !json.Valid(change.Payload) || !json.Valid(change.Snapshot) {
		return errors.New("对局变更记录不完整")
	}
	if change.Status != "playing" && change.Status != "finished" && change.Status != "aborted" {
		return errors.New("对局状态非法")
	}
	if s.db == nil {
		return errors.New("对局数据库不可用")
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("开启走子事务: %w", err)
	}
	defer tx.Rollback(context.Background())
	var finishedAt *time.Time
	if change.Status != "playing" {
		finishedAt = &change.OccurredAt
	}
	tag, err := tx.Exec(ctx, "UPDATE game_matches SET last_sequence=$2,status=$3,winner=NULLIF($4,''),result_reason=NULLIF($5,''),finished_at=$6 WHERE match_id=$1 AND status='playing' AND last_sequence=$7", change.MatchID, change.Sequence, change.Status, change.Winner, change.ResultReason, finishedAt, change.Sequence-1)
	if err != nil {
		return fmt.Errorf("更新对局状态: %w", err)
	}
	if tag.RowsAffected() != 1 {
		return errors.New("对局状态或记录序号发生冲突")
	}
	if _, err := tx.Exec(ctx, "INSERT INTO game_events(match_id,sequence,event_type,payload,created_at) VALUES($1,$2,$3,$4,$5)", change.MatchID, change.Sequence, change.EventType, []byte(change.Payload), change.OccurredAt); err != nil {
		return fmt.Errorf("写入游戏事件: %w", err)
	}
	if _, err := tx.Exec(ctx, "INSERT INTO game_snapshots(match_id,sequence,snapshot,created_at) VALUES($1,$2,$3,$4)", change.MatchID, change.Sequence, []byte(change.Snapshot), change.OccurredAt); err != nil {
		return fmt.Errorf("写入游戏快照: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("提交走子事务: %w", err)
	}
	return nil
}
