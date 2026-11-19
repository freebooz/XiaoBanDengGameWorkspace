package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
)

func TestMahjongActiveBoardDisconnectReleasesMatchAndNotifiesParticipants(t *testing.T) {
	h := newMahjongHub(matchmaking.NewManager(room.NewManager()))
	exerciseBoardDisconnect(t, h)
}

func TestMahjongActiveBoardDisconnectPostgresRetiresOnlyPrivateMatch(t *testing.T) {
	endpoint := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if endpoint == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, endpoint)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	h := newMahjongHub(matchmaking.NewManager(room.NewManager()))
	h.checkpoints = mahjongactive.NewService(db)
	h.friendStore = mahjongrooms.NewService(db)
	roomID, matchID := exerciseBoardDisconnect(t, h)
	var active, friend, history, transfers, receipts int
	err = db.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM mahjong_active_matches WHERE match_id=$1),
		(SELECT count(*) FROM mahjong_friend_rooms WHERE room_id=$2),
		(SELECT count(*) FROM mahjong_match_results WHERE public_match_id=$1),
		(SELECT count(*) FROM wallet_ledger WHERE reference_id=$1 AND reason='mahjong_settlement_eggs'),
		(SELECT count(*) FROM mahjong_active_completions WHERE match_id=$1)`, matchID, roomID).Scan(&active, &friend, &history, &transfers, &receipts)
	if err != nil {
		t.Fatal(err)
	}
	if active != 0 || friend != 0 || history != 0 || transfers != 0 || receipts != 1 {
		t.Fatalf("after disconnect: active=%d friend=%d history=%d transfers=%d privateReceipts=%d", active, friend, history, transfers, receipts)
	}
}

func exerciseBoardDisconnect(t *testing.T, h *mahjongHub) (string, string) {
	t.Helper()
	accounts := &fixtureAccounts{}
	if h.disconnectGrace != 5*time.Minute {
		t.Fatalf("default board reconnect interval: %s", h.disconnectGrace)
	}
	h.disconnectGrace = 250 * time.Millisecond
	server := httptest.NewServer(http.HandlerFunc((&Server{accounts: accounts, mahjong: h}).mahjongWebSocket))
	t.Cleanup(server.Close)
	var lobbies, boards [4]*websocket.Conn
	var roomID, matchID string
	for seat := range lobbies {
		id := fmt.Sprintf("disconnect-%d", seat)
		lobbies[seat] = lobbySocket(t, server, accounts, id)
		if seat == 0 {
			roomID = spectatorCreate(t, lobbies[seat], map[string]any{"allow_spectators": true})["room_id"].(string)
		} else {
			lobbyCommand(t, lobbies[seat], "join", roomID, "", "", true)
		}
	}
	spectatorPermission(t, lobbies[0], roomID, true, true)
	for _, lobby := range lobbies {
		lobbyCommand(t, lobby, "ready", roomID, "", "", true)
	}
	join := func(seat int) *websocket.Conn {
		socket := spectatorSocket(t, server, accounts, fmt.Sprintf("disconnect-%d", seat))
		message := map[string]any{"type": "mahjong_join", "room_id": roomID}
		if matchID != "" {
			message["match_id"] = matchID
		}
		referenceSend(t, socket, message)
		lobbyRead(t, socket, "mahjong_joined", nil)
		return socket
	}
	for seat := range boards {
		boards[seat] = join(seat)
	}
	state := lobbyRead(t, boards[0], "mahjong_state", func(m map[string]any) bool { return m["status"] == "playing" })
	matchID = state["match_id"].(string)
	watch := spectatorSocket(t, server, accounts, "outside-account")
	spectatorRequest(t, watch, roomID, "outside-account", 0, "")
	lobbyRead(t, watch, "mahjong_watch_joined", nil)
	_ = lobbies[0].Close()
	boards[1] = join(1) // Evicts the previous board without losing presence.
	_ = boards[2].Close()
	lobbyRead(t, boards[0], "mahjong_state", func(m map[string]any) bool { return m["connected_seats"].([]any)[2] == false })
	boards[2] = join(2)
	// A full grace period after the new seat binding keeps the live round.
	time.Sleep(2 * h.disconnectGrace)
	if a, ok := h.matches.MahjongAssignment("disconnect-2"); !ok || !a.Start {
		t.Fatal("a restored board, lobby-only disconnect or replaced socket cancelled the round")
	}
	_ = boards[2].Close()
	_ = boards[3].Close()
	lobbyRead(t, boards[0], "mahjong_state", func(m map[string]any) bool {
		seats := m["connected_seats"].([]any)
		return seats[2] == false && seats[3] == false
	})
	boards[2] = join(2)
	for _, socket := range []*websocket.Conn{boards[0], boards[1], boards[2], lobbies[3]} {
		msg := lobbyRead(t, socket, "mahjong_match_cancelled", nil)
		if msg["room_id"] != roomID || msg["match_id"] != matchID || msg["reason"] != "disconnect_timeout" {
			t.Fatalf("unscoped disconnect notice: %v", msg)
		}
	}
	ended := lobbyRead(t, watch, "mahjong_watch_ended", nil)
	if ended["match_id"] != matchID || ended["reason"] != "disconnect_timeout" {
		t.Fatalf("watcher did not end with the expired round: %v", ended)
	}
	for seat := range boards {
		if _, assigned := h.matches.MahjongAssignment(fmt.Sprintf("disconnect-%d", seat)); assigned {
			t.Fatalf("abandoned match retained seat %d", seat)
		}
	}
	h.mu.Lock()
	held := h.rooms[roomID] != nil || h.entries[roomID] != nil
	h.mu.Unlock()
	if held {
		t.Fatal("abandoned match retained its board or entry timer")
	}
	late := spectatorSocket(t, server, accounts, "disconnect-3")
	referenceSend(t, late, map[string]any{"type": "mahjong_join", "room_id": roomID, "match_id": matchID})
	if msg := lobbyRead(t, late, "mahjong_match_cancelled", nil); msg["match_id"] != matchID {
		t.Fatalf("late reconnect did not receive its scoped cancellation: %v", msg)
	}
	return roomID, matchID
}

type disconnectStore struct {
	mahjongCheckpointStore
	mu              sync.Mutex
	row             mahjongactive.Snapshot
	lostAck         bool
	failPresence    bool
	abandonAttempts chan int
	attempts        int
}

func (s *disconnectStore) List(context.Context) ([]mahjongactive.Snapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return []mahjongactive.Snapshot{s.row}, nil
}

func (s *disconnectStore) SetDisconnectDeadlines(_ context.Context, match, room string, deadlines [4]int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failPresence || match != s.row.MatchID || room != s.row.RoomID {
		return errors.New("board presence unavailable")
	}
	s.row.DisconnectDeadlines = deadlines
	return nil
}

func (s *disconnectStore) Abandon(_ context.Context, match, room string, revision int64, _ func(context.Context, pgx.Tx) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if match != s.row.MatchID || room != s.row.RoomID || revision != s.row.Revision {
		return mahjongactive.ErrConflict
	}
	s.attempts++
	s.abandonAttempts <- s.attempts
	if s.lostAck && s.attempts == 1 {
		return errors.New("connection lost after abandoning game")
	}
	return nil
}

func TestMahjongActiveBoardRestoresDeadlinesAndRetriesDurableRelease(t *testing.T) {
	f := referenceMahjongServer(t, 1, 4)
	r := f.hub.rooms[f.rooms[0]]
	r.mu.Lock()
	game, err := r.game.MarshalCheckpoint()
	if err != nil {
		t.Fatal(err)
	}
	payload, err := json.Marshal(mahjongCheckpoint{Version: 1, Assignment: r.assignment, Game: game, StartedAt: r.startedAt, LastActionAt: r.lastActionAt})
	if err != nil {
		t.Fatal(err)
	}
	originalDeadline := time.Now().Add(-time.Millisecond).UnixMilli()
	row := mahjongactive.Snapshot{MatchID: r.matchID, RoomID: r.id, Revision: 12, Payload: payload, DisconnectDeadlines: [4]int64{0, originalDeadline}}
	r.mu.Unlock()
	store := &disconnectStore{row: row, lostAck: true, abandonAttempts: make(chan int, 5)}
	h := newMahjongHub(matchmaking.NewManager(room.NewManager()))
	h.checkpoints = store
	before := time.Now().Add(h.disconnectGrace).UnixMilli()
	if err := h.restore(context.Background()); err != nil {
		t.Fatal(err)
	}
	after := time.Now().Add(h.disconnectGrace).UnixMilli()
	store.mu.Lock()
	persisted := store.row.DisconnectDeadlines
	store.mu.Unlock()
	if persisted[1] != originalDeadline || persisted[0] < before || persisted[0] > after || persisted[0] != persisted[2] || persisted[0] != persisted[3] {
		t.Fatalf("restart changed a known deadline or failed to persist grace for previously online players: %v", persisted)
	}
	for attempt := 1; attempt <= 2; attempt++ {
		select {
		case got := <-store.abandonAttempts:
			if got != attempt {
				t.Fatalf("unexpected release attempt: %d", got)
			}
		case <-time.After(3 * time.Second):
			t.Fatalf("no durable release attempt %d", attempt)
		}
		h.mu.Lock()
		_, live := h.rooms[r.id]
		_, assigned := h.matches.MahjongAssignment(r.game.Players[0])
		h.mu.Unlock()
		if live != (attempt == 1) || assigned != live {
			t.Fatalf("release attempt %d left room %v, assignment %v", attempt, live, assigned)
		}
	}
}

func TestMahjongDisconnectDeadlineBoundary(t *testing.T) {
	g := guiyang.NewGame([4]string{"a", "b", "c", "d"}, 1)
	r := &mahjongRoom{game: g, started: true}
	now := time.Now().Truncate(time.Millisecond)
	cutoff := now.Add(5 * time.Minute)
	r.disconnectDeadlines = [4]int64{0, cutoff.Add(time.Minute).UnixMilli(), cutoff.UnixMilli()}
	if r.disconnectExpired(cutoff.Add(-time.Nanosecond)) || !r.disconnectExpired(cutoff) {
		t.Fatal("active round must expire exactly at the earliest disconnected seat's deadline")
	}
	r.game.Phase = guiyang.PhaseFinished
	if r.disconnectExpired(cutoff) {
		t.Fatal("completed round was eligible for abandonment")
	}
}

func TestMahjongBoardReleaseUsesCurrentSettingsAfterCheckingRoundIdentity(t *testing.T) {
	f := referenceMahjongServer(t, 1, 4)
	h := f.hub
	h.mu.Lock()
	defer h.mu.Unlock()
	r := h.rooms[f.rooms[0]]
	r.mu.Lock()
	defer r.mu.Unlock()
	// The checkpoint contains the setup image. A non-identity setting may
	// have been canonicalized since that image was taken.
	r.assignment.Settings.AdmissionRevision++
	if err := h.abandonBoardLocked(r); err != nil {
		t.Fatalf("verified active round kept its seats because an old setting differed: %v", err)
	}
	if h.rooms[r.id] != nil {
		t.Fatal("expired board remained in the hub")
	}
}

func TestMahjongBoardDisconnectDuringUnconfirmedInitialDealKeepsOriginalDeadline(t *testing.T) {
	h := newMahjongHub(matchmaking.NewManager(room.NewManager()))
	g := guiyang.NewGame([4]string{"a", "b", "c", "d"}, 1)
	r := &mahjongRoom{id: "room", matchID: "match", game: g, kind: matchmaking.MahjongQuick, persistPending: true}
	r.disconnectSeatLocked(h, 2, 0)
	prior := r.disconnectDeadlines[2]
	if prior == 0 {
		t.Fatal("lost the disconnect that occurred while the opening deal awaited its acknowledgement")
	}
	h.disconnectGrace = time.Second
	r.markAbsentSeats(h, [4]bool{true, true, false, true})
	if r.disconnectDeadlines[2] != prior {
		t.Fatal("first-deal confirmation restarted an existing five-minute grace")
	}
}

func TestMahjongBoardGraceRejectsUnpersistedReconnectAndSkipsTrainingBots(t *testing.T) {
	h := newMahjongHub(matchmaking.NewManager(room.NewManager()))
	g := guiyang.NewGame([4]string{"a", "b", "c", "d"}, 1)
	r := &mahjongRoom{id: "room", matchID: "match", game: g, started: true, kind: matchmaking.MahjongTraining}
	if !r.markAbsentSeats(h, [4]bool{}) || r.disconnectDeadlines[0] <= 0 || r.disconnectDeadlines[1] != 0 || r.disconnectDeadlines[2] != 0 || r.disconnectDeadlines[3] != 0 {
		t.Fatalf("training bots acquired disconnect timers: %v", r.disconnectDeadlines)
	}
	r.kind = matchmaking.MahjongQuick
	r.revision = 7
	r.markAbsentSeats(h, [4]bool{})
	before := r.disconnectDeadlines
	store := &disconnectStore{row: mahjongactive.Snapshot{MatchID: r.matchID, RoomID: r.id, Revision: r.revision, DisconnectDeadlines: before}, failPresence: true}
	h.checkpoints = store
	h.rooms[r.id] = r
	r.mu.Lock()
	defer r.mu.Unlock()
	defer r.closeLocked()
	if err := r.reconnectSeatLocked(h, 0); err == nil || !r.presenceDirty || r.disconnectDeadlines != before {
		t.Fatalf("unconfirmed reconnect erased its deadline: %v (%v)", r.disconnectDeadlines, err)
	}
	store.failPresence = false
	if err := r.reconnectSeatLocked(h, 0); err != nil {
		t.Fatal(err)
	}
	before[0] = 0
	if r.presenceDirty || r.disconnectDeadlines != before || store.row.DisconnectDeadlines != before {
		t.Fatalf("confirmed reconnect altered other seats: %v", r.disconnectDeadlines)
	}
}
