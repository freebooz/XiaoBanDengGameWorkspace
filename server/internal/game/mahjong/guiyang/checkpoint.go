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
	return g, nil
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
