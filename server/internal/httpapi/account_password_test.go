package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/google/uuid"
)

func TestPasswordAccountRegistrationLoginAndSession(t *testing.T) {
	database := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if database == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, database)
	if err != nil {
		t.Fatal("could not connect to isolated account database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	handler := New(config.Config{}, db, nil)
	request := func(path, username, password string, expected int) *httptest.ResponseRecorder {
		t.Helper()
		body, err := json.Marshal(map[string]string{"username": username, "password": password})
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(string(body)))
		result := httptest.NewRecorder()
		handler.ServeHTTP(result, req)
		if result.Code != expected || result.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("%s status %d expected %d and no-store", path, result.Code, expected)
		}
		return result
	}
	const register, login = "/api/v1/auth/register", "/api/v1/auth/login"
	username := "player_" + uuid.NewString()[:8]
	const password = "测试 房间口令42 "
	request(register, "!", password, http.StatusBadRequest)
	request(register, username, "short", http.StatusBadRequest)
	created := request(register, "  "+strings.ToUpper(username)+"  ", password, http.StatusCreated)
	var profile account.GuestLogin
	if err := json.Unmarshal(created.Body.Bytes(), &profile); err != nil || profile.AccountID == "" || profile.Token == "" || utf8.RuneCountInString(profile.DisplayName) != 4 {
		t.Fatal("registration did not return account, token and four-character display name")
	}
	for _, character := range profile.DisplayName {
		if !unicode.Is(unicode.Han, character) {
			t.Fatal("registered display name must contain only Chinese characters")
		}
	}
	request(register, username, password, http.StatusConflict)
	wrong := request(login, username, strings.TrimSpace(password), http.StatusUnauthorized)
	unknown := request(login, "unknown_"+username, password, http.StatusUnauthorized)
	if wrong.Body.String() != unknown.Body.String() {
		t.Fatal("sign-in distinguishes unknown usernames and incorrect passwords")
	}
	var restored account.GuestLogin
	if err := json.Unmarshal(request(login, username, password, http.StatusOK).Body.Bytes(), &restored); err != nil ||
		restored.AccountID != profile.AccountID || restored.DisplayName != profile.DisplayName || restored.Token == "" || restored.Token == profile.Token {
		t.Fatal("sign-in did not restore the same account with a new session token")
	}
	sessionRequest := httptest.NewRequest(http.MethodGet, "/api/v1/auth/session", nil)
	sessionRequest.Header.Set("Authorization", "Bearer "+restored.Token)
	sessionResponse := httptest.NewRecorder()
	handler.ServeHTTP(sessionResponse, sessionRequest)
	var session account.Session
	if err := json.Unmarshal(sessionResponse.Body.Bytes(), &session); err != nil || sessionResponse.Code != http.StatusOK || session.AccountID != profile.AccountID {
		t.Fatal("existing session resolver did not recognize the password session")
	}
	var scheme, accountType string
	var saltBytes, hashBytes int
	if err := db.QueryRow(ctx, `SELECT scheme,account_type,octet_length(salt),octet_length(password_hash)
		FROM account_password_credentials c JOIN accounts a USING (account_id) WHERE username=$1`, username).Scan(
		&scheme, &accountType, &saltBytes, &hashBytes); err != nil || scheme != "argon2id-v1" || accountType != "registered" || saltBytes != 16 || hashBytes != 32 {
		t.Fatal("expected a separately salted Argon2id password digest for the registered account")
	}
}

func TestPasswordAuthLimiterBoundsConcurrentAndRepeatedAttempts(t *testing.T) {
	var limiter passwordAuthLimiter
	now := time.Now()
	for range 6 {
		if allowed, _ := limiter.begin(now, "proxy", "example"); !allowed {
			t.Fatal("unexpected concurrency rejection below cap")
		}
	}
	if allowed, retry := limiter.begin(now, "proxy", "other"); allowed || retry != "1" {
		t.Fatal("password work must remain bounded")
	}
	for range 6 {
		limiter.end()
		if allowed, _ := limiter.begin(now, "proxy", "example"); !allowed {
			t.Fatal("unexpected username rejection below cap")
		}
	}
	for range 6 {
		limiter.end()
	}
	if allowed, retry := limiter.begin(now, "second-source", "example"); allowed || retry != "60" {
		t.Fatal("username limit must apply across sources")
	}
	if allowed, _ := limiter.begin(now.Add(time.Minute), "proxy", "example"); !allowed {
		t.Fatal("username limit must expire")
	}
	limiter.end()
}
