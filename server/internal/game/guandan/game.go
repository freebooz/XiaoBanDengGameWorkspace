package guandan

import (
	"errors"
	"math/rand"
	"sort"
)

const ( PhasePlay="play";PhaseTribute="tribute";PhaseReturn="return";PhaseRoundFinished="round_finished";PhaseFinished="finished" )
type Play struct { Seat int `json:"seat"`; Cards []Card `json:"cards"`; Pattern Pattern `json:"pattern"` }
type Exchange struct { From int `json:"from"`; To int `json:"to"`; Card Card `json:"card"`; Returned bool `json:"returned"`; ReturnCard *Card `json:"return_card,omitempty"` }
type Game struct {
	Players [4]string
	Hands [4][]Card
	Phase string
	Turn int
	LevelRank int
	TeamLevels [2]int
	ActiveTeam int
	Round int
	Epoch int
	LastPlay Play
	HasLastPlay bool
	FinishOrder []int
	RoundWinner int
	RoundAdvance int
	MatchWinner int
	RoundReady [4]bool
	Tributes []Exchange
	AntiTribute bool
	Reason string
	seed int64
	followers map[int]bool
	donors []int
	given map[int]Card
	tributeLeader int
}

func NewGame(players [4]string,seed int64) *Game {
	g:=&Game{Players:players,TeamLevels:[2]int{2,2},LevelRank:2,ActiveTeam:0,MatchWinner:-1,RoundWinner:-1,seed:seed}
	g.deal(nil)
	return g
}

func (g *Game) deal(previous []int) {
	g.Round++;g.Epoch++;g.Phase=PhasePlay;g.FinishOrder=[]int{};g.RoundReady=[4]bool{};g.HasLastPlay=false;g.LastPlay=Play{Seat:-1};g.Tributes=[]Exchange{};g.AntiTribute=false;g.given=map[int]Card{};g.followers=map[int]bool{};g.donors=nil
	deck:=NewDeck();rng:=rand.New(rand.NewSource(g.seed+int64(g.Round)*7919));rng.Shuffle(len(deck),func(i,j int){deck[i],deck[j]=deck[j],deck[i]})
	g.Hands=[4][]Card{};for i,card:=range deck { g.Hands[i%4]=append(g.Hands[i%4],card) }
	for seat:=range g.Hands { SortHand(g.Hands[seat],g.LevelRank) }
	g.Turn=rng.Intn(4)
	if len(previous)==4 { g.setupTribute(previous) }
}

func (g *Game) nextActive(after int) int { for offset:=1;offset<=4;offset++ { seat:=(after+offset)%4;if len(g.Hands[seat])>0 { return seat } };return -1 }
func (g *Game) PlayCards(seat int,ids []int) error {
	if seat<0 || seat>=4 || g.Phase!=PhasePlay || seat!=g.Turn { return errors.New("现在不是你的出牌回合") }
	if len(ids)==0 || len(ids)>10 { return errors.New("请选择合法数量的手牌") }
	owned:=map[int]Card{};for _,card:=range g.Hands[seat] { owned[card.ID]=card }
	cards:=make([]Card,0,len(ids));chosen:=map[int]bool{}
	for _,id:=range ids { card,ok:=owned[id];if !ok || chosen[id] { return errors.New("选牌不属于你的手牌或含重复编号") };chosen[id]=true;cards=append(cards,card) }
	var previous *Pattern
	if g.HasLastPlay { previous=&g.LastPlay.Pattern }
	pattern,err:=Choose(cards,g.LevelRank,previous);if err!=nil { return err }
	remaining:=[]Card{};for _,card:=range g.Hands[seat] { if !chosen[card.ID] { remaining=append(remaining,card) } };g.Hands[seat]=remaining
	g.LastPlay=Play{Seat:seat,Cards:cards,Pattern:pattern};g.HasLastPlay=true;g.Epoch++
	if len(remaining)==0 { g.FinishOrder=append(g.FinishOrder,seat) }
	if len(g.FinishOrder)>=3 { for i:=0;i<4;i++ { if len(g.Hands[i])>0 { g.FinishOrder=append(g.FinishOrder,i) } };g.finishRound();return nil }
	g.followers=map[int]bool{};for i:=0;i<4;i++ { if i!=seat && len(g.Hands[i])>0 { g.followers[i]=true } }
	g.Turn=g.nextActive(seat)
	return nil
}

