package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongmoderation"
)

type adminMahjongReviews interface {
	ListReviews(context.Context, string, int, int) ([]mahjongmoderation.Review, int, error)
	Resolve(context.Context, string, string, string, string) (mahjongmoderation.Review, error)
}

func (s *Server) adminMahjongReports(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r, adminMahjongReview); !ok || !requireGET(w, r) {
		return
	}
	limit, limitErr := queryInt(r, "limit", 20)
	offset, offsetErr := queryInt(r, "offset", 0)
	if limitErr != nil || offsetErr != nil || limit < 1 || limit > 100 || offset < 0 {
		writeError(w, http.StatusBadRequest, "无效的举报分页参数")
		return
	}
	if s.adminReviews == nil {
		writeError(w, http.StatusServiceUnavailable, "举报审核暂时不可用")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	items, total, err := s.adminReviews.ListReviews(ctx, r.URL.Query().Get("status"), limit, offset)
	if handleAdminReviewError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Items []mahjongmoderation.Review `json:"items"`
		Total int                        `json:"total"`
	}{items, total})
}

func (s *Server) resolveAdminMahjongReport(w http.ResponseWriter, r *http.Request) {
	principal, ok := s.requireAdmin(w, r, adminMahjongReview)
	if !ok {
		return
	}
	var req struct {
		Status string `json:"status"`
		Note   string `json:"note"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil || decoder.Decode(new(any)) != io.EOF {
		writeError(w, http.StatusBadRequest, "无效的举报审核请求")
		return
	}
	if s.adminReviews == nil {
		writeError(w, http.StatusServiceUnavailable, "举报审核暂时不可用")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	review, err := s.adminReviews.Resolve(ctx, r.PathValue("id"), principal.Name, req.Status, req.Note)
	if handleAdminReviewError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Report mahjongmoderation.Review `json:"report"`
	}{review})
}

func handleAdminReviewError(w http.ResponseWriter, err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, mahjongmoderation.ErrInvalidReview):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, mahjongmoderation.ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, mahjongmoderation.ErrConflict):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeError(w, http.StatusServiceUnavailable, "举报审核暂时不可用")
	}
	return true
}
