package httpapi

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/chinesechess"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchrecord"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

type fakeMatchStore struct {
	mu        sync.Mutex
	matches   []matchrecord.Match
	changes   []matchrecord.Change
	createErr error
	appendErr error
}

func (s *fakeMatchStore) CreateMatch(_ context.Context, match matchrecord.Match) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.createErr != nil {
		return s.createErr
	}
	s.matches = append(s.matches, match)
	return nil
}
func (s *fakeMatchStore) AppendChange(_ context.Context, change matchrecord.Change) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.appendErr != nil {
		return s.appendErr
	}
	s.changes = append(s.changes, change)
	return nil
}

func (s *fakeMatchStore) matchCount() int  { s.mu.Lock(); defer s.mu.Unlock(); return len(s.matches) }
func (s *fakeMatchStore) changeCount() int { s.mu.Lock(); defer s.mu.Unlock(); return len(s.changes) }
func (s *fakeMatchStore) match(index int) matchrecord.Match {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.matches[index]
}
func (s *fakeMatchStore) change(index int) matchrecord.Change {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.changes[index]
}
func (s *fakeMatchStore) allChanges() []matchrecord.Change {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]matchrecord.Change{}, s.changes...)
}

func configuredChessRoom(t *testing.T) (*chessHub, string, *room.Manager, room.Room, *fakeMatchStore) {
	t.Helper()
	hub, url := newTestChessHub(t)
	directory := room.NewManager()
	item, err := directory.Create(room.CreateRequest{ProductID: "custom_chess_product", GameID: "chinese_chess", RuleSetID: "standard", RuleVersion: "1.0.0"})
	if err != nil {
		t.Fatal(err)
	}
	store := &fakeMatchStore{}
	hub.ConfigureRecords(store, directory)
	return hub, url, directory, item, store
}

// 已创建HTTP目录的元数据必须透传，双方就绪才创建对局与初始快照。
func TestChessHubPersistsReadyMatchAndLegalMoves(t *testing.T) {
	_, url, directory, item, store := configuredChessRoom(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, item.RoomID, "untrusted-red")
	if store.matchCount() != 0 {
		t.Fatal("单方就绪不应创建对局")
	}
	black := dialTestWebSocket(t, url)
	defer black.Close()
	state := joinTestChessRoom(t, black, item.RoomID, "untrusted-black")
	_ = readUntilType(t, red, "chess_state", nil)
	if store.matchCount() != 1 || state["match_id"] == "" {
		t.Fatal("双方就绪必须创建真实match_id")
	}
	created := store.match(0)
	if created.RoomID != item.RoomID || created.ProductID != "custom_chess_product" || len(created.Players) != 2 || len(created.Snapshot) == 0 {
		t.Fatalf("初始对局元数据错误: %+v", created)
	}
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_state", nil)
	_ = readUntilType(t, black, "chess_state", nil)
	if store.changeCount() != 1 || store.change(0).Sequence != 1 || store.change(0).Status != "playing" {
		t.Fatalf("合法走子未记录: %+v", store.allChanges())
	}
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_error", nil)
	if store.changeCount() != 1 {
		t.Fatal("非法走子不能落库")
	}
	live, _ := directory.Get(item.RoomID)
	if live.State != "playing" || live.ConnectedCount != 2 || live.MatchID != created.MatchID {
		t.Fatalf("实时目录未同步: %+v", live)
	}
}

// 数据库失败必须撤回棋盘变化且停止房间，不能给对手广播假成功。
func TestChessHubPersistenceFailureRestoresBoardAndStopsMatch(t *testing.T) {
	hub, url, directory, item, store := configuredChessRoom(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	black := dialTestWebSocket(t, url)
	defer black.Close()
	joinTestChessRoom(t, red, item.RoomID, "red")
	joinTestChessRoom(t, black, item.RoomID, "black")
	_ = readUntilType(t, red, "chess_state", nil)
	store.mu.Lock()
	store.appendErr = errors.New("disk unavailable")
	store.mu.Unlock()
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_error", nil)
	runtime := hub.findRoom(item.RoomID)
	runtime.mu.Lock()
	position := runtime.board.Pieces["red_soldier_0"].Pos
	turn := runtime.board.Turn
	runtime.mu.Unlock()
	if position.Y != 6 || turn != "red" || store.changeCount() != 0 {
		t.Fatal("失败事务不能推进棋盘或记录")
	}
	live, _ := directory.Get(item.RoomID)
	if live.State != "unavailable" {
		t.Fatalf("存储失败后必须停止对局: %+v", live)
	}
	_ = black.SetReadDeadline(time.Now().Add(80 * time.Millisecond))
	var message map[string]any
	if err := black.ReadJSON(&message); err == nil && message["type"] == "chess_state" {
		t.Fatal("数据库失败不能广播走子成功")
	}
	store.mu.Lock()
	store.appendErr = nil
	store.mu.Unlock()
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_error", nil)
	if store.changeCount() != 0 {
		t.Fatal("异常房间不能静默恢复并继续写入")
	}
}

func TestChessHubDisconnectAbortsAndReplacementCreatesNewMatch(t *testing.T) {
	_, url, directory, item, store := configuredChessRoom(t)
	red := dialTestWebSocket(t, url)
	black := dialTestWebSocket(t, url)
	defer black.Close()
	joinTestChessRoom(t, red, item.RoomID, "red")
	joinTestChessRoom(t, black, item.RoomID, "black")
	_ = readUntilType(t, red, "chess_state", nil)
	firstID := store.match(0).MatchID
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_state", nil)
	_ = readUntilType(t, black, "chess_state", nil)
	_ = red.Close()
	_ = readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "waiting" })
	if store.changeCount() != 2 || store.change(1).Status != "aborted" || store.change(1).ResultReason != "player_disconnected" {
		t.Fatalf("断线必须中止历史对局: %+v", store.allChanges())
	}
	live, _ := directory.Get(item.RoomID)
	if live.ConnectedCount != 1 {
		t.Fatalf("断线人数错误: %+v", live)
	}
	for _, player := range live.Players {
		if player.ClientID == "red" && player.Connected {
			t.Fatal("离线玩家仍标记在线")
		}
	}
	replacement := dialTestWebSocket(t, url)
	defer replacement.Close()
	state := joinTestChessRoom(t, replacement, item.RoomID, "replacement")
	if store.matchCount() != 2 || store.match(1).MatchID == firstID {
		t.Fatal("替补就绪必须保留旧记录并创建新对局")
	}
	assertPiecePosition(t, state, "red_soldier_0", 0, 6)
}

func TestChessHubRejectsUnknownAndNonChessRooms(t *testing.T) {
	hub, url, directory, _, _ := configuredChessRoom(t)
	client := dialTestWebSocket(t, url)
	defer client.Close()
	mustWriteJSON(t, client, map[string]any{"type": "chess_join", "room_id": "unknown", "client_id": "guest"})
	_ = readUntilType(t, client, "chess_error", nil)
	mahjong, err := directory.Create(room.CreateRequest{ProductID: "xbd_mahjong", GameID: "mahjong", RuleSetID: "guiyang", RuleVersion: "1.0.0"})
	if err != nil {
		t.Fatal(err)
	}
	mustWriteJSON(t, client, map[string]any{"type": "chess_join", "room_id": mahjong.RoomID, "client_id": "guest"})
	_ = readUntilType(t, client, "chess_error", nil)
	if hub.findRoom(mahjong.RoomID) != nil {
		t.Fatal("非象棋目录房间不能创建象棋棋盘")
	}
	hub.ConfigureDevelopmentRooms(true)
	joinTestChessRoom(t, client, "dev-room", "guest")
	development, ok := directory.Get("dev-room")
	if !ok || development.Source != "development" {
		t.Fatalf("显式开发房间必须进入同一目录: %+v", development)
	}
}

