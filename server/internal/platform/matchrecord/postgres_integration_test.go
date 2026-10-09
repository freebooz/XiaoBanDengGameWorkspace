package matchrecord_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/admin"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchrecord"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// 使用专用测试连接与临时schema，绝不删除业务schema或依赖已有对局数据。
func isolatedPostgres(t *testing.T, legacy bool) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("XBD_TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("设置XBD_TEST_POSTGRES_DSN后运行真实PostgreSQL集成测试")
	}
	ctx := context.Background()
	base, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	schema := "matchrecord_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if _, err := base.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		base.Close()
		t.Fatal(err)
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		pool.Close()
		_, _ = base.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE")
		base.Close()
	})
	if legacy {
		_, err = pool.Exec(ctx, `CREATE TABLE game_matches(match_id UUID PRIMARY KEY,product_id VARCHAR(64) NOT NULL,game_id VARCHAR(64) NOT NULL,rule_set_id VARCHAR(64) NOT NULL,rule_version VARCHAR(32) NOT NULL,status VARCHAR(24) NOT NULL,started_at TIMESTAMPTZ,finished_at TIMESTAMPTZ,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()); INSERT INTO game_matches(match_id,product_id,game_id,rule_set_id,rule_version,status) VALUES('00000000-0000-0000-0000-000000000001','legacy','chinese_chess','standard','1.0.0','finished')`)
		if err != nil {
			t.Fatal(err)
		}
	}
	_, sourceFile, _, _ := runtime.Caller(0)
	schemaSQL, err := os.ReadFile(filepath.Join(filepath.Dir(sourceFile), "../../infra/postgres/schema.sql"))
	if err != nil {
		t.Fatal(err)
	}
	// 第二次迁移必须幂等，且保留迁移前记录。
	for i := 0; i < 2; i++ {
		if _, err := pool.Exec(ctx, string(schemaSQL)); err != nil {
			t.Fatal(err)
		}
	}
	return pool
}

