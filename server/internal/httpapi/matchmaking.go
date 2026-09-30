package httpapi

import (
	"encoding/json"
	"net/http"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

// quickMatch（快速匹配接口）由客户端登录大厅后反复调用。
// 对同一account_id幂等；status=matched后客户端进入房间页面。
func (s *Server) quickMatch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "仅支持POST")
		return
	}
	var req matchmaking.QuickMatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "请求体不是合法JSON")
		return
	}
	result, err := s.matchmaking.QuickMatch(req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

// roomReady（房间准备）记录玩家准备状态；双方都准备后返回start=true。
func (s *Server) roomReady(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "仅支持POST")
		return
	}
	var req matchmaking.RoomReadyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "请求体不是合法JSON")
		return
	}
	result, err := s.matchmaking.Ready(req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

// cancelMatch（退出匹配/房间）只允许对局正式开始前调用。
func (s *Server) cancelMatch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "仅支持POST")
		return
	}
	var req matchmaking.CancelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "请求体不是合法JSON")
		return
	}
	if err := s.matchmaking.Cancel(req.AccountID); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "cancelled"})
}
