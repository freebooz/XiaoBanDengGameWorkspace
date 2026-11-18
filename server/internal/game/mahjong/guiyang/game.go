package guiyang

import (
	"errors"
	"fmt"
	"math/rand"
	"sort"
)

const (
	PhaseDingque       = "dingque"
	PhaseTurn          = "turn"
	PhaseReaction      = "reaction"
	PhaseFinished      = "finished"
	actionEventHistory = 32
)

type Meld struct {
	Kind     string `json:"kind"`
	Tiles    []Tile `json:"tiles"`
	FromSeat int    `json:"from_seat"`
}

type Discard struct {
	Seat    int  `json:"seat"`
	Tile    Tile `json:"tile"`
	Claimed bool `json:"claimed"`
}

type ActionOption struct {
	Type   string `json:"type"`
	TileID int    `json:"tile_id,omitempty"`
	Suit   string `json:"suit,omitempty"`
}

// ActionEvent describes a committed public action without exposing tile data.
type ActionEvent struct {
	Sequence int    `json:"sequence"`
	Seat     int    `json:"seat"`
	Type     string `json:"type"`
}

// PublicBoardSnapshot is the tile and turn data available to observers.
type PublicBoardSnapshot struct {
	Phase          string          `json:"phase"`
	Turn           int             `json:"turn"`
	HandCounts     [4]int          `json:"hand_counts"`
	Melds          [4][]Meld       `json:"melds"`
	Discards       []Discard       `json:"discards"`
	Remaining      int             `json:"remaining"`
	ActionEvents   []ActionEvent   `json:"action_events"`
	Dealer         int             `json:"dealer"`
	Epoch          int             `json:"epoch"`
	MissingSuits   *[4]string      `json:"missing_suits,omitempty"`
	ScoreTransfers []ScoreTransfer `json:"score_transfers,omitempty"`
	RobbedTile     *Tile           `json:"robbed_tile,omitempty"`
}

type JiEvent struct {
	Kind         string `json:"kind"`
	ActorSeat    int    `json:"actor_seat"`
	TargetSeat   int    `json:"target_seat"`
	Tile         Tile   `json:"tile"`
	ValueUnits   int    `json:"value_units"`
	DiscardIndex int    `json:"discard_index"`
}

// Game 是单房间、单局的权威状态。调用方须串行调用 Apply、Timeout 和 SnapshotFor。
type Game struct {
	Rules               RuleSet
	Players             [4]string
	Hands               [4][]Tile
	Melds               [4][]Meld
	Discards            []Discard
	Wall                []Tile
	NextWall            int
	WallBreakDiceTotal  int
	WallBreakSide       int
	WallBreakStack      int
	Turn                int
	Dealer              int
	Phase               string
	PendingTile         Tile
	PendingFrom         int
	PendingKind         string
	Candidates          map[int][]string
	Submitted           map[int]string
	LastDrawnID         int
	Winners             []int
	WinFrom             int
	WinKind             string
	ClaimedWinTile      *Tile `json:",omitempty"`
	Scores              [4]int
	ScoreBreakdown      *ScoreBreakdown   `json:",omitempty"`
	ScoreLedger         []ScoreTransfer   `json:",omitempty"`
	Local               *localRoundState  `json:",omitempty"`
	LastKongScore       *kongScoreReceipt `json:",omitempty"`
	MissingSuits        *[4]string        `json:",omitempty"`
	RobbedTile          *Tile             `json:",omitempty"`
	FlippedJi           Tile
	JiCounts            [4]int
	JiEvents            []JiEvent
	FirstSpecialDiscard int
	Reason              string
	Epoch               int
	actionSequence      int
	actionEvents        []ActionEvent
	replay              *Replay
}

func NewGame(players [4]string, seed int64) *Game {
	return NewGameWithRules(players, seed, NewRuleSet())
}

func NewGameWithRules(players [4]string, seed int64, rules RuleSet) *Game {
	return NewGameWithDealer(players, seed, rules, -1)
}

