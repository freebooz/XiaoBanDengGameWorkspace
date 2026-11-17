package guiyang

import "testing"

func testPlayers() [4]string { return [4]string{"east", "south", "west", "north"} }

func TestSnapshotDrawnTileIsPrivateToCurrentPlayer(t *testing.T) {
	game := NewGame(testPlayers(), 1)
	for seat := range game.Players {
		drawn, present := game.SnapshotFor(seat)["drawn_tile_id"]
		if seat == game.Turn {
			if !present || drawn != game.LastDrawnID || game.LastDrawnID == 0 {
				t.Fatalf("current player should see their draw, got %v", drawn)
			}
		} else if present {
			t.Fatalf("opponent %d received private drawn tile %v", seat, drawn)
		}
	}
	game.Phase = PhaseReaction
	if _, present := game.SnapshotFor(game.Turn)["drawn_tile_id"]; present {
		t.Fatal("reaction should not send the previous draw")
	}
}

func TestMahjongSameDiscardUsesSelectedRules(t *testing.T) {
	for _, id := range []string{"guiyang", "basic_108"} {
		t.Run(id, func(t *testing.T) {
			game := NewGame(testPlayers(), 1)
			game.Rules.ID = id
			game.Rules.Version = "1.0.0"
			if id == "guiyang" {
				game.Rules.Version = "2.0.0"
			}
			wall := game.Rules.BuildWall()
			discard := wall[72] // 一条
			game.Hands = [4][]Tile{{discard}, nil, nil, nil}
			for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 73} {
				game.Hands[1] = append(game.Hands[1], wall[index])
			}
			if err := game.Apply(0, "play", discard.ID); err != nil {
				t.Fatal(err)
			}
			canHu := false
			for _, option := range game.Options(1) {
				canHu = canHu || option.Type == "hu"
			}
			if canHu != (id == "basic_108") {
				t.Fatalf("%s: discard Hu = %v", id, canHu)
			}
			if !canHu {
				if len(game.JiEvents) != 1 {
					t.Fatalf("Guiyang should record the first chicken discard: %v", game.JiEvents)
				}
				return
			}
			remaining := game.Remaining()
			if err := game.Apply(1, "hu", 0); err != nil {
				t.Fatal(err)
			}
			if game.Phase != PhaseFinished || game.Scores != [4]int{-3, 3, 0, 0} || game.Remaining() != remaining || game.FlippedJi.ID != 0 || len(game.JiEvents) != 0 || game.JiCounts != [4]int{} {
				t.Fatalf("basic_108 must settle base points without chicken scoring: scores=%v remaining=%d flipped=%v events=%v", game.Scores, game.Remaining(), game.FlippedJi, game.JiEvents)
			}
		})
	}
}

