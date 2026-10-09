package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"sort"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/chinesechess"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchrecord"
	roomplatform "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

// chessHub（象棋实时对局中心）负责把两个 WebSocket 客户端绑定到同一个开发/一期象棋房间。
// 房间中的棋盘状态只保存在服务端，客户端只能提交走子意图，最终合法性由 chinesechess.Board 校验。
type chessHub struct {
	mu                sync.Mutex
	rooms             map[string]*chessRoom
	directory         *roomplatform.Manager
	records           matchrecord.Store
	recordsConfigured bool
	allowDevelopment  bool
}

// chessRoom（象棋实时房间）串行保护同一棋局中的座位、棋盘和广播。
// 一期先采用进程内状态，后续可在 Room/GameNode 分层后迁移到独立游戏节点。
type chessRoom struct {
	mu              sync.Mutex
	roomID          string
	board           *chinesechess.Board
	clients         map[*chessClient]struct{}
	seats           map[chinesechess.Color]string
	winner          chinesechess.Color
	matchStartedAt  time.Time
	turnStartedAt   time.Time
	metadata        roomplatform.Room
	directory       *roomplatform.Manager
	records         matchrecord.Store
	recordsRequired bool
	players         map[string]roomplatform.Player
	matchID         string
	sequence        int64
	blocked         bool
	resultReason    string
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
	return &chessHub{rooms: map[string]*chessRoom{}, directory: roomplatform.NewManager(), allowDevelopment: true}
}

// ConfigureRecords 在接收连接前接入真实仓储与HTTP共用目录；默认拒绝未知房间。
func (h *chessHub) ConfigureRecords(store matchrecord.Store, directory *roomplatform.Manager) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.records, h.directory, h.recordsConfigured = store, directory, true
	h.allowDevelopment = false
}

// ConfigureDevelopmentRooms 只供显式开发配置启用，创建的目录标记development来源。
func (h *chessHub) ConfigureDevelopmentRooms(allow bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.allowDevelopment = allow
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
func (h *chessHub) getOrCreateRoom(roomID string) (*chessRoom, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if existing := h.rooms[roomID]; existing != nil {
		return existing, nil
	}
	if h.directory == nil {
		return nil, errors.New("房间目录不可用")
	}
	metadata, exists := h.directory.Get(roomID)
	if !exists {
		if !h.allowDevelopment {
			return nil, errors.New("房间不存在，请先创建房间")
		}
		metadata = h.directory.EnsureDevelopment(roomID)
	}
	if metadata.GameID != "chinese_chess" || metadata.RuleSetID != "standard" || metadata.RuleVersion != "1.0.0" {
		return nil, errors.New("房间游戏或规则版本不支持象棋实时对局")
	}
	created := &chessRoom{
		roomID:  roomID,
		board:   chinesechess.NewInitialBoard(),
		clients: map[*chessClient]struct{}{},
		seats: map[chinesechess.Color]string{
			chinesechess.Red:   "",
			chinesechess.Black: "",
		},
		metadata: metadata, directory: h.directory, records: h.records, recordsRequired: h.recordsConfigured,
		players: map[string]roomplatform.Player{},
	}
	h.rooms[roomID] = created
	return created, nil
}

// findRoom（查找房间）。
func (h *chessHub) findRoom(roomID string) *chessRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.rooms[roomID]
}

