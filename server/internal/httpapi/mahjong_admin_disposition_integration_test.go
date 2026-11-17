package httpapi

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestMahjongAdminDispositionRealAPI(t *testing.T) {
	if os.Getenv("XBD_MAHJONG_TEST_ADMIN_DISPOSITION") != "1" {
		t.Skip("set XBD_MAHJONG_TEST_ADMIN_DISPOSITION=1 and disposable restart API/DB endpoints")
	}
	binary := os.Getenv("XBD_MAHJONG_RESTART_API")
	if info, err := os.Stat(binary); !filepath.IsAbs(binary) || err != nil || !info.Mode().IsRegular() {
		t.Fatal("XBD_MAHJONG_RESTART_API must name an absolute path to the compiled cmd/api executable")
	}
	postgres, err := url.Parse(os.Getenv("XBD_MAHJONG_TEST_POSTGRES_URL"))
	redis := os.Getenv("XBD_MAHJONG_TEST_REDIS_ADDR")
	if err != nil || (postgres.Scheme != "postgres" && postgres.Scheme != "postgresql") || !restartLoopback(postgres.Host) || postgres.RawQuery != "sslmode=disable" || len(postgres.Path) < 2 || !restartLoopback(redis) {
		t.Fatal("set disposable loopback PostgreSQL URL (?sslmode=disable) and Redis host:port")
	}
	credentialFile, reviewers := writeMahjongAdminFixture(t)
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := listener.Addr().String()
	listener.Close()
	endpoint := "http://" + addr
	apiEnv := []string{
		"HTTP_ADDR=" + addr, "POSTGRES_URL=" + postgres.String(), "REDIS_ADDR=" + redis,
		"REDIS_PASSWORD=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_PASSWORD"), "REDIS_DB=" + os.Getenv("XBD_MAHJONG_TEST_REDIS_DB"),
		"XBD_ADMIN_CREDENTIAL_FILE=" + credentialFile,
	}
	first := launchRestartAPI(t, binary, endpoint, apiEnv)
	guest, matchID := makeMahjongAdminReport(t, endpoint)
	const sessionPath = "/api/v1/admin/session"
	const overviewPath = "/api/v1/admin/overview"
	const reportPath = "/api/v1/admin/mahjong/reports"
	const pendingPath = reportPath + "?status=pending&limit=20&offset=0"
	const upheldPath = reportPath + "?status=upheld&limit=20&offset=0"
	read := func(token, route string, want int) map[string]any {
		return requestMahjongAdminFixture(t, endpoint, http.MethodGet, route, token, "", want)
	}
	for _, path := range []string{sessionPath, overviewPath, pendingPath} {
		read("", path, http.StatusUnauthorized)
		read(guest.Token, path, http.StatusUnauthorized)
	}
	read(reviewers[2], overviewPath, http.StatusOK)
	read(reviewers[2], pendingPath, http.StatusForbidden)
	read(reviewers[0], overviewPath, http.StatusForbidden)
	if session := read(reviewers[0], sessionPath, http.StatusOK); session["admin_name"] != "reviewer-a" || !reflect.DeepEqual(session["capabilities"], []any{"mahjong:review"}) {
		t.Fatal("admin session exposed a different operator or scope")
	}
	pending := findMahjongAdminReport(t, read(reviewers[0], pendingPath, http.StatusOK), matchID)
	if pending == nil || pending["status"] != "pending" || pending["reason"] != "voice_abuse" || pending["reporter_seat"] != float64(0) || pending["target_seat"] != float64(1) {
		t.Fatal("genuine player report was not pending with the authenticated seats and reason")
	}
	id, ok := pending["report_id"].(string)
	if !ok || id == "" || strings.ContainsAny(id, "/?#") {
		t.Fatal("admin queue did not expose a usable report id")
	}
	resolveRoute := reportPath + "/" + id + "/resolve"
	const decision = `{"status":"upheld","note":"confirmed by review"}`
	const overwrite = `{"status":"dismissed","note":"overwrite attempt"}`
	resolve := func(token, body string, want int) map[string]any {
		return requestMahjongAdminFixture(t, endpoint, http.MethodPost, resolveRoute, token, body, want)
	}
	resolve("", decision, http.StatusUnauthorized)
	resolve(guest.Token, decision, http.StatusUnauthorized)
	resolve(reviewers[2], decision, http.StatusForbidden)
	accepted := resolve(reviewers[0], decision, http.StatusOK)
	disposition, ok := accepted["report"].(map[string]any)
	if !ok || disposition["report_id"] != id || disposition["status"] != "upheld" || disposition["analyst"] != "reviewer-a" || disposition["note"] != "confirmed by review" {
		t.Fatal("resolve response did not bind the original report to the authenticated reviewer and decision")
	}
	if reviewed, ok := disposition["reviewed_at"].(string); !ok || reviewed == "" {
		t.Fatal("resolve response omitted the review timestamp")
	}
	if retry := resolve(reviewers[0], decision, http.StatusOK); !reflect.DeepEqual(retry, accepted) {
		t.Fatal("exact retry changed the disposition response")
	}
	resolve(reviewers[1], overwrite, http.StatusConflict)
	if findMahjongAdminReport(t, read(reviewers[0], pendingPath, http.StatusOK), matchID) != nil {
		t.Fatal("reviewed report remained in pending queue")
	}
	upheld := findMahjongAdminReport(t, read(reviewers[0], upheldPath, http.StatusOK), matchID)
	if !reflect.DeepEqual(upheld, disposition) {
		t.Fatal("queue did not expose the upheld disposition")
	}
	first.stop(t)
	second := launchRestartAPI(t, binary, endpoint, apiEnv)
	if second.cmd.Process.Pid == first.cmd.Process.Pid {
		t.Fatal("admin disposition test did not restart the API")
	}
	if retry := resolve(reviewers[0], decision, http.StatusOK); !reflect.DeepEqual(retry, accepted) {
		t.Fatal("exact retry changed the persisted review after restart")
	}
	resolve(reviewers[1], overwrite, http.StatusConflict)
	if after := findMahjongAdminReport(t, read(reviewers[1], upheldPath, http.StatusOK), matchID); !reflect.DeepEqual(after, upheld) {
		t.Fatal("another operator or service restart changed the persisted disposition")
	}
	t.Logf("MAHJONG_ADMIN_DISPOSITION_OK first_pid=%d second_pid=%d report=%s scope_gate=true exact_retry=true overwrite_denied=true",
		first.cmd.Process.Pid, second.cmd.Process.Pid, id)
}

