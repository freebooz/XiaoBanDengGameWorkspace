package mahjonghistory

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestHistoryPostgresPersistsOwnedResults(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_HISTORY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated history database")
	}
	if err := postgres.Migrate(ctx, db); err != nil {
		db.Close()
		t.Fatal(err)
	}
	var players [5]string
	for seat := range players {
		guest, err := account.NewService(db).CreateGuest(ctx)
		if err != nil {
			db.Close()
			t.Fatal(err)
		}
		players[seat] = guest.AccountID
	}
	options := guiyang.RuleOptions{Version: guiyang.RuleOptionsVersion, Chicken: true, BlackEight: true}
	rule, err := guiyang.ResolveRuleDescriptor("guiyang", "2.0.0", &options)
	if err != nil {
		db.Close()
		t.Fatal(err)
	}
	now := time.Now().UTC().Truncate(time.Microsecond)
	match := Result{MatchID: uuid.NewString(), RoomID: "1234", Kind: "friend", Rule: rule, StartedAt: now.Add(-time.Minute), FinishedAt: now,
		Scores: [4]int{-3, 0, 3, 0}, Winners: []int{2}, WinFrom: 0, WinKind: "dian_pao", Reason: "hu", Members: [4]string(players[:4])}
	match.Breakdown = &guiyang.ScoreBreakdown{Hu: [4]int{-3, 0, 3, 0}}
	training := Result{MatchID: uuid.NewString(), RoomID: "5678", Kind: "training", Rule: rule, StartedAt: now.Add(time.Minute), FinishedAt: now.Add(2 * time.Minute),
		Winners: []int{}, WinFrom: -1, Reason: "wall_exhausted", Members: [4]string{players[0], "电脑1", "电脑2", "电脑3"}}
	meldIndex := 0
	training.Replay = &guiyang.Replay{Version: guiyang.ReplayVersion, Dealer: 0, Events: []guiyang.ReplayEvent{
		{Sequence: 1, Seat: 0, Kind: "an_gang", Meld: &guiyang.Meld{Kind: "an_gang", Tiles: make([]guiyang.Tile, 4), FromSeat: 0}, MeldIndex: &meldIndex},
		{Sequence: 2, Seat: -1, Kind: "wall_exhausted"},
	}}
	rolledBack := match
	rolledBack.MatchID = uuid.NewString()
	rolledBack.Members[3] = uuid.NewString()
	service := NewService(db)
	invalid := training
	invalid.MatchID = uuid.NewString()
	invalid.Replay = &guiyang.Replay{Version: guiyang.ReplayVersion, Dealer: 0, Events: []guiyang.ReplayEvent{
		{Sequence: 1, Seat: 0, Kind: "an_gang", Meld: &guiyang.Meld{Kind: "an_gang", Tiles: []guiyang.Tile{{ID: 17, Suit: "wan", Rank: 5}, {}, {}, {}}, FromSeat: 0}, MeldIndex: &meldIndex},
		{Sequence: 2, Seat: -1, Kind: "wall_exhausted"},
	}}
	if err := service.Save(ctx, invalid); err == nil {
		db.Close()
		t.Fatal("replay included an exposed concealed tile")
	}
	if err := service.Save(ctx, rolledBack); err == nil {
		db.Close()
		t.Fatal("save accepted a nonexistent human seat")
	}
	for _, result := range []Result{match, training} {
		if err := service.Save(ctx, result); err != nil {
			db.Close()
			t.Fatal(err)
		}
	}
	duplicate := match
	duplicate.Scores = [4]int{-6, 0, 6, 0}
	if err := service.Save(ctx, duplicate); err == nil {
		db.Close()
		t.Fatal("nonmatching score breakdown was accepted")
	}
	duplicate.Breakdown = &guiyang.ScoreBreakdown{Hu: duplicate.Scores}
	if err := service.Save(ctx, duplicate); err != nil {
		db.Close()
		t.Fatal(err)
	}
	var partial int
	rolledBackKey := uuid.NewSHA1(uuid.NameSpaceURL, []byte("urn:xbd:mahjong:match:"+rolledBack.MatchID))
	if err := db.QueryRow(ctx, `SELECT COUNT(*) FROM game_matches WHERE match_id=$1`, rolledBackKey).Scan(&partial); err != nil || partial != 0 {
		db.Close()
		t.Fatalf("failed member write must roll back the parent and summary: count=%d err=%v", partial, err)
	}
	db.Close()

	reopened, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not reconnect to isolated history database")
	}
	defer reopened.Close()
	service = NewService(reopened)
	owner, err := service.ListOwn(ctx, players[0], 20)
	if err != nil || len(owner) != 2 || owner[0].MatchID != training.MatchID || owner[0].YourSeat != 0 || owner[0].Winners == nil || owner[0].Breakdown != nil || owner[1].MatchID != match.MatchID || owner[1].Rule != rule || owner[1].Scores != match.Scores || owner[1].Breakdown == nil || *owner[1].Breakdown != *match.Breakdown || !reflect.DeepEqual(owner[1].Winners, []int{2}) {
		t.Fatalf("reopened history did not return immutable results newest first: %+v err=%v", owner, err)
	}
	peer, err := service.ListOwn(ctx, players[2], 20)
	if err != nil || len(peer) != 1 || peer[0].YourSeat != 2 || peer[0].MatchID != match.MatchID {
		t.Fatalf("human peer history did not preserve its own seat: %+v err=%v", peer, err)
	}
	outsider, err := service.ListOwn(ctx, players[4], 20)
	if err != nil || len(outsider) != 0 {
		t.Fatalf("history exposed another account's result: %+v err=%v", outsider, err)
	}
	jsonPayload, err := json.Marshal(owner)
	if err != nil || strings.Contains(string(jsonPayload), players[2]) || strings.Contains(string(jsonPayload), `"replay"`) || owner[0].Replay != nil {
		t.Fatal("history response exposed another player's identity")
	}
	item, err := service.GetOwn(ctx, players[2], match.MatchID)
	if err != nil || item.MatchID != match.MatchID || item.YourSeat != 2 || item.Breakdown == nil || *item.Breakdown != *match.Breakdown {
		t.Fatalf("member detail did not expose persisted score details: %+v err=%v", item, err)
	}
	if _, err := service.GetOwn(ctx, players[4], match.MatchID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("non-member queried a match: %v", err)
	}
	replay, err := service.GetOwnReplay(ctx, players[0], training.MatchID)
	if err != nil || !reflect.DeepEqual(replay, *training.Replay) {
		t.Fatalf("original participant could not recover redacted replay: %v", err)
	}
	if _, err := service.GetOwnReplay(ctx, players[1], training.MatchID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("unrelated account accessed a replay: %v", err)
	}
	if _, err := service.GetOwnReplay(ctx, players[2], match.MatchID); !errors.Is(err, ErrReplayUnavailable) {
		t.Fatalf("legacy own summary did not report missing replay: %v", err)
	}
	tied := training
	tied.MatchID = uuid.NewString()
	if err := service.Save(ctx, tied); err != nil {
		t.Fatal(err)
	}
	ordered, err := service.ListOwn(ctx, players[0], 20)
	if err != nil || len(ordered) != 3 {
		t.Fatalf("could not find all history rows: %v", err)
	}
	cursor := ""
	for i := range ordered {
		page, err := service.ListOwnPage(ctx, players[0], 1, cursor)
		if err != nil || len(page.Matches) != 1 || page.Matches[0].MatchID != ordered[i].MatchID || (page.NextCursor == "") != (i == len(ordered)-1) {
			t.Fatalf("page %d skipped or repeated a match with tied finish times: %+v %v", i, page, err)
		}
		cursor = page.NextCursor
	}
	if _, err := service.ListOwnPage(ctx, players[0], 1, "bad"); !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("invalid cursor was accepted: %v", err)
	}
	malformed := historyCursor(now, historyMatchID(match.MatchID))
	malformed = malformed[:len(malformed)-2] + "\r\n" // base64 decoder skips CR and LF.
	if _, err := service.ListOwnPage(ctx, players[0], 1, malformed); !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("truncated cursor was accepted: %v", err)
	}
}