// handleJoin（加入房间）按红方、黑方顺序分配座位；第三个连接进入观战。
// 一个 client_id 只能对应一个在房间中的活动连接；同一连接重复加入保持幂等。
func (h *chessHub) handleJoin(client *chessClient, message map[string]any) {
	roomID, _ := message["room_id"].(string)
	clientID, _ := message["client_id"].(string)
	if roomID == "" || clientID == "" {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "加入象棋房间必须提供 room_id 和 client_id"})
		return
	}
	if client.clientID != "" && client.clientID != clientID {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "已加入连接不能更改 client_id"})
		return
	}
	room, err := h.getOrCreateRoom(roomID)
	if err != nil {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": err.Error()})
		return
	}
	if client.roomID != "" && client.roomID != roomID {
		// 先释放旧房间锁和成员，再进入新房间，避免同时持有两个房间锁。
		h.disconnect(client)
	}

	room.mu.Lock()
	defer room.mu.Unlock()
	if room.blocked {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "对局记录异常，房间已暂停"})
		return
	}

	for existing := range room.clients {
		if existing != client && existing.clientID == clientID {
			_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "该 client_id 已有活动连接"})
			return
		}
	}

	color := client.color
	_, alreadyJoined := room.clients[client]
	if !alreadyJoined {
		if room.seats[chinesechess.Red] == "" {
			color = chinesechess.Red
			room.seats[chinesechess.Red] = clientID
		} else if room.seats[chinesechess.Black] == "" {
			color = chinesechess.Black
			room.seats[chinesechess.Black] = clientID
		}
	}

	client.roomID = roomID
	client.clientID = clientID
	client.color = color
	room.clients[client] = struct{}{}
	seat := string(color)
	if seat == "" {
		seat = "spectator"
	}
	// 已被替换的离线席位不无限累积在实时目录中，历史仍由对局玩家表保留。
	for id, player := range room.players {
		if !player.Connected && player.Seat == seat {
			delete(room.players, id)
		}
	}
	room.players[clientID] = roomplatform.Player{ClientID: clientID, Seat: seat, Connected: true}

	// 两个正式座位都就绪时才启动权威对局计时；观战连接不会影响计时。
	if room.seats[chinesechess.Red] != "" && room.seats[chinesechess.Black] != "" && room.matchStartedAt.IsZero() {
		if err := room.startMatchLocked(); err != nil {
			if !alreadyJoined {
				delete(room.clients, client)
				if color != "" {
					room.seats[color] = ""
				}
				player := room.players[clientID]
				player.Connected = false
				room.players[clientID] = player
				client.roomID, client.clientID, client.color = "", "", ""
			}
			room.stopForStorageErrorLocked(err)
			_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "创建对局记录失败，房间已暂停"})
			return
		}
	}
	room.publishRuntimeLocked()

	_ = client.writeJSON(map[string]any{
		"type":       "chess_joined",
		"room_id":    roomID,
		"match_id":   room.matchID,
		"your_color": string(color),
		"message":    joinMessage(color),
	})
	room.broadcastStateLocked()
}

// handleMove（处理走子）只允许已入座的当前阵营提交动作。
// 规则校验与持久化事务均成功后广播权威棋盘；客户端本地状态不能覆盖该结果。
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
	if room.blocked {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "对局记录异常，房间已暂停"})
		return
	}

	if client.color != chinesechess.Red && client.color != chinesechess.Black {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "观战连接不能走棋"})
		return
	}
	if _, joined := room.clients[client]; !joined || room.seats[client.color] != client.clientID {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "当前连接未占用该席位"})
		return
	}
	if room.winner != "" {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "本局已经结束"})
		return
	}
	if room.seats[chinesechess.Red] == "" || room.seats[chinesechess.Black] == "" {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "等待双方就绪后才能走棋"})
		return
	}
	if room.board.Turn != client.color {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "当前不是你的回合"})
		return
	}

	previousBoard := cloneChessBoard(room.board)
	previousWinner, previousTurnAt, previousSequence := room.winner, room.turnStartedAt, room.sequence
	if err := room.board.ApplyMove(move); err != nil {
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": err.Error()})
		return
	}
	room.winner = capturedGeneralWinner(room.board)
	// 合法走子完成后切换回合，并以服务端时间重置下一步计时。
	room.turnStartedAt = time.Now().UTC()
	room.sequence++
	status, reason := "playing", ""
	if room.winner != "" {
		status, reason = "finished", "general_captured"
	}
	room.resultReason = reason
	payload, _ := json.Marshal(map[string]any{"client_id": client.clientID, "seat": string(client.color), "move": move})
	if err := room.persistChangeLocked("chess_move", payload, status, reason, room.turnStartedAt); err != nil {
		room.board, room.winner, room.turnStartedAt, room.sequence = previousBoard, previousWinner, previousTurnAt, previousSequence
		room.resultReason = ""
		room.stopForStorageErrorLocked(err)
		_ = client.writeJSON(map[string]any{"type": "chess_error", "message": "保存对局记录失败，房间已暂停"})
		return
	}
	room.publishRuntimeLocked()
	room.broadcastStateLocked()
}

// disconnect（连接断开）释放席位并更新当前进程的连接事实。
// 正式玩家离开会中止活动对局；替补就绪从标准开局建立新记录。
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
	if _, joined := room.clients[client]; !joined {
		return
	}
	clientID, color := client.clientID, client.color
	delete(room.clients, client)
	player := room.players[clientID]
	player.Connected = false
	room.players[clientID] = player
	// 正式玩家断线结束当前对局；观战连接不改变对局生命周期。
	if color != "" && room.matchID != "" && room.winner == "" && !room.blocked {
		payload, _ := json.Marshal(map[string]any{"client_id": clientID, "seat": string(color), "reason": "player_disconnected"})
		room.sequence++
		if err := room.persistChangeLocked("match_aborted", payload, "aborted", "player_disconnected", time.Now().UTC()); err != nil {
			room.sequence--
			room.stopForStorageErrorLocked(err)
		}
	}
	if client.color == chinesechess.Red && room.seats[chinesechess.Red] == client.clientID {
		room.seats[chinesechess.Red] = ""
	}
	if client.color == chinesechess.Black && room.seats[chinesechess.Black] == client.clientID {
		room.seats[chinesechess.Black] = ""
	}
	client.roomID = ""
	client.clientID = ""
	client.color = ""
	if !room.blocked && (color != "" || len(room.clients) == 0) {
		room.resetMatchLocked()
	}
	room.publishRuntimeLocked()
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

	status := r.statusLocked()
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
		"match_id":               r.matchID,
		"sequence":               r.sequence,
		"product_id":             r.metadata.ProductID,
		"game_id":                r.metadata.GameID,
		"rule_set_id":            r.metadata.RuleSetID,
		"rule_version":           r.metadata.RuleVersion,
		"result_reason":          r.resultReason,
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

func (r *chessRoom) statusLocked() string {
	if r.blocked {
		return "unavailable"
	}
	if r.winner != "" {
		return "finished"
	}
	if r.seats[chinesechess.Red] != "" && r.seats[chinesechess.Black] != "" && r.matchID != "" {
		return "playing"
	}
	return "waiting"
}

func (r *chessRoom) publishRuntimeLocked() {
	players := make([]roomplatform.Player, 0, len(r.players))
	for _, player := range r.players {
		players = append(players, player)
	}
	sort.Slice(players, func(i, j int) bool {
		if players[i].Seat == players[j].Seat {
			return players[i].ClientID < players[j].ClientID
		}
		return players[i].Seat < players[j].Seat
	})
	r.directory.UpdateRuntime(r.roomID, r.statusLocked(), r.matchID, players)
}

// startMatchLocked 先落库再确认入座，所有后续快照都引用这个UUID。
func (r *chessRoom) startMatchLocked() error {
	r.matchID, r.sequence = uuid.NewString(), 0
	r.matchStartedAt = time.Now().UTC()
	r.turnStartedAt = r.matchStartedAt
	if r.recordsRequired && r.records == nil {
		r.resetMatchLocked()
		return errors.New("对局仓储未配置")
	}
	if r.records == nil {
		return nil
	}
	snapshot, err := json.Marshal(r.snapshotFor(&chessClient{}))
	if err != nil {
		r.resetMatchLocked()
		return err
	}
	source := r.metadata.Source
	if source == "" {
		source = "room"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	err = r.records.CreateMatch(ctx, matchrecord.Match{MatchID: r.matchID, RoomID: r.roomID, ProductID: r.metadata.ProductID, GameID: r.metadata.GameID, RuleSetID: r.metadata.RuleSetID, RuleVersion: r.metadata.RuleVersion, Source: source, StartedAt: r.matchStartedAt, Players: []matchrecord.Player{{ClientID: r.seats[chinesechess.Red], Seat: "red"}, {ClientID: r.seats[chinesechess.Black], Seat: "black"}}, Snapshot: snapshot})
	if err != nil {
		r.resetMatchLocked()
	}
	return err
}

func (r *chessRoom) persistChangeLocked(eventType string, payload json.RawMessage, status, reason string, occurredAt time.Time) error {
	if r.recordsRequired && r.records == nil {
		return errors.New("对局仓储未配置")
	}
	if r.records == nil {
		return nil
	}
	snapshot := r.snapshotFor(&chessClient{})
	snapshot["status"], snapshot["result_reason"] = status, reason
	encoded, err := json.Marshal(snapshot)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return r.records.AppendChange(ctx, matchrecord.Change{MatchID: r.matchID, Sequence: r.sequence, EventType: eventType, Payload: payload, Snapshot: encoded, Status: status, Winner: string(r.winner), ResultReason: reason, OccurredAt: occurredAt})
}

func (r *chessRoom) stopForStorageErrorLocked(err error) {
	r.blocked = true
	r.publishRuntimeLocked()
	log.Printf("象棋对局记录写入失败 room_id=%s match_id=%s: %v", r.roomID, r.matchID, err)
}

func (r *chessRoom) resetMatchLocked() {
	r.board, r.winner, r.resultReason = chinesechess.NewInitialBoard(), "", ""
	r.matchID, r.sequence = "", 0
	r.matchStartedAt, r.turnStartedAt = time.Time{}, time.Time{}
}

// 棋子是指针，必须深拷贝才能在事务失败时恢复吃子与坐标。
func cloneChessBoard(board *chinesechess.Board) *chinesechess.Board {
	cloned := &chinesechess.Board{Turn: board.Turn, Pieces: make(map[string]*chinesechess.Piece, len(board.Pieces))}
	for id, piece := range board.Pieces {
		copy := *piece
		cloned.Pieces[id] = &copy
	}
	return cloned
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