// NewGameWithDealer continues from a specified dealer, or picks the opening
// dealer for this preset when dealer is -1.
func NewGameWithDealer(players [4]string, seed int64, rules RuleSet, dealer int) *Game {
	wall := rules.BuildWall()
	rng := rand.New(rand.NewSource(seed))
	rng.Shuffle(len(wall), func(i, j int) { wall[i], wall[j] = wall[j], wall[i] })
	if dealer < 0 || dealer >= 4 {
		dealer = 0
		if rules.RotatesDealer() {
			dealer = rng.Intn(4)
		}
	}
	// 与虚幻版一致：三颗骰子决定开门边和从右数的牌墩，随后顺时针抓牌。
	diceTotal := 0
	for roll := 0; roll < 3; roll++ {
		diceTotal += rng.Intn(6) + 1
	}
	breakSide, breakStack, start := wallBreak(dealer, diceTotal)
	wall = append(append([]Tile{}, wall[start:]...), wall[:start]...)
	g := &Game{Rules: rules, Players: players, Wall: wall, WallBreakDiceTotal: diceTotal, WallBreakSide: breakSide, WallBreakStack: breakStack, Phase: PhaseTurn, Turn: dealer, Dealer: dealer, PendingFrom: -1, WinFrom: -1, FirstSpecialDiscard: -1, Epoch: 1, ScoreBreakdown: &ScoreBreakdown{}}
	g.replay = &Replay{Version: ReplayVersion, Dealer: g.Dealer}
	if rules.localRules() {
		g.Local = &localRoundState{}
	}
	if rules.Dingque() {
		g.Phase = PhaseDingque
		g.MissingSuits = &[4]string{}
	}
	// 虚幻版发牌顺序：三轮每家四张，再每家一张，庄家补一张。
	for round := 0; round < 3; round++ {
		for offset := 0; offset < 4; offset++ {
			seat := (g.Dealer + offset) % 4
			for count := 0; count < 4; count++ {
				g.drawTo(seat)
			}
		}
	}
	for offset := 0; offset < 4; offset++ {
		g.drawTo((g.Dealer + offset) % 4)
	}
	g.LastDrawnID = g.drawTo(g.Dealer).ID
	for seat := 0; seat < 4; seat++ {
		SortHand(g.Hands[seat])
	}
	return g
}

func wallBreak(dealer, diceTotal int) (side, stack, start int) {
	wallTiles := [4]int{28, 26, 28, 26}
	segmentStarts := [4]int{0, 28, 54, 82}
	side = (dealer + diceTotal - 1) % 4
	stack = (diceTotal-1)%(wallTiles[side]/2) + 1
	segment := (4 - side) % 4
	start = (segmentStarts[segment] + stack*2) % 108
	return
}

func (g *Game) Remaining() int { return len(g.Wall) - g.NextWall }

func (g *Game) drawTo(seat int) Tile {
	if g.Remaining() <= 0 {
		return Tile{}
	}
	if g.Local != nil {
		g.Local.DeclinedHu[seat], g.Local.DeclinedPeng[seat] = false, 0
		g.Local.ReplacementDraw, g.Local.HotDiscard = false, false
	}
	tile := g.Wall[g.NextWall]
	g.NextWall++
	g.Hands[seat] = append(g.Hands[seat], tile)
	return tile
}

func (g *Game) Options(seat int) []ActionOption {
	if seat < 0 || seat >= 4 || g.Phase == PhaseFinished {
		return nil
	}
	if g.Phase == PhaseDingque {
		return g.missingSuitOptions(seat)
	}
	if g.Phase == PhaseReaction {
		choices, eligible := g.Candidates[seat]
		if !eligible {
			return nil
		}
		if _, submitted := g.Submitted[seat]; submitted {
			return nil
		}
		out := []ActionOption{{Type: "pass"}}
		for _, choice := range choices {
			if g.validReaction(seat, choice) {
				out = append(out, ActionOption{Type: choice})
			}
		}
		return out
	}
	if seat != g.Turn {
		return nil
	}
	out := []ActionOption{{Type: "play"}}
	if g.Rules.Dingque() {
		out = nil
		for _, tile := range g.Hands[seat] {
			if g.canDiscard(seat, tile) {
				out = append(out, ActionOption{Type: "play", TileID: tile.ID})
			}
		}
	}
	if g.canSelfDraw(seat) {
		out = append(out, ActionOption{Type: "hu"})
	}
	if g.Remaining() == 0 {
		return out
	}
	seen := map[int]bool{}
	for _, tile := range g.Hands[seat] {
		if g.isMissingSuit(seat, tile) {
			continue
		}
		index := tileIndex(tile)
		if seen[index] {
			continue
		}
		seen[index] = true
		if CountType(g.Hands[seat], tile) == 4 {
			out = append(out, ActionOption{Type: "an_gang", TileID: tile.ID})
		}
		for _, meld := range g.Melds[seat] {
			if meld.Kind == "peng" && sameType(meld.Tiles[0], tile) {
				out = append(out, ActionOption{Type: "bu_gang", TileID: tile.ID})
			}
		}
	}
	return out
}

