package room

import "testing"

// 目录玩家是客户端连接事实；返回副本必须隔离调用方写入。
func TestManagerRuntimeSnapshotIsDetached(t *testing.T) {
	m := NewManager()
	r, err := m.Create(CreateRequest{ProductID: "p", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0"})
	if err != nil {
		t.Fatal(err)
	}
	if !m.UpdateRuntime(r.RoomID, "playing", "match-1", []Player{{ClientID: "guest", Seat: "red", Connected: true}}) {
		t.Fatal("更新已有目录房间失败")
	}
	item, _ := m.Get(r.RoomID)
	if item.ConnectedCount != 1 || item.MatchID != "match-1" || item.State != "playing" {
		t.Fatalf("连接快照错误: %+v", item)
	}
	item.Players[0].Connected = false
	listed := m.List()
	listed[0].Players[0].ClientID = "changed"
	again, _ := m.Get(r.RoomID)
	if !again.Players[0].Connected || again.Players[0].ClientID != "guest" {
		t.Fatal("外部修改污染了目录")
	}
}
