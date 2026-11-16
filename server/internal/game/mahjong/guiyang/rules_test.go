package guiyang

import "testing"

func TestResolveRuleDescriptorNormalizesAndCopiesVersionedOptions(t *testing.T) {
	base, err := ResolveRuleDescriptor("guiyang", "2.0.0", nil)
	if err != nil || base.Options != (RuleOptions{Version: RuleOptionsVersion, Chicken: true, ChargeChicken: true, BlackEight: true, RequiresKongToClaim: true, RobKong: true}) {
		t.Fatalf("unexpected legacy Guiyang defaults: %+v, %v", base.Options, err)
	}
	basic, err := ResolveRuleDescriptor("basic_108", "1.0.0", nil)
	if err != nil || basic.Options != (RuleOptions{Version: RuleOptionsVersion, RobKong: true}) {
		t.Fatalf("unexpected legacy Basic 108 defaults: %+v, %v", basic.Options, err)
	}
	requested := RuleOptions{Version: RuleOptionsVersion, ChargeChicken: true, BlackEight: true, RobKong: true}
	custom, err := ResolveRuleDescriptor("guiyang", "2.0.0", &requested)
	if err != nil || custom.Options.ChargeChicken || custom.Options.BlackEight || custom.Chicken || custom.RequiresKongToClaim || !custom.Options.RobKong {
		t.Fatalf("disabled chicken must normalize dependent switches: %+v, %v", custom, err)
	}
	requested.Version = "future"
	if _, err := ResolveRuleDescriptor("guiyang", "2.0.0", &requested); err == nil {
		t.Fatal("unknown custom schema must be rejected")
	}
	requested = RuleOptions{Version: RuleOptionsVersion, Chicken: true, BlackEight: true}
	custom, err = ResolveRuleDescriptor("basic_108", "1.0.0", &requested)
	if err != nil || !custom.Options.BlackEight || !custom.Chicken {
		t.Fatalf("Basic 108 must be usable as a custom base: %+v, %v", custom, err)
	}
	rules := custom.RuleSet()
	requested.Chicken = false
	custom.Options.Chicken = false
	if !rules.chickenEnabled() {
		t.Fatal("changing the supplied options or descriptor modified an active ruleset")
	}
}

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
