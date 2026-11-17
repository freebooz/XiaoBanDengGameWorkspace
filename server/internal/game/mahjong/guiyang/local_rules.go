package guiyang

import "slices"

const LocalRuleVersion = "3.0.0"

const localRuleSummary = "四人108张，不吃；点炮与抢补杠胡须本人已完成一个杠，自摸不限。按牌型计番，首胡窗口允许多响，黄庄查叫。"

// HuDetail describes the score collected by one seat before netting against
// other transfers. Fan includes the applicable win-method bonus.
type HuDetail struct {
	Seat    int    `json:"seat"`
	Kind    string `json:"kind"`
	Pattern string `json:"pattern"`
	Fan     int    `json:"fan"`
	Points  int    `json:"points"`
}

// Persisted only for local rules. Declined claims and the post-kong draw
// must survive resuming either a turn or its reaction window.
type localRoundState struct {
	DeclinedHu      [4]bool
	DeclinedPeng    [4]uint32
	ReplacementDraw bool
	HotDiscard      bool
	HuDetails       []HuDetail
	ReadySeats      []int
}

func (r RuleSet) localRules() bool { return r.ID == "guiyang" && r.Version == LocalRuleVersion }

func (g *Game) allowsLocalReaction(seat int, action string, tile Tile) bool {
	if g.Local == nil {
		return true
	}
	switch action {
	case "hu":
		return !g.Local.DeclinedHu[seat]
	case "peng":
		index := tileIndex(tile)
		return index >= 0 && g.Local.DeclinedPeng[seat]&(1<<index) == 0
	default:
		return true
	}
}

func (g *Game) recordLocalDeclines(seat int, action string) {
	if g.Local == nil {
		return
	}
	choices := g.Candidates[seat]
	if action != "hu" && slices.Contains(choices, "hu") {
		g.Local.DeclinedHu[seat] = true
	}
	if action != "peng" && slices.Contains(choices, "peng") {
		if index := tileIndex(g.PendingTile); index >= 0 {
			g.Local.DeclinedPeng[seat] |= 1 << index
		}
	}
}

// The pattern table follows 同城游's published figures. Opening hands use
// DoubleWin's 33/23 figures. Patterns are exclusive and the highest wins.
func (r RuleSet) localHandFan(hand []Tile, melds []Meld) (pattern string, fan int) {
	ok, shape := r.CanHuHand(hand, len(melds))
	if !ok {
		return "", 0
	}
	suit := hand[0].Suit
	pure := true
	var counts [27]int
	for _, tile := range hand {
		pure = pure && tile.Suit == suit
		counts[tileIndex(tile)]++
	}
	for _, meld := range melds {
		for _, tile := range meld.Tiles {
			pure = pure && tile.Suit == suit
		}
	}
	if shape == "七对" {
		dragon := slices.Contains(counts[:], 4)
		switch {
		case pure && dragon:
			return "清龙七对", 20
		case pure:
			return "清七对", 17
		case dragon:
			return "龙七对", 10
		default:
			return "七对", 7
		}
	}
	pairs, triplets := 0, 0
	for _, count := range counts {
		if count == 2 {
			pairs++
		}
		if count == 3 {
			triplets++
		}
	}
	allTriplets := pairs == 1 && triplets+len(melds) == 4
	switch {
	case pure && allTriplets:
		return "清大对", 15
	case pure:
		return "清一色", 10
	case allTriplets:
		return "大对子", 5
	default:
		return "平胡", 1
	}
}

func (g *Game) localOpeningHand(seat int) bool {
	if len(g.Discards) != seatDistance(g.Dealer, seat) {
		return false
	}
	for _, melds := range g.Melds {
		if len(melds) != 0 {
			return false
		}
	}
	return true
}

func isGoldenChicken(tile, flipped Tile, blackEight bool) bool {
	return validType(flipped) && tile.Suit == flipped.Suit && tile.Rank == flipped.Rank%9+1 &&
		(isBasicJi(tile) || (blackEight && isWuGuJi(tile)))
}

func (g *Game) awardLocalGang(seat int, kind string, from int) {
	if kind == "ming_gang" {
		g.transferScore(scoreGang, from, seat, 1)
		return
	}
	points := 2
	if kind == "bu_gang" {
		points = 3
	}
	for other := range g.Players {
		if seat != other {
			g.transferScore(scoreGang, other, seat, points)
		}
	}
}

// In this preset, heat cannon, robbing a kong and a draw cancel all kong
// and chicken transfers. The melds themselves remain committed on the board.
func (g *Game) cancelLocalExtras() {
	for seat := range g.Scores {
		g.Scores[seat] -= g.ScoreBreakdown.Gang[seat] + g.ScoreBreakdown.Ji[seat]
	}
	g.ScoreBreakdown.Gang = [4]int{}
	g.ScoreBreakdown.Ji = [4]int{}
}