func TestMahjongRobbingKongUsesSelectedRules(t *testing.T) {
	for _, rule := range RuleDescriptors() {
		if rule.RuleSet().Dingque() || rule.Version != "1.0.0" && rule.Version != "2.0.0" {
			continue
		}
		t.Run(rule.ID, func(t *testing.T) {
			game := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
			wall := game.Rules.BuildWall()
			upgrade := wall[72]
			game.Hands = [4][]Tile{{upgrade}, nil, nil, nil}
			game.Melds[0] = []Meld{{Kind: "peng", Tiles: wall[73:76], FromSeat: 2}}
			// Bamboo two and three complete the fourth meld with the upgrade tile.
			for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 76, 80} {
				game.Hands[1] = append(game.Hands[1], wall[index])
			}
			remaining := game.Remaining()
			if err := game.Apply(0, "bu_gang", upgrade.ID); err != nil {
				t.Fatal(err)
			}
			if rule.RequiresKongToClaim {
				if game.Melds[0][0].Kind != "bu_gang" || game.Remaining() != remaining-1 || len(game.Options(1)) != 0 {
					t.Fatalf("Guiyang should complete the unopposed kong: %+v", game.Melds[0])
				}
				events := game.SnapshotFor(1)["action_events"].([]ActionEvent)
				if len(events) != 1 || events[0] != (ActionEvent{Sequence: 1, Seat: 0, Type: "bu_gang"}) {
					t.Fatalf("completed upgrade must emit its kong once: %v", events)
				}
				return
			}
			if events := game.SnapshotFor(1)["action_events"].([]ActionEvent); len(events) != 0 {
				t.Fatalf("pending upgrade offers a reaction, no committed event: %v", events)
			}
			if err := game.Apply(1, "hu", 0); err != nil {
				t.Fatal(err)
			}
			if game.Phase != PhaseFinished || game.Scores != [4]int{-3, 3, 0, 0} || game.Melds[0][0].Kind != "peng" || game.Remaining() != remaining {
				t.Fatalf("robbed kong must settle without completing the kong or drawing: melds=%v scores=%v remaining=%d", game.Melds[0], game.Scores, game.Remaining())
			}
			if _, exists := game.findTile(0, upgrade.ID); exists {
				t.Fatal("the tile robbed from the upgrade must leave the original hand")
			}
			events := game.SnapshotFor(0)["action_events"].([]ActionEvent)
			if len(events) != 1 || events[0] != (ActionEvent{Sequence: 1, Seat: 1, Type: "hu"}) {
				t.Fatalf("robbed upgrade must emit only the winner's event: %v", events)
			}
		})
	}
}

func TestGuiyangExternalWinRequiresOwnCompletedKong(t *testing.T) {
	exposures := []struct {
		name         string
		winnerMeld   string
		feederMeld   string
		claimAllowed bool
	}{
		{name: "no meld"},
		{name: "only feeder has a kong", feederMeld: "an_gang"},
		{name: "winner has a pung", winnerMeld: "peng"},
		{name: "concealed kong", winnerMeld: "an_gang", claimAllowed: true},
		{name: "exposed kong", winnerMeld: "ming_gang", claimAllowed: true},
		{name: "added kong", winnerMeld: "bu_gang", claimAllowed: true},
	}
	for _, action := range []string{"play", "bu_gang"} {
		for _, exposure := range exposures {
			t.Run(action+"/"+exposure.name, func(t *testing.T) {
				game := NewGame(testPlayers(), 1)
				wall := game.Rules.BuildWall()
				candidate := wall[72]
				game.Hands = [4][]Tile{{candidate}, nil, nil, nil}
				game.Melds = [4][]Meld{}
				if action == "bu_gang" {
					game.Melds[0] = []Meld{{Kind: "peng", Tiles: wall[73:76], FromSeat: 2}}
				}
				if exposure.feederMeld != "" {
					game.Melds[0] = append(game.Melds[0], Meld{Kind: exposure.feederMeld, Tiles: wall[64:68], FromSeat: 0})
				}
				// Two sequences, a pair and two bamboo tiles waiting on the candidate.
				handIndices := []int{0, 4, 8, 12, 16, 20, 36, 37, 76, 80}
				if exposure.winnerMeld == "" {
					handIndices = append(handIndices, 24, 28, 32)
				} else {
					end := 64
					if exposure.winnerMeld == "peng" {
						end = 63
					}
					game.Melds[1] = []Meld{{Kind: exposure.winnerMeld, Tiles: wall[60:end], FromSeat: 1}}
				}
				for _, index := range handIndices {
					game.Hands[1] = append(game.Hands[1], wall[index])
				}
				if ok, _ := game.Rules.CanHuHand(append(game.Hands[1], candidate), len(game.Melds[1])); !ok {
					t.Fatal("fixture must have a complete winning shape")
				}
				if err := game.Apply(0, action, candidate.ID); err != nil {
					t.Fatal(err)
				}
				offered := false
				for _, option := range game.Options(1) {
					offered = offered || option.Type == "hu"
				}
				if offered != exposure.claimAllowed {
					t.Fatalf("hu option = %v, want %v", offered, exposure.claimAllowed)
				}
				err := game.Apply(1, "hu", 0)
				if !exposure.claimAllowed {
					if err == nil {
						t.Fatal("server accepted an ineligible external hu")
					}
				} else if err != nil || game.Phase != PhaseFinished || len(game.Winners) != 1 || game.Winners[0] != 1 {
					t.Fatalf("eligible external hu failed: winners=%v err=%v", game.Winners, err)
				}
			})
		}
	}
}

