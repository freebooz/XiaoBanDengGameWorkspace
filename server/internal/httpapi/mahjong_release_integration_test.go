package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
)

// TestMahjongReleaseFourPeers uses a separately started, isolated cmd/api with
// the release migrations and real Postgres/Redis. Every guest and WebSocket
// request reaches that process, including the optionally faulted host socket.
func TestMahjongReleaseFourPeers(t *testing.T) {
	endpoint := strings.TrimSpace(os.Getenv("XBD_MAHJONG_RELEASE_URL"))
	if endpoint == "" {
		t.Skip("set XBD_MAHJONG_RELEASE_URL to the isolated loopback release service")
	}
	base, err := url.Parse(endpoint)
	if err != nil || base.Scheme != "http" || base.User != nil || base.Port() == "" || (base.Path != "" && base.Path != "/") || base.RawQuery != "" || base.Fragment != "" {
		t.Fatal("XBD_MAHJONG_RELEASE_URL must be an HTTP loopback origin with an explicit port")
	}
	if address := net.ParseIP(base.Hostname()); address == nil || !address.IsLoopback() {
		t.Fatal("XBD_MAHJONG_RELEASE_URL must use a numeric loopback address")
	}
	endpoint = strings.TrimSuffix(base.String(), "/")
	checkMahjongReleaseService(t, endpoint)

	godot := os.Getenv("XBD_MAHJONG_SMOKE_GODOT")
	if godot == "" {
		t.Fatal("set XBD_MAHJONG_SMOKE_GODOT to the installed Godot executable")
	}
	if runtime.GOOS == "windows" && strings.HasSuffix(godot, "_console.exe") {
		executable := strings.TrimSuffix(godot, "_console.exe") + ".exe"
		if _, err := os.Stat(executable); err == nil {
			godot = executable
		}
	}
	repo, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	project := filepath.Join(repo, "client", ".generated", "mahjong")
	if _, err := os.Stat(filepath.Join(project, "project.godot")); err != nil {
		t.Fatalf("compose and import the Mahjong product first: %v", err)
	}
	tmp := filepath.Join(repo, ".tmp")
	if err := os.MkdirAll(tmp, 0755); err != nil {
		t.Fatal(err)
	}
	fixture, err := os.MkdirTemp(tmp, "mahjong-release-peers-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(fixture); err != nil {
			t.Errorf("remove release peer profiles: %v", err)
		}
	})
	preview := os.Getenv("XBD_MAHJONG_SMOKE_PREVIEW")
	allHeadless := os.Getenv("XBD_MAHJONG_SMOKE_HEADLESS") == "1"
	if !allHeadless && preview != "" {
		preview, err = filepath.Abs(preview)
		if err != nil {
			t.Fatal(err)
		}
		relative, err := filepath.Rel(repo, preview)
		if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			t.Fatal("release previews must be saved inside the workspace")
		}
		if err := os.MkdirAll(preview, 0755); err != nil {
			t.Fatal(err)
		}
	}
	script := filepath.Join(repo, "client", "tests", "mahjong_guiyang_peer_smoke.gd")
	var fault *releaseBoardFault
	switch mode := os.Getenv("XBD_MAHJONG_RELEASE_RECONNECT"); mode {
	case "":
	case "drop", "blackhole":
		fault = newReleaseBoardFault(t, base, mode)
	default:
		t.Fatal("XBD_MAHJONG_RELEASE_RECONNECT must be drop, blackhole or empty")
	}
	customRules := os.Getenv("XBD_MAHJONG_RELEASE_CUSTOM_RULES") == "1"
	if !runMahjongReleasePeers(t, godot, project, script, fixture, endpoint, preview, allHeadless, false, customRules, fault) {
		return
	}
	var resumed bool
	readGuiyangReceipt(t, fixture, "resumed", &resumed)
	if !resumed {
		t.Fatal("host did not resume its original room and seat")
	}
	first := verifyGuiyangPeerReceipts(t, fixture, 1)
	if fault != nil {
		var restored struct {
			RoomID     string `json:"room_id"`
			MatchID    string `json:"match_id"`
			Seat       int    `json:"seat"`
			Epoch      int    `json:"epoch"`
			HandSize   int    `json:"hand_size"`
			DetectedMS int    `json:"detected_ms"`
			RestoredMS int    `json:"restored_ms"`
		}
		readGuiyangReceipt(t, fixture, "reconnected-board", &restored)
		if restored.RoomID != first[0].RoomID || restored.MatchID != first[0].MatchID || restored.Seat != first[0].Seat || restored.Epoch < 0 || restored.HandSize != len(first[0].HandIDs) || restored.DetectedMS <= 0 || restored.RestoredMS <= restored.DetectedMS {
			t.Fatal("board reconnect receipt does not match the original host deal")
		}
		t.Logf("MAHJONG_RELEASE_BOARD_RECONNECTED mode=%s room=%s match=%s seat=%d hand_size=%d detected_ms=%d restored_ms=%d authoritative_discard=true", fault.mode, restored.RoomID, restored.MatchID, restored.Seat, restored.HandSize, restored.DetectedMS, restored.RestoredMS)
	}
	second := verifyGuiyangPeerReceipts(t, fixture, 2)
	for index := range first {
		if second[index].RoomID != first[index].RoomID || second[index].MatchID == first[index].MatchID || second[index].Seat != first[index].Seat ||
			second[index].PID != first[index].PID || second[index].Account != first[index].Account {
			t.Fatalf("peer %d did not retain process, account, room and seat across distinct rounds", index)
		}
	}
	if customRules {
		verifyReleaseCustomRules(t, fixture)
	}
	if !runMahjongReleasePeers(t, godot, project, script, fixture, endpoint, preview, allHeadless || preview == "", true, false, fault) {
		return
	}
	seenRestart := make(map[int]bool, len(first))
	for index, deal := range first {
		var session struct {
			Account string `json:"account"`
			PID     int    `json:"pid"`
		}
		readGuiyangReceipt(t, fixture, fmt.Sprintf("session-%d", index), &session)
		if session.Account != deal.Account || session.PID <= 0 || session.PID == deal.PID || seenRestart[session.PID] {
			t.Fatalf("peer %d did not recover the original account in a new process", index)
		}
		seenRestart[session.PID] = true
	}
	t.Logf("MAHJONG_RELEASE_FOUR_PEERS_OK postgres=ok redis=ok room=%s first=%s second=%s session_restarts=4",
		first[0].RoomID, first[0].MatchID, second[0].MatchID)
}

