package guiyang

import (
	"bytes"
	"encoding/json"
	"reflect"
	"slices"
	"testing"
)

func TestGuiyangCannotDisableRequiredKongOrReuseStaleHu(t *testing.T) {
	options := RuleOptions{Version: RuleOptionsVersion, RobKong: true}
	rule, err := ResolveRuleDescriptor("guiyang", "2.0.0", &options)
	if err != nil {
		t.Fatal(err)
	}
	game := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
	game.Phase = PhaseReaction
	game.Candidates = map[int][]string{1: {"hu"}}
	game.Submitted = map[int]string{}
	game.PendingFrom, game.PendingKind = 0, "discard"
	if !rule.RequiresKongToClaim {
		t.Error("a legacy override disabled the Guiyang kong requirement")
	}
	if slices.Contains(game.Options(1), ActionOption{Type: "hu"}) {
		t.Error("stale candidates offered an illegal claim")
	}
	if err := game.Apply(1, "hu", 0); err == nil || len(game.Submitted) != 0 {
		t.Fatal("stale candidates accepted an illegal claim")
	}
	game.Submitted[1] = "hu"
	game = restartTrial(t, game)
	game.Timeout()
	if game.Phase == PhaseFinished || len(game.Winners) != 0 || game.Scores != [4]int{} {
		t.Fatal("restored submissions settled an illegal claim")
	}
}

func newTrialGame(t *testing.T, chicken bool, dealer int) *Game {
	t.Helper()
	options := RuleOptions{Version: "2.0.0", Chicken: chicken, RobKong: true}
	descriptor, err := ResolveRuleDescriptor("zunyi_dingque", "1.0.0", &options)
	if err != nil {
		t.Fatal(err)
	}
	return NewGameWithDealer(testPlayers(), 17, descriptor.RuleSet(), dealer)
}

