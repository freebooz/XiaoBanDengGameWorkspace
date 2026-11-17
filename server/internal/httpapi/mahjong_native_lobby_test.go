package httpapi

import (
	"context"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Launch the actual Godot product against this freshly built in-process listener.
// Only health and guest-account creation are fixture endpoints; game/lobby/rooms
// use the production handler and socket. Opt-in to keep default Go CI headless.
func TestMahjongNativeLobbyProduct(t *testing.T) {
	runMahjongNativeLobbyProduct(t, "", "MAHJONG_NATIVE_LOBBY_OK", 4)
}

func TestMahjongNativeSpectatorProduct(t *testing.T) {
	runMahjongNativeLobbyProduct(t, "--spectators", "MAHJONG_NATIVE_SPECTATORS_OK", 5)
}

func runMahjongNativeLobbyProduct(t *testing.T, exercise, successMarker string, guests int) {
	t.Helper()
	godot := os.Getenv("XBD_MAHJONG_SMOKE_GODOT")
	if godot == "" {
		t.Skip("set XBD_MAHJONG_SMOKE_GODOT to run the native product")
	}
	repo, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()

	project := os.Getenv("XBD_MAHJONG_SMOKE_PROJECT")
	if project == "" {
		project = filepath.Join(repo, "client", ".generated", "mahjong")
	}
	args := []string{"--disable-vsync", "--max-fps", "0", "--resolution", "540x960",
		"--path", project,
		"--script", filepath.Join(repo, "client", "tests", "mahjong_native_lobby_smoke.gd"),
		"--", "--server-url=" + server.URL}
	if exercise != "" {
		args = append(args, exercise)
	}
	if os.Getenv("XBD_MAHJONG_SMOKE_HEADLESS") == "1" {
		args = append([]string{"--headless"}, args...)
	}
	if preview := os.Getenv("XBD_MAHJONG_SMOKE_PREVIEW"); preview != "" {
		if err := os.MkdirAll(preview, 0755); err != nil {
			t.Fatal(err)
		}
		args = append(args, "--preview-dir="+preview)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, godot, args...).CombinedOutput()
	log := string(output)
	if path := os.Getenv("XBD_MAHJONG_SMOKE_LOG"); path != "" {
		if logErr := os.WriteFile(path, output, 0644); logErr != nil {
			t.Fatal(logErr)
		}
	}
	if err != nil || accounts.count() != guests || !strings.Contains(log, successMarker) ||
		strings.Contains(log, "SCRIPT ERROR:") || strings.Contains(log, "ERROR:") {
		t.Fatalf("native Mahjong failed: err=%v accounts=%d\n%s", err, accounts.count(), output)
	}
	for _, line := range strings.Split(log, "\n") {
		if strings.HasPrefix(line, "MAHJONG_NATIVE_") {
			t.Log(strings.TrimSpace(line))
		}
	}
}
