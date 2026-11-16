package room

import (
	"crypto/rand"
	"errors"
	"math/big"
	"sort"
	"strconv"
	"sync"
	"time"
)

// Room（通用房间）只管理玩家容器与游戏标识，不实现象棋或麻将规则。
type Room struct {
	RoomID      string    `json:"room_id"`
	ProductID   string    `json:"product_id"`
	GameID      string    `json:"game_id"`
	RuleSetID   string    `json:"rule_set_id"`
	RuleVersion string    `json:"rule_version"`
	State       string    `json:"state"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreateRequest（创建房间请求）由大厅/匹配服务提交。
type CreateRequest struct {
	ProductID       string `json:"product_id"`
	GameID          string `json:"game_id"`
	RuleSetID       string `json:"rule_set_id"`
	RuleVersion     string `json:"rule_version"`
	RequestedRoomID string `json:"-"`
}

// Manager（房间管理器）一期使用进程内存维护活动房间目录。
type Manager struct {
	mu    sync.RWMutex
	rooms map[string]Room
}

// NewManager（创建房间管理器）。
func NewManager() *Manager { return &Manager{rooms: map[string]Room{}} }

// Create（创建房间）验证统一游戏标识。
func (m *Manager) Create(req CreateRequest) (Room, error) {
	if req.ProductID == "" || req.GameID == "" || req.RuleSetID == "" || req.RuleVersion == "" {
		return Room{}, errors.New("product_id/game_id/rule_set_id/rule_version均不能为空")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.rooms) >= 9000 {
		return Room{}, errors.New("房间已满，请稍后重试")
	}
	roomID := req.RequestedRoomID
	if roomID != "" {
		number, err := strconv.Atoi(roomID)
		if err != nil || number < 1000 || number > 9999 || strconv.Itoa(number) != roomID {
			return Room{}, errors.New("房间号须为 1000 至 9999 的四位数字")
		}
		if _, exists := m.rooms[roomID]; exists {
			return Room{}, errors.New("房间号已被占用，请重新生成")
		}
	} else {
		start, err := rand.Int(rand.Reader, big.NewInt(9000))
		if err != nil {
			return Room{}, errors.New("生成房间号失败，请稍后重试")
		}
		for offset := 0; offset < 9000; offset++ {
			candidate := strconv.Itoa(1000 + (int(start.Int64())+offset)%9000)
			if _, exists := m.rooms[candidate]; !exists {
				roomID = candidate
				break
			}
		}
	}
	item := Room{RoomID: roomID, ProductID: req.ProductID, GameID: req.GameID, RuleSetID: req.RuleSetID, RuleVersion: req.RuleVersion, State: "waiting", CreatedAt: time.Now().UTC()}
	m.rooms[item.RoomID] = item
	return item, nil
}

// Restore reserves a persisted room number without replacing an existing room.
func (m *Manager) Restore(item Room) error {
	number, err := strconv.Atoi(item.RoomID)
	if err != nil || len(item.RoomID) != 4 || number < 1000 || number > 9999 || item.CreatedAt.IsZero() ||
		item.ProductID == "" || item.GameID == "" || item.RuleSetID == "" || item.RuleVersion == "" ||
		(item.State != "waiting" && item.State != "matched" && item.State != "playing") {
		return errors.New("无效的活动房间快照")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, exists := m.rooms[item.RoomID]; exists {
		return errors.New("房间号已被占用")
	}
	m.rooms[item.RoomID] = item
	return nil
}

// List（列出活动房间）返回按创建时间倒序排列的稳定快照。
func (m *Manager) List() []Room {
	m.mu.RLock()
	defer m.mu.RUnlock()
	result := make([]Room, 0, len(m.rooms))
	for _, item := range m.rooms {
		result = append(result, item)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].CreatedAt.After(result[j].CreatedAt) })
	return result
}

// Get（获取单个活动房间）返回值副本，避免管理后台直接持有内部可变状态。
func (m *Manager) Get(roomID string) (Room, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	item, ok := m.rooms[roomID]
	return item, ok
}

// SetState（更新房间状态）由匹配和对局生命周期管理调用。
func (m *Manager) SetState(roomID string, state string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	item, ok := m.rooms[roomID]
	if !ok {
		return false
	}
	item.State = state
	m.rooms[roomID] = item
	return true
}

// Close（关闭房间）从活动房间目录移除房间。
// 对局结算或超时解散后调用；历史记录由独立对局/回放存储负责。
func (m *Manager) Close(roomID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.rooms[roomID]; !ok {
		return false
	}
	delete(m.rooms, roomID)
	return true
}
