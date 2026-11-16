package guiyang

import (
	"encoding/json"
	"testing"
)

func TestScoreBreakdownTracksAllTransfersAndPublishesOnlyOnSettlement(t *testing.T) {
	g := NewGame(testPlayers(), 1)
	if _, exists := g.SnapshotFor(0)["score_breakdown"]; exists {
		t.Fatal("active game published breakdown")
	}
	// Controlled inputs: one gang, one response to the first fixed chicken,
	// then a discard win. Zeroing held tiles isolates the chicken transfers.
	g.Hands = [4][]Tile{}
	g.Wall = nil
	g.NextWall = 0
	g.awardGang(1)
	g.PendingTile = Tile{ID: 1, Suit: "tiao", Rank: 1}
	g.Hands[2] = []Tile{{ID: 2, Suit: "tiao", Rank: 1}, {ID: 3, Suit: "tiao", Rank: 1}}
	g.PendingFrom = 0
	g.FirstSpecialDiscard = 0
	g.Discards = []Discard{{Seat: 0, Tile: g.PendingTile}}
	g.claim(2, "peng")
	g.settle([]int{3}, 0, "dian_pao")
	want := ScoreBreakdown{
		Hu: [4]int{-3, 0, 0, 3}, Gang: [4]int{-1, 3, -1, -1}, Ji: [4]int{-4, -3, 10, -3},
	}
	if breakdown := g.SettlementScoreBreakdown(); breakdown == nil || *breakdown != want {
		t.Fatalf("breakdown = %+v, want %+v (scores %v)", breakdown, want, g.Scores)
	}
	if g.Scores != [4]int{-8, 0, 9, -1} {
		t.Fatalf("unexpected scores: %v", g.Scores)
	}
	for seat := range 4 {
		breakdown, ok := g.SnapshotFor(seat)["score_breakdown"].(*ScoreBreakdown)
		if !ok || *breakdown != want {
			t.Fatalf("seat %d got different breakdown: %+v", seat, breakdown)
		}
		breakdown.Hu[0] = 99
	}
	if *g.ScoreBreakdown != want {
		t.Fatal("public settlement aliased authoritative score breakdown")
	}
}

func TestScoreBreakdownSurvivesCheckpointAndLeavesLegacyDetailsUnknown(t *testing.T) {
	rules := NewRuleSet()
	g := NewGameWithRules(testPlayers(), 3, rules)
	g.awardGang(0)
	checkpoint, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	recovered, err := RestoreCheckpoint(checkpoint, rules)
	if err != nil {
		t.Fatal(err)
	}
	recovered.finishDraw()
	if got := recovered.SettlementScoreBreakdown(); got == nil || got.Gang != [4]int{3, -1, -1, -1} {
		t.Fatalf("checkpoint lost gang transfers: %+v", got)
	}
	var legacy struct{ State map[string]json.RawMessage }
	if err := json.Unmarshal(checkpoint, &legacy); err != nil {
		t.Fatal(err)
	}
	delete(legacy.State, "ScoreBreakdown")
	data, err := json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	old, err := RestoreCheckpoint(data, rules)
	if err != nil {
		t.Fatal(err)
	}
	old.awardGang(1)
	old.finishDraw()
	if old.Scores != [4]int{2, 2, -2, -2} || old.ScoreBreakdown != nil || old.SettlementScoreBreakdown() != nil {
		t.Fatalf("legacy checkpoint changed score semantics or invented details: %+v %v", old.ScoreBreakdown, old.Scores)
	}
	if _, exists := old.SnapshotFor(0)["score_breakdown"]; exists {
		t.Fatal("legacy game published unverified breakdown")
	}
	recovered.ScoreBreakdown.Hu = [4]int{1, -1, 0, 0}
	if recovered.SettlementScoreBreakdown() != nil {
		t.Fatal("published breakdown that does not reconcile to settled scores")
	}
}
