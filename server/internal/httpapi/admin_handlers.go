package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	adminplatform "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/admin"
)

// adminReader（管理查询接口）让HTTP层只依赖只读能力，便于测试与后续权限装饰。
type adminReader interface {
	Overview(context.Context) (adminplatform.Overview, error)
	ListUsers(context.Context, adminplatform.UserQuery) (adminplatform.Page[adminplatform.UserSummary], error)
	ListRooms(adminplatform.RoomQuery) []adminplatform.RoomSummary
	RoomDetail(string) (adminplatform.RoomSummary, error)
	ListMatches(context.Context, adminplatform.MatchQuery) (adminplatform.Page[adminplatform.MatchSummary], error)
	MatchDetail(context.Context, string, adminplatform.MatchRecordQuery) (adminplatform.MatchDetail, error)
}

func (s *Server) adminOverview(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	result, err := s.admin.Overview(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) adminUsers(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	page, err := queryInt(r, "page", 1)
	if err != nil {
		writeError(w, http.StatusBadRequest, "page必须为整数")
		return
	}
	pageSize, err := queryInt(r, "page_size", 20)
	if err != nil {
		writeError(w, http.StatusBadRequest, "page_size必须为整数")
		return
	}
	result, err := s.admin.ListUsers(r.Context(), adminplatform.UserQuery{
		Page: page, PageSize: pageSize,
		Status: r.URL.Query().Get("status"), Keyword: r.URL.Query().Get("keyword"),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) adminRooms(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	result := s.admin.ListRooms(adminplatform.RoomQuery{
		ProductID: r.URL.Query().Get("product_id"),
		GameID:    r.URL.Query().Get("game_id"),
		RuleSetID: r.URL.Query().Get("rule_set_id"),
		State:     r.URL.Query().Get("state"),
	})
	writeJSON(w, http.StatusOK, map[string]any{"items": result, "total": len(result), "data_source": adminplatform.DataSourcePartial})
}

func (s *Server) adminRoomRoute(w http.ResponseWriter, r *http.Request) {
	roomID := strings.TrimPrefix(r.URL.Path, "/api/v1/admin/rooms/")
	if roomID == "" {
		writeError(w, http.StatusBadRequest, "缺少room_id")
		return
	}
	s.adminRoomDetail(w, r, roomID)
}

func (s *Server) adminRoomDetail(w http.ResponseWriter, r *http.Request, roomID string) {
	if !requireGET(w, r) {
		return
	}
	result, err := s.admin.RoomDetail(roomID)
	if errors.Is(err, adminplatform.ErrNotFound) {
		writeError(w, http.StatusNotFound, "房间不存在")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) adminMatches(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	page, err := queryInt(r, "page", 1)
	if err != nil {
		writeError(w, http.StatusBadRequest, "page必须为整数")
		return
	}
	pageSize, err := queryInt(r, "page_size", 20)
	if err != nil {
		writeError(w, http.StatusBadRequest, "page_size必须为整数")
		return
	}
	result, err := s.admin.ListMatches(r.Context(), adminplatform.MatchQuery{
		Page: page, PageSize: pageSize,
		GameID: r.URL.Query().Get("game_id"), Status: r.URL.Query().Get("status"),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) adminMatchRoute(w http.ResponseWriter, r *http.Request) {
	matchID := strings.TrimPrefix(r.URL.Path, "/api/v1/admin/matches/")
	if matchID == "" {
		writeError(w, http.StatusBadRequest, "缺少match_id")
		return
	}
	s.adminMatchDetail(w, r, matchID)
}

func (s *Server) adminMatchDetail(w http.ResponseWriter, r *http.Request, matchID string) {
	if !requireGET(w, r) {
		return
	}
	eventPage, err := queryInt(r, "event_page", 1)
	if err != nil || eventPage < 1 {
		writeError(w, http.StatusBadRequest, "event_page必须为正整数")
		return
	}
	snapshotPage, err := queryInt(r, "snapshot_page", 1)
	if err != nil || snapshotPage < 1 {
		writeError(w, http.StatusBadRequest, "snapshot_page必须为正整数")
		return
	}
	pageSize, err := queryInt(r, "record_page_size", 20)
	if err != nil || pageSize < 1 {
		writeError(w, http.StatusBadRequest, "record_page_size必须为正整数")
		return
	}
	if pageSize > 100 {
		pageSize = 100
	}
	result, err := s.admin.MatchDetail(r.Context(), matchID, adminplatform.MatchRecordQuery{EventPage: eventPage, SnapshotPage: snapshotPage, RecordPageSize: pageSize})
	if errors.Is(err, adminplatform.ErrInvalidQuery) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if errors.Is(err, adminplatform.ErrNotFound) {
		writeError(w, http.StatusNotFound, "对局不存在")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func requireGET(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "仅支持GET")
		return false
	}
	return true
}

func queryInt(r *http.Request, key string, defaultValue int) (int, error) {
	value := r.URL.Query().Get(key)
	if value == "" {
		return defaultValue, nil
	}
	return strconv.Atoi(value)
}
