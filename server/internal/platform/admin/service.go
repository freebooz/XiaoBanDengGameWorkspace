package admin

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// repository（管理查询仓储）隔离数据库细节，使服务规则可在无数据库单元测试中验证。
type repository interface {
	CountUsers(context.Context) (int64, error)
	CountMatches(context.Context) (int64, error)
	ListUsers(context.Context, UserQuery) (Page[UserSummary], error)
	ListMatches(context.Context, MatchQuery) (Page[MatchSummary], error)
	MatchDetail(context.Context, string, MatchRecordQuery) (MatchDetail, error)
}

// Service（运营管理只读服务）只聚合查询，不提供高风险管理写操作。
type Service struct {
	repo  repository
	rooms *room.Manager
}

// NewService（创建运营管理服务）。
func NewService(db *pgxpool.Pool, rooms *room.Manager) *Service {
	return &Service{repo: &pgRepository{db: db}, rooms: rooms}
}

// newServiceWithRepository（测试构造器）让单元测试注入无副作用仓储。
func newServiceWithRepository(repo repository, rooms *room.Manager) *Service {
	return &Service{repo: repo, rooms: rooms}
}

// Overview（综合工作台概览）仅汇总现阶段真实可得的数据。
func (s *Service) Overview(ctx context.Context) (Overview, error) {
	users, err := s.repo.CountUsers(ctx)
	if err != nil {
		return Overview{}, fmt.Errorf("统计用户失败: %w", err)
	}
	matches, err := s.repo.CountMatches(ctx)
	if err != nil {
		return Overview{}, fmt.Errorf("统计对局失败: %w", err)
	}
	activeRooms := 0
	for _, item := range s.rooms.List() {
		if item.Source != "development" {
			activeRooms++
		}
	}
	return Overview{
		RegisteredUsers: users,
		ActiveRooms:     activeRooms,
		TotalMatches:    matches,
		ServiceTime:     time.Now().UTC(),
		DataSource:      DataSourcePartial,
	}, nil
}

// ListUsers（用户列表）统一规范化分页，最大每页100条。
func (s *Service) ListUsers(ctx context.Context, q UserQuery) (Page[UserSummary], error) {
	q.Page, q.PageSize = normalizePaging(q.Page, q.PageSize)
	result, err := s.repo.ListUsers(ctx, q)
	if err != nil {
		return Page[UserSummary]{}, err
	}
	if result.Items == nil {
		result.Items = []UserSummary{}
	}
	result.Page, result.PageSize = q.Page, q.PageSize
	if result.DataSource == "" {
		result.DataSource = DataSourcePartial
	}
	return result, nil
}

// ListRooms（实时房间）从当前 Game Node 进程内目录生成真实快照。
func (s *Service) ListRooms(q RoomQuery) []RoomSummary {
	source := s.rooms.List()
	result := make([]RoomSummary, 0, len(source))
	now := time.Now().UTC()
	for _, item := range source {
		if q.ProductID != "" && item.ProductID != q.ProductID {
			continue
		}
		if q.GameID != "" && item.GameID != q.GameID {
			continue
		}
		if q.RuleSetID != "" && item.RuleSetID != q.RuleSetID {
			continue
		}
		if q.State != "" && item.State != q.State {
			continue
		}
		result = append(result, roomSummary(item, now))
	}
	return result
}

// RoomDetail（房间详情）仅返回房间管理器已有真实字段。
func (s *Service) RoomDetail(roomID string) (RoomSummary, error) {
	item, ok := s.rooms.Get(roomID)
	if !ok {
		return RoomSummary{}, ErrNotFound
	}
	return roomSummary(item, time.Now().UTC()), nil
}

// ListMatches（对局列表）查询持久化对局索引。
func (s *Service) ListMatches(ctx context.Context, q MatchQuery) (Page[MatchSummary], error) {
	q.Page, q.PageSize = normalizePaging(q.Page, q.PageSize)
	result, err := s.repo.ListMatches(ctx, q)
	if err != nil {
		return Page[MatchSummary]{}, err
	}
	if result.Items == nil {
		result.Items = []MatchSummary{}
	}
	result.Page, result.PageSize = q.Page, q.PageSize
	if result.DataSource == "" {
		result.DataSource = DataSourcePartial
	}
	return result, nil
}

// MatchDetail（对局详情）返回摘要、历史座位及当前记录页。
func (s *Service) MatchDetail(ctx context.Context, matchID string, q MatchRecordQuery) (MatchDetail, error) {
	q, err := normalizeRecordPaging(q)
	if err != nil {
		return MatchDetail{}, err
	}
	result, err := s.repo.MatchDetail(ctx, matchID, q)
	if err != nil {
		return MatchDetail{}, err
	}
	if result.Events == nil {
		result.Events = []GameEvent{}
	}
	if result.Snapshots == nil {
		result.Snapshots = []GameSnapshot{}
	}
	if result.Players == nil {
		result.Players = []MatchPlayer{}
	}
	result.EventPage, result.SnapshotPage, result.RecordPageSize = q.EventPage, q.SnapshotPage, q.RecordPageSize
	if result.Summary.Source == "development" {
		result.DataSource = DataSourceDevelopment
	}
	if result.DataSource == "" {
		result.DataSource = DataSourcePartial
	}
	return result, nil
}

