package httpapi

import (
	"context"
	"crypto/sha256"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/gorilla/websocket"
)

type accountSessions interface {
	CreateGuest(context.Context) (account.GuestLogin, error)
	Session(context.Context, string) (account.Session, error)
}

func (s *Server) guestLogin(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "仅支持POST")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	info, err := s.accounts.CreateGuest(ctx)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "暂时无法登录，请稍后重试")
		return
	}
	writeJSON(w, http.StatusCreated, info)
}

func (s *Server) authSession(w http.ResponseWriter, r *http.Request) {
	if !requireGET(w, r) {
		return
	}
	if session, ok := s.requireSession(w, r); ok {
		writeJSON(w, http.StatusOK, session)
	}
}

func (s *Server) requireSession(w http.ResponseWriter, r *http.Request) (account.Session, bool) {
	w.Header().Set("Cache-Control", "no-store")
	token := accountBearer(r)
	if token == "" {
		writeError(w, http.StatusUnauthorized, "请先登录")
		return account.Session{}, false
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	session, err := s.accounts.Session(ctx, token)
	if errors.Is(err, account.ErrInvalidSession) || (err == nil && (session.AccountID == "" || !session.ExpiresAt.After(time.Now()))) {
		writeError(w, http.StatusUnauthorized, "登录已失效，请重新登录")
		return account.Session{}, false
	}
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "登录服务暂时不可用，请稍后重试")
		return account.Session{}, false
	}
	return session, true
}

func accountBearer(r *http.Request) string {
	values := r.Header.Values("Authorization")
	if len(values) != 1 {
		return ""
	}
	parts := strings.Fields(values[0])
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || len(parts[1]) != 43 {
		return ""
	}
	return parts[1]
}

type accountPrivacy interface {
	RevokeSession(context.Context, string) error
	RequestDeletion(context.Context, string) (account.DeletionReceipt, error)
}

func (s *Server) authLogout(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	token := accountBearer(r)
	if token == "" {
		writeError(w, http.StatusUnauthorized, "请先登录")
		return
	}
	privacy, ok := s.accounts.(accountPrivacy)
	if !ok {
		writeError(w, http.StatusServiceUnavailable, "账号服务暂时不可用")
		return
	}
	s.socketsMu.Lock()
	defer s.socketsMu.Unlock()
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if err := privacy.RevokeSession(ctx, token); err != nil {
		if errors.Is(err, account.ErrInvalidSession) {
			writeError(w, http.StatusUnauthorized, "登录已失效，请重新登录")
		} else {
			writeError(w, http.StatusServiceUnavailable, "退出登录暂未确认，请重试")
		}
		return
	}
	digest := sha256.Sum256([]byte(token))
	s.closeMahjongSessions("", &digest)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) authDeleteRequest(w http.ResponseWriter, r *http.Request) {
	s.socketsMu.Lock()
	defer s.socketsMu.Unlock()
	session, valid := s.requireSession(w, r)
	if !valid {
		return
	}
	privacy, ok := s.accounts.(accountPrivacy)
	if !ok {
		writeError(w, http.StatusServiceUnavailable, "账号服务暂时不可用")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	receipt, err := privacy.RequestDeletion(ctx, session.AccountID)
	if err != nil {
		if errors.Is(err, account.ErrDeletionUnavailable) {
			writeError(w, http.StatusConflict, err.Error())
		} else {
			writeError(w, http.StatusServiceUnavailable, "删除申请暂未确认，请重试")
		}
		return
	}
	s.closeMahjongSessions(session.AccountID, nil)
	writeJSON(w, http.StatusAccepted, receipt)
}

func (s *Server) mahjongWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, session, ok := s.upgradeMahjongSession(w, r)
	if !ok {
		return
	}
	defer s.removeMahjongSocket(conn)
	defer conn.Close()
	conn.SetReadLimit(256 << 10)
	const receiveTimeout = 15 * time.Second
	if err := conn.SetReadDeadline(time.Now().Add(receiveTimeout)); err != nil {
		return
	}
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(receiveTimeout))
	})
	done := make(chan struct{})
	defer close(done)
	go func() {
		ping := time.NewTicker(5 * time.Second)
		defer ping.Stop()
		for {
			select {
			case <-done:
				return
			case <-ping.C:
				if conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(time.Second)) != nil {
					_ = conn.Close()
					return
				}
			}
		}
	}()
	client := newMahjongClient(newChessClient(conn))
	client.principal = session.AccountID
	client.displayName = session.DisplayName
	defer s.mahjong.disconnect(client)
	expire := func() {
		_ = conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "session_expired"), time.Now().Add(time.Second))
		_ = conn.Close()
	}
	expiry := time.AfterFunc(time.Until(session.ExpiresAt), expire)
	defer expiry.Stop()
	if client.writeJSON(map[string]any{"type": "connected", "message": "麻将连接已建立"}) != nil {
		return
	}
	for {
		var message map[string]any
		if err := conn.ReadJSON(&message); err != nil {
			return
		}
		if !time.Now().Before(session.ExpiresAt) {
			return
		}
		if !s.mahjong.handle(client, message) {
			client.fail("未知的麻将消息")
		}
	}
}

func (s *Server) upgradeMahjongSession(w http.ResponseWriter, r *http.Request) (*websocket.Conn, account.Session, bool) {
	s.socketsMu.Lock()
	defer s.socketsMu.Unlock()
	if s.draining {
		writeError(w, http.StatusServiceUnavailable, "服务正在交接，请稍后重连")
		return nil, account.Session{}, false
	}
	session, ok := s.requireSession(w, r)
	if !ok {
		return nil, account.Session{}, false
	}
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return nil, account.Session{}, false
	}
	if s.sockets == nil {
		s.sockets = make(map[*websocket.Conn]authenticatedMahjongSocket)
	}
	s.sockets[conn] = authenticatedMahjongSocket{accountID: session.AccountID, digest: sha256.Sum256([]byte(accountBearer(r)))}
	return conn, session, true
}
