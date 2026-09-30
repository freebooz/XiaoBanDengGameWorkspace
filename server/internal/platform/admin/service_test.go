package admin

import (
	"context"
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
func (f *fakeRepository) MatchDetail(context.Context, string) (MatchDetail, error) {
	if f.detailErr != nil {
		return MatchDetail{}, f.detailErr
	}
	return f.matchDetail, nil
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

	_, err := service.MatchDetail(context.Background(), "missing")
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
