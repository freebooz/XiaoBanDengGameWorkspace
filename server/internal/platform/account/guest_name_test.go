package account

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestConcurrentGuestLoginsAssignUniqueChineseNames(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated account database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	legacyID := uuid.New()
	const legacyName = "游客-legacy01"
	if _, err := db.Exec(ctx, `INSERT INTO accounts (account_id,display_name) VALUES ($1,$2)`, legacyID, legacyName); err != nil {
		t.Fatal(err)
	}
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	service := NewService(db)
	const loginCount = 64
	type result struct {
		login GuestLogin
		err   error
	}
	results := make(chan result, loginCount)
	for range loginCount {
		go func() {
			login, err := service.CreateGuest(ctx)
			results <- result{login, err}
		}()
	}
	names := make(map[string]bool, loginCount)
	for range loginCount {
		item := <-results
		if item.err != nil {
			t.Fatal(item.err)
		}
		name := item.login.DisplayName
		if utf8.RuneCountInString(name) != 4 || names[name] {
			t.Fatalf("invalid or duplicate guest name %q", name)
		}
		for _, character := range name {
			if !unicode.Is(unicode.Han, character) {
				t.Fatalf("guest name must contain only four Chinese characters: %q", name)
			}
		}
		nickname := []rune(name)[2:]
		if !strings.ContainsRune("阿老幺大小二三四春冬杏桂桃麦豆石山福田金银牛兰玉翠", nickname[0]) &&
			!strings.ContainsRune("叔婶嫂哥姐伯姨婆爷", nickname[1]) {
			t.Fatalf("missing a village-style nickname in %q", name)
		}
		names[name] = true
		session, err := service.Session(ctx, item.login.Token)
		if err != nil || session.AccountID != item.login.AccountID || session.DisplayName != name {
			t.Fatalf("session did not retain the assigned identity: %v", err)
		}
	}
	var displayName string
	if err := db.QueryRow(ctx, `SELECT display_name FROM accounts WHERE account_id=$1`, legacyID).Scan(&displayName); err != nil || displayName != legacyName {
		t.Fatalf("migration changed an existing account: %q, %v", displayName, err)
	}
}

func TestGuestDefaultNameReservationSurvivesRenamingAndSkipsExistingNames(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated account database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	service := NewService(db)
	guest, err := service.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.RequestDeletion(ctx, guest.AccountID); err != nil {
		t.Fatal(err)
	}
	const legacyChineseName = "春山听雨"
	if err := pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO accounts (account_id,display_name) VALUES ($1,$2)`, uuid.New(), legacyChineseName); err != nil {
			return err
		}
		for _, name := range []string{guest.DisplayName, legacyChineseName} {
			reserved, err := reserveGuestDefaultName(ctx, tx, name)
			if err != nil {
				return err
			}
			if reserved {
				t.Errorf("previously assigned nickname %q was reused", name)
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
