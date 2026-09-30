package httpapi

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/chinesechess"
	"github.com/gorilla/websocket"
)

// chessHub（象棋实时对局中心）负责把两个 WebSocket 客户端绑定到同一个开发/一期象棋房间。
// 房间中的棋盘状态只保存在服务端，客户端只能提交走子意图，最终合法性由 chinesechess.Board 校验。
type chessHub struct {
	mu    sync.Mutex
	rooms map[string]*chessRoom
}

// chessRoom（象棋实时房间）串行保护同一棋局中的座位、棋盘和广播。
// 一期先采用进程内状态，后续可在 Room/GameNode 分层后迁移到独立游戏节点。
type chessRoom struct {
	mu             sync.Mutex
	roomID         string
	board          *chinesechess.Board
	clients        map[*chessClient]struct{}
	seats          map[chinesechess.Color]string
	winner         chinesechess.Color
	matchStartedAt time.Time
	turnStartedAt  time.Time
}

// chessClient（象棋实时连接）保存单个 WebSocket 的房间、客户端标识与阵营。
// writeMu 保证同一连接不会被多个房间事件协程并发写入。
type chessClient struct {
	conn     *websocket.Conn
	writeMu  sync.Mutex
	roomID   string
	clientID string
	color    chinesechess.Color
}

// chessPieceView（棋子快照）是服务端发给客户端的稳定只读结构。
type chessPieceView struct {
	ID    string                 `json:"id"`
	Type  chinesechess.PieceType `json:"type"`
	Color chinesechess.Color     `json:"color"`
	X     int                    `json:"x"`
	Y     int                    `json:"y"`
}

// newChessHub（创建象棋实时中心）。
func newChessHub() *chessHub {
	return &chessHub{rooms: map[string]*chessRoom{}}
}

// newChessClient（创建连接上下文）。
func newChessClient(conn *websocket.Conn) *chessClient {
	return &chessClient{conn: conn}
}

// writeJSON（线程安全写消息）统一保护一个 WebSocket 连接的写操作。
func (c *chessClient) writeJSON(v any) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	return c.conn.WriteJSON(v)
}

// handle（处理象棋实时消息）返回 true 表示消息已由象棋子协议消费。
func (h *chessHub) handle(client *chessClient, message map[string]any) bool {
	messageType, _ := message["type"].(string)
	switch messageType {
	case "chess_join":
		h.handleJoin(client, message)
		return true
	case "chess_move":
		h.handleMove(client, message)
		return true
	default:
		return false
	}
}

// getOrCreateRoom（获取或创建房间）只在短时间内持有中心锁。
func (h *chessHub) getOrCreateRoom(roomID string) *chessRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	if existing := h.rooms[roomID]; existing != nil {
		return existing
	}
	created := &chessRoom{
		roomID:  roomID,
		board:   chinesechess.NewInitialBoard(),
		clients: map[*chessClient]struct{}{},
		seats: map[chinesechess.Color]string{
			chinesechess.Red:   "",
			chinesechess.Black: "",
		},
	}
	h.rooms[roomID] = created
	return created
}

// findRoom（查找房间）。
func (h *chessHub) findRoom(roomID string) *chessRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.rooms[roomID]
}

// handleJoin（加入房间）按红方、黑方顺序分配座位；第三个连接进入观战。
// 同一个 client_id 重新连接时尽量恢复原座位。
func (h *chessHub) handleJoin(client *chessClient, message map[string]any) {
	roomID, _ := message["room_id"].(string)
	clientID, _ := message["client_id"].(string)
	if roomID == "" || clientID == "" {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "加入象棋房间必须提供 room_id 和 client_id"})
		return
	}

	room := h.getOrCreateRoom(roomID)
	room.mu.Lock()
	defer room.mu.Unlock()

	color := chinesechess.Color("")
	if room.seats[chinesechess.Red] == "" || room.seats[chinesechess.Red] == clientID {
		color = chinesechess.Red
		room.seats[chinesechess.Red] = clientID
	} else if room.seats[chinesechess.Black] == "" || room.seats[chinesechess.Black] == clientID {
		color = chinesechess.Black
		room.seats[chinesechess.Black] = clientID
	}

	client.roomID = roomID
	client.clientID = clientID
	client.color = color
	room.clients[client] = struct{}{}

	// 两个正式座位都就绪时才启动权威对局计时；观战连接不会影响计时。
	if room.seats[chinesechess.Red] != "" && room.seats[chinesechess.Black] != "" && room.matchStartedAt.IsZero() {
		now := time.Now().UTC()
		room.matchStartedAt = now
		room.turnStartedAt = now
	}

	_ = client.writeJSON(map[string]any{
		"type":       "chess_joined",
		"room_id":    roomID,
		"your_color": string(color),
		"message":    joinMessage(color),
	})
	room.broadcastStateLocked()
}

// handleMove（处理走子）只允许已入座的当前阵营提交动作。
// 规则校验成功后立即广播新的权威棋盘快照；客户端本地状态不能覆盖该结果。
func (h *chessHub) handleMove(client *chessClient, message map[string]any) {
	if client.roomID == "" {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "尚未加入象棋房间"})
		return
	}
	room := h.findRoom(client.roomID)
	if room == nil {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "象棋房间不存在"})
		return
	}

	move, err := decodeChessMove(message)
	if err != nil {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": err.Error()})
		return
	}

	room.mu.Lock()
	defer room.mu.Unlock()

	if client.color != chinesechess.Red && client.color != chinesechess.Black {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "观战连接不能走棋"})
		return
	}
	if room.winner != "" {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "本局已经结束"})
		return
	}
	if room.board.Turn != client.color {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "当前不是你的回合"})
		return
	}

	if err := room.board.ApplyMove(move); err != nil {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": err.Error()})
		return
	}
	room.winner = capturedGeneralWinner(room.board)
	// 合法走子完成后切换回合，并以服务端时间重置下一步计时。
	room.turnStartedAt = time.Now().UTC()
	room.broadcastStateLocked()
}

// disconnect（连接断开）释放该连接占用的座位。
// 最后一个客户端离开后重置棋盘，方便下一轮人工测试从标准开局开始。
func (h *chessHub) disconnect(client *chessClient) {
	if client == nil || client.roomID == "" {
		return
	}
	room := h.findRoom(client.roomID)
	if room == nil {
		return
	}

	room.mu.Lock()
	defer room.mu.Unlock()
	delete(room.clients, client)
	if client.color == chinesechess.Red && room.seats[chinesechess.Red] == client.clientID {
		room.seats[chinesechess.Red] = ""
	}
	if client.color == chinesechess.Black && room.seats[chinesechess.Black] == client.clientID {
		room.seats[chinesechess.Black] = ""
	}
	if len(room.clients) == 0 {
		room.board = chinesechess.NewInitialBoard()
		room.winner = ""
		room.matchStartedAt = time.Time{}
		room.turnStartedAt = time.Time{}
		room.seats[chinesechess.Red] = ""
		room.seats[chinesechess.Black] = ""
		return
	}
	room.broadcastStateLocked()
}

// broadcastStateLocked（广播权威状态）要求调用方已经持有 room.mu。
func (r *chessRoom) broadcastStateLocked() {
	for client := range r.clients {
		_ = client.writeJSON(r.snapshotFor(client))
	}
}

