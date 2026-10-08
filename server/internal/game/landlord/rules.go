package landlord

import (
	"errors"
	"sort"
"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/poker"
)

// Shared poker face schema; Landlord uses one deck, Guandan uses two.
type Card = poker.Card
func CardFromID(id int) Card { if id < 0 || id > 53 { return Card{} }; return poker.FromID(id) }
func NewDeck() []Card { return poker.Deck(1) }

func SortHand(hand []Card) {
	sort.Slice(hand, func(i, j int) bool {
		if hand[i].Rank == hand[j].Rank {
			return hand[i].ID < hand[j].ID
		}
		return hand[i].Rank < hand[j].Rank
	})
}

type Pattern struct {
	Kind   string `json:"kind"`
	Main   int    `json:"main"`
	Length int    `json:"length"`
}

// Classify recognizes all common three-player Dou Dizhu combinations.
func Classify(cards []Card) (Pattern, error) {
	n := len(cards)
	if n == 0 {
		return Pattern{}, errors.New("请选择要出的牌")
	}
	count := map[int]int{}
	for _, card := range cards {
		if card.Rank < 3 || card.Rank > 17 {
			return Pattern{}, errors.New("无效扑克牌")
		}
		count[card.Rank]++
	}
	keys := make([]int, 0, len(count))
	for rank := range count {
		keys = append(keys, rank)
	}
	sort.Ints(keys)
	if n == 1 {
		return Pattern{"single", keys[0], n}, nil
	}
	if n == 2 {
		if count[16] == 1 && count[17] == 1 {
			return Pattern{"rocket", 17, n}, nil
		}
		if len(keys) == 1 {
			return Pattern{"pair", keys[0], n}, nil
		}
	}
	if n == 3 && len(keys) == 1 {
		return Pattern{"triple", keys[0], n}, nil
	}
	if n == 4 {
		if len(keys) == 1 {
			return Pattern{"bomb", keys[0], n}, nil
		}
		for rank, quantity := range count {
			if quantity == 3 {
				return Pattern{"triple_single", rank, n}, nil
			}
		}
	}
	if n == 5 {
		for rank, quantity := range count {
			if quantity == 3 && len(keys) == 2 {
				for _, other := range keys {
					if other != rank && count[other] == 2 {
						return Pattern{"triple_pair", rank, n}, nil
					}
				}
			}
		}
	}
	if n >= 5 && consecutive(keys) && len(keys) == n && keys[len(keys)-1] <= 14 {
		return Pattern{"straight", keys[len(keys)-1], n}, nil
	}
	if n >= 6 && n%2 == 0 && len(keys) == n/2 && consecutive(keys) && keys[len(keys)-1] <= 14 && allCount(count, keys, 2) {
		return Pattern{"pair_straight", keys[len(keys)-1], n}, nil
	}
	if n >= 6 && n%3 == 0 && len(keys) == n/3 && consecutive(keys) && keys[len(keys)-1] <= 14 && allCount(count, keys, 3) {
		return Pattern{"airplane", keys[len(keys)-1], n}, nil
	}
	if n == 6 || n == 8 {
		for rank, quantity := range count {
			if quantity != 4 {
				continue
			}
			if n == 6 {
				return Pattern{"four_two_single", rank, n}, nil
			}
			if len(keys) == 3 {
				pairCount := 0
				for other, c := range count {
					if other != rank && c == 2 {
						pairCount++
					}
				}
				if pairCount == 2 {
					return Pattern{"four_two_pair", rank, n}, nil
				}
			}
		}
	}
	// Consecutive triple cores with one single or one pair wing per triple.
	for _, wingSize := range []int{1, 2} {
		groupSize := 3 + wingSize
		if n < groupSize*2 || n%groupSize != 0 {
			continue
		}
		groups := n / groupSize
		for high := 3 + groups - 1; high <= 14; high++ {
			low := high - groups + 1
			core := true
			for rank := low; rank <= high; rank++ {
				if count[rank] != 3 {
					core = false
					break
				}
			}
			if !core {
				continue
			}
			wings := 0
			wingRanks := 0
			valid := true
			for rank, quantity := range count {
				if rank >= low && rank <= high {
					continue
				}
				wings += quantity
				if wingSize == 2 {
					if quantity != 2 {
						valid = false
					}
					wingRanks++
				}
			}
			if valid && wings == groups*wingSize && (wingSize == 1 || wingRanks == groups) {
				kind := "airplane_single"
				if wingSize == 2 {
					kind = "airplane_pair"
				}
				return Pattern{kind, high, n}, nil
			}
		}
	}
	return Pattern{}, errors.New("不符合斗地主牌型")
}

func consecutive(keys []int) bool {
	for i := 1; i < len(keys); i++ {
		if keys[i] != keys[i-1]+1 {
			return false
		}
	}
	return true
}
func allCount(count map[int]int, keys []int, want int) bool {
	for _, rank := range keys {
		if count[rank] != want {
			return false
		}
	}
	return true
}

func Beats(next, current Pattern) bool {
	if next.Kind == "rocket" {
		return current.Kind != "rocket"
	}
	if current.Kind == "rocket" {
		return false
	}
	if next.Kind == "bomb" && current.Kind != "bomb" {
		return true
	}
	return next.Kind == current.Kind && next.Length == current.Length && next.Main > current.Main
}
