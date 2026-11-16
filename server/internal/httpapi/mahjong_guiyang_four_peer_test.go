package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"
)

type guiyangPeerDeal struct {
	PID         int       `json:"pid"`
	RoomID      string    `json:"room_id"`
	MatchID     string    `json:"match_id"`
	RuleSetID   string    `json:"rule_set_id"`
	RuleVersion string    `json:"rule_version"`
	Seat        int       `json:"seat"`
	Dealer      int       `json:"dealer"`
	Account     string    `json:"account"`
	Players     [4]string `json:"players"`
	HandIDs     []int     `json:"hand_ids"`
}

type guiyangPeerSettlement struct {
	RoomID   string `json:"room_id"`
	MatchID  string `json:"match_id"`
	Seat     int    `json:"seat"`
	Scores   [4]int `json:"scores"`
	Winners  []int  `json:"winners"`
	Reason   string `json:"reason"`
	Commands int    `json:"commands"`
}

// Run the composed product in four isolated processes. The local HTTP fixture
// provides health and guest identities. Production handlers own lobby and play.
func TestMahjongGuiyangFourPeers(t *testing.T) {
	godot := os.Getenv("XBD_MAHJONG_SMOKE_GODOT")
	if godot == "" {
		t.Skip("set XBD_MAHJONG_SMOKE_GODOT to run four native Mahjong processes")
	}
	// The official Windows console launcher starts a child. Target the real
	// executable so the timeout owns the same process that runs the product.
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
	fixture, err := os.MkdirTemp(tmp, "mahjong-guiyang-peers-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(fixture); err != nil {
			t.Errorf("remove peer fixture: %v", err)
		}
	})

	accounts := &fixtureAccounts{}
	server := httptest.NewServer(mahjongAccountFixture(accounts))
	defer server.Close()

	allHeadless := os.Getenv("XBD_MAHJONG_SMOKE_HEADLESS") == "1"
	rematch := os.Getenv("XBD_MAHJONG_SMOKE_REMATCH") == "1"
	preview := os.Getenv("XBD_MAHJONG_SMOKE_PREVIEW")
	if !allHeadless && preview != "" {
		preview, err = filepath.Abs(preview)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(preview, 0755); err != nil {
			t.Fatal(err)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 115*time.Second)
	defer cancel()
	type peerResult struct {
		index  int
		output string
		err    error
	}
	results := make(chan peerResult, 4)
	for index := 0; index < 4; index++ {
		go func(index int) {
			headless := allHeadless || index != 0
			logPath := filepath.Join(fixture, fmt.Sprintf("peer-%d.log", index))
			args := []string{"--disable-vsync", "--max-fps", "0", "--resolution", "540x960", "--audio-driver", "Dummy", "--log-file", logPath}
			if headless {
				args = append(args, "--headless")
			} else if runtime.GOOS == "windows" {
				args = append(args, "--rendering-driver", "vulkan")
			}
			args = append(args, "--path", project, "--script", filepath.Join(repo, "client", "tests", "mahjong_guiyang_peer_smoke.gd"),
				"--", "--server-url="+server.URL, fmt.Sprintf("--peer=%d", index), "--fixture-dir="+fixture)
			if !headless && preview != "" {
				args = append(args, "--preview-dir="+preview)
			}
			if rematch {
				args = append(args, "--rematch")
			}
			cmd := exec.CommandContext(ctx, godot, args...)
			profile := filepath.Join(fixture, fmt.Sprintf("profile-%d", index))
			cmd.Env = append(os.Environ(), "APPDATA="+profile, "LOCALAPPDATA="+profile, "XDG_DATA_HOME="+profile, "XDG_CONFIG_HOME="+profile)
			output, err := cmd.CombinedOutput()
			if log, logErr := os.ReadFile(logPath); logErr == nil && len(log) > 0 {
				output = log
			}
			results <- peerResult{index, string(output), err}
		}(index)
	}
	failed := false
	for range 4 {
		result := <-results
		if result.err != nil || !strings.Contains(result.output, "MAHJONG_GUIYANG_PEER_OK") || strings.Contains(result.output, "ERROR:") {
			t.Errorf("peer %d failed: %v\n%s", result.index, result.err, result.output)
			failed = true
			cancel()
			continue
		}
		if result.index == 0 && !allHeadless && runtime.GOOS == "windows" && !strings.Contains(result.output, "Vulkan") {
			t.Errorf("peer 0 did not report Vulkan:\n%s", result.output)
		}
		for _, line := range strings.Split(result.output, "\n") {
			if strings.HasPrefix(line, "MAHJONG_PEER_LIMITS") || strings.HasPrefix(line, "MAHJONG_GUIYANG_PEER_OK") {
				t.Log(strings.TrimSpace(line))
			}
		}
	}
	if failed {
		return
	}
	if accounts.count() != 4 {
		t.Fatalf("fixture issued %d accounts, want 4", accounts.count())
	}
	var resumed bool
	readGuiyangReceipt(t, fixture, "resumed", &resumed)
	if !resumed {
		t.Fatal("host did not resume the original seat")
	}
	first := verifyGuiyangPeerReceipts(t, fixture, 1)
	if rematch {
		second := verifyGuiyangPeerReceipts(t, fixture, 2)
		for index := range first {
			if second[index].RoomID != first[index].RoomID || second[index].MatchID == first[index].MatchID || second[index].Seat != first[index].Seat ||
				second[index].PID != first[index].PID || second[index].Account != first[index].Account {
				t.Fatalf("peer %d did not retain room, process, account and seat across distinct matches", index)
			}
		}
		t.Logf("MAHJONG_GUIYANG_REMATCH_OK room=%s first=%s second=%s settlement_readies=4 retained_seats=4 returned_to_lobby=4", first[0].RoomID, first[0].MatchID, second[0].MatchID)
	}
}

