package guiyang

import "testing"

func TestBuildWallHas108UniqueSuitedTiles(t *testing.T) {
	rules := NewRuleSet()
	wall := rules.BuildWall()
	if got := len(wall); got != 108 {
		t.Fatalf("贵阳默认牌墙应为108张，实际=%d", got)
	}
	seen := map[int]bool{}
	for _, tile := range wall {
		if tile.Suit == "honor" || tile.ID <= 0 || seen[tile.ID] {
			t.Fatalf("牌面或唯一ID错误: %+v", tile)
		}
		seen[tile.ID] = true
	}
}

func TestCanHuStandardAndSevenPairs(t *testing.T) {
	rules := NewRuleSet()
	standard := []Tile{{Suit: "wan", Rank: 1}, {Suit: "wan", Rank: 2}, {Suit: "wan", Rank: 3}, {Suit: "wan", Rank: 4}, {Suit: "wan", Rank: 5}, {Suit: "wan", Rank: 6}, {Suit: "tong", Rank: 2}, {Suit: "tong", Rank: 3}, {Suit: "tong", Rank: 4}, {Suit: "tiao", Rank: 7}, {Suit: "tiao", Rank: 8}, {Suit: "tiao", Rank: 9}, {Suit: "wan", Rank: 9}}
	if ok, _ := rules.CanHu(standard, Tile{Suit: "wan", Rank: 9}); !ok {
		t.Fatal("四顺一对应可胡")
	}
	if ok, _ := rules.CanHu(standard, Tile{Suit: "tong", Rank: 9}); ok {
		t.Fatal("不成型手牌不得胡")
	}
	pairs := []Tile{}
	for rank := 1; rank <= 7; rank++ {
		pairs = append(pairs, Tile{Suit: "wan", Rank: rank}, Tile{Suit: "wan", Rank: rank})
	}
	if ok, _ := rules.CanHuHand(pairs, 0); !ok {
		t.Fatal("七对可胡")
	}
}

func TestTileRuleChecksIgnorePhysicalID(t *testing.T) {
	rules := NewRuleSet()
	played := Tile{ID: 101, Suit: "wan", Rank: 3}
	hand := []Tile{{ID: 1, Suit: "wan", Rank: 3}, {ID: 2, Suit: "wan", Rank: 3}, {ID: 3, Suit: "wan", Rank: 3}}
	if !rules.CanPeng(hand, played) || !rules.CanGangFromDiscard(hand, played) {
		t.Fatal("同种牌的实体ID不同仍可碰杠")
	}
	if err := rules.ValidateDiscard(hand, played); err == nil {
		t.Fatal("不能打出手中不存在的实体牌")
	}
}

func TestCanPeng(t *testing.T) {
	rules := NewRuleSet()
	tile := Tile{Suit: "wan", Rank: 3}
	hand := []Tile{tile, tile, {Suit: "tong", Rank: 2}}
	if !rules.CanPeng(hand, tile) {
		t.Fatal("持有两张相同牌时应允许碰")
	}
}
