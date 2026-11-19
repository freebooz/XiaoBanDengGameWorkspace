package matchmaking

import (
	"slices"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

func TestCancelActiveMahjongRoundOnlyReleasesItsCurrentSeats(t *testing.T) {
	for _, kind := range []string{MahjongQuick, MahjongFriend, MahjongTraining} {
		t.Run(kind, func(t *testing.T) {
			active := savedMahjongAssignment(t, kind)
			directory := room.NewManager()
			manager := NewManager(directory)
			if err := manager.RestoreMahjongAssignment(active); err != nil {
				t.Fatal(err)
			}
			other, err := manager.CreateMahjongRoom(restoreRequest("other"), MahjongTraining, nil)
			if err != nil {
				t.Fatal(err)
			}
			for _, change := range []func(*MahjongAssignment){
				func(a *MahjongAssignment) { a.Room.CreatedAt = a.Room.CreatedAt.Add(-time.Second) },
				func(a *MahjongAssignment) { a.CompletedRounds++ },
				func(a *MahjongAssignment) { a.PreviousMatchID = "another-round" },
				func(a *MahjongAssignment) { a.PlayerAccountIDs[3] = "replacement" },
				func(a *MahjongAssignment) { a.Start = false },
			} {
				stale := active
				stale.PlayerAccountIDs = slices.Clone(active.PlayerAccountIDs)
				change(&stale)
				if manager.CancelActiveMahjongRound(stale) {
					t.Fatal("a timeout for a stale assignment released a live round")
				}
			}
			if !manager.CancelActiveMahjongRound(active) {
				t.Fatal("active round did not dissolve")
			}
			for _, account := range active.PlayerAccountIDs {
				if _, exists := manager.MahjongAssignment(account); exists {
					t.Fatalf("seat %q remained assigned", account)
				}
			}
			if _, exists := directory.Get(active.RoomID); exists {
				t.Fatal("the dissolved room still owns its number")
			}
			if current, ok := manager.MahjongAssignment("other"); !ok || current.RoomID != other {
				t.Fatal("dissolving the round affected another room")
			}
			replacement := active
			replacement.Room.CreatedAt = active.Room.CreatedAt.Add(time.Second)
			if err := manager.RestoreMahjongAssignment(replacement); err != nil {
				t.Fatal(err)
			}
			if manager.CancelActiveMahjongRound(active) {
				t.Fatal("a late timeout released a new table sharing this number")
			}
		})
	}
}