func writeMahjongAdminFixture(t *testing.T) (string, [3]string) {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", "..", ".tmp"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	file, err := os.CreateTemp(root, "mahjong-admin-disposition-*.json")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.Remove(file.Name()); err != nil {
			t.Errorf("remove temporary admin credential digests: %v", err)
		}
	})
	defer file.Close()
	type credential struct {
		Name         string   `json:"name"`
		TokenSHA256  string   `json:"token_sha256"`
		Capabilities []string `json:"capabilities"`
	}
	entries := []credential{
		{Name: "reviewer-a", Capabilities: []string{"mahjong:review"}},
		{Name: "reviewer-b", Capabilities: []string{"mahjong:review"}},
		{Name: "platform-reader", Capabilities: []string{"platform:read"}},
	}
	var rawTokens [3]string
	for i := range entries {
		var secret [32]byte
		if _, err := rand.Read(secret[:]); err != nil {
			t.Fatal("could not generate temporary admin credentials")
		}
		rawTokens[i] = base64.RawURLEncoding.EncodeToString(secret[:])
		digest := sha256.Sum256([]byte(rawTokens[i]))
		entries[i].TokenSHA256 = hex.EncodeToString(digest[:])
	}
	if err := json.NewEncoder(file).Encode(entries); err != nil {
		t.Fatal("could not write temporary admin credential digests")
	}
	return file.Name(), rawTokens
}

func makeMahjongAdminReport(t *testing.T, endpoint string) (restartGuest, string) {
	t.Helper()
	var guests [4]restartGuest
	var lobby [4]*websocket.Conn
	for seat := range guests {
		guests[seat] = loadRestartGuest(t, endpoint, "")
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guests[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	lobbyCommand(t, lobby[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for _, conn := range lobby[1:] {
		lobbyCommand(t, conn, "join", roomID, "", "", true)
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	options := map[string]any{"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true, "requires_kong_to_claim": true, "rob_kong": true}
	board, _, matchID := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	referenceSend(t, board[0], map[string]any{"type": "mahjong_report", "command_id": "operator-e2e-report", "target_seat": 1, "match_id": matchID, "reason": "voice_abuse"})
	result := mahjongReferenceRead(t, board[0], "mahjong_report_result")
	if result["command_id"] != "operator-e2e-report" || result["ok"] != true {
		t.Fatal("normal board socket could not file the report")
	}
	return guests[0], matchID
}

func requestMahjongAdminFixture(t *testing.T, endpoint, method, route, token, body string, want int) map[string]any {
	t.Helper()
	client := &http.Client{Timeout: 4 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, err := http.NewRequest(method, endpoint+route, bytes.NewBufferString(body))
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	response, err := client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, route, err)
	}
	defer response.Body.Close()
	if response.StatusCode != want {
		t.Fatalf("%s %s returned %d, want %d", method, route, response.StatusCode, want)
	}
	if want != http.StatusOK {
		return nil
	}
	var result map[string]any
	if err := json.NewDecoder(response.Body).Decode(&result); err != nil {
		t.Fatalf("%s %s returned invalid JSON", method, route)
	}
	return result
}

func findMahjongAdminReport(t *testing.T, page map[string]any, matchID string) map[string]any {
	t.Helper()
	items, ok := page["items"].([]any)
	total, counted := page["total"].(float64)
	if !ok || !counted || total < float64(len(items)) || len(items) > 20 {
		t.Fatal("admin report list did not return a bounded page with total")
	}
	for _, item := range items {
		report, ok := item.(map[string]any)
		if ok && report["match_id"] == matchID {
			return report
		}
	}
	return nil
}
