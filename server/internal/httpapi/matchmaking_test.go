package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

func TestQuickMatchHandlerReturnsWaitingThenMatched(t *testing.T) {
	rooms := room.NewManager()
	s := &Server{matchmaking: matchmaking.NewManager(rooms)}

	request := func(accountID string) matchmaking.QuickMatchResult {
		body, _ := json.Marshal(matchmaking.QuickMatchRequest{
			AccountID:   accountID,
			ProductID:   "xbd_chinese_chess",
			GameID:      "chinese_chess",
			RuleSetID:   "standard",
			RuleVersion: "1.0.0",
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/matchmaking/quick", bytes.NewReader(body))
		res := httptest.NewRecorder()
		s.quickMatch(res, req)
		if res.Code != http.StatusOK {
			t.Fatalf("快速匹配应返回200，实际=%d body=%s", res.Code, res.Body.String())
		}
		var result matchmaking.QuickMatchResult
		if err := json.NewDecoder(res.Body).Decode(&result); err != nil {
			t.Fatal(err)
		}
		return result
	}

	first := request("red-account")
	second := request("black-account")
	if first.Status != matchmaking.StatusWaiting {
		t.Fatalf("首个玩家应等待: %+v", first)
	}
	if second.Status != matchmaking.StatusMatched || second.RoomID != first.RoomID {
		t.Fatalf("第二个玩家应匹配到首个房间: first=%+v second=%+v", first, second)
	}
}

func TestQuickMatchHandlerRejectsInvalidJSON(t *testing.T) {
	s := &Server{matchmaking: matchmaking.NewManager(room.NewManager())}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/matchmaking/quick", bytes.NewBufferString("{"))
	res := httptest.NewRecorder()
	s.quickMatch(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("非法JSON应返回400，实际=%d", res.Code)
	}
}
