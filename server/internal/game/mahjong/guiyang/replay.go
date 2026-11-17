package guiyang

import (
	"errors"
	"slices"
	"strings"
)

const (
	ReplayVersion = 1
	// A 108-tile round cannot spend 256 turns on committed discards/melds.
	// If that invariant ever changes, omit the replay instead of truncating it.
	MaxReplayEvents = 256
)

type Replay struct {
	Version        int             `json:"version"`
	Dealer         int             `json:"dealer"`
	Events         []ReplayEvent   `json:"events"`
	RuleKey        string          `json:"rule_key,omitempty"`
	ScoreTransfers []ScoreTransfer `json:"score_transfers,omitempty"`
	HuDetails      []HuDetail      `json:"hu_details,omitempty"`
	ReadySeats     []int           `json:"ready_seats,omitempty"`
}

type ReplayEvent struct {
	Sequence     int        `json:"sequence"`
	Seat         int        `json:"seat"`
	Kind         string     `json:"kind"`
	Tile         *Tile      `json:"tile,omitempty"`
	Meld         *Meld      `json:"meld,omitempty"`
	DiscardIndex *int       `json:"discard_index,omitempty"`
	MeldIndex    *int       `json:"meld_index,omitempty"`
	MissingSuits *[4]string `json:"missing_suits,omitempty"`
	RobbedTile   *Tile      `json:"robbed_tile,omitempty"`
}

type ReplayBoard struct {
	Discards       []Discard       `json:"discards"`
	Melds          [4][]Meld       `json:"melds"`
	Winners        []int           `json:"winners"`
	Reason         string          `json:"reason"`
	MissingSuits   *[4]string      `json:"missing_suits,omitempty"`
	RobbedTile     *Tile           `json:"robbed_tile,omitempty"`
	ScoreTransfers []ScoreTransfer `json:"score_transfers,omitempty"`
	HuDetails      []HuDetail      `json:"hu_details,omitempty"`
	ReadySeats     []int           `json:"ready_seats,omitempty"`
}

func (g *Game) recordReplay(event ReplayEvent) {
	if g.replay == nil {
		return
	}
	if len(g.replay.Events) >= MaxReplayEvents {
		g.replay = nil
		return
	}
	event.Sequence = len(g.replay.Events) + 1
	g.replay.Events = append(g.replay.Events, event)
}

func publicReplayMeld(meld Meld) Meld {
	if meld.Kind == "an_gang" {
		meld.Tiles = make([]Tile, len(meld.Tiles))
	} else {
		meld.Tiles = slices.Clone(meld.Tiles)
	}
	return meld
}

func (g *Game) recordReplayMeld(seat, meldIndex int, discardIndex *int) {
	meld := publicReplayMeld(g.Melds[seat][meldIndex])
	g.recordReplay(ReplayEvent{Seat: seat, Kind: meld.Kind, Meld: &meld, MeldIndex: &meldIndex, DiscardIndex: discardIndex})
}

// SettlementReplay publishes a detached, complete public journal only after
// the final board has been validated against the committed engine state.
func (g *Game) SettlementReplay() *Replay {
	if g.Phase != PhaseFinished || g.replay == nil {
		return nil
	}
	result := *g.replay
	if g.Rules.localRules() || g.Rules.Dingque() {
		result.RuleKey = g.Rules.effectiveKey()
	}
	board, err := result.Project(len(result.Events))
	if err != nil || result.Dealer != g.Dealer || board.Reason != g.Reason ||
		!slices.Equal(board.Discards, g.Discards) || !slices.Equal(board.Winners, g.Winners) || !sameOptionalTile(board.RobbedTile, g.RobbedTile) {
		return nil
	}
	if g.Rules.Dingque() && (board.MissingSuits == nil || *board.MissingSuits != *g.MissingSuits) {
		return nil
	}
	for seat, melds := range board.Melds {
		if len(melds) != len(g.Melds[seat]) {
			return nil
		}
		for index, meld := range melds {
			want := publicReplayMeld(g.Melds[seat][index])
			if meld.Kind != want.Kind || meld.FromSeat != want.FromSeat || !slices.Equal(meld.Tiles, want.Tiles) {
				return nil
			}
		}
	}
	if g.Rules.localRules() {
		result.HuDetails = g.SettlementHuDetails()
		result.ReadySeats = g.SettlementReadySeats()
	}
	if g.Rules.Dingque() {
		result.ScoreTransfers = g.SettlementScoreTransfers()
		if result.ScoreTransfers == nil {
			return nil
		}
	}
	result.Events = slices.Clone(result.Events)
	for index := range result.Events {
		event := &result.Events[index]
		if event.Tile != nil {
			tile := *event.Tile
			event.Tile = &tile
		}
		if event.Meld != nil {
			meld := publicReplayMeld(*event.Meld)
			event.Meld = &meld
		}
		if event.DiscardIndex != nil {
			index := *event.DiscardIndex
			event.DiscardIndex = &index
		}
		if event.MeldIndex != nil {
			index := *event.MeldIndex
			event.MeldIndex = &index
		}
		if event.MissingSuits != nil {
			suits := *event.MissingSuits
			event.MissingSuits = &suits
		}
		if event.RobbedTile != nil {
			tile := *event.RobbedTile
			event.RobbedTile = &tile
		}
	}
	return &result
}

