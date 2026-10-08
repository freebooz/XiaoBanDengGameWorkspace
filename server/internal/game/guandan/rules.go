package guandan

import (
	"errors"
	"sort"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/poker"
)

type Card = poker.Card
type Pattern struct { Kind string `json:"kind"`; Main int `json:"main"`; Length int `json:"length"` }
func NewDeck() []Card { return poker.Deck(2) }
func Natural(rank int) int { if rank==15 { return 2 };return rank }
func Strength(rank,level int) int { value:=Natural(rank);if value==level { return 15 };return value }
func IsWild(card Card,level int) bool { return card.Suit=="heart" && Natural(card.Rank)==level }
func SortHand(cards []Card,level int) { sort.Slice(cards,func(i,j int)bool{ a,b:=Strength(cards[i].Rank,level),Strength(cards[j].Rank,level);if a==b { return cards[i].ID<cards[j].ID };return a<b }) }

func tier(p Pattern) int { switch p.Kind { case "rocket":return 100;case "straight_flush":return 60;case "bomb":if p.Length>=6 { return 70+p.Length };return 40+p.Length;case "triple_straight":return 20;case "pair_straight":return 19;case "triple_pair":return 18;case "straight":return 17;case "triple":return 16;case "pair":return 15;default:return 14 } }
func Beats(next,current Pattern) bool {
	nt,ct:=tier(next),tier(current)
	if nt>=40 || ct>=40 { if nt!=ct { return nt>ct };if next.Kind!=current.Kind { return false };return next.Main>current.Main }
	return next.Kind==current.Kind && next.Length==current.Length && next.Main>current.Main
}

// Choose searches the at most two heart level cards; suits may be substituted for a flush.
func Choose(cards []Card,level int,current *Pattern) (Pattern,error) {
	if len(cards)==0 || len(cards)>10 { return Pattern{},errors.New("请选择合法数量的牌") }
	for _, card := range cards { if card.Rank < 3 || card.Rank > 17 { return Pattern{}, errors.New("无效扑克牌") } }
	if len(cards)==1 { p:=Pattern{"single",Strength(cards[0].Rank,level),1};if current!=nil && !Beats(p,*current) { return Pattern{},errors.New("所选单牌无法压过上手") };return p,nil }
	ranks:=make([]int,len(cards));wilds:=[]int{}
	flushSuit:="";flushPossible:=true
	for i,card:=range cards {
		if card.Rank<3 || card.Rank>17 { return Pattern{},errors.New("无效扑克牌") }
		ranks[i]=Natural(card.Rank)
		if IsWild(card,level) { wilds=append(wilds,i) } else { if flushSuit=="" { flushSuit=card.Suit };if flushSuit!=card.Suit || card.Rank>=16 { flushPossible=false } }
	}
	if len(wilds)>2 { return Pattern{},errors.New("配牌数量错误") }
	patterns:=map[Pattern]bool{}
	var evaluate func(int)
	evaluate=func(index int) {
		if index<len(wilds) { for rank:=2;rank<=14;rank++ { ranks[wilds[index]]=rank;evaluate(index+1) };return }
		for _,p:=range naturalPatterns(ranks,level,flushPossible) { if current==nil || Beats(p,*current) { patterns[p]=true } }
	}
	evaluate(0)
	if len(patterns)==0 { return Pattern{},errors.New("所选牌不符合掼蛋牌型或不能压过上手") }
	choices:=make([]Pattern,0,len(patterns));for p:=range patterns { choices=append(choices,p) }
	sort.Slice(choices,func(i,j int)bool { a,b:=choices[i],choices[j];if tier(a)!=tier(b) { return tier(a)<tier(b) };if a.Main!=b.Main { return a.Main<b.Main };return a.Kind<b.Kind })
	if current!=nil { return choices[0],nil };return choices[len(choices)-1],nil
}

func naturalPatterns(ranks []int,level int,flush bool) []Pattern {
	n:=len(ranks);counts:=map[int]int{};for _,rank:=range ranks { counts[rank]++ }
	keys:=[]int{};for rank:=range counts { keys=append(keys,rank) };sort.Ints(keys)
	value:=func(rank int)int { if rank==level { return 15 };return rank }
	result:=[]Pattern{}
	if n==4 && counts[16]==2 && counts[17]==2 { return []Pattern{{"rocket",17,4}} }
	if len(keys)==1 {
		rank:=keys[0]
		if n==2 && (rank<=14 || rank==16 || rank==17) { result=append(result,Pattern{"pair",value(rank),n}) }
		if n==3 && rank<=14 { result=append(result,Pattern{"triple",value(rank),n}) }
		if n>=4 && rank<=14 { result=append(result,Pattern{"bomb",value(rank),n}) }
	}
	if n==5 && len(keys)==2 { for rank,count:=range counts { if count==3 && rank<=14 { for other,c:=range counts { if other!=rank && c==2 { result=append(result,Pattern{"triple_pair",value(rank),n}) } } } } }
	check:=func(groupSize,groups int,kind string) {
		if n!=groupSize*groups || len(keys)!=groups { return }
		for _,rank:=range keys { if rank>14 || counts[rank]!=groupSize { return } }
		ordered:=append([]int(nil),keys...)
		valid:=true;for i:=1;i<len(ordered);i++ { if ordered[i]!=ordered[i-1]+1 { valid=false } }
		high:=ordered[len(ordered)-1]
		if !valid && counts[14]==groupSize { for i,rank:=range ordered { if rank==14 { ordered[i]=1 } };sort.Ints(ordered);valid=true;for i:=1;i<len(ordered);i++ { if ordered[i]!=ordered[i-1]+1 { valid=false } };high=ordered[len(ordered)-1] }
		if valid { result=append(result,Pattern{kind,high,n});if kind=="straight" && flush { result=append(result,Pattern{"straight_flush",high,n}) } }
	}
	check(1,5,"straight");check(2,3,"pair_straight");check(3,2,"triple_straight")
	return result
}