func readGuiyangReceipt(t *testing.T, fixture, name string, dst any) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(fixture, name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, dst); err != nil {
		t.Fatalf("invalid %s receipt: %v", name, err)
	}
}

func verifyGuiyangPeerReceipts(t *testing.T, fixture string, round int) [4]guiyangPeerDeal {
	t.Helper()
	var deals [4]guiyangPeerDeal
	var firstSettlement guiyangPeerSettlement
	pids, seats, tiles := map[int]bool{}, map[int]bool{}, map[int]bool{}
	accounts := map[string]bool{}
	commands := 0
	for index := range 4 {
		var settlement guiyangPeerSettlement
		readGuiyangReceipt(t, fixture, fmt.Sprintf("deal-%d-%d", round, index), &deals[index])
		readGuiyangReceipt(t, fixture, fmt.Sprintf("settlement-%d-%d", round, index), &settlement)
		deal, firstDeal := deals[index], deals[0]
		if index == 0 {
			firstSettlement = settlement
		}
		if deal.PID <= 0 || pids[deal.PID] || deal.Seat < 0 || deal.Seat >= 4 || seats[deal.Seat] || deal.Account == "" || accounts[deal.Account] {
			t.Fatalf("peer %d repeated or invalid process, seat or account: %+v", index, deal)
		}
		pids[deal.PID], seats[deal.Seat], accounts[deal.Account] = true, true, true
		if len(deal.RoomID) != 4 || deal.RoomID != firstDeal.RoomID || deal.MatchID == "" || deal.MatchID != firstDeal.MatchID ||
			deal.RuleSetID != "guiyang" || deal.RuleVersion != "2.0.0" || deal.Dealer < 0 || deal.Dealer >= 4 ||
			deal.Dealer != firstDeal.Dealer || deal.Players != firstDeal.Players || deal.Players[deal.Seat] != deal.Account {
			t.Fatalf("peer %d received inconsistent authoritative deal: %+v", index, deal)
		}
		handSize := 13
		if deal.Seat == deal.Dealer {
			handSize++
		}
		if len(deal.HandIDs) != handSize {
			t.Fatalf("peer %d received %d tiles, want %d", index, len(deal.HandIDs), handSize)
		}
		for _, id := range deal.HandIDs {
			if id <= 0 || tiles[id] {
				t.Fatalf("peer %d received invalid or overlapping tile ID %d", index, id)
			}
			tiles[id] = true
		}
		if settlement.RoomID != deal.RoomID || settlement.MatchID != deal.MatchID || settlement.Seat != deal.Seat ||
			settlement.Scores != firstSettlement.Scores || settlement.Reason != firstSettlement.Reason || !slices.Equal(settlement.Winners, firstSettlement.Winners) {
			t.Fatalf("peer %d received inconsistent settlement: %+v", index, settlement)
		}
		commands += settlement.Commands
	}
	var scoreSum int
	for _, score := range firstSettlement.Scores {
		scoreSum += score
	}
	if len(tiles) != 53 || scoreSum != 0 || commands < 4 {
		t.Fatalf("want 53 private initial tiles, zero-sum scoring and live play, got tiles=%d scores=%v commands=%d", len(tiles), firstSettlement.Scores, commands)
	}
	t.Logf("MAHJONG_GUIYANG_FOUR_PEERS_OK round=%d room=%s match=%s rules=guiyang@2.0.0 processes=%d seats=%d private_tiles=%d commands=%d scores=%v winners=%v reason=%s",
		round, deals[0].RoomID, deals[0].MatchID, len(pids), len(seats), len(tiles), commands, firstSettlement.Scores, firstSettlement.Winners, firstSettlement.Reason)
	return deals
}
