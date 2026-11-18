package guiyang

import (
	"encoding/json"
	"reflect"
	"slices"
	"testing"
)

// Check the wire contract, including array shape and privacy, independently
// of the concrete Go types used by SnapshotFor.
type snapshotFanItem struct {
	Name string `json:"name"`
	Fan  int    `json:"fan"`
}

type snapshotFanRow struct {
	Seat  int               `json:"seat"`
	Items []snapshotFanItem `json:"items"`
	Total int               `json:"total"`
}

func assertFanRows(t *testing.T, g *Game, want ...snapshotFanRow) {
	t.Helper()
	value, ok := g.SnapshotFor(3)["fan_breakdown"]
	if !ok {
		t.Fatal("missing participant settlement fan_breakdown")
	}
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	var got []snapshotFanRow
	if err := json.Unmarshal(data, &got); err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("fan_breakdown = %s (%v), want %+v", data, err, want)
	}
}

func assertNoSettlementReveal(t *testing.T, state any) {
	t.Helper()
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"settlement_hands", "fan_breakdown"} {
		if _, ok := fields[key]; ok {
			t.Errorf("unexpected %s in snapshot", key)
		}
	}
}

func assertSettlementHands(t *testing.T, g *Game, external Tile) {
	t.Helper()
	var original [4][]Tile
	for seat, held := range g.Hands {
		original[seat] = slices.Clone(held)
	}
	for viewer := range g.Players {
		state := g.SnapshotFor(viewer)
		hands, ok := state["settlement_hands"].([][]Tile)
		if !ok || len(hands) != 4 {
			t.Fatalf("seat %d received invalid settlement_hands: %#v", viewer, state["settlement_hands"])
		}
		for seat, held := range original {
			want := slices.Clone(held)
			if external.ID != 0 && slices.Contains(g.Winners, seat) {
				want = append(want, external)
			}
			SortHand(want)
			if hands[seat] == nil || !slices.Equal(hands[seat], want) {
				t.Fatalf("viewer %d seat %d settlement hand = %v, want %v", viewer, seat, hands[seat], want)
			}
			if len(hands[seat]) > 0 {
				hands[seat][0] = Tile{}
			}
		}
		if !slices.Equal(state["hand"].([]Tile), original[viewer]) {
			t.Fatal("mutating the settlement view changed the private hand")
		}
	}
	for seat, held := range original {
		if !slices.Equal(g.Hands[seat], held) {
			t.Fatalf("reading or editing settlement hands changed seat %d's game state", seat)
		}
	}
	assertNoSettlementReveal(t, g.PublicBoard())
}

func legacySettlementCheckpoint(t *testing.T, g *Game) *Game {
	t.Helper()
	old := *g
	old.ClaimedWinTile = nil // Omitted entirely by the checkpoint encoding.
	return restartTrial(t, &old)
}

func TestParticipantSettlementRejectsNonseatedViewers(t *testing.T) {
	g := newLocalGame(t, false)
	g.finishDraw()
	g.Players[3] = ""
	for _, seat := range []int{3, -1, 4} {
		assertNoSettlementReveal(t, g.SnapshotFor(seat))
	}
}

func TestParticipantSettlementMultipleWinnersAndActivePrivacy(t *testing.T) {
	for _, action := range []string{"play", "bu_gang"} {
		t.Run(action, func(t *testing.T) {
			g := newLocalGame(t, false)
			wall := g.Rules.BuildWall()
			winTile := wall[72]
			g.Hands = [4][]Tile{{winTile}, {}, {}, {wall[107], wall[40]}}
			for i, seat := range []int{1, 2} {
				for _, index := range []int{80 + i, 76 + i, 36 + 2*i, 37 + 2*i, 20 + i, 16 + i, 12 + i, 8 + i, 4 + i, i} {
					g.Hands[seat] = append(g.Hands[seat], wall[index])
				}
				start := 48 + i*4
				g.Melds[seat] = []Meld{{Kind: "an_gang", FromSeat: seat, Tiles: wall[start : start+4]}}
			}
			if action == "bu_gang" {
				g.Melds[0] = []Meld{{Kind: "peng", FromSeat: 3, Tiles: wall[73:76]}}
			}
			assertNoSettlementReveal(t, g.SnapshotFor(3))
			if err := g.Apply(0, action, winTile.ID); err != nil {
				t.Fatal(err)
			}
			if err := g.Apply(2, "hu", 0); err != nil {
				t.Fatal(err)
			}
			assertNoSettlementReveal(t, g.SnapshotFor(1))
			assertNoSettlementReveal(t, g.PublicBoard())
			if err := g.Apply(1, "hu", 0); err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(g.Winners, []int{1, 2}) {
				t.Fatalf("unexpected winners: %v", g.Winners)
			}
			for _, settled := range []*Game{g, restartTrial(t, g), legacySettlementCheckpoint(t, g)} {
				assertSettlementHands(t, settled, winTile)
				melds := settled.SnapshotFor(3)["melds"].([][]Meld)
				if !slices.Equal(melds[1][0].Tiles, make([]Tile, 4)) {
					t.Fatal("settlement changed concealed kong masking")
				}
				want := []snapshotFanItem{{"平胡", 1}}
				total := 1
				if action == "bu_gang" {
					want = append(want, snapshotFanItem{"抢杠胡", 1})
					total++
				}
				assertFanRows(t, settled, snapshotFanRow{1, want, total}, snapshotFanRow{2, want, total})
			}
		})
	}
}

func TestParticipantSettlementLegacyRobbedKong(t *testing.T) {
	rule, _ := FindRuleDescriptor("basic_108", "1.0.0")
	g := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
	wall := g.Rules.BuildWall()
	winTile := wall[74]
	g.Hands = [4][]Tile{{winTile}, {}, {}, {}}
	for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 76, 80} {
		g.Hands[1] = append(g.Hands[1], wall[index])
	}
	g.Melds[0] = []Meld{{Kind: "peng", FromSeat: 3, Tiles: []Tile{wall[72], wall[73], wall[75]}}}
	g.Melds[2] = []Meld{{Kind: "peng", FromSeat: 0, Tiles: wall[52:55]}}
	g.Discards = []Discard{{Seat: 3, Tile: wall[75], Claimed: true}, {Seat: 0, Tile: wall[52], Claimed: true}}
	// Account for each dealt tile. The legacy checkpoint stored the robbed
	// tile only in the original wall, and its last discard was an older pung.
	g.Wall = nil
	for seat, hand := range g.Hands {
		g.Wall = append(g.Wall, hand...)
		for _, meld := range g.Melds[seat] {
			g.Wall = append(g.Wall, meld.Tiles...)
		}
	}
	g.NextWall = len(g.Wall)
	for _, tile := range wall {
		if !slices.Contains(g.Wall, tile) {
			g.Wall = append(g.Wall, tile)
		}
	}
	if err := g.Apply(0, "bu_gang", winTile.ID); err != nil {
		t.Fatal(err)
	}
	if err := g.Apply(1, "hu", 0); err != nil {
		t.Fatal(err)
	}
	for _, settled := range []*Game{g, restartTrial(t, g), legacySettlementCheckpoint(t, g)} {
		assertSettlementHands(t, settled, winTile)
		if _, hasFan := settled.SnapshotFor(0)["fan_breakdown"]; hasFan {
			t.Fatal("points-only rules published a fan value")
		}
	}
}
