package matchrecord

import (
	"context"
	"encoding/json"
	"testing"
)

func TestUnavailableStoreReturnsError(t *testing.T) {
	store := NewPostgresStore(nil)
	match := Match{MatchID: "id", RoomID: "room", Players: []Player{{ClientID: "red", Seat: "red"}, {ClientID: "black", Seat: "black"}}, Snapshot: json.RawMessage(`{}`)}
	if err := store.CreateMatch(context.Background(), match); err == nil {
		t.Fatal("缺少数据库不能报告持久化成功")
	}
	if err := store.AppendChange(context.Background(), Change{Sequence: 1, Payload: json.RawMessage(`{}`), Snapshot: json.RawMessage(`{}`), Status: "playing"}); err == nil {
		t.Fatal("缺少数据库不能报告持久化成功")
	}
}