func (g *Game) Apply(seat int, action string, tileID int) error {
	if seat < 0 || seat >= 4 || g.Players[seat] == "" {
		return errors.New("座位无效")
	}
	if g.Phase == PhaseFinished {
		return errors.New("本局已经结束")
	}
	if g.Phase == PhaseDingque {
		return errors.New("须先完成定缺")
	}
	if g.Phase == PhaseReaction {
		if g.Rules.Dingque() && tileID != 0 {
			return errors.New("响应操作不指定手牌")
		}
		return g.applyReaction(seat, action)
	}
	if seat != g.Turn {
		return errors.New("当前不是你的回合")
	}
	switch action {
	case "play":
		return g.play(seat, tileID)
	case "hu":
		if (g.Rules.Dingque() && tileID != 0) || !g.canSelfDraw(seat) {
			return errors.New("当前手牌不能胡")
		}
		g.settle([]int{seat}, -1, "zi_mo")
		return nil
	case "an_gang":
		if g.Remaining() == 0 {
			return errors.New("牌墙已无补牌，不能杠牌")
		}
		return g.anGang(seat, tileID)
	case "bu_gang":
		if g.Remaining() == 0 {
			return errors.New("牌墙已无补牌，不能杠牌")
		}
		return g.beginBuGang(seat, tileID)
	default:
		return errors.New("当前阶段不支持该操作")
	}
}

func (g *Game) canSelfDraw(seat int) bool {
	if _, drawn := g.findTile(seat, g.LastDrawnID); !drawn {
		return false
	}
	return g.winningHand(seat, g.Hands[seat])
}

func (g *Game) play(seat, tileID int) error {
	index := -1
	for i, tile := range g.Hands[seat] {
		if tile.ID == tileID {
			index = i
			break
		}
	}
	if index < 0 {
		return errors.New("目标牌不在你的手牌中")
	}
	played := g.Hands[seat][index]
	if !g.canDiscard(seat, played) {
		return errors.New("必须先打出定缺花色")
	}
	g.Hands[seat] = append(g.Hands[seat][:index], g.Hands[seat][index+1:]...)
	g.Discards = append(g.Discards, Discard{Seat: seat, Tile: played})
	discardIndex := len(g.Discards) - 1
	g.recordReplay(ReplayEvent{Seat: seat, Kind: "play", Tile: &played, DiscardIndex: &discardIndex})
	options := g.Rules.effectiveOptions()
	if options.ChargeChicken && g.FirstSpecialDiscard < 0 && (isBasicJi(played) || (options.BlackEight && isWuGuJi(played))) {
		g.FirstSpecialDiscard = len(g.Discards) - 1
		units := 2
		if isWuGuJi(played) {
			units = 4
		}
		g.JiEvents = append(g.JiEvents, JiEvent{Kind: "chong_feng", ActorSeat: seat, TargetSeat: -1, Tile: played, ValueUnits: units, DiscardIndex: g.FirstSpecialDiscard})
	}
	g.PendingTile, g.PendingFrom, g.PendingKind = played, seat, "discard"
	if g.Local != nil {
		g.Local.HotDiscard, g.Local.ReplacementDraw = g.Local.ReplacementDraw, false
	}
	g.Candidates = map[int][]string{}
	g.Submitted = map[int]string{}
	for other := 0; other < 4; other++ {
		if other == seat {
			continue
		}
		choices := []string{}
		if g.canClaimHu(other, played) {
			choices = append(choices, "hu")
		}
		if !g.isMissingSuit(other, played) {
			if g.Remaining() > 0 && g.Rules.CanGangFromDiscard(g.Hands[other], played) {
				choices = append(choices, "ming_gang")
			}
			if g.Rules.CanPeng(g.Hands[other], played) && g.allowsLocalReaction(other, "peng", played) {
				choices = append(choices, "peng")
			}
		}
		if len(choices) > 0 {
			g.Candidates[other] = choices
		}
	}
	g.Epoch++
	if len(g.Candidates) > 0 {
		g.Phase = PhaseReaction
	} else {
		g.advanceFrom(seat)
	}
	return nil
}

