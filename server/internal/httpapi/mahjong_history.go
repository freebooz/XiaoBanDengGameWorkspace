package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/jackc/pgx/v5"
)

type mahjongHistoryReader interface {
	ListOwnPage(context.Context, string, int, string) (mahjonghistory.Page, error)
	GetOwn(context.Context, string, string) (mahjonghistory.Summary, error)
	GetOwnReplay(context.Context, string, string) (guiyang.Replay, error)
}

func (s *Server) listMahjongHistory(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	session, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	limit := 20
	query := r.URL.Query()
	if raw, supplied := query["limit"]; supplied {
		if len(raw) != 1 {
			writeError(w, http.StatusBadRequest, "limit 必须为 1 至 100 的整数")
			return
		}
		var err error
		limit, err = strconv.Atoi(raw[0])
		if err != nil || limit < 1 || limit > 100 {
			writeError(w, http.StatusBadRequest, "limit 必须为 1 至 100 的整数")
			return
		}
	}
	cursor := ""
	if raw, supplied := query["cursor"]; supplied {
		if len(raw) != 1 || raw[0] == "" {
			writeError(w, http.StatusBadRequest, "无效的麻将战绩分页标识")
			return
		}
		cursor = raw[0]
	}
	if s.mahjongHistory == nil {
		writeError(w, http.StatusServiceUnavailable, "麻将战绩暂时不可用，请稍后重试")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	page, err := s.mahjongHistory.ListOwnPage(ctx, session.AccountID, limit, cursor)
	if errors.Is(err, mahjonghistory.ErrInvalidCursor) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "麻将战绩暂时不可用，请稍后重试")
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (s *Server) mahjongHistoryDetail(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	session, ok := s.requireSession(w, r)
	if !ok {
		return
	}
	matchID := strings.TrimPrefix(r.URL.Path, "/api/v1/mahjong/history/")
	matchID, replayRequested := strings.CutSuffix(matchID, "/replay")
	if matchID == "" || strings.Contains(matchID, "/") || len(matchID) > 128 {
		writeError(w, http.StatusNotFound, "未找到该麻将战绩")
		return
	}
	if s.mahjongHistory == nil {
		writeError(w, http.StatusServiceUnavailable, "麻将战绩暂时不可用，请稍后重试")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if replayRequested {
		replay, err := s.mahjongHistory.GetOwnReplay(ctx, session.AccountID, matchID)
		if writeMahjongHistoryError(w, err) {
			return
		}
		writeJSON(w, http.StatusOK, struct {
			Replay guiyang.Replay `json:"replay"`
		}{Replay: replay})
		return
	}
	match, err := s.mahjongHistory.GetOwn(ctx, session.AccountID, matchID)
	if writeMahjongHistoryError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Match mahjonghistory.Summary `json:"match"`
	}{Match: match})
}

func writeMahjongHistoryError(w http.ResponseWriter, err error) bool {
	if errors.Is(err, mahjonghistory.ErrReplayUnavailable) {
		writeError(w, http.StatusNotFound, err.Error())
		return true
	}
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "未找到该麻将战绩")
		return true
	}
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "麻将战绩暂时不可用，请稍后重试")
		return true
	}
	return false
}
