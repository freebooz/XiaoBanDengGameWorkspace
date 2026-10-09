package admin

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

type fakeRepository struct {
	userPage    Page[UserSummary]
	matchPage   Page[MatchSummary]
	matchDetail MatchDetail
	userCount   int64
	matchCount  int64
	detailErr   error
	lastUserQ   UserQuery
	lastMatchQ  MatchQuery
	lastRecordQ MatchRecordQuery
}

func (f *fakeRepository) CountUsers(context.Context) (int64, error)   { return f.userCount, nil }
func (f *fakeRepository) CountMatches(context.Context) (int64, error) { return f.matchCount, nil }
func (f *fakeRepository) ListUsers(_ context.Context, q UserQuery) (Page[UserSummary], error) {
	f.lastUserQ = q
	return f.userPage, nil
}
func (f *fakeRepository) ListMatches(_ context.Context, q MatchQuery) (Page[MatchSummary], error) {
	f.lastMatchQ = q
	return f.matchPage, nil
}
func (f *fakeRepository) MatchDetail(_ context.Context, _ string, q MatchRecordQuery) (MatchDetail, error) {
	f.lastRecordQ = q
	if f.detailErr != nil {
		return MatchDetail{}, f.detailErr
	}
	return f.matchDetail, nil
}

func TestAdminMatchDetailNormalizesIndependentPagesAndEmptyArrays(t *testing.T) {
	repo := &fakeRepository{matchDetail: MatchDetail{EventTotal: 42, SnapshotTotal: 43}}
	service := newServiceWithRepository(repo, room.NewManager())
	detail, err := service.MatchDetail(context.Background(), "id", MatchRecordQuery{EventPage: 3, SnapshotPage: 2, RecordPageSize: 500})
	if err != nil {
		t.Fatal(err)
	}
	if repo.lastRecordQ.EventPage != 3 || repo.lastRecordQ.SnapshotPage != 2 || repo.lastRecordQ.RecordPageSize != 100 {
		t.Fatalf("记录页未传给仓储: %+v", repo.lastRecordQ)
	}
	if detail.Events == nil || detail.Snapshots == nil || detail.Players == nil || detail.RecordPageSize != 100 || detail.EventTotal != 42 {
		t.Fatalf("记录分页响应错误: %+v", detail)
	}
	if _, err := service.MatchDetail(context.Background(), "id", MatchRecordQuery{EventPage: -1}); !errors.Is(err, ErrInvalidQuery) {
		t.Fatalf("负页应拒绝: %v", err)
	}
	if _, err := service.MatchDetail(context.Background(), "id", MatchRecordQuery{EventPage: int(^uint(0) >> 1), RecordPageSize: 100}); !errors.Is(err, ErrInvalidQuery) {
		t.Fatalf("偏移溢出应拒绝: %v", err)
	}
}