func TestGuiyangSelfDrawCanWinWithoutKong(t *testing.T) {
	game := NewGame(testPlayers(), 1)
	wall := game.Rules.BuildWall()
	game.Hands[0] = nil
	for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 76, 80, 72} {
		game.Hands[0] = append(game.Hands[0], wall[index])
	}
	game.LastDrawnID = wall[72].ID
	if err := game.Apply(0, "hu", 0); err != nil || game.WinKind != "zi_mo" {
		t.Fatalf("Guiyang self draw requires no completed kong: kind=%s err=%v", game.WinKind, err)
	}
}

func TestMahjongRequiresReplacementTileForKong(t *testing.T) {
	game := NewGame(testPlayers(), 1)
	game.NextWall = len(game.Wall)
	w := game.Rules.BuildWall()
	game.Hands = [4][]Tile{append(append([]Tile{}, w[:4]...), w[4]), nil, nil, nil}
	game.Melds[0] = []Meld{{Kind: "peng", Tiles: w[5:8], FromSeat: 1}}
	for _, option := range game.Options(0) {
		if option.Type == "an_gang" || option.Type == "bu_gang" {
			t.Fatalf("cannot offer %s when no replacement tile can be drawn", option.Type)
		}
	}
	if err := game.Apply(0, "an_gang", w[0].ID); err == nil {
		t.Fatal("concealed kong accepted without a replacement tile")
	}
	if err := game.Apply(0, "bu_gang", w[4].ID); err == nil || game.Scores != [4]int{} || game.Melds[0][0].Kind != "peng" {
		t.Fatalf("added kong without a replacement tile changed the game: meld=%v scores=%v", game.Melds[0], game.Scores)
	}
	game.Melds[0] = nil
	game.Hands = [4][]Tile{{w[0]}, append([]Tile{}, w[1:4]...), nil, nil}
	if err := game.Apply(0, "play", w[0].ID); err != nil {
		t.Fatal(err)
	}
	options := game.Options(1)
	if len(options) != 2 || options[0].Type != "pass" || options[1].Type != "peng" {
		t.Fatalf("last discard can be claimed by peng but cannot be used for a kong: %v", options)
	}
}

func TestMahjongPengCannotBeCountedAsSelfDraw(t *testing.T) {
	rule, _ := FindRuleDescriptor("basic_108", "1.0.0")
	game := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
	w := game.Rules.BuildWall()
	game.Hands = [4][]Tile{{w[0]}, {w[1], w[2]}, nil, nil}
	for _, index := range []int{4, 8, 12, 16, 20, 24, 36, 40, 44, 48, 49} {
		game.Hands[1] = append(game.Hands[1], w[index])
	}
	if err := game.Apply(0, "play", w[0].ID); err != nil {
		t.Fatal(err)
	}
	remaining := game.Remaining()
	if err := game.Apply(1, "peng", 0); err != nil {
		t.Fatal(err)
	}
	if game.Remaining() != remaining || len(game.Melds[1]) != 1 || len(game.Melds[1][0].Tiles) != 3 {
		t.Fatalf("peng must claim the discard and advance without drawing: %+v", game.Melds[1])
	}
	for _, option := range game.Options(1) {
		if option.Type == "hu" {
			t.Fatal("peng does not draw a tile and cannot offer self-draw hu")
		}
	}
	if err := game.Apply(1, "hu", 0); err == nil || game.Phase != PhaseTurn || game.Scores != [4]int{} {
		t.Fatalf("peng was incorrectly settled as self-draw: %v %v", err, game.Scores)
	}
}

