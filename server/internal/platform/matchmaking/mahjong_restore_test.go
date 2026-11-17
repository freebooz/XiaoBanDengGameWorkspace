package matchmaking

import (
	"encoding/json"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

func TestRestoreMahjongAssignmentPreservesCustomRoomAndRound(t *testing.T) {
	saved := savedMahjongAssignment(t, MahjongFriend)
	directory := room.NewManager()
	manager := NewManager(directory)
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := manager.RestoreMahjongAssignment(saved); err != nil {
				t.Errorf("restore exact replay: %v", err)
			}
		}()
	}
	wg.Wait()
	for index, account := range saved.PlayerAccountIDs {
		got, ok := manager.MahjongAssignment(account)
		want := saved
		want.SeatIndex = index
		if !ok || !reflect.DeepEqual(got, want) {
			t.Fatalf("seat %d recovered different assignment: %+v", index, got)
		}
	}
	if len(directory.List()) != 1 {
		t.Fatal("restored multiple directory entries")
	}
	seatOne := saved.PlayerAccountIDs[1]
	saved.PlayerAccountIDs[1] = "mutated-checkpoint"
	if players, ok := manager.MahjongPlayersFor(saved.RoomID); !ok || players[1] != seatOne {
		t.Fatal("restored seats retained the caller's mutable slice")
	}
	saved.PlayerAccountIDs[1] = seatOne
	if !manager.SettleMahjongRound(saved.RoomID, saved.Room.CreatedAt, saved.CompletedRounds, "played-after-restart", 0) {
		t.Fatal("restored room cannot settle normally")
	}
	if err := manager.RestoreMahjongAssignment(saved); err == nil {
		t.Fatal("stale checkpoint restarted a settled room")
	}
	continued, _ := manager.MahjongAssignment("host")
	if continued.CompletedRounds != 2 || continued.PreviousMatchID != "played-after-restart" || continued.ReadyPlayers != 0 || continued.Rule != saved.Rule {
		t.Fatalf("room did not progress from the restored round: %+v", continued)
	}
}

func TestRestoreLegacyGuiyangRoomRequiresKongToClaim(t *testing.T) {
	saved := savedMahjongAssignment(t, MahjongFriend)
	saved.Rule, _ = guiyang.ResolveRuleDescriptor("guiyang", "2.0.0", nil)
	saved.Rule.Options.RequiresKongToClaim = false
	saved.Rule.RequiresKongToClaim = false
	saved.Rule.Summary = "四人108张，不吃；点炮、抢杠胡及鸡分按本房设置，首胡窗口结算。"
	saved.Room.RuleSetID, saved.Room.RuleVersion = saved.Rule.ID, saved.Rule.Version
	saved.RuleSetID, saved.RuleVersion = saved.Rule.ID, saved.Rule.Version
	manager := NewManager(room.NewManager())
	if err := manager.RestoreMahjongAssignment(saved); err != nil {
		t.Fatal(err)
	}
	got, ok := manager.MahjongAssignment(saved.PlayerAccountIDs[0])
	if !ok || !got.Rule.RequiresKongToClaim || !got.Rule.Options.RequiresKongToClaim {
		t.Fatalf("reconnected Guiyang player still has a no-kong claim rule: %+v", got.Rule)
	}
}

func TestRestoreMahjongAssignmentRejectsConflictsWithoutPartialAssignment(t *testing.T) {
	tests := map[string]func(*MahjongAssignment){
		"duplicate seat":      func(saved *MahjongAssignment) { saved.PlayerAccountIDs[1] = saved.PlayerAccountIDs[0] },
		"foreign ready seat":  func(saved *MahjongAssignment) { saved.ReadyAccountIDs[3] = "stranger" },
		"wrong room identity": func(saved *MahjongAssignment) { saved.Room.RoomID = "1234" },
		"invalid room number": func(saved *MahjongAssignment) { saved.Room.RoomID, saved.RoomID = "0001", "0001" },
		"missing timestamp":   func(saved *MahjongAssignment) { saved.Room.CreatedAt = time.Time{} },
		"invalid status":      func(saved *MahjongAssignment) { saved.Room.State = "matched" },
		"invalid rule":        func(saved *MahjongAssignment) { saved.Rule.AllowChi = true },
		"invalid history":     func(saved *MahjongAssignment) { saved.PreviousMatchID = "" },
	}
	for name, modify := range tests {
		t.Run(name, func(t *testing.T) {
			directory := room.NewManager()
			manager := NewManager(directory)
			saved := savedMahjongAssignment(t, MahjongFriend)
			modify(&saved)
			if err := manager.RestoreMahjongAssignment(saved); err == nil || len(directory.List()) != 0 || len(manager.assignments) != 0 {
				t.Fatalf("invalid restore published state, err=%v", err)
			}
		})
	}
	t.Run("live account and reused room number", func(t *testing.T) {
		saved := savedMahjongAssignment(t, MahjongFriend)
		directory := room.NewManager()
		manager := NewManager(directory)
		liveRoom, err := manager.CreateMahjongRoom(restoreRequest("guest3"), MahjongFriend, nil)
		if err != nil {
			t.Fatal(err)
		}
		if saved.RoomID == liveRoom {
			saved.Room.RoomID, saved.RoomID = "1000", "1000"
			if liveRoom == "1000" {
				saved.Room.RoomID, saved.RoomID = "1001", "1001"
			}
		}
		if err := manager.RestoreMahjongAssignment(saved); err == nil || len(directory.List()) != 1 || len(manager.assignments) != 1 {
			t.Fatalf("restore claimed a player assigned to another room: %v", err)
		}
		saved.Room.RoomID, saved.RoomID = liveRoom, liveRoom
		if err := manager.RestoreMahjongAssignment(saved); err == nil || len(directory.List()) != 1 || len(manager.assignments) != 1 {
			t.Fatalf("restore overwrote an existing room: %v", err)
		}
	})
}

