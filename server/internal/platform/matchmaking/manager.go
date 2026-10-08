package matchmaking

import (
	"errors"
	"fmt"
	"strings"
	"sync"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

const (
	StatusWaiting = "waiting"
	StatusMatched = "matched"
)

type QuickMatchRequest struct {
	AccountID   string `json:"account_id"`
	ProductID   string `json:"product_id"`
	GameID      string `json:"game_id"`
	RuleSetID   string `json:"rule_set_id"`
	RuleVersion string `json:"rule_version"`
}

type QuickMatchResult struct {
	Status           string   `json:"status"`
	RoomID           string   `json:"room_id"`
	Players          int      `json:"players"`
	ProductID        string   `json:"product_id"`
	GameID           string   `json:"game_id"`
	RuleSetID        string   `json:"rule_set_id"`
	RuleVersion      string   `json:"rule_version"`
	SeatColor        string   `json:"seat_color"`
	RedAccountID     string   `json:"red_account_id"`
	BlackAccountID   string   `json:"black_account_id"`
	ReadyPlayers     int      `json:"ready_players"`
	Start            bool     `json:"start"`
	Capacity         int      `json:"capacity"`
	SeatIndex        int      `json:"seat_index"`
	PlayerAccountIDs []string `json:"player_account_ids"`
}

type RoomReadyRequest struct {
	AccountID string `json:"account_id"`
	RoomID    string `json:"room_id"`
}

type RoomReadyResult struct {
	RoomID       string `json:"room_id"`
	ReadyPlayers int    `json:"ready_players"`
	Start        bool   `json:"start"`
}

type CancelRequest struct {
	AccountID string `json:"account_id"`
}

type assignment struct {
	RoomID string
	Key    string
}

type Manager struct {
	mu            sync.Mutex
	rooms         *room.Manager
	waitingByKey  map[string]string
	assignments   map[string]assignment
	playersByRoom map[string][]string
	readyByRoom   map[string]map[string]bool
}

func NewManager(rooms *room.Manager) *Manager {
	return &Manager{
		rooms:         rooms,
		waitingByKey:  map[string]string{},
		assignments:   map[string]assignment{},
		playersByRoom: map[string][]string{},
		readyByRoom:   map[string]map[string]bool{},
	}
}

// QuickMatch（快速匹配）具有账号级幂等性。
// 第一名玩家进入红方等待位，第二名玩家进入黑方；匹配完成只进入房间阶段，双方准备后才开始对局。
func (m *Manager) QuickMatch(req QuickMatchRequest) (QuickMatchResult, error) {
	if err := validateRequest(req); err != nil {
		return QuickMatchResult{}, err
	}
	key := queueKey(req)

	m.mu.Lock()
	defer m.mu.Unlock()

	if current, ok := m.assignments[req.AccountID]; ok {
		if _, exists := m.rooms.Get(current.RoomID); exists {
			return m.resultLocked(current.RoomID, req.AccountID), nil
		}
		delete(m.assignments, req.AccountID)
	}

	if roomID, ok := m.waitingByKey[key]; ok {
		players := m.playersByRoom[roomID]
		capacity := capacityFor(req.GameID)
		if len(players) < capacity && !containsPlayer(players, req.AccountID) {
			players = append(players, req.AccountID)
			m.playersByRoom[roomID] = players
			m.assignments[req.AccountID] = assignment{RoomID: roomID, Key: key}
			if len(players) == capacity {
				delete(m.waitingByKey, key)
				if !m.rooms.SetState(roomID, "matched") {
					return QuickMatchResult{}, errors.New("匹配房间已失效")
				}
			}
			return m.resultLocked(roomID, req.AccountID), nil
		}
	}

	created, err := m.rooms.Create(room.CreateRequest{
		ProductID:   req.ProductID,
		GameID:      req.GameID,
		RuleSetID:   req.RuleSetID,
		RuleVersion: req.RuleVersion,
	})
	if err != nil {
		return QuickMatchResult{}, fmt.Errorf("创建匹配房间失败: %w", err)
	}
	m.waitingByKey[key] = created.RoomID
	m.assignments[req.AccountID] = assignment{RoomID: created.RoomID, Key: key}
	m.playersByRoom[created.RoomID] = []string{req.AccountID}
	m.readyByRoom[created.RoomID] = map[string]bool{}
	return m.resultLocked(created.RoomID, req.AccountID), nil
}

// Ready（准备进入对局）是幂等操作；只有两个正式座位都准备后才把房间置为playing。
func (m *Manager) Ready(req RoomReadyRequest) (RoomReadyResult, error) {
	if strings.TrimSpace(req.AccountID) == "" || strings.TrimSpace(req.RoomID) == "" {
		return RoomReadyResult{}, errors.New("account_id/room_id不能为空")
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	current, ok := m.assignments[req.AccountID]
	if !ok || current.RoomID != req.RoomID {
		return RoomReadyResult{}, errors.New("玩家不属于该匹配房间")
	}
	players := m.playersByRoom[req.RoomID]
	item, exists := m.rooms.Get(req.RoomID)
	if !exists {
		return RoomReadyResult{}, errors.New("匹配房间已失效")
	}
	capacity := capacityFor(item.GameID)
	if len(players) < capacity {
		return RoomReadyResult{}, errors.New("玩家尚未满座")
	}
	if m.readyByRoom[req.RoomID] == nil {
		m.readyByRoom[req.RoomID] = map[string]bool{}
	}
	m.readyByRoom[req.RoomID][req.AccountID] = true
	readyPlayers := m.readyCountLocked(req.RoomID)
	start := readyPlayers >= capacity
	if start {
		if !m.rooms.SetState(req.RoomID, "playing") {
			return RoomReadyResult{}, errors.New("房间已失效")
		}
	}
	return RoomReadyResult{RoomID: req.RoomID, ReadyPlayers: readyPlayers, Start: start}, nil
}

// Cancel（退出匹配/房间）允许对局开始前退出。
// 剩余一名玩家继续使用原房间等待，并重新成为红方等待位。
func (m *Manager) Cancel(accountID string) error {
	accountID = strings.TrimSpace(accountID)
	if accountID == "" {
		return errors.New("account_id不能为空")
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	current, ok := m.assignments[accountID]
	if !ok {
		return nil
	}
	item, exists := m.rooms.Get(current.RoomID)
	if exists && item.State == "playing" {
		return errors.New("对局已经开始，不能退出匹配房间")
	}

	players := m.playersByRoom[current.RoomID]
	remaining := make([]string, 0, len(players))
	for _, player := range players {
		if player != accountID {
			remaining = append(remaining, player)
		}
	}
	delete(m.assignments, accountID)
	delete(m.readyByRoom, current.RoomID)

	if len(remaining) == 0 {
		if waitingRoom, ok := m.waitingByKey[current.Key]; ok && waitingRoom == current.RoomID {
			delete(m.waitingByKey, current.Key)
		}
		delete(m.playersByRoom, current.RoomID)
		if exists {
			m.rooms.SetState(current.RoomID, "closed")
		}
		return nil
	}

	m.playersByRoom[current.RoomID] = remaining
	m.waitingByKey[current.Key] = current.RoomID
	m.readyByRoom[current.RoomID] = map[string]bool{}
	if exists {
		m.rooms.SetState(current.RoomID, "waiting")
	}
	return nil
}

// FinishRoom（结束房间）释放房间内全部玩家的匹配关系并从活动房间目录移除。
// 该操作幂等，供正常结算与超时解散统一调用。
func (m *Manager) FinishRoom(roomID string) {
	roomID = strings.TrimSpace(roomID)
	if roomID == "" {
		return
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	for _, accountID := range m.playersByRoom[roomID] {
		delete(m.assignments, accountID)
	}
	for key, waitingRoomID := range m.waitingByKey {
		if waitingRoomID == roomID {
			delete(m.waitingByKey, key)
		}
	}
	delete(m.playersByRoom, roomID)
	delete(m.readyByRoom, roomID)
	m.rooms.Close(roomID)
}

func (m *Manager) resultLocked(roomID string, accountID string) QuickMatchResult {
	item, ok := m.rooms.Get(roomID)
	if !ok {
		return QuickMatchResult{Status: StatusWaiting, RoomID: roomID}
	}
	players := m.playersByRoom[roomID]
	status := StatusWaiting
	capacity := capacityFor(item.GameID)
	if len(players) >= capacity {
		status = StatusMatched
	}
	seatIndex := -1
	for index, player := range players {
		if player == accountID {
			seatIndex = index
			break
		}
	}
	seatColor := ""
	if item.GameID == "chinese_chess" && len(players) > 0 && players[0] == accountID {
		seatColor = "red"
	} else if item.GameID == "chinese_chess" && len(players) > 1 && players[1] == accountID {
		seatColor = "black"
	}
	redAccountID := ""
	blackAccountID := ""
	if len(players) > 0 {
		redAccountID = players[0]
	}
	if len(players) > 1 {
		blackAccountID = players[1]
	}
	readyPlayers := m.readyCountLocked(roomID)
	return QuickMatchResult{
		Status:           status,
		RoomID:           roomID,
		Players:          len(players),
		ProductID:        item.ProductID,
		GameID:           item.GameID,
		RuleSetID:        item.RuleSetID,
		RuleVersion:      item.RuleVersion,
		SeatColor:        seatColor,
		RedAccountID:     redAccountID,
		BlackAccountID:   blackAccountID,
		ReadyPlayers:     readyPlayers,
		Start:            item.State == "playing" && readyPlayers >= capacity,
		Capacity:         capacity,
		SeatIndex:        seatIndex,
		PlayerAccountIDs: append([]string(nil), players...),
	}
}

// SeatIndexFor 返回服务端分配的四人麻将座位，也供其他多座位游戏复用。
func (m *Manager) SeatIndexFor(roomID string, accountID string) (int, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	current, ok := m.assignments[accountID]
	if !ok || current.RoomID != roomID {
		return -1, false
	}
	for index, player := range m.playersByRoom[roomID] {
		if player == accountID {
			return index, true
		}
	}
	return -1, false
}

// MahjongPlayersFor 仅为已满座且四人准备完成的麻将房间返回权威座位表。
func (m *Manager) MahjongPlayersFor(roomID string) ([4]string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var seats [4]string
	item, ok := m.rooms.Get(roomID)
	if !ok || item.GameID != "mahjong" || item.State != "playing" {
		return seats, false
	}
	players := m.playersByRoom[roomID]
	if len(players) != 4 || m.readyCountLocked(roomID) != 4 {
		return seats, false
	}
	copy(seats[:], players)
	return seats, true
}

// LandlordPlayersFor 返回已经满座且完成准备的三人斗地主座位。
func (m *Manager) LandlordPlayersFor(roomID string) ([3]string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var seats [3]string
	item, ok := m.rooms.Get(roomID)
	if !ok || item.GameID != "landlord" || item.State != "playing" {
		return seats, false
	}
	players := m.playersByRoom[roomID]
	if len(players) != 3 || m.readyCountLocked(roomID) != 3 {
		return seats, false
	}
	copy(seats[:], players)
	return seats, true
}

func capacityFor(gameID string) int {
	if gameID == "mahjong" || gameID == "guandan" {
		return 4
	}
	if gameID == "landlord" {
		return 3
	}
	return 2
}

// GuandanPlayersFor 仅返回已经满座并完成准备的四人掼蛋搭档座位。
func (m *Manager) GuandanPlayersFor(roomID string) ([4]string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var seats [4]string
	item, ok := m.rooms.Get(roomID)
	if !ok || item.GameID != "guandan" || item.State != "playing" || len(m.playersByRoom[roomID]) != 4 || m.readyCountLocked(roomID) != 4 {
		return seats, false
	}
	copy(seats[:], m.playersByRoom[roomID])
	return seats, true
}

func containsPlayer(players []string, accountID string) bool {
	for _, player := range players {
		if player == accountID {
			return true
		}
	}
	return false
}

// SeatFor（查询权威座位）供实时对局层校验红/黑身份，禁止客户端自行声明阵营。
func (m *Manager) SeatFor(roomID string, accountID string) (string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	current, ok := m.assignments[accountID]
	if !ok || current.RoomID != roomID {
		return "", false
	}
	players := m.playersByRoom[roomID]
	if len(players) > 0 && players[0] == accountID {
		return "red", true
	}
	if len(players) > 1 && players[1] == accountID {
		return "black", true
	}
	return "", false
}

func (m *Manager) readyCountLocked(roomID string) int {
	count := 0
	for _, ready := range m.readyByRoom[roomID] {
		if ready {
			count++
		}
	}
	return count
}

func validateRequest(req QuickMatchRequest) error {
	if strings.TrimSpace(req.AccountID) == "" {
		return errors.New("account_id不能为空")
	}
	if req.ProductID == "" || req.GameID == "" || req.RuleSetID == "" || req.RuleVersion == "" {
		return errors.New("product_id/game_id/rule_set_id/rule_version均不能为空")
	}
	return nil
}

func queueKey(req QuickMatchRequest) string {
	return strings.Join([]string{req.ProductID, req.GameID, req.RuleSetID, req.RuleVersion}, "|")
}
