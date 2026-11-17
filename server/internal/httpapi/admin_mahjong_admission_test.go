package httpapi

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

const adminMahjongAdmissionPath = "/api/v1/admin/mahjong/rooms/4819/admission"
const adminMahjongOperationsPath = "/api/v1/admin/mahjong/rooms/4819/operations"

func TestAdminMahjongAdmissionRequiresRoomWriteCapability(t *testing.T) {
	reader, readPrincipal := eggWalletToken(t, "reader", adminPlatformRead)
	operator, writePrincipal := eggWalletToken(t, "operator", "mahjong:manage_rooms")
	s := buildServer(config.Config{}, nil, nil, account.NewService(nil))
	s.adminPrincipals = []adminPrincipal{readPrincipal, writePrincipal}
	handler := s.routes()

	generation := "2026-11-17T01:20:03.123456789Z"
	payload := map[string]any{
		"room_generation": generation, "expected_revision": 0, "paused": true,
		"reason": "处理房间举报", "request_id": "afcb75f7-2a01-4ef2-aa48-7a989793f09c",
	}
	for _, test := range []struct {
		name, method, route, token string
		want                       int
	}{
		{"unauthenticated", http.MethodPost, adminMahjongAdmissionPath, "", http.StatusUnauthorized},
		{"read only", http.MethodPost, adminMahjongAdmissionPath, reader, http.StatusForbidden},
		{"unavailable writer", http.MethodPost, adminMahjongAdmissionPath, operator, http.StatusServiceUnavailable},
		{"unavailable history", http.MethodGet, adminMahjongOperationsPath + "?room_generation=" + generation, reader, http.StatusServiceUnavailable},
		{"history needs platform read", http.MethodGet, adminMahjongOperationsPath + "?room_generation=" + generation, operator, http.StatusForbidden},
	} {
		t.Run(test.name, func(t *testing.T) {
			reply := eggWalletRequest(handler, test.method, test.route, test.token, payload)
			if reply.Code != test.want {
				t.Fatalf("got %d, want %d", reply.Code, test.want)
			}
		})
	}
}

func TestAdminMahjongAdmissionValidatesRequiredPayload(t *testing.T) {
	token, principal := eggWalletToken(t, "operator", "mahjong:manage_rooms")
	s := buildServer(config.Config{}, nil, nil, account.NewService(nil))
	s.adminPrincipals = []adminPrincipal{principal}
	handler := s.routes()
	for _, test := range []struct {
		name, field string
		value       any
	}{
		{"missing paused", "paused", nil},
		{"missing revision", "expected_revision", nil},
		{"negative revision", "expected_revision", -1},
		{"fractional revision", "expected_revision", 1.5},
		{"wrong generation zone", "room_generation", "2026-11-17T02:20:03+01:00"},
		{"wrong generation precision", "room_generation", "2026-11-17T01:20:03.1234567890Z"},
		{"blank reason", "reason", "  \t"},
		{"long reason", "reason", strings.Repeat("房", 161)},
		{"embedded null in reason", "reason", "房\x00"},
		{"invalid request UUID", "request_id", "invalid"},
		{"unknown field", "seat", 1},
	} {
		t.Run(test.name, func(t *testing.T) {
			payload := map[string]any{
				"room_generation": "2026-11-17T01:20:03.123456789Z", "expected_revision": 0, "paused": false,
				"reason": "处理房间举报", "request_id": "afcb75f7-2a01-4ef2-aa48-7a989793f09c",
			}
			if test.value == nil {
				delete(payload, test.field)
			} else {
				payload[test.field] = test.value
			}
			reply := eggWalletRequest(handler, http.MethodPost, adminMahjongAdmissionPath, token, payload)
			if reply.Code != http.StatusBadRequest {
				t.Fatalf("malformed admission request got %d", reply.Code)
			}
		})
	}
}

type lostMahjongAdmissionReply struct {
	*mahjongrooms.Service
	failNextLookup atomic.Bool
	blockLoad      atomic.Bool
}

var errLostMahjongAdmissionReply = errors.New("injected admission storage connection failure")

