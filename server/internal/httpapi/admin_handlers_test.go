package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	adminplatform "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/admin"
)

type fakeAdminReader struct {
	overview adminplatform.Overview
	userPage adminplatform.Page[adminplatform.UserSummary]
	roomItem adminplatform.RoomSummary
	roomErr  error
	queryErr error
}

func (f *fakeAdminReader) Overview(context.Context) (adminplatform.Overview, error) {
	return f.overview, f.queryErr
}
func (f *fakeAdminReader) ListUsers(context.Context, adminplatform.UserQuery) (adminplatform.Page[adminplatform.UserSummary], error) {
	return f.userPage, f.queryErr
}
func (f *fakeAdminReader) ListRooms(adminplatform.RoomQuery) []adminplatform.RoomSummary {
	return []adminplatform.RoomSummary{}
}
func (f *fakeAdminReader) RoomDetail(string) (adminplatform.RoomSummary, error) {
	return f.roomItem, f.roomErr
}
func (f *fakeAdminReader) ListMatches(context.Context, adminplatform.MatchQuery) (adminplatform.Page[adminplatform.MatchSummary], error) {
	return adminplatform.Page[adminplatform.MatchSummary]{Items: []adminplatform.MatchSummary{}}, f.queryErr
}
func (f *fakeAdminReader) MatchDetail(context.Context, string) (adminplatform.MatchDetail, error) {
	if f.queryErr != nil {
		return adminplatform.MatchDetail{}, f.queryErr
	}
	return adminplatform.MatchDetail{}, adminplatform.ErrNotFound
}

func TestAdminReadErrorsHideInternalDetails(t *testing.T) {
	const internalDetail = "private-database-error-detail"
	queryErr := errors.New(internalDetail)
	s := &Server{admin: &fakeAdminReader{queryErr: queryErr, roomErr: queryErr}}
	for path, handler := range map[string]http.HandlerFunc{
		"/api/v1/admin/overview":      s.adminOverview,
		"/api/v1/admin/users":         s.adminUsers,
		"/api/v1/admin/rooms/1234":    s.adminRoomRoute,
		"/api/v1/admin/matches":       s.adminMatches,
		"/api/v1/admin/matches/match": s.adminMatchRoute,
	} {
		t.Run(path, func(t *testing.T) {
			res := httptest.NewRecorder()
			handler(res, httptest.NewRequest(http.MethodGet, path, nil))
			if res.Code != http.StatusInternalServerError || strings.Contains(res.Body.String(), internalDetail) {
				t.Fatal("admin query failure exposed internal details or returned the wrong status")
			}
		})
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
