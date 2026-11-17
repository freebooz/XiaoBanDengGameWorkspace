package matchmaking

import (
	"encoding/json"
	"testing"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

func TestRestoredPausedFriendRoomKeepsSeatsButRejectsNewPlayers(t *testing.T) {
	original := NewManager(room.NewManager())
	roomID, err := original.CreateMahjongRoom(restoreRequest("host"), MahjongFriend, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := original.JoinMahjongFriendRoom(restoreRequest("guest"), roomID); err != nil {
		t.Fatal(err)
	}
	waiting, _ := original.MahjongFriendRoomSnapshot(roomID)
	if err := json.Unmarshal([]byte(`{"admission_paused":true,"admission_revision":1}`), &waiting.Settings); err != nil {
		t.Fatal(err)
	}
	manager := NewManager(room.NewManager())
	if err := manager.RestoreMahjongAssignment(waiting); err != nil {
		t.Fatal(err)
	}
	if err := manager.JoinMahjongFriendRoom(restoreRequest("guest"), roomID); err != nil {
		t.Fatalf("existing seat could not return: %v", err)
	}
	if _, err := manager.Ready(RoomReadyRequest{AccountID: "guest", RoomID: roomID}); err != nil {
		t.Fatalf("existing seat could not ready: %v", err)
	}
	if err := manager.JoinMahjongFriendRoom(restoreRequest("new-player"), roomID); err == nil {
		t.Fatal("paused room admitted a new player")
	}
	rooms := manager.MahjongPublicRooms()
	if len(rooms) != 1 || rooms[0].Players != 2 || rooms[0].Joinable {
		t.Fatalf("wrong public availability for a paused room: %+v", rooms)
	}
}