func (s *lostMahjongAdmissionReply) CommitAdmission(ctx context.Context, change mahjongrooms.AdmissionChange, snapshot mahjongrooms.Snapshot) (mahjongrooms.AdmissionOperation, error) {
	if operation, err := s.Service.CommitAdmission(ctx, change, snapshot); err != nil {
		return operation, err
	}
	s.failNextLookup.Store(true)
	return mahjongrooms.AdmissionOperation{}, errLostMahjongAdmissionReply
}

func (s *lostMahjongAdmissionReply) FindAdmissionOperation(ctx context.Context, id uuid.UUID) (mahjongrooms.AdmissionOperation, error) {
	if s.failNextLookup.Swap(false) {
		return mahjongrooms.AdmissionOperation{}, errLostMahjongAdmissionReply
	}
	return s.Service.FindAdmissionOperation(ctx, id)
}

func (s *lostMahjongAdmissionReply) Load(ctx context.Context, roomID string) (mahjongrooms.Snapshot, error) {
	if s.blockLoad.Load() {
		return mahjongrooms.Snapshot{}, errLostMahjongAdmissionReply
	}
	return s.Service.Load(ctx, roomID)
}

func TestAdminMahjongAdmissionReconcilesAnUnconfirmedCommit(t *testing.T) {
	ctx, db := admissionTestDatabase(t)
	token, principal := eggWalletToken(t, "operator", adminMahjongManageRooms)
	s := buildServer(config.Config{}, db, nil, account.NewService(db))
	defer s.mahjong.stopping.Store(true)
	store := &lostMahjongAdmissionReply{Service: mahjongrooms.NewService(db)}
	s.mahjong.friendStore = store
	s.adminPrincipals = []adminPrincipal{principal}
	handler := s.routes()
	roomID, err := s.mahjong.applyLobbyCommand(&mahjongClient{lobbyAccount: "admission-host"}, map[string]any{
		"action": "create", "rule_set_id": "guiyang", "rule_version": "2.0.0",
	}, "create-room")
	if err != nil {
		t.Fatal(err)
	}
	cleanAdmissionTestRoom(t, ctx, db, roomID)
	initial := s.mahjong.friendAssignment(roomID)
	wake, subscribed := s.monitor.subscribe()
	if !subscribed {
		t.Fatal("could not subscribe to the monitor signal")
	}
	defer s.monitor.unsubscribe(wake)
	store.blockLoad.Store(true)
	requestID := uuid.New()
	input := map[string]any{
		"room_generation": initial.Room.CreatedAt.Format(time.RFC3339Nano), "expected_revision": 0,
		"paused": true, "reason": "连接恢复检查", "request_id": requestID.String(),
	}
	route := "/api/v1/admin/mahjong/rooms/" + roomID + "/admission"
	for _, attempt := range []string{"lost commit reply", "snapshot temporarily unavailable"} {
		if reply := eggWalletRequest(handler, http.MethodPost, route, token, input); reply.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s: got %d, want 503", attempt, reply.Code)
		}
	}
	if s.mahjong.friendAssignment(roomID).Settings.AdmissionPaused {
		t.Fatal("unconfirmed commit was published")
	}

	store.blockLoad.Store(false)
	select {
	case <-wake:
	case <-time.After(5 * time.Second):
		t.Fatal("confirmed durable admission did not notify the monitor")
	}
	if current := s.mahjong.friendAssignment(roomID); !current.Settings.AdmissionPaused || current.Settings.AdmissionRevision != 1 {
		t.Fatalf("reconciliation did not install the committed state: %+v", current.Settings)
	}
	if reply := eggWalletRequest(handler, http.MethodPost, route, token, input); reply.Code != http.StatusOK {
		t.Fatalf("confirmed retry got %d, want 200", reply.Code)
	}
	select {
	case <-wake:
		t.Fatal("idempotent receipt triggered a second publication")
	default:
	}
	operations, err := store.ListAdmissionOperations(ctx, roomID, initial.Room.CreatedAt)
	if err != nil || len(operations) != 1 || operations[0].RequestID != requestID {
		t.Fatalf("reconciliation rewrote the durable audit: %v, %v", operations, err)
	}
}