// Project applies a prefix of the public journal. Step zero is the empty
// table; step n includes exactly the first n committed events.
func (r Replay) Project(step int) (ReplayBoard, error) {
	if r.Version != ReplayVersion || r.Dealer < 0 || r.Dealer >= 4 || len(r.Events) > MaxReplayEvents || step < 0 || step > len(r.Events) {
		return ReplayBoard{}, errors.New("invalid Mahjong replay step or header")
	}
	board := ReplayBoard{Discards: []Discard{}, Winners: []int{}}
	for seat := range board.Melds {
		board.Melds[seat] = []Meld{}
	}
	localRules := strings.HasPrefix(r.RuleKey, "guiyang@"+LocalRuleVersion+"/")
	for index, event := range r.Events[:step] {
		if event.Sequence != index+1 || !board.apply(event, localRules) {
			return ReplayBoard{}, errors.New("invalid committed Mahjong replay event")
		}
	}
	if step == len(r.Events) && board.Reason != "" {
		board.ScoreTransfers = slices.Clone(r.ScoreTransfers)
		board.HuDetails = slices.Clone(r.HuDetails)
		board.ReadySeats = slices.Clone(r.ReadySeats)
	}
	return board, nil
}

func (b *ReplayBoard) apply(event ReplayEvent, localRules bool) bool {
	if b.Reason != "" && (b.Reason != "hu" || event.Kind != "hu") {
		return false
	}
	if event.Kind == PhaseDingque {
		if event.Sequence != 1 || b.MissingSuits != nil || event.Seat != -1 || event.Tile != nil || event.Meld != nil || event.DiscardIndex != nil || event.MeldIndex != nil || event.MissingSuits == nil || event.RobbedTile != nil {
			return false
		}
		for _, suit := range *event.MissingSuits {
			if !validMissingSuit(suit) {
				return false
			}
		}
		suits := *event.MissingSuits
		b.MissingSuits = &suits
		return true
	}
	if event.MissingSuits != nil || (event.RobbedTile != nil && event.Kind != "hu") {
		return false
	}
	if event.Kind == "wall_exhausted" {
		if event.Seat != -1 || event.Tile != nil || event.Meld != nil || event.DiscardIndex != nil || event.MeldIndex != nil {
			return false
		}
		b.Reason = event.Kind
		return true
	}
	if event.Seat < 0 || event.Seat >= 4 {
		return false
	}
	switch event.Kind {
	case "play":
		if event.Tile == nil || !validReplayTile(*event.Tile) || event.Meld != nil || event.MeldIndex != nil || event.DiscardIndex == nil || *event.DiscardIndex != len(b.Discards) {
			return false
		}
		b.Discards = append(b.Discards, Discard{Seat: event.Seat, Tile: *event.Tile})
	case "hu":
		if event.Tile != nil || event.Meld != nil || event.MeldIndex != nil || slices.Contains(b.Winners, event.Seat) {
			return false
		}
		if event.RobbedTile != nil {
			if (!localRules && b.MissingSuits == nil) || event.DiscardIndex != nil || !validReplayTile(*event.RobbedTile) || (b.RobbedTile != nil && *b.RobbedTile != *event.RobbedTile) {
				return false
			}
			tile := *event.RobbedTile
			b.RobbedTile = &tile
		}
		if event.DiscardIndex != nil {
			index := *event.DiscardIndex
			if index < 0 || index != len(b.Discards)-1 || b.Discards[index].Seat == event.Seat {
				return false
			}
			b.Discards[index].Claimed = true
		}
		b.Winners = append(b.Winners, event.Seat)
		b.Reason = event.Kind
	case "peng", "ming_gang", "an_gang", "bu_gang":
		return b.applyMeld(event)
	default:
		return false
	}
	return true
}

func sameOptionalTile(a, b *Tile) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func (b *ReplayBoard) applyMeld(event ReplayEvent) bool {
	if event.Tile != nil || event.Meld == nil || event.MeldIndex == nil || event.Meld.Kind != event.Kind {
		return false
	}
	meld := *event.Meld
	count := 4
	if event.Kind == "peng" {
		count = 3
	}
	if len(meld.Tiles) != count || meld.FromSeat < 0 || meld.FromSeat >= 4 {
		return false
	}
	for _, tile := range meld.Tiles {
		if event.Kind == "an_gang" {
			if tile != (Tile{}) {
				return false
			}
		} else if !validReplayTile(tile) || !sameType(meld.Tiles[0], tile) {
			return false
		}
	}
	melds := b.Melds[event.Seat]
	index := *event.MeldIndex
	if event.Kind == "bu_gang" {
		if event.DiscardIndex != nil || index < 0 || index >= len(melds) || melds[index].Kind != "peng" || melds[index].FromSeat != meld.FromSeat ||
			!slices.Equal(melds[index].Tiles, meld.Tiles[:3]) {
			return false
		}
		melds[index] = publicReplayMeld(meld)
		return true
	}
	if index != len(melds) {
		return false
	}
	if event.Kind == "an_gang" {
		if event.DiscardIndex != nil || meld.FromSeat != event.Seat {
			return false
		}
	} else {
		if event.DiscardIndex == nil || *event.DiscardIndex < 0 || *event.DiscardIndex != len(b.Discards)-1 || meld.FromSeat == event.Seat {
			return false
		}
		discard := &b.Discards[*event.DiscardIndex]
		if discard.Claimed || discard.Seat != meld.FromSeat || !slices.Contains(meld.Tiles, discard.Tile) {
			return false
		}
		discard.Claimed = true
	}
	b.Melds[event.Seat] = append(melds, publicReplayMeld(meld))
	return true
}

func validReplayTile(tile Tile) bool {
	return tile.ID >= 1 && tile.ID <= 108 && validType(tile)
}
