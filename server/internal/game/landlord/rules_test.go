package landlord

import "testing"

func cards(ranks ...int) []Card {
	out := make([]Card, len(ranks))
	for i, r := range ranks {
		out[i] = Card{ID: i, Rank: r}
	}
	return out
}

func TestClassifyStandardPatterns(t *testing.T) {
	tests := []struct {
		name  string
		ranks []int
		want  string
	}{
		{"single", []int{3}, "single"}, {"pair", []int{5, 5}, "pair"}, {"rocket", []int{16, 17}, "rocket"},
		{"triple", []int{8, 8, 8}, "triple"}, {"bomb", []int{12, 12, 12, 12}, "bomb"},
		{"triple single", []int{6, 6, 6, 9}, "triple_single"}, {"triple pair", []int{6, 6, 6, 9, 9}, "triple_pair"},
		{"straight", []int{3, 4, 5, 6, 7}, "straight"}, {"pair straight", []int{3, 3, 4, 4, 5, 5}, "pair_straight"},
		{"airplane", []int{3, 3, 3, 4, 4, 4}, "airplane"}, {"airplane single", []int{3, 3, 3, 4, 4, 4, 8, 9}, "airplane_single"},
		{"airplane pair", []int{3, 3, 3, 4, 4, 4, 8, 8, 9, 9}, "airplane_pair"},
		{"four two single", []int{6, 6, 6, 6, 8, 9}, "four_two_single"}, {"four two pair", []int{6, 6, 6, 6, 8, 8, 9, 9}, "four_two_pair"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, e := Classify(cards(tt.ranks...))
			if e != nil || p.Kind != tt.want {
				t.Fatalf("pattern=%+v err=%v want=%s", p, e, tt.want)
			}
		})
	}
	for _, invalid := range [][]int{{3, 3, 4}, {10, 11, 12, 13, 15}, {11, 12, 13, 14, 15, 16}, {3, 3, 4, 4}, {3, 3, 3, 4, 4, 4, 8, 8, 9, 10}} {
		if _, e := Classify(cards(invalid...)); e == nil {
			t.Errorf("invalid pattern accepted %v", invalid)
		}
	}
	if !Beats(Pattern{"bomb", 3, 4}, Pattern{"straight", 14, 5}) || !Beats(Pattern{"rocket", 17, 2}, Pattern{"bomb", 15, 4}) || Beats(Pattern{"pair", 8, 2}, Pattern{"single", 7, 1}) {
		t.Fatal("beating priority incorrect")
	}
}

func TestThreePlayerDealBidPlayAndPrivateHands(t *testing.T) {
	g := NewGame([3]string{"a", "b", "c"}, 42)
	seen := map[int]bool{}
	for seat := 0; seat < 3; seat++ {
		if len(g.Hands[seat]) != 17 {
			t.Fatal("expected 17 cards")
		}
		for _, card := range g.Hands[seat] {
			if seen[card.ID] {
				t.Fatal("duplicate card")
			}
			seen[card.ID] = true
		}
	}
	if len(g.Bottom) != 3 {
		t.Fatal("expected three bottom cards")
	}
	if len(g.SnapshotFor(1)["bottom"].([]Card)) != 0 {
		t.Fatal("hidden bottom leaked before bidding")
	}
	if e := g.Bid(0, 1); e != nil {
		t.Fatal(e)
	}
	if e := g.Bid(1, 0); e != nil {
		t.Fatal(e)
	}
	if e := g.Bid(2, 2); e != nil {
		t.Fatal(e)
	}
	if g.Landlord != 2 || len(g.Hands[2]) != 20 || g.Phase != PhasePlay {
		t.Fatalf("bad landlord %+v", g)
	}
	if e := g.PlayCards(1, []int{g.Hands[1][0].ID}); e == nil {
		t.Fatal("out of turn accepted")
	}
	first := g.Hands[2][0].ID
	if e := g.PlayCards(2, []int{first}); e != nil {
		t.Fatal(e)
	}
	if len(g.Hands[2]) != 19 {
		t.Fatal("played card not removed")
	}
	if e := g.Pass(0); e != nil {
		t.Fatal(e)
	}
	if e := g.Pass(1); e != nil {
		t.Fatal(e)
	}
	if g.Turn != 2 || g.HasLastPlay {
		t.Fatal("trick did not reset after two passes")
	}
	if _, exists := g.SnapshotFor(0)["hands_revealed"]; exists {
		t.Fatal("opponents revealed before settlement")
	}
}

func TestAllPassRedealsAndSpringSettlement(t *testing.T) {
	g := NewGame([3]string{"a", "b", "c"}, 99)
	for seat := 0; seat < 3; seat++ {
		if err := g.Bid(seat, 0); err != nil {
			t.Fatal(err)
		}
	}
	if g.Phase != PhaseBid || g.DealNumber != 1 || g.Turn != 0 || len(g.Hands[0]) != 17 {
		t.Fatalf("all pass should redeal: %+v", g)
	}
	if err := g.Bid(0, 3); err != nil {
		t.Fatal(err)
	}
	g.Hands[0] = []Card{CardFromID(0)}
	g.Hands[1] = []Card{CardFromID(1)}
	g.Hands[2] = []Card{CardFromID(2)}
	if err := g.PlayCards(0, []int{0}); err != nil {
		t.Fatal(err)
	}
	if g.Phase != PhaseFinished || g.Winner != 0 || g.Multiplier != 2 || g.Scores != [3]int{12, -6, -6} {
		t.Fatalf("spring settlement: %+v", g)
	}
}

func TestTrainingBotRespondsToSingleWithLegalCard(t *testing.T) {
	g := NewGame([3]string{"me", "bot1", "bot2"}, 7)
	if err := g.Bid(0, 3); err != nil {
		t.Fatal(err)
	}
	g.Hands[0] = []Card{CardFromID(0), CardFromID(40)}
	g.Hands[1] = []Card{CardFromID(8), CardFromID(12)}
	g.Hands[2] = []Card{CardFromID(16)}
	if err := g.PlayCards(0, []int{0}); err != nil {
		t.Fatal(err)
	}
	if err := g.BotTurn(1); err != nil {
		t.Fatal(err)
	}
	if !g.HasLastPlay || g.LastPlay.Seat != 1 || g.LastPlay.Pattern.Main != 5 || len(g.Hands[1]) != 1 {
		t.Fatalf("bot did not beat a single with its lowest legal card: %+v", g.LastPlay)
	}
}
