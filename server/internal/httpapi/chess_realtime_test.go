package httpapi

import (
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/chinesechess"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
)

func TestReusedRoomNumberStartsFreshWithoutOldClientDisconnectResettingIt(t *testing.T) {
	hub := newChessHub()
	old := hub.getOrCreateRoom("1234")
	old.dissolved = true
	old.endReason = "timeout"
	old.moveNumber = 9
	oldClient := &chessClient{roomID: "1234", clientID: "old-red", color: chinesechess.Red}
	old.clients[oldClient] = struct{}{}
	fresh := hub.getOrCreateRoom("1234")
	if fresh == old || fresh.moveNumber != 1 || fresh.endReason != "" || fresh.dissolved {
		t.Fatal("reused four-digit number must create a fresh game")
	}
	oldClient.room = old
	fresh.moveNumber = 3
	hub.disconnect(oldClient)
	if fresh.moveNumber != 3 || hub.findRoom("1234") != fresh {
		t.Fatal("old client disconnect must not reset the replacement game")
	}
}

// TestChessHubTwoClients（双客户端象棋实时集成测试）验证：
// 1. 两个连接进入同一房间后分别取得红方和黑方；
// 2. 红方合法走兵后，红黑双方都收到相同权威快照；
// 3. 回合正确切换给黑方；
// 4. 非当前回合重复走子会被服务端拒绝。
func TestChessHubTwoClients(t *testing.T) {
	hub := newChessHub()
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		client := newChessClient(conn)
		defer hub.disconnect(client)
		for {
			var message map[string]any
			if err := conn.ReadJSON(&message); err != nil {
				return
			}
			hub.handle(client, message)
		}
	})

	server := httptest.NewServer(handler)
	defer server.Close()
	wsURL := "ws" + strings.TrimPrefix(server.URL, "http")

	red := dialTestWebSocket(t, wsURL)
	defer red.Close()
	black := dialTestWebSocket(t, wsURL)
	defer black.Close()

	mustWriteJSON(t, red, map[string]any{"type": "chess_join", "room_id": "test-room", "client_id": "red-client"})
	redJoined := readUntilType(t, red, "chess_joined", nil)
	if redJoined["your_color"] != "red" {
		t.Fatalf("首位玩家应为红方，实际=%v", redJoined["your_color"])
	}
	// 首位玩家会先收到 waiting 快照。
	_ = readUntilType(t, red, "chess_state", nil)

	mustWriteJSON(t, black, map[string]any{"type": "chess_join", "room_id": "test-room", "client_id": "black-client"})
	blackJoined := readUntilType(t, black, "chess_joined", nil)
	if blackJoined["your_color"] != "black" {
		t.Fatalf("第二位玩家应为黑方，实际=%v", blackJoined["your_color"])
	}

	redReady := readUntilType(t, red, "chess_state", func(m map[string]any) bool { return m["status"] == "playing" })
	blackReady := readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "playing" })
	if redReady["turn"] != "red" || blackReady["turn"] != "red" {
		t.Fatal("标准开局必须由红方先行")
	}
	if int(redReady["move_number"].(float64)) != 1 || int(blackReady["move_number"].(float64)) != 1 {
		t.Fatalf("标准开局权威步数必须为1: red=%v black=%v", redReady["move_number"], blackReady["move_number"])
	}
	if redReady["match_started_at_ms"].(float64) <= 0 || redReady["turn_started_at_ms"].(float64) <= 0 {
		t.Fatal("双方就绪后必须下发服务端权威对局/回合开始时间")
	}
	if int(redReady["step_warning_seconds"].(float64)) != 60 || int(redReady["step_countdown_seconds"].(float64)) != 30 {
		t.Fatalf("单步计时配置错误: %v", redReady)
	}
	if redReady["server_time_ms"].(float64) < redReady["match_started_at_ms"].(float64) {
		t.Fatal("服务端当前时间不能早于对局开始时间")
	}

	mustWriteJSON(t, red, map[string]any{
		"type":     "chess_move",
		"piece_id": "red_soldier_0",
		"from":     map[string]any{"x": 0, "y": 6},
		"to":       map[string]any{"x": 0, "y": 5},
	})

	redState := readUntilType(t, red, "chess_state", nil)
	blackState := readUntilType(t, black, "chess_state", nil)
	if redState["turn"] != "black" || blackState["turn"] != "black" {
		t.Fatal("红方走子后必须切换为黑方回合")
	}
	if int(redState["move_number"].(float64)) != 2 || int(blackState["move_number"].(float64)) != 2 {
		t.Fatalf("合法走子后权威步数必须递增到2: red=%v black=%v", redState["move_number"], blackState["move_number"])
	}
	assertPiecePosition(t, redState, "red_soldier_0", 0, 5)
	assertPiecePosition(t, blackState, "red_soldier_0", 0, 5)
	if blackState["turn_started_at_ms"].(float64) <= 0 {
		t.Fatal("合法走子后必须为下一回合重新下发权威开始时间")
	}

	// 红方连续再走一步属于非法操作，应由服务端拒绝。
	mustWriteJSON(t, red, map[string]any{
		"type":     "chess_move",
		"piece_id": "red_soldier_0",
		"from":     map[string]any{"x": 0, "y": 5},
		"to":       map[string]any{"x": 0, "y": 4},
	})
	errorMessage := readUntilType(t, red, "chess_error", nil)
	if !strings.Contains(errorMessage["message"].(string), "当前不是你的回合") {
		t.Fatalf("预期服务端拒绝抢回合，实际=%v", errorMessage)
	}
}

