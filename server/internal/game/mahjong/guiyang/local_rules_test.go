package guiyang

import (
	"encoding/json"
	"slices"
	"testing"
)

func newLocalGame(t *testing.T, chicken bool) *Game {
	t.Helper()
	options := RuleOptions{Version: RuleOptionsVersion, Chicken: chicken, ChargeChicken: chicken, BlackEight: chicken, RobKong: true}
	rule, err := ResolveRuleDescriptor("guiyang", "3.0.0", &options)
	if err != nil {
		t.Fatal(err)
	}
	if !rule.RequiresKongToClaim || !rule.Options.RequiresKongToClaim {
		t.Fatal("the local preset must lock own completed kong for external wins")
	}
	return NewGameWithDealer(testPlayers(), 1, rule.RuleSet(), 0)
}

func TestLocalDianPaoAndRobKongStayStrict(t *testing.T) {
	for _, action := range []string{"play", "bu_gang"} {
		t.Run(action, func(t *testing.T) {
			g := newLocalGame(t, false)
			wall := g.Rules.BuildWall()
			g.Hands = [4][]Tile{{wall[72]}, {}, {}, {}}
			if action == "bu_gang" {
				g.Melds[0] = []Meld{{Kind: "peng", Tiles: wall[73:76], FromSeat: 2}}
			}
			for _, index := range []int{76, 80, 84, 88, 92, 96, 100, 104, 85, 89, 93, 97, 98} {
				g.Hands[1] = append(g.Hands[1], wall[index])
			}
			if ok, _ := g.Rules.CanHu(g.Hands[1], wall[72]); !ok {
				t.Fatal("fixture must be a winning pure suit")
			}
			if err := g.Apply(0, action, wall[72].ID); err != nil {
				t.Fatal(err)
			}
			if slices.Contains(g.Options(1), ActionOption{Type: "hu"}) {
				t.Fatal("even a named hand must not claim without a prior kong")
			}
			if err := g.Apply(1, "hu", 0); err == nil {
				t.Fatal("a forged hu command bypassed the completed kong gate")
			}
		})
	}
}

func TestLocalNamedSelfDrawWithoutKong(t *testing.T) {
	for _, test := range []struct {
		name    string
		indices []int
		fan     int
	}{
		{"平胡", []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 72, 76, 80}, 2},
		{"大对子", []int{0, 1, 2, 12, 13, 14, 24, 25, 26, 36, 37, 38, 72, 73}, 6},
		{"七对", []int{0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 36, 37, 40, 41}, 8},
		{"龙七对", []int{0, 1, 2, 3, 4, 5, 8, 9, 16, 17, 36, 37, 40, 41}, 11},
		{"清一色", []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 0 + 1, 4 + 1, 8 + 1, 28 + 1, 28 + 2}, 11},
		{"清大对", []int{0, 1, 2, 12, 13, 14, 20, 21, 22, 32, 33, 34, 24, 25}, 16},
		{"清七对", []int{0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 20, 21, 24, 25}, 18},
		{"清龙七对", []int{0, 1, 2, 3, 4, 5, 8, 9, 12, 13, 16, 17, 20, 21}, 21},
	} {
		t.Run(test.name, func(t *testing.T) {
			g := newLocalGame(t, false)
			wall := g.Rules.BuildWall()
			g.Hands = [4][]Tile{}
			for _, index := range test.indices {
				g.Hands[0] = append(g.Hands[0], wall[index])
			}
			g.Discards = []Discard{{Seat: 0, Tile: wall[107]}}
			g.LastDrawnID = g.Hands[0][13].ID
			if err := g.Apply(0, "hu", 0); err != nil {
				t.Fatal(err)
			}
			var settlement struct {
				HuDetails []struct {
					Seat, Fan, Points int
					Kind, Pattern     string
				} `json:"hu_details"`
			}
			payload, err := json.Marshal(g.SnapshotFor(1))
			if err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(payload, &settlement); err != nil {
				t.Fatal(err)
			}
			if len(settlement.HuDetails) != 1 || settlement.HuDetails[0].Pattern != test.name || settlement.HuDetails[0].Kind != "zi_mo" || settlement.HuDetails[0].Fan != test.fan || settlement.HuDetails[0].Points != 3*test.fan {
				t.Fatalf("unexpected local settlement: %+v", settlement)
			}
			if got := g.SettlementScoreBreakdown(); got == nil || got.Hu != [4]int{3 * test.fan, -test.fan, -test.fan, -test.fan} {
				t.Fatalf("invalid local scoring breakdown: %+v", got)
			}
		})
	}
}

