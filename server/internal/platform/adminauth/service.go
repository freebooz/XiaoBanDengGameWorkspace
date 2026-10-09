// Package adminauth（只读管理员认证）提供口令校验与服务端会话，不扩展运营写权限。
package adminauth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrUnauthorized = errors.New("管理员凭据或会话无效")
	ErrUnavailable  = errors.New("管理员认证服务暂不可用")
	ErrRateLimited  = errors.New("登录过于频繁，请稍后重试")
)

// Session（只读会话）仅返回身份和到期时间，令牌只保存在 HttpOnly Cookie。
type Session struct {
	Username  string    `json:"username"`
	Role      string    `json:"role"`
	ExpiresAt time.Time `json:"expires_at"`
}

// Store（会话存储）由 Redis 实现；存储失败时禁止降级授权。
type Store interface {
	Put(context.Context, string, Session, time.Duration) error
	Get(context.Context, string) (Session, error)
	Delete(context.Context, string) error
	AllowAttempt(context.Context, string) (bool, error)
}

// Service（认证服务）只接受部署环境注入的 bcrypt 哈希。
type Service struct {
	username   string
	hash       []byte
	store      Store
	configured bool
}

func New(username, hash string, store Store) *Service {
	cost, err := bcrypt.Cost([]byte(hash))
	return &Service{username: username, hash: []byte(hash), store: store, configured: username != "" && err == nil && cost >= bcrypt.DefaultCost && store != nil}
}

// Login（登录）对来源节流；统一返回凭据错误，避免泄露用户名存在性。
func (s *Service) Login(ctx context.Context, username, password, source string) (string, Session, error) {
	if !s.configured {
		return "", Session{}, ErrUnavailable
	}
	allowed, err := s.store.AllowAttempt(ctx, tokenKey(source))
	if err != nil {
		return "", Session{}, ErrUnavailable
	}
	if !allowed {
		return "", Session{}, ErrRateLimited
	}
	passwordErr := bcrypt.CompareHashAndPassword(s.hash, []byte(password))
	if username != s.username || passwordErr != nil {
		return "", Session{}, ErrUnauthorized
	}
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", Session{}, ErrUnavailable
	}
	token := base64.RawURLEncoding.EncodeToString(bytes)
	const ttl = 12 * time.Hour
	session := Session{Username: s.username, Role: "readonly", ExpiresAt: time.Now().UTC().Add(ttl)}
	if err := s.store.Put(ctx, tokenKey(token), session, ttl); err != nil {
		return "", Session{}, ErrUnavailable
	}
	return token, session, nil
}

// Session（恢复会话）同时检查存储与到期时间，重启服务仍可恢复 Redis 会话。
func (s *Service) Session(ctx context.Context, token string) (Session, error) {
	if token == "" || len(token) > 128 || !s.configured {
		return Session{}, ErrUnauthorized
	}
	session, err := s.store.Get(ctx, tokenKey(token))
	if errors.Is(err, ErrUnauthorized) {
		return Session{}, ErrUnauthorized
	}
	if err != nil {
		return Session{}, ErrUnavailable
	}
	if session.Username != s.username || session.Role != "readonly" || !session.ExpiresAt.After(time.Now()) {
		return Session{}, ErrUnauthorized
	}
	return session, nil
}

// Logout（注销）删除服务端令牌；存储失败不会伪报已注销。
func (s *Service) Logout(ctx context.Context, token string) error {
	if token == "" {
		return nil
	}
	if s.store == nil {
		return ErrUnavailable
	}
	if err := s.store.Delete(ctx, tokenKey(token)); err != nil {
		return ErrUnavailable
	}
	return nil
}

// tokenKey（令牌摘要）避免 Redis 键暴露浏览器可用的原始令牌。
func tokenKey(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