func TestChessHubCreateFailureDoesNotConfirmSecondSeat(t *testing.T) {
	_, url, directory, item, store := configuredChessRoom(t)
	red := dialTestWebSocket(t, url)
	defer red.Close()
	joinTestChessRoom(t, red, item.RoomID, "red")
	store.mu.Lock()
	store.createErr = errors.New("cannot create match")
	store.mu.Unlock()
	black := dialTestWebSocket(t, url)
	defer black.Close()
	mustWriteJSON(t, black, map[string]any{"type": "chess_join", "room_id": item.RoomID, "client_id": "black"})
	_ = readUntilType(t, black, "chess_error", nil)
	if store.matchCount() != 0 {
		t.Fatal("失败创建不能产生已确认对局")
	}
	live, _ := directory.Get(item.RoomID)
	if live.State != "unavailable" || live.ConnectedCount != 1 || live.MatchID != "" {
		t.Fatalf("创建失败不能公布playing状态或假席位: %+v", live)
	}
	moveTestRedSoldier(t, red)
	_ = readUntilType(t, red, "chess_error", nil)
}

// 同时验证终局结果落库与吃子后失败的深拷贝恢复，避免死亡棋子被错误保留。
func TestChessHubGeneralCapturePersistsWinnerOrRestoresCapture(t *testing.T) {
	for _, failure := range []bool{false, true} {
		name := "finished"
		if failure {
			name = "rollback"
		}
		t.Run(name, func(t *testing.T) {
			hub, url, _, item, store := configuredChessRoom(t)
			red := dialTestWebSocket(t, url)
			defer red.Close()
			black := dialTestWebSocket(t, url)
			defer black.Close()
			joinTestChessRoom(t, red, item.RoomID, "red")
			joinTestChessRoom(t, black, item.RoomID, "black")
			_ = readUntilType(t, red, "chess_state", nil)
			runtime := hub.findRoom(item.RoomID)
			runtime.mu.Lock()
			runtime.board.Pieces["red_back_0"].Pos = chinesechess.Position{X: 4, Y: 1}
			runtime.mu.Unlock()
			if failure {
				store.mu.Lock()
				store.appendErr = errors.New("snapshot unavailable")
				store.mu.Unlock()
			}
			mustWriteJSON(t, red, map[string]any{"type": "chess_move", "piece_id": "red_back_0", "from": map[string]any{"x": 4, "y": 1}, "to": map[string]any{"x": 4, "y": 0}})
			if failure {
				_ = readUntilType(t, red, "chess_error", nil)
				runtime.mu.Lock()
				alive, position, winner := runtime.board.Pieces["black_back_4"].Alive, runtime.board.Pieces["red_back_0"].Pos, runtime.winner
				runtime.mu.Unlock()
				if !alive || position.Y != 1 || winner != "" || store.changeCount() != 0 {
					t.Fatal("失败提交必须恢复被吃的将与胜负状态")
				}
				return
			}
			state := readUntilType(t, red, "chess_state", nil)
			_ = readUntilType(t, black, "chess_state", nil)
			change := store.change(0)
			if state["status"] != "finished" || state["winner"] != "red" || change.Status != "finished" || change.Winner != "red" || change.ResultReason != "general_captured" {
				t.Fatalf("将被吃必须记录终局: state=%v change=%+v", state, change)
			}
		})
	}
}

func TestChessHubAbortFailureStillUpdatesConnectionAndStopsRoom(t *testing.T) {
	_, url, directory, item, store := configuredChessRoom(t)
	red := dialTestWebSocket(t, url)
	black := dialTestWebSocket(t, url)
	defer black.Close()
	joinTestChessRoom(t, red, item.RoomID, "red")
	joinTestChessRoom(t, black, item.RoomID, "black")
	_ = readUntilType(t, red, "chess_state", nil)
	store.mu.Lock()
	store.appendErr = errors.New("abort cannot commit")
	store.mu.Unlock()
	_ = red.Close()
	_ = readUntilType(t, black, "chess_state", func(m map[string]any) bool { return m["status"] == "unavailable" })
	live, _ := directory.Get(item.RoomID)
	if live.ConnectedCount != 1 || live.State != "unavailable" || store.changeCount() != 0 {
		t.Fatalf("中止失败必须停房并保留真实连接事实: %+v", live)
	}
	for _, player := range live.Players {
		if player.ClientID == "red" && player.Connected {
			t.Fatal("中止失败不能让离线玩家仍在线")
		}
	}
}