func admissionTestDatabase(t *testing.T) (context.Context, *pgxpool.Pool) {
	t.Helper()
	databaseURL := os.Getenv("XBD_MAHJONG_ADMISSION_TEST_POSTGRES_URL")
	if databaseURL == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)
	db, err := postgres.Connect(ctx, databaseURL)
	if err != nil {
		t.Fatal("could not connect to isolated admission database")
	}
	t.Cleanup(db.Close)
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	return ctx, db
}

func cleanAdmissionTestRoom(t *testing.T, ctx context.Context, db *pgxpool.Pool, roomID string) {
	t.Helper()
	t.Cleanup(func() {
		_, _ = db.Exec(ctx, `DELETE FROM mahjong_friend_rooms WHERE room_id=$1`, roomID)
		_, _ = db.Exec(ctx, `DELETE FROM mahjong_room_admission_operations WHERE room_id=$1`, roomID)
	})
}

func TestAdminMahjongAdmissionPublishesToLiveClientsAndProtectsRoomReuse(t *testing.T) {
	ctx, db := admissionTestDatabase(t)
	viewerToken, readerPrincipal := eggWalletToken(t, "reader", adminPlatformRead)
	operatorToken, operatorPrincipal := eggWalletToken(t, "operator", adminMahjongManageRooms)
	accounts := &fixtureAccounts{}
	s := buildServer(config.Config{}, db, nil, accounts)
	s.mahjong.friendStore = mahjongrooms.NewService(db)
	s.adminPrincipals = []adminPrincipal{readerPrincipal, operatorPrincipal}
	runtime := &Runtime{Handler: s.routes(), server: s}
	server := httptest.NewServer(runtime)
	defer server.Close()
	defer runtime.Drain()

	host := lobbySocket(t, server, accounts, "admission-owner")
	peer := lobbySocket(t, server, accounts, "admission-peer")
	player := lobbySocket(t, server, accounts, "admission-new-player")
	room := spectatorCreate(t, host, map[string]any{"allow_spectators": true})
	roomID := room["room_id"].(string)
	cleanAdmissionTestRoom(t, ctx, db, roomID)
	spectatorPermission(t, host, roomID, true, true)
	lobbyCommand(t, peer, "join", roomID, "", "", true)
	lobbyCommand(t, host, "ready", roomID, "", "", true)
	referenceSend(t, player, map[string]any{"type": "mahjong_room_directory", "open": true, "request_id": "admission-directory"})

	streamRequest, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+"/api/v1/admin/monitor/stream", nil)
	if err != nil {
		t.Fatal(err)
	}
	streamRequest.Header.Set("Authorization", "Bearer "+viewerToken)
	stream, err := server.Client().Do(streamRequest)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Body.Close()
	if stream.StatusCode != http.StatusOK {
		t.Fatalf("could not open admin SSE: %d", stream.StatusCode)
	}
	events := bufio.NewReader(stream.Body)
	waitMonitorRoom := func(match func(monitorRoom) bool) monitorRoom {
		t.Helper()
		snapshot := readMonitorTestState(t, events, func(snapshot monitorSnapshot) bool {
			return len(snapshot.Rooms) == 1 && snapshot.Rooms[0].Mahjong != nil && snapshot.Rooms[0].RoomID == roomID && match(snapshot.Rooms[0])
		})
		return snapshot.Rooms[0]
	}
	initial := waitMonitorRoom(func(room monitorRoom) bool { return room.Mahjong.CanSetAdmission && room.ReadyPlayers == 1 })
	if initial.RoomGeneration == "" || initial.Mahjong.AdmissionPaused || initial.Mahjong.AdmissionRevision != 0 {
		t.Fatalf("incorrect initial admission state: %+v", initial)
	}
	route := "/api/v1/admin/mahjong/rooms/" + roomID
	input := func(revision int, paused bool) string {
		t.Helper()
		body, err := json.Marshal(map[string]any{
			"room_generation": initial.RoomGeneration, "expected_revision": revision,
			"paused": paused, "reason": "  核对房间举报  ", "request_id": uuid.NewString(),
		})
		if err != nil {
			t.Fatal(err)
		}
		return string(body)
	}
	post := func(body string, code int) map[string]any {
		t.Helper()
		result := requestMahjongAdminFixture(t, server.URL, http.MethodPost, route+"/admission", operatorToken, body, code)
		if code == http.StatusOK {
			return result["operation"].(map[string]any)
		}
		return nil
	}
	history := func(generation string) []any {
		t.Helper()
		result := requestMahjongAdminFixture(t, server.URL, http.MethodGet, route+"/operations?room_generation="+generation, viewerToken, "", http.StatusOK)
		return result["items"].([]any)
	}
	pauseRequest := input(0, true)
	paused := post(pauseRequest, http.StatusOK)
	if paused["admin_name"] != "operator" || paused["reason"] != "核对房间举报" || paused["paused"] != true ||
		paused["admission_revision"] != float64(1) || paused["room_generation"] != initial.RoomGeneration {
		t.Fatalf("incorrect pause receipt: %v", paused)
	}
	post(input(0, true), http.StatusConflict)
	waitMonitorRoom(func(room monitorRoom) bool {
		return room.Mahjong.AdmissionPaused && room.Mahjong.AdmissionRevision == 1 && room.ReadyPlayers == 1 && room.Players == 2
	})
	lobbyRead(t, host, "mahjong_lobby_state", func(message map[string]any) bool {
		state := message["state"].(map[string]any)
		return state["admission_paused"] == true && state["ready_players"] == float64(1)
	})
	lobbyRead(t, player, "mahjong_lobby_state", func(message map[string]any) bool {
		rooms, _ := message["public_rooms"].([]any)
		for _, value := range rooms {
			room := value.(map[string]any)
			if room["room_id"] == roomID && room["admission_paused"] == true && room["joinable"] == false {
				return true
			}
		}
		return false
	})
	if rejection := spectatorLobbyCommand(t, player, "join", map[string]any{"room_id": roomID}); rejection["ok"] != false || rejection["code"] != "room_admission_paused" {
		t.Fatalf("new player was not rejected with the paused-room code: %v", rejection)
	}
	lobbyCommand(t, peer, "join", roomID, "", "", true)
	lobbyCommand(t, peer, "ready", roomID, "", "", true)
	if state := lobbyState(t, peer, "waiting", 2, 2); state["admission_paused"] != true {
		t.Fatalf("readying an existing seat cleared the pause: %v", state)
	}
	watcher := spectatorSocket(t, server, accounts, "admission-watcher")
	spectatorRequest(t, watcher, roomID, "admission-watcher", 0, "")
	lobbyRead(t, watcher, "mahjong_watch_joined", nil)
	waitMonitorRoom(func(room monitorRoom) bool { return room.Mahjong.AdmissionPaused && room.Mahjong.SpectatorCount == 1 })

	resumed := post(input(1, false), http.StatusOK)
	waitMonitorRoom(func(room monitorRoom) bool {
		return !room.Mahjong.AdmissionPaused && room.Mahjong.AdmissionRevision == 2 && room.ReadyPlayers == 2
	})
	lobbyCommand(t, player, "join", roomID, "", "", true)
	lobbyCommand(t, player, "leave", roomID, "", "", true)
	lobbyCommand(t, peer, "leave", roomID, "", "", true)
	lobbyCommand(t, host, "leave", roomID, "", "", true)
	post(input(2, true), http.StatusNotFound)

	spectatorCreate(t, host, map[string]any{"room_id": roomID})
	replacement := waitMonitorRoom(func(room monitorRoom) bool {
		return room.RoomGeneration != initial.RoomGeneration && room.Mahjong.CanSetAdmission
	})
	post(input(0, true), http.StatusConflict)
	if current := history(replacement.RoomGeneration); len(current) != 0 || replacement.Mahjong.AdmissionRevision != 0 || replacement.Mahjong.AdmissionPaused {
		t.Fatalf("replacement room inherited admission state: %v", current)
	}
	if retry := post(pauseRequest, http.StatusOK); !reflect.DeepEqual(retry, paused) {
		t.Fatalf("stale UUID retry did not read the original receipt: %v", retry)
	}
	if archived := history(initial.RoomGeneration); !reflect.DeepEqual(archived, []any{resumed, paused}) {
		t.Fatalf("wrong old generation history: %v", archived)
	}
}
