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
}

func (g *Game) MarshalCheckpoint() ([]byte, error) {
	return json.Marshal(gameCheckpoint{State: (*checkpointGame)(g), Sequence: g.actionSequence, Events: g.actionEvents, Replay: g.replay})
}

func RestoreCheckpoint(data []byte, rules RuleSet) (*Game, error) {
	var checkpoint gameCheckpoint
	if err := json.Unmarshal(data, &checkpoint); err != nil {
		return nil, err
	}
	g := (*Game)(checkpoint.State)
	if g == nil || g.Epoch < 1 || g.Turn < 0 || g.Turn >= 4 || g.Dealer < 0 || g.Dealer >= 4 ||
		g.Rules.ID != rules.ID || g.Rules.Version != rules.Version ||
		g.NextWall < 0 || g.NextWall > len(g.Wall) || len(g.Wall) != len(rules.BuildWall()) ||
		(g.Phase != PhaseTurn && g.Phase != PhaseReaction && g.Phase != PhaseFinished) {
		return nil, errors.New("无效的麻将牌局快照")
	}
	g.Rules = rules
	g.actionSequence, g.actionEvents = checkpoint.Sequence, checkpoint.Events
	g.replay = checkpoint.Replay
	return g, nil
}
