package landlord

import (
	"errors"
	"fmt"
	"math/rand"
	"sort"
)

const (
	PhaseBid      = "bid"
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
			*g = *fresh
			return nil
		}
		g.Landlord = g.HighestBidder
		g.Hands[g.Landlord] = append(g.Hands[g.Landlord], g.Bottom...)
		SortHand(g.Hands[g.Landlord])
		g.Turn = g.Landlord
		g.Phase = PhasePlay
	} else {
		g.Turn = (g.Turn + 1) % 3
	}
	return nil
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
	if g.Phase == PhaseFinished {
		state["hands_revealed"] = g.Hands
	}
	return state
}
