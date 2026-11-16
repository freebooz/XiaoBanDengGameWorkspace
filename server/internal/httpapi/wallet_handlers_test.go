package httpapi

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
)

const eggGrantPath = "/api/v1/admin/wallet/eggs/grant"

func eggWalletToken(t *testing.T, name, capability string) (string, adminPrincipal) {
	t.Helper()
	var key [32]byte
	if _, err := rand.Read(key[:]); err != nil {
		t.Fatal("could not create an ephemeral admin credential")
	}
	token := base64.RawURLEncoding.EncodeToString(key[:])
	return token, adminPrincipal{Name: name, Capabilities: []string{capability}, digest: sha256.Sum256([]byte(token))}
}

func eggWalletRequest(handler http.Handler, method, path, token string, data any) *httptest.ResponseRecorder {
	content, _ := json.Marshal(data)
	request := httptest.NewRequest(method, path, bytes.NewReader(content))
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	reply := httptest.NewRecorder()
	handler.ServeHTTP(reply, request)
	return reply
}

func TestEggWalletRoutesRequireAdminCapabilityAndPlayerSession(t *testing.T) {
	adminToken, reader := eggWalletToken(t, "reader", adminPlatformRead)
	s := buildServer(config.Config{}, nil, nil, account.NewService(nil))
	s.adminPrincipals = []adminPrincipal{reader}
	handler := s.routes()
	if code := eggWalletRequest(handler, http.MethodGet, "/api/v1/wallet", "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("wallet without player session returned %d", code)
	}
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("grant without admin credentials returned %d", code)
	}
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, nil).Code; code != http.StatusForbidden {
		t.Fatalf("read-only admin grant returned %d", code)
	}
}

func TestEggWalletRegistrationAndAdminGrant(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated wallet database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	accounts := account.NewService(db)
	player, err := accounts.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	other, err := accounts.CreateGuest(ctx)
	if err != nil {
		t.Fatal(err)
	}
	oldAccount := uuid.NewString()
	if _, err := db.Exec(ctx, `INSERT INTO accounts(account_id, display_name) VALUES($1,$2)`, oldAccount, "以前玩家"+oldAccount); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO wallet_accounts(account_id, asset_id, scope, balance) VALUES($1,'xbd_point','family',250)`, oldAccount); err != nil {
		t.Fatal(err)
	}
	adminToken, operator := eggWalletToken(t, "egg-operator", adminGrantEggs)
	s := buildServer(config.Config{}, db, nil, accounts)
	s.adminPrincipals = []adminPrincipal{operator}
	handler := s.routes()
	assertBalance := func(token string, amount int64) {
		t.Helper()
		reply := eggWalletRequest(handler, http.MethodGet, "/api/v1/wallet", token, nil)
		var got wallet.Balance
		if reply.Code != http.StatusOK || json.Unmarshal(reply.Body.Bytes(), &got) != nil || got.AssetID != wallet.EggAssetID || got.Amount != amount || got.Scope != wallet.FamilyScope {
			t.Fatalf("wrong player egg balance for expected %d: status=%d, balance=%+v", amount, reply.Code, got)
		}
	}
	assertBalance(player.Token, 100)
	if code := eggWalletRequest(handler, http.MethodGet, "/api/v1/wallet?account_id="+other.AccountID, player.Token, nil).Code; code != http.StatusForbidden {
		t.Fatalf("another player's wallet returned %d", code)
	}
	if balance, err := s.wallets.GetFamilyBalance(ctx, oldAccount); err != nil || balance.Amount != 0 {
		t.Fatal("pre-existing account incorrectly received a welcome grant or converted coins")
	}
	grant := wallet.EggGrant{DisplayName: player.DisplayName, Amount: 25, RequestID: uuid.New()}
	results := make(chan *httptest.ResponseRecorder, 8)
	for range cap(results) {
		go func() { results <- eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, grant) }()
	}
	for range cap(results) {
		reply := <-results
		var granted wallet.EggGrantReceipt
		if reply.Code != http.StatusOK || json.Unmarshal(reply.Body.Bytes(), &granted) != nil || granted.Balance != 125 || granted.Amount != 25 ||
			granted.AccountID != player.AccountID || granted.DisplayName != player.DisplayName || granted.RequestID != grant.RequestID || granted.AssetID != wallet.EggAssetID {
			t.Fatalf("grant receipt incorrect: status=%d, receipt=%+v", reply.Code, granted)
		}
	}
	invalid := grant
	invalid.Amount = -1
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, invalid).Code; code != http.StatusBadRequest {
		t.Fatalf("negative grant returned %d", code)
	}
	invalid.Amount = 26
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, invalid).Code; code != http.StatusConflict {
		t.Fatalf("reused request with different amount returned %d", code)
	}
	invalid.RequestID = uuid.New()
	invalid.DisplayName = "不存在的昵称" + oldAccount
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, invalid).Code; code != http.StatusNotFound {
		t.Fatalf("missing exact nickname returned %d", code)
	}
	if _, err := db.Exec(ctx, `UPDATE accounts SET display_name=$2 WHERE account_id=$1`, other.AccountID, player.DisplayName); err != nil {
		t.Fatal(err)
	}
	invalid.DisplayName = player.DisplayName
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, invalid).Code; code != http.StatusConflict {
		t.Fatalf("ambiguous nickname returned %d", code)
	}
	assertBalance(player.Token, 125)
	assertBalance(other.Token, 100)
	var releases, welcomes int
	if err := db.QueryRow(ctx, `SELECT count(*) FILTER (WHERE reason='admin_egg_grant' AND performed_by=$2 AND target_display_name=$3),
		count(*) FILTER (WHERE reason='guest_welcome_eggs') FROM wallet_ledger WHERE account_id=$1`, player.AccountID, operator.Name, player.DisplayName).Scan(&releases, &welcomes); err != nil || releases != 1 || welcomes != 1 {
		t.Fatalf("wallet ledger should preserve one welcome and one audited grant: releases=%d welcomes=%d err=%v", releases, welcomes, err)
	}
}
