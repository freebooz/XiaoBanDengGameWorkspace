package account

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
)

func TestNewPlayerWelcomeEggsAndReturningBalances(t *testing.T) {
	databaseURL := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if databaseURL == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal("could not connect to isolated welcome wallet database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	accounts, wallets := NewService(db), wallet.NewService(db)
	for _, accountType := range []string{"guest", "registered"} {
		t.Run(accountType, func(t *testing.T) {
			username := "welcome_" + uuid.NewString()[:8]
			password := uuid.NewString()
			var login GuestLogin
			var err error
			if accountType == "guest" {
				login, err = accounts.CreateGuest(ctx)
			} else {
				login, err = accounts.Register(ctx, username, password)
			}
			if err != nil {
				t.Fatal(err)
			}
			assertWallet := func(amount, welcomeTotal int64) {
				t.Helper()
				balance, err := wallets.GetFamilyBalance(ctx, login.AccountID)
				if err != nil || balance.Amount != amount {
					t.Fatalf("wallet amount = %d, want %d (error: %v)", balance.Amount, amount, err)
				}
				var grants int
				var total int64
				if err := db.QueryRow(ctx, `SELECT count(*),COALESCE(sum(delta),0) FROM wallet_ledger
					WHERE account_id=$1 AND asset_id='xbd_egg' AND scope='family' AND reason='guest_welcome_eggs'`,
					login.AccountID).Scan(&grants, &total); err != nil || grants != 1 || total != welcomeTotal {
					t.Fatalf("welcome ledger = %d grants / %d eggs, want 1 / %d (error: %v)", grants, total, welcomeTotal, err)
				}
			}
			assertWallet(500, 500)
			for _, fixture := range []struct{ balance, welcome int64 }{{500, 500}, {37, 500}, {100, 100}} {
				// Simulate a spent balance and an account created under the former
				// 100-egg policy. Returning players must never be topped up/reset.
				if _, err := db.Exec(ctx, `UPDATE wallet_accounts SET balance=$2 WHERE account_id=$1 AND asset_id='xbd_egg' AND scope='family'`, login.AccountID, fixture.balance); err != nil {
					t.Fatal(err)
				}
				if _, err := db.Exec(ctx, `UPDATE wallet_ledger SET delta=$2 WHERE account_id=$1 AND reason='guest_welcome_eggs'`, login.AccountID, fixture.welcome); err != nil {
					t.Fatal(err)
				}
				for range 2 {
					if accountType == "registered" {
						repeated, err := accounts.Login(ctx, username, password)
						if err != nil || repeated.AccountID != login.AccountID {
							t.Fatalf("returning password login changed identity: %v", err)
						}
						login = repeated
					}
					session, err := accounts.Session(ctx, login.Token)
					if err != nil || session.AccountID != login.AccountID {
						t.Fatalf("returning session changed identity: %v", err)
					}
					assertWallet(fixture.balance, fixture.welcome)
				}
			}
		})
	}
}
