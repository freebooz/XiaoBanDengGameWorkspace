package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
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
	manager := s.matchmaking
	if req.GameID == string(domain.GameMahjong) || req.ProductID == string(domain.ProductMahjong) {
		if !s.verifyMahjongAccount(w, r, req.AccountID) {
			return
		}
		manager = s.mahjong.matches
	}
	match := manager.QuickMatch
	if manager != s.matchmaking {
		match = s.mahjong.quickMatch
	}
	result, err := match(req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if result.GameID == string(domain.GameMahjong) {
		s.mahjong.publishLobby(result.RoomID, req.AccountID)
	} else {
		s.monitor.notify()
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
	manager := s.matchmaking
	if s.rooms != nil {
		if item, exists := s.rooms.Get(req.RoomID); exists && item.GameID == string(domain.GameMahjong) {
			if !s.verifyMahjongAccount(w, r, req.AccountID) {
				return
			}
			manager = s.mahjong.matches
		}
	}
	ready := manager.Ready
	if manager != s.matchmaking {
		ready = s.mahjong.ready
	}
	result, err := ready(req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if manager != s.matchmaking {
		s.mahjong.publishLobby(result.RoomID, req.AccountID)
	} else {
		s.monitor.notify()
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
	accountID := strings.TrimSpace(req.AccountID)
	var err error
	if s.mahjong != nil {
		if current, assigned := s.mahjong.matches.MahjongAssignment(accountID); assigned {
			if !s.verifyMahjongAccount(w, r, accountID) {
				return
			}
			err = s.mahjong.leaveLobbyRoom(accountID, current)
			if err != nil {
				writeError(w, http.StatusBadRequest, err.Error())
				return
			}
			s.mahjong.publishLobby(current.RoomID, accountID)
			writeJSON(w, http.StatusOK, map[string]any{"status": "cancelled"})
			return
		}
	}
	if err = s.matchmaking.Cancel(accountID); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	s.monitor.notify()
	writeJSON(w, http.StatusOK, map[string]any{"status": "cancelled"})
}

func (s *Server) verifyMahjongAccount(w http.ResponseWriter, r *http.Request, accountID string) bool {
	session, ok := s.requireSession(w, r)
	if !ok {
		return false
	}
	if session.AccountID != strings.TrimSpace(accountID) {
		writeError(w, http.StatusForbidden, "账号与当前登录会话不符")
		return false
	}
	return true
}
