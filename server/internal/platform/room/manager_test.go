package room

import (
	"regexp"
	"sync"
	"testing"
)

var numericRoomID = regexp.MustCompile(`^[1-9][0-9]{3}$`)

func testRoomRequest() CreateRequest {
	return CreateRequest{ProductID: "xbd_chinese_chess", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0"}
}

func TestRoomsHaveFourDigitUniqueIDsUnderConcurrentCreation(t *testing.T) {
	manager := NewManager()
	var workers sync.WaitGroup
	ids := make(chan string, 128)
	for i := 0; i < cap(ids); i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			item, err := manager.Create(testRoomRequest())
			if err != nil {
				t.Errorf("create room: %v", err)
				return
			}
			ids <- item.RoomID
		}()
	}
	workers.Wait()
	close(ids)
	seen := map[string]bool{}
	for id := range ids {
		if !numericRoomID.MatchString(id) {
			t.Fatalf("room ID must contain four digits: %q", id)
		}
		if seen[id] {
			t.Fatalf("active room ID was reused: %s", id)
		}
		seen[id] = true
	}
	if len(seen) != 128 {
		t.Fatalf("expected 128 rooms, got %d", len(seen))
	}
}

func TestFourDigitRoomCapacityAndReleasedNumber(t *testing.T) {
	manager := NewManager()
	var released string
	for i := 0; i < 9000; i++ {
		item, err := manager.Create(testRoomRequest())
		if err != nil || !numericRoomID.MatchString(item.RoomID) {
			t.Fatalf("room %d: ID=%q error=%v", i, item.RoomID, err)
		}
		released = item.RoomID
	}
	if len(manager.List()) != 9000 {
		t.Fatal("allocation overwrote an existing room")
	}
	if _, err := manager.Create(testRoomRequest()); err == nil {
		t.Fatal("a full room directory must return an error")
	}
	manager.Close(released)
	replacement, err := manager.Create(testRoomRequest())
	if err != nil || replacement.RoomID != released {
		t.Fatalf("released number should become available: %+v error=%v", replacement, err)
	}
}