func TestLocalOpeningWinUsesActualDealerAndFirstDraw(t *testing.T) {
	for _, test := range []struct {
		seat, fan int
		pattern   string
	}{
		{2, 34, "天胡"},
		{3, 24, "地胡"},
	} {
		t.Run(test.pattern, func(t *testing.T) {
			g := NewGameWithDealer(testPlayers(), 1, newLocalGame(t, false).Rules, 2)
			if g.Turn != 2 || len(g.Hands[2]) != 14 || g.SnapshotFor(0)["dealer"] != 2 {
				t.Fatalf("the specified dealer does not open play: %+v", g.PublicBoard())
			}
			wall := g.Rules.BuildWall()
			openingHand := make([]Tile, 0, 14)
			for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 76, 80, 72} {
				openingHand = append(openingHand, wall[index])
			}
			g.Hands = [4][]Tile{}
			if test.seat == g.Dealer {
				g.Hands[test.seat] = openingHand
				g.LastDrawnID = wall[72].ID
			} else {
				g.Hands[test.seat] = openingHand[:13]
				g.Hands[g.Dealer] = []Tile{wall[107]}
				g.Wall[g.NextWall] = wall[72]
				if err := g.Apply(g.Dealer, "play", wall[107].ID); err != nil {
					t.Fatal(err)
				}
			}
			if err := g.Apply(test.seat, "hu", 0); err != nil {
				t.Fatal(err)
			}
			want := HuDetail{Seat: test.seat, Kind: "zi_mo", Pattern: test.pattern, Fan: test.fan, Points: 3 * test.fan}
			if !slices.Equal(g.SettlementHuDetails(), []HuDetail{want}) || g.NextDealer() != test.seat {
				t.Fatalf("incorrect opening settlement: %+v, next dealer %d", g.SettlementHuDetails(), g.NextDealer())
			}
		})
	}
}

func TestLocalKongPayers(t *testing.T) {
	for _, test := range []struct {
		kind string
		want [4]int
	}{
		{"an_gang", [4]int{6, -2, -2, -2}},
		{"bu_gang", [4]int{9, -3, -3, -3}},
		{"ming_gang", [4]int{1, -1, 0, 0}},
	} {
		t.Run(test.kind, func(t *testing.T) {
			g := newLocalGame(t, false)
			wall := g.Rules.BuildWall()
			g.Hands = [4][]Tile{}
			if test.kind == "ming_gang" {
				g.Turn, g.Hands[1], g.Hands[0] = 1, wall[:1:1], wall[1:4:4]
				if err := g.Apply(1, "play", wall[0].ID); err != nil {
					t.Fatal(err)
				}
			} else if test.kind == "bu_gang" {
				g.Hands[0] = wall[:1:1]
				g.Melds[0] = []Meld{{Kind: "peng", Tiles: wall[1:4:4], FromSeat: 1}}
			} else {
				g.Hands[0] = wall[:4:4]
			}
			if err := g.Apply(0, test.kind, wall[0].ID); err != nil {
				t.Fatal(err)
			}
			if g.Scores != test.want || g.ScoreBreakdown.Gang != test.want {
				t.Fatalf("kong scored %v, want %v", g.Scores, test.want)
			}
		})
	}
}

func TestLocalDrawChecksReadyAndRemovesKongCharge(t *testing.T) {
	g := newLocalGame(t, true)
	wall := g.Rules.BuildWall()
	g.NextWall = len(g.Wall)
	g.Hands = [4][]Tile{{wall[106]}, {}, {}, {}}
	for _, index := range []int{0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 36, 37, 40} {
		g.Hands[1] = append(g.Hands[1], wall[index])
	}
	g.transferScore(scoreGang, 0, 2, 2)
	g.transferScore(scoreJi, 3, 2, 1)
	if err := g.Apply(0, "play", wall[106].ID); err != nil {
		t.Fatal(err)
	}
	if g.Reason != "wall_exhausted" || g.Scores != [4]int{-7, 21, -7, -7} {
		t.Fatalf("draw check-ready settlement: %s %v", g.Reason, g.Scores)
	}
	if got, ok := g.SnapshotFor(0)["ready_seats"].([]int); !ok || !slices.Equal(got, []int{1}) {
		t.Fatalf("draw did not publish confirmed ready seats: %v", got)
	}
	if got := g.SettlementScoreBreakdown(); got == nil || got.Gang != [4]int{} || got.Ji != [4]int{} || got.Hu != [4]int{} || got.ChaJiao != g.Scores {
		t.Fatalf("draw scoring breakdown: %+v", got)
	}
	checkpoint, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	resumed, err := RestoreCheckpoint(checkpoint, g.Rules)
	if err != nil {
		t.Fatal(err)
	}
	replay := resumed.SettlementReplay()
	if replay == nil {
		t.Fatal("the saved settlement must reconstruct the public replay")
	}
	end, err := replay.Project(len(replay.Events))
	if err != nil || !slices.Equal(end.ReadySeats, []int{1}) || len(end.HuDetails) != 1 || end.HuDetails[0] != (HuDetail{Seat: 1, Kind: "cha_jiao", Pattern: "七对", Fan: 7, Points: 21}) {
		t.Fatalf("invalid final replay settlement: %+v, %v", end, err)
	}
	start, err := replay.Project(0)
	if err != nil || len(start.HuDetails) != 0 || len(start.ReadySeats) != 0 {
		t.Fatalf("the replay exposed settlement before the end: %+v, %v", start, err)
	}
}