func newRecordedMatch() matchrecord.Match {
	return matchrecord.Match{MatchID: uuid.NewString(), RoomID: uuid.NewString(), ProductID: "xbd_chinese_chess", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0", Source: "room", StartedAt: time.Now().UTC(), Players: []matchrecord.Player{{ClientID: "browser-red", Seat: "red"}, {ClientID: "browser-black", Seat: "black"}}, Snapshot: json.RawMessage(`{"status":"playing","sequence":0,"pieces":[]}`)}
}

func newRecordedChange(matchID string, sequence int64) matchrecord.Change {
	return matchrecord.Change{MatchID: matchID, Sequence: sequence, EventType: "chess_move", Payload: json.RawMessage(`{"move":"accepted"}`), Snapshot: json.RawMessage(`{"pieces":[]}`), Status: "playing", OccurredAt: time.Now().UTC()}
}

func TestPostgresMatchRecordsAndAdminPaging(t *testing.T) {
	pool := isolatedPostgres(t, true)
	ctx := context.Background()
	store := matchrecord.NewPostgresStore(pool)
	match := newRecordedMatch()
	if err := store.CreateMatch(ctx, match); err != nil {
		t.Fatal(err)
	}
	if err := store.AppendChange(ctx, newRecordedChange(match.MatchID, 1)); err != nil {
		t.Fatal(err)
	}
	finished := newRecordedChange(match.MatchID, 2)
	finished.Status, finished.Winner, finished.ResultReason = "finished", "red", "general_captured"
	if err := store.AppendChange(ctx, finished); err != nil {
		t.Fatal(err)
	}
	service := admin.NewService(pool, room.NewManager())
	detail, err := service.MatchDetail(ctx, match.MatchID, admin.MatchRecordQuery{EventPage: 2, SnapshotPage: 2, RecordPageSize: 1})
	if err != nil {
		t.Fatal(err)
	}
	if detail.EventTotal != 2 || detail.SnapshotTotal != 3 || len(detail.Events) != 1 || detail.Events[0].Sequence != 2 || len(detail.Snapshots) != 1 || detail.Snapshots[0].Sequence != 1 {
		t.Fatalf("记录分页错误: %+v", detail)
	}
	if detail.Summary.RoomID != match.RoomID || detail.Summary.Winner != "red" || detail.Summary.FinishedAt == nil || len(detail.Players) != 2 {
		t.Fatalf("摘要/席位未持久化: %+v", detail)
	}
	empty, err := service.MatchDetail(ctx, match.MatchID, admin.MatchRecordQuery{EventPage: 10, SnapshotPage: 10, RecordPageSize: 1})
	if err != nil || len(empty.Events) != 0 || len(empty.Snapshots) != 0 || empty.EventTotal != 2 {
		t.Fatalf("越界分页应为空但保留总数: %+v err=%v", empty, err)
	}
	legacy, err := service.MatchDetail(ctx, "00000000-0000-0000-0000-000000000001", admin.MatchRecordQuery{})
	if err != nil || legacy.Summary.ProductID != "legacy" || len(legacy.Players) != 0 {
		t.Fatalf("增量迁移破坏旧对局: %+v err=%v", legacy, err)
	}
	page, err := service.ListMatches(ctx, admin.MatchQuery{Page: 1, PageSize: 20})
	if err != nil || page.Total != 2 {
		t.Fatalf("对局列表错误: %+v err=%v", page, err)
	}
	if err := store.AppendChange(ctx, newRecordedChange(match.MatchID, 3)); err == nil {
		t.Fatal("已结束对局不应继续写入")
	}
	development := newRecordedMatch()
	development.Source = "development"
	if err := store.CreateMatch(ctx, development); err != nil {
		t.Fatal(err)
	}
	overview, err := service.Overview(ctx)
	if err != nil || overview.TotalMatches != 2 {
		t.Fatalf("运营总数应排除显式开发对局并保留sourceNULL旧数据: %+v err=%v", overview, err)
	}
	allMatches, err := service.ListMatches(ctx, admin.MatchQuery{Page: 1, PageSize: 20})
	if err != nil || allMatches.Total != 3 {
		t.Fatalf("管理列表仍应包含可辨别来源的开发记录: %+v err=%v", allMatches, err)
	}
}

func TestPostgresChangeRollbackAndConcurrentSequence(t *testing.T) {
	pool := isolatedPostgres(t, false)
	ctx := context.Background()
	store := matchrecord.NewPostgresStore(pool)
	match := newRecordedMatch()
	if err := store.CreateMatch(ctx, match); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, "ALTER TABLE game_snapshots ADD CONSTRAINT fail_sequence_one CHECK(sequence <> 1) NOT VALID"); err != nil {
		t.Fatal(err)
	}
	if err := store.AppendChange(ctx, newRecordedChange(match.MatchID, 1)); err == nil {
		t.Fatal("数据库快照失败应传回错误")
	}
	var events, snapshots, sequence int64
	if err := pool.QueryRow(ctx, "SELECT (SELECT COUNT(*) FROM game_events WHERE match_id=$1),(SELECT COUNT(*) FROM game_snapshots WHERE match_id=$1),last_sequence FROM game_matches WHERE match_id=$1", match.MatchID).Scan(&events, &snapshots, &sequence); err != nil {
		t.Fatal(err)
	}
	if events != 0 || snapshots != 1 || sequence != 0 {
		t.Fatalf("失败事务未全部回滚: events=%d snapshots=%d sequence=%d", events, snapshots, sequence)
	}
	if _, err := pool.Exec(ctx, "ALTER TABLE game_snapshots DROP CONSTRAINT fail_sequence_one"); err != nil {
		t.Fatal(err)
	}
	errors := make(chan error, 2)
	var group sync.WaitGroup
	for i := 0; i < 2; i++ {
		group.Add(1)
		go func() { defer group.Done(); errors <- store.AppendChange(ctx, newRecordedChange(match.MatchID, 1)) }()
	}
	group.Wait()
	close(errors)
	successes := 0
	for err := range errors {
		if err == nil {
			successes++
		}
	}
	if successes != 1 {
		t.Fatalf("相同序号并发提交只能成功一次，实际=%d", successes)
	}
}

func TestPostgresCreateRollbackKeepsNoPartialIndexOrPlayers(t *testing.T) {
	pool := isolatedPostgres(t, false)
	ctx := context.Background()
	if _, err := pool.Exec(ctx, "ALTER TABLE game_snapshots ADD CONSTRAINT fail_initial_snapshot CHECK(sequence <> 0) NOT VALID"); err != nil {
		t.Fatal(err)
	}
	match := newRecordedMatch()
	if err := matchrecord.NewPostgresStore(pool).CreateMatch(ctx, match); err == nil {
		t.Fatal("初始快照失败应传回错误")
	}
	var matches, players int64
	if err := pool.QueryRow(ctx, "SELECT (SELECT COUNT(*) FROM game_matches WHERE match_id=$1),(SELECT COUNT(*) FROM game_match_players WHERE match_id=$1)", match.MatchID).Scan(&matches, &players); err != nil {
		t.Fatal(err)
	}
	if matches != 0 || players != 0 {
		t.Fatalf("创建事务失败遗留部分记录: matches=%d players=%d", matches, players)
	}
}
