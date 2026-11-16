package httpapi

import (
	"cmp"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/chinesechess"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
)

type monitorSnapshot struct {
	GeneratedAt time.Time         `json:"generated_at"`
	Services    [3]monitorService `json:"services"`
	Lobbies     []monitorLobby    `json:"lobbies"`
	Rooms       []monitorRoom     `json:"rooms"`
	Players     []monitorPlayer   `json:"players"`
}

type monitorLobby struct {
	GameID          string `json:"game_id"`
	ProductID       string `json:"product_id"`
	PresenceTracked bool   `json:"presence_tracked"`
	OnlinePlayers   int    `json:"online_players"`
	WaitingPlayers  int    `json:"waiting_players"`
	Rooms           int    `json:"rooms"`
}

type monitorRoom struct {
	RoomID           string    `json:"room_id"`
	GameID           string    `json:"game_id"`
	ProductID        string    `json:"product_id"`
	RuleSetID        string    `json:"rule_set_id"`
	RuleVersion      string    `json:"rule_version"`
	Kind             string    `json:"kind"`
	Status           string    `json:"status"`
	Phase            string    `json:"phase"`
	Capacity         int       `json:"capacity"`
	Players          int       `json:"players"`
	ConnectedPlayers int       `json:"connected_players"`
	ReadyPlayers     int       `json:"ready_players"`
	CompletedRounds  int       `json:"completed_rounds"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type monitorPlayer struct {
	AccountID   string `json:"account_id"`
	DisplayName string `json:"display_name,omitempty"`
	GameID      string `json:"game_id"`
	RoomID      string `json:"room_id,omitempty"`
	RoomStatus  string `json:"room_status,omitempty"`
	Status      string `json:"status"`
	Seat        *int   `json:"seat,omitempty"`
	Connected   bool   `json:"connected"`
}

// These projections contain connectivity and stage only. They never use the
// gameplay snapshot, which carries cards, options and other private state.
type monitorBoard struct {
	status    string
	phase     string
	connected map[string]string // Account ID to display name, optionally empty.
	touchedAt time.Time
}

func (s *Server) monitorSnapshot(services [3]monitorService) monitorSnapshot {
	snap := monitorSnapshot{
		GeneratedAt: time.Now().UTC(), Services: services,
		Lobbies: []monitorLobby{}, Rooms: []monitorRoom{}, Players: []monitorPlayer{},
	}
	lobbyIndex := map[string]int{}
	for _, descriptor := range game.Catalog() {
		id := string(descriptor.GameID)
		if _, seen := lobbyIndex[id]; seen {
			continue
		}
		lobbyIndex[id] = len(snap.Lobbies)
		snap.Lobbies = append(snap.Lobbies, monitorLobby{
			GameID: id, ProductID: string(descriptor.ProductID), PresenceTracked: id == string(domain.GameMahjong),
		})
	}
	type playerKey struct{ gameID, accountID string }
	players := map[playerKey]monitorPlayer{}
	lobby := s.mahjong.monitorLobby()
	managed := s.matchmaking.RoomMonitorStates()
	for id, state := range s.mahjong.matches.RoomMonitorStates() {
		managed[id] = state
	}
	for _, item := range s.rooms.List() {
		if item.State == "closed" {
			continue
		}
		state := managed[item.RoomID]
		if !state.Room.CreatedAt.Equal(item.CreatedAt) {
			state = matchmaking.RoomMonitorState{Room: item}
		}
		board := s.monitorRoomBoard(item, state)
		room := projectMonitorRoom(item, state, board)
		for seat, account := range state.Accounts {
			if account == "" || (state.Kind == matchmaking.MahjongTraining && seat > 0) {
				continue
			}
			name, connected := board.connected[account]
			if item.GameID == string(domain.GameMahjong) && room.Status != "playing" {
				if lobbyName, present := lobby[account]; present {
					connected = true
					name = lobbyName
				}
			}
			if connected {
				room.ConnectedPlayers++
			}
			players[playerKey{item.GameID, account}] = monitorPlayer{
				AccountID: account, DisplayName: name, GameID: item.GameID, RoomID: item.RoomID,
				RoomStatus: room.Status, Status: monitorPlayerStatus(room.Status, connected), Seat: &seat, Connected: connected,
			}
		}
		snap.Rooms = append(snap.Rooms, room)
		if index, found := lobbyIndex[item.GameID]; found {
			snap.Lobbies[index].Rooms++
		}
	}
	for account, name := range lobby {
		id := string(domain.GameMahjong)
		key := playerKey{id, account}
		if _, exists := players[key]; !exists {
			players[key] = monitorPlayer{AccountID: account, DisplayName: name, GameID: id, Status: "lobby", Connected: true}
		}
	}
	for _, player := range players {
		if index, found := lobbyIndex[player.GameID]; found {
			if player.Connected {
				snap.Lobbies[index].OnlinePlayers++
			}
			if player.Status == "waiting" {
				snap.Lobbies[index].WaitingPlayers++
			}
		}
		snap.Players = append(snap.Players, player)
	}
	slices.SortFunc(snap.Players, func(a, b monitorPlayer) int {
		return cmp.Or(cmp.Compare(a.GameID, b.GameID), cmp.Compare(a.RoomID, b.RoomID), cmp.Compare(a.AccountID, b.AccountID))
	})
	return snap
}

func projectMonitorRoom(item room.Room, state matchmaking.RoomMonitorState, board monitorBoard) monitorRoom {
	view := monitorRoom{
		RoomID: item.RoomID, GameID: item.GameID, ProductID: item.ProductID, RuleSetID: item.RuleSetID, RuleVersion: item.RuleVersion,
		Kind: state.Kind, Status: item.State, Capacity: state.Capacity, Players: len(state.Accounts), ReadyPlayers: state.ReadyPlayers,
		CompletedRounds: state.CompletedRounds, UpdatedAt: item.CreatedAt,
	}
	if view.Kind == "" {
		view.Kind = matchmaking.MahjongQuick
	}
	if board.status != "" {
		view.Status, view.Phase = board.status, board.phase
		if !board.touchedAt.IsZero() {
			view.UpdatedAt = board.touchedAt
		}
	} else if item.State == "playing" {
		view.Status, view.Phase = "waiting", "entering"
	}
	return view
}

func monitorPlayerStatus(roomStatus string, connected bool) string {
	switch roomStatus {
	case "playing":
		if !connected {
			return "reconnecting"
		}
		return "playing"
	case "finished":
		return "settled"
	default:
		return "waiting"
	}
}

func (h *mahjongHub) monitorLobby() map[string]string {
	h.lobbyMu.Lock()
	defer h.lobbyMu.Unlock()
	present := make(map[string]string, len(h.lobbyClients))
	for client, sub := range h.lobbyClients {
		present[sub.accountID] = client.displayName
	}
	return present
}

func (s *Server) monitorRoomBoard(item room.Room, state matchmaking.RoomMonitorState) monitorBoard {
	switch item.GameID {
	case string(domain.GameMahjong):
		return s.mahjong.monitorBoard(item, state.CompletedRounds)
	case string(domain.GameChineseChess):
		return s.chess.monitorBoard(item, state.Accounts)
	case string(domain.GameLandlord):
		return s.landlord.monitorBoard(item, state.Accounts)
	case string(domain.GameGuandan):
		return s.guandan.monitorBoard(item, state.Accounts)
	default:
		return monitorBoard{}
	}
}

func (h *mahjongHub) monitorBoard(item room.Room, completedRounds int) monitorBoard {
	h.mu.Lock()
	board := h.rooms[item.RoomID]
	h.mu.Unlock()
	if board == nil {
		return monitorBoard{}
	}
	board.mu.Lock()
	defer board.mu.Unlock()
	if !board.createdAt.Equal(item.CreatedAt) || (board.completedRounds != completedRounds && (!board.retained || item.State == "playing")) {
		return monitorBoard{}
	}
	// A retained room goes back to the waiting lobby after the last client
	// closes its settlement. Its old board is still kept for recovery.
	if board.closed && (!board.retained || len(board.clients) == 0) {
		return monitorBoard{}
	}
	view := activeMonitorBoard(board.started, board.closed, board.game.Phase, board.lastActionAt)
	if board.persistPending {
		view.phase = "saving"
	}
	for client := range board.clients {
		if client.seat >= 0 && client.seat < len(board.game.Players) && board.game.Players[client.seat] == client.accountID {
			view.connected[client.accountID] = client.displayName
		}
	}
	return view
}

func (h *chessHub) monitorBoard(item room.Room, accounts []string) monitorBoard {
	if len(accounts) == 0 {
		return monitorBoard{}
	}
	board := h.findRoom(item.RoomID)
	if board == nil {
		return monitorBoard{}
	}
	board.mu.Lock()
	defer board.mu.Unlock()
	if board.turnStartedAt.Before(item.CreatedAt) && len(board.clients) == 0 {
		return monitorBoard{}
	}
	view := activeMonitorBoard(!board.matchStartedAt.IsZero(), board.dissolved, "turn", board.turnStartedAt)
	for client := range board.clients {
		if (client.color == chinesechess.Red || client.color == chinesechess.Black) && slices.Contains(accounts, client.clientID) {
			view.connected[client.clientID] = ""
		}
	}
	return view
}

func (h *landlordHub) monitorBoard(item room.Room, accounts []string) monitorBoard {
	h.mu.Lock()
	board := h.rooms[item.RoomID]
	h.mu.Unlock()
	if board == nil {
		return monitorBoard{}
	}
	board.mu.Lock()
	defer board.mu.Unlock()
	if !slices.Equal(board.game.Players[:], accounts) {
		return monitorBoard{}
	}
	view := activeMonitorBoard(board.started, board.closed, board.game.Phase, board.lastActionAt)
	for client := range board.clients {
		view.connected[client.accountID] = ""
	}
	return view
}

func (h *guandanHub) monitorBoard(item room.Room, accounts []string) monitorBoard {
	h.mu.Lock()
	board := h.rooms[item.RoomID]
	h.mu.Unlock()
	if board == nil {
		return monitorBoard{}
	}
	board.mu.Lock()
	defer board.mu.Unlock()
	if !slices.Equal(board.game.Players[:], accounts) {
		return monitorBoard{}
	}
	view := activeMonitorBoard(board.started, board.closed, board.game.Phase, board.lastActionAt)
	for client := range board.clients {
		if client.seat >= 0 && client.seat < len(accounts) {
			view.connected[accounts[client.seat]] = ""
		}
	}
	return view
}

func activeMonitorBoard(started, closed bool, phase string, touchedAt time.Time) monitorBoard {
	view := monitorBoard{status: "playing", phase: phase, touchedAt: touchedAt, connected: map[string]string{}}
	if closed || phase == "finished" {
		view.status, view.phase = "finished", "finished"
	} else if !started {
		view.status, view.phase = "waiting", "entering"
	}
	return view
}
