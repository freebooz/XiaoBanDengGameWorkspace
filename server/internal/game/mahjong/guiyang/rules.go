package guiyang

import (
	"errors"
	"sort"
)

// Tile（麻将牌）采用 Suit + Rank 的稳定数据模型。
type Tile struct { Suit string `json:"suit"`; Rank int `json:"rank"` }

// RuleSet（贵阳麻将规则集）与麻将公共核心分离。
type RuleSet struct { ID string; Version string }

// NewRuleSet（创建贵阳麻将规则集）返回一期固定版本。
func NewRuleSet() RuleSet { return RuleSet{ID:"guiyang",Version:"1.0.0"} }

// BuildWall（构建牌墙）创建136张标准基础牌。
func (r RuleSet) BuildWall() []Tile {
	wall:=make([]Tile,0,136)
	for _,suit:=range []string{"wan","tong","tiao"} {
		for rank:=1; rank<=9; rank++ { for i:=0;i<4;i++ { wall=append(wall,Tile{Suit:suit,Rank:rank}) } }
	}
	for rank:=1; rank<=7; rank++ { for i:=0;i<4;i++ { wall=append(wall,Tile{Suit:"honor",Rank:rank}) } }
	return wall
}

// ValidateDiscard（校验出牌）确保玩家只能打出自己持有的牌。
func (r RuleSet) ValidateDiscard(hand []Tile,tile Tile) error {
	for _,item:=range hand { if item==tile { return nil } }
	return errors.New("不能打出手牌中不存在的麻将牌")
}

// SortHand（整理手牌）提供稳定排序。
func SortHand(hand []Tile) {
	order:=map[string]int{"wan":0,"tong":1,"tiao":2,"honor":3}
	sort.SliceStable(hand,func(i,j int) bool {
		if order[hand[i].Suit]!=order[hand[j].Suit] { return order[hand[i].Suit]<order[hand[j].Suit] }
		return hand[i].Rank<hand[j].Rank
	})
}

// CanPeng（可碰判断）是响应窗口的基础规则入口。
func (r RuleSet) CanPeng(hand []Tile,discarded Tile) bool {
	count:=0
	for _,item:=range hand { if item==discarded { count++ } }
	return count>=2
}

// CanGangFromDiscard（明杠判断）要求手中三张相同牌。
func (r RuleSet) CanGangFromDiscard(hand []Tile,discarded Tile) bool {
	count:=0
	for _,item:=range hand { if item==discarded { count++ } }
	return count>=3
}

// CanHu（胡牌入口）一期不伪造贵阳地方番型，保留确定性规则边界。
func (r RuleSet) CanHu(hand []Tile,incoming Tile) (bool,string) {
	if len(hand)+1!=14 { return false,"当前牌数不满足标准胡牌输入" }
	return false,"贵阳麻将完整胡牌/番型算法须按正式规则验收文档继续实现"
}