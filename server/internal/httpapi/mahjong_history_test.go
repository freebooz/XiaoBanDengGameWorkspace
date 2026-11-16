package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/jackc/pgx/v5"
)

type historyProbe struct {
	accountID string
	limit     int
	cursor    string
	matchID   string
	replay    guiyang.Replay
	replayErr error
}

func (p *historyProbe) ListOwnPage(_ context.Context, accountID string, limit int, cursor string) (mahjonghistory.Page, error) {
	p.accountID, p.limit, p.cursor = accountID, limit, cursor
	return mahjonghistory.Page{Matches: []mahjonghistory.Summary{}, NextCursor: "next"}, nil
}

func (p *historyProbe) GetOwn(_ context.Context, accountID, matchID string) (mahjonghistory.Summary, error) {
	p.accountID, p.matchID = accountID, matchID
	return mahjonghistory.Summary{}, pgx.ErrNoRows
}

func (p *historyProbe) GetOwnReplay(_ context.Context, accountID, matchID string) (guiyang.Replay, error) {
	p.accountID, p.matchID = accountID, matchID
	return p.replay, p.replayErr
}

func TestMahjongHistoryReplayUsesSessionOwner(t *testing.T) {
	accounts := &fixtureAccounts{}
	probe := &historyProbe{replay: guiyang.Replay{Version: 1, Dealer: 2, Events: []guiyang.ReplayEvent{{Sequence: 1, Seat: -1, Kind: "wall_exhausted"}}}}
	s := &Server{accounts: accounts, mahjongHistory: probe}
	for _, tc := range []struct {
		name    string
		failure error
		status  int
		message string
	}{
		{name: "member", status: http.StatusOK},
		{name: "owned legacy", failure: mahjonghistory.ErrReplayUnavailable, status: http.StatusNotFound, message: "该局没有可用的复盘记录"},
		{name: "outsider", failure: pgx.ErrNoRows, status: http.StatusNotFound, message: "未找到该麻将战绩"},
		{name: "database failure", failure: errors.New("unavailable"), status: http.StatusServiceUnavailable, message: "麻将战绩暂时不可用，请稍后重试"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			probe.replayErr = tc.failure
			req := httptest.NewRequest(http.MethodGet, "/api/v1/mahjong/history/public-match/replay?account_id=someone-else", nil)
			req.Header = accounts.header(t, "signed-in-owner")
			response := httptest.NewRecorder()
			s.mahjongHistoryDetail(response, req)
			if response.Code != tc.status || probe.accountID != "signed-in-owner" || probe.matchID != "public-match" || response.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("unexpected response: %d", response.Code)
			}
			var body struct {
				Replay guiyang.Replay
				Error  string
			}
			if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || body.Error != tc.message || (tc.status == http.StatusOK && (body.Replay.Dealer != 2 || len(body.Replay.Events) != 1)) {
				t.Fatalf("unexpected response body: %s", response.Body.String())
			}
		})
	}
}

func TestMahjongHistoryUsesSessionOwner(t *testing.T) {
	accounts := &fixtureAccounts{}
	probe := &historyProbe{}
	s := &Server{accounts: accounts, mahjongHistory: probe}
	response := httptest.NewRecorder()
	s.listMahjongHistory(response, httptest.NewRequest(http.MethodGet, "/api/v1/mahjong/history?limit=7", nil))
	if response.Code != http.StatusUnauthorized || probe.accountID != "" {
		t.Fatalf("anonymous request reached history: %d", response.Code)
	}
	request := httptest.NewRequest(http.MethodGet, "/api/v1/mahjong/history?limit=7&account_id=someone-else&cursor=opaque", nil)
	request.Header = accounts.header(t, "signed-in-owner")
	response = httptest.NewRecorder()
	s.listMahjongHistory(response, request)
	if response.Code != http.StatusOK || probe.accountID != "signed-in-owner" || probe.limit != 7 || probe.cursor != "opaque" || response.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("history did not use the authenticated owner: status=%d account=%q limit=%d", response.Code, probe.accountID, probe.limit)
	}
	var payload mahjonghistory.Page
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil || payload.Matches == nil || len(payload.Matches) != 0 || payload.NextCursor != "next" {
		t.Fatalf("empty results must serialize as an array: %s", response.Body.String())
	}
	request = httptest.NewRequest(http.MethodGet, "/api/v1/mahjong/history/other-match?account_id=someone-else", nil)
	request.Header = accounts.header(t, "signed-in-owner")
	response = httptest.NewRecorder()
	s.mahjongHistoryDetail(response, request)
	if response.Code != http.StatusNotFound || probe.accountID != "signed-in-owner" || probe.matchID != "other-match" {
		t.Fatalf("detail did not use the authenticated owner or leaked existence: %d", response.Code)
	}
}

func TestMahjongHistoryCapturesCompletedRoundOnce(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	recorded := []mahjonghistory.Result{}
	fixture.hub.recordHistory = func(result mahjonghistory.Result) { recorded = append(recorded, result) }
	r := fixture.hub.rooms[fixture.rooms[0]]
	r.mu.Lock()
	defer r.mu.Unlock()
	r.finishIfNeededLocked(fixture.hub)
	if len(recorded) != 0 {
		t.Fatal("playing round was recorded as finished")
	}
	for range 120 {
		if r.game.Phase == guiyang.PhaseFinished {
			break
		}
		r.game.Timeout()
	}
	r.finishIfNeededLocked(fixture.hub)
	r.finishIfNeededLocked(fixture.hub)
	if len(recorded) != 1 {
		t.Fatalf("finished result should be submitted once, got %d", len(recorded))
	}
	result := recorded[0]
	if result.MatchID != r.matchID || result.Members != r.game.Players || result.Reason != r.game.Reason || result.Scores != r.game.Scores || result.Rule != r.rule || result.StartedAt.IsZero() || result.FinishedAt.Before(result.StartedAt) || time.Since(result.FinishedAt) > time.Minute {
		t.Fatalf("recorded result differs from authoritative result: %+v", result)
	}
}