func (g *Game) Pass(seat int) error {
	if seat<0 || seat>=4 || g.Phase!=PhasePlay || seat!=g.Turn { return errors.New("现在不是你的回合") }
	if !g.HasLastPlay || !g.followers[seat] { return errors.New("新一轮必须出牌") }
	delete(g.followers,seat);g.Epoch++
	if len(g.followers)==0 {
		leader:=g.LastPlay.Seat
		if len(g.Hands[leader])==0 { partner:=(leader+2)%4;if len(g.Hands[partner])>0 { leader=partner } else { leader=g.nextActive(leader) } }
		g.Turn=leader;g.HasLastPlay=false
	} else { next:=seat;for i:=0;i<4;i++ { next=(next+1)%4;if g.followers[next] { g.Turn=next;break } } }
	return nil
}

func (g *Game) finishRound() {
	head:=g.FinishOrder[0];team:=head%2;partnerPlace:=0
	for place,seat:=range g.FinishOrder { if seat==(head+2)%4 { partnerPlace=place+1 } }
	advance:=1;if partnerPlace==2 { advance=3 } else if partnerPlace==3 { advance=2 }
	g.RoundWinner=team;g.RoundAdvance=advance;g.Phase=PhaseRoundFinished
	if g.ActiveTeam==team && g.LevelRank==14 && partnerPlace<4 { g.MatchWinner=team;g.Phase=PhaseFinished;g.Reason="过A获胜";return }
	level:=g.TeamLevels[team];if level==2 { level=2+advance } else { level+=advance };if level>14 { level=14 }
	g.TeamLevels[team]=level;g.ActiveTeam=team
}

func (g *Game) ReadyNextRound(seat int) error {
	if seat<0 || seat>=4 || g.Phase!=PhaseRoundFinished { return errors.New("本副尚未结束或比赛已经结束") }
	if g.RoundReady[seat] { return nil }
	g.RoundReady[seat]=true;g.Epoch++
	for _,ready:=range g.RoundReady { if !ready { return nil } }
	previous:=append([]int(nil),g.FinishOrder...);g.LevelRank=g.TeamLevels[g.ActiveTeam];g.deal(previous)
	return nil
}

func (g *Game) setupTribute(order []int) {
	g.given=map[int]Card{};g.Tributes=[]Exchange{};g.donors=[]int{order[3]};g.AntiTribute=false
	if order[0]%2==order[1]%2 { g.donors=[]int{order[2],order[3]} }
	bigJokers:=0;for _,seat:=range g.donors { for _,card:=range g.Hands[seat] { if card.Rank==17 { bigJokers++ } } }
	g.tributeLeader=order[0]
	if bigJokers>=2 { g.AntiTribute=true;g.Phase=PhasePlay;g.Turn=order[0];return }
	g.Phase=PhaseTribute
	for index,donor:=range g.donors { receiver:=order[0];if index==1 { receiver=order[1] };g.Tributes=append(g.Tributes,Exchange{From:donor,To:receiver,Card:Card{ID:-1}}) }
	g.Turn=g.donors[0]
}

func (g *Game) EligibleTribute(seat int) []Card {
	if seat<0 || seat>=4 { return nil }
	best:=-1;cards:=[]Card{};for _,card:=range g.Hands[seat] { if IsWild(card,g.LevelRank) { continue };strength:=Strength(card.Rank,g.LevelRank);if strength>best { best=strength;cards=[]Card{card} } else if strength==best { cards=append(cards,card) } }
	return cards
}

