package matchmaking

import (
	"testing"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

func TestQuickMatchPairsTwoAccountsIntoSameRoom(t *testing.T) {
	rooms := room.NewManager()
	manager := NewManager(rooms)
	req := QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}

	req.AccountID = "account-red"
	first, err := manager.QuickMatch(req)
	if err != nil {
		t.Fatalf("第一个玩家匹配失败: %v", err)
	}
	if first.Status != StatusWaiting || first.RoomID == "" || first.Players != 1 {
		t.Fatalf("第一个玩家应进入等待房间: %+v", first)
	}

	req.AccountID = "account-black"
	second, err := manager.QuickMatch(req)
	if err != nil {
		t.Fatalf("第二个玩家匹配失败: %v", err)
	}
	if second.Status != StatusMatched || second.RoomID != first.RoomID || second.Players != 2 {
		t.Fatalf("第二个玩家应匹配到同一房间: first=%+v second=%+v", first, second)
	}

	req.AccountID = "account-red"
	polled, err := manager.QuickMatch(req)
	if err != nil {
		t.Fatalf("首个玩家轮询匹配状态失败: %v", err)
	}
	if polled.Status != StatusMatched || polled.RoomID != first.RoomID || polled.Players != 2 {
		t.Fatalf("首个玩家轮询后应看到已匹配: %+v", polled)
	}

	matchedRoom, ok := rooms.Get(first.RoomID)
	if !ok || matchedRoom.State != "matched" {
		t.Fatalf("匹配完成后进入房间阶段，状态应为matched: %+v ok=%v", matchedRoom, ok)
	}
}

func TestQuickMatchIsIdempotentForSameAccount(t *testing.T) {
	manager := NewManager(room.NewManager())
	req := QuickMatchRequest{
		AccountID:   "same-account",
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}
	first, err := manager.QuickMatch(req)
	if err != nil {
		t.Fatal(err)
	}
	second, err := manager.QuickMatch(req)
	if err != nil {
		t.Fatal(err)
	}
	if first.RoomID != second.RoomID || second.Players != 1 || second.Status != StatusWaiting {
		t.Fatalf("同一账号重复请求不能创建多个等待房: first=%+v second=%+v", first, second)
	}
}

func TestQuickMatchSeparatesDifferentRuleVersions(t *testing.T) {
	manager := NewManager(room.NewManager())
	first, err := manager.QuickMatch(QuickMatchRequest{
		AccountID:   "a",
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	})
	if err != nil {
		t.Fatal(err)
	}
	second, err := manager.QuickMatch(QuickMatchRequest{
		AccountID:   "b",
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "2.0.0",
	})
	if err != nil {
		t.Fatal(err)
	}
	if first.RoomID == second.RoomID || second.Status != StatusWaiting {
		t.Fatalf("不同规则版本不得匹配: first=%+v second=%+v", first, second)
	}
}

func TestQuickMatchRejectsMissingIdentity(t *testing.T) {
	manager := NewManager(room.NewManager())
	_, err := manager.QuickMatch(QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	})
	if err == nil {
		t.Fatal("缺少account_id必须返回错误")
	}
}

func TestQuickMatchAssignsRedAndBlackSeats(t *testing.T) {
	manager := NewManager(room.NewManager())
	base := QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}
	base.AccountID = "red-player"
	red, err := manager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	base.AccountID = "black-player"
	black, err := manager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	base.AccountID = "red-player"
	redAfter, err := manager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	if redAfter.SeatColor != "red" || black.SeatColor != "black" {
		t.Fatalf("座位分配错误 red=%+v black=%+v", redAfter, black)
	}
	if black.RedAccountID != "red-player" || black.BlackAccountID != "black-player" {
		t.Fatalf("房间双方账号错误: %+v", black)
	}
	if red.RoomID != black.RoomID {
		t.Fatalf("双方必须进入同一房间 red=%+v black=%+v", red, black)
	}
}

func TestRoomReadyStartsOnlyAfterBothPlayersReady(t *testing.T) {
	rooms := room.NewManager()
	manager := NewManager(rooms)
	base := QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}
	base.AccountID = "red-player"
	red, _ := manager.QuickMatch(base)
	base.AccountID = "black-player"
	_, _ = manager.QuickMatch(base)

	first, err := manager.Ready(RoomReadyRequest{AccountID: "red-player", RoomID: red.RoomID})
	if err != nil {
		t.Fatal(err)
	}
	if first.Start || first.ReadyPlayers != 1 {
		t.Fatalf("只有一方准备不能开始: %+v", first)
	}
	second, err := manager.Ready(RoomReadyRequest{AccountID: "black-player", RoomID: red.RoomID})
	if err != nil {
		t.Fatal(err)
	}
	if !second.Start || second.ReadyPlayers != 2 {
		t.Fatalf("双方准备后必须开始: %+v", second)
	}
	item, ok := rooms.Get(red.RoomID)
	if !ok || item.State != "playing" {
		t.Fatalf("双方准备后房间必须进入playing: %+v ok=%v", item, ok)
	}
}

func TestCancelReturnsRemainingPlayerToWaiting(t *testing.T) {
	rooms := room.NewManager()
	manager := NewManager(rooms)
	base := QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}
	base.AccountID = "red-player"
	red, _ := manager.QuickMatch(base)
	base.AccountID = "black-player"
	_, _ = manager.QuickMatch(base)

	if err := manager.Cancel("black-player"); err != nil {
		t.Fatal(err)
	}
	base.AccountID = "red-player"
	remaining, err := manager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	if remaining.Status != StatusWaiting || remaining.Players != 1 || remaining.SeatColor != "red" {
		t.Fatalf("对手退出后剩余玩家应回到等待态: %+v", remaining)
	}
	item, ok := rooms.Get(red.RoomID)
	if !ok || item.State != "waiting" {
		t.Fatalf("房间应回到waiting: %+v ok=%v", item, ok)
	}
}

func TestFinishRoomReleasesPlayersAndClosesRoom(t *testing.T) {
	rooms := room.NewManager()
	manager := NewManager(rooms)
	base := QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}
	base.AccountID = "finish-red"
	first, _ := manager.QuickMatch(base)
	base.AccountID = "finish-black"
	_, _ = manager.QuickMatch(base)

	manager.FinishRoom(first.RoomID)

	if _, ok := rooms.Get(first.RoomID); ok {
		t.Fatal("结束房间后活动房间目录不应继续保留该房间")
	}
	base.AccountID = "finish-red"
	rematch, err := manager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	if rematch.RoomID == first.RoomID {
		t.Fatal("结束房间后玩家重新匹配必须进入新房间")
	}
}
