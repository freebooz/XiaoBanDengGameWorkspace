package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/adminauth"
)

const adminCookieName = "xbd_admin_session"

// adminLogin（管理员登录）限制请求体，凭据不会写入日志或返回响应。
func (s *Server) adminLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, 405, "仅支持POST")
		return
	}
	if !s.adminOriginAllowed(r) {
		writeError(w, 403, "管理请求来源不被允许")
		return
	}
	var input struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, 400, "请求体不是合法登录信息")
		return
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		writeError(w, 400, "请求体必须只有一个JSON对象")
		return
	}
	token, session, err := s.auth.Login(r.Context(), input.Username, input.Password, s.adminSourceIP(r))
	if err != nil {
		writeAuthError(w, err)
		return
	}
	http.SetCookie(w, &http.Cookie{Name: adminCookieName, Value: token, Path: "/api/v1/admin", HttpOnly: true, Secure: s.cfg.AdminCookieSecure, SameSite: http.SameSiteLaxMode, Expires: session.ExpiresAt, MaxAge: 12 * 60 * 60})
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, 200, session)
}

// adminSession（刷新恢复）以服务端会话为准，前端存储不能授权。
func (s *Server) adminSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, 405, "仅支持GET")
		return
	}
	session, err := s.auth.Session(r.Context(), adminToken(r))
	if err != nil {
		writeAuthError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, 200, session)
}

// adminLogout（会话注销）先删除服务端会话，再清除浏览器 Cookie。
func (s *Server) adminLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, 405, "仅支持POST")
		return
	}
	if !s.adminOriginAllowed(r) {
		writeError(w, 403, "管理请求来源不被允许")
		return
	}
	if err := s.auth.Logout(r.Context(), adminToken(r)); err != nil {
		writeAuthError(w, err)
		return
	}
	http.SetCookie(w, &http.Cookie{Name: adminCookieName, Path: "/api/v1/admin", MaxAge: -1, Expires: time.Unix(1, 0), HttpOnly: true, Secure: s.cfg.AdminCookieSecure, SameSite: http.SameSiteLaxMode})
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(204)
}

// requireAdmin（只读认证边界）统一保护管理查询，未配置或服务故障均不放行。
func (s *Server) requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if _, err := s.auth.Session(r.Context(), adminToken(r)); err != nil {
			writeAuthError(w, err)
			return
		}
		if r.Method != http.MethodGet {
			writeError(w, 405, "管理业务接口仅支持只读GET查询")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// adminOriginAllowed（管理来源）允许同源或显式白名单；不信任客户端伪造的代理头。
func (s *Server) adminOriginAllowed(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	for _, allowed := range s.cfg.AdminAllowedOrigins {
		if origin == strings.TrimSpace(allowed) {
			return true
		}
	}
	parsed, err := url.Parse(origin)
	return err == nil && parsed.Host == r.Host && parsed.Path == "" && parsed.RawQuery == "" && parsed.Fragment == "" && parsed.User == nil && (parsed.Scheme == "https" || parsed.Scheme == "http" && !s.cfg.AdminCookieSecure)
}

// adminCORS（管理跨域）只回显经过验证的来源，公共游戏平台继续使用既有跨域规则。
func (s *Server) adminCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/v1/admin/") {
			// 显式允许的来源可携带会话读取公共目录；其他来源保持原公共接口跨域约定。
			if origin := r.Header.Get("Origin"); origin != "" && s.adminOriginAllowed(r) {
				w.Header().Set("Vary", "Origin")
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Access-Control-Allow-Credentials", "true")
				w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
				w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
				if r.Method == http.MethodOptions {
					w.WriteHeader(204)
					return
				}
				next.ServeHTTP(w, r)
				return
			}
			cors(next).ServeHTTP(w, r)
			return
		}
		w.Header().Set("Vary", "Origin")
		if !s.adminOriginAllowed(r) {
			writeError(w, 403, "管理请求来源不被允许")
			return
		}
		if origin := r.Header.Get("Origin"); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}
func adminToken(r *http.Request) string {
	cookie, err := r.Cookie(adminCookieName)
	if err != nil {
		return ""
	}
	return cookie.Value
}

// adminSourceIP（可靠来源）只信任配置中的直接代理，忽略非可信客户端伪造的转发头。
func (s *Server) adminSourceIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	remote := net.ParseIP(host)
	if remote == nil {
		return host
	}
	for _, value := range s.cfg.AdminTrustedProxyCIDRs {
		_, subnet, err := net.ParseCIDR(strings.TrimSpace(value))
		if err != nil || !subnet.Contains(remote) {
			continue
		}
		if source := net.ParseIP(strings.TrimSpace(r.Header.Get("X-Real-IP"))); source != nil {
			return source.String()
		}
	}
	return remote.String()
}
func writeAuthError(w http.ResponseWriter, err error) {
	status := 503
	if errors.Is(err, adminauth.ErrUnauthorized) {
		status = 401
	}
	if errors.Is(err, adminauth.ErrRateLimited) {
		status = 429
		w.Header().Set("Retry-After", "60")
	}
	w.Header().Set("Cache-Control", "no-store")
	writeError(w, status, err.Error())
}
