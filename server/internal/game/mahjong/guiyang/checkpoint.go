package guiyang

import (
	"encoding/json"
	"errors"
)

// Private server state. Never use this encoding in a player snapshot.
type checkpointGame Game

type gameCheckpoint struct {
	State    *checkpointGame
	Sequence int
	Events   []ActionEvent
	Replay   *Replay `json:",omitempty"`
	RuleKey  string  `json:",omitempty"`
}

func (g *Game) MarshalCheckpoint() ([]byte, error) {
	checkpoint := gameCheckpoint{State: (*checkpointGame)(g), Sequence: g.actionSequence, Events: g.actionEvents, Replay: g.replay}
	if g.Rules.Dingque() || g.Rules.localRules() {
		checkpoint.RuleKey = g.Rules.effectiveKey()
	}
	return json.Marshal(checkpoint)
}

func RestoreCheckpoint(data []byte, rules RuleSet) (*Game, error) {
	var checkpoint gameCheckpoint
	if err := json.Unmarshal(data, &checkpoint); err != nil {
		return nil, err
	}
	g := (*Game)(checkpoint.State)
	if g == nil || g.Epoch < 1 || g.Turn < 0 || g.Turn >= 4 || g.Dealer < 0 || g.Dealer >= 4 ||
		g.Rules.ID != rules.ID || g.Rules.Version != rules.Version ||
		((rules.Dingque() || rules.localRules()) && checkpoint.RuleKey != rules.effectiveKey()) ||
		g.NextWall < 0 || g.NextWall > len(g.Wall) || len(g.Wall) != len(rules.BuildWall()) ||
		(g.Phase != PhaseTurn && g.Phase != PhaseReaction && g.Phase != PhaseFinished && g.Phase != PhaseDingque) ||
		!g.validTrialCheckpoint(rules) || rules.localRules() != (g.Local != nil) ||
		(rules.localRules() && g.ScoreBreakdown == nil) {
		return nil, errors.New("无效的麻将牌局快照")
	}
	g.Rules = rules
	g.actionSequence, g.actionEvents = checkpoint.Sequence, checkpoint.Events
	g.replay = checkpoint.Replay
	if g.Phase == PhaseFinished && len(g.Winners) > 0 && g.WinFrom >= 0 && g.ClaimedWinTile == nil {
		if tile := g.legacyClaimedWinTile(); tile.ID > 0 {
			g.ClaimedWinTile = &tile
		}
	}
	return g, nil
}

// Older checkpoints did not keep the winning tile after clearing the claim
// window. In a robbed kong under a points-only preset, the fourth tile left
// the feeder's hand without entering any hand, meld or discard pile.
func (g *Game) legacyClaimedWinTile() Tile {
	if g.RobbedTile != nil {
		return *g.RobbedTile
	}
	accounted := map[int]bool{g.FlippedJi.ID: true}
	for seat, hand := range g.Hands {
		for _, tile := range hand {
			accounted[tile.ID] = true
		}
		for _, meld := range g.Melds[seat] {
			for _, tile := range meld.Tiles {
				accounted[tile.ID] = true
			}
		}
	}
	if n := len(g.Discards); n > 0 {
		last := g.Discards[n-1]
		if last.Claimed && last.Seat == g.WinFrom && !accounted[last.Tile.ID] {
			return last.Tile
		}
	}
	for _, discard := range g.Discards {
		accounted[discard.Tile.ID] = true
	}
	var missing Tile
	for _, tile := range g.Wall[:g.NextWall] {
		if !accounted[tile.ID] {
			if missing.ID != 0 {
				return Tile{}
			}
			missing = tile
		}
	}
	return missing
}

func (g *Game) validTrialCheckpoint(rules RuleSet) bool {
	if !rules.Dingque() {
		return g.Phase != PhaseDingque && g.MissingSuits == nil && g.LastKongScore == nil && len(g.ScoreLedger) == 0
	}
	if g.MissingSuits == nil || g.ScoreBreakdown == nil {
		return false
	}
	chosen := 0
	for _, suit := range *g.MissingSuits {
		if suit == "" {
			continue
		}
		if !validMissingSuit(suit) {
			return false
		}
		chosen++
	}
	if (g.Phase == PhaseDingque) == (chosen == 4) {
		return false
	}
	receipt := g.LastKongScore
	if receipt == nil {
		return true
	}
	if (g.Phase != PhaseTurn && g.Phase != PhaseReaction) || receipt.Seat != g.Turn || receipt.Start < 0 || receipt.End <= receipt.Start || receipt.End != len(g.ScoreLedger) {
		return false
	}
	for _, entry := range g.ScoreLedger[receipt.Start:receipt.End] {
		if entry.Category != "gang" || entry.Receiver != receipt.Seat || entry.Payer < 0 || entry.Payer >= 4 || entry.Payer == receipt.Seat || entry.Amount != 3 {
			return false
		}
	}
	return true
}
