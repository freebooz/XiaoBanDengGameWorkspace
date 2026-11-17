package httpapi

import (
	"cmp"
	"slices"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/chinesechess"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
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
	RoomID           string              `json:"room_id"`
	RoomGeneration   string              `json:"room_generation"`
	GameID           string              `json:"game_id"`
	ProductID        string              `json:"product_id"`
	RuleSetID        string              `json:"rule_set_id"`
	RuleVersion      string              `json:"rule_version"`
	Kind             string              `json:"kind"`
	Status           string              `json:"status"`
	Phase            string              `json:"phase"`
	Capacity         int                 `json:"capacity"`
	Players          int                 `json:"players"`
	ConnectedPlayers int                 `json:"connected_players"`
	ReadyPlayers     int                 `json:"ready_players"`
	CompletedRounds  int                 `json:"completed_rounds"`
	UpdatedAt        time.Time           `json:"updated_at"`
	Mahjong          *monitorMahjongRoom `json:"mahjong,omitempty"`
}

type monitorPlayer struct {
	AccountID      string `json:"account_id"`
	DisplayName    string `json:"display_name,omitempty"`
	GameID         string `json:"game_id"`
	RoomID         string `json:"room_id,omitempty"`
	RoomGeneration string `json:"room_generation,omitempty"`
	RoomStatus     string `json:"room_status,omitempty"`
	Status         string `json:"status"`
	Seat           *int   `json:"seat,omitempty"`
	Connected      bool   `json:"connected"`
}

type monitorMahjongRoom struct {
	RoundNumber       int                    `json:"round_number"`
	RoundLimit        int                    `json:"round_limit"`
	AdmissionPaused   bool                   `json:"admission_paused"`
	AdmissionRevision int64                  `json:"admission_revision"`
	CanSetAdmission   bool                   `json:"can_set_admission"`
	SpectatorCount    int                    `json:"spectator_count"`
	MatchID           string                 `json:"match_id,omitempty"`
	Dealer            *int                   `json:"dealer,omitempty"`
	Turn              *int                   `json:"turn,omitempty"`
	RemainingTiles    *int                   `json:"remaining_tiles,omitempty"`
	ActionDeadlineMS  int64                  `json:"action_deadline_ms,omitempty"`
	LastDiscard       *monitorMahjongDiscard `json:"last_discard,omitempty"`
}

type monitorMahjongDiscard struct {
	Seat int    `json:"seat"`
	Suit string `json:"suit"`
	Rank int    `json:"rank"`
}

// Each game projects only allowlisted metadata. Player-specific snapshots
// include hands, legal actions and private state and are never used here.
type monitorBoard struct {
	status    string
	phase     string
	connected map[string]string // Account ID to display name, optionally empty.
	names     map[string]string // Last known seat name, including offline seats.
	touchedAt time.Time
	mahjong   monitorMahjongRoom
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
	lobby, waitingDisconnects := s.mahjong.monitorLobby()
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
		isMahjong := item.GameID == string(domain.GameMahjong)
		if isMahjong {
			detail := board.mahjong
			if detail.RoundNumber == 0 {
				detail.RoundNumber = state.CompletedRounds + 1
			}
			detail.RoundLimit = state.RoundLimit
			detail.AdmissionPaused = state.AdmissionPaused
			detail.AdmissionRevision = state.AdmissionRevision
			detail.CanSetAdmission = state.Kind == matchmaking.MahjongFriend && state.Room.State == "waiting" &&
				room.Players < room.Capacity && s.db != nil && s.mahjong.friendStore != nil && !s.mahjong.stopping.Load()
			detail.SpectatorCount = s.mahjong.spectators.activeCount(item.RoomID, item.CreatedAt)
			room.Mahjong = &detail
		}
		for seat, account := range state.Accounts {
			if account == "" || (state.Kind == matchmaking.MahjongTraining && seat > 0) {
				continue
			}
			name, connected := board.connected[account]
			if name == "" {
				name = board.names[account]
			}
			if isMahjong && room.Status != "playing" {
				if lobbyName, present := lobby[account]; present {
					connected = true
					name = lobbyName
				}
			}
			if connected {
				room.ConnectedPlayers++
			}
			status := monitorPlayerStatus(room.Status, connected, state.ReadyAccounts[account])
			if disconnected, tracked := waitingDisconnects[account]; isMahjong && !connected && tracked &&
				room.Status != "playing" && room.Status != "finished" && disconnected.RoomID == item.RoomID &&
				disconnected.Room.CreatedAt.Equal(item.CreatedAt) && disconnected.CompletedRounds == state.CompletedRounds {
				status = "reconnecting"
			}
			players[playerKey{item.GameID, account}] = monitorPlayer{
				AccountID: account, DisplayName: name, GameID: item.GameID, RoomID: item.RoomID,
				RoomGeneration: room.RoomGeneration, RoomStatus: room.Status, Status: status, Seat: &seat, Connected: connected,
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
			if player.Status == "waiting" || player.Status == "ready" {
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
		RoomGeneration: item.CreatedAt.UTC().Format(time.RFC3339Nano),
		Kind:           state.Kind, Status: item.State, Capacity: state.Capacity, Players: len(state.Accounts), ReadyPlayers: state.ReadyPlayers,
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

func monitorPlayerStatus(roomStatus string, connected, ready bool) string {
	switch roomStatus {
	case "playing":
		if !connected {
			return "reconnecting"
		}
		return "playing"
	case "finished":
		return "settled"
	default:
		if ready {
			return "ready"
		}
		return "waiting"
	}
}

func (h *mahjongHub) monitorLobby() (map[string]string, map[string]matchmaking.MahjongAssignment) {
	h.lobbyMu.Lock()
	defer h.lobbyMu.Unlock()
	present := make(map[string]string, len(h.lobbyClients))
	for client, sub := range h.lobbyClients {
		present[sub.accountID] = client.displayName
	}
	disconnected := make(map[string]matchmaking.MahjongAssignment, len(h.waitingDisconnects))
	for account, entry := range h.waitingDisconnects {
		disconnected[account] = entry.assignment
	}
	return present, disconnected
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
	view.mahjong.RoundNumber = board.completedRounds + 1
	view.mahjong.MatchID = board.matchID
	if board.persistPending {
		view.phase = "saving"
	}
	if board.started {
		dealer, remaining := board.game.Dealer, board.game.Remaining()
		view.mahjong.Dealer = &dealer
		view.mahjong.RemainingTiles = &remaining
		if !board.closed && board.game.Phase != guiyang.PhaseFinished {
			turn := board.game.Turn
			view.mahjong.Turn = &turn
			if !board.persistPending && board.decisionID != "" {
				view.mahjong.ActionDeadlineMS = board.actionDeadline().UnixMilli()
			}
		}
		if discards := board.game.Discards; len(discards) > 0 {
			latest := discards[len(discards)-1]
			view.mahjong.LastDiscard = &monitorMahjongDiscard{Seat: latest.Seat, Suit: latest.Tile.Suit, Rank: latest.Tile.Rank}
		}
	}
	view.names = make(map[string]string, len(board.game.Players))
	for seat, profile := range board.seatProfiles {
		if profile.known && profile.DisplayName != "" {
			view.names[board.game.Players[seat]] = profile.DisplayName
		}
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
