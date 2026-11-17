package guiyang

import "errors"

var missingSuitOrder = [...]string{"wan", "tong", "tiao"}

func validMissingSuit(suit string) bool {
	return validType(Tile{Suit: suit, Rank: 1})
}

func (g *Game) missingSuitOptions(seat int) []ActionOption {
	if g.Players[seat] == "" || (*g.MissingSuits)[seat] != "" {
		return nil
	}
	return []ActionOption{{Type: PhaseDingque, Suit: "wan"}, {Type: PhaseDingque, Suit: "tong"}, {Type: PhaseDingque, Suit: "tiao"}}
}

// ChooseMissingSuit commits one private choice in the current opening window.
func (g *Game) ChooseMissingSuit(seat int, suit string) error {
	if seat < 0 || seat >= 4 || g.Players[seat] == "" {
		return errors.New("座位无效")
	}
	if g.Phase != PhaseDingque || g.MissingSuits == nil {
		return errors.New("当前阶段不能选择定缺")
	}
	if !validMissingSuit(suit) {
		return errors.New("定缺花色无效")
	}
	choices := g.MissingSuits
	if (*choices)[seat] != "" {
		return errors.New("该座位已经定缺")
	}
	(*choices)[seat] = suit
	for _, choice := range choices {
		if choice == "" {
			return nil
		}
	}
	g.Phase = PhaseTurn
	g.Epoch++
	revealed := *choices
	g.recordReplay(ReplayEvent{Seat: -1, Kind: PhaseDingque, MissingSuits: &revealed})
	return nil
}

// DefaultMissingSuit picks the least represented suit, with ties in wall order.
func (g *Game) DefaultMissingSuit(seat int) string {
	if seat < 0 || seat >= 4 || !g.Rules.Dingque() {
		return ""
	}
	counts := make(map[string]int, len(missingSuitOrder))
	for _, tile := range g.Hands[seat] {
		counts[tile.Suit]++
	}
	chosen := missingSuitOrder[0]
	for _, suit := range missingSuitOrder[1:] {
		if counts[suit] < counts[chosen] {
			chosen = suit
		}
	}
	return chosen
}

func (g *Game) isMissingSuit(seat int, tile Tile) bool {
	return g.MissingSuits != nil && (*g.MissingSuits)[seat] == tile.Suit
}

func (g *Game) canDiscard(seat int, tile Tile) bool {
	if g.MissingSuits == nil || g.isMissingSuit(seat, tile) {
		return true
	}
	for _, held := range g.Hands[seat] {
		if g.isMissingSuit(seat, held) {
			return false
		}
	}
	return true
}

func (g *Game) winningHand(seat int, hand []Tile) bool {
	if g.Rules.Dingque() {
		return g.trialHandScore(seat, hand) > 0
	}
	ok, _ := g.Rules.CanHuHand(hand, len(g.Melds[seat]))
	return ok
}

func (g *Game) canClaimHu(seat int, tile Tile) bool {
	if !g.allowsLocalReaction(seat, "hu", tile) {
		return false
	}
	if g.Rules.requiresKongToClaim() && !g.hasCompletedGang(seat) {
		return false
	}
	hand := append(append([]Tile(nil), g.Hands[seat]...), tile)
	return g.winningHand(seat, hand)
}

func (g *Game) validReaction(seat int, action string) bool {
	if g.Phase != PhaseReaction || seat < 0 || seat >= 4 || g.PendingFrom < 0 || g.PendingFrom >= 4 ||
		seat == g.PendingFrom || g.PendingFrom != g.Turn {
		return false
	}
	// A cached/restored candidate is a window membership, not proof that the
	// current tiles still permit the action. Pass remains usable to drain it.
	if action == "pass" {
		return true
	}
	if !g.validPendingSource() {
		return false
	}
	if !g.allowsLocalReaction(seat, action, g.PendingTile) {
		return false
	}
	switch action {
	case "hu":
		return g.canClaimHu(seat, g.PendingTile) &&
			(g.PendingKind == "discard" || (g.PendingKind == "bu_gang" && g.Rules.effectiveOptions().RobKong))
	case "peng":
		return g.PendingKind == "discard" && !g.isMissingSuit(seat, g.PendingTile) && g.Rules.CanPeng(g.Hands[seat], g.PendingTile)
	case "ming_gang":
		return g.PendingKind == "discard" && !g.isMissingSuit(seat, g.PendingTile) && g.Remaining() > 0 &&
			g.Rules.CanGangFromDiscard(g.Hands[seat], g.PendingTile)
	default:
		return false
	}
}

func (g *Game) validPendingSource() bool {
	if g.PendingTile.ID <= 0 || !validType(g.PendingTile) {
		return false
	}
	switch g.PendingKind {
	case "discard":
		if len(g.Discards) == 0 {
			return false
		}
		last := g.Discards[len(g.Discards)-1]
		return !last.Claimed && last.Seat == g.PendingFrom && last.Tile == g.PendingTile
	case "bu_gang":
		tile, held := g.findTile(g.PendingFrom, g.PendingTile.ID)
		if !held || tile != g.PendingTile {
			return false
		}
		for _, meld := range g.Melds[g.PendingFrom] {
			if meld.Kind == "peng" && len(meld.Tiles) == 3 && sameType(meld.Tiles[0], tile) {
				return true
			}
		}
	}
	return false
}