func TestChessTurnTimeoutDissolvesRoom(t *testing.T) {
	rooms := room.NewManager()
	matchManager := matchmaking.NewManager(rooms)
	base := matchmaking.QuickMatchRequest{
		ProductID:   "xbd_chinese_chess",
		GameID:      "chinese_chess",
		RuleSetID:   "standard",
		RuleVersion: "1.0.0",
	}
	base.AccountID = "timeout-red"
	redMatch, err := matchManager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	base.AccountID = "timeout-black"
	if _, err := matchManager.QuickMatch(base); err != nil {
		t.Fatal(err)
	}
	if _, err := matchManager.Ready(matchmaking.RoomReadyRequest{AccountID: "timeout-red", RoomID: redMatch.RoomID}); err != nil {
		t.Fatal(err)
	}
	if _, err := matchManager.Ready(matchmaking.RoomReadyRequest{AccountID: "timeout-black", RoomID: redMatch.RoomID}); err != nil {
		t.Fatal(err)
	}

	hub := newChessHub(matchManager)
	hub.turnTimeout = 80 * time.Millisecond
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		client := newChessClient(conn)
		defer hub.disconnect(client)
		for {
			var message map[string]any
			if err := conn.ReadJSON(&message); err != nil {
				return
			}
			hub.handle(client, message)
		}
	})

	server := httptest.NewServer(handler)
	defer server.Close()
	wsURL := "ws" + strings.TrimPrefix(server.URL, "http")

	red := dialTestWebSocket(t, wsURL)
	defer red.Close()
	black := dialTestWebSocket(t, wsURL)
	defer black.Close()

	mustWriteJSON(t, red, map[string]any{"type": "chess_join", "room_id": redMatch.RoomID, "client_id": "timeout-red"})
	_ = readUntilType(t, red, "chess_joined", nil)
	_ = readUntilType(t, red, "chess_state", nil)

	mustWriteJSON(t, black, map[string]any{"type": "chess_join", "room_id": redMatch.RoomID, "client_id": "timeout-black"})
	_ = readUntilType(t, black, "chess_joined", nil)
	_ = readUntilType(t, red, "chess_state", func(m map[string]any) bool { return m["status"] == "playing" })
	_ = readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "playing" })

	finalRed := readUntilType(t, red, "chess_state", func(m map[string]any) bool { return m["status"] == "finished" })
	finalBlack := readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "finished" })

	for _, state := range []map[string]any{finalRed, finalBlack} {
		if state["end_reason"] != "timeout" {
			t.Fatalf("超时结束原因错误: %v", state["end_reason"])
		}
		if state["loser"] != "red" {
			t.Fatalf("首回合超时方应为红方: %v", state["loser"])
		}
		if state["winner"] != "" {
			t.Fatalf("超时自动解散不应伪造胜方: %v", state["winner"])
		}
		if state["dissolved"] != true {
			t.Fatalf("超时后必须标记已解散: %v", state["dissolved"])
		}
	}

	if _, ok := rooms.Get(redMatch.RoomID); ok {
		t.Fatal("超时后活动房间必须从房间目录移除")
	}

	base.AccountID = "timeout-red"
	rematch, err := matchManager.QuickMatch(base)
	if err != nil {
		t.Fatal(err)
	}
	if rematch.RoomID == redMatch.RoomID {
		t.Fatal("超时解散后重新匹配必须创建新房间")
	}
}

func dialTestWebSocket(t *testing.T, url string) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("连接测试 WebSocket 失败: %v", err)
	}
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	return conn
}

func mustWriteJSON(t *testing.T, conn *websocket.Conn, value any) {
	t.Helper()
	if err := conn.WriteJSON(value); err != nil {
		t.Fatalf("发送 WebSocket 消息失败: %v", err)
	}
}

func readUntilType(t *testing.T, conn *websocket.Conn, expectedType string, predicate func(map[string]any) bool) map[string]any {
	t.Helper()
	for i := 0; i < 8; i++ {
		var message map[string]any
		if err := conn.ReadJSON(&message); err != nil {
			t.Fatalf("读取 WebSocket 消息失败: %v", err)
		}
		if message["type"] != expectedType {
			continue
		}
		if predicate == nil || predicate(message) {
			return message
		}
	}
	t.Fatalf("未收到期望消息类型 %s", expectedType)
	return nil
}

func assertPiecePosition(t *testing.T, state map[string]any, pieceID string, x, y int) {
	t.Helper()
	pieces, ok := state["pieces"].([]any)
	if !ok {
		t.Fatalf("pieces 类型异常: %T", state["pieces"])
	}
	for _, raw := range pieces {
		piece, ok := raw.(map[string]any)
		if !ok || piece["id"] != pieceID {
			continue
		}
		if int(piece["x"].(float64)) != x || int(piece["y"].(float64)) != y {
			t.Fatalf("棋子 %s 坐标错误: %v", pieceID, piece)
		}
		return
	}
	t.Fatalf("未找到棋子 %s", pieceID)
}
