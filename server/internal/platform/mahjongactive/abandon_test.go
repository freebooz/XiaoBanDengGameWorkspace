package mahjongactive

import (
	"context"
	"crypto/sha256"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func activeTestStore(t *testing.T) (context.Context, *Service) {
	t.Helper()
	url := os.Getenv("XBD_MAHJONG_ACTIVE_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	t.Cleanup(cancel)
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated active Mahjong database")
	}
	t.Cleanup(db.Close)
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	return ctx, NewService(db)
}

func TestDisconnectDeadlinesSurviveGameCommits(t *testing.T) {
	ctx, store := activeTestStore(t)
	initial := Snapshot{MatchID: uuid.NewString(), RoomID: uuid.NewString(), Revision: 1, Payload: []byte(`{"game":1}`),
		DisconnectDeadlines: [4]int64{0, 1750000300000, 0, 0}}
	stamp, err := store.InsertCommitted(ctx, initial)
	if err != nil {
		t.Fatal(err)
	}
	check := func(expected [4]int64) {
		t.Helper()
		rows, err := NewService(store.db).List(ctx)
		if err != nil {
			t.Fatal(err)
		}
		for _, row := range rows {
			if row.MatchID == initial.MatchID {
				if row.DisconnectDeadlines != expected {
					t.Fatalf("restored deadlines %v, want %v", row.DisconnectDeadlines, expected)
				}
				return
			}
		}
		t.Fatal("missing active match")
	}
	check(initial.DisconnectDeadlines)
	changed := [4]int64{0, 0, 1750000380000, 1750000400000}
	if err := store.SetDisconnectDeadlines(ctx, initial.MatchID, "wrong-room", changed); !errors.Is(err, ErrConflict) {
		t.Fatalf("wrong room updated presence: %v", err)
	}
	if err := store.SetDisconnectDeadlines(ctx, initial.MatchID, initial.RoomID, changed); err != nil {
		t.Fatal(err)
	}
	if exact, err := store.CommittedAt(ctx, initial); err != nil || !exact.Equal(stamp) {
		t.Fatalf("presence changed the original game receipt or turn clock: %v", err)
	}
	next := initial
	next.Revision++
	next.Payload = []byte(`{"game":2}`)
	if err := store.Update(ctx, next); err != nil {
		t.Fatal(err)
	}
	check(changed)
	if err := store.SetDisconnectDeadlines(ctx, initial.MatchID, initial.RoomID, [4]int64{-1}); err == nil {
		t.Fatal("negative expiry accepted")
	}
	for _, malformed := range []string{"{}", "{1,2,3}", "{1,2,3,4,5}", "{1,NULL,3,4}", "{1,2,-3,4}", "[0:3]={1,2,3,4}", "{{1,2},{3,4}}"} {
		if _, err := store.db.Exec(ctx, `UPDATE mahjong_active_matches SET disconnect_deadlines=$2::TEXT::BIGINT[] WHERE match_id=$1`, initial.MatchID, malformed); err == nil {
			t.Fatalf("database accepted malformed seat deadlines %s", malformed)
		}
	}
	check(changed)
	if err := store.Abandon(ctx, initial.MatchID, initial.RoomID, next.Revision, nil); err != nil {
		t.Fatal(err)
	}
	if err := store.SetDisconnectDeadlines(ctx, initial.MatchID, initial.RoomID, changed); !errors.Is(err, ErrConflict) {
		t.Fatalf("a late presence write revived a terminal hand: %v", err)
	}
}

func TestAbandonAtomicallyRetiresFriendAndFencesLateRetries(t *testing.T) {
	ctx, store := activeTestStore(t)
	friends := mahjongrooms.NewService(store.db)
	active := Snapshot{MatchID: uuid.NewString(), RoomID: uuid.NewString(), Revision: 1, Payload: []byte(`{"game":1}`)}
	head := mahjongrooms.Snapshot{RoomID: active.RoomID, CreatedAt: time.Now().UTC(), Revision: 1, Payload: []byte(`{"room":1}`)}
	if err := store.Insert(ctx, active); err != nil {
		t.Fatal(err)
	}
	if err := friends.Save(ctx, head); err != nil {
		t.Fatal(err)
	}
	retire := func(ctx context.Context, tx pgx.Tx) error {
		return friends.DeleteTx(ctx, tx, head.RoomID, head.CreatedAt, head.Revision)
	}
	if err := store.Abandon(ctx, active.MatchID, "another-room", 1, retire); !errors.Is(err, ErrConflict) {
		t.Fatalf("wrong room dissolved: %v", err)
	}
	if err := store.Abandon(ctx, active.MatchID, active.RoomID, 2, retire); !errors.Is(err, ErrConflict) {
		t.Fatalf("wrong revision dissolved: %v", err)
	}
	if err := store.Abandon(ctx, active.MatchID, active.RoomID, 1, func(ctx context.Context, tx pgx.Tx) error {
		return friends.DeleteTx(ctx, tx, head.RoomID, head.CreatedAt.Add(time.Second), head.Revision)
	}); !errors.Is(err, mahjongrooms.ErrConflict) {
		t.Fatalf("stale friend room generation dissolved: %v", err)
	}
	interrupted := errors.New("injected interruption")
	if err := store.Abandon(ctx, active.MatchID, active.RoomID, 1, func(ctx context.Context, tx pgx.Tx) error {
		if err := retire(ctx, tx); err != nil {
			return err
		}
		return interrupted
	}); !errors.Is(err, interrupted) {
		t.Fatalf("abandonment lost a write failure: %v", err)
	}
	if ok, err := store.Matches(ctx, active); err != nil || !ok {
		t.Fatalf("aborted retirement lost the game checkpoint: %v", err)
	}
	if _, err := friends.Load(ctx, active.RoomID); err != nil {
		t.Fatalf("aborted retirement lost the friend room: %v", err)
	}
	if err := store.Abandon(ctx, active.MatchID, active.RoomID, 1, retire); err != nil {
		t.Fatal(err)
	}
	if _, err := friends.Load(ctx, active.RoomID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("dissolved friend room restored: %v", err)
	}
	if err := store.Insert(ctx, active); !errors.Is(err, ErrConflict) {
		t.Fatalf("old initial deal revived a dissolved hand: %v", err)
	}
	never := func(context.Context, pgx.Tx) error { return errors.New("terminal retry performed a new write") }
	if err := store.Complete(ctx, active.MatchID, 1, sha256.Sum256([]byte("hu")), never); !errors.Is(err, ErrConflict) {
		t.Fatalf("late settlement succeeded for a dissolved hand: %v", err)
	}
	var published bool
	if err := store.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM mahjong_match_results WHERE match_id=$1::TEXT::UUID)
		OR EXISTS(SELECT 1 FROM wallet_ledger WHERE reference_id=$1::TEXT)`, active.MatchID).Scan(&published); err != nil || published {
		t.Fatalf("abandonment published settlement or changed a wallet: %v", err)
	}
	replacement := active
	replacement.MatchID = uuid.NewString()
	if err := store.Insert(ctx, replacement); err != nil {
		t.Fatalf("dissolved round still owns its room: %v", err)
	}
	head.CreatedAt = head.CreatedAt.Add(time.Second)
	if err := friends.Save(ctx, head); err != nil {
		t.Fatal(err)
	}
	if err := store.Abandon(ctx, active.MatchID, active.RoomID, 1, never); err != nil {
		t.Fatalf("a committed abandonment could not replay after room reuse: %v", err)
	}
	if ok, err := store.Matches(ctx, replacement); err != nil || !ok {
		t.Fatalf("old timeout removed a replacement hand: %v", err)
	}
	if err := store.Abandon(ctx, replacement.MatchID, replacement.RoomID, 1, retire); err != nil {
		t.Fatal(err)
	}
}