func (g *Game) applyReaction(seat int, action string) error {
	choices, eligible := g.Candidates[seat]
	if !eligible {
		return errors.New("没有该座位的响应窗口")
	}
	if _, submitted := g.Submitted[seat]; submitted {
		return errors.New("该响应已经提交")
	}
	allowed := action == "pass"
	for _, choice := range choices {
		if choice == action {
			allowed = true
		}
	}
	if !allowed || !g.validReaction(seat, action) {
		return errors.New("操作不在服务端候选列表中")
	}
	g.recordLocalDeclines(seat, action)
	g.Submitted[seat] = action
	g.Epoch++
	if len(g.Submitted) == len(g.Candidates) {
		g.resolveReactions()
	}
	return nil
}

func (g *Game) resolveReactions() {
	huSeats := []int{}
	for seat, action := range g.Submitted {
		if action == "hu" && g.validReaction(seat, action) {
			huSeats = append(huSeats, seat)
		}
	}
	sort.Slice(huSeats, func(i, j int) bool {
		return seatDistance(g.PendingFrom, huSeats[i]) < seatDistance(g.PendingFrom, huSeats[j])
	})
	if len(huSeats) > 0 {
		if g.PendingKind == "discard" && len(g.Discards) > 0 {
			g.Discards[len(g.Discards)-1].Claimed = true
		}
		kind := "dian_pao"
		if g.Rules.Dingque() && g.PendingKind == "bu_gang" {
			kind = "qiang_gang"
		}
		g.settle(huSeats, g.PendingFrom, kind)
		return
	}
	if g.PendingKind == "bu_gang" {
		g.completeBuGang()
		return
	}
	claimSeat, claimAction, bestPriority, bestDistance := -1, "", -1, 5
	for seat, action := range g.Submitted {
		if !g.validReaction(seat, action) {
			continue
		}
		priority := 0
		if action == "peng" {
			priority = 1
		}
		if action == "ming_gang" {
			priority = 2
		}
		distance := seatDistance(g.PendingFrom, seat)
		if priority > bestPriority || (priority == bestPriority && distance < bestDistance) {
			claimSeat, claimAction, bestPriority, bestDistance = seat, action, priority, distance
		}
	}
	if bestPriority <= 0 {
		g.advanceFrom(g.PendingFrom)
		return
	}
	g.claim(claimSeat, claimAction)
}

func seatDistance(from, to int) int { return (to - from + 4) % 4 }

func (g *Game) claim(seat int, kind string) {
	count := 2
	if kind == "ming_gang" {
		count = 3
	}
	removed := g.removeType(seat, g.PendingTile, count)
	removed = append(removed, g.PendingTile)
	g.Melds[seat] = append(g.Melds[seat], Meld{Kind: kind, Tiles: removed, FromSeat: g.PendingFrom})
	if g.FirstSpecialDiscard >= 0 && len(g.Discards)-1 == g.FirstSpecialDiscard {
		g.transferScore(scoreJi, g.PendingFrom, seat, 1)
		g.JiEvents = append(g.JiEvents, JiEvent{Kind: "ze_ren", ActorSeat: seat, TargetSeat: g.PendingFrom, Tile: g.PendingTile, ValueUnits: 1, DiscardIndex: g.FirstSpecialDiscard})
	}
	if len(g.Discards) > 0 {
		g.Discards[len(g.Discards)-1].Claimed = true
	}
	discardIndex := len(g.Discards) - 1
	g.recordReplayMeld(seat, len(g.Melds[seat])-1, &discardIndex)
	g.Turn = seat
	g.LastDrawnID = 0
	from := g.PendingFrom
	g.Phase = PhaseTurn
	g.clearPending()
	g.LastKongScore = nil
	if kind == "ming_gang" {
		g.awardGang(seat, kind, from)
		g.drawReplacement(seat)
	}
	g.recordAction(seat, kind)
	g.Epoch++
}

func (g *Game) removeType(seat int, target Tile, count int) []Tile {
	removed := make([]Tile, 0, count)
	kept := make([]Tile, 0, len(g.Hands[seat])-count)
	for _, tile := range g.Hands[seat] {
		if sameType(tile, target) && len(removed) < count {
			removed = append(removed, tile)
		} else {
			kept = append(kept, tile)
		}
	}
	g.Hands[seat] = kept
	return removed
}

