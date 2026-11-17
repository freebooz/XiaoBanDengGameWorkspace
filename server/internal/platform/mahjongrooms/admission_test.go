package mahjongrooms

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestFriendRoomAdmissionOperationCommitsAtomically(t *testing.T) {
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
	store := NewService(db)
	waiting := Snapshot{
		RoomID: uuid.NewString(), CreatedAt: time.Unix(1711111111, 123456789).UTC(), Revision: 1,
		Payload: json.RawMessage(`{"Settings":{}}`),
	}
	if err := store.Save(ctx, waiting); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_, _ = db.Exec(ctx, `DELETE FROM mahjong_friend_rooms WHERE room_id=$1`, waiting.RoomID)
		_, _ = db.Exec(ctx, `DELETE FROM mahjong_room_admission_operations WHERE room_id=$1`, waiting.RoomID)
	}()

	change := AdmissionChange{
		RequestID: uuid.New(), RoomID: waiting.RoomID, RoomGeneration: waiting.CreatedAt,
		Paused: true, Reason: "暂停以处理举报", AdminName: "operator",
	}
	paused := waiting
	paused.Revision = 2
	paused.Payload = json.RawMessage(`{"Settings":{"admission_paused":true,"admission_revision":1}}`)
	stale := paused
	stale.Revision = 3
	if _, err := store.CommitAdmission(ctx, change, stale); !errors.Is(err, ErrConflict) {
		t.Fatalf("generation-matching snapshot with a stale predecessor returned %v", err)
	}
	if _, err := store.FindAdmissionOperation(ctx, change.RequestID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("failed snapshot left an audit receipt: %v", err)
	}
	if read, err := store.Load(ctx, waiting.RoomID); err != nil || read.Revision != 1 {
		t.Fatalf("failed operation changed room: %+v, %v", read, err)
	}

	receipt, err := store.CommitAdmission(ctx, change, paused)
	if err != nil || !receipt.Matches(change) || receipt.AdmissionRevision != 1 || receipt.CreatedAt.IsZero() {
		t.Fatalf("first operation returned wrong receipt: %+v, %v", receipt, err)
	}
	if read, err := store.Load(ctx, waiting.RoomID); err != nil || read.Revision != 2 || !read.CreatedAt.Equal(waiting.CreatedAt) {
		t.Fatalf("committed operation lost its matching snapshot: %+v, %v", read, err)
	}
	if saved, err := store.FindAdmissionOperation(ctx, change.RequestID); err != nil || saved != receipt {
		t.Fatalf("stored receipt differs from original: %+v, %v", saved, err)
	}

	resume := change
	resume.RequestID, resume.ExpectedRevision, resume.Paused = uuid.New(), 1, false
	latest := waiting
	latest.Revision = 3
	latest.Payload = json.RawMessage(`{"Settings":{"admission_revision":2}}`)
	second, err := store.CommitAdmission(ctx, resume, latest)
	if err != nil || second.AdmissionRevision != 2 {
		t.Fatalf("resuming admission failed: %+v, %v", second, err)
	}
	retry, err := store.CommitAdmission(ctx, change, paused)
	if err != nil || retry != receipt {
		t.Fatalf("retry after a newer operation did not return the original receipt: %+v, %v", retry, err)
	}
	conflicting := change
	conflicting.AdminName = "another-operator"
	if _, err := store.CommitAdmission(ctx, conflicting, paused); !errors.Is(err, ErrConflict) {
		t.Fatalf("another operator replayed the request ID: %v", err)
	}
	if read, err := store.Load(ctx, waiting.RoomID); err != nil || read.Revision != 3 {
		t.Fatalf("retry rewrote a newer snapshot: %+v, %v", read, err)
	}

	if err := store.Delete(ctx, waiting.RoomID, waiting.CreatedAt, latest.Revision); err != nil {
		t.Fatal(err)
	}
	replacement := waiting
	replacement.CreatedAt = waiting.CreatedAt.Add(time.Nanosecond)
	if err := store.Save(ctx, replacement); err != nil {
		t.Fatal(err)
	}
	old, err := store.ListAdmissionOperations(ctx, waiting.RoomID, waiting.CreatedAt)
	if err != nil || !reflect.DeepEqual(old, []AdmissionOperation{second, receipt}) {
		t.Fatalf("old generation lost immutable history: %+v, %v", old, err)
	}
	current, err := store.ListAdmissionOperations(ctx, replacement.RoomID, replacement.CreatedAt)
	if err != nil || current == nil || len(current) != 0 {
		t.Fatalf("replacement inherited old generation operations: %+v, %v", current, err)
	}
}
