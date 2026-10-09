package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	adminplatform "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/admin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

// TestAdminRealServices（真实依赖回归）必须显式提供隔离测试数据库与 Redis，默认跳过。
// 数据只由真实象棋协议产生，并标记 development；不向生产库预填运营记录。
func TestAdminRealServices(t *testing.T) {
	databaseURL, redisAddr := os.Getenv("TEST_POSTGRES_URL"), os.Getenv("TEST_REDIS_ADDR")
	if databaseURL == "" || redisAddr == "" {
		t.Skip("未提供隔离 PostgreSQL/Redis 测试服务")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for i := 0; i < 2; i++ {
		if err := postgres.Migrate(ctx, db); err != nil {
			t.Fatal("幂等迁移", err)
		}
	}
	cache := redis.NewClient(&redis.Options{Addr: redisAddr})
	defer cache.Close()
	if err := cache.Ping(ctx).Err(); err != nil {
		t.Fatal(err)
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte("integration-only-password"), bcrypt.DefaultCost)
	cfg := config.Config{AdminUsername: "regression-operator", AdminPasswordHash: string(hash), DevelopmentRooms: true}
	server := httptest.NewServer(New(cfg, db, cache))
	defer server.Close()
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar, Timeout: 5 * time.Second}
	request := func(method, path, body string, want int, target any) {
		t.Helper()
		req, _ := http.NewRequest(method, server.URL+path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		if res.StatusCode != want {
			raw, _ := io.ReadAll(res.Body)
			t.Fatalf("%s %s: %d %s", method, path, res.StatusCode, raw)
		}
		if target != nil {
			if err := json.NewDecoder(res.Body).Decode(target); err != nil {
				t.Fatal(err)
			}
		}
	}
	request("GET", "/api/v1/admin/rooms", "", 401, nil)
	request("POST", "/api/v1/admin/auth/login", `{"username":"regression-operator","password":"wrong"}`, 401, nil)
	request("POST", "/api/v1/admin/auth/login", `{"username":"regression-operator","password":"integration-only-password"}`, 200, nil)
	request("GET", "/api/v1/admin/auth/session", "", 200, nil)
	request("POST", "/api/v1/admin/matches", "{}", 405, nil)
	roomID := "regression-development-" + uuid.NewString()
	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"
	red := dialTestWebSocket(t, wsURL)
	defer red.Close()
	black := dialTestWebSocket(t, wsURL)
	defer black.Close()
	joinTestChessRoom(t, red, roomID, "test-only-red")
	state := joinTestChessRoom(t, black, roomID, "test-only-black")
	_ = readUntilType(t, red, "chess_state", nil)
	matchID := state["match_id"].(string)
	// 清理仅本测试生成的对局；连接先关闭使断线写入完成，绝不清空整库。
	defer func() {
		_ = red.Close()
		_ = black.Close()
		cleanupCtx, stop := context.WithTimeout(context.Background(), 5*time.Second)
		defer stop()
		// 原有事件/快照外键不级联删除，按依赖顺序只清理本次记录。
		for _, table := range []string{"game_events", "game_snapshots", "game_match_players", "game_matches"} {
			if _, err := db.Exec(cleanupCtx, "DELETE FROM "+table+" WHERE match_id=$1", matchID); err != nil {
				t.Errorf("清理测试记录: %v", err)
			}
		}
	}()
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_state", nil)
	_ = readUntilType(t, black, "chess_state", nil)
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_error", nil)
	var roomData adminplatform.RoomSummary
	request("GET", "/api/v1/admin/rooms/"+roomID, "", 200, &roomData)
	if roomData.ConnectedCount != 2 || len(roomData.Players) != 2 || roomData.Source != "development" {
		t.Fatalf("真实目录不同步: %+v", roomData)
	}
	var detail adminplatform.MatchDetail
	request("GET", "/api/v1/admin/matches/"+matchID+"?event_page=1&snapshot_page=1&record_page_size=1", "", 200, &detail)
	if detail.EventTotal != 1 || detail.SnapshotTotal != 2 || len(detail.Snapshots) != 1 || len(detail.Players) != 2 || detail.Summary.Source != "development" {
		t.Fatalf("真实写入或分页错误: %+v", detail)
	}
	request("GET", "/api/v1/admin/matches/"+matchID+"?snapshot_page=2&record_page_size=1", "", 200, &detail)
	if detail.Snapshots[0].Sequence != 1 {
		t.Fatal("第二页必须返回真实走子快照")
	}
	request("GET", "/api/v1/admin/matches/"+matchID+"?event_page=0", "", 400, nil)
	_ = red.Close()
	_ = readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "waiting" })
	request("GET", "/api/v1/admin/matches/"+matchID, "", 200, &detail)
	if detail.Summary.Status != "aborted" || detail.EventTotal != 2 || detail.SnapshotTotal != 3 {
		t.Fatalf("断线中止未持久化: %+v", detail)
	}
	// 新 HTTP 实例验证历史与 Redis 会话跨服务实例可读，活动房间仍是进程目录。
	restarted := httptest.NewServer(New(cfg, db, cache))
	defer restarted.Close()
	req, _ := http.NewRequest("GET", restarted.URL+"/api/v1/admin/matches/"+matchID, nil)
	cookieURL, _ := url.Parse(server.URL + "/api/v1/admin/auth/session")
	for _, cookie := range jar.Cookies(cookieURL) {
		req.AddCookie(cookie)
	}
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatal("重启后历史与会话必须恢复", res.StatusCode)
	}
	request("POST", "/api/v1/admin/auth/logout", "{}", 204, nil)
	request("GET", "/api/v1/admin/auth/session", "", 401, nil)
}
