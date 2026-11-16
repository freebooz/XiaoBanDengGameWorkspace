package guiyang

import (
	"bytes"
	"testing"
)

// Exercise the real play -> response -> pung -> discard transitions. An exposed
// pung is not a concealed triplet and can never take another player's fourth.
func TestExposedPungCannotKongAnotherPlayersFourth(t *testing.T) {
	g := NewGame(testPlayers(), 1)
	w := g.Rules.BuildWall()
	g.Turn = 2
	g.Hands = [4][]Tile{{w[5], w[6], w[40]}, {w[7], w[44]}, {w[4]}, {w[48]}}
	if err := g.Apply(2, "play", w[4].ID); err != nil {
		t.Fatal(err)
	}
	if err := g.Apply(0, "peng", 0); err != nil {
		t.Fatal(err)
	}
	if len(g.Melds[0]) != 1 || g.Melds[0][0].Kind != "peng" || len(g.Melds[0][0].Tiles) != 3 {
		t.Fatal("fixture did not expose a real pung")
	}
	if err := g.Apply(0, "play", w[40].ID); err != nil {
		t.Fatal(err)
	}
	// Seat 1 held the last copy, and now discards it after the pung was made.
	if err := g.Apply(1, "play", w[7].ID); err != nil {
		t.Fatal(err)
	}
	for _, option := range g.Options(0) {
		if option.Type == "ming_gang" || option.Type == "bu_gang" {
			t.Fatalf("exposed pung offered illegal kong: %+v", option)
		}
	}
	before, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	for _, action := range []string{"ming_gang", "bu_gang"} {
		if err := g.Apply(0, action, w[7].ID); err == nil {
			t.Fatalf("forged %s accepted another player's fourth tile", action)
		}
		after, err := g.MarshalCheckpoint()
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(before, after) {
			t.Fatalf("rejected %s mutated state", action)
		}
	}
	if g.Melds[0][0].Kind != "peng" || len(g.Melds[0][0].Tiles) != 3 || g.Discards[len(g.Discards)-1].Claimed || g.Scores != [4]int{} {
		t.Fatal("another player's fourth changed the pung, discard ownership or scores")
	}
}

func TestConcealedTripletCanKongAnotherPlayersFourth(t *testing.T) {
	g := NewGame(testPlayers(), 1)
	w := g.Rules.BuildWall()
	g.Turn = 1
	g.Hands = [4][]Tile{{w[4], w[5], w[6], w[40]}, {w[7]}, nil, nil}
	remaining := g.Remaining()
	if err := g.Apply(1, "play", w[7].ID); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, option := range g.Options(0) {
		found = found || option.Type == "ming_gang"
	}
	if !found {
		t.Fatal("three concealed matching tiles must offer exposed kong")
	}
	if err := g.Apply(0, "ming_gang", 0); err != nil {
		t.Fatal(err)
	}
	if len(g.Melds[0]) != 1 || g.Melds[0][0].Kind != "ming_gang" || len(g.Melds[0][0].Tiles) != 4 || g.Melds[0][0].FromSeat != 1 {
		t.Fatal("exposed kong did not contain the concealed triplet and external fourth")
	}
	if CountType(g.Hands[0], w[7]) != 0 || !g.Discards[0].Claimed || g.Remaining() != remaining-1 || g.Turn != 0 || g.Scores != [4]int{3, -1, -1, -1} {
		t.Fatal("exposed kong did not remove three concealed tiles, claim the discard and draw one replacement")
	}
}

func TestExposedPungCanUpgradeWithOwnDrawnFourth(t *testing.T) {
	g := NewGame(testPlayers(), 1)
	w := g.Rules.BuildWall()
	g.Turn = 2
	g.Hands = [4][]Tile{{w[5], w[6], w[40]}, {w[44]}, {w[4]}, {w[48]}}
	// The fourth copy is drawn by seat 0 after the intervening three turns.
	for offset, tile := range []Tile{w[80], w[84], w[88], w[7], w[92]} {
		g.Wall[g.NextWall+offset] = tile
	}
	for _, action := range []struct {
		seat int
		kind string
		tile int
	}{
		{2, "play", w[4].ID}, {0, "peng", 0}, {0, "play", w[40].ID},
		{1, "play", w[44].ID}, {2, "play", w[84].ID}, {3, "play", w[48].ID},
	} {
		if err := g.Apply(action.seat, action.kind, action.tile); err != nil {
			t.Fatalf("%+v: %v", action, err)
		}
	}
	if g.Turn != 0 || g.LastDrawnID != w[7].ID {
		t.Fatal("fixture did not draw the fourth tile into the pung owner's hand")
	}
	found := false
	for _, option := range g.Options(0) {
		found = found || (option.Type == "bu_gang" && option.TileID == w[7].ID)
	}
	if !found {
		t.Fatal("own drawn fourth must retain the normal added-kong option")
	}
	remaining := g.Remaining()
	if err := g.Apply(0, "bu_gang", w[7].ID); err != nil {
		t.Fatal(err)
	}
	if len(g.Melds[0]) != 1 || g.Melds[0][0].Kind != "bu_gang" || len(g.Melds[0][0].Tiles) != 4 || g.Melds[0][0].FromSeat != 2 || g.Melds[0][0].Tiles[3] != w[7] {
		t.Fatal("own fourth did not upgrade the existing pung")
	}
	if CountType(g.Hands[0], w[7]) != 0 || g.Remaining() != remaining-1 || g.Scores != [4]int{3, -1, -1, -1} || g.LastDrawnID != w[92].ID {
		t.Fatal("added kong failed to remove the owned fourth or award exactly one replacement and score")
	}
}
