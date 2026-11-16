package mahjongrooms

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestFriendRoomPersistenceCAS(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_ROOMS_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated friend room database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	rooms := NewService(db)
	room := Snapshot{RoomID: uuid.NewString(), CreatedAt: time.Unix(1711111111, 123456789).UTC(), Revision: 1, Payload: json.RawMessage(`{"members":["host"],"completed_rounds":0}`)}
	if err := rooms.Save(ctx, room); err != nil {
		t.Fatal(err)
	}
	if err := rooms.Save(ctx, room); err != nil {
		t.Fatalf("identical initial snapshot should be replayable: %v", err)
	}
	advance := room
	advance.Revision++
	advance.Payload = json.RawMessage(`{"members":["host","guest"],"completed_rounds":1}`)
	rollback := errors.New("abort settlement")
	if err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		if err := rooms.SaveTx(ctx, tx, advance); err != nil {
			return err
		}
		return rollback
	}); !errors.Is(err, rollback) {
		t.Fatalf("failed transaction did not report original error: %v", err)
	}
	read, err := NewService(db).Load(ctx, room.RoomID)
	if err != nil || read.Revision != 1 || !read.CreatedAt.Equal(room.CreatedAt) {
		t.Fatalf("rollback did not preserve revision and nanosecond generation: %v, %v", read.Revision, err)
	}
	if err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error { return rooms.SaveTx(ctx, tx, advance) }); err != nil {
		t.Fatal(err)
	}
	replay := advance
	replay.Payload = json.RawMessage(`{ "completed_rounds":1, "members":["host","guest"] }`)
	if err := rooms.Save(ctx, replay); err != nil {
		t.Fatalf("same JSONB state must be replayable: %v", err)
	}
	replay.Payload = room.Payload
	if err := rooms.Save(ctx, replay); !errors.Is(err, ErrConflict) {
		t.Fatalf("different same-revision payload was accepted: %v", err)
	}
	if err := rooms.Delete(ctx, room.RoomID, room.CreatedAt, room.Revision); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale deletion was accepted: %v", err)
	}
	rows, err := rooms.List(ctx)
	if err != nil || len(rows) != 1 || rows[0].Revision != 2 || rows[0].RoomID != room.RoomID {
		t.Fatalf("startup list did not return current room: rows=%d err=%v", len(rows), err)
	}
	if err := rooms.Delete(ctx, room.RoomID, room.CreatedAt, advance.Revision); err != nil {
		t.Fatal(err)
	}
	if err := rooms.Delete(ctx, room.RoomID, room.CreatedAt, advance.Revision); err != nil {
		t.Fatalf("an already absent room must allow a delete replay: %v", err)
	}
	if _, err := rooms.Load(ctx, room.RoomID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("closed room still loads: %v", err)
	}
	replacement := room
	replacement.CreatedAt = room.CreatedAt.Add(time.Nanosecond)
	if err := rooms.Save(ctx, replacement); err != nil {
		t.Fatal(err)
	}
	if err := rooms.Delete(ctx, room.RoomID, room.CreatedAt, room.Revision); !errors.Is(err, ErrConflict) {
		t.Fatalf("previous room generation deleted its replacement: %v", err)
	}
	if err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		return rooms.DeleteTx(ctx, tx, room.RoomID, replacement.CreatedAt, replacement.Revision)
	}); err != nil {
		t.Fatal(err)
	}
}
