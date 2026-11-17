package guiyang

type trialPattern struct {
	points int
	name   string
}

func (g *Game) trialHandScore(seat int, hand []Tile) int {
	return g.trialHandPattern(seat, hand).points
}

func (g *Game) trialHandPattern(seat int, hand []Tile) trialPattern {
	melds := g.Melds[seat]
	ok, _ := g.Rules.CanHuHand(hand, len(melds))
	if !ok {
		return trialPattern{}
	}
	suit := hand[0].Suit
	pure := true
	for _, tile := range hand {
		if g.isMissingSuit(seat, tile) {
			return trialPattern{}
		}
		pure = pure && tile.Suit == suit
	}
	for _, meld := range melds {
		for _, tile := range meld.Tiles {
			if g.isMissingSuit(seat, tile) {
				return trialPattern{}
			}
			pure = pure && tile.Suit == suit
		}
	}
	var counts [27]int
	for _, tile := range hand {
		counts[tileIndex(tile)]++
	}
	pairs, pairRemainders, hasQuad := 0, 0, false
	allTriples := true
	for _, count := range counts {
		pairs += count / 2
		hasQuad = hasQuad || count == 4
		switch count {
		case 2:
			pairRemainders++
		case 1, 4:
			allTriples = false
		}
	}
	sevenPairs := len(melds) == 0 && pairs == 7
	dragon := sevenPairs && hasQuad
	switch {
	case pure && dragon:
		return trialPattern{20, "清龙七对"}
	case pure:
		return trialPattern{10, "清一色"}
	case dragon:
		return trialPattern{10, "龙七对"}
	case sevenPairs:
		return trialPattern{5, "七对"}
	case allTriples && pairRemainders == 1:
		return trialPattern{5, "大对子"}
	default:
		return trialPattern{3, "平胡"}
	}
}

type kongScoreReceipt struct {
	Seat  int
	Start int
	End   int
}

func (g *Game) awardTrialGang(seat int, kind string, from int) {
	start := len(g.ScoreLedger)
	if kind == "ming_gang" {
		g.recordScore(scoreGang, from, seat, 3, kind, "")
	} else {
		for payer := range g.Players {
			if payer != seat {
				g.recordScore(scoreGang, payer, seat, 3, kind, "")
			}
		}
	}
	g.LastKongScore = &kongScoreReceipt{Seat: seat, Start: start, End: len(g.ScoreLedger)}
}

func (g *Game) revokeHeatCannonKong(from int) {
	receipt := g.LastKongScore
	if receipt == nil || receipt.Seat != from {
		return
	}
	for _, entry := range g.ScoreLedger[receipt.Start:receipt.End] {
		g.recordScore(scoreGang, entry.Receiver, entry.Payer, entry.Amount, "revoke_gang_heat_cannon", "")
	}
}

func (g *Game) awardTrialHu(winner, from int, kind string, winningTile Tile) {
	hand := g.Hands[winner]
	if from >= 0 {
		hand = append(append([]Tile(nil), hand...), winningTile)
	}
	pattern := g.trialHandPattern(winner, hand)
	for payer := range g.Players {
		if payer != winner && (from < 0 || payer == from) {
			g.recordScore(scoreHu, payer, winner, pattern.points, kind, pattern.name)
		}
	}
}

func (g *Game) awardTrialDraw() {
	ready := [4]trialPattern{}
	for seat := range g.Players {
		ready[seat] = g.bestLiveWait(seat)
	}
	for payer, wait := range ready {
		if wait.points > 0 {
			continue
		}
		multiplier := 1
		for _, tile := range g.Hands[payer] {
			if g.isMissingSuit(payer, tile) {
				multiplier = 2
				break
			}
		}
		for receiver, target := range ready {
			g.recordScore(scoreChaJiao, payer, receiver, multiplier*target.points, "wall_exhausted", target.name)
		}
	}
}

func (g *Game) bestLiveWait(seat int) trialPattern {
	var known [27]int
	var seen [109]bool
	count := func(tile Tile) {
		index := tileIndex(tile)
		if index < 0 || tile.ID < 1 || tile.ID >= len(seen) || seen[tile.ID] {
			return
		}
		seen[tile.ID] = true
		known[index]++
	}
	for _, tile := range g.Hands[seat] {
		if g.isMissingSuit(seat, tile) {
			return trialPattern{}
		}
		count(tile)
	}
	for _, discard := range g.Discards {
		count(discard.Tile)
	}
	for owner, melds := range g.Melds {
		for _, meld := range melds {
			if owner == seat || meld.Kind != "an_gang" {
				for _, tile := range meld.Tiles {
					count(tile)
				}
			}
		}
	}
	hand := append(append([]Tile(nil), g.Hands[seat]...), Tile{})
	best := trialPattern{}
	for _, suit := range missingSuitOrder {
		for rank := 1; rank <= 9; rank++ {
			tile := Tile{Suit: suit, Rank: rank}
			if known[tileIndex(tile)] >= 4 || g.isMissingSuit(seat, tile) {
				continue
			}
			hand[len(hand)-1] = tile
			wait := g.trialHandPattern(seat, hand)
			if wait.points > best.points {
				best = wait
			}
		}
	}
	return best
}