func TestLocalDrawExcludesWaitWithAllFourCopiesVisible(t *testing.T) {
	g := newLocalGame(t, false)
	wall := g.Rules.BuildWall()
	g.NextWall = len(g.Wall)
	g.Hands = [4][]Tile{{wall[106]}, {}, {}, {}}
	for _, index := range []int{0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 36, 37, 40} {
		g.Hands[1] = append(g.Hands[1], wall[index])
	}
	for _, tile := range wall[41:44] {
		g.Discards = append(g.Discards, Discard{Seat: 3, Tile: tile})
	}
	if err := g.Apply(0, "play", wall[106].ID); err != nil {
		t.Fatal(err)
	}
	if g.Reason != "wall_exhausted" || len(g.SettlementReadySeats()) != 0 || g.Scores != [4]int{} || g.NextDealer() != g.Dealer {
		t.Fatalf("the closed wait was payable: ready=%v scores=%v", g.SettlementReadySeats(), g.Scores)
	}
}

func TestLocalGoldenChickenDoublesFixedTypeAndCharge(t *testing.T) {
	for _, test := range []struct {
		name                             string
		first, held, flip, charge, units int
	}{
		{"金幺鸡", 72, 73, 104, 4, 2},
		{"金乌骨鸡", 64, 65, 60, 8, 4},
	} {
		t.Run(test.name, func(t *testing.T) {
			g := newLocalGame(t, true)
			wall := g.Rules.BuildWall()
			g.Hands = [4][]Tile{{wall[test.first]}, {wall[test.held]}, {}, {}}
			g.Wall, g.NextWall = []Tile{wall[100], wall[test.flip]}, 0
			if err := g.Apply(0, "play", wall[test.first].ID); err != nil {
				t.Fatal(err)
			}
			g.scoreChicken([]int{2}, -1, Tile{})
			if g.JiCounts != [4]int{test.charge, test.units, 0, 0} || g.JiEvents[0].ValueUnits != test.charge {
				t.Fatalf("golden chicken settled with counts %v and charge %+v", g.JiCounts, g.JiEvents)
			}
		})
	}
}

func TestLocalDeclinedHuSurvivesRestartAndBlocksDifferentWaitUntilDraw(t *testing.T) {
	g := newLocalGame(t, false)
	wall := g.Rules.BuildWall()
	g.Hands = [4][]Tile{{wall[72]}, {wall[84]}, {}, {}}
	g.Melds[2] = []Meld{{Kind: "an_gang", Tiles: wall[60:64:64], FromSeat: 2}}
	for _, index := range []int{0, 4, 8, 12, 16, 20, 36, 37, 76, 80} {
		g.Hands[2] = append(g.Hands[2], wall[index])
	}
	for _, candidate := range []Tile{wall[72], wall[84]} {
		if ok, _ := g.Rules.CanHuHand(append(slices.Clone(g.Hands[2]), candidate), 1); !ok {
			t.Fatalf("fixture must wait on both bamboo tiles: %v", candidate)
		}
	}
	if err := g.Apply(0, "play", wall[72].ID); err != nil || !slices.Contains(g.Options(2), ActionOption{Type: "hu"}) {
		t.Fatalf("first external win not offered: %v", err)
	}
	g.Timeout()
	checkpoint, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	otherOptions := newLocalGame(t, true).Rules
	if _, err := RestoreCheckpoint(checkpoint, otherOptions); err == nil {
		t.Fatal("checkpoint accepted different effective rules for the same preset")
	}
	g, err = RestoreCheckpoint(checkpoint, g.Rules)
	if err != nil {
		t.Fatal(err)
	}
	if err := g.Apply(1, "play", wall[84].ID); err != nil || slices.Contains(g.Options(2), ActionOption{Type: "hu"}) || g.Turn != 2 {
		t.Fatalf("declining hu did not close the cycle until drawing: %v %v", err, g.Options(2))
	}
	if err := g.Apply(2, "play", g.LastDrawnID); err != nil {
		t.Fatal(err)
	}
	if g.Phase == PhaseReaction {
		g.Timeout()
	}
	g.Hands[3] = []Tile{wall[85]}
	if err := g.Apply(3, "play", wall[85].ID); err != nil || !slices.Contains(g.Options(2), ActionOption{Type: "hu"}) {
		t.Fatalf("drawing a tile should reset declined hu: %v %v", err, g.Options(2))
	}
}