func normalizeRecordPaging(q MatchRecordQuery) (MatchRecordQuery, error) {
	if q.EventPage == 0 {
		q.EventPage = 1
	}
	if q.SnapshotPage == 0 {
		q.SnapshotPage = 1
	}
	if q.RecordPageSize == 0 {
		q.RecordPageSize = 20
	}
	if q.EventPage < 1 || q.SnapshotPage < 1 || q.RecordPageSize < 1 {
		return q, ErrInvalidQuery
	}
	if q.RecordPageSize > 100 {
		q.RecordPageSize = 100
	}
	// LIMIT/OFFSET 使用 int 参数，先排除乘法溢出。
	maxPage := int(^uint(0)>>1) / q.RecordPageSize
	if q.EventPage-1 > maxPage || q.SnapshotPage-1 > maxPage {
		return q, ErrInvalidQuery
	}
	return q, nil
}

func normalizePaging(page, pageSize int) (int, int) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	return page, pageSize
}

func roomSummary(item room.Room, now time.Time) RoomSummary {
	duration := now.Sub(item.CreatedAt)
	if duration < 0 {
		duration = 0
	}
	players := make([]RoomPlayer, 0, len(item.Players))
	for _, player := range item.Players {
		players = append(players, RoomPlayer{ClientID: player.ClientID, Seat: player.Seat, Connected: player.Connected})
	}
	source := DataSourcePartial
	if item.Source == "development" {
		source = DataSourceDevelopment
	}
	return RoomSummary{
		RoomID: item.RoomID, ProductID: item.ProductID, GameID: item.GameID,
		RuleSetID: item.RuleSetID, RuleVersion: item.RuleVersion, State: item.State,
		CreatedAt: item.CreatedAt, DurationSeconds: int64(duration.Seconds()),
		DataSource: source,
		Players:    players, ConnectedCount: item.ConnectedCount, MatchID: item.MatchID, Source: item.Source,
	}
}

// pgRepository（PostgreSQL管理查询仓储）仅执行参数化SELECT。
type pgRepository struct {
	db *pgxpool.Pool
}

func (r *pgRepository) CountUsers(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM accounts").Scan(&count)
	return count, err
}

func (r *pgRepository) CountMatches(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM game_matches WHERE COALESCE(source,'')<>'development'").Scan(&count)
	return count, err
}

func (r *pgRepository) ListUsers(ctx context.Context, q UserQuery) (Page[UserSummary], error) {
	where, args := []string{"1=1"}, []any{}
	if q.Status != "" {
		args = append(args, q.Status)
		where = append(where, fmt.Sprintf("status=$%d", len(args)))
	}
	if strings.TrimSpace(q.Keyword) != "" {
		args = append(args, "%"+strings.TrimSpace(q.Keyword)+"%")
		where = append(where, fmt.Sprintf("(account_id::text ILIKE $%d OR display_name ILIKE $%d)", len(args), len(args)))
	}
	clause := strings.Join(where, " AND ")
	var total int64
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM accounts WHERE "+clause, args...).Scan(&total); err != nil {
		return Page[UserSummary]{}, err
	}
	args = append(args, q.PageSize, (q.Page-1)*q.PageSize)
	rows, err := r.db.Query(ctx,
		fmt.Sprintf("SELECT account_id::text,display_name,account_type,status,created_at FROM accounts WHERE %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d", clause, len(args)-1, len(args)),
		args...,
	)
	if err != nil {
		return Page[UserSummary]{}, err
	}
	defer rows.Close()
	items := make([]UserSummary, 0)
	for rows.Next() {
		var item UserSummary
		if err := rows.Scan(&item.AccountID, &item.DisplayName, &item.AccountType, &item.Status, &item.CreatedAt); err != nil {
			return Page[UserSummary]{}, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return Page[UserSummary]{}, err
	}
	return Page[UserSummary]{Items: items, Total: total}, nil
}

func (r *pgRepository) ListMatches(ctx context.Context, q MatchQuery) (Page[MatchSummary], error) {
	where, args := []string{"1=1"}, []any{}
	if q.GameID != "" {
		args = append(args, q.GameID)
		where = append(where, fmt.Sprintf("game_id=$%d", len(args)))
	}
	if q.Status != "" {
		args = append(args, q.Status)
		where = append(where, fmt.Sprintf("status=$%d", len(args)))
	}
	clause := strings.Join(where, " AND ")
	var total int64
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM game_matches WHERE "+clause, args...).Scan(&total); err != nil {
		return Page[MatchSummary]{}, err
	}
	args = append(args, q.PageSize, (q.Page-1)*q.PageSize)
	rows, err := r.db.Query(ctx,
		fmt.Sprintf("SELECT match_id::text,product_id,game_id,rule_set_id,rule_version,status,started_at,finished_at,created_at,COALESCE(room_id,''),COALESCE(winner,''),COALESCE(result_reason,''),COALESCE(source,'') FROM game_matches WHERE %s ORDER BY created_at DESC,match_id DESC LIMIT $%d OFFSET $%d", clause, len(args)-1, len(args)),
		args...,
	)
	if err != nil {
		return Page[MatchSummary]{}, err
	}
	defer rows.Close()
	items := make([]MatchSummary, 0)
	for rows.Next() {
		var item MatchSummary
		if err := rows.Scan(&item.MatchID, &item.ProductID, &item.GameID, &item.RuleSetID, &item.RuleVersion, &item.Status, &item.StartedAt, &item.FinishedAt, &item.CreatedAt, &item.RoomID, &item.Winner, &item.ResultReason, &item.Source); err != nil {
			return Page[MatchSummary]{}, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return Page[MatchSummary]{}, err
	}
	return Page[MatchSummary]{Items: items, Total: total}, nil
}