func removeCard(cards []Card,id int) ([]Card,Card,bool) { for i,card:=range cards { if card.ID==id { return append(append([]Card{},cards[:i]...),cards[i+1:]...),card,true } };return cards,Card{},false }
func containsID(cards []Card,id int) bool { for _,card:=range cards { if card.ID==id { return true } };return false }

func (g *Game) SubmitTribute(seat,id int) error {
	if g.Phase!=PhaseTribute { return errors.New("当前不在进贡阶段") }
	donor:=false;for _,candidate:=range g.donors { if candidate==seat { donor=true } }
	if !donor { return errors.New("此座位无需进贡") };if _,ok:=g.given[seat];ok { return errors.New("已经提交贡牌") }
	if !containsID(g.EligibleTribute(seat),id) { return errors.New("须进贡最大的非红桃配牌") }
	remaining,card,_:=removeCard(g.Hands[seat],id);g.Hands[seat]=remaining;g.given[seat]=card;g.Epoch++
	for i:=range g.Tributes { if g.Tributes[i].From==seat { g.Tributes[i].Card=card } }
	if len(g.given)!=len(g.donors) { return nil }
	head:=g.tributeLeader
	sort.Slice(g.Tributes,func(i,j int)bool{ a,b:=g.Tributes[i],g.Tributes[j];sa,sb:=Strength(a.Card.Rank,g.LevelRank),Strength(b.Card.Rank,g.LevelRank);if sa!=sb { return sa>sb };return (a.From-head+4)%4<(b.From-head+4)%4 })
	for i:=range g.Tributes { receiver:=head;if i==1 { receiver=(head+2)%4 };g.Tributes[i].To=receiver;g.Hands[receiver]=append(g.Hands[receiver],g.Tributes[i].Card);SortHand(g.Hands[receiver],g.LevelRank) }
	g.tributeLeader=g.Tributes[0].From;g.Phase=PhaseReturn
	return nil
}

func (g *Game) EligibleReturn(seat int) []Card {
	if seat<0 || seat>=4 { return nil }
	candidates:=[]Card{};fallback:=[]Card{};lowest:=100
	for _,card:=range g.Hands[seat] {
		if IsWild(card,g.LevelRank) { continue }
		if Natural(card.Rank)<=10 { candidates=append(candidates,card) }
		rank:=Strength(card.Rank,g.LevelRank);if rank<lowest { lowest=rank;fallback=[]Card{card} } else if rank==lowest { fallback=append(fallback,card) }
	}
	if len(candidates)>0 { return candidates };return fallback
}

func (g *Game) ReturnCard(seat,id int) error {
	if g.Phase!=PhaseReturn { return errors.New("当前不在还贡阶段") }
	index:=-1;for i,exchange:=range g.Tributes { if exchange.To==seat && !exchange.Returned { index=i } };if index<0 { return errors.New("此座位无需还贡") }
	if !containsID(g.EligibleReturn(seat),id) { return errors.New("还贡须选不大于10的非配牌；无此类牌时还最小非配牌") }
	remaining,card,_:=removeCard(g.Hands[seat],id);g.Hands[seat]=remaining;donor:=g.Tributes[index].From;g.Hands[donor]=append(g.Hands[donor],card);SortHand(g.Hands[donor],g.LevelRank)
	g.Tributes[index].Returned=true;g.Tributes[index].ReturnCard=&card;g.Epoch++
	for _,exchange:=range g.Tributes { if !exchange.Returned { return nil } }
	g.Phase=PhasePlay;g.Turn=g.tributeLeader
	return nil
}

func (g *Game) Leave(seat int) error { if seat<0 || seat>=4 { return errors.New("无效座位") };if g.Phase==PhaseFinished { return nil };g.Phase=PhaseFinished;g.MatchWinner=1-seat%2;g.Reason="玩家离开对局";g.Epoch++;return nil }

