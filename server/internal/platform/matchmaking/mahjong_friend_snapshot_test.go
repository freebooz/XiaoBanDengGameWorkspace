package matchmaking

import (
	"reflect"
	"testing"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

func TestFriendRoomReconcilesFailedPersistence(t *testing.T) {
	manager := NewManager(room.NewManager())
	code, err := manager.CreateMahjongRoom(restoreRequest("host"), MahjongFriend, nil)
	if err != nil {
		t.Fatal(err)
	}
	waiting, ok := manager.MahjongFriendRoomSnapshot(code)
	if !ok || waiting.Room.State != "waiting" {
		t.Fatal("missing waiting image")
	}
	if err := manager.JoinMahjongFriendRoom(restoreRequest("guest"), code); err != nil {
		t.Fatal(err)
	}
	joined, _ := manager.MahjongFriendRoomSnapshot(code)
	if err := manager.ReconcileMahjongFriendRoom(&waiting, nil); err == nil {
		t.Fatal("stale rollback removed newer roster")
	}
	if err := manager.ReconcileMahjongFriendRoom(&joined, &waiting); err != nil {
		t.Fatal(err)
	}
	if got, ok := manager.MahjongFriendRoomSnapshot(code); !ok || !reflect.DeepEqual(got, waiting) {
		t.Fatal("rollback did not restore initial image")
	}
	if _, exists := manager.MahjongAssignment("guest"); exists {
		t.Fatal("rolled-back guest retained the seat")
	}
	if err := manager.ReconcileMahjongFriendRoom(&waiting, nil); err != nil {
		t.Fatal(err)
	}
	if _, exists := manager.MahjongFriendRoomSnapshot(code); exists {
		t.Fatal("failed create rollback kept room")
	}
	if err := manager.ReconcileMahjongFriendRoom(nil, &waiting); err != nil {
		t.Fatal(err)
	}
	if err := NewManager(room.NewManager()).RestoreMahjongAssignment(waiting); err != nil {
		t.Fatal(err)
	}
}

func TestFriendSeriesKeepsScoresAndDealerWithAccounts(t *testing.T) {
	playing := savedMahjongAssignment(t, MahjongFriend)
	playing.Rule, _ = guiyang.FindRuleDescriptor("guiyang", guiyang.LocalRuleVersion)
	playing.Room.RuleVersion = guiyang.LocalRuleVersion
	playing.RuleVersion = guiyang.LocalRuleVersion
	manager := NewManager(room.NewManager())
	if err := manager.RestoreMahjongAssignment(playing); err != nil {
		t.Fatal(err)
	}
	players := playing.PlayerAccountIDs
	finished, ok := manager.ProjectMahjongFriendSettlement(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, "local-next", 1, [4]int{8, -4, -2, -2})
	if !ok || finished.Series.Rounds != 1 || finished.NextDealerAccount != players[1] {
		t.Fatalf("wrong series projection: %+v", finished)
	}
	if !manager.SettleMahjongRound(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, "local-next", 1, [4]int{8, -4, -2, -2}) ||
		manager.SettleMahjongRound(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, "local-next", 1, [4]int{8, -4, -2, -2}) {
		t.Fatal("a round must contribute exactly once")
	}
	if got, _ := manager.MahjongFriendRoomSnapshot(playing.RoomID); !reflect.DeepEqual(got, finished) {
		t.Fatal("publication did not match the durable series projection")
	}
	restored := NewManager(room.NewManager())
	if err := restored.RestoreMahjongAssignment(finished); err != nil {
		t.Fatal(err)
	}
	if _, err := restored.LeaveMahjong(players[0], finished); err != nil {
		t.Fatal(err)
	}
	replacement := restoreRequest("replacement")
	replacement.RuleVersion = guiyang.LocalRuleVersion
	if err := restored.JoinMahjongFriendRoom(replacement, playing.RoomID); err != nil {
		t.Fatal(err)
	}
	next, _ := restored.MahjongFriendRoomSnapshot(playing.RoomID)
	scores, ranks := next.Series.Scoreboard(next.PlayerAccountIDs)
	if next.OpeningDealer() != 0 || next.PlayerAccountIDs[0] != players[1] ||
		!reflect.DeepEqual(scores, []int{-4, -2, -2, 0}) || !reflect.DeepEqual(ranks, []int{4, 2, 2, 1}) {
		t.Fatalf("compaction assigned the previous seat's dealer or points: %+v %v %v", next, scores, ranks)
	}
	if _, err := restored.LeaveMahjong(players[1], next); err != nil {
		t.Fatal(err)
	}
	legacy, _ := restored.MahjongFriendRoomSnapshot(playing.RoomID)
	legacy.NextDealer, legacy.NextDealerAccount = next.NextDealer, next.NextDealerAccount
	legacyRestore := NewManager(room.NewManager())
	if err := legacyRestore.RestoreMahjongAssignment(legacy); err != nil {
		t.Fatal(err)
	}
	returning := restoreRequest(players[1])
	returning.RuleVersion = guiyang.LocalRuleVersion
	for _, test := range []struct {
		name    string
		manager *Manager
	}{{"current waiting room", restored}, {"old waiting room snapshot", legacyRestore}} {
		t.Run(test.name, func(t *testing.T) {
			if err := test.manager.JoinMahjongFriendRoom(returning, playing.RoomID); err != nil {
				t.Fatal(err)
			}
			current, _ := test.manager.MahjongFriendRoomSnapshot(playing.RoomID)
			scores, _ := current.Series.Scoreboard(current.PlayerAccountIDs)
			if current.OpeningDealer() != 0 || current.PlayerAccountIDs[0] != players[2] ||
				!reflect.DeepEqual(scores, []int{-2, -2, 0, -4}) {
				t.Fatalf("returning dealer reclaimed the dealer seat or lost account points: %+v %v", current, scores)
			}
		})
	}
}

func TestFriendRoomSettlementProjectionCanBePublishedAfterCommit(t *testing.T) {
	playing := savedMahjongAssignment(t, MahjongFriend)
	manager := NewManager(room.NewManager())
	if err := manager.RestoreMahjongAssignment(playing); err != nil {
		t.Fatal(err)
	}
	matched, ok := manager.ProjectMahjongFriendSettlement(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, "round-two", 0)
	if !ok || matched.Room.State != "matched" || matched.Start || matched.ReadyPlayers != 0 || matched.CompletedRounds != playing.CompletedRounds+1 || matched.PreviousMatchID != "round-two" {
		t.Fatalf("unexpected settlement projection: %+v", matched)
	}
	if got, _ := manager.MahjongFriendRoomSnapshot(playing.RoomID); !reflect.DeepEqual(got, playing) {
		t.Fatal("projection mutated the room before persistence")
	}
	if err := manager.ReconcileMahjongFriendRoom(&playing, &matched); err != nil {
		t.Fatal(err)
	}
	if got, _ := manager.MahjongFriendRoomSnapshot(playing.RoomID); !reflect.DeepEqual(got, matched) {
		t.Fatal("committed room publication did not match projection")
	}
	if _, ok := manager.ProjectMahjongFriendSettlement(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, "stale", 0); ok {
		t.Fatal("stale round was projected")
	}
	if err := NewManager(room.NewManager()).RestoreMahjongAssignment(matched); err != nil {
		t.Fatal(err)
	}
	usingSettle := NewManager(room.NewManager())
	if err := usingSettle.RestoreMahjongAssignment(playing); err != nil {
		t.Fatal(err)
	}
	if !usingSettle.SettleMahjongRound(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, matched.PreviousMatchID, 0) {
		t.Fatal("settlement did not retain the room")
	}
	if actual, _ := usingSettle.MahjongFriendRoomSnapshot(playing.RoomID); !reflect.DeepEqual(actual, matched) {
		t.Fatal("settlement differs from the projected room")
	}
}

func TestFriendRoomRoundLimitClosesOnlyAfterLastHand(t *testing.T) {
	for _, completed := range []int{6, 7} {
		playing := savedMahjongAssignment(t, MahjongFriend)
		playing.Settings.RoundLimit = 8
		playing.CompletedRounds = completed
		manager := NewManager(room.NewManager())
		if err := manager.RestoreMahjongAssignment(playing); err != nil {
			t.Fatal(err)
		}
		wantRetained := completed == 6
		projected, projectedOK := manager.ProjectMahjongFriendSettlement(playing.RoomID, playing.Room.CreatedAt, completed, "this-round", 0)
		if !projectedOK || projected.CompletedRounds != completed+1 || (projected.Room.State == "matched") != wantRetained {
			t.Fatalf("unexpected terminal projection at %d: %+v", completed, projected)
		}
		retained := manager.SettleMahjongRound(playing.RoomID, playing.Room.CreatedAt, completed, "this-round", 0)
		_, assigned := manager.MahjongAssignment(playing.PlayerAccountIDs[0])
		if retained != wantRetained || assigned != wantRetained || playing.CanPlayAnotherRound() != wantRetained {
			t.Fatalf("retention and admission do not match the limit at %d", completed)
		}
	}
}

func TestFriendRoomRestoresPartialReadinessAndSurvivingHost(t *testing.T) {
	playing := savedMahjongAssignment(t, MahjongFriend)
	playing.Settings.TurnTimeoutSeconds = 60
	manager := NewManager(room.NewManager())
	if err := manager.RestoreMahjongAssignment(playing); err != nil {
		t.Fatal(err)
	}
	if !manager.SettleMahjongRound(playing.RoomID, playing.Room.CreatedAt, playing.CompletedRounds, "round-two", 0) {
		t.Fatal("settlement did not retain the room")
	}
	if _, err := manager.Ready(RoomReadyRequest{AccountID: "guest2", RoomID: playing.RoomID}); err != nil {
		t.Fatal(err)
	}
	matched, _ := manager.MahjongFriendRoomSnapshot(playing.RoomID)
	if matched.ReadyPlayers != 1 || !reflect.DeepEqual(matched.ReadyAccountIDs, []string{"guest2"}) {
		t.Fatalf("wrong readiness in snapshot: %+v", matched)
	}
	restarted := NewManager(room.NewManager())
	if err := restarted.RestoreMahjongAssignment(matched); err != nil {
		t.Fatal(err)
	}
	if got, _ := restarted.MahjongFriendRoomSnapshot(playing.RoomID); !reflect.DeepEqual(got, matched) {
		t.Fatal("partial readiness did not survive restore")
	}
	if _, err := restarted.LeaveMahjong("host", matched); err != nil {
		t.Fatal(err)
	}
	waiting, _ := restarted.MahjongFriendRoomSnapshot(playing.RoomID)
	if waiting.Room.State != "waiting" || waiting.RedAccountID != "guest1" || waiting.SeatIndex != 0 || waiting.ReadyPlayers != 0 ||
		waiting.PreviousMatchID != "round-two" || waiting.CompletedRounds != playing.CompletedRounds+1 || waiting.Rule != playing.Rule ||
		waiting.Settings.TurnTimeoutSeconds != 60 {
		t.Fatalf("waiting image has stale host, readiness, history, rule or time limit: %+v", waiting)
	}
	if err := restarted.ReconcileMahjongFriendRoom(&waiting, &matched); err != nil {
		t.Fatal(err)
	}
	if got, _ := restarted.MahjongFriendRoomSnapshot(playing.RoomID); !reflect.DeepEqual(got, matched) {
		t.Fatal("host leave rollback did not restore roster and readiness")
	}

	reopened := NewManager(room.NewManager())
	if err := reopened.RestoreMahjongAssignment(waiting); err != nil {
		t.Fatal(err)
	}
	if result, err := reopened.Ready(RoomReadyRequest{AccountID: "guest2", RoomID: waiting.RoomID}); err != nil || result.Start {
		t.Fatalf("cannot prepare while waiting for another seat: %v %v", result, err)
	}
	partlyReady, _ := reopened.MahjongFriendRoomSnapshot(waiting.RoomID)
	recovered := NewManager(room.NewManager())
	if err := recovered.RestoreMahjongAssignment(partlyReady); err != nil {
		t.Fatal(err)
	}
	if saved, _ := recovered.MahjongFriendRoomSnapshot(waiting.RoomID); saved.ReadyPlayers != 1 || saved.Start {
		t.Fatalf("partial waiting-room readiness was lost after restore: %v", saved)
	}
}
