package admin

import (
	"encoding/json"
	"errors"
	"time"
)

// ErrNotFound（管理查询未找到）用于HTTP层统一映射404。
var ErrNotFound = errors.New("管理查询目标不存在")

const (
	// DataSourcePartial（部分真实数据）表示字段来自真实服务/数据库，但一期尚未覆盖全部运营指标。
	DataSourcePartial = "partial"
)

// Page（分页结果）是管理后台列表接口的统一返回结构。
type Page[T any] struct {
	Items      []T    `json:"items"`
	Total      int64  `json:"total"`
	Page       int    `json:"page"`
	PageSize   int    `json:"page_size"`
	DataSource string `json:"data_source"`
}

// Overview（运营概览）只返回当前已能可靠计算的真实指标。
type Overview struct {
	RegisteredUsers int64     `json:"registered_users"`
	ActiveRooms     int       `json:"active_rooms"`
	TotalMatches    int64     `json:"total_matches"`
	ServiceTime     time.Time `json:"service_time"`
	DataSource      string    `json:"data_source"`
}

// UserQuery（用户查询）支持基础分页、状态和关键词筛选。
type UserQuery struct {
	Page     int
	PageSize int
	Status   string
	Keyword  string
}

// UserSummary（用户摘要）映射现有 accounts 表的真实字段。
type UserSummary struct {
	AccountID   string    `json:"account_id"`
	DisplayName string    `json:"display_name"`
	AccountType string    `json:"account_type"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

// RoomQuery（房间查询）用于进程内活动房间目录过滤。
type RoomQuery struct {
	ProductID string
	GameID    string
	RuleSetID string
	State     string
}

// RoomSummary（房间摘要）保持与通用房间模型解耦，方便后续扩展在线人数等运营字段。
type RoomSummary struct {
	RoomID          string    `json:"room_id"`
	ProductID       string    `json:"product_id"`
	GameID          string    `json:"game_id"`
	RuleSetID       string    `json:"rule_set_id"`
	RuleVersion     string    `json:"rule_version"`
	State           string    `json:"state"`
	CreatedAt       time.Time `json:"created_at"`
	DurationSeconds int64     `json:"duration_seconds"`
	DataSource      string    `json:"data_source"`
}

// MatchQuery（对局查询）支持游戏、状态和分页筛选。
type MatchQuery struct {
	Page     int
	PageSize int
	GameID   string
	Status   string
}

// MatchSummary（对局摘要）映射 game_matches 表。
type MatchSummary struct {
	MatchID     string     `json:"match_id"`
	ProductID   string     `json:"product_id"`
	GameID      string     `json:"game_id"`
	RuleSetID   string     `json:"rule_set_id"`
	RuleVersion string     `json:"rule_version"`
	Status      string     `json:"status"`
	StartedAt   *time.Time `json:"started_at"`
	FinishedAt  *time.Time `json:"finished_at"`
	CreatedAt   time.Time  `json:"created_at"`
}

// DurationSeconds（对局时长）仅在开始和结束时间都存在时返回确定时长。
func (m MatchSummary) DurationSeconds() int64 {
	if m.StartedAt == nil || m.FinishedAt == nil || m.FinishedAt.Before(*m.StartedAt) {
		return 0
	}
	return int64(m.FinishedAt.Sub(*m.StartedAt).Seconds())
}

// GameEvent（游戏事件）映射事件持久化表。
type GameEvent struct {
	Sequence  int64           `json:"sequence"`
	EventType string          `json:"event_type"`
	Payload   json.RawMessage `json:"payload"`
	CreatedAt time.Time       `json:"created_at"`
}

// GameSnapshot（游戏快照）映射快照持久化表。
type GameSnapshot struct {
	Sequence  int64           `json:"sequence"`
	Snapshot  json.RawMessage `json:"snapshot"`
	CreatedAt time.Time       `json:"created_at"`
}

// MatchDetail（对局详情）第一期包含摘要、事件和快照；玩家明细/回放文件后续按真实存储扩展。
type MatchDetail struct {
	Summary    MatchSummary   `json:"summary"`
	Events     []GameEvent    `json:"events"`
	Snapshots  []GameSnapshot `json:"snapshots"`
	DataSource string         `json:"data_source"`
}
