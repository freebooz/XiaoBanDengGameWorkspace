package guiyang

import (
	"errors"
	"fmt"
	"math/rand"
	"sort"
)

const (
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
}

// ActionEvent describes a committed public action without exposing tile data.
type ActionEvent struct {
	Sequence int    `json:"sequence"`
	Seat     int    `json:"seat"`
	Type     string `json:"type"`
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
	Scores              [4]int
	ScoreBreakdown      *ScoreBreakdown `json:",omitempty"`
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
	wall := rules.BuildWall()
	rng := rand.New(rand.NewSource(seed))
	rng.Shuffle(len(wall), func(i, j int) { wall[i], wall[j] = wall[j], wall[i] })
	// 与虚幻版一致：三颗骰子决定开门边和从右数的牌墩，随后顺时针抓牌。
	diceTotal := 0
	for roll := 0; roll < 3; roll++ {
		diceTotal += rng.Intn(6) + 1
	}
	breakSide, breakStack, start := wallBreak(0, diceTotal)
	wall = append(append([]Tile{}, wall[start:]...), wall[:start]...)
	g := &Game{Rules: rules, Players: players, Wall: wall, WallBreakDiceTotal: diceTotal, WallBreakSide: breakSide, WallBreakStack: breakStack, Phase: PhaseTurn, Turn: 0, Dealer: 0, PendingFrom: -1, WinFrom: -1, FirstSpecialDiscard: -1, Epoch: 1, ScoreBreakdown: &ScoreBreakdown{}}
	g.replay = &Replay{Version: ReplayVersion, Dealer: g.Dealer}
	// 虚幻版发牌顺序：三轮每家四张，再每家一张，庄家补一张。
	for round := 0; round < 3; round++ {
		for seat := 0; seat < 4; seat++ {
			for count := 0; count < 4; count++ {
				g.drawTo(seat)
			}
		}
	}
	for seat := 0; seat < 4; seat++ {
		g.drawTo(seat)
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
	tile := g.Wall[g.NextWall]
	g.NextWall++
	g.Hands[seat] = append(g.Hands[seat], tile)
	return tile
}

func (g *Game) Options(seat int) []ActionOption {
	if seat < 0 || seat >= 4 || g.Phase == PhaseFinished {
		return nil
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
			out = append(out, ActionOption{Type: choice})
		}
		return out
	}
	if seat != g.Turn {
		return nil
	}
	out := []ActionOption{{Type: "play"}}
	if g.canSelfDraw(seat) {
		out = append(out, ActionOption{Type: "hu"})
	}
	if g.Remaining() == 0 {
		return out
	}
	seen := map[int]bool{}
	for _, tile := range g.Hands[seat] {
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
	if g.Phase == PhaseReaction {
		return g.applyReaction(seat, action)
	}
	if seat != g.Turn {
		return errors.New("当前不是你的回合")
	}
	switch action {
	case "play":
		return g.play(seat, tileID)
	case "hu":
		if !g.canSelfDraw(seat) {
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
	ok, _ := g.Rules.CanHuHand(g.Hands[seat], len(g.Melds[seat]))
	return ok
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
	g.Candidates = map[int][]string{}
	g.Submitted = map[int]string{}
	for other := 0; other < 4; other++ {
		if other == seat {
			continue
		}
		choices := []string{}
		if !g.Rules.requiresKongToClaim() || g.hasCompletedGang(other) {
			testHand := append(append([]Tile(nil), g.Hands[other]...), played)
			if ok, _ := g.Rules.CanHuHand(testHand, len(g.Melds[other])); ok {
				choices = append(choices, "hu")
			}
		}
		if g.Remaining() > 0 && g.Rules.CanGangFromDiscard(g.Hands[other], played) {
			choices = append(choices, "ming_gang")
		}
		if g.Rules.CanPeng(g.Hands[other], played) {
			choices = append(choices, "peng")
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
	if !allowed {
		return errors.New("操作不在服务端候选列表中")
	}
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
		if action == "hu" {
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
		g.settle(huSeats, g.PendingFrom, "dian_pao")
		return
	}
	if g.PendingKind == "bu_gang" {
		g.completeBuGang()
		return
	}
	claimSeat, claimAction, bestPriority, bestDistance := -1, "", -1, 5
	for seat, action := range g.Submitted {
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
	g.Phase = PhaseTurn
	g.clearPending()
	if kind == "ming_gang" {
		g.awardGang(seat)
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
	if !ok || CountType(g.Hands[seat], tile) != 4 {
		return errors.New("手中没有可暗杠的四张同牌")
	}
	removed := g.removeType(seat, tile, 4)
	g.Melds[seat] = append(g.Melds[seat], Meld{Kind: "an_gang", Tiles: removed, FromSeat: seat})
	g.recordReplayMeld(seat, len(g.Melds[seat])-1, nil)
	g.awardGang(seat)
	g.drawReplacement(seat)
	g.recordAction(seat, "an_gang")
	g.Epoch++
	return nil
}

func (g *Game) beginBuGang(seat, tileID int) error {
	tile, ok := g.findTile(seat, tileID)
	if !ok {
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
	g.PendingTile, g.PendingFrom, g.PendingKind = tile, seat, "bu_gang"
	if !g.Rules.effectiveOptions().RobKong {
		g.completeBuGang()
		g.Epoch++
		return nil
	}
	g.Candidates = map[int][]string{}
	g.Submitted = map[int]string{}
	for other := 0; other < 4; other++ {
		if other == seat || (g.Rules.requiresKongToClaim() && !g.hasCompletedGang(other)) {
			continue
		}
		testHand := append(append([]Tile(nil), g.Hands[other]...), tile)
		if ok, _ := g.Rules.CanHuHand(testHand, len(g.Melds[other])); ok {
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
	g.awardGang(seat)
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

func (g *Game) awardGang(seat int) {
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
	SortHand(g.Hands[seat])
}

func (g *Game) advanceFrom(seat int) {
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
	g.Phase, g.Reason = PhaseFinished, "wall_exhausted"
	g.recordReplay(ReplayEvent{Seat: -1, Kind: g.Reason})
	g.Epoch++
}

func (g *Game) settle(winners []int, from int, kind string) {
	winningTile := g.PendingTile
	if from < 0 {
		winningTile, _ = g.findTile(winners[0], g.LastDrawnID)
	}
	if g.PendingKind == "bu_gang" && from >= 0 {
		for index, held := range g.Hands[from] {
			if held.ID == winningTile.ID {
				g.Hands[from] = append(g.Hands[from][:index], g.Hands[from][index+1:]...)
				break
			}
		}
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
		g.recordReplay(ReplayEvent{Seat: winner, Kind: "hu", DiscardIndex: replayClaim})
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
	if g.Rules.chickenEnabled() {
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
	for seat := 0; seat < 4; seat++ {
		for _, tile := range g.Hands[seat] {
			g.JiCounts[seat] += jiUnits(tile, g.FlippedJi, blackEight)
		}
		for _, meld := range g.Melds[seat] {
			for _, tile := range meld.Tiles {
				g.JiCounts[seat] += jiUnits(tile, g.FlippedJi, blackEight)
			}
		}
		if from >= 0 && containsSeat(winners, seat) {
			g.JiCounts[seat] += jiUnits(winningTile, g.FlippedJi, blackEight)
		}
	}
	for _, discard := range g.Discards {
		if !discard.Claimed {
			g.JiCounts[discard.Seat] += jiUnits(discard.Tile, g.FlippedJi, blackEight)
		}
	}
	for _, event := range g.JiEvents {
		if event.Kind != "chong_feng" {
			continue
		}
		already := 0
		if event.DiscardIndex >= 0 && event.DiscardIndex < len(g.Discards) && !g.Discards[event.DiscardIndex].Claimed {
			already = jiUnits(event.Tile, g.FlippedJi, blackEight)
		}
		if event.ValueUnits > already {
			g.JiCounts[event.ActorSeat] += event.ValueUnits - already
		}
	}
	for a := 0; a < 4; a++ {
		for b := a + 1; b < 4; b++ {
			delta := g.JiCounts[a] - g.JiCounts[b]
			g.transferScore(scoreJi, b, a, delta)
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
	if g.Phase == PhaseReaction {
		for seat := range g.Candidates {
			if _, done := g.Submitted[seat]; !done {
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
	_ = g.play(g.Turn, chosen)
}

// SnapshotFor 不序列化其它玩家暗牌；暗杠也只显示四张牌背。
func (g *Game) SnapshotFor(seat int) map[string]any {
	options := g.Options(seat)
	if options == nil {
		options = []ActionOption{}
	}
	counts := make([]int, 4)
	publicMelds := make([][]Meld, 4)
	for other := 0; other < 4; other++ {
		counts[other] = len(g.Hands[other])
		publicMelds[other] = make([]Meld, 0, len(g.Melds[other]))
		for _, meld := range g.Melds[other] {
			copyMeld := meld
			if other != seat && meld.Kind == "an_gang" {
				copyMeld.Tiles = make([]Tile, 4)
			}
			publicMelds[other] = append(publicMelds[other], copyMeld)
		}
	}
	hand := append([]Tile{}, g.Hands[seat]...)
	snapshot := map[string]any{
		"type": "mahjong_state", "phase": g.Phase, "turn": g.Turn, "your_seat": seat,
		"players": g.Players, "hand": hand, "hand_counts": counts, "melds": publicMelds,
		"discards": append([]Discard{}, g.Discards...), "remaining": g.Remaining(),
		"options": options, "winners": append([]int{}, g.Winners...),
		"win_from": g.WinFrom, "win_kind": g.WinKind, "scores": g.Scores,
		"reason": g.Reason, "epoch": g.Epoch, "last_discard": g.PendingTile,
		"wall_break_dice_total": g.WallBreakDiceTotal, "wall_break_side": g.WallBreakSide, "wall_break_stack": g.WallBreakStack,
		"flipped_ji": g.FlippedJi, "ji_counts": g.JiCounts, "ji_events": append([]JiEvent{}, g.JiEvents...),
		"action_events": append([]ActionEvent{}, g.actionEvents...),
	}
	if g.Phase == PhaseTurn && seat == g.Turn && g.LastDrawnID > 0 {
		if _, held := g.findTile(seat, g.LastDrawnID); held {
			snapshot["drawn_tile_id"] = g.LastDrawnID
		}
	}
	if breakdown := g.SettlementScoreBreakdown(); breakdown != nil {
		snapshot["score_breakdown"] = breakdown
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
