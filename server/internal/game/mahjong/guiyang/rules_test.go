package guiyang

import "testing"

func TestBuildWallHas136Tiles(t *testing.T) {
	rules:=NewRuleSet()
	if got:=len(rules.BuildWall()); got!=136 { t.Fatalf("基础牌墙应为136张，实际=%d",got) }
}

func TestCanPeng(t *testing.T) {
	rules:=NewRuleSet()
	tile:=Tile{Suit:"wan",Rank:3}
	hand:=[]Tile{tile,tile,{Suit:"tong",Rank:2}}
	if !rules.CanPeng(hand,tile) { t.Fatal("持有两张相同牌时应允许碰") }
}