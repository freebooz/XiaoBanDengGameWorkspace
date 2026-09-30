package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

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