func TestRestoreMahjongAssignmentPreservesQuickAndTrainingEntry(t *testing.T) {
	for _, kind := range []string{MahjongQuick, MahjongTraining} {
		t.Run(kind, func(t *testing.T) {
			saved := savedMahjongAssignment(t, kind)
			manager := NewManager(room.NewManager())
			if err := manager.RestoreMahjongAssignment(saved); err != nil {
				t.Fatal(err)
			}
			if err := manager.RestoreMahjongAssignment(saved); err != nil {
				t.Fatal(err)
			}
			got, ok := manager.MahjongAssignment("host")
			if !ok || !reflect.DeepEqual(got, saved) {
				t.Fatalf("restored different assignment: %+v", got)
			}
			if kind == MahjongQuick {
				queued, err := manager.QuickMatch(restoreRequest("host"))
				if err != nil || queued.RoomID != saved.RoomID {
					t.Fatalf("quick match no longer idempotent: %v", err)
				}
			} else if len(manager.assignments) != 1 {
				t.Fatal("training bots received human assignments")
			}
		})
	}
}

func restoreRequest(account string) QuickMatchRequest {
	return QuickMatchRequest{AccountID: account, ProductID: "xbd_mahjong", GameID: "mahjong", RuleSetID: "guiyang", RuleVersion: "2.0.0"}
}

func savedMahjongAssignment(t *testing.T, kind string) MahjongAssignment {
	t.Helper()
	original := NewManager(room.NewManager())
	accounts := []string{"host", "guest1", "guest2", "guest3"}
	var code string
	var err error
	switch kind {
	case MahjongQuick:
		for _, account := range accounts {
			joined, joinErr := original.QuickMatch(restoreRequest(account))
			if joinErr != nil {
				t.Fatal(joinErr)
			}
			code = joined.RoomID
		}
	case MahjongFriend:
		options := guiyang.RuleOptions{Version: guiyang.RuleOptionsVersion, Chicken: true}
		code, err = original.CreateMahjongRoom(restoreRequest("host"), kind, &options)
		if err != nil {
			t.Fatal(err)
		}
		for _, account := range accounts[1:] {
			if err := original.JoinMahjongFriendRoom(restoreRequest(account), code); err != nil {
				t.Fatal(err)
			}
		}
	case MahjongTraining:
		_, err = original.CreateMahjongRoom(restoreRequest("host"), kind, nil)
		if err != nil {
			t.Fatal(err)
		}
	}
	if kind != MahjongTraining {
		for _, account := range accounts {
			if _, err := original.Ready(RoomReadyRequest{AccountID: account, RoomID: code}); err != nil {
				t.Fatal(err)
			}
		}
	}
	saved, ok := original.MahjongAssignment("host")
	if !ok || !saved.Start {
		t.Fatal("failed to build original active assignment")
	}
	if kind == MahjongFriend {
		if !original.SettleMahjongRound(code, saved.Room.CreatedAt, 0, "first-round", 0) {
			t.Fatal("failed to build round history")
		}
		for _, account := range accounts {
			if _, err := original.Ready(RoomReadyRequest{AccountID: account, RoomID: code}); err != nil {
				t.Fatal(err)
			}
		}
		saved, _ = original.MahjongAssignment("host")
	}
	data, err := json.Marshal(saved)
	if err != nil {
		t.Fatal(err)
	}
	var restored MahjongAssignment
	if err := json.Unmarshal(data, &restored); err != nil {
		t.Fatal(err)
	}
	return restored
}