func (g *Game) anGang(seat, tileID int) error {
	tile, ok := g.findTile(seat, tileID)
	if !ok || g.isMissingSuit(seat, tile) || CountType(g.Hands[seat], tile) != 4 {
		return errors.New("手中没有可暗杠的四张同牌")
	}
	removed := g.removeType(seat, tile, 4)
	g.Melds[seat] = append(g.Melds[seat], Meld{Kind: "an_gang", Tiles: removed, FromSeat: seat})
	g.recordReplayMeld(seat, len(g.Melds[seat])-1, nil)
	g.awardGang(seat, "an_gang", seat)
	g.drawReplacement(seat)
	g.recordAction(seat, "an_gang")
	g.Epoch++
	return nil
}

func (g *Game) beginBuGang(seat, tileID int) error {
	tile, ok := g.findTile(seat, tileID)
	if !ok || g.isMissingSuit(seat, tile) {
		return errors.New("补杠牌不在手中")
	}
	foundPeng := false
	for _, meld := range g.Melds[seat] {
		if meld.Kind == "peng" && sameType(meld.Tiles[0], tile) {
			foundPeng = true
		}
	}
	if !foundPeng {
		return errors.New("没有可补杠的碰牌")
	}
	g.LastKongScore = nil
	g.PendingTile, g.PendingFrom, g.PendingKind = tile, seat, "bu_gang"
	if !g.Rules.effectiveOptions().RobKong {
		g.completeBuGang()
		g.Epoch++
		return nil
	}
	g.Candidates = map[int][]string{}
	g.Submitted = map[int]string{}
	for other := 0; other < 4; other++ {
		if other == seat {
			continue
		}
		if g.canClaimHu(other, tile) {
			g.Candidates[other] = []string{"hu"}
		}
	}
	if len(g.Candidates) == 0 {
		g.completeBuGang()
	} else {
		g.Phase = PhaseReaction
	}
	g.Epoch++
	return nil
}

func (g *Game) completeBuGang() {
	seat, tile := g.PendingFrom, g.PendingTile
	for index, held := range g.Hands[seat] {
		if held.ID == tile.ID {
			g.Hands[seat] = append(g.Hands[seat][:index], g.Hands[seat][index+1:]...)
			break
		}
	}
	for index := range g.Melds[seat] {
		if g.Melds[seat][index].Kind == "peng" && sameType(g.Melds[seat][index].Tiles[0], tile) {
			g.Melds[seat][index].Kind = "bu_gang"
			g.Melds[seat][index].Tiles = append(g.Melds[seat][index].Tiles, tile)
			g.recordReplayMeld(seat, index, nil)
			break
		}
	}
	g.Phase, g.Turn = PhaseTurn, seat
	g.clearPending()
	g.awardGang(seat, "bu_gang", seat)
	g.drawReplacement(seat)
	g.recordAction(seat, "bu_gang")
	g.Epoch++
}

func (g *Game) findTile(seat, id int) (Tile, bool) {
	for _, tile := range g.Hands[seat] {
		if tile.ID == id {
			return tile, true
		}
	}
	return Tile{}, false
}

func (g *Game) hasCompletedGang(seat int) bool {
	for _, meld := range g.Melds[seat] {
		if meld.Kind == "ming_gang" || meld.Kind == "an_gang" || meld.Kind == "bu_gang" {
			return true
		}
	}
	return false
}

func (g *Game) awardGang(seat int, kind string, from int) {
	if g.Local != nil {
		g.awardLocalGang(seat, kind, from)
		return
	}
	if g.Rules.Dingque() {
		g.awardTrialGang(seat, kind, from)
		return
	}
	for other := 0; other < 4; other++ {
		if other != seat {
			g.transferScore(scoreGang, other, seat, 1)
		}
	}
}

func (g *Game) drawReplacement(seat int) {
	if g.Remaining() == 0 {
		g.finishDraw()
		return
	}
	g.LastDrawnID = g.drawTo(seat).ID
	if g.Local != nil {
		g.Local.ReplacementDraw = true
	}
	SortHand(g.Hands[seat])
}