func checkMahjongReleaseService(t *testing.T, endpoint string) {
	t.Helper()
	client := &http.Client{
		Timeout:       5 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	response, err := client.Get(endpoint + "/health")
	if err != nil {
		t.Fatalf("release service health request failed: %v", err)
	}
	defer response.Body.Close()
	var health struct {
		Service  string `json:"service"`
		Postgres string `json:"postgres"`
		Redis    string `json:"redis"`
	}
	if response.StatusCode != http.StatusOK || json.NewDecoder(response.Body).Decode(&health) != nil ||
		health.Service != "ok" || health.Postgres != "ok" || health.Redis != "ok" {
		t.Fatalf("release health must report service, postgres and redis ready (HTTP %d)", response.StatusCode)
	}
	for _, path := range []string{"/api/v1/auth/session", "/api/v1/mahjong/ws"} {
		check, err := client.Get(endpoint + path)
		if err != nil {
			t.Fatalf("check protected route %s: %v", path, err)
		}
		check.Body.Close()
		if check.StatusCode != http.StatusUnauthorized {
			t.Fatalf("%s must reject missing Bearer credentials (HTTP %d)", path, check.StatusCode)
		}
	}
}

func verifyReleaseCustomRules(t *testing.T, fixture string) {
	t.Helper()
	for round := 1; round <= 2; round++ {
		for _, stage := range []string{"waiting", "deal", "settlement"} {
			for peer := range 4 {
				var options guiyang.RuleOptions
				name := fmt.Sprintf("custom-%s-%d-%d", stage, round, peer)
				readGuiyangReceipt(t, fixture, name, &options)
				want := guiyang.RuleOptions{Version: guiyang.RuleOptionsVersion, Chicken: true, RequiresKongToClaim: true}
				if options != want {
					t.Fatalf("peer %d round %d %s had different effective options: %+v", peer, round, stage, options)
				}
			}
		}
	}
	t.Log("MAHJONG_RELEASE_CUSTOM_RULES_OK peers=4 rounds=2 stages=waiting,deal,settlement chicken=true charge_chicken=false black_eight=false requires_kong_to_claim=true rob_kong=false")
}

func runMahjongReleasePeers(t *testing.T, godot, project, script, fixture, endpoint, preview string, allHeadless, restart, customRules bool, fault *releaseBoardFault) bool {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 115*time.Second)
	defer cancel()
	phase, success := "rounds", "MAHJONG_GUIYANG_PEER_OK"
	if restart {
		phase, success = "restart", "MAHJONG_GUIYANG_SESSION_OK"
	}
	verifyHistory := restart && os.Getenv("XBD_MAHJONG_RELEASE_HISTORY") == "1"
	verifyReport := !restart && os.Getenv("XBD_MAHJONG_RELEASE_REPORT") == "1"
	type result struct {
		index  int
		output string
		err    error
	}
	results := make(chan result, 4)
	var disruption chan error
	if fault != nil && !restart {
		disruption = make(chan error, 1)
		go func() {
			disruption <- fault.exercise(ctx, fixture)
		}()
	}
	for index := range 4 {
		go func() {
			serverURL := endpoint
			if index == 0 && fault != nil {
				serverURL = fault.url
			}
			headless := allHeadless || index != 0
			logPath := filepath.Join(fixture, fmt.Sprintf("%s-%d.log", phase, index))
			resolution := "540x960"
			if !headless && os.Getenv("XBD_MAHJONG_RELEASE_TABLET") == "1" {
				resolution = "1024x768"
			}
			args := []string{"--disable-vsync", "--max-fps", "0", "--resolution", resolution, "--audio-driver", "Dummy", "--log-file", logPath}
			if headless {
				args = append(args, "--headless")
			} else if runtime.GOOS == "windows" {
				args = append(args, "--rendering-driver", "vulkan")
			}
			args = append(args, "--path", project, "--script", script, "--",
				"--server-url="+serverURL, fmt.Sprintf("--peer=%d", index), "--fixture-dir="+fixture)
			if !headless && preview != "" {
				args = append(args, "--preview-dir="+preview)
			}
			if restart {
				args = append(args, "--resume-session-only")
				if verifyHistory {
					args = append(args, "--verify-history")
				}
			} else {
				args = append(args, "--rematch")
				if index == 0 && verifyReport {
					args = append(args, "--verify-report")
				}
				if customRules {
					args = append(args, "--custom-rules")
				}
				if index == 0 && fault != nil {
					args = append(args, "--transport-fault")
				}
			}
			cmd := exec.CommandContext(ctx, godot, args...)
			profile := filepath.Join(fixture, fmt.Sprintf("profile-%d", index))
			cmd.Env = append(os.Environ(), "APPDATA="+profile, "LOCALAPPDATA="+profile, "XDG_DATA_HOME="+profile, "XDG_CONFIG_HOME="+profile)
			output, err := cmd.CombinedOutput()
			if log, logErr := os.ReadFile(logPath); logErr == nil && len(log) > 0 {
				output = log
			}
			results <- result{index, string(output), err}
		}()
	}
	passed := true
	for pending := 4; pending > 0 || disruption != nil; {
		var peer result
		select {
		case err := <-disruption:
			disruption = nil
			if err != nil && passed {
				t.Errorf("board fault fixture: %v", err)
				passed = false
				cancel()
			}
			continue
		case peer = <-results:
			pending--
		}
		if peer.err != nil || !strings.Contains(peer.output, success) || strings.Contains(peer.output, "ERROR:") {
			// Only explicit test steps and result markers leave the isolated log directory.
			t.Errorf("release %s peer %d failed: %v (engine error=%t)", phase, peer.index, peer.err, strings.Contains(peer.output, "ERROR:"))
			passed = false
			cancel()
		} else if peer.index == 0 && !allHeadless && runtime.GOOS == "windows" && !strings.Contains(peer.output, "Vulkan") {
			t.Error("release peer 0 failed to start the requested Vulkan renderer")
			passed = false
		}
		if verifyHistory && !strings.Contains(peer.output, "MAHJONG_GUIYANG_HISTORY_RESTORED ") {
			t.Errorf("release restart peer %d did not restore both persisted rounds", peer.index)
			passed = false
		}
		if verifyHistory && !strings.Contains(peer.output, "MAHJONG_GUIYANG_NATIVE_REPLAY_OK ") {
			t.Errorf("release restart peer %d did not open and step the persisted replay", peer.index)
			passed = false
		}
		if verifyReport && peer.index == 0 && !strings.Contains(peer.output, "MAHJONG_GUIYANG_NATIVE_REPORT_OK ") {
			t.Error("release host did not receive an authenticated report acknowledgement")
			passed = false
		}
		for _, line := range strings.Split(peer.output, "\n") {
			if strings.HasPrefix(line, "MAHJONG_PEER_LIMITS ") || strings.HasPrefix(line, success+" ") || strings.HasPrefix(line, "MAHJONG_PEER_STEP ") || strings.HasPrefix(line, "MAHJONG_GUIYANG_HISTORY_RESTORED ") || strings.HasPrefix(line, "MAHJONG_GUIYANG_NATIVE_REPLAY_OK ") || strings.HasPrefix(line, "MAHJONG_GUIYANG_NATIVE_REPORT_OK ") {
				t.Log(strings.TrimSpace(line))
			}
			if strings.HasPrefix(line, "   at: GDScript::reload (res://") {
				t.Logf("release %s peer %d has a script load error at %s", phase, peer.index, strings.TrimSpace(line))
			}
		}
	}
	return passed
}

