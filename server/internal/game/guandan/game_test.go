package guandan

import "testing"

func TestDealPrivacyAndOwnership(t *testing.T) {
	g:=NewGame([4]string{"a","b","c","d"},42)
	seen:=map[int]bool{};for seat:=0;seat<4;seat++ { if len(g.Hands[seat])!=27 { t.Fatal("not 27 cards") };for _,c:=range g.Hands[seat] { if seen[c.ID] { t.Fatal("duplicate ID") };seen[c.ID]=true } }
	if len(seen)!=108 { t.Fatal("incomplete deck") }
	if _,ok:=g.SnapshotFor(0)["hands_revealed"];ok { t.Fatal("opponents leaked") }
	epoch:=g.Epoch;wrong:=g.Hands[(g.Turn+1)%4][0].ID
	if err:=g.PlayCards(g.Turn,[]int{wrong});err==nil || g.Epoch!=epoch { t.Fatal("foreign card changed state") }
}

func TestFinishedPlayerPartnerReceivesWindAfterPasses(t *testing.T) {
	g:=NewGame([4]string{},7);g.Turn=0
	g.Hands=[4][]Card{{{ID:0,Rank:3,Suit:"spade"}},{{ID:4,Rank:4,Suit:"spade"},{ID:8,Rank:5,Suit:"spade"}},{{ID:12,Rank:6,Suit:"spade"},{ID:16,Rank:7,Suit:"spade"}},{{ID:20,Rank:8,Suit:"spade"},{ID:24,Rank:9,Suit:"spade"}}}
	if err:=g.PlayCards(0,[]int{0});err!=nil { t.Fatal(err) }
	for _,seat:=range []int{1,2,3} { if err:=g.Pass(seat);err!=nil { t.Fatal(err) } }
	if g.Turn!=2 || g.HasLastPlay || len(g.FinishOrder)!=1 { t.Fatalf("wind incorrect turn=%d order=%v",g.Turn,g.FinishOrder) }
}

func TestUpgradeAndTributeConstraints(t *testing.T) {
	g:=NewGame([4]string{},17);g.FinishOrder=[]int{0,2,1,3};g.finishRound()
	if g.TeamLevels[0]!=5 || g.RoundAdvance!=3 || g.Phase!=PhaseRoundFinished { t.Fatalf("upgrade %+v",g) }
	g.LevelRank=5;g.Hands=[4][]Card{}
	g.Hands[0]=hand(3,4);g.Hands[2]=hand(6,7)
	g.Hands[1]=[]Card{{ID:1,Rank:5,Suit:"heart"},{ID:2,Rank:14,Suit:"club"},{ID:3,Rank:3,Suit:"club"}}
	g.Hands[3]=[]Card{{ID:4,Rank:16,Suit:"small_joker"},{ID:5,Rank:4,Suit:"club"}}
	g.setupTribute([]int{0,2,1,3})
	if g.Phase!=PhaseTribute { t.Fatal("expected double tribute") }
	if err:=g.SubmitTribute(1,1);err==nil { t.Fatal("heart level tribute accepted") }
	if err:=g.SubmitTribute(1,3);err==nil { t.Fatal("non-highest tribute accepted") }
	if err:=g.SubmitTribute(1,2);err!=nil { t.Fatal(err) };if err:=g.SubmitTribute(3,4);err!=nil { t.Fatal(err) }
	if g.Phase!=PhaseReturn || g.Tributes[0].From!=3 || g.Tributes[0].To!=0 { t.Fatalf("strongest tribute must go to head %+v",g.Tributes) }
	if err:=g.ReturnCard(0,4);err==nil { t.Fatal("returning joker while low cards available accepted") }
	for _,exchange:=range g.Tributes { candidates:=g.EligibleReturn(exchange.To);if err:=g.ReturnCard(exchange.To,candidates[0].ID);err!=nil { t.Fatal(err) } }
	if g.Phase!=PhasePlay || g.Turn!=3 { t.Fatal("largest tribute giver must lead") }
}

func TestAntiTributeAndCompleteRound(t *testing.T) {
	g:=NewGame([4]string{},99);g.Hands[1]=[]Card{{ID:53,Rank:17,Suit:"big_joker"}};g.Hands[3]=[]Card{{ID:107,Rank:17,Suit:"big_joker"}}
	g.setupTribute([]int{0,2,1,3});if g.Phase!=PhasePlay || !g.AntiTribute || g.Turn!=0 { t.Fatal("two big jokers must resist double tribute") }
	g=NewGame([4]string{},31)
	for action:=0;action<1000 && g.Phase==PhasePlay;action++ { if err:=g.AutoAction(g.Turn);err!=nil { t.Fatal(err) } }
	if g.Phase!=PhaseRoundFinished || len(g.FinishOrder)!=4 { t.Fatalf("round incomplete %s %v",g.Phase,g.FinishOrder) }
	for seat:=0;seat<4;seat++ { if err:=g.ReadyNextRound(seat);err!=nil { t.Fatal(err) } }
	if g.Round!=2 { t.Fatal("next round not dealt") }
}
