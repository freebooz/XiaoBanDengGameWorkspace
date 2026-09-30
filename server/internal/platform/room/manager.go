package room

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"
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
	ProductID   string `json:"product_id"`
	GameID      string `json:"game_id"`
	RuleSetID   string `json:"rule_set_id"`
	RuleVersion string `json:"rule_version"`
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
	item := Room{RoomID: uuid.NewString(), ProductID: req.ProductID, GameID: req.GameID, RuleSetID: req.RuleSetID, RuleVersion: req.RuleVersion, State: "waiting", CreatedAt: time.Now().UTC()}
	m.mu.Lock()
	m.rooms[item.RoomID] = item
	m.mu.Unlock()
	return item, nil
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
