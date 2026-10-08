package landlord

import (
	"errors"
	"fmt"
	"math/rand"
	"sort"
)

const (
	PhaseBid      = "bid"
	PhaseDouble   = "double"
	PhasePlay     = "play"
	PhaseFinished = "finished"
)

type Play struct {
	Seat    int     `json:"seat"`
	Cards   []Card  `json:"cards"`
	Pattern Pattern `json:"pattern"`
}

// Game owns all hidden cards; SnapshotFor is the only public state projection.
type Game struct {
	seed          int64
	DealNumber    int
	Players       [3]string
	Hands         [3][]Card
	Bottom        []Card
	Phase         string
	Turn          int
	Landlord      int
	HighestBid    int
	HighestBidder int
	Bids          [3]int
	BidCount      int
	LastPlay      Play
	HasLastPlay   bool
	PassCount     int
	History       []Play
	Winner        int
	Multiplier    int
	Scores        [3]int
	LandlordPlays int
	FarmerPlays   int
	Epoch         int
	// Opt in for the reference battle UI; existing NewGame callers retain bid -> play.
	EnableDoubling bool
	DoubleDecided  [3]bool
	Doubled        [3]bool
}

func NewGame(players [3]string, seed int64) *Game {
	deck := NewDeck()
	rng := rand.New(rand.NewSource(seed))
	rng.Shuffle(len(deck), func(i, j int) { deck[i], deck[j] = deck[j], deck[i] })
	g := &Game{seed: seed, Players: players, Phase: PhaseBid, Turn: 0, Landlord: -1, HighestBidder: -1, Winner: -1, Multiplier: 1, Epoch: 1}
	for i := 0; i < 51; i++ {
		g.Hands[i%3] = append(g.Hands[i%3], deck[i])
	}
	g.Bottom = append([]Card(nil), deck[51:]...)
	for seat := 0; seat < 3; seat++ {
		SortHand(g.Hands[seat])
	}
	return g
}

func (g *Game) Bid(seat, amount int) error {
	if g.Phase != PhaseBid || seat != g.Turn {
		return errors.New("现在不是你的叫地主回合")
	}
	if amount < 0 || amount > 3 || (amount != 0 && amount <= g.HighestBid) {
		return errors.New("叫分须高于当前分数，或选择不叫")
	}
	g.Bids[seat] = amount
	g.BidCount++
	if amount > g.HighestBid {
		g.HighestBid = amount
		g.HighestBidder = seat
	}
	g.Epoch++
	if amount == 3 || g.BidCount == 3 {
		if g.HighestBidder < 0 {
			fresh := NewGame(g.Players, g.seed+int64(g.DealNumber+1))
			fresh.seed = g.seed
			fresh.DealNumber = g.DealNumber + 1
			fresh.Epoch = g.Epoch + 1
			fresh.EnableDoubling = g.EnableDoubling
			*g = *fresh
			return nil
		}
		g.Landlord = g.HighestBidder
		g.Hands[g.Landlord] = append(g.Hands[g.Landlord], g.Bottom...)
		SortHand(g.Hands[g.Landlord])
		g.Turn = g.Landlord
		g.Phase = PhasePlay
		if g.EnableDoubling {
			g.Phase = PhaseDouble
		}
	} else {
		g.Turn = (g.Turn + 1) % 3
	}
	return nil
}

// Double uses a shared table multiplier: each player's affirmative decision doubles it.
// Decisions are sequential from the landlord, so the existing action timer remains authoritative.
func (g *Game) Double(seat int, enabled bool) error {
	if seat < 0 || seat >= 3 || g.Phase != PhaseDouble || seat != g.Turn || g.DoubleDecided[seat] {
		return errors.New("现在不是你的加倍回合，或已经决定")
	}
	g.DoubleDecided[seat], g.Doubled[seat] = true, enabled
	if enabled {
		g.Multiplier *= 2
	}
	g.Epoch++
	for offset := 1; offset <= 3; offset++ {
		next := (seat + offset) % 3
		if !g.DoubleDecided[next] {
			g.Turn = next
			return nil
		}
	}
	g.Phase, g.Turn = PhasePlay, g.Landlord
	return nil
}

