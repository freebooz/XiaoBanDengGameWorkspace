package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	adminplatform "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/admin"
)

type fakeAdminReader struct {
	overview    adminplatform.Overview
	userPage    adminplatform.Page[adminplatform.UserSummary]
	roomItem    adminplatform.RoomSummary
	roomErr     error
	recordQ     adminplatform.MatchRecordQuery
	matchDetail *adminplatform.MatchDetail
}

func (f *fakeAdminReader) Overview(context.Context) (adminplatform.Overview, error) {
	return f.overview, nil
}
func (f *fakeAdminReader) ListUsers(context.Context, adminplatform.UserQuery) (adminplatform.Page[adminplatform.UserSummary], error) {
	return f.userPage, nil
}
func (f *fakeAdminReader) ListRooms(adminplatform.RoomQuery) []adminplatform.RoomSummary {
	return []adminplatform.RoomSummary{}
}
func (f *fakeAdminReader) RoomDetail(string) (adminplatform.RoomSummary, error) {
	return f.roomItem, f.roomErr
}
func (f *fakeAdminReader) ListMatches(context.Context, adminplatform.MatchQuery) (adminplatform.Page[adminplatform.MatchSummary], error) {
	return adminplatform.Page[adminplatform.MatchSummary]{Items: []adminplatform.MatchSummary{}}, nil
}
func (f *fakeAdminReader) MatchDetail(_ context.Context, _ string, q adminplatform.MatchRecordQuery) (adminplatform.MatchDetail, error) {
	f.recordQ = q
	if f.matchDetail != nil {
		return *f.matchDetail, nil
	}
	return adminplatform.MatchDetail{}, adminplatform.ErrNotFound
}

func TestAdminMatchDetailPassesIndependentRecordPages(t *testing.T) {
	for _, test := range []struct {
		query string
		want  adminplatform.MatchRecordQuery
	}{
		{"", adminplatform.MatchRecordQuery{EventPage: 1, SnapshotPage: 1, RecordPageSize: 20}},
		{"?event_page=2&snapshot_page=4&record_page_size=500", adminplatform.MatchRecordQuery{EventPage: 2, SnapshotPage: 4, RecordPageSize: 100}},
	} {
		reader := &fakeAdminReader{matchDetail: &adminplatform.MatchDetail{EventTotal: 50, SnapshotTotal: 51}}
		s := &Server{admin: reader}
		res := httptest.NewRecorder()
		s.adminMatchDetail(res, httptest.NewRequest(http.MethodGet, "/api/v1/admin/matches/id"+test.query, nil), "id")
		if res.Code != http.StatusOK || reader.recordQ != test.want {
			t.Fatalf("分页参数传递错误: code=%d q=%+v want=%+v", res.Code, reader.recordQ, test.want)
		}
	}
}

func TestAdminOverviewHandlerReturnsJSON(t *testing.T) {
	serviceTime := time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC)
	s := &Server{admin: &fakeAdminReader{overview: adminplatform.Overview{
		RegisteredUsers: 3, ActiveRooms: 2, TotalMatches: 8,
		ServiceTime: serviceTime, DataSource: adminplatform.DataSourcePartial,
	}}}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/overview", nil)
	res := httptest.NewRecorder()
	s.adminOverview(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("预期200，实际=%d body=%s", res.Code, res.Body.String())
	}
	var payload adminplatform.Overview
	if err := json.NewDecoder(res.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if payload.RegisteredUsers != 3 || payload.DataSource != adminplatform.DataSourcePartial {
		t.Fatalf("响应内容错误: %+v", payload)
	}
}

func TestAdminUsersHandlerRejectsInvalidPage(t *testing.T) {
	s := &Server{admin: &fakeAdminReader{}}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/users?page=abc", nil)
	res := httptest.NewRecorder()
	s.adminUsers(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("非法page应返回400，实际=%d", res.Code)
	}
}

func TestAdminRoomDetailReturns404(t *testing.T) {
	s := &Server{admin: &fakeAdminReader{roomErr: adminplatform.ErrNotFound}}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/rooms/missing", nil)
	res := httptest.NewRecorder()
	s.adminRoomDetail(res, req, "missing")
	if res.Code != http.StatusNotFound {
		t.Fatalf("不存在房间应返回404，实际=%d", res.Code)
	}
}

// 对局记录页必须拒绝非法页，避免负偏移或无限查询。
func TestAdminMatchDetailRejectsInvalidRecordPage(t *testing.T) {
	for _, query := range []string{"event_page=0", "snapshot_page=-1", "record_page_size=0", "event_page=abc"} {
		s := &Server{admin: &fakeAdminReader{}}
		res := httptest.NewRecorder()
		s.adminMatchDetail(res, httptest.NewRequest(http.MethodGet, "/api/v1/admin/matches/m?"+query, nil), "m")
		if res.Code != http.StatusBadRequest {
			t.Errorf("%s应返回400，实际=%d", query, res.Code)
		}
	}
}