// Only host traffic reaches this relay. HTTP remains intact and active WebSocket
// upgrades are ordered. Lobby opens first, then the board opens on the same route.
type releaseBoardFault struct {
	mode    string
	url     string
	mu      sync.Mutex
	streams []*releaseBoardStream
	blocked bool
	next    http.RoundTripper
}

func newReleaseBoardFault(t *testing.T, base *url.URL, mode string) *releaseBoardFault {
	t.Helper()
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	fault := &releaseBoardFault{mode: mode, next: transport}
	proxy := httputil.NewSingleHostReverseProxy(base)
	proxy.Transport = fault
	proxy.ErrorLog = log.New(io.Discard, "", 0)
	server := httptest.NewServer(proxy)
	fault.url = server.URL
	t.Cleanup(func() {
		fault.mu.Lock()
		for _, stream := range fault.streams {
			if !stream.closed.Load() {
				_ = stream.Close()
			}
		}
		fault.mu.Unlock()
		server.Close()
		transport.CloseIdleConnections()
	})
	return fault
}

func (f *releaseBoardFault) RoundTrip(request *http.Request) (*http.Response, error) {
	upgrade := strings.EqualFold(request.Header.Get("Upgrade"), "websocket")
	if upgrade {
		f.mu.Lock()
		blocked := f.blocked
		f.mu.Unlock()
		if blocked {
			return nil, fmt.Errorf("board fixture temporarily blocks upgrades")
		}
	}
	response, err := f.next.RoundTrip(request)
	if err != nil || !upgrade || response.StatusCode != http.StatusSwitchingProtocols {
		return response, err
	}
	conn, ok := response.Body.(io.ReadWriteCloser)
	if !ok {
		response.Body.Close()
		return nil, fmt.Errorf("board fixture did not receive a bidirectional upgrade")
	}
	stream := &releaseBoardStream{ReadWriteCloser: conn}
	f.mu.Lock()
	f.streams = append(f.streams, stream)
	f.mu.Unlock()
	response.Body = stream
	return response, nil
}

