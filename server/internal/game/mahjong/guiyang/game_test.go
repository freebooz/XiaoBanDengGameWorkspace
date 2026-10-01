package guiyang

import "testing"

func testPlayers() [4]string { return [4]string{"east", "south", "west", "north"} }

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
	game := NewGame(testPlayers(), 1)
	claim := Tile{ID: 1000, Suit: "wan", Rank: 5}
	game.Phase = PhaseReaction
	game.PendingTile = claim
	game.PendingFrom = 0
	game.PendingKind = "discard"
	game.Discards = append(game.Discards, Discard{Seat: 0, Tile: claim})
	game.Candidates = map[int][]string{1: {"peng"}, 2: {"ming_gang"}, 3: {"hu"}}
	game.Submitted = map[int]string{}
	if err := game.Apply(1, "peng", 0); err != nil {
		t.Fatal(err)
	}
	if err := game.Apply(2, "ming_gang", 0); err != nil {
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
	if got := jiUnits(Tile{Suit: "wan", Rank: 1}, flipped); got != 1 {
		t.Fatalf("九万翻一万鸡: %d", got)
	}
	if got := jiUnits(Tile{Suit: "tiao", Rank: 1}, flipped); got != 1 {
		t.Fatalf("幺鸡固定一分: %d", got)
	}
	if got := jiUnits(Tile{Suit: "tong", Rank: 8}, flipped); got != 2 {
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
