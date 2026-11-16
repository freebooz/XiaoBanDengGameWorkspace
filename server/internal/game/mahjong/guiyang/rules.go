package guiyang

import (
	"errors"
	"sort"
)

// Tile 的 ID 是服务器生成的实体牌编号，牌型比较仅使用 Suit 和 Rank。
type Tile struct {
	ID   int    `json:"id"`
	Suit string `json:"suit"`
	Rank int    `json:"rank"`
}

type RuleSet struct {
	ID      string
	Version string
	options RuleOptions
}

func NewRuleSet() RuleSet { return RuleSet{ID: "guiyang", Version: "2.0.0"} }

const RuleOptionsVersion = "1.0.0"

// RuleOptions is the complete value of a friend's room rules. The schema
// versions the switches and their semantics independently of the base preset.
type RuleOptions struct {
	Version             string `json:"version"`
	Chicken             bool   `json:"chicken"`
	ChargeChicken       bool   `json:"charge_chicken"`
	BlackEight          bool   `json:"black_eight"`
	RequiresKongToClaim bool   `json:"requires_kong_to_claim"`
	RobKong             bool   `json:"rob_kong"`
}

type RuleDescriptor struct {
	ID                  string      `json:"rule_set_id"`
	Version             string      `json:"rule_version"`
	Name                string      `json:"name"`
	Summary             string      `json:"summary"`
	AllowChi            bool        `json:"allow_chi"`
	Chicken             bool        `json:"chicken"`
	RequiresKongToClaim bool        `json:"requires_kong_to_claim"`
	Options             RuleOptions `json:"options"`
}

func RuleDescriptors() []RuleDescriptor {
	return []RuleDescriptor{
		{ID: "guiyang", Version: "2.0.0", Name: "贵阳捉鸡", Summary: "四人108张，不吃；点炮与抢杠胡须已完成一个杠，计鸡分，首胡窗口结算。", Chicken: true, RequiresKongToClaim: true,
			Options: RuleOptions{Version: RuleOptionsVersion, Chicken: true, ChargeChicken: true, BlackEight: true, RequiresKongToClaim: true, RobKong: true}},
		{ID: "basic_108", Version: "1.0.0", Name: "基础 108", Summary: "四人108张，不吃；无杠也可点炮与抢杠胡，不计鸡分，首胡窗口结算。",
			Options: RuleOptions{Version: RuleOptionsVersion, RobKong: true}},
	}
}

func FindRuleDescriptor(id, version string) (RuleDescriptor, bool) {
	for _, rule := range RuleDescriptors() {
		if id == rule.ID && version == rule.Version {
			return rule, true
		}
	}
	return RuleDescriptor{}, false
}

// ResolveRuleDescriptor normalizes dependencies and returns the effective rules.
// A nil override selects the preset defaults. A supplied override is complete.
func ResolveRuleDescriptor(id, version string, options *RuleOptions) (RuleDescriptor, error) {
	descriptor, exists := FindRuleDescriptor(id, version)
	if !exists {
		return RuleDescriptor{}, errors.New("未知的麻将玩法或版本")
	}
	if options == nil {
		return descriptor, nil
	}
	if options.Version != RuleOptionsVersion {
		return RuleDescriptor{}, errors.New("未知的麻将自定义规则版本")
	}
	effective := *options
	if !effective.Chicken {
		effective.ChargeChicken = false
		effective.BlackEight = false
	}
	if effective != descriptor.Options {
		descriptor.Summary = "四人108张，不吃；点炮、抢杠胡及鸡分按本房设置，首胡窗口结算。"
	}
	descriptor.Options = effective
	descriptor.Chicken = effective.Chicken
	descriptor.RequiresKongToClaim = effective.RequiresKongToClaim
	return descriptor, nil
}

func (r RuleDescriptor) RuleSet() RuleSet {
	return RuleSet{ID: r.ID, Version: r.Version, options: r.Options}
}

func (r RuleSet) effectiveOptions() RuleOptions {
	if r.options.Version == RuleOptionsVersion {
		return r.options
	}
	descriptor, _ := FindRuleDescriptor(r.ID, r.Version)
	return descriptor.Options
}

func (r RuleSet) chickenEnabled() bool {
	return r.effectiveOptions().Chicken
}

func (r RuleSet) requiresKongToClaim() bool {
	return r.effectiveOptions().RequiresKongToClaim
}