func (f *releaseBoardFault) exercise(ctx context.Context, fixture string) error {
	if err := waitForBoardReceipt(ctx, fixture, "disconnect-board"); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 18*time.Second)
	defer cancel()
	f.mu.Lock()
	var active []*releaseBoardStream
	for _, stream := range f.streams {
		if !stream.closed.Load() {
			active = append(active, stream)
		}
	}
	if len(active) != 2 {
		f.mu.Unlock()
		return fmt.Errorf("expected host's two active lobby and board streams, got %d", len(active))
	}
	f.blocked = true
	board := active[1]
	upgradeCount := len(f.streams)
	f.mu.Unlock()
	if f.mode == "drop" {
		_ = board.Close()
	} else {
		board.blackhole.Store(true)
	}
	releaseErr := waitForBoardReceipt(ctx, fixture, "release-board")
	f.mu.Lock()
	f.blocked = false
	f.mu.Unlock()
	if releaseErr != nil {
		return releaseErr
	}
	if f.mode == "blackhole" && board.discardedBytes.Load() == 0 {
		return fmt.Errorf("blackhole fixture did not suppress any board traffic")
	}
	if err := waitForBoardReceipt(ctx, fixture, "reconnected-board"); err != nil {
		return err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.streams) <= upgradeCount || active[0].closed.Load() {
		return fmt.Errorf("board did not establish a fresh WebSocket with the original lobby stream intact")
	}
	return nil
}

func waitForBoardReceipt(ctx context.Context, fixture, name string) error {
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		if _, err := os.Stat(filepath.Join(fixture, name+".json")); err == nil {
			return nil
		} else if !os.IsNotExist(err) {
			return err
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("wait for %s: %w", name, ctx.Err())
		case <-ticker.C:
		}
	}
}

type releaseBoardStream struct {
	io.ReadWriteCloser
	closed         atomic.Bool
	blackhole      atomic.Bool
	discardedBytes atomic.Int64
}

func (s *releaseBoardStream) Read(data []byte) (int, error) {
	for {
		n, err := s.ReadWriteCloser.Read(data)
		if !s.blackhole.Load() || err != nil {
			return n, err
		}
		s.discardedBytes.Add(int64(n))
	}
}

func (s *releaseBoardStream) Write(data []byte) (int, error) {
	if s.blackhole.Load() {
		s.discardedBytes.Add(int64(len(data)))
		return len(data), nil
	}
	return s.ReadWriteCloser.Write(data)
}

func (s *releaseBoardStream) Close() error {
	s.closed.Store(true)
	return s.ReadWriteCloser.Close()
}