func TestCustomChickenOptionsChangeFirstDiscardAndBlackEightScoring(t *testing.T) {
	for _, test := range []struct {
		name               string
		charge, blackEight bool
		wantCounts         [4]int
		wantEvents         int
	}{
		{name: "both on", charge: true, blackEight: true, wantCounts: [4]int{4, 1, 0, 0}, wantEvents: 1},
		{name: "black eight off", charge: true, wantCounts: [4]int{1, 2, 0, 0}, wantEvents: 1},
		{name: "charge off", blackEight: true, wantCounts: [4]int{2, 1, 0, 0}},
	} {
		t.Run(test.name, func(t *testing.T) {
			options := RuleOptions{Version: RuleOptionsVersion, Chicken: true, ChargeChicken: test.charge, BlackEight: test.blackEight}
			rule, err := ResolveRuleDescriptor("guiyang", "2.0.0", &options)
			if err != nil {
				t.Fatal(err)
			}
			game := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
			wall := game.Rules.BuildWall()
			eight, one := wall[64], wall[72]
			game.Hands = [4][]Tile{{eight}, {one}, nil, nil}
			game.Wall, game.NextWall = []Tile{wall[16], wall[20], wall[60]}, 0 // 7筒 makes 8筒 a standard flipped chicken.
			if err := game.Apply(0, "play", eight.ID); err != nil {
				t.Fatal(err)
			}
			if err := game.Apply(1, "play", one.ID); err != nil {
				t.Fatal(err)
			}
			game.settle([]int{2}, -1, "zi_mo")
			if game.JiCounts != test.wantCounts || len(game.JiEvents) != test.wantEvents {
				t.Fatalf("wrong chicken scoring: units=%v events=%v", game.JiCounts, game.JiEvents)
			}
		})
	}
}

func TestCustomRobKongCanBeDisabled(t *testing.T) {
	options := RuleOptions{Version: RuleOptionsVersion}
	rule, err := ResolveRuleDescriptor("basic_108", "1.0.0", &options)
	if err != nil {
		t.Fatal(err)
	}
	game := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
	wall := game.Rules.BuildWall()
	game.Hands = [4][]Tile{{wall[72]}, nil, nil, nil}
	game.Melds[0] = []Meld{{Kind: "peng", Tiles: wall[73:76], FromSeat: 2}}
	for _, index := range []int{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 37, 76, 80} {
		game.Hands[1] = append(game.Hands[1], wall[index])
	}
	remaining := game.Remaining()
	if err := game.Apply(0, "bu_gang", wall[72].ID); err != nil {
		t.Fatal(err)
	}
	if game.Phase != PhaseTurn || game.Melds[0][0].Kind != "bu_gang" || game.Remaining() != remaining-1 || game.Scores != [4]int{3, -1, -1, -1} {
		t.Fatalf("disabling rob-kong did not complete exactly one kong: phase=%v meld=%v scores=%v", game.Phase, game.Melds[0], game.Scores)
	}
}

func TestMahjongActionEventsOnlyExposeCommittedClaims(t *testing.T) {
	rule, _ := FindRuleDescriptor("basic_108", "1.0.0")
	game := NewGameWithRules(testPlayers(), 1, rule.RuleSet())
	w := game.Rules.BuildWall()
	game.Hands = [4][]Tile{{w[0]}, {w[1], w[2], w[3]}, nil, nil}
	game.Melds = [4][]Meld{}
	game.Wall, game.NextWall = []Tile{w[4]}, 0
	if err := game.Apply(0, "play", w[0].ID); err != nil {
		t.Fatal(err)
	}
	if events, ok := game.SnapshotFor(0)["action_events"].([]ActionEvent); !ok || events == nil || len(events) != 0 {
		t.Fatalf("discard reaction advertised an uncommitted event: %v", game.SnapshotFor(0)["action_events"])
	}
	if err := game.Apply(1, "ming_gang", 0); err != nil {
		t.Fatal(err)
	}
	if game.Remaining() != 0 || game.LastDrawnID != w[4].ID || game.Scores != [4]int{-1, 3, -1, -1} {
		t.Fatalf("committed exposed kong did not pay once and draw once: scores=%v", game.Scores)
	}
	for seat := 0; seat < 4; seat++ {
		events := game.SnapshotFor(seat)["action_events"].([]ActionEvent)
		if len(events) != 1 || events[0] != (ActionEvent{Sequence: 1, Seat: 1, Type: "ming_gang"}) {
			t.Fatalf("seat %d received the wrong committed event: %v", seat, events)
		}
	}
}