func (g *Game) SuggestedCards(seat int) []int {
	if g.Phase!=PhasePlay || seat!=g.Turn || len(g.Hands[seat])==0 { return nil }
	var previous *Pattern;if g.HasLastPlay { previous=&g.LastPlay.Pattern }
	for _,card:=range g.Hands[seat] { if _,err:=Choose([]Card{card},g.LevelRank,previous);err==nil { return []int{card.ID} } }
	groups:=map[int][]Card{};for _,card:=range g.Hands[seat] { groups[card.Rank]=append(groups[card.Rank],card) }
	ranks:=[]int{};for rank:=range groups { ranks=append(ranks,rank) };sort.Slice(ranks,func(i,j int)bool{return Strength(ranks[i],g.LevelRank)<Strength(ranks[j],g.LevelRank)})
	for _,rank:=range ranks { for count:=2;count<=len(groups[rank]);count++ { if _,err:=Choose(groups[rank][:count],g.LevelRank,previous);err==nil { ids:=[]int{};for _,c:=range groups[rank][:count] { ids=append(ids,c.ID) };return ids } } }
	return nil
}

func (g *Game) AutoAction(seat int) error {
	switch g.Phase {
	case PhasePlay:
		if seat!=g.Turn { return errors.New("不是此座位回合") }
		if g.HasLastPlay && g.LastPlay.Seat%2==seat%2 { return g.Pass(seat) }
		ids:=g.SuggestedCards(seat);if len(ids)>0 { return g.PlayCards(seat,ids) };return g.Pass(seat)
	case PhaseTribute:
		if _,ok:=g.given[seat];ok { return nil };cards:=g.EligibleTribute(seat);if len(cards)>0 { return g.SubmitTribute(seat,cards[0].ID) }
	case PhaseReturn:
		cards:=g.EligibleReturn(seat);if len(cards)>0 { return g.ReturnCard(seat,cards[0].ID) }
	case PhaseRoundFinished:return g.ReadyNextRound(seat)
	}
	return nil
}

func (g *Game) PendingSeats() []int {
	if g.Phase==PhasePlay { return []int{g.Turn} }
	result:=[]int{}
	if g.Phase==PhaseTribute { for _,seat:=range g.donors { if _,done:=g.given[seat];!done { result=append(result,seat) } } }
	if g.Phase==PhaseReturn { for _,exchange:=range g.Tributes { if !exchange.Returned { result=append(result,exchange.To) } } }
	return result
}

func (g *Game) SnapshotFor(seat int) map[string]any {
	counts:=[4]int{};for i:=range counts { counts[i]=len(g.Hands[i]) }
	hand:=[]Card{};if seat>=0 && seat<4 { hand=append(hand,g.Hands[seat]...) }
	state:=map[string]any{"type":"guandan_state","phase":g.Phase,"turn":g.Turn,"your_seat":seat,"players":g.Players,"hand":hand,"hand_counts":counts,"level_rank":g.LevelRank,"team_levels":g.TeamLevels,"active_team":g.ActiveTeam,"round":g.Round,"epoch":g.Epoch,"last_play":g.LastPlay,"has_last_play":g.HasLastPlay,"finish_order":g.FinishOrder,"round_winner":g.RoundWinner,"round_advance":g.RoundAdvance,"match_winner":g.MatchWinner,"round_ready":g.RoundReady,"tributes":g.Tributes,"anti_tribute":g.AntiTribute,"reason":g.Reason,"pending_seats":g.PendingSeats()}
	eligible:=[]int{};if g.Phase==PhaseTribute { for _,pending:=range g.PendingSeats() { if pending==seat { for _,c:=range g.EligibleTribute(seat) { eligible=append(eligible,c.ID) } } } } else if g.Phase==PhaseReturn { for _,pending:=range g.PendingSeats() { if pending==seat { for _,c:=range g.EligibleReturn(seat) { eligible=append(eligible,c.ID) } } } };state["eligible_card_ids"]=eligible
	if g.Phase==PhaseRoundFinished || g.Phase==PhaseFinished { state["hands_revealed"]=g.Hands }
	return state
}
