package landlord

import (
	"reflect"
	"testing"
)

func TestReferenceDoublingIsOptInAndEachSeatDecidesOnce(t *testing.T) {
	legacy := NewGame([3]string{"a", "b", "c"}, 42)
	if err := legacy.Bid(0, 3); err != nil || legacy.Phase != PhasePlay { t.Fatalf("legacy bidding changed: %v %s", err, legacy.Phase) }
	g := NewGame([3]string{"a", "b", "c"}, 42)
	g.EnableDoubling = true
	if err := g.Bid(0, 3); err != nil { t.Fatal(err) }
	if g.Phase != PhaseDouble || g.Turn != 0 || len(g.Hands[0]) != 20 { t.Fatalf("invalid doubling start: %+v", g) }
	if err := g.PlayCards(0, []int{g.Hands[0][0].ID}); err == nil { t.Fatal("play accepted before doubling decisions") }
	if err := g.Double(1, true); err == nil { t.Fatal("out of turn doubling accepted") }
	if err := g.Double(0, true); err != nil { t.Fatal(err) }
	if g.Multiplier != 2 || g.Turn != 1 { t.Fatal("first doubling did not update shared multiplier") }
	epoch := g.Epoch
	if err := g.Double(0, true); err == nil || g.Epoch != epoch || g.Multiplier != 2 { t.Fatal("repeated decision changed the game") }
	if err := g.Double(1, false); err != nil { t.Fatal(err) }
	if err := g.Double(2, true); err != nil { t.Fatal(err) }
	if g.Phase != PhasePlay || g.Turn != 0 || g.Multiplier != 4 { t.Fatalf("doubling failed to begin landlord play: %+v", g) }
	state := g.SnapshotFor(1)
	if !reflect.DeepEqual(state["double_decided"], [3]bool{true,true,true}) || !reflect.DeepEqual(state["doubled"], [3]bool{true,false,true}) { t.Fatalf("decisions not publicly projected: %v", state) }
}

func TestReferenceDoublingSurvivesRedealAndAutoDeclines(t *testing.T) {
	g := NewGame([3]string{}, 7)
	g.EnableDoubling = true
	for seat := 0; seat < 3; seat++ { if err := g.Bid(seat, 0); err != nil { t.Fatal(err) } }
	if !g.EnableDoubling || g.DealNumber != 1 { t.Fatal("redeal lost doubling configuration") }
	if err := g.Bid(0, 3); err != nil { t.Fatal(err) }
	g.Timeout()
	if g.Phase != PhaseDouble || g.Turn != 1 || !g.DoubleDecided[0] || g.Doubled[0] { t.Fatal("timeout did not decline doubling") }
	if err := g.BotTurn(1); err != nil { t.Fatal(err) }
	if err := g.BotTurn(2); err != nil { t.Fatal(err) }
	if g.Phase != PhasePlay || g.Multiplier != 1 || g.Turn != 0 { t.Fatalf("automatic decisions invalid: %+v", g) }
	if err := g.Double(-1, true); err == nil { t.Fatal("invalid seat accepted") }
}

func TestReferenceHintFindsLegalPatternResponsesWithoutChangingHand(t *testing.T) {
	fixtures := []struct { kind string; previous, hand []int }{
		{"single", []int{3}, []int{3,4}},
		{"pair", []int{4,4}, []int{3,3,5,5}},
		{"triple", []int{4,4,4}, []int{5,5,5,9}},
		{"triple_single", []int{4,4,4,8}, []int{5,5,5,9}},
		{"triple_pair", []int{4,4,4,8,8}, []int{5,5,5,9,9}},
		{"straight", []int{3,4,5,6,7}, []int{4,5,6,7,8}},
		{"pair_straight", []int{3,3,4,4,5,5}, []int{4,4,5,5,6,6}},
		{"airplane", []int{3,3,3,4,4,4}, []int{4,4,4,5,5,5}},
		{"airplane_single", []int{3,3,3,4,4,4,8,9}, []int{4,4,4,5,5,5,9,10}},
		{"airplane_pair", []int{3,3,3,4,4,4,8,8,9,9}, []int{4,4,4,5,5,5,9,9,10,10}},
		{"four_two_single", []int{4,4,4,4,8,9}, []int{5,5,5,5,9,10}},
		{"four_two_pair", []int{4,4,4,4,8,8,9,9}, []int{5,5,5,5,9,9,10,10}},
		{"bomb", []int{4,4,4,4}, []int{5,5,5,5,9}},
	}
	for _, fixture := range fixtures {
		t.Run(fixture.kind, func(t *testing.T){
			previous, err := Classify(cards(fixture.previous...))
			if err != nil { t.Fatal(err) }
			g := NewGame([3]string{}, 42)
			g.Phase, g.Turn, g.Landlord = PhasePlay, 0, 0
			g.Hands[0] = cards(fixture.hand...)
			g.HasLastPlay, g.LastPlay = true, Play{Seat:1,Pattern:previous}
			before := append([]Card(nil), g.Hands[0]...)
			ids := g.SuggestedCards(0)
			if len(ids) == 0 { t.Fatal("valid response missed") }
			if !reflect.DeepEqual(before, g.Hands[0]) { t.Fatal("requesting hint changed private hand") }
			if err := g.PlayCards(0, ids); err != nil { t.Fatalf("illegal recommendation: %v ids=%v", err, ids) }
			if g.LastPlay.Pattern.Kind != fixture.kind { t.Fatalf("expected normal response, got %s", g.LastPlay.Pattern.Kind) }
		})
	}
}

func TestReferenceHintBombRocketAndNoLegalResponse(t *testing.T) {
	g := NewGame([3]string{}, 42)
	g.Phase, g.Turn, g.Landlord = PhasePlay, 0, 0
	g.HasLastPlay, g.LastPlay = true, Play{Seat:1, Pattern:Pattern{Kind:"straight",Main:14,Length:5}}
	g.Hands[0] = cards(3,3,3,3,8)
	if err := g.PlayCards(0, g.SuggestedCards(0)); err != nil || g.LastPlay.Pattern.Kind != "bomb" { t.Fatalf("bomb fallback missed: %v", err) }
	g.Phase, g.Turn = PhasePlay, 0
	g.HasLastPlay, g.LastPlay = true, Play{Seat:1, Pattern:Pattern{Kind:"bomb",Main:15,Length:4}}
	g.Hands[0] = cards(16,17,3)
	if err := g.PlayCards(0, g.SuggestedCards(0)); err != nil || g.LastPlay.Pattern.Kind != "rocket" { t.Fatalf("rocket fallback missed: %v", err) }
	g.Phase, g.Turn = PhasePlay, 0
	g.HasLastPlay, g.LastPlay = true, Play{Seat:1, Pattern:Pattern{Kind:"rocket",Main:17,Length:2}}
	g.Hands[0] = cards(3,4,5)
	if len(g.SuggestedCards(0)) != 0 { t.Fatal("hint recommended a response to rocket") }
	if len(g.SuggestedCards(1)) != 0 || len(g.SuggestedCards(-1)) != 0 { t.Fatal("out of turn or invalid seat hint returned private cards") }
	g.Phase = PhaseBid
	if len(g.SuggestedCards(0)) != 0 { t.Fatal("hint available during bidding") }
}