func (g *Game) advanceFrom(seat int) {
	g.LastKongScore = nil
	g.clearPending()
	g.Turn = (seat + 1) % 4
	if g.Remaining() == 0 {
		g.finishDraw()
		return
	}
	g.LastDrawnID = g.drawTo(g.Turn).ID
	SortHand(g.Hands[g.Turn])
	g.Phase = PhaseTurn
	g.Epoch++
}

func (g *Game) finishDraw() {
	g.LastKongScore = nil
	g.Phase, g.Reason = PhaseFinished, "wall_exhausted"
	if g.Rules.Dingque() {
		g.awardTrialDraw()
	} else if g.Local != nil {
		g.settleLocalDraw()
	}
	g.recordReplay(ReplayEvent{Seat: -1, Kind: g.Reason})
	g.Epoch++
}

func (g *Game) settle(winners []int, from int, kind string) {
	if g.Local != nil {
		kind = g.localWinKind(kind)
	}
	winningTile := g.PendingTile
	if from < 0 {
		winningTile, _ = g.findTile(winners[0], g.LastDrawnID)
	} else if winningTile.ID > 0 {
		claimed := winningTile
		g.ClaimedWinTile = &claimed
	}
	if g.PendingKind == "bu_gang" && from >= 0 {
		for index, held := range g.Hands[from] {
			if held.ID == winningTile.ID {
				g.Hands[from] = append(g.Hands[from][:index], g.Hands[from][index+1:]...)
				break
			}
		}
	}
	if kind == "qiang_gang" {
		g.RobbedTile = &winningTile
	}
	g.Winners, g.WinFrom, g.WinKind = append([]int(nil), winners...), from, kind
	g.Phase, g.Reason = PhaseFinished, "hu"
	var replayClaim *int
	if g.PendingKind == "discard" && len(g.Discards) > 0 && g.Discards[len(g.Discards)-1].Claimed {
		discardIndex := len(g.Discards) - 1
		replayClaim = &discardIndex
	}
	for _, winner := range winners {
		g.recordAction(winner, "hu")
		g.recordReplay(ReplayEvent{Seat: winner, Kind: "hu", DiscardIndex: replayClaim, RobbedTile: g.RobbedTile})
		if g.Local != nil {
			continue
		}
		if g.Rules.Dingque() {
			g.awardTrialHu(winner, from, kind, winningTile)
			continue
		}
		for other := 0; other < 4; other++ {
			if other == winner {
				continue
			}
			if from == -1 {
				g.transferScore(scoreHu, other, winner, 2)
			}
			if from == other {
				g.transferScore(scoreHu, other, winner, 3)
			}
		}
	}
	if g.Rules.Dingque() && kind == "dian_pao" {
		g.revokeHeatCannonKong(from)
	}
	g.LastKongScore = nil
	if g.Local != nil {
		g.settleLocalHu(winners, from, winningTile)
	} else if g.Rules.chickenEnabled() {
		g.scoreChicken(winners, from, winningTile)
	}
	g.clearPending()
	g.Epoch++
}

func (g *Game) recordAction(seat int, kind string) {
	g.actionSequence++
	event := ActionEvent{Sequence: g.actionSequence, Seat: seat, Type: kind}
	if len(g.actionEvents) == actionEventHistory {
		copy(g.actionEvents, g.actionEvents[1:])
		g.actionEvents[len(g.actionEvents)-1] = event
		return
	}
	g.actionEvents = append(g.actionEvents, event)
}