func TestAdminRoomReadModelShowsClientConnections(t *testing.T) {
	directory := room.NewManager()
	item, err := directory.Create(room.CreateRequest{ProductID: "p", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0"})
	if err != nil {
		t.Fatal(err)
	}
	directory.UpdateRuntime(item.RoomID, "playing", "match", []room.Player{{ClientID: "browser", Seat: "red", Connected: true}, {ClientID: "departed", Seat: "black", Connected: false}})
	result, err := newServiceWithRepository(&fakeRepository{}, directory).RoomDetail(item.RoomID)
	if err != nil || result.MatchID != "match" || result.ConnectedCount != 1 || len(result.Players) != 2 || !result.Players[0].Connected {
		t.Fatalf("目录读模型连接事实错误: %+v err=%v", result, err)
	}
}

func TestDevelopmentSourcesRemainExplicitInAdminDetails(t *testing.T) {
	directory := room.NewManager()
	item := directory.EnsureDevelopment("development-room")
	repo := &fakeRepository{matchDetail: MatchDetail{Summary: MatchSummary{Source: "development"}, DataSource: DataSourcePartial}}
	service := newServiceWithRepository(repo, directory)
	roomDetail, err := service.RoomDetail(item.RoomID)
	if err != nil || roomDetail.DataSource != "development" {
		t.Fatalf("开发房间来源必须可见: %+v err=%v", roomDetail, err)
	}
	matchDetail, err := service.MatchDetail(context.Background(), "match", MatchRecordQuery{})
	if err != nil || matchDetail.DataSource != "development" {
		t.Fatalf("开发对局来源必须可见: %+v err=%v", matchDetail, err)
	}
}

// 空winner表示当前尚无胜方，JSON仍必须包含已接入的字段。
func TestMatchSummaryJSONIncludesEmptyResultFields(t *testing.T) {
	payload, err := json.Marshal(MatchSummary{})
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(payload, &fields); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"room_id", "winner", "result_reason"} {
		if value, ok := fields[key]; !ok || value != "" {
			t.Errorf("%s应明确返回空字符串，实际=%v 存在=%v", key, value, ok)
		}
	}
}

func TestAdminOverviewUsesRealCountsAndMarksPartialSource(t *testing.T) {
	repo := &fakeRepository{userCount: 0, matchCount: 0}
	rooms := room.NewManager()
	service := newServiceWithRepository(repo, rooms)

	result, err := service.Overview(context.Background())
	if err != nil {
		t.Fatalf("Overview返回错误: %v", err)
	}
	if result.RegisteredUsers != 0 || result.ActiveRooms != 0 || result.TotalMatches != 0 {
		t.Fatalf("空数据不得伪造运营数字: %+v", result)
	}
	if result.DataSource != DataSourcePartial {
		t.Fatalf("一期概览应明确标记partial数据源，实际=%s", result.DataSource)
	}
	if result.ServiceTime.IsZero() {
		t.Fatal("概览必须返回服务端时间")
	}
}

func TestAdminOverviewExcludesExplicitDevelopmentRooms(t *testing.T) {
	directory := room.NewManager()
	if _, err := directory.Create(room.CreateRequest{ProductID: "xbd_chinese_chess", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0"}); err != nil {
		t.Fatal(err)
	}
	directory.EnsureDevelopment("development-only")
	repo := &fakeRepository{userCount: 7, matchCount: 4}
	result, err := newServiceWithRepository(repo, directory).Overview(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if result.ActiveRooms != 1 || result.RegisteredUsers != 7 || result.TotalMatches != 4 || result.DataSource != DataSourcePartial {
		t.Fatalf("运营统计应排除显式开发房间并保留真实用户/对局数量: %+v", result)
	}
}

func TestAdminListUsersNormalizesPagingAndKeepsStatusFilter(t *testing.T) {
	repo := &fakeRepository{userPage: Page[UserSummary]{Items: []UserSummary{}, Total: 0}}
	service := newServiceWithRepository(repo, room.NewManager())

	_, err := service.ListUsers(context.Background(), UserQuery{Page: 0, PageSize: 500, Status: "active"})
	if err != nil {
		t.Fatalf("ListUsers返回错误: %v", err)
	}
	if repo.lastUserQ.Page != 1 || repo.lastUserQ.PageSize != 100 || repo.lastUserQ.Status != "active" {
		t.Fatalf("分页/筛选规范化错误: %+v", repo.lastUserQ)
	}
}

func TestAdminRoomListFiltersAndGetReturnsNotFound(t *testing.T) {
	rooms := room.NewManager()
	created, err := rooms.Create(room.CreateRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	})
	if err != nil {
		t.Fatal(err)
	}
	service := newServiceWithRepository(&fakeRepository{}, rooms)

	items := service.ListRooms(RoomQuery{GameID: "chinese_chess"})
	if len(items) != 1 || items[0].RoomID != created.RoomID {
		t.Fatalf("房间筛选错误: %+v", items)
	}
	if _, err := service.RoomDetail("missing"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("不存在房间应返回ErrNotFound，实际=%v", err)
	}
}

func TestAdminMatchDetailPropagatesNotFound(t *testing.T) {
	repo := &fakeRepository{detailErr: ErrNotFound}
	service := newServiceWithRepository(repo, room.NewManager())

	_, err := service.MatchDetail(context.Background(), "missing", MatchRecordQuery{})
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("不存在对局应返回ErrNotFound，实际=%v", err)
	}
}

func TestMatchDurationSeconds(t *testing.T) {
	start := time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC)
	end := start.Add(95 * time.Second)
	item := MatchSummary{StartedAt: &start, FinishedAt: &end}
	if item.DurationSeconds() != 95 {
		t.Fatalf("对局时长应为95秒，实际=%d", item.DurationSeconds())
	}
}
