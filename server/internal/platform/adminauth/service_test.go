package adminauth

import (
	"context"
	"errors"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// memoryStore（会话夹具）只用于测试，不替代正式 Redis 存储。
type memoryStore struct {
	sessions    map[string]Session
	attempts    int
	unavailable bool
}

func (m *memoryStore) Put(_ context.Context, key string, value Session, _ time.Duration) error {
	if m.unavailable {
		return errors.New("offline")
	}
	m.sessions[key] = value
	return nil
}
func (m *memoryStore) Get(_ context.Context, key string) (Session, error) {
	if m.unavailable {
		return Session{}, errors.New("offline")
	}
	value, ok := m.sessions[key]
	if !ok {
		return Session{}, ErrUnauthorized
	}
	return value, nil
}
func (m *memoryStore) Delete(_ context.Context, key string) error {
	if m.unavailable {
		return errors.New("offline")
	}
	delete(m.sessions, key)
	return nil
}
func (m *memoryStore) AllowAttempt(_ context.Context, _ string) (bool, error) {
	if m.unavailable {
		return false, errors.New("offline")
	}
	m.attempts++
	return m.attempts <= 5, nil
}

// TestSessions（真实口令校验）验证随机会话、失效与后端故障关闭。
func TestSessions(t *testing.T) {
	hash, _ := bcrypt.GenerateFromPassword([]byte("test-only-password"), bcrypt.DefaultCost)
	store := &memoryStore{sessions: map[string]Session{}}
	svc := New("operator", string(hash), store)
	if _, _, err := svc.Login(context.Background(), "operator", "wrong", "ip"); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("wrong password: %v", err)
	}
	token, session, err := svc.Login(context.Background(), "operator", "test-only-password", "ip")
	if err != nil || token == "" || session.Role != "readonly" {
		t.Fatalf("login: %+v %v", session, err)
	}
	if _, exists := store.sessions[token]; exists {
		t.Fatal("Redis key must not contain raw session token")
	}
	if got, err := svc.Session(context.Background(), token); err != nil || got.Username != "operator" {
		t.Fatalf("restore: %+v %v", got, err)
	}
	if err := svc.Logout(context.Background(), token); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Session(context.Background(), token); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("logout: %v", err)
	}
	store.unavailable = true
	if _, err := svc.Session(context.Background(), token); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("offline: %v", err)
	}
}

// TestLoginFailsClosed（配置与节流）保证未配置管理员时不能免密进入。
func TestLoginFailsClosed(t *testing.T) {
	store := &memoryStore{sessions: map[string]Session{}}
	if _, _, err := New("", "", store).Login(context.Background(), "", "", "ip"); !errors.Is(err, ErrUnavailable) {
		t.Fatal(err)
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte("test-only-password"), bcrypt.DefaultCost)
	svc := New("operator", string(hash), store)
	for i := 0; i < 5; i++ {
		_, _, _ = svc.Login(context.Background(), "operator", "wrong", "ip")
	}
	if _, _, err := svc.Login(context.Background(), "operator", "test-only-password", "ip"); !errors.Is(err, ErrRateLimited) {
		t.Fatal(err)
	}
	expired := Session{Username: "operator", Role: "readonly", ExpiresAt: time.Now().Add(-time.Second)}
	store.sessions[tokenKey("expired")] = expired
	if _, err := svc.Session(context.Background(), "expired"); !errors.Is(err, ErrUnauthorized) {
		t.Fatal(err)
	}
}