func TestNewGameDealsPrivateHandsAndKeepsWallSecret(t *testing.T) {
	game := NewGame(testPlayers(), 42)
	if game.Phase != PhaseTurn || game.Turn != 0 || game.Remaining() != 55 {
		t.Fatalf("开局状态错误: %+v", game)
	}
	for seat := 0; seat < 4; seat++ {
		want := 13
		if seat == 0 {
			want = 14
		}
		if len(game.Hands[seat]) != want {
			t.Fatalf("座位 %d 手牌应有 %d 张", seat, want)
		}
		snapshot := game.SnapshotFor(seat)
		hand := snapshot["hand"].([]Tile)
		if len(hand) != want {
			t.Fatalf("私有快照手牌错误: %d", seat)
		}
		if _, ok := snapshot["wall"]; ok {
			t.Fatal("快照不能公开牌墙")
		}
		for other := 0; other < 4; other++ {
			if other == seat {
				continue
			}
			for _, secret := range game.Hands[other] {
				for _, exposed := range hand {
					if secret.ID == exposed.ID {
						t.Fatalf("座位 %d 收到座位 %d 的暗牌", seat, other)
					}
				}
			}
		}
	}
}

func TestWallBreakMatchesUnrealPhysicalWallLayout(t *testing.T) {
	checks := []struct {
		dealer, dice, side, stack, start int
	}{
		{0, 1, 0, 1, 2},
		{0, 2, 1, 2, 86},
		{0, 3, 2, 3, 60},
		{0, 4, 3, 4, 36},
		{2, 18, 3, 5, 38},
	}
	for _, check := range checks {
		side, stack, start := wallBreak(check.dealer, check.dice)
		if side != check.side || stack != check.stack || start != check.start {
			t.Fatalf("dealer=%d dice=%d: got (%d,%d,%d), want (%d,%d,%d)", check.dealer, check.dice, side, stack, start, check.side, check.stack, check.start)
		}
	}
	game := NewGame(testPlayers(), 42)
	if game.WallBreakDiceTotal < 3 || game.WallBreakDiceTotal > 18 || game.WallBreakStack < 1 {
		t.Fatalf("开门数据无效: dice=%d stack=%d", game.WallBreakDiceTotal, game.WallBreakStack)
	}
	if err := game.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestEmptySnapshotCollectionsAreArrays(t *testing.T) {
	game := NewGame(testPlayers(), 11)
	state := game.SnapshotFor(1)
	if state["discards"] == nil || state["options"] == nil || state["winners"] == nil || state["ji_events"] == nil {
		t.Fatalf("空列表必须序列化为数组而非 null: %+v", state)
	}
}

func TestDiscardRejectsWrongSeatAndTileAndAdvancesTurn(t *testing.T) {
	game := NewGame(testPlayers(), 7)
	chosen := game.Hands[0][0]
	for _, option := range game.Options(0) {
		if option.Type == "pass" {
			t.Fatal("自己出牌的回合不能提供过操作")
		}
	}
	epoch := game.Epoch
	if err := game.Apply(0, "pass", 0); err == nil {
		t.Fatal("不能用过跳过自己的出牌回合")
	}
	if game.Epoch != epoch || game.Phase != PhaseTurn || game.Turn != 0 || len(game.Hands[0]) != 14 || len(game.Discards) != 0 {
		t.Fatal("拒绝过操作后不得改变本人的出牌状态")
	}
	if err := game.Apply(1, "play", chosen.ID); err == nil {
		t.Fatal("非当前玩家不能出牌")
	}
	if err := game.Apply(0, "play", 999); err == nil {
		t.Fatal("不能打出不存在的实体牌")
	}
	if err := game.Apply(0, "play", chosen.ID); err != nil {
		t.Fatal(err)
	}
	if len(game.Hands[0]) != 13 || len(game.Discards) != 1 {
		t.Fatal("出牌应从手中移出并进入公共弃牌区")
	}
	if game.Phase == PhaseReaction {
		game.Timeout()
	}
	if game.Phase != PhaseTurn || game.Turn != 1 || len(game.Hands[1]) != 14 {
		t.Fatalf("应轮到下一家摸牌: phase=%s turn=%d hand=%d", game.Phase, game.Turn, len(game.Hands[1]))
	}
}

func TestReactionHuBeatsPengAndGang(t *testing.T) {
	for _, action := range []string{"peng", "ming_gang"} {
		t.Run(action, func(t *testing.T) {
			game := priorityReactionFixture(action)
			if err := game.Apply(1, "pass", 0); err != nil {
				t.Fatal(err)
			}
			if err := game.Apply(2, action, 0); err != nil {
				t.Fatal(err)
			}
			if game.Phase != PhaseReaction {
				t.Fatal("须等待最后一位有资格者")
			}
			if err := game.Apply(3, "hu", 0); err != nil {
				t.Fatal(err)
			}
			if game.Phase != PhaseFinished || len(game.Winners) != 1 || game.Winners[0] != 3 {
				t.Fatalf("胡应优先: %+v", game.Winners)
			}
		})
	}
}

func TestDiscardWinPaysThreeUnitsAndFlipsJi(t *testing.T) {
	game := NewGame(testPlayers(), 9)
	game.Wall[game.NextWall] = Tile{ID: 104, Suit: "wan", Rank: 9}
	game.Hands = [4][]Tile{}
	game.Discards = nil
	game.settle([]int{1}, 0, "dian_pao")
	if game.Scores != [4]int{-3, 3, 0, 0} {
		t.Fatalf("点炮应由放炮者支付三倍基础分: %+v", game.Scores)
	}
	if game.FlippedJi.Suit != "wan" || game.FlippedJi.Rank != 9 {
		t.Fatalf("结算应翻一张鸡牌: %+v", game.FlippedJi)
	}
}

func TestJiUnitsIncludeBasicWuGuAndFlippedRank(t *testing.T) {
	flipped := Tile{Suit: "wan", Rank: 9}
	if got := jiUnits(Tile{Suit: "wan", Rank: 1}, flipped, true); got != 1 {
		t.Fatalf("九万翻一万鸡: %d", got)
	}
	if got := jiUnits(Tile{Suit: "tiao", Rank: 1}, flipped, true); got != 1 {
		t.Fatalf("幺鸡固定一分: %d", got)
	}
	if got := jiUnits(Tile{Suit: "tong", Rank: 8}, flipped, true); got != 2 {
		t.Fatalf("黑八两分: %d", got)
	}
}

func TestFourSeatTimeoutRoundReachesSettlement(t *testing.T) {
	game := NewGame(testPlayers(), 27)
	for action := 0; action < 120 && game.Phase != PhaseFinished; action++ {
		game.Timeout()
	}
	if game.Phase != PhaseFinished || game.Reason != "wall_exhausted" || game.Remaining() != 0 {
		t.Fatalf("自动轮转未正常流局: phase=%s reason=%s remaining=%d", game.Phase, game.Reason, game.Remaining())
	}
	total := 0
	for _, score := range game.Scores {
		total += score
	}
	if total != 0 {
		t.Fatalf("结算分数必须守恒: %+v", game.Scores)
	}
	for seat := 0; seat < 4; seat++ {
		if game.SnapshotFor(seat)["options"] == nil {
			t.Fatalf("结束后座位 %d 的操作列表不能为 null", seat)
		}
	}
}
