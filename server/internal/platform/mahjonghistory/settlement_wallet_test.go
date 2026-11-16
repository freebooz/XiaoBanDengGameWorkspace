package mahjonghistory

import (
	"context"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
)

func TestSettlementEggsCommitOnceWithHistory(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_HISTORY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated settlement database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	var players [4]string
	for seat := range players {
		guest, err := account.NewService(db).CreateGuest(ctx)
		if err != nil {
			t.Fatal(err)
		}
		players[seat] = guest.AccountID
	}
	rule, err := guiyang.ResolveRuleDescriptor("guiyang", "2.0.0", nil)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	result := Result{MatchID: uuid.NewString(), RoomID: "1234", Kind: "friend", Rule: rule,
		StartedAt: now.Add(-time.Minute), FinishedAt: now, Scores: [4]int{-100, 30, 0, 70},
		Winners: []int{1}, WinFrom: 0, WinKind: "dian_pao", Reason: "hu", Members: players}
	service := NewService(db)
	assertBalances := func(want [4]int64) {
		t.Helper()
		for seat, id := range players {
			got, err := wallet.NewService(db).GetFamilyBalance(ctx, id)
			if err != nil || got.Amount != want[seat] {
				t.Fatalf("seat %d eggs=%d want=%d err=%v", seat, got.Amount, want[seat], err)
			}
		}
	}
	// The wallet and history must both disappear if their outer transaction fails.
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.SaveTx(ctx, tx, result); err != nil {
		_ = tx.Rollback(ctx)
		t.Fatal(err)
	}
	if err := tx.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	assertBalances([4]int64{100, 100, 100, 100})
	var count int
	if err := db.QueryRow(ctx, `SELECT count(*) FROM wallet_ledger WHERE reference_id=$1`, result.MatchID).Scan(&count); err != nil || count != 0 {
		t.Fatalf("rolled-back settlement left ledger rows: %d %v", count, err)
	}
	if err := service.Save(ctx, result); err != nil {
		t.Fatal(err)
	}
	assertBalances([4]int64{0, 130, 100, 170})
	stored, err := service.GetOwn(ctx, players[0], result.MatchID)
	if err != nil || stored.EggDeltas == nil || *stored.EggDeltas != [4]int64{-100, 30, 0, 70} {
		t.Fatalf("history lacks actual egg deltas: %+v %v", stored.EggDeltas, err)
	}
	// Duplicate callers, including a lost-reply retry, must never pay twice.
	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for range 8 {
		wg.Add(1)
		go func() { defer wg.Done(); errs <- service.Save(ctx, result) }()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	assertBalances([4]int64{0, 130, 100, 170})
	var sum int64
	if err := db.QueryRow(ctx, `SELECT count(*),COALESCE(sum(delta),0) FROM wallet_ledger WHERE reference_id=$1 AND reason='mahjong_settlement_eggs'`, result.MatchID).Scan(&count, &sum); err != nil || count != 4 || sum != 0 {
		t.Fatalf("settlement ledger not four conserved, unique seat entries: count=%d sum=%d err=%v", count, sum, err)
	}
	// A later inconsistent replay preserves the first authoritative result.
	duplicate := result
	duplicate.Scores = [4]int{-200, 60, 0, 140}
	if err := service.Save(ctx, duplicate); err != nil {
		t.Fatal(err)
	}
	assertBalances([4]int64{0, 130, 100, 170})
	quick := result
	quick.MatchID = uuid.NewString()
	quick.Kind = "quick"
	quick.Scores = [4]int{2, -1, 0, -1}
	if err := service.Save(ctx, quick); err != nil {
		t.Fatal(err)
	}
	assertBalances([4]int64{2, 129, 100, 169})
	training := result
	training.MatchID = uuid.NewString()
	training.Kind = "training"
	training.Members = [4]string{players[0], "bot1", "bot2", "bot3"}
	if err := service.Save(ctx, training); err != nil {
		t.Fatal(err)
	}
	assertBalances([4]int64{2, 129, 100, 169})
	if err := db.QueryRow(ctx, `SELECT count(*) FROM wallet_ledger WHERE reference_id=$1`, training.MatchID).Scan(&count); err != nil || count != 0 {
		t.Fatal("training changed real eggs")
	}
	for _, tc := range []struct {
		name     string
		balances [4]int64
		scores   [4]int
		want     [4]int64
	}{
		{"underfunded proportional", [4]int64{100, 100, 100, 100}, [4]int{-500, 101, 100, 299}, [4]int64{-100, 20, 20, 60}},
		{"equal remainder seat order", [4]int64{100, 100, 100, 100}, [4]int{-300, 100, 100, 100}, [4]int64{-100, 34, 33, 33}},
		{"empty loser", [4]int64{0, 100, 100, 100}, [4]int{-8, 8, 0, 0}, [4]int64{0, 0, 0, 0}},
		{"two losers", [4]int64{1, 2, 100, 100}, [4]int{-9, -11, 13, 7}, [4]int64{-1, -2, 2, 1}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for seat, id := range players {
				if _, err := db.Exec(ctx, `UPDATE wallet_accounts SET balance=$2 WHERE account_id=$1 AND asset_id='xbd_egg' AND scope='family'`, id, tc.balances[seat]); err != nil {
					t.Fatal(err)
				}
			}
			item := result
			item.MatchID = uuid.NewString()
			item.Scores = tc.scores
			if err := service.Save(ctx, item); err != nil {
				t.Fatal(err)
			}
			deltas, err := service.EggDeltas(ctx, item.MatchID)
			if err != nil || deltas == nil || *deltas != tc.want {
				t.Fatalf("actual deltas=%v want=%v err=%v", deltas, tc.want, err)
			}
			var want [4]int64
			for seat := range want {
				want[seat] = tc.balances[seat] + tc.want[seat]
			}
			assertBalances(want)
		})
	}
	// A grant concurrent with settlement is serialized by the wallet row locks.
	var displayName string
	if err := db.QueryRow(ctx, `SELECT display_name FROM accounts WHERE account_id=$1`, players[0]).Scan(&displayName); err != nil {
		t.Fatal(err)
	}
	item := result
	item.MatchID = uuid.NewString()
	item.Scores = [4]int{-300, 100, 100, 100}
	before := [4]int64{}
	for seat, id := range players {
		b, err := wallet.NewService(db).GetFamilyBalance(ctx, id)
		if err != nil {
			t.Fatal(err)
		}
		before[seat] = b.Amount
	}
	start := make(chan struct{})
	errs = make(chan error, 2)
	go func() { <-start; errs <- service.Save(ctx, item) }()
	go func() {
		<-start
		_, err := wallet.NewService(db).GrantEggs(ctx, "test-operator", wallet.EggGrant{DisplayName: displayName, Amount: 25, RequestID: uuid.New()})
		errs <- err
	}()
	close(start)
	for range 2 {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
	}
	deltas, err := service.EggDeltas(ctx, item.MatchID)
	if err != nil || deltas == nil {
		t.Fatal("missing concurrent settlement receipt")
	}
	want := before
	for seat := range want {
		want[seat] += deltas[seat]
	}
	want[0] += 25
	assertBalances(want)
	// Simulate a pre-wallet release's immutable history (no settlement postings).
	// Saving/recovering it must not retroactively charge players.
	legacy := result
	legacy.MatchID = uuid.NewString()
	legacy.Scores = [4]int{0, 0, 0, 0}
	if err := service.Save(ctx, legacy); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `DELETE FROM wallet_ledger WHERE reference_id=$1 AND reason='mahjong_settlement_eggs'`, legacy.MatchID); err != nil {
		t.Fatal(err)
	}
	legacy.Scores = [4]int{-300, 100, 100, 100}
	if err := service.Save(ctx, legacy); err != nil {
		t.Fatal(err)
	}
	assertBalances(want)
	if deltas, err := service.EggDeltas(ctx, legacy.MatchID); err != nil || deltas != nil {
		t.Fatal("legacy history was retroactively paid")
	}
}
