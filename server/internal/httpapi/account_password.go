package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
)

type passwordAccounts interface {
	Register(context.Context, string, string) (account.GuestLogin, error)
	Login(context.Context, string, string) (account.GuestLogin, error)
}

func (s *Server) passwordRegister(w http.ResponseWriter, r *http.Request) {
	s.passwordAuthRequest(w, r, true)
}

func (s *Server) passwordLogin(w http.ResponseWriter, r *http.Request) {
	s.passwordAuthRequest(w, r, false)
}

func (s *Server) passwordAuthRequest(w http.ResponseWriter, r *http.Request, register bool) {
	w.Header().Set("Cache-Control", "no-store")
	service, ok := s.accounts.(passwordAccounts)
	if !ok {
		writeError(w, http.StatusServiceUnavailable, "账号登录服务暂不可用")
		return
	}
	var input struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil || decoder.Decode(new(any)) != io.EOF {
		writeError(w, http.StatusBadRequest, "请输入有效的账号和密码")
		return
	}
	source, _, _ := net.SplitHostPort(r.RemoteAddr)
	if source == "" {
		source = r.RemoteAddr
	}
	username := strings.ToLower(strings.TrimSpace(input.Username))
	if len(username) > 32 {
		username = ""
	}
	accept, retry := s.passwordAuth.begin(time.Now(), source, username)
	if !accept {
		w.Header().Set("Retry-After", retry)
		writeError(w, http.StatusTooManyRequests, "尝试次数过多，请稍后再试")
		return
	}
	defer s.passwordAuth.end()
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()
	status, action := http.StatusOK, service.Login
	if register {
		status, action = http.StatusCreated, service.Register
	}
	login, err := action(ctx, input.Username, input.Password)
	switch {
	case errors.Is(err, account.ErrInvalidRegistration):
		writeError(w, http.StatusBadRequest, account.ErrInvalidRegistration.Error())
	case errors.Is(err, account.ErrUsernameTaken):
		writeError(w, http.StatusConflict, account.ErrUsernameTaken.Error())
	case errors.Is(err, account.ErrInvalidPasswordLogin):
		writeError(w, http.StatusUnauthorized, account.ErrInvalidPasswordLogin.Error())
	case err != nil:
		writeError(w, http.StatusServiceUnavailable, "账号登录服务暂不可用")
	default:
		writeJSON(w, status, login)
	}
}

// Both endpoints pay the same per-account and connection rate limits. RemoteAddr
// is used rather than trusting headers supplied by arbitrary callers.
type passwordAuthLimiter struct {
	mu       sync.Mutex
	window   time.Time
	sources  map[string]int
	accounts map[string]int
	active   int
}

func (l *passwordAuthLimiter) begin(now time.Time, source, username string) (bool, string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.active >= 6 {
		return false, "1"
	}
	if !now.Before(l.window) {
		l.window = now.Add(time.Minute)
		l.sources = make(map[string]int)
		l.accounts = make(map[string]int)
	}
	if (len(l.sources) >= 1024 && l.sources[source] == 0) ||
		(len(l.accounts) >= 8192 && l.accounts[username] == 0) ||
		l.sources[source] >= 180 || l.accounts[username] >= 12 {
		return false, "60"
	}
	l.sources[source]++
	l.accounts[username]++
	l.active++
	return true, ""
}

func (l *passwordAuthLimiter) end() {
	l.mu.Lock()
	l.active--
	l.mu.Unlock()
}
