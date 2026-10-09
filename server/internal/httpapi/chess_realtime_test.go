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

// newTestChessHub 通过真实 WebSocket 驱动房间协议，避免用伪造连接绕过生命周期。
func newTestChessHub(t *testing.T) (*chessHub, string) {
	t.Helper()
	hub := newChessHub()
	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		client := newChessClient(conn)
		defer hub.disconnect(client)
		for {
			var message map[string]any
			if conn.ReadJSON(&message) != nil {
				return
			}
			hub.handle(client, message)
		}
	}))
	t.Cleanup(server.Close)
	return hub, "ws" + strings.TrimPrefix(server.URL, "http")
}

func joinTestChessRoom(t *testing.T, conn *websocket.Conn, roomID, clientID string) map[string]any {
	t.Helper()
	mustWriteJSON(t, conn, map[string]any{"type": "chess_join", "room_id": roomID, "client_id": clientID})
	_ = readUntilType(t, conn, "chess_joined", nil)
	return readUntilType(t, conn, "chess_state", nil)
}

func moveTestRedSoldier(t *testing.T, conn *websocket.Conn) {
	t.Helper()
	mustWriteJSON(t, conn, map[string]any{
		"type": "chess_move", "piece_id": "red_soldier_0",
		"from": map[string]any{"x": 0, "y": 6}, "to": map[string]any{"x": 0, "y": 5},
	})
}

func TestChessHubRejectsDuplicateClientID(t *testing.T) {
	_, url := newTestChessHub(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, "duplicate-room", "red-id")
	duplicate := dialTestWebSocket(t, url)
	mustWriteJSON(t, duplicate, map[string]any{"type": "chess_join", "room_id": "duplicate-room", "client_id": "red-id"})
	var response map[string]any
	if err := duplicate.ReadJSON(&response); err != nil {
		t.Fatal(err)
	}
	if response["type"] != "chess_error" {
		t.Fatalf("同一标识的并发连接必须被拒绝，实际=%v", response)
	}
	_ = duplicate.Close()
	black := dialTestWebSocket(t, url)
	defer black.Close()
	state := joinTestChessRoom(t, black, "duplicate-room", "black-id")
	if state["your_color"] != "black" || state["red_player"] != "red-id" {
		t.Fatalf("拒绝连接断开不能释放原玩家席位: %v", state)
	}
	_ = readUntilType(t, red, "chess_state", nil)
	moveTestRedSoldier(t, red)
	assertPiecePosition(t, readUntilType(t, red, "chess_state", nil), "red_soldier_0", 0, 5)
}

func TestChessHubRejectsMoveWhileWaiting(t *testing.T) {
	_, url := newTestChessHub(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, "waiting-room", "red-id")
	moveTestRedSoldier(t, red)
	var response map[string]any
	if err := red.ReadJSON(&response); err != nil {
		t.Fatal(err)
	}
	if response["type"] != "chess_error" {
		t.Fatalf("等待对手时走子必须被拒绝，实际=%v", response["type"])
	}
	black := dialTestWebSocket(t, url)
	defer black.Close()
	state := joinTestChessRoom(t, black, "waiting-room", "black-id")
	assertPiecePosition(t, state, "red_soldier_0", 0, 6)
	if state["turn"] != "red" {
		t.Fatal("等待期间不能改变回合")
	}
}

func TestChessHubSwitchRoomReleasesPreviousSeat(t *testing.T) {
	hub, url := newTestChessHub(t)
	player := dialTestWebSocket(t, url)
	defer player.Close()
	joinTestChessRoom(t, player, "old-room", "player-id")
	state := joinTestChessRoom(t, player, "new-room", "player-id")
	if state["room_id"] != "new-room" {
		t.Fatalf("未进入新房间: %v", state)
	}
	oldRoom := hub.findRoom("old-room")
	oldRoom.mu.Lock()
	remaining := len(oldRoom.clients)
	oldState := oldRoom.snapshotFor(&chessClient{})
	oldRoom.mu.Unlock()
	if remaining != 0 || oldState["red_player"] != "" {
		t.Fatalf("切换房间必须移除旧成员并释放席位: clients=%d state=%v", remaining, oldState)
	}
	replacement := dialTestWebSocket(t, url)
	defer replacement.Close()
	if state := joinTestChessRoom(t, replacement, "old-room", "replacement-id"); state["your_color"] != "red" {
		t.Fatal("旧房间应能重新分配红方席位")
	}
}

func TestChessHubRepeatedJoinKeepsSeatAndClock(t *testing.T) {
	_, url := newTestChessHub(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, "repeat-room", "red-id")
	black := dialTestWebSocket(t, url)
	defer black.Close()
	initial := joinTestChessRoom(t, black, "repeat-room", "black-id")
	_ = readUntilType(t, red, "chess_state", nil)
	repeated := joinTestChessRoom(t, red, "repeat-room", "red-id")
	if repeated["your_color"] != "red" || repeated["match_started_at_ms"] != initial["match_started_at_ms"] {
		t.Fatal("同一连接重复加入应保留席位与对局计时")
	}
	mustWriteJSON(t, red, map[string]any{"type": "chess_join", "room_id": "repeat-room", "client_id": "changed-id"})
	var response map[string]any
	if err := red.ReadJSON(&response); err != nil {
		t.Fatal(err)
	}
	if response["type"] != "chess_error" {
		t.Fatal("已加入连接不能通过改标识占用另一个席位")
	}
}

func TestChessHubRepeatedJoinDoesNotTakeVacantOpponentSeat(t *testing.T) {
	_, url := newTestChessHub(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, "vacant-room", "red-id")
	black := dialTestWebSocket(t, url)
	defer black.Close()
	joinTestChessRoom(t, black, "vacant-room", "black-id")
	_ = readUntilType(t, red, "chess_state", nil)
	_ = red.Close()
	_ = readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "waiting" })
	state := joinTestChessRoom(t, black, "vacant-room", "black-id")
	if state["your_color"] != "black" || state["red_player"] != "" || state["status"] != "waiting" {
		t.Fatalf("重复加入不能占用对手空位: %v", state)
	}
	mustWriteJSON(t, black, map[string]any{
		"type": "chess_move", "piece_id": "black_soldier_0",
		"from": map[string]any{"x": 0, "y": 3}, "to": map[string]any{"x": 0, "y": 4},
	})
	var response map[string]any
	if err := black.ReadJSON(&response); err != nil {
		t.Fatal(err)
	}
	if response["type"] != "chess_error" || !strings.Contains(response["message"].(string), "双方就绪") {
		t.Fatalf("对手断线后应拒绝走子: %v", response)
	}
}

func TestChessHubRepeatedSpectatorJoinKeepsRole(t *testing.T) {
	_, url := newTestChessHub(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, "spectator-room", "red-id")
	black := dialTestWebSocket(t, url)
	defer black.Close()
	joinTestChessRoom(t, black, "spectator-room", "black-id")
	spectator := dialTestWebSocket(t, url)
	defer spectator.Close()
	joinTestChessRoom(t, spectator, "spectator-room", "spectator-id")
	_ = red.Close()
	_ = readUntilType(t, spectator, "chess_state", func(m map[string]any) bool { return m["status"] == "waiting" })
	state := joinTestChessRoom(t, spectator, "spectator-room", "spectator-id")
	if state["your_color"] != "" || state["red_player"] != "" || state["black_player"] != "black-id" {
		t.Fatalf("观战连接重复加入不应占用空位: %v", state)
	}
}
