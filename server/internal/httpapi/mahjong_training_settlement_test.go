package httpapi

import (
	"context"
	"errors"
	"net/http/httptest"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/jackc/pgx/v5"
)

func TestMahjongTrainingSettlementWaitsForDatabase(t *testing.T) {
	databaseURL := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if databaseURL == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	upstream, err := url.Parse(databaseURL)
	if err != nil || (upstream.Scheme != "postgres" && upstream.Scheme != "postgresql") ||
		!restartLoopback(upstream.Host) || upstream.RawQuery != "sslmode=disable" {
		t.Fatal("requires a disposable numeric loopback PostgreSQL URL with sslmode=disable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal("isolated settlement database unavailable")
	}
	t.Cleanup(db.Close)
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}

	proxy := newMahjongOutageProxy(t, upstream.Host)
	upstream.Host = proxy.listener.Addr().String()
	apiDB, err := postgres.Connect(ctx, upstream.String())
	if err != nil {
		t.Fatal("isolated API database proxy unavailable")
	}
	t.Cleanup(apiDB.Close)
	s := buildServer(config.Config{}, apiDB, nil, account.NewService(apiDB))
	s.mahjong.checkpoints = mahjongactive.NewService(apiDB)
	runtime := &Runtime{Handler: s.routes(), server: s}
	endpoint := httptest.NewServer(runtime)
	t.Cleanup(endpoint.Close)
	t.Cleanup(runtime.Drain)
	owner := loadRestartGuest(t, endpoint.URL, "")
	outsider := loadRestartGuest(t, endpoint.URL, "")
	lobby := subscribeFriendRestartLobby(t, endpoint.URL, owner)
	lobbyState(t, lobby, "idle", 0, 0)
	lobbyCommand(t, lobby, "training", "", "basic_108", "1.0.0", true)
	roomID := lobbyState(t, lobby, "playing", 4, 4)["room_id"].(string)
	board := joinRestartBoard(t, endpoint.URL, owner, roomID, "", 0)
	initial := lobbyRead(t, board, "mahjong_state", nil)
	matchID := initial["match_id"].(string)

	// Use real turns and passes to reach a final discard where only seat zero
	// still has to pass. Avoid waiting for the entire round's live bot timers.
	s.mahjong.mu.Lock()
	r := s.mahjong.rooms[roomID]
	s.mahjong.mu.Unlock()
	r.mu.Lock()
	prepared := prepareTrainingFinalPass(t, r)
	r.mu.Unlock()
	if !prepared {
		t.Fatal("fixture did not reach the training player's final pass")
	}
	initial = lobbyRead(t, board, "mahjong_state", func(msg map[string]any) bool {
		return msg["phase"] == guiyang.PhaseReaction && msg["remaining"] == float64(0)
	})

	if proxy.pause() == 0 {
		t.Fatal("fixture did not interrupt an API database connection")
	}
	command := restartAction(roomID, matchID, "training-final-pass", "pass", nil)
	referenceSend(t, board, command)
	saving := lobbyRead(t, board, "mahjong_state", func(msg map[string]any) bool {
		return msg["saving"] == true || msg["status"] == "finished"
	})
	if saving["status"] == "finished" {
		t.Fatal("training broadcast a finished round while its database was disconnected")
	}
	checkMahjongSavingSnapshot(t, saving, initial, 0)
	history := mahjonghistory.NewService(db)
	if _, err := history.GetOwn(ctx, owner.ID, matchID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("read through the uninterrupted database connection: %v", err)
	}

	proxy.resume()
	waitRestartAction(t, board, "training-final-pass")
	finished := lobbyRead(t, board, "mahjong_state", func(msg map[string]any) bool {
		return msg["status"] == "finished"
	})
	if finished["reason"] != "wall_exhausted" || finished["saving"] == true || finished["egg_deltas"] != nil {
		t.Fatalf("unexpected training settlement: reason=%v saving=%v eggs=%v", finished["reason"], finished["saving"], finished["egg_deltas"])
	}
	referenceSend(t, board, command)
	waitRestartAction(t, board, "training-final-pass")
	item, err := history.GetOwn(ctx, owner.ID, matchID)
	if err != nil || item.Kind != "training" || item.RoomID != roomID || item.YourSeat != 0 ||
		item.Reason != "wall_exhausted" || item.EggDeltas != nil {
		t.Fatalf("owner could not read the committed training history: %+v, %v", item, err)
	}
	if _, err := history.GetOwn(ctx, outsider.ID, matchID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("non-member read the result: %v", err)
	}
	var members, ledger int
	err = db.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM mahjong_match_members JOIN mahjong_match_results USING (match_id) WHERE public_match_id=$1),
		(SELECT count(*) FROM wallet_ledger WHERE reference_id=$1)`, matchID).Scan(&members, &ledger)
	if err != nil || members != 1 || ledger != 0 {
		t.Fatalf("training persistence has %d members and %d wallet entries: %v", members, ledger, err)
	}
}

func prepareTrainingFinalPass(t *testing.T, r *mahjongRoom) bool {
	t.Helper()
	for seed := int64(1); seed <= 40; seed++ {
		game := guiyang.NewGameWithRules(r.game.Players, seed, r.rule.RuleSet())
		for step := 0; step < 150 && game.Phase != guiyang.PhaseFinished; step++ {
			if game.Remaining() == 0 && game.Phase == guiyang.PhaseReaction && len(game.Options(0)) > 0 {
				for seat := 1; seat < 4; seat++ {
					if len(game.Options(seat)) > 0 {
						if err := game.Apply(seat, "pass", 0); err != nil {
							t.Error(err)
							return false
						}
					}
				}
				r.timer.Stop()
				r.game = game
				r.broadcastLocked()
				return true
			}
			game.Timeout()
		}
	}
	return false
}