// SuggestedCards returns only owned cards accepted by the same classifier and comparison
// used by PlayCards. It searches rank combinations (not duplicate suit permutations),
// covering compound patterns and falling back to bombs/rocket without mutating the game.
func (g *Game) SuggestedCards(seat int) []int {
	if seat < 0 || seat >= 3 || g.Phase != PhasePlay || seat != g.Turn || len(g.Hands[seat]) == 0 {
		return []int{}
	}
	hand := append([]Card(nil), g.Hands[seat]...)
	SortHand(hand)
	if !g.HasLastPlay || g.LastPlay.Seat == seat {
		return []int{hand[0].ID}
	}
	previous := g.LastPlay.Pattern
	if previous.Kind == "rocket" {
		return []int{}
	}
	groups := [][]Card{}
	for _, card := range hand {
		if len(groups) == 0 || groups[len(groups)-1][0].Rank != card.Rank {
			groups = append(groups, []Card{})
		}
		groups[len(groups)-1] = append(groups[len(groups)-1], card)
	}
	capacity := make([]int, len(groups)+1)
	for index := len(groups)-1; index >= 0; index-- {
		capacity[index] = capacity[index+1] + len(groups[index])
	}
	selected := []Card{}
	var found []int
	var search func(int, int) bool
	search = func(index, remaining int) bool {
		if remaining == 0 {
			pattern, err := Classify(selected)
			if err != nil || pattern.Kind != previous.Kind || !Beats(pattern, previous) {
				return false
			}
			found = make([]int, len(selected))
			for index, card := range selected { found[index] = card.ID }
			return true
		}
		if index == len(groups) || remaining > capacity[index] { return false }
		maximum := len(groups[index])
		if maximum > remaining { maximum = remaining }
		for count := maximum; count >= 0; count-- {
			length := len(selected)
			selected = append(selected, groups[index][:count]...)
			if search(index+1, remaining-count) { return true }
			selected = selected[:length]
		}
		return false
	}
	if search(0, previous.Length) { return found }
	for _, group := range groups {
		if len(group) < 4 { continue }
		pattern, err := Classify(group[:4])
		if err == nil && Beats(pattern, previous) {
			return []int{group[0].ID,group[1].ID,group[2].ID,group[3].ID}
		}
	}
	var small, big = -1, -1
	for _, card := range hand {
		if card.Rank == 16 { small = card.ID }
		if card.Rank == 17 { big = card.ID }
	}
	if small >= 0 && big >= 0 { return []int{small,big} }
	return []int{}
}

func (g *Game) PlayCards(seat int, ids []int) error {
	if g.Phase != PhasePlay || seat != g.Turn {
		return errors.New("现在不是你的出牌回合")
	}
	if len(ids) == 0 {
		return errors.New("请选择要出的牌")
	}
	seen := map[int]bool{}
	owned := map[int]Card{}
	for _, card := range g.Hands[seat] {
		owned[card.ID] = card
	}
	cards := make([]Card, 0, len(ids))
	for _, id := range ids {
		card, ok := owned[id]
		if !ok || seen[id] {
			return errors.New("选择的牌不在你的手牌中")
		}
		seen[id] = true
		cards = append(cards, card)
	}
	pattern, err := Classify(cards)
	if err != nil {
		return err
	}
	if g.HasLastPlay && g.LastPlay.Seat != seat && !Beats(pattern, g.LastPlay.Pattern) {
		return errors.New("出牌必须大过上一手，或选择不出")
	}
	remaining := make([]Card, 0, len(g.Hands[seat])-len(cards))
	for _, card := range g.Hands[seat] {
		if !seen[card.ID] {
			remaining = append(remaining, card)
		}
	}
	g.Hands[seat] = remaining
	sort.Slice(cards, func(i, j int) bool { return cards[i].Rank < cards[j].Rank })
	g.LastPlay = Play{Seat: seat, Cards: cards, Pattern: pattern}
	g.HasLastPlay = true
	g.History = append(g.History, g.LastPlay)
	g.PassCount = 0
	if pattern.Kind == "bomb" || pattern.Kind == "rocket" {
		g.Multiplier *= 2
	}
	if seat == g.Landlord {
		g.LandlordPlays++
	} else {
		g.FarmerPlays++
	}
	g.Epoch++
	if len(remaining) == 0 {
		g.finish(seat)
	} else {
		g.Turn = (seat + 1) % 3
	}
	return nil
}

