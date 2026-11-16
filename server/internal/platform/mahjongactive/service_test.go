package mahjongactive

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestActiveMahjongPostgresRevisionAndCompletion(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_ACTIVE_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated active Mahjong database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `CREATE TABLE IF NOT EXISTS test_mahjong_completions (match_id TEXT PRIMARY KEY)`); err != nil {
		t.Fatal(err)
	}
	store := NewService(db)
	first := Snapshot{MatchID: uuid.NewString(), RoomID: uuid.NewString(), Revision: 1, Payload: json.RawMessage(`{"revision":1,"wall":[1,2,3]}`)}
	first.CommittedAt = time.Unix(100, 0)
	insertedAt, err := store.InsertCommitted(ctx, first)
	if err != nil || insertedAt.IsZero() || insertedAt.Equal(first.CommittedAt) {
		t.Fatalf("insert did not stamp the database time: %v %v", insertedAt, err)
	}
	if exact, err := store.CommittedAt(ctx, first); err != nil || !exact.Equal(insertedAt) {
		t.Fatalf("ambiguous insert confirmation lost its exact timestamp: %v %v", exact, err)
	}
	if err := store.Insert(ctx, first); !errors.Is(err, ErrConflict) {
		t.Fatalf("insert must not replace the existing match: %v", err)
	}
	second := first
	second.MatchID = uuid.NewString()
	if err := store.Insert(ctx, second); !errors.Is(err, ErrConflict) {
		t.Fatalf("two active matches must not occupy the same room: %v", err)
	}
	advanced := first
	advanced.Revision = 2
	advanced.Payload = json.RawMessage(`{"revision":2,"wall":[3,2,1]}`)
	updatedAt, err := store.UpdateCommitted(ctx, advanced)
	if err != nil || updatedAt.Before(insertedAt) {
		t.Fatalf("update did not stamp the new revision: %v %v", updatedAt, err)
	}
	if err := store.Update(ctx, advanced); !errors.Is(err, ErrConflict) {
		t.Fatalf("update replay must not advance or overwrite current state: %v", err)
	}
	matching := advanced
	matching.Payload = json.RawMessage(`{ "wall":[3,2,1], "revision":2 }`)
	if same, err := store.Matches(ctx, matching); err != nil || !same {
		t.Fatalf("ambiguous update confirmation must ignore JSON formatting: %v %v", same, err)
	}
	if exact, err := store.CommittedAt(ctx, matching); err != nil || !exact.Equal(updatedAt) {
		t.Fatalf("ambiguous update confirmation lost its exact timestamp: %v %v", exact, err)
	}
	matching.Payload = first.Payload
	if same, err := store.Matches(ctx, matching); err != nil || same {
		t.Fatalf("ambiguous update confirmation must verify the private payload: %v %v", same, err)
	}
	if _, err := store.CommittedAt(ctx, matching); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("timestamp leaked for a nonmatching snapshot: %v", err)
	}
	wrongRoom := advanced
	wrongRoom.Revision++
	wrongRoom.RoomID = "5922"
	if err := store.Update(ctx, wrongRoom); !errors.Is(err, ErrConflict) {
		t.Fatalf("update must check match and room together: %v", err)
	}
	if err := store.Delete(ctx, first.MatchID, 1); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale delete succeeded: %v", err)
	}
	fingerprint := sha256.Sum256([]byte("command-1:hu"))
	failure := errors.New("history write failed")
	writeHistory := func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `INSERT INTO test_mahjong_completions VALUES ($1)`, first.MatchID)
		return err
	}
	if err := store.Complete(ctx, first.MatchID, 2, fingerprint, func(ctx context.Context, tx pgx.Tx) error {
		if err := writeHistory(ctx, tx); err != nil {
			return err
		}
		return failure
	}); !errors.Is(err, failure) {
		t.Fatalf("completion must report callback failure: %v", err)
	}
	rows, err := NewService(db).List(ctx)
	if err != nil || len(rows) != 1 || rows[0].MatchID != first.MatchID || rows[0].RoomID != first.RoomID || rows[0].Revision != 2 || !rows[0].CommittedAt.Equal(updatedAt) {
		t.Fatalf("failed completion must leave the active revision available: rows=%d err=%v", len(rows), err)
	}
	var expected map[string]any
	if err := json.Unmarshal(rows[0].Payload, &expected); err != nil || expected["revision"] != float64(2) || expected["wall"].([]any)[0] != float64(3) {
		t.Fatal("private snapshot did not round-trip")
	}
	completing := make(chan struct{})
	finish := make(chan struct{})
	completion := make(chan error, 1)
	go func() {
		completion <- store.Complete(ctx, first.MatchID, 2, fingerprint, func(ctx context.Context, tx pgx.Tx) error {
			close(completing)
			<-finish
			return writeHistory(ctx, tx)
		})
	}()
	select {
	case <-completing:
	case <-ctx.Done():
		close(finish)
		t.Fatal("completion did not reach the history write")
	}
	insertion := make(chan error, 1)
	go func() { insertion <- store.Insert(ctx, first) }()
	close(finish)
	if err := <-completion; err != nil {
		t.Fatal(err)
	}
	if err := <-insertion; !errors.Is(err, ErrConflict) {
		t.Fatalf("a concurrent first-deal replay restored a terminal match: %v", err)
	}
	if err := store.Complete(ctx, first.MatchID, 2, fingerprint, writeHistory); err != nil {
		t.Fatalf("completion replay ran the callback or lost the receipt: %v", err)
	}
	different := sha256.Sum256([]byte("command-2:hu"))
	if err := store.Complete(ctx, first.MatchID, 2, different, writeHistory); !errors.Is(err, ErrConflict) {
		t.Fatalf("completion accepted a different result for the same revision: %v", err)
	}
	if err := store.Complete(ctx, first.MatchID, 1, fingerprint, writeHistory); !errors.Is(err, ErrConflict) {
		t.Fatalf("completion accepted a stale revision: %v", err)
	}
	legacyID := uuid.NewString()
	if _, err := db.Exec(ctx, `INSERT INTO mahjong_active_completions (match_id,revision) VALUES ($1,1)`, legacyID); err != nil {
		t.Fatal(err)
	}
	if err := store.Complete(ctx, legacyID, 1, [32]byte{}, writeHistory); !errors.Is(err, ErrConflict) {
		t.Fatalf("unverifiable legacy completion confirmed a replay: %v", err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO mahjong_active_completions (match_id,revision,fingerprint) VALUES ($1,1,$2)`, uuid.NewString(), []byte{1}); err == nil {
		t.Fatal("database accepted a malformed fingerprint")
	}
	if err := store.Insert(ctx, first); !errors.Is(err, ErrConflict) {
		t.Fatalf("a completed match was reinserted: %v", err)
	}
	if err := store.Insert(ctx, Snapshot{MatchID: "invalid", RoomID: "5923", Revision: 1, Payload: json.RawMessage(`[123]`)}); err == nil {
		t.Fatal("non-object recovery payload was accepted")
	}
	if err := store.Insert(ctx, second); err != nil {
		t.Fatalf("completion did not release the room: %v", err)
	}
	if err := store.Delete(ctx, second.MatchID, 1); err != nil {
		t.Fatal(err)
	}
	legacySnapshot := Snapshot{MatchID: uuid.NewString(), RoomID: uuid.NewString(), Revision: 1, Payload: json.RawMessage(`{"legacy":true}`)}
	if _, err := db.Exec(ctx, `INSERT INTO mahjong_active_matches (match_id,room_id,revision,payload) VALUES ($1,$2,$3,$4)`, legacySnapshot.MatchID, legacySnapshot.RoomID, legacySnapshot.Revision, legacySnapshot.Payload); err != nil {
		t.Fatal(err)
	}
	if stamp, err := store.CommittedAt(ctx, legacySnapshot); err != nil || !stamp.IsZero() {
		t.Fatalf("legacy snapshot should not gain a fabricated timestamp: %v %v", stamp, err)
	}
	if rows, err := store.List(ctx); err != nil || len(rows) != 1 || !rows[0].CommittedAt.IsZero() {
		t.Fatalf("startup must accept SQL NULL timestamps: rows=%d err=%v", len(rows), err)
	}
	if err := store.Delete(ctx, legacySnapshot.MatchID, 1); err != nil {
		t.Fatal(err)
	}
	rows, err = store.List(ctx)
	if err != nil || len(rows) != 0 {
		t.Fatalf("startup list returned already removed state: rows=%d err=%v", len(rows), err)
	}
}