func (g *Game) scoreChicken(winners []int, from int, winningTile Tile) {
	if g.Remaining() > 0 {
		g.FlippedJi = g.Wall[g.NextWall]
		g.NextWall++
	}
	blackEight := g.Rules.effectiveOptions().BlackEight
	units := func(tile Tile) int {
		value := jiUnits(tile, g.FlippedJi, blackEight)
		if g.Local != nil && isGoldenChicken(tile, g.FlippedJi, blackEight) {
			value *= 2
		}
		return value
	}
	for seat := 0; seat < 4; seat++ {
		for _, tile := range g.Hands[seat] {
			g.JiCounts[seat] += units(tile)
		}
		for _, meld := range g.Melds[seat] {
			for _, tile := range meld.Tiles {
				g.JiCounts[seat] += units(tile)
			}
		}
		if from >= 0 && containsSeat(winners, seat) {
			g.JiCounts[seat] += units(winningTile)
		}
	}
	for _, discard := range g.Discards {
		if !discard.Claimed {
			if !g.Rules.Dingque() {
				g.JiCounts[discard.Seat] += units(discard.Tile)
			} else if isBasicJi(discard.Tile) {
				g.JiCounts[discard.Seat]++
			}
		}
	}
	for index := range g.JiEvents {
		event := &g.JiEvents[index]
		if event.Kind != "chong_feng" {
			continue
		}
		if g.Local != nil && isGoldenChicken(event.Tile, g.FlippedJi, blackEight) {
			event.ValueUnits *= 2
		}
		already := 0
		if event.DiscardIndex >= 0 && event.DiscardIndex < len(g.Discards) && !g.Discards[event.DiscardIndex].Claimed {
			already = units(event.Tile)
		}
		if event.ValueUnits > already {
			g.JiCounts[event.ActorSeat] += event.ValueUnits - already
		}
	}
	for a := 0; a < 4; a++ {
		for b := a + 1; b < 4; b++ {
			delta := g.JiCounts[a] - g.JiCounts[b]
			switch {
			case !g.Rules.Dingque():
				g.transferScore(scoreJi, b, a, delta)
			case delta > 0:
				g.recordScore(scoreJi, b, a, delta, "chicken_difference", "")
			case delta < 0:
				g.recordScore(scoreJi, a, b, -delta, "chicken_difference", "")
			}
		}
	}
}

func (g *Game) clearPending() {
	g.PendingTile = Tile{}
	g.PendingFrom = -1
	g.PendingKind = ""
	g.Candidates = nil
	g.Submitted = nil
}

// Timeout 自动打出刚摸的牌或自动过响应，使用者以 Epoch 拒绝旧计时器。
func (g *Game) Timeout() {
	if g.Phase == PhaseDingque {
		for seat, suit := range *g.MissingSuits {
			if suit == "" {
				_ = g.ChooseMissingSuit(seat, g.DefaultMissingSuit(seat))
			}
		}
		return
	}
	if g.Phase == PhaseReaction {
		for seat := range g.Candidates {
			if _, done := g.Submitted[seat]; !done {
				g.recordLocalDeclines(seat, "pass")
				g.Submitted[seat] = "pass"
			}
		}
		g.resolveReactions()
		return
	}
	if g.Phase != PhaseTurn {
		return
	}
	chosen := g.LastDrawnID
	if _, ok := g.findTile(g.Turn, chosen); !ok && len(g.Hands[g.Turn]) > 0 {
		chosen = g.Hands[g.Turn][len(g.Hands[g.Turn])-1].ID
	}
	if g.Rules.Dingque() {
		if drawn, _ := g.findTile(g.Turn, chosen); !g.canDiscard(g.Turn, drawn) {
			for _, tile := range g.Hands[g.Turn] {
				if g.canDiscard(g.Turn, tile) {
					chosen = tile.ID
					break
				}
			}
		}
	}
	_ = g.play(g.Turn, chosen)
}

// PublicBoard returns a detached snapshot with every concealed kong masked.
func (g *Game) PublicBoard() PublicBoardSnapshot {
	return g.boardFor(-1)
}

// NextDealer returns the winner nearest the feeder, or the incumbent on a draw.
func (g *Game) NextDealer() int {
	if !g.Rules.RotatesDealer() {
		return 0
	}
	if len(g.Winners) > 0 {
		return g.Winners[0]
	}
	return g.Dealer
}

func (g *Game) boardFor(seat int) PublicBoardSnapshot {
	board := PublicBoardSnapshot{
		Phase: g.Phase, Turn: g.Turn, Discards: append([]Discard{}, g.Discards...),
		Remaining: g.Remaining(), ActionEvents: append([]ActionEvent{}, g.actionEvents...), Dealer: g.Dealer, Epoch: g.Epoch,
	}
	if g.MissingSuits != nil && g.Phase != PhaseDingque {
		suits := *g.MissingSuits
		board.MissingSuits = &suits
	}
	board.ScoreTransfers = g.SettlementScoreTransfers()
	if g.RobbedTile != nil && g.Phase == PhaseFinished {
		tile := *g.RobbedTile
		board.RobbedTile = &tile
	}
	for other := 0; other < 4; other++ {
		board.HandCounts[other] = len(g.Hands[other])
		board.Melds[other] = make([]Meld, 0, len(g.Melds[other]))
		for _, meld := range g.Melds[other] {
			copyMeld := meld
			if other != seat && meld.Kind == "an_gang" {
				copyMeld.Tiles = make([]Tile, 4)
			} else {
				copyMeld.Tiles = append([]Tile(nil), meld.Tiles...)
			}
			board.Melds[other] = append(board.Melds[other], copyMeld)
		}
	}
	return board
}