// snapshotFor（生成客户端快照）只包含表现层需要的数据。
func (r *chessRoom) snapshotFor(client *chessClient) map[string]any {
	pieces := make([]chessPieceView, 0, len(r.board.Pieces))
	for _, piece := range r.board.Pieces {
		if !piece.Alive {
			continue
		}
		pieces = append(pieces, chessPieceView{
			ID: piece.ID, Type: piece.Type, Color: piece.Color,
			X: piece.Pos.X, Y: piece.Pos.Y,
		})
	}
	sort.Slice(pieces, func(i, j int) bool {
		if pieces[i].Y == pieces[j].Y {
			return pieces[i].X < pieces[j].X
		}
		return pieces[i].Y < pieces[j].Y
	})

	status := "waiting"
	if r.seats[chinesechess.Red] != "" && r.seats[chinesechess.Black] != "" {
		status = "playing"
	}
	if r.winner != "" {
		status = "finished"
	}
	now := time.Now().UTC()
	matchStartedAtMS := int64(0)
	turnStartedAtMS := int64(0)
	if !r.matchStartedAt.IsZero() {
		matchStartedAtMS = r.matchStartedAt.UnixMilli()
	}
	if !r.turnStartedAt.IsZero() {
		turnStartedAtMS = r.turnStartedAt.UnixMilli()
	}
	return map[string]any{
		"type":                   "chess_state",
		"room_id":                r.roomID,
		"status":                 status,
		"turn":                   string(r.board.Turn),
		"winner":                 string(r.winner),
		"your_color":             string(client.color),
		"red_player":             r.seats[chinesechess.Red],
		"black_player":           r.seats[chinesechess.Black],
		"server_time_ms":         now.UnixMilli(),
		"match_started_at_ms":    matchStartedAtMS,
		"turn_started_at_ms":     turnStartedAtMS,
		"step_warning_seconds":   60,
		"step_countdown_seconds": 30,
		"pieces":                 pieces,
	}
}

// decodeChessMove（解析客户端走子命令）。
func decodeChessMove(message map[string]any) (chinesechess.Move, error) {
	pieceID, _ := message["piece_id"].(string)
	if pieceID == "" {
		return chinesechess.Move{}, errors.New("缺少 piece_id")
	}
	fromMap, ok := message["from"].(map[string]any)
	if !ok {
		return chinesechess.Move{}, errors.New("缺少合法 from 坐标")
	}
	toMap, ok := message["to"].(map[string]any)
	if !ok {
		return chinesechess.Move{}, errors.New("缺少合法 to 坐标")
	}
	fromX, ok := jsonInt(fromMap["x"])
	if !ok {
		return chinesechess.Move{}, errors.New("from.x 不是整数")
	}
	fromY, ok := jsonInt(fromMap["y"])
	if !ok {
		return chinesechess.Move{}, errors.New("from.y 不是整数")
	}
	toX, ok := jsonInt(toMap["x"])
	if !ok {
		return chinesechess.Move{}, errors.New("to.x 不是整数")
	}
	toY, ok := jsonInt(toMap["y"])
	if !ok {
		return chinesechess.Move{}, errors.New("to.y 不是整数")
	}
	return chinesechess.Move{
		PieceID: pieceID,
		From:    chinesechess.Position{X: fromX, Y: fromY},
		To:      chinesechess.Position{X: toX, Y: toY},
	}, nil
}

// jsonInt（读取 JSON 数字）兼容 encoding/json 默认的 float64。
func jsonInt(value any) (int, bool) {
	switch typed := value.(type) {
	case float64:
		return int(typed), typed == float64(int(typed))
	case int:
		return typed, true
	default:
		return 0, false
	}
}

// capturedGeneralWinner（判断是否有将/帅被吃）用于一期最小完整胜负验证。
// 更完整的将军、将死、长将、长捉与和棋规则后续仍由确定性 RuleSet 扩展。
func capturedGeneralWinner(board *chinesechess.Board) chinesechess.Color {
	redAlive := false
	blackAlive := false
	for _, piece := range board.Pieces {
		if piece.Type != chinesechess.General || !piece.Alive {
			continue
		}
		if piece.Color == chinesechess.Red {
			redAlive = true
		}
		if piece.Color == chinesechess.Black {
			blackAlive = true
		}
	}
	if !redAlive {
		return chinesechess.Black
	}
	if !blackAlive {
		return chinesechess.Red
	}
	return ""
}

// joinMessage（加入提示）。
func joinMessage(color chinesechess.Color) string {
	switch color {
	case chinesechess.Red:
		return "你是红方，红方先行。"
	case chinesechess.Black:
		return "你是黑方，请等待红方走棋。"
	default:
		return "红黑双方座位已满，你以观战身份进入。"
	}
}
