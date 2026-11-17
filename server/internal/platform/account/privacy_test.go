package account

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/google/uuid"
)

func TestGuestPrivacyRevokesOnlyOwnedSessionsAndRetainsEvidence(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated privacy database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	s := NewService(db)
	guest, err := s.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	other, err := s.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	guestID := uuid.MustParse(guest.AccountID)
	var secondSecret [32]byte
	if _, err := rand.Read(secondSecret[:]); err != nil {
		t.Fatal(err)
	}
	secondHash := sha256.Sum256(secondSecret[:])
	second := base64.RawURLEncoding.EncodeToString(secondSecret[:])
	if _, err := db.Exec(ctx, `INSERT INTO account_sessions(token_hash,account_id,expires_at) VALUES($1,$2,clock_timestamp()+interval '1 day')`, secondHash[:], guestID); err != nil {
		t.Fatal(err)
	}
	if err := s.RevokeSession(ctx, guest.Token); err != nil {
		t.Fatal(err)
	}
	if err := s.RevokeSession(ctx, guest.Token); !errors.Is(err, ErrInvalidSession) {
		t.Fatal("logout accepted an already revoked credential")
	}
	if _, err := s.Session(ctx, second); err != nil {
		t.Fatal("logout revoked a different session")
	}
	if _, err := db.Exec(ctx, `INSERT INTO wallet_accounts(account_id,asset_id,scope) VALUES ($1,'coin','test')`, guestID); err != nil {
		t.Fatal(err)
	}
	first, err := s.RequestDeletion(ctx, guest.AccountID)
	if err != nil || first.RequestID == "" || first.AccountID != guest.AccountID || first.Status != "pending_retention_review" || first.RequestedAt.IsZero() {
		t.Fatalf("missing valid pending deletion receipt: %v", err)
	}
	again, err := s.RequestDeletion(ctx, guest.AccountID)
	if err != nil || again != first {
		t.Fatalf("second request changed the original audit: %v", err)
	}
	if _, err := s.Session(ctx, second); !errors.Is(err, ErrInvalidSession) {
		t.Fatal("deactivated account's second session still resolves")
	}
	if _, err := s.Session(ctx, other.Token); err != nil {
		t.Fatal("deactivation changed another account")
	}
	var name, status string
	var sessions, walletRows int
	if err := db.QueryRow(ctx, `SELECT display_name,status,(SELECT COUNT(*) FROM account_sessions WHERE account_id=$1),
		(SELECT COUNT(*) FROM wallet_accounts WHERE account_id=$1) FROM accounts WHERE account_id=$1`, guestID).Scan(&name, &status, &sessions, &walletRows); err != nil || name != "已停用游客" || status != "deactivated" || sessions != 0 || walletRows != 2 {
		t.Fatalf("deactivation must anonymize, revoke, and preserve referring rows: status=%s sessions=%d wallet=%d err=%v", status, sessions, walletRows, err)
	}
	if _, err := db.Exec(ctx, `UPDATE accounts SET account_type='registered' WHERE account_id=$1`, uuid.MustParse(other.AccountID)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.RequestDeletion(ctx, other.AccountID); !errors.Is(err, ErrDeletionUnavailable) {
		t.Fatal("guest route accepted a non-guest account")
	}
	if _, err := s.Session(ctx, other.Token); err != nil {
		t.Fatal("non-guest rejection revoked its session")
	}
}