// SnapshotFor serves a seated player. Other concealed hands are revealed at
// settlement only. Concealed kongs stay masked for everyone except their owner.
func (g *Game) SnapshotFor(seat int) map[string]any {
	if seat < 0 || seat >= len(g.Players) || g.Players[seat] == "" {
		return map[string]any{}
	}
	options := g.Options(seat)
	if options == nil {
		options = []ActionOption{}
	}
	board := g.boardFor(seat)
	hand := append([]Tile{}, g.Hands[seat]...)
	snapshot := map[string]any{
		"type": "mahjong_state", "phase": g.Phase, "turn": g.Turn, "dealer": board.Dealer, "your_seat": seat,
		"players": g.Players, "hand": hand, "hand_counts": board.HandCounts[:], "melds": board.Melds[:],
		"discards": board.Discards, "remaining": board.Remaining,
		"options": options, "winners": append([]int{}, g.Winners...),
		"win_from": g.WinFrom, "win_kind": g.WinKind, "scores": g.Scores,
		"reason": g.Reason, "epoch": g.Epoch, "last_discard": g.PendingTile,
		"pending_kind": g.PendingKind, "pending_from": g.PendingFrom,
		"wall_break_dice_total": g.WallBreakDiceTotal, "wall_break_side": g.WallBreakSide, "wall_break_stack": g.WallBreakStack,
		"flipped_ji": g.FlippedJi, "ji_counts": g.JiCounts, "ji_events": append([]JiEvent{}, g.JiEvents...),
		"action_events": board.ActionEvents,
	}
	if board.MissingSuits != nil {
		snapshot["missing_suits"] = *board.MissingSuits
	}
	if board.ScoreTransfers != nil {
		snapshot["score_transfers"] = board.ScoreTransfers
	}
	if board.RobbedTile != nil {
		snapshot["robbed_tile"] = *board.RobbedTile
	}
	if g.Phase == PhaseTurn && seat == g.Turn && g.LastDrawnID > 0 {
		if _, held := g.findTile(seat, g.LastDrawnID); held {
			snapshot["drawn_tile_id"] = g.LastDrawnID
		}
	}
	if breakdown := g.SettlementScoreBreakdown(); breakdown != nil {
		snapshot["score_breakdown"] = breakdown
	}
	if g.Phase == PhaseFinished {
		snapshot["settlement_hands"] = g.settlementHands()
	}
	if details := g.SettlementHuDetails(); len(details) > 0 {
		snapshot["hu_details"] = details
		if rows := settlementFanBreakdown(details); len(rows) > 0 {
			snapshot["fan_breakdown"] = rows
		}
	}
	if ready := g.SettlementReadySeats(); ready != nil {
		snapshot["ready_seats"] = ready
	}
	return snapshot
}

func containsSeat(seats []int, target int) bool {
	for _, seat := range seats {
		if seat == target {
			return true
		}
	}
	return false
}

func isBasicJi(tile Tile) bool { return tile.Suit == "tiao" && tile.Rank == 1 }
func isWuGuJi(tile Tile) bool  { return tile.Suit == "tong" && tile.Rank == 8 }

func jiUnits(tile, flipped Tile, blackEight bool) int {
	units := 0
	if isBasicJi(tile) {
		units = 1
	}
	if blackEight && isWuGuJi(tile) {
		units = 2
	}
	if validType(flipped) && tile.Suit == flipped.Suit && tile.Rank == flipped.Rank%9+1 && units < 1 {
		units = 1
	}
	return units
}

func (g *Game) Validate() error {
	seen := map[int]bool{}
	for _, tile := range g.Wall {
		if tile.ID < 1 || tile.ID > 108 || seen[tile.ID] {
			return fmt.Errorf("牌墙实体ID错误: %d", tile.ID)
		}
		seen[tile.ID] = true
	}
	if len(seen) != 108 {
		return errors.New("牌墙不是108张")
	}
	return nil
}
