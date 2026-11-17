package guiyang

import (
	"encoding/json"
	"reflect"
	"slices"
	"testing"
)

func TestReplayRoundReconstructsCommittedBoard(t *testing.T) {
	game := NewGame(testPlayers(), 17)
	if game.SettlementReplay() != nil {
		t.Fatal("live replay must stay private")
	}
	for range 8 {
		game.Timeout()
	}
	activeCheckpoint, err := game.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	game, err = RestoreCheckpoint(activeCheckpoint, game.Rules)
	if err != nil || game.SettlementReplay() != nil {
		t.Fatalf("active checkpoint exposed replay or failed to restore: %v", err)
	}
	for i := 0; game.Phase != PhaseFinished && i < 120; i++ {
		game.Timeout()
	}
	replay := game.SettlementReplay()
	if replay == nil || len(replay.Events) <= actionEventHistory {
		t.Fatal("full round journal did not retain opening moves")
	}
	board, err := replay.Project(len(replay.Events))
	if err != nil || !reflect.DeepEqual(board.Discards, game.Discards) || board.Reason != game.Reason {
		t.Fatalf("journal did not reconstruct final board: %v", err)
	}
	initial, err := replay.Project(0)
	if err != nil || len(initial.Discards) > 0 || initial.Reason != "" {
		t.Fatal("zero-step replay was not empty")
	}
	checkpoint, err := game.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	restored, err := RestoreCheckpoint(checkpoint, game.Rules)
	if err != nil || !reflect.DeepEqual(restored.SettlementReplay(), replay) {
		t.Fatalf("checkpoint did not retain journal: %v", err)
	}
	var old map[string]json.RawMessage
	if err := json.Unmarshal(checkpoint, &old); err != nil {
		t.Fatal(err)
	}
	delete(old, "Replay")
	legacy, err := json.Marshal(old)
	if err != nil {
		t.Fatal(err)
	}
	restored, err = RestoreCheckpoint(legacy, game.Rules)
	if err != nil || restored.SettlementReplay() != nil {
		t.Fatal("legacy checkpoint invented replay")
	}
}

func TestReplayMasksConcealedKongAndTracksPublicMeldUpgrade(t *testing.T) {
	rules := NewRuleSet()
	wall := rules.BuildWall()
	game := NewGame(testPlayers(), 1)
	game.Hands[0] = append([]Tile(nil), wall[:4]...)
	game.Hands[1] = append([]Tile(nil), wall[5:8]...)
	if err := game.anGang(0, wall[0].ID); err != nil {
		t.Fatal(err)
	}
	game.Hands[0] = []Tile{wall[4]}
	if err := game.play(0, wall[4].ID); err != nil {
		t.Fatal(err)
	}
	game.claim(1, "peng")
	game.PendingFrom, game.PendingTile, game.PendingKind = 1, wall[7], "bu_gang"
	game.completeBuGang()
	game.finishDraw()
	replay := game.SettlementReplay()
	if replay == nil || len(replay.Events) != 5 {
		t.Fatalf("missing replay: %+v", replay)
	}
	for _, tile := range replay.Events[0].Meld.Tiles {
		if tile != (Tile{}) {
			t.Fatal("concealed kong leaked physical tile")
		}
	}
	claimed, err := replay.Project(3)
	if err != nil || !claimed.Discards[0].Claimed || claimed.Melds[1][0].Kind != "peng" {
		t.Fatalf("discard claim did not project: %v", err)
	}
	upgraded, err := replay.Project(4)
	if err != nil || len(upgraded.Melds[1]) != 1 || upgraded.Melds[1][0].Kind != "bu_gang" || upgraded.Melds[1][0].Tiles[3] != wall[7] {
		t.Fatalf("public kong upgrade did not project in place: %v", err)
	}
	replay.Events[0].Meld.Tiles[0] = wall[0]
	if _, err := replay.Project(1); err == nil {
		t.Fatal("projection accepted exposed concealed tile")
	}
	if fresh := game.SettlementReplay(); fresh == nil || fresh.Events[0].Meld.Tiles[0] != (Tile{}) {
		t.Fatal("replay mutation altered stored journal")
	}
}