func (r *pgRepository) MatchDetail(ctx context.Context, matchID string, q MatchRecordQuery) (MatchDetail, error) {
	var summary MatchSummary
	err := r.db.QueryRow(ctx,
		"SELECT match_id::text,product_id,game_id,rule_set_id,rule_version,status,started_at,finished_at,created_at,COALESCE(room_id,''),COALESCE(winner,''),COALESCE(result_reason,''),COALESCE(source,'') FROM game_matches WHERE match_id::text=$1",
		matchID,
	).Scan(&summary.MatchID, &summary.ProductID, &summary.GameID, &summary.RuleSetID, &summary.RuleVersion, &summary.Status, &summary.StartedAt, &summary.FinishedAt, &summary.CreatedAt, &summary.RoomID, &summary.Winner, &summary.ResultReason, &summary.Source)
	if errors.Is(err, pgx.ErrNoRows) {
		return MatchDetail{}, ErrNotFound
	}
	if err != nil {
		return MatchDetail{}, err
	}

	var eventTotal, snapshotTotal int64
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM game_events WHERE match_id::text=$1", matchID).Scan(&eventTotal); err != nil {
		return MatchDetail{}, err
	}
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM game_snapshots WHERE match_id::text=$1", matchID).Scan(&snapshotTotal); err != nil {
		return MatchDetail{}, err
	}
	players := make([]MatchPlayer, 0)
	playerRows, err := r.db.Query(ctx, "SELECT client_id,seat,joined_at FROM game_match_players WHERE match_id::text=$1 ORDER BY seat", matchID)
	if err != nil {
		return MatchDetail{}, err
	}
	for playerRows.Next() {
		var player MatchPlayer
		if err := playerRows.Scan(&player.ClientID, &player.Seat, &player.JoinedAt); err != nil {
			playerRows.Close()
			return MatchDetail{}, err
		}
		players = append(players, player)
	}
	if err := playerRows.Err(); err != nil {
		playerRows.Close()
		return MatchDetail{}, err
	}
	playerRows.Close()
	events := make([]GameEvent, 0)
	eventRows, err := r.db.Query(ctx, "SELECT sequence,event_type,payload,created_at FROM game_events WHERE match_id::text=$1 ORDER BY sequence LIMIT $2 OFFSET $3", matchID, q.RecordPageSize, (q.EventPage-1)*q.RecordPageSize)
	if err != nil {
		return MatchDetail{}, err
	}
	for eventRows.Next() {
		var item GameEvent
		var payload []byte
		if err := eventRows.Scan(&item.Sequence, &item.EventType, &payload, &item.CreatedAt); err != nil {
			eventRows.Close()
			return MatchDetail{}, err
		}
		item.Payload = json.RawMessage(payload)
		events = append(events, item)
	}
	if err := eventRows.Err(); err != nil {
		eventRows.Close()
		return MatchDetail{}, err
	}
	eventRows.Close()

	snapshots := make([]GameSnapshot, 0)
	snapshotRows, err := r.db.Query(ctx, "SELECT sequence,snapshot,created_at FROM game_snapshots WHERE match_id::text=$1 ORDER BY sequence LIMIT $2 OFFSET $3", matchID, q.RecordPageSize, (q.SnapshotPage-1)*q.RecordPageSize)
	if err != nil {
		return MatchDetail{}, err
	}
	for snapshotRows.Next() {
		var item GameSnapshot
		var payload []byte
		if err := snapshotRows.Scan(&item.Sequence, &payload, &item.CreatedAt); err != nil {
			snapshotRows.Close()
			return MatchDetail{}, err
		}
		item.Snapshot = json.RawMessage(payload)
		snapshots = append(snapshots, item)
	}
	if err := snapshotRows.Err(); err != nil {
		snapshotRows.Close()
		return MatchDetail{}, err
	}
	snapshotRows.Close()

	return MatchDetail{Summary: summary, Events: events, Snapshots: snapshots, Players: players, EventTotal: eventTotal, SnapshotTotal: snapshotTotal, EventPage: q.EventPage, SnapshotPage: q.SnapshotPage, RecordPageSize: q.RecordPageSize, DataSource: DataSourcePartial}, nil
}