func (g *Game) localWinKind(kind string) string {
	switch {
	case kind == "zi_mo" && g.Local.ReplacementDraw:
		return "gang_shang_hua"
	case g.PendingKind == "bu_gang":
		return "qiang_gang"
	case g.PendingKind == "discard" && g.Local.HotDiscard:
		return "re_pao"
	}
	return kind
}

func (g *Game) settleLocalHu(winners []int, from int, winningTile Tile) {
	kind := g.WinKind
	burnExtras := kind == "re_pao" || kind == "qiang_gang"
	if burnExtras {
		g.cancelLocalExtras()
	}
	for _, winner := range winners {
		hand := g.Hands[winner]
		if from >= 0 {
			hand = append(slices.Clone(hand), winningTile)
		}
		pattern, fan := g.Rules.localHandFan(hand, g.Melds[winner])
		if from < 0 && g.localOpeningHand(winner) {
			pattern, fan = "地胡", 23
			if winner == g.Dealer {
				pattern, fan = "天胡", 33
			}
		}
		switch kind {
		case "zi_mo", "qiang_gang":
			fan++
		case "gang_shang_hua", "re_pao":
			fan += 2
		}
		points := fan
		if from < 0 {
			for seat := range g.Players {
				if seat != winner {
					g.transferScore(scoreHu, seat, winner, fan)
				}
			}
			points *= 3
		} else {
			if kind == "qiang_gang" {
				points *= 3
			}
			g.transferScore(scoreHu, from, winner, points)
		}
		g.Local.HuDetails = append(g.Local.HuDetails, HuDetail{Seat: winner, Kind: kind, Pattern: pattern, Fan: fan, Points: points})
	}
	if !burnExtras && g.Rules.chickenEnabled() {
		// The shared winning discard is one physical chicken. Credit it to the
		// nearest winner, using the same seat order as the reaction resolution.
		g.scoreChicken(winners[:1], from, winningTile)
	}
}

// A wait requires at least one copy outside the player's hand/melds and
// public discards/melds. Other players' concealed tiles are unavailable as
// knowledge, even when checking the final board on the server.
func (g *Game) localReadyHand(seat int) (pattern string, fan int) {
	var seen [27]int
	countTile := func(tile Tile) {
		if index := tileIndex(tile); index >= 0 {
			seen[index]++
		}
	}
	for _, tile := range g.Hands[seat] {
		countTile(tile)
	}
	for _, discard := range g.Discards {
		if !discard.Claimed {
			countTile(discard.Tile)
		}
	}
	for owner, melds := range g.Melds {
		for _, meld := range melds {
			if owner != seat && meld.Kind == "an_gang" {
				continue
			}
			for _, tile := range meld.Tiles {
				countTile(tile)
			}
		}
	}
	hand := append(slices.Clone(g.Hands[seat]), Tile{})
	for index, count := range seen {
		if count >= 4 {
			continue
		}
		hand[len(hand)-1] = Tile{Suit: [...]string{"wan", "tong", "tiao"}[index/9], Rank: index%9 + 1}
		if candidate, candidateFan := g.Rules.localHandFan(hand, g.Melds[seat]); candidateFan > fan {
			pattern, fan = candidate, candidateFan
		}
	}
	return pattern, fan
}

func (g *Game) settleLocalDraw() {
	g.cancelLocalExtras()
	g.Local.ReadySeats = []int{}
	for seat := range g.Players {
		pattern, fan := g.localReadyHand(seat)
		if fan != 0 {
			g.Local.ReadySeats = append(g.Local.ReadySeats, seat)
			g.Local.HuDetails = append(g.Local.HuDetails, HuDetail{Seat: seat, Kind: "cha_jiao", Pattern: pattern, Fan: fan})
		}
	}
	for i := range g.Local.HuDetails {
		detail := &g.Local.HuDetails[i]
		for seat := range g.Players {
			if !slices.Contains(g.Local.ReadySeats, seat) {
				g.transferScore(scoreChaJiao, seat, detail.Seat, detail.Fan)
				detail.Points += detail.Fan
			}
		}
	}
}

func (g *Game) SettlementHuDetails() []HuDetail {
	if g.Phase != PhaseFinished || g.Local == nil {
		return nil
	}
	return slices.Clone(g.Local.HuDetails)
}

func (g *Game) SettlementReadySeats() []int {
	if g.Phase != PhaseFinished || g.Local == nil || g.Reason != "wall_exhausted" {
		return nil
	}
	return slices.Clone(g.Local.ReadySeats)
}
