package httpapi

import (
	"bytes"
	"context"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
)

// The supplied local backup script owns the fresh database. This test stops
// only the API it starts. Redis and original PostgreSQL are left running.
func TestMahjongBackupRestorePreservesSessionsHistoryAndActiveTable(t *testing.T) {
	script := os.Getenv("XBD_MAHJONG_TEST_BACKUP_SCRIPT")
	if script == "" {
		t.Skip("set XBD_MAHJONG_TEST_BACKUP_SCRIPT, XBD_MAHJONG_TEST_BACKUP_SOURCE_CONTAINER and disposable restart API/DB endpoints")
	}
	if info, err := os.Stat(script); !filepath.IsAbs(script) || err != nil || !info.Mode().IsRegular() || !strings.EqualFold(filepath.Ext(script), ".ps1") {
		t.Fatal("XBD_MAHJONG_TEST_BACKUP_SCRIPT must be an absolute path to a PowerShell backup test script")
	}
	sourceContainer := os.Getenv("XBD_MAHJONG_TEST_BACKUP_SOURCE_CONTAINER")
	if !backupMachineToken(sourceContainer) {
		t.Fatal("XBD_MAHJONG_TEST_BACKUP_SOURCE_CONTAINER must identify the disposable PostgreSQL container")
	}
	binary := os.Getenv("XBD_MAHJONG_RESTART_API")
	if info, err := os.Stat(binary); !filepath.IsAbs(binary) || err != nil || !info.Mode().IsRegular() {
		t.Fatal("XBD_MAHJONG_RESTART_API must name an absolute path to the compiled cmd/api executable")
	}
	sourceURL, err := url.Parse(os.Getenv("XBD_MAHJONG_TEST_POSTGRES_URL"))
	redis := os.Getenv("XBD_MAHJONG_TEST_REDIS_ADDR")
	if err != nil || (sourceURL.Scheme != "postgres" && sourceURL.Scheme != "postgresql") || !restartLoopback(sourceURL.Host) || sourceURL.RawQuery != "sslmode=disable" || sourceURL.User == nil || !backupMachineToken(sourceURL.User.Username()) || !backupMachineToken(strings.TrimPrefix(sourceURL.Path, "/")) || !restartLoopback(redis) {
		t.Fatal("set disposable loopback PostgreSQL URL (?sslmode=disable) and Redis host:port")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close()
	endpoint := "http://" + addr
	apiEnv := []string{
		"HTTP_ADDR=" + addr, "REDIS_ADDR=" + redis, "REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"),
		"REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
	}
	sourceAPI := launchRestartAPI(t, binary, endpoint, append(apiEnv, "POSTGRES_URL="+sourceURL.String()))
	var guests [4]restartGuest
	var lobby [4]*websocket.Conn
	for seat := range guests {
		guests[seat] = loadRestartGuest(t, endpoint, "")
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guests[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true, "requires_kong_to_claim": true, "rob_kong": true}
	lobbyCommand(t, lobby[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for _, conn := range lobby[1:] {
		lobbyCommand(t, conn, "join", roomID, "", "", true)
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	board, initial, finishedMatch := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	finished, _ := playFriendRestartRound(t, board, initial, roomID, finishedMatch)
	for seat, conn := range lobby {
		state := lobbyState(t, conn, "matched", 4, 0)
		verifyFriendRestartLobby(t, state, guests, roomID, seat, 1, finishedMatch, []any{}, options)
		board[seat].Close()
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	board, initial, activeMatch := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	if activeMatch == finishedMatch {
		t.Fatal("test did not create a separate active match")
	}
	turn := int(initial[0]["turn"].(float64))
	tile := initial[turn]["hand"].([]any)[0].(map[string]any)["id"]
	referenceSend(t, board[turn], restartAction(roomID, activeMatch, "backup-initial-discard", "play", tile))
	waitRestartAction(t, board[turn], "backup-initial-discard")
	for seat, conn := range board {
		initial[seat] = lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return restartHasDiscard(msg, turn, tile) })
	}
	sourceAPI.stop(t)
	source := readMahjongBackupCheckpoint(t, sourceURL.String(), activeMatch)
	restoredURL := restoreMahjongBackupFixture(t, script, sourceContainer, sourceURL)
	restored := readMahjongBackupCheckpoint(t, restoredURL.String(), activeMatch)
	if source.revision != restored.revision || !source.committedAt.Equal(restored.committedAt) || !bytes.Equal(source.payload, restored.payload) {
		t.Fatal("restored database changed the private checkpoint revision, clock stamp or state")
	}
	restoredAPI := launchRestartAPI(t, binary, endpoint, append(apiEnv, "POSTGRES_URL="+restoredURL.String()))
	if restoredAPI.cmd.Process.Pid == sourceAPI.cmd.Process.Pid {
		t.Fatal("restore must use a separate API process")
	}
	var first [4]map[string]any
	for seat, guest := range guests {
		if loadRestartGuest(t, endpoint, guest.Token).ID != guest.ID {
			t.Fatalf("seat %d did not recover its original account session", seat)
		}
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
		state := lobbyState(t, lobby[seat], "playing", 4, 4)
		if state["room_id"] != roomID || state["seat_index"] != float64(seat) || state["completed_rounds"] != float64(1) || state["previous_match_id"] != finishedMatch {
			t.Fatalf("seat %d did not restore the active room and prior round", seat)
		}
		board[seat] = joinRestartBoard(t, endpoint, guest, roomID, activeMatch, seat)
		first[seat] = lobbyRead(t, board[seat], "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "playing" })
		verifyRestartIdentity(t, first[seat], guests, roomID, activeMatch, seat, options)
		if first[seat]["epoch"] == initial[seat]["epoch"] {
			compareRestartTable(t, initial[seat], first[seat], seat)
		} else if first[seat]["epoch"].(float64) <= initial[seat]["epoch"].(float64) || !restartHasDiscard(first[seat], turn, tile) {
			t.Fatalf("seat %d restored incompatible gameplay after a scheduled timeout", seat)
		}
	}
	// A slow backup may legitimately let persisted turn timers advance. Take a
	// fresh, matching epoch from each connection before choosing a legal action.
	latest := synchronizeRestoredBackupBoard(t, board, first, roomID, activeMatch)
	seat, kind, nextTile := chooseFriendRestartAction(latest)
	if seat < 0 {
		t.Fatal("restored active round offers no legal decision")
	}
	referenceSend(t, board[seat], restartAction(roomID, activeMatch, "backup-restored-action", kind, nextTile))
	waitRestartAction(t, board[seat], "backup-restored-action")
	lobbyRead(t, board[seat], "mahjong_state", func(msg map[string]any) bool { return msg["epoch"].(float64) > latest[seat]["epoch"].(float64) })
	verifyRestartedFriendHistory(t, endpoint, guests, finishedMatch, finished[0])
	t.Logf("MAHJONG_BACKUP_API_E2E_OK source_pid=%d restored_pid=%d restored_port=%s room=%s history_match=%s active_match=%s seats=4 checkpoint_exact=true active_action=%s saved_epoch=%.0f restored_epoch=%.0f",
		sourceAPI.cmd.Process.Pid, restoredAPI.cmd.Process.Pid, restoredURL.Port(), roomID, finishedMatch, activeMatch, kind, initial[0]["epoch"], latest[0]["epoch"])
}

func synchronizeRestoredBackupBoard(t *testing.T, board [4]*websocket.Conn, states [4]map[string]any, roomID, matchID string) [4]map[string]any {
	t.Helper()
	for range 3 {
		for seat, conn := range board {
			referenceSend(t, conn, map[string]any{"type": "mahjong_join", "room_id": roomID, "match_id": matchID})
			lobbyRead(t, conn, "mahjong_joined", nil)
			states[seat] = lobbyRead(t, conn, "mahjong_state", nil)
		}
		if states[0]["epoch"] == states[1]["epoch"] && states[0]["epoch"] == states[2]["epoch"] && states[0]["epoch"] == states[3]["epoch"] {
			return states
		}
	}
	t.Fatal("could not obtain matching epochs from the restored board")
	return states
}

type mahjongBackupCheckpoint struct {
	revision    int64
	committedAt time.Time
	payload     []byte
}

func readMahjongBackupCheckpoint(t *testing.T, endpoint, matchID string) mahjongBackupCheckpoint {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, endpoint)
	if err != nil {
		t.Fatal("could not open disposable PostgreSQL to verify active checkpoint")
	}
	defer conn.Close(ctx)
	var result mahjongBackupCheckpoint
	if err := conn.QueryRow(ctx, "SELECT revision,committed_at,payload::text FROM mahjong_active_matches WHERE match_id=$1", matchID).Scan(&result.revision, &result.committedAt, &result.payload); err != nil {
		t.Fatal("could not read the committed active checkpoint from disposable PostgreSQL")
	}
	return result
}

func restoreMahjongBackupFixture(t *testing.T, script, sourceContainer string, sourceURL *url.URL) *url.URL {
	t.Helper()
	pwsh, err := exec.LookPath("pwsh")
	if err != nil {
		t.Fatal("PowerShell 7 is required to run the configured backup script")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, pwsh, "-NoProfile", "-NonInteractive", "-File", script,
		"-SourceContainer", sourceContainer, "-SourceUser", sourceURL.User.Username(), "-SourceDatabase", strings.TrimPrefix(sourceURL.Path, "/"), "-KeepRestored")
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("configured backup script failed: %v", err)
	}
	var port, project string
	for _, line := range strings.Split(string(output), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 || fields[0] != "MAHJONG_BACKUP_RESTORE_OK" {
			continue
		}
		if port != "" {
			t.Fatal("backup script emitted multiple restore markers")
		}
		for _, field := range fields[1:] {
			key, value, _ := strings.Cut(field, "=")
			switch key {
			case "restored_port":
				port = value
			case "project":
				project = value
			}
		}
	}
	number, err := strconv.Atoi(port)
	if !backupMachineToken(project) || project == sourceContainer || !strings.HasPrefix(project, "xbd-mj-restore-") {
		t.Fatal("backup script did not report an owned restore fixture container")
	}
	t.Cleanup(func() {
		stopCtx, stop := context.WithTimeout(context.Background(), 15*time.Second)
		defer stop()
		if err := exec.CommandContext(stopCtx, "docker", "stop", project).Run(); err != nil {
			t.Errorf("stop owned restore fixture: %v", err)
		}
	})
	if err != nil || number < 1 || number > 65535 || strconv.Itoa(number) == sourceURL.Port() {
		t.Fatal("backup script did not report a fresh loopback PostgreSQL port and fixture project")
	}
	restored := *sourceURL
	restored.Host = net.JoinHostPort("127.0.0.1", port)
	t.Logf("MAHJONG_BACKUP_FIXTURE_RESTORED restored_port=%s project=%s", port, project)
	return &restored
}

func backupMachineToken(value string) bool {
	return value != "" && !strings.HasPrefix(value, "-") && !strings.ContainsFunc(value, func(r rune) bool {
		return !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '-' || r == '.')
	})
}
