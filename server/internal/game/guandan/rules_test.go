package guandan

import "testing"

func hand(ranks ...int) []Card {
	result:=make([]Card,len(ranks))
	for i,rank:=range ranks { result[i]=Card{ID:i,Rank:rank,Suit:[]string{"spade","club","diamond"}[i%3]} }
	return result
}

func TestDeckAndLevelOrder(t *testing.T) {
	deck:=NewDeck(); seen:=map[int]bool{}; faces:=map[string]int{}
	for _,card:=range deck { if seen[card.ID] { t.Fatal("duplicate ID") };seen[card.ID]=true;faces[card.Suit+string(rune(card.Rank))]++ }
	if len(deck)!=108 || len(faces)!=54 { t.Fatal("must have two complete decks") }
	for _,count:=range faces { if count!=2 { t.Fatal("each face must occur twice") } }
	level,_:=Choose(hand(7),7,nil); ace,_:=Choose(hand(14),7,nil)
	if !Beats(level,ace) { t.Fatal("level card must beat ace") }
	joker,_:=Choose(hand(16),7,nil); if !Beats(joker,level) { t.Fatal("joker must beat level") }
}

func TestGuandanPatternsAndWildcards(t *testing.T) {
	for _,tt:=range []struct{ ranks []int; kind string }{
		{[]int{3},"single"},{[]int{4,4},"pair"},{[]int{6,6,6},"triple"},
		{[]int{8,8,8,4,4},"triple_pair"},{[]int{3,4,5,6,7},"straight"},
		{[]int{14,15,3,4,5},"straight"},{[]int{3,3,4,4,5,5},"pair_straight"},
		{[]int{14,14,15,15,3,3},"pair_straight"},{[]int{8,8,8,9,9,9},"triple_straight"},
		{[]int{6,6,6,6},"bomb"},{[]int{16,16,17,17},"rocket"},
	} { p,e:=Choose(hand(tt.ranks...),10,nil);if e!=nil || p.Kind!=tt.kind { t.Errorf("%v: %+v %v",tt.ranks,p,e) } }
	for _,ranks:=range [][]int{{3,3,3,4},{3,4,5,6,7,8},{4,4,5,5},{16,17},{16,16,16}} { if _,e:=Choose(hand(ranks...),10,nil);e==nil { t.Errorf("illegal pattern accepted %v",ranks) } }
	wild:=Card{ID:107,Rank:7,Suit:"heart"}
	cards:=append(hand(3,4,5,6),wild)
	p,e:=Choose(cards,7,nil);if e!=nil || p.Kind!="straight" { t.Fatalf("wildcard straight %+v %v",p,e) }
	cards=hand(10,11,12,13);for i:=range cards { cards[i].Suit="spade" };cards=append(cards,wild)
	p,e=Choose(cards,7,nil);if e!=nil || p.Kind!="straight_flush" || p.Main!=14 { t.Fatalf("wildcard flush %+v %v",p,e) }
	if _,e:=Choose([]Card{{ID:1,Rank:16,Suit:"small_joker"},wild},7,nil);e==nil { t.Fatal("wildcard must not substitute a joker") }
	five,_:=Choose(hand(4,4,4,4,4),7,nil); six,_:=Choose(hand(3,3,3,3,3,3),7,nil)
	if !Beats(p,five) || !Beats(six,p) { t.Fatal("flush/bomb precedence") }
}

func TestWildcardChoosesMinimalBeatingInterpretation(t *testing.T) {
	wild:=Card{ID:90,Rank:5,Suit:"heart"}
	current:=Pattern{Kind:"pair",Main:8,Length:2}
	p,err:=Choose([]Card{{ID:91,Rank:9,Suit:"spade"},wild},5,&current)
	if err!=nil || p.Main!=9 { t.Fatalf("pair response: %+v %v",p,err) }
}