func TestZunyiRuleCatalogAndOptions(t *testing.T) {
	rule, err := ResolveRuleDescriptor("zunyi_dingque", "1.0.0", nil)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(rule)
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Dingque        bool           `json:"dingque"`
		QuickMatch     bool           `json:"quick_match"`
		Region         string         `json:"region"`
		MutableOptions []string       `json:"mutable_options"`
		Options        map[string]any `json:"options"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	if !doc.Dingque || !rule.RuleSet().Dingque() || doc.QuickMatch || rule.AllowsQuickMatch() || doc.Region != "遵义" || !slices.Equal(doc.MutableOptions, []string{"chicken", "rob_kong"}) ||
		!reflect.DeepEqual(doc.Options, map[string]any{"version": "2.0.0", "chicken": true, "rob_kong": true}) {
		t.Fatalf("unexpected trial contract: %s", raw)
	}
	invalid := rule.Options
	invalid.BlackEight = true
	if _, err := ResolveRuleDescriptor(rule.ID, rule.Version, &invalid); err == nil {
		t.Fatal("accepted a legacy-only trial option")
	}
}

func TestZunyiSelectionsRemainPrivateAcrossRestartThenRevealTogether(t *testing.T) {
	game := newTrialGame(t, false, 2)
	if game.Phase != "dingque" || game.Turn != 2 || game.Dealer != 2 || len(game.Hands[2]) != 14 ||
		!slices.Equal(game.Options(1), []ActionOption{{Type: "dingque", Suit: "wan"}, {Type: "dingque", Suit: "tong"}, {Type: "dingque", Suit: "tiao"}}) {
		t.Fatalf("unexpected opening phase: dealer=%d phase=%s options=%v", game.Dealer, game.Phase, game.Options(1))
	}
	epoch := game.Epoch
	if err := game.Apply(2, "play", game.Hands[2][0].ID); err == nil {
		t.Fatal("the dealer discarded before choices finished")
	}
	if err := game.ChooseMissingSuit(0, "invalid"); err == nil {
		t.Fatal("an invalid suit was accepted")
	}
	if err := game.ChooseMissingSuit(0, "tiao"); err != nil {
		t.Fatal(err)
	}
	if err := game.ChooseMissingSuit(0, "wan"); err == nil || game.Epoch != epoch || len(game.Options(0)) != 0 || len(game.Options(1)) != 3 {
		t.Fatal("a duplicate choice changed the response window")
	}
	if _, ok := game.SnapshotFor(3)["missing_suits"]; ok {
		t.Fatal("a choice leaked before everyone had submitted")
	}
	if game.PublicBoard().MissingSuits != nil {
		t.Fatal("a choice leaked to observers")
	}
	restarted := restartTrial(t, game)
	for _, game := range []*Game{game, restarted} {
		game.Hands[1] = nil // Equal counts default to wan.
		game.Hands[2] = []Tile{{ID: 1, Suit: "wan", Rank: 1}}
		game.Hands[3] = []Tile{{ID: 37, Suit: "tong", Rank: 1}, {ID: 73, Suit: "tiao", Rank: 1}}
		game.Timeout()
		want := [4]string{"tiao", "wan", "tong", "wan"}
		if game.Phase != PhaseTurn || game.Epoch != epoch+1 || game.Turn != 2 || game.PublicBoard().MissingSuits == nil || *game.PublicBoard().MissingSuits != want || game.SnapshotFor(3)["missing_suits"] != want {
			t.Fatalf("unexpected public reveal: %+v", game.PublicBoard())
		}
		board, err := game.replay.Project(1)
		if err != nil || board.MissingSuits == nil || *board.MissingSuits != want {
			t.Fatalf("unexpected replay reveal: %+v, %v", board, err)
		}
	}
}

func restartTrial(t *testing.T, game *Game) *Game {
	t.Helper()
	raw, err := game.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	restored, err := RestoreCheckpoint(raw, game.Rules)
	if err != nil {
		t.Fatal(err)
	}
	return restored
}

func TestZunyiRestoreRejectsDifferentEffectiveOptions(t *testing.T) {
	game := newTrialGame(t, false, 0)
	otherRules := newTrialGame(t, true, 0).Rules
	raw, err := game.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := RestoreCheckpoint(raw, otherRules); err == nil {
		t.Fatal("same-version checkpoint accepted different locked options")
	}
}

func TestZunyiRequiresClearingMissingSuitEvenWhenDrawnAgain(t *testing.T) {
	game := newTrialGame(t, false, 0)
	wall := game.Rules.BuildWall()
	for seat := range game.Players {
		if err := game.ChooseMissingSuit(seat, "tiao"); err != nil {
			t.Fatal(err)
		}
	}
	game.Hands = [4][]Tile{{wall[0], wall[72], wall[73], wall[74], wall[75]}, nil, nil, nil}
	game.LastDrawnID = wall[0].ID
	for _, option := range game.Options(0) {
		if option.Type != "play" || option.TileID < wall[72].ID || option.TileID > wall[75].ID {
			t.Fatalf("illegal option with a missing suit: %+v", option)
		}
	}
	if len(game.Options(0)) != 4 {
		t.Fatalf("missing physical discard options: %v", game.Options(0))
	}
	for _, action := range []ActionOption{{Type: "play", TileID: wall[0].ID}, {Type: "an_gang", TileID: wall[72].ID}, {Type: "hu"}} {
		if err := game.Apply(0, action.Type, action.TileID); err == nil {
			t.Fatalf("the server accepted an illegal action: %+v", action)
		}
	}
	game.Timeout()
	if len(game.Discards) != 1 || game.Discards[0].Tile.Suit != "tiao" {
		t.Fatal("timeout must discard the missing suit when the draw cannot be played")
	}
}

func chooseTrialSuits(t *testing.T, game *Game, suit string) {
	t.Helper()
	for seat := range game.Players {
		if err := game.ChooseMissingSuit(seat, suit); err != nil {
			t.Fatal(err)
		}
	}
}

func trialPlainWait(wall []Tile, copyIndex int) []Tile {
	hand := make([]Tile, 0, 13)
	for _, offset := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 44, 48, 68} {
		hand = append(hand, wall[offset+copyIndex])
	}
	return hand
}

func TestZunyiClosestWinnerTakesDealerAfterMultiWinAndRestart(t *testing.T) {
	for _, multi := range []bool{false, true} {
		game := newTrialGame(t, false, 0)
		chooseTrialSuits(t, game, "tiao")
		wall := game.Rules.BuildWall()
		game.Hands = [4][]Tile{{wall[71]}, trialPlainWait(wall, 0), nil, nil}
		if multi {
			game.Hands[2] = trialPlainWait(wall, 1)
		}
		if err := game.Apply(0, "play", wall[71].ID); err != nil {
			t.Fatal(err)
		}
		if multi {
			if err := game.Apply(2, "hu", 0); err != nil {
				t.Fatal(err)
			}
		}
		for _, game := range []*Game{game, restartTrial(t, game)} {
			if err := game.Apply(1, "hu", 0); err != nil {
				t.Fatal(err)
			}
			wantScores := [4]int{-3, 3, 0, 0}
			wantLedger := []ScoreTransfer{{Payer: 0, Receiver: 1, Category: "hu", Reason: "dian_pao", Amount: 3, HandType: "平胡"}}
			if multi {
				wantScores = [4]int{-6, 3, 3, 0}
				wantLedger = append(wantLedger, ScoreTransfer{Payer: 0, Receiver: 2, Category: "hu", Reason: "dian_pao", Amount: 3, HandType: "平胡"})
			}
			restarted := restartTrial(t, game)
			for _, game := range []*Game{game, restarted} {
				replay := game.SettlementReplay()
				if game.WinKind != "dian_pao" || game.NextDealer() != 1 || game.Scores != wantScores ||
					!slices.Equal(game.SettlementScoreTransfers(), wantLedger) || replay == nil || !slices.Equal(replay.ScoreTransfers, wantLedger) ||
					!game.Discards[0].Claimed {
					t.Fatalf("scores=%v dealer=%d replay=%+v ledger=%+v", game.Scores, game.NextDealer(), replay, game.SettlementScoreTransfers())
				}
			}
		}
	}
}

func TestZunyiWallExhaustionOnlyPaysLiveWaitsAndPreservesKong(t *testing.T) {
	for _, blocked := range []bool{false, true} {
		game := newTrialGame(t, true, 2)
		chooseTrialSuits(t, game, "tiao")
		wall := game.Rules.BuildWall()
		game.Hands = [4][]Tile{{wall[72]}, trialPlainWait(wall, 0), nil, nil}
		game.awardGang(3, "ming_gang", 2)
		// The final tile is in the dealer's hand; all copies of the wait
		// are public or already held in the blocked case.
		if blocked {
			for _, tile := range wall[69:72] {
				game.Discards = append(game.Discards, Discard{Seat: 0, Tile: tile})
			}
		}
		game.NextWall = len(game.Wall)
		game.finishDraw()
		want := [4]int{-6, 12, -6, 0}
		wantBreakdown := ScoreBreakdown{Gang: [4]int{0, 0, -3, 3}, ChaJiao: [4]int{-6, 12, -3, -3}}
		if blocked {
			want = [4]int{0, 0, -3, 3}
			wantBreakdown.ChaJiao = [4]int{}
		}
		if game.NextDealer() != 2 || game.Scores != want || game.SettlementScoreBreakdown() == nil || *game.SettlementScoreBreakdown() != wantBreakdown ||
			game.FlippedJi != (Tile{}) || game.JiCounts != [4]int{} {
			t.Fatalf("blocked=%v draw results=%v breakdown=%+v", blocked, game.Scores, game.SettlementScoreBreakdown())
		}
		for _, transfer := range game.SettlementScoreTransfers() {
			if transfer.Category == "cha_jiao" && transfer.Payer == 0 && (transfer.Receiver != 1 || transfer.Amount != 6) {
				t.Fatalf("no-wait seat holding missing suit pays double: %+v", transfer)
			}
		}
	}
}

func TestZunyiHeatCannonReversesOnlyDirectlyPrecedingKong(t *testing.T) {
	game := newTrialGame(t, false, 0)
	chooseTrialSuits(t, game, "tiao")
	wall := game.Rules.BuildWall()
	game.Hands = [4][]Tile{{wall[71], wall[52], wall[53], wall[54], wall[55]}, trialPlainWait(wall, 0), nil, nil}
	game.Wall[game.NextWall] = wall[56]
	game.awardGang(0, "ming_gang", 2)
	if err := game.Apply(0, "an_gang", wall[52].ID); err != nil {
		t.Fatal(err)
	}
	if game.Scores != [4]int{12, -3, -6, -3} {
		t.Fatalf("each concealed kong payer owes 3, got %v", game.Scores)
	}
	if _, visible := game.SnapshotFor(1)["score_transfers"]; visible {
		t.Fatal("the live ledger leaked a concealed kong")
	}
	game = restartTrial(t, game)
	if err := game.Apply(0, "play", wall[71].ID); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(1, "hu", 0); err != nil {
		t.Fatal(err)
	}
	if game.Scores != [4]int{0, 3, -3, 0} || game.SettlementScoreBreakdown() == nil || game.SettlementScoreBreakdown().Gang != [4]int{3, 0, -3, 0} {
		t.Fatalf("heat cannon reversed an older kong or charged the wrong payer: %v", game.Scores)
	}
	reversalCount := 0
	for _, transfer := range game.SettlementScoreTransfers() {
		if transfer.Reason == "revoke_gang_heat_cannon" {
			reversalCount++
			if transfer.Payer != 0 || transfer.Receiver == 0 || transfer.Amount != 3 {
				t.Fatalf("bad reversal: %+v", transfer)
			}
		}
	}
	if reversalCount != 3 {
		t.Fatalf("expected all three concealed kong payers to receive a refund: %v", game.SettlementScoreTransfers())
	}
}

func TestZunyiChickenCountsRiverAndWinningTileOwnership(t *testing.T) {
	game := newTrialGame(t, true, 0)
	chooseTrialSuits(t, game, "tong")
	wall := game.Rules.BuildWall()
	game.Hands = [4][]Tile{{wall[73]}, {wall[0]}, {wall[74]}, nil}
	game.Wall[game.NextWall] = wall[104] // Nine tiao flips to one tiao, also fixed chicken.
	game.Discards = []Discard{
		{Seat: 0, Tile: wall[75]},
		{Seat: 3, Tile: wall[72], Claimed: true},
	}
	game.PendingTile, game.PendingFrom, game.PendingKind = wall[72], 3, "discard"
	game.settle([]int{1, 2}, 3, "dian_pao")
	if game.FlippedJi != wall[104] || game.JiCounts != [4]int{2, 1, 2, 0} || game.SettlementScoreBreakdown().Ji != [4]int{3, -1, 3, -5} {
		t.Fatalf("incorrect fixed/flip overlap or physical ownership: flips=%v counts=%v ledger=%v", game.FlippedJi, game.JiCounts, game.SettlementScoreTransfers())
	}
}

func TestZunyiRobbedKongLeavesOriginalPengAndNoKongScore(t *testing.T) {
	game := newTrialGame(t, false, 0)
	chooseTrialSuits(t, game, "tiao")
	wall := game.Rules.BuildWall()
	// Tong nine completes a sequence without needing a second copy of the
	// tile type already fully occupied by the pung and upgrade.
	game.Hands = [4][]Tile{{wall[69], wall[70], wall[71]}, nil, nil, {wall[68]}}
	game.Hands[1] = append(trialPlainWait(wall, 0)[:11], wall[60], wall[64])
	// The middle two tongs form the pair; tong seven/eight wait for nine.
	game.Hands[1][9], game.Hands[1][10] = wall[40], wall[41]
	if err := game.Apply(3, "play", wall[68].ID); err == nil {
		t.Fatal("non-turn play succeeded")
	}
	game.Turn = 3
	if err := game.Apply(3, "play", wall[68].ID); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(1, "pass", 0); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(0, "peng", 0); err != nil {
		t.Fatal(err)
	}
	before := game.Remaining()
	if err := game.Apply(0, "bu_gang", wall[71].ID); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(1, "hu", 0); err != nil {
		t.Fatal(err)
	}
	replay := game.SettlementReplay()
	if game.WinKind != "qiang_gang" || game.Melds[0][0].Kind != "peng" || game.Remaining() != before || game.Scores != [4]int{-3, 3, 0, 0} || replay == nil {
		t.Fatalf("invalid robbed kong settlement: phase=%s winner=%s scores=%v melds=%v replay=%v", game.Phase, game.WinKind, game.Scores, game.Melds, replay)
	}
	board, err := replay.Project(len(replay.Events))
	if err != nil || board.RobbedTile == nil || *board.RobbedTile != wall[71] || board.ScoreTransfers[0].Category != "hu" {
		t.Fatalf("robbed tile missing from replay: %+v, %v", board, err)
	}
}

func TestZunyiSelfDrawUsesHighestSinglePatternAndNoKongRequirement(t *testing.T) {
	for _, fixture := range []struct {
		name   string
		points int
		cards  []int
	}{
		{"平胡", 3, []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 44, 48, 68, 69}},
		{"大对子", 5, []int{0, 1, 2, 12, 13, 14, 24, 25, 26, 36, 37, 38, 44, 45}},
		{"七对", 5, []int{0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 36, 37, 40, 41}},
		{"龙七对", 10, []int{0, 1, 2, 3, 4, 5, 8, 9, 16, 17, 36, 37, 40, 41}},
		{"清一色", 10, []int{0, 1, 2, 12, 13, 14, 20, 21, 22, 32, 33, 34, 24, 25}},
		{"清龙七对", 20, []int{0, 1, 2, 3, 4, 5, 8, 9, 12, 13, 16, 17, 20, 21}},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			game := newTrialGame(t, false, 0)
			chooseTrialSuits(t, game, "tiao")
			wall := game.Rules.BuildWall()
			game.Hands = [4][]Tile{}
			for _, i := range fixture.cards {
				game.Hands[0] = append(game.Hands[0], wall[i])
			}
			game.LastDrawnID = game.Hands[0][13].ID
			if err := game.Apply(0, "hu", 0); err != nil {
				t.Fatal(err)
			}
			points := fixture.points
			if game.WinKind != "zi_mo" || game.NextDealer() != 0 || game.Scores != [4]int{3 * points, -points, -points, -points} {
				t.Fatalf("wrong self-draw result: %s %v", game.WinKind, game.Scores)
			}
			ledger := game.SettlementScoreTransfers()
			if len(ledger) != 3 {
				t.Fatalf("each of the other seats should pay once: %+v", ledger)
			}
			for _, entry := range ledger {
				if entry.HandType != fixture.name || entry.Amount != points || entry.Receiver != 0 {
					t.Fatalf("wrong highest pattern or payment: %+v", entry)
				}
			}
		})
	}
}

func TestZunyiSeededRoundSurvivesRepeatedRestartWithConservedTiles(t *testing.T) {
	first := newTrialGame(t, true, -1)
	second := newTrialGame(t, true, -1)
	for i := 0; i < 150 && first.Phase != PhaseFinished; i++ {
		first.Timeout()
		second = restartTrial(t, second)
		second.Timeout()
	}
	a, errA := first.MarshalCheckpoint()
	b, errB := second.MarshalCheckpoint()
	if errA != nil || errB != nil || !bytes.Equal(a, b) || first.Phase != PhaseFinished || first.SettlementReplay() == nil {
		t.Fatalf("seeded replay does not match repeated restore: phase=%s/%s errors=%v/%v", first.Phase, second.Phase, errA, errB)
	}
	seen := map[int]bool{}
	count := func(tile Tile) {
		t.Helper()
		if tile.ID < 1 || tile.ID > 108 || seen[tile.ID] {
			t.Fatalf("the physical entity appeared twice or was invalid: %+v", tile)
		}
		seen[tile.ID] = true
	}
	for seat, hand := range first.Hands {
		for _, tile := range hand {
			count(tile)
		}
		for _, meld := range first.Melds[seat] {
			for _, tile := range meld.Tiles {
				count(tile)
			}
		}
	}
	for _, discard := range first.Discards {
		if !discard.Claimed {
			count(discard.Tile)
		}
	}
	if first.FlippedJi.ID != 0 {
		count(first.FlippedJi)
	}
	if first.RobbedTile != nil {
		count(*first.RobbedTile)
	}
	for _, tile := range first.Wall[first.NextWall:] {
		count(tile)
	}
	if len(seen) != 108 {
		t.Fatalf("expected every physical tile exactly once, saw %d", len(seen))
	}
}