func TestLocalDeclinedPengBlocksSameTypeOnly(t *testing.T) {
	g := newLocalGame(t, false)
	wall := g.Rules.BuildWall()
	g.Hands = [4][]Tile{{wall[0]}, {wall[3]}, {}, {wall[1], wall[2]}}
	g.Wall[g.NextWall] = wall[40]
	if err := g.Apply(0, "play", wall[0].ID); err != nil {
		t.Fatal(err)
	}
	if err := g.Apply(3, "pass", 0); err != nil {
		t.Fatal(err)
	}
	if err := g.Apply(1, "play", wall[3].ID); err != nil || slices.Contains(g.Options(3), ActionOption{Type: "peng"}) {
		t.Fatalf("same type peng was offered again before a draw: %v %v", err, g.Options(3))
	}
}

func TestLocalKongWinKindsAndBurnedExtras(t *testing.T) {
	for _, test := range []struct {
		name     string
		wantHu   [4]int
		wantGang [4]int
	}{
		{"gang_shang_hua", [4]int{9, -3, -3, -3}, [4]int{6, -2, -2, -2}},
		{"re_pao", [4]int{-3, 3, 0, 0}, [4]int{}},
		{"qiang_gang", [4]int{-6, 6, 0, 0}, [4]int{}},
	} {
		t.Run(test.name, func(t *testing.T) {
			g := newLocalGame(t, test.name != "gang_shang_hua")
			wall := g.Rules.BuildWall()
			g.Hands = [4][]Tile{}
			seat := 1
			if test.name == "gang_shang_hua" {
				seat = 0
			} else {
				g.Melds[1] = []Meld{{Kind: "an_gang", Tiles: wall[60:64:64], FromSeat: 1}}
				g.transferScore(scoreGang, 2, 1, 2)
				g.transferScore(scoreJi, 0, 2, 1)
			}
			for _, index := range []int{0, 4, 8, 12, 16, 20, 36, 37, 76, 80} {
				g.Hands[seat] = append(g.Hands[seat], wall[index])
			}
			if test.name == "qiang_gang" {
				g.Hands[0] = []Tile{wall[72]}
				g.Melds[0] = []Meld{{Kind: "peng", Tiles: wall[73:76:76], FromSeat: 2}}
				if err := g.Apply(0, "bu_gang", wall[72].ID); err != nil {
					t.Fatal(err)
				}
			} else {
				g.Hands[0] = append(g.Hands[0], wall[64:68]...)
				g.Wall[g.NextWall] = wall[72]
				if err := g.Apply(0, "an_gang", wall[64].ID); err != nil {
					t.Fatal(err)
				}
				if test.name == "re_pao" {
					if err := g.Apply(0, "play", wall[72].ID); err != nil {
						t.Fatal(err)
					}
				}
			}
			if err := g.Apply(seat, "hu", 0); err != nil {
				t.Fatal(err)
			}
			if snapshot := g.SnapshotFor(seat); snapshot["win_kind"] != test.name {
				t.Errorf("player snapshot win kind = %v, want %q", snapshot["win_kind"], test.name)
			}
			if g.WinKind != test.name {
				t.Errorf("persisted win kind = %q, want %q", g.WinKind, test.name)
			}
			breakdown := g.SettlementScoreBreakdown()
			if breakdown == nil || breakdown.Hu != test.wantHu || breakdown.Gang != test.wantGang || breakdown.Ji != [4]int{} {
				t.Fatalf("unexpected %s breakdown: %+v", test.name, breakdown)
			}
			if g.FlippedJi != (Tile{}) || g.JiCounts != [4]int{} {
				t.Fatalf("special count must not flip chicken: %v %v", g.FlippedJi, g.JiCounts)
			}
		})
	}
}
