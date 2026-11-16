package httpapi

import (
	"context"
	"errors"
	"net/http/httptest"
	"os"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
)

func TestMahjongSettlementPublishesCommittedWallets(t *testing.T) {
	for _, fault := range []string{"transaction_rollback", "committed_read_retry"} {
		t.Run(fault, func(t *testing.T) { checkSettlementWalletBroadcast(t, fault) })
	}
}

func checkSettlementWalletBroadcast(t *testing.T, fault string) {
	t.Helper()
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("isolated settlement database unavailable")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	accounts := account.NewService(db)
	s := buildServer(config.Config{}, db, nil, accounts)
	history := mahjonghistory.NewService(db)
	s.mahjong.checkpoints = mahjongactive.NewService(db)
	s.mahjong.friendStore = mahjongrooms.NewService(db)
	var fail atomic.Bool
	s.mahjong.saveHistory = func(ctx context.Context, tx pgx.Tx, result mahjonghistory.Result) error {
		if err := history.SaveTx(ctx, tx, result); err != nil {
			return err
		}
		if fault == "transaction_rollback" && fail.Load() {
			return errors.New("isolated injected pre-commit failure")
		}
		return nil
	}
	s.mahjong.seatWallets = func(ctx context.Context, ids []string) (map[string]wallet.EggProfile, error) {
		if fault == "committed_read_retry" && fail.Load() {
			return nil, errors.New("isolated injected committed read failure")
		}
		return s.wallets.GetFamilyEggProfiles(ctx, ids)
	}
	endpoint := httptest.NewServer(s.routes())
	defer endpoint.Close()
	defer func() {
		s.mahjong.stopping.Store(true)
		s.mahjong.mu.Lock()
		defer s.mahjong.mu.Unlock()
		for _, r := range s.mahjong.rooms {
			r.mu.Lock()
			if r.timer != nil {
				r.timer.Stop()
			}
			r.mu.Unlock()
		}
	}()
	var players [4]restartGuest
	var lobby [4]*websocket.Conn
	for seat := range players {
		guest, err := accounts.CreateGuest(ctx)
		if err != nil {
			t.Fatal(err)
		}
		players[seat] = restartGuest{ID: guest.AccountID, Token: guest.Token}
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint.URL, players[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	lobbyCommand(t, lobby[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for _, conn := range lobby[1:] {
		lobbyCommand(t, conn, "join", roomID, "", "", true)
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true, "requires_kong_to_claim": true, "rob_kong": true}
	board, initial, matchID := startFriendRestartRound(t, endpoint.URL, players, roomID, "", options)
	s.mahjong.mu.Lock()
	r := s.mahjong.rooms[roomID]
	s.mahjong.mu.Unlock()
	r.mu.Lock()
	next, err := r.copyForAction(s.mahjong)
	if err != nil {
		r.mu.Unlock()
		t.Fatal(err)
	}
	for step := 0; next.Phase != guiyang.PhaseFinished && step < 150; step++ {
		next.Timeout()
	}
	if next.Phase != guiyang.PhaseFinished {
		r.mu.Unlock()
		t.Fatal("fixture game did not finish")
	}
	// Isolate payment/publication behavior with an authoritative fixture result.
	// Rule scores stay intact even when only 100 of the 500 owed eggs exist.
	next.Scores = [4]int{-500, 101, 100, 299}
	next.ScoreBreakdown = &guiyang.ScoreBreakdown{Hu: next.Scores}
	fail.Store(true)
	r.commitLocked(s.mahjong, next, time.Now().UTC(), nil, mahjongCommand{}, func() {})
	r.mu.Unlock()
	for seat, conn := range board {
		saving := lobbyRead(t, conn, "mahjong_state", func(m map[string]any) bool { return m["saving"] == true })
		if saving["status"] == "finished" || saving["epoch"] != initial[seat]["epoch"] || !reflect.DeepEqual(saving["egg_counts"], []any{float64(100), float64(100), float64(100), float64(100)}) {
			t.Fatal("unconfirmed settlement was published")
		}
	}
	if fault == "transaction_rollback" {
		for _, p := range players {
			b, err := s.wallets.GetFamilyBalance(ctx, p.ID)
			if err != nil || b.Amount != 100 {
				t.Fatal("failed transaction changed wallet")
			}
		}
	}
	fail.Store(false)
	want := []any{float64(0), float64(120), float64(120), float64(160)}
	actual := []any{float64(-100), float64(20), float64(20), float64(60)}
	for _, conn := range board {
		state := lobbyRead(t, conn, "mahjong_state", func(m map[string]any) bool { return m["status"] == "finished" })
		if !reflect.DeepEqual(state["egg_counts"], want) || !reflect.DeepEqual(state["egg_deltas"], actual) {
			t.Fatalf("terminal state lacks committed balances/deltas: counts=%v deltas=%v", state["egg_counts"], state["egg_deltas"])
		}
	}
	var count int
	if err := db.QueryRow(ctx, `SELECT count(*) FROM wallet_ledger WHERE reference_id=$1 AND reason='mahjong_settlement_eggs'`, matchID).Scan(&count); err != nil || count != 4 {
		t.Fatalf("retry posted %d ledger rows: %v", count, err)
	}
	// Later grants must win over any historical after-balance on reconnect.
	var name string
	if err := db.QueryRow(ctx, `SELECT display_name FROM accounts WHERE account_id=$1`, players[0].ID).Scan(&name); err != nil {
		t.Fatal(err)
	}
	if _, err := s.wallets.GrantEggs(ctx, "test-operator", wallet.EggGrant{DisplayName: name, Amount: 30, RequestID: uuid.New()}); err != nil {
		t.Fatal(err)
	}
	s.mahjong.refreshWalletForPlayer(players[0].ID)
	want[0] = float64(30)
	for _, conn := range board {
		state := lobbyRead(t, conn, "mahjong_state", func(m map[string]any) bool { return reflect.DeepEqual(m["egg_counts"], want) })
		if !reflect.DeepEqual(state["egg_deltas"], actual) {
			t.Fatal("grant changed immutable hand delta")
		}
	}
	for seat, p := range players {
		conn := joinRestartBoard(t, endpoint.URL, p, roomID, matchID, seat)
		state := lobbyRead(t, conn, "mahjong_state", func(m map[string]any) bool { return m["status"] == "finished" })
		if !reflect.DeepEqual(state["egg_counts"], want) || !reflect.DeepEqual(state["egg_deltas"], actual) {
			t.Fatal("reconnect changed settled wallet projection")
		}
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	_, states, nextID := startFriendRestartRound(t, endpoint.URL, players, roomID, "", options)
	if nextID == matchID {
		t.Fatal("next hand reused match")
	}
	for _, state := range states {
		if !reflect.DeepEqual(state["egg_counts"], want) || state["egg_deltas"] != nil {
			t.Fatal("next hand has stale balance or previous hand delta")
		}
	}
}
