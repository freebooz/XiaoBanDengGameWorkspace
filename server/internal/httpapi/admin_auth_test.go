package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/adminauth"
	"golang.org/x/crypto/bcrypt"
)

// authMemory（HTTP 会话夹具）验证 Cookie，不伪造正式运营身份。
type authMemory struct{ sessions map[string]adminauth.Session }

func (m *authMemory) Put(_ context.Context, key string, value adminauth.Session, _ time.Duration) error {
	m.sessions[key] = value
	return nil
}
func (m *authMemory) Get(_ context.Context, key string) (adminauth.Session, error) {
	value, ok := m.sessions[key]
	if !ok {
		return value, adminauth.ErrUnauthorized
	}
	return value, nil
}
func (m *authMemory) Delete(_ context.Context, key string) error         { delete(m.sessions, key); return nil }
func (m *authMemory) AllowAttempt(context.Context, string) (bool, error) { return true, nil }

// TestAdminCookieLifecycle（认证链路）覆盖登录、刷新恢复、只读限制与注销。
func TestAdminCookieLifecycle(t *testing.T) {
	hash, _ := bcrypt.GenerateFromPassword([]byte("test-only-password"), bcrypt.DefaultCost)
	s := &Server{cfg: config.Config{AdminCookieSecure: true}, auth: adminauth.New("operator", string(hash), &authMemory{sessions: map[string]adminauth.Session{}})}
	login := httptest.NewRecorder()
	s.adminLogin(login, httptest.NewRequest(http.MethodPost, "/api/v1/admin/auth/login", strings.NewReader(`{"username":"operator","password":"test-only-password"}`)))
	if login.Code != 200 {
		t.Fatal(login.Body.String())
	}
	cookie := login.Result().Cookies()[0]
	if !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteLaxMode {
		t.Fatalf("unsafe cookie: %+v", cookie)
	}
	next := s.requireAdmin(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	for _, tc := range []struct {
		method string
		cookie bool
		want   int
	}{{"GET", false, 401}, {"GET", true, 204}, {"POST", true, 405}} {
		req := httptest.NewRequest(tc.method, "/api/v1/admin/rooms", nil)
		if tc.cookie {
			req.AddCookie(cookie)
		}
		res := httptest.NewRecorder()
		next.ServeHTTP(res, req)
		if res.Code != tc.want {
			t.Fatalf("%+v got %d", tc, res.Code)
		}
	}
	request := httptest.NewRequest("GET", "/api/v1/admin/auth/session", nil)
	request.AddCookie(cookie)
	res := httptest.NewRecorder()
	s.adminSession(res, request)
	if res.Code != 200 {
		t.Fatal(res.Body.String())
	}
	request = httptest.NewRequest("POST", "/api/v1/admin/auth/logout", nil)
	request.AddCookie(cookie)
	res = httptest.NewRecorder()
	s.adminLogout(res, request)
	if res.Code != 204 {
		t.Fatal(res.Code)
	}
	request = httptest.NewRequest("GET", "/api/v1/admin/rooms", nil)
	request.AddCookie(cookie)
	res = httptest.NewRecorder()
	next.ServeHTTP(res, request)
	if res.Code != 401 {
		t.Fatal(res.Code)
	}
}

// TestAdminOriginAndDefaultDeny（来源与默认拒绝）避免管理 Cookie 被通配跨域暴露。
func TestAdminOriginAndDefaultDeny(t *testing.T) {
	handler := New(config.Config{}, nil, nil)
	for _, tc := range []struct {
		path, method, origin string
		want                 int
	}{{"/api/v1/admin/rooms", "GET", "", 401}, {"/api/v1/catalog", "GET", "", 200}, {"/api/v1/admin/auth/login", "POST", "https://evil.example", 403}, {"/api/v1/admin/auth/login", "POST", "", 503}} {
		req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(`{}`))
		req.Header.Set("Origin", tc.origin)
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		if res.Code != tc.want {
			t.Fatalf("%+v got %d %s", tc, res.Code, res.Body.String())
		}
		if res.Header().Get("Access-Control-Allow-Origin") == "*" && strings.Contains(tc.path, "/admin/") {
			t.Fatal("管理接口不得使用通配跨域")
		}
	}
}

// TestAllowedCredentialedCatalog（允许来源的目录）保证跨域部署的凭据请求可读取公共目录。
func TestAllowedCredentialedCatalog(t *testing.T) {
	handler := New(config.Config{AdminAllowedOrigins: []string{"https://ops.example"}}, nil, nil)
	for _, method := range []string{"GET", "OPTIONS"} {
		req := httptest.NewRequest(method, "/api/v1/catalog", nil)
		req.Header.Set("Origin", "https://ops.example")
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		if res.Header().Get("Access-Control-Allow-Origin") != "https://ops.example" || res.Header().Get("Access-Control-Allow-Credentials") != "true" {
			t.Fatal("目录跨域凭据头不完整")
		}
	}
}

// TestTrustedProxySource（代理来源）只读取可信代理覆写的单个客户端 IP。
func TestTrustedProxySource(t *testing.T) {
	s := &Server{cfg: config.Config{AdminTrustedProxyCIDRs: []string{"127.0.0.1/32"}}}
	for _, tc := range []struct{ remote, forwarded, want string }{{"127.0.0.1:4567", "192.0.2.10", "192.0.2.10"}, {"127.0.0.1:4567", "192.0.2.11", "192.0.2.11"}, {"192.0.2.12:5678", "192.0.2.10", "192.0.2.12"}, {"127.0.0.1:4567", "bad,192.0.2.10", "127.0.0.1"}} {
		req := httptest.NewRequest("POST", "/api/v1/admin/auth/login", nil)
		req.RemoteAddr = tc.remote
		req.Header.Set("X-Real-IP", tc.forwarded)
		if got := s.adminSourceIP(req); got != tc.want {
			t.Fatalf("%+v got %s", tc, got)
		}
	}
}
