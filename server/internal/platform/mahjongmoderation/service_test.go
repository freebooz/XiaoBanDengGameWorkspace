package mahjongmoderation

import (
	"context"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/google/uuid"
)

func TestTableReportsPersistOncePerPair(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_MODERATION_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated moderation database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	guest := account.NewService(db)
	reporter, err := guest.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	target, err := guest.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	store := NewService(db)
	first := Report{MatchID: uuid.NewString(), RoomID: "4321", ReporterAccountID: reporter.AccountID,
		TargetAccountID: target.AccountID, ReporterSeat: 2, TargetSeat: 3, Reason: "voice_abuse"}
	if err := store.Save(ctx, first); err != nil {
		t.Fatal(err)
	}
	var group sync.WaitGroup
	failures := make(chan error, 4)
	for range 4 {
		group.Add(1)
		go func() {
			defer group.Done()
			retry := first
			retry.Reason = "spam"
			failures <- store.Save(ctx, retry)
		}()
	}
	group.Wait()
	close(failures)
	for err := range failures {
		if err != nil {
			t.Fatal(err)
		}
	}
	reports, err := NewService(db).List(ctx, 100)
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	for _, item := range reports {
		if item.MatchID == first.MatchID {
			count++
			if item.Reason != first.Reason || item.ReporterAccountID != first.ReporterAccountID || item.TargetAccountID != first.TargetAccountID || item.RoomID != first.RoomID || item.ReporterSeat != first.ReporterSeat || item.TargetSeat != first.TargetSeat || item.CreatedAt.IsZero() {
				t.Fatal("stored audit did not preserve the first submitted reason and authoritative seats")
			}
		}
	}
	if count != 1 {
		t.Fatalf("wanted one report after repeated saves, got %d", count)
	}
	first.TargetSeat = first.ReporterSeat
	if err := store.Save(ctx, first); err == nil {
		t.Fatal("storage accepted a self-report")
	}
}