func (g *Game) Pass(seat int) error {
	if g.Phase != PhasePlay || seat != g.Turn {
		return errors.New("现在不是你的回合")
	}
	if !g.HasLastPlay || g.LastPlay.Seat == seat {
		return errors.New("新一轮必须出牌")
	}
	g.PassCount++
	g.Epoch++
	if g.PassCount >= 2 {
		g.Turn = g.LastPlay.Seat
		g.HasLastPlay = false
		g.PassCount = 0
	} else {
		g.Turn = (seat + 1) % 3
	}
	return nil
}

func (g *Game) finish(winner int) {
	g.Winner = winner
	g.Phase = PhaseFinished
	if winner == g.Landlord && g.FarmerPlays == 0 {
		g.Multiplier *= 2
	}
	if winner != g.Landlord && g.LandlordPlays == 1 {
		g.Multiplier *= 2
	}
	points := g.HighestBid * g.Multiplier
	if winner == g.Landlord {
		g.Scores[g.Landlord] = 2 * points
		for i := 0; i < 3; i++ {
			if i != g.Landlord {
				g.Scores[i] = -points
			}
		}
	} else {
		g.Scores[g.Landlord] = -2 * points
		for i := 0; i < 3; i++ {
			if i != g.Landlord {
				g.Scores[i] = points
			}
		}
	}
}

func (g *Game) Timeout() {
	if g.Phase == PhaseDouble {
		_ = g.Double(g.Turn, false)
		return
	}
	if g.Phase == PhaseBid {
		_ = g.Bid(g.Turn, 0)
		return
	}
	if g.Phase != PhasePlay {
		return
	}
	if g.HasLastPlay && g.LastPlay.Seat != g.Turn {
		_ = g.Pass(g.Turn)
		return
	}
	if len(g.Hands[g.Turn]) > 0 {
		_ = g.PlayCards(g.Turn, []int{g.Hands[g.Turn][0].ID})
	}
}

// BotTurn uses the same rule validator as human play; it is intentionally simple training opposition.
func (g *Game) BotTurn(seat int) error {
	if seat != g.Turn {
		return errors.New("不是电脑玩家回合")
	}
	if g.Phase == PhaseBid {
		return g.Bid(seat, 0)
	}
	if g.Phase == PhaseDouble {
		return g.Double(seat, false)
	}
	if g.Phase != PhasePlay {
		return nil
	}
	if g.HasLastPlay && g.LastPlay.Seat != seat {
		if seat != g.Landlord && g.LastPlay.Seat != g.Landlord {
			return g.Pass(seat)
		}
		needed := 0
		switch g.LastPlay.Pattern.Kind {
		case "single":
			needed = 1
		case "pair":
			needed = 2
		case "triple":
			needed = 3
		}
		if needed > 0 {
			for _, card := range g.Hands[seat] {
				if card.Rank <= g.LastPlay.Pattern.Main {
					continue
				}
				ids := make([]int, 0, needed)
				for _, candidate := range g.Hands[seat] {
					if candidate.Rank == card.Rank && len(ids) < needed {
						ids = append(ids, candidate.ID)
					}
				}
				if len(ids) == needed {
					return g.PlayCards(seat, ids)
				}
			}
		}
		return g.Pass(seat)
	}
	if len(g.Hands[seat]) == 0 {
		return nil
	}
	return g.PlayCards(seat, []int{g.Hands[seat][0].ID})
}

func (g *Game) SnapshotFor(seat int) map[string]any {
	if seat < 0 || seat >= 3 {
		panic(fmt.Sprintf("invalid seat %d", seat))
	}
	counts := [3]int{}
	for i := range counts {
		counts[i] = len(g.Hands[i])
	}
	bottom := []Card{}
	if g.Phase != PhaseBid {
		bottom = g.Bottom
	}
	hand := append([]Card(nil), g.Hands[seat]...)
	state := map[string]any{"type": "landlord_state", "phase": g.Phase, "turn": g.Turn, "your_seat": seat, "players": g.Players, "hand": hand, "hand_counts": counts, "bottom": bottom, "landlord": g.Landlord, "highest_bid": g.HighestBid, "bids": g.Bids, "deal_number": g.DealNumber, "last_play": g.LastPlay, "has_last_play": g.HasLastPlay, "pass_count": g.PassCount, "winner": g.Winner, "multiplier": g.Multiplier, "scores": g.Scores, "epoch": g.Epoch}
	state["double_decided"], state["doubled"] = g.DoubleDecided, g.Doubled
	if g.Phase == PhaseFinished {
		state["hands_revealed"] = g.Hands
	}
	return state
}