func TestReplayOmitsSubmittedAndRobbedKong(t *testing.T) {
	descriptor, _ := FindRuleDescriptor("basic_108", "1.0.0")
	game := NewGameWithRules(testPlayers(), 1, descriptor.RuleSet())
	wall := game.Rules.BuildWall()
	game.Turn = 2
	game.Hands = [4][]Tile{append([]Tile(nil), wall[72:74]...), nil, {wall[75]}, nil}
	if err := game.Apply(2, "play", wall[75].ID); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(0, "peng", 0); err != nil {
		t.Fatal(err)
	}
	game.Hands[0] = []Tile{wall[74]}
	for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 76, 80} {
		game.Hands[1] = append(game.Hands[1], wall[index])
	}
	if err := game.Apply(0, "bu_gang", wall[74].ID); err != nil || game.Phase != PhaseReaction || len(game.replay.Events) != 2 {
		t.Fatalf("uncommitted kong entered replay or opened no response: %v", err)
	}
	if err := game.Apply(1, "hu", 0); err != nil {
		t.Fatal(err)
	}
	replay := game.SettlementReplay()
	if replay == nil || len(replay.Events) != 3 || replay.Events[2].Kind != "hu" || replay.Events[2].Tile != nil || replay.Events[2].DiscardIndex != nil {
		t.Fatalf("robbed kong leaked a provisional event: %+v", replay)
	}
	board, err := replay.Project(3)
	if err != nil || board.Melds[0][0].Kind != "peng" || !reflect.DeepEqual(board.Winners, []int{1}) {
		t.Fatalf("robbed kong projection did not retain the original meld: %v", err)
	}
}

func TestLocalRobbedKongTileSurvivesCheckpointAndAppearsInReplay(t *testing.T) {
	game := newLocalGame(t, false)
	wall := game.Rules.BuildWall()
	game.Turn = 2
	game.Hands = [4][]Tile{slices.Clone(wall[72:75]), nil, {wall[75]}, nil}
	game.Melds[1] = []Meld{{Kind: "an_gang", FromSeat: 1, Tiles: slices.Clone(wall[60:64])}}
	game.recordReplayMeld(1, 0, nil)
	if err := game.Apply(2, "play", wall[75].ID); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(0, "peng", 0); err != nil {
		t.Fatal(err)
	}
	for _, index := range []int{0, 4, 8, 12, 16, 20, 36, 37, 76, 80} {
		game.Hands[1] = append(game.Hands[1], wall[index])
	}
	robbed := wall[74]
	if err := game.Apply(0, "bu_gang", robbed.ID); err != nil {
		t.Fatal(err)
	}
	if before := game.PublicBoard(); before.RobbedTile != nil {
		t.Fatal("unresolved upgrade exposed a robbed tile before the win")
	}
	if err := game.Apply(1, "hu", 0); err != nil {
		t.Fatal(err)
	}
	data, err := game.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	game, err = RestoreCheckpoint(data, game.Rules)
	if err != nil {
		t.Fatal(err)
	}
	if board := game.PublicBoard(); board.RobbedTile == nil || *board.RobbedTile != robbed {
		t.Errorf("restored public board omitted the winning tile %v: %+v", robbed, board.RobbedTile)
	}
	replay := game.SettlementReplay()
	if replay == nil {
		t.Fatal("settlement replay is missing")
	}
	board, err := replay.Project(len(replay.Events))
	if err != nil || board.RobbedTile == nil || *board.RobbedTile != robbed || board.Melds[0][0].Kind != "peng" {
		t.Fatalf("replay must display the winning tile and retain the existing pung: %+v, %v", board, err)
	}
}
