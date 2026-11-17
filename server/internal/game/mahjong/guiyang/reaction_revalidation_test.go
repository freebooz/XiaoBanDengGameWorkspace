package guiyang

import (
	"bytes"
	"testing"
)

func reactionFixture(rule RuleSet) *Game {
	g := NewGameWithRules(testPlayers(), 17, rule)
	w := rule.BuildWall()
	g.Phase, g.Turn = PhaseReaction, 0
	g.PendingTile, g.PendingFrom, g.PendingKind = w[64], 0, "discard" // Eight dots.
	g.Discards = []Discard{{Seat: 0, Tile: g.PendingTile}}
	g.Hands = [4][]Tile{}
	// Three FIVE dots cannot claim an EIGHT dots discard.
	for _, i := range []int{52, 53, 54, 0, 4, 8, 16, 24, 32, 72, 80, 88, 96} {
		g.Hands[1] = append(g.Hands[1], w[i])
	}
	g.Candidates, g.Submitted = map[int][]string{1: {"peng", "ming_gang", "hu"}}, map[int]string{}
	if g.MissingSuits != nil {
		*g.MissingSuits = [4]string{"tiao", "wan", "wan", "wan"}
	}
	return g
}

func assertRejectedReaction(t *testing.T, g *Game, action string) {
	t.Helper()
	for _, option := range g.Options(1) {
		if option.Type == action {
			t.Errorf("invalid %s is advertised for pending %v and hand %v", action, g.PendingTile, g.Hands[1])
		}
	}
	for _, option := range g.SnapshotFor(1)["options"].([]ActionOption) {
		if option.Type == action {
			t.Errorf("private snapshot exposes invalid %s", action)
		}
	}
	before, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	if err := g.Apply(1, action, 0); err == nil {
		t.Errorf("invalid %s command accepted", action)
	}
	after, err := g.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Errorf("invalid %s changed authoritative state", action)
	}
}

func TestReactionRevalidatesCachedOptionsAgainstCurrentTiles(t *testing.T) {
	for _, descriptor := range RuleDescriptors() {
		t.Run(descriptor.ID+"@"+descriptor.Version, func(t *testing.T) {
			for _, action := range []string{"peng", "ming_gang", "hu"} {
				t.Run(action, func(t *testing.T) {
					g := reactionFixture(descriptor.RuleSet())
					if action == "hu" && descriptor.RequiresKongToClaim {
						w := g.Rules.BuildWall()
						g.Melds[1] = []Meld{{Kind: "an_gang", Tiles: w[100:104], FromSeat: 1}}
						g.Hands[1] = g.Hands[1][:10]
					}
					// Restoring a cached response must not turn it into authority.
					data, err := g.MarshalCheckpoint()
					if err != nil {
						t.Fatal(err)
					}
					g, err = RestoreCheckpoint(data, descriptor.RuleSet())
					if err != nil {
						t.Fatal(err)
					}
					assertRejectedReaction(t, g, action)
				})
			}
		})
	}
}

func TestReactionRevalidatesClaimSourceAndReplacementWall(t *testing.T) {
	rule, _ := FindRuleDescriptor("basic_108", "1.0.0")
	for _, test := range []struct {
		name   string
		change func(*Game)
	}{
		{"wrong_suit", func(g *Game) { g.PendingTile.Suit = "wan"; g.Discards[0].Tile = g.PendingTile }},
		{"only_two_held", func(g *Game) { g.Hands[1] = g.Hands[1][1:] }},
		{"no_replacement", func(g *Game) { g.NextWall = len(g.Wall) }},
		{"claimed_discard", func(g *Game) { g.Discards[0].Claimed = true }},
		{"old_discard", func(g *Game) { g.Discards[0].Tile = g.Rules.BuildWall()[64] }},
		{"wrong_feeder", func(g *Game) { g.Discards[0].Seat = 2 }},
		{"upgrade_is_not_discard", func(g *Game) { g.PendingKind = "bu_gang" }},
	} {
		t.Run(test.name, func(t *testing.T) {
			g := reactionFixture(rule.RuleSet())
			g.PendingTile = g.Rules.BuildWall()[55]
			g.Discards[0].Tile = g.PendingTile
			test.change(g)
			assertRejectedReaction(t, g, "ming_gang")
		})
	}
}

func TestReactionStillOffersMatchingKongAndWinningHand(t *testing.T) {
	for _, descriptor := range RuleDescriptors() {
		t.Run(descriptor.ID+"@"+descriptor.Version, func(t *testing.T) {
			g := reactionFixture(descriptor.RuleSet())
			w := g.Rules.BuildWall()
			g.PendingTile = w[55]
			g.Discards[0].Tile = g.PendingTile
			g.Candidates[1] = []string{"peng", "ming_gang"}
			found := false
			for _, option := range g.Options(1) {
				found = found || option.Type == "ming_gang"
			}
			if !found {
				t.Fatal("matching concealed triplet lost its kong")
			}
			if err := g.Apply(1, "ming_gang", 0); err != nil {
				t.Fatal(err)
			}
			if len(g.Melds[1]) != 1 || len(g.Melds[1][0].Tiles) != 4 {
				t.Fatal("legal kong not committed")
			}
		})
	}
}

// Physically compatible competitors: a matching triplet/pair and two sequence
// waits. A pong and a kong in different hands cannot both claim the same tile.
func priorityReactionFixture(action string) *Game {
	descriptor, _ := FindRuleDescriptor("basic_108", "1.0.0")
	g := NewGameWithRules(testPlayers(), 1, descriptor.RuleSet())
	w := g.Rules.BuildWall()
	g.Phase, g.Turn = PhaseReaction, 0
	g.PendingTile, g.PendingFrom, g.PendingKind = w[16], 0, "discard"
	g.Discards = []Discard{{Seat: 0, Tile: g.PendingTile}}
	g.Hands = [4][]Tile{}
	for copy, seat := range []int{1, 3} {
		for _, index := range []int{8, 12, 36, 40, 44, 72, 76, 80, 96, 100, 104, 68, 69} {
			if index == 68 || index == 69 {
				index += copy * 2
			} else {
				index += copy
			}
			g.Hands[seat] = append(g.Hands[seat], w[index])
		}
	}
	g.Hands[2] = []Tile{w[17], w[18]}
	if action == "ming_gang" {
		g.Hands[2] = append(g.Hands[2], w[19])
	}
	for _, index := range []int{0, 1, 4, 5, 20, 24, 28, 32, 48, 52, 56} {
		if len(g.Hands[2]) == 13 {
			break
		}
		g.Hands[2] = append(g.Hands[2], w[index])
	}
	g.Candidates = map[int][]string{1: {"hu"}, 2: {action}, 3: {"hu"}}
	g.Submitted = map[int]string{}
	return g
}