// BuildWall 与虚幻 GuiyangMainstreamV1 v2 一致：万、筒、条各一至九，四张一型。
func (r RuleSet) BuildWall() []Tile {
	wall := make([]Tile, 0, 108)
	for _, suit := range []string{"wan", "tong", "tiao"} {
		for rank := 1; rank <= 9; rank++ {
			for copyIndex := 0; copyIndex < 4; copyIndex++ {
				wall = append(wall, Tile{ID: len(wall) + 1, Suit: suit, Rank: rank})
			}
		}
	}
	return wall
}

func sameType(a, b Tile) bool { return a.Suit == b.Suit && a.Rank == b.Rank }

func validType(tile Tile) bool {
	if tile.Rank < 1 || tile.Rank > 9 {
		return false
	}
	return tile.Suit == "wan" || tile.Suit == "tong" || tile.Suit == "tiao"
}

func (r RuleSet) ValidateDiscard(hand []Tile, tile Tile) error {
	for _, item := range hand {
		if tile.ID > 0 && item.ID == tile.ID {
			return nil
		}
		if tile.ID == 0 && sameType(item, tile) {
			return nil
		}
	}
	return errors.New("不能打出手牌中不存在的麻将牌")
}

func SortHand(hand []Tile) {
	order := map[string]int{"wan": 0, "tong": 1, "tiao": 2}
	sort.SliceStable(hand, func(i, j int) bool {
		if order[hand[i].Suit] != order[hand[j].Suit] {
			return order[hand[i].Suit] < order[hand[j].Suit]
		}
		if hand[i].Rank != hand[j].Rank {
			return hand[i].Rank < hand[j].Rank
		}
		return hand[i].ID < hand[j].ID
	})
}

func CountType(hand []Tile, target Tile) int {
	count := 0
	for _, item := range hand {
		if sameType(item, target) {
			count++
		}
	}
	return count
}

func (r RuleSet) CanPeng(hand []Tile, discarded Tile) bool { return CountType(hand, discarded) >= 2 }
func (r RuleSet) CanGangFromDiscard(hand []Tile, discarded Tile) bool {
	return CountType(hand, discarded) >= 3
}

func (r RuleSet) CanHu(hand []Tile, incoming Tile) (bool, string) {
	all := append(append([]Tile(nil), hand...), incoming)
	return r.CanHuHand(all, 0)
}

// CanHuHand 检查四副面子一对将或七对。meldCount 是已完成的碰/杠数。
func (r RuleSet) CanHuHand(hand []Tile, meldCount int) (bool, string) {
	requiredMelds := 4 - meldCount
	if requiredMelds < 0 || len(hand) != requiredMelds*3+2 {
		return false, "手牌张数不符合胡牌结构"
	}
	var counts [27]int
	for _, tile := range hand {
		index := tileIndex(tile)
		if index < 0 {
			return false, "存在无效牌型"
		}
		counts[index]++
		if counts[index] > 4 {
			return false, "同种牌不能超过四张"
		}
	}
	if meldCount == 0 {
		pairs := 0
		for _, count := range counts {
			pairs += count / 2
		}
		if pairs == 7 {
			return true, "七对"
		}
	}
	for pairIndex := range counts {
		if counts[pairIndex] < 2 {
			continue
		}
		counts[pairIndex] -= 2
		if canFormMelds(&counts, requiredMelds) {
			return true, "平胡"
		}
		counts[pairIndex] += 2
	}
	return false, "手牌未组成有效牌型"
}

func tileIndex(tile Tile) int {
	if !validType(tile) {
		return -1
	}
	suitBase := map[string]int{"wan": 0, "tong": 9, "tiao": 18}[tile.Suit]
	return suitBase + tile.Rank - 1
}

func canFormMelds(counts *[27]int, required int) bool {
	first := -1
	for index, count := range counts {
		if count > 0 {
			first = index
			break
		}
	}
	if required == 0 {
		return first == -1
	}
	if first == -1 {
		return false
	}
	if counts[first] >= 3 {
		counts[first] -= 3
		if canFormMelds(counts, required-1) {
			counts[first] += 3
			return true
		}
		counts[first] += 3
	}
	if first%9 <= 6 && counts[first+1] > 0 && counts[first+2] > 0 {
		counts[first]--
		counts[first+1]--
		counts[first+2]--
		if canFormMelds(counts, required-1) {
			counts[first]++
			counts[first+1]++
			counts[first+2]++
			return true
		}
		counts[first]++
		counts[first+1]++
		counts[first+2]++
	}
	return false
}
