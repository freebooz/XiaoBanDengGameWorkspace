package mahjongmoderation

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/google/uuid"
)

func TestTableReviewPersistsOneAtomicDisposition(t *testing.T) {
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
	s := NewService(db)
	r := Report{MatchID: uuid.NewString(), RoomID: "4321", ReporterAccountID: reporter.AccountID, TargetAccountID: target.AccountID, ReporterSeat: 0, TargetSeat: 1, Reason: "spam"}
	if err := s.Save(ctx, r); err != nil {
		t.Fatal(err)
	}
	pending, total, err := s.ListReviews(ctx, StatusPending, 1, 0)
	if err != nil || total < 1 || len(pending) != 1 || pending[0].MatchID != r.MatchID || pending[0].ID == "" || pending[0].ReviewedAt != nil || pending[0].Analyst != "" || pending[0].Note != "" {
		t.Fatalf("new report should await review: rows=%d total=%d err=%v", len(pending), total, err)
	}
	id := pending[0].ID
	if _, err := s.Resolve(ctx, id, "analyst-a", StatusUpheld, "https://example.test/secret"); !errors.Is(err, ErrInvalidReview) {
		t.Fatalf("invalid note was accepted: %v", err)
	}
	type attempt struct {
		actor, status, note string
		review              Review
		err                 error
	}
	start := make(chan struct{})
	outcomes := make(chan attempt, 2)
	for _, a := range []attempt{{actor: "analyst-a", status: StatusUpheld, note: "重复刷屏。"}, {actor: "analyst-b", status: StatusDismissed, note: "依据不足。"}} {
		go func() {
			<-start
			a.review, a.err = s.Resolve(ctx, id, a.actor, a.status, a.note)
			outcomes <- a
		}()
	}
	close(start)
	first, second := <-outcomes, <-outcomes
	if first.err != nil {
		first, second = second, first
	}
	if first.err != nil || !errors.Is(second.err, ErrConflict) || first.review.ID != id || first.review.Status != first.status || first.review.Analyst != first.actor || first.review.ReviewedAt == nil || first.review.Note != first.note {
		t.Fatalf("concurrent dispositions did not select one winner: %v %v", first.err, second.err)
	}
	if again, err := s.Resolve(ctx, id, first.actor, first.status, first.note); err != nil || again.ReviewedAt == nil || !again.ReviewedAt.Equal(*first.review.ReviewedAt) {
		t.Fatalf("identical retry did not return the committed review: %v", err)
	}
	if _, err := s.Resolve(ctx, id, first.actor, first.status, "修改后的原因"); !errors.Is(err, ErrConflict) {
		t.Fatalf("same analyst changed final note: %v", err)
	}
	var rows int
	var before, after, beforeNote, afterNote, actor string
	if err := db.QueryRow(ctx, `SELECT count(*),min(status_before),min(status_after),min(note_before),min(note_after),min(analyst)
		FROM mahjong_table_report_reviews WHERE report_id=$1`, id).Scan(&rows, &before, &after, &beforeNote, &afterNote, &actor); err != nil || rows != 1 || before != StatusPending || after != first.status || beforeNote != "" || afterNote != first.note || actor != first.actor {
		t.Fatalf("disposition did not leave one correct audit row: count=%d %v", rows, err)
	}
	if empty, count, err := s.ListReviews(ctx, first.status, 1, 10000); err != nil || len(empty) != 0 || count < 1 {
		t.Fatalf("empty page should retain filtered total: rows=%d count=%d %v", len(empty), count, err)
	}
	if _, err := s.Resolve(ctx, uuid.NewString(), "analyst-a", StatusUpheld, ""); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing review must return not found: %v", err)
	}
}
