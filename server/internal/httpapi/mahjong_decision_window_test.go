package httpapi

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/gorilla/websocket"
)

func TestMahjongActionRejectsWrongDecisionWindow(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	conn := fixture.connections[0][0]
	state := lobbyRead(t, conn, "mahjong_state", func(state map[string]any) bool { return state["status"] == "playing" })
	tile := state["hand"].([]any)[0].(map[string]any)["id"]
	packet := map[string]any{"type": "mahjong_action", "match_id": state["match_id"],
		"command_id": "play-from-window", "action": "play", "tile_id": tile, "action_window_id": "previous-window"}
	referenceSend(t, conn, packet)
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != false {
		t.Fatal("otherwise legal action from a stale window was accepted")
	}
	window, ok := state["action_window_id"].(string)
	if !ok || window == "" {
		t.Fatal("playing snapshot lacks an action window")
	}
	packet["action_window_id"] = window
	referenceSend(t, conn, packet)
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("current window was rejected: %v", result)
	}
	next := lobbyRead(t, conn, "mahjong_state", nil)
	if next["action_window_id"] == window || next["action_window_id"] == nil {
		t.Fatal("discard did not advance the decision window")
	}
	// A lost acknowledgement may be retried after the underlying decision closed.
	referenceSend(t, conn, packet)
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("retry of committed command was rejected: %v", result)
	}
	retry := lobbyRead(t, conn, "mahjong_state", nil)
	if retry["epoch"] != next["epoch"] || retry["action_window_id"] != next["action_window_id"] {
		t.Fatal("acknowledgement retry changed the live decision")
	}
}

func TestMahjongDecisionWindowKeepsOneDeadlineAcrossReplies(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	// Age the window without sleeping so a refresh changes the observed deadline.
	stageReactionDecision(fixture, nil, time.Now().UTC().Add(-3*time.Second))

	peers := fixture.connections[0]
	first := [4]map[string]any{}
	for seat, peer := range peers {
		first[seat] = lobbyRead(t, peer, "mahjong_state", func(state map[string]any) bool { return state["phase"] == guiyang.PhaseReaction })
	}
	window, deadline := first[1]["action_window_id"], first[1]["action_deadline_ms"]
	for _, seat := range []int{1, 2} {
		referenceSend(t, peers[seat], reactionPass(first[seat]))
	}
	for _, seat := range []int{1, 2} {
		if result := lobbyRead(t, peers[seat], "mahjong_action_result", nil); result["ok"] != true {
			t.Fatalf("seat %d could not respond within the same decision: %v", seat, result)
		}
	}
	for count := 1; count <= 2; count++ {
		updated := lobbyRead(t, peers[3], "mahjong_state", nil)
		if updated["epoch"].(float64) != first[3]["epoch"].(float64)+float64(count) || updated["phase"] != guiyang.PhaseReaction {
			t.Fatalf("unexpected intermediate snapshot for response %d: %v", count, updated)
		}
		if updated["action_deadline_ms"] != deadline {
			t.Fatalf("response %d shifted the deadline from %v to %v", count, deadline, updated["action_deadline_ms"])
		}
		if window == nil || window == "" || updated["action_window_id"] != window {
			t.Fatal("intermediate response changed the decision window")
		}
	}
	legacy := reactionPass(first[3])
	delete(legacy, "action_window_id")
	referenceSend(t, peers[3], legacy)
	if result := lobbyRead(t, peers[3], "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("legacy response without decision ID was rejected: %v", result)
	}
	finished := lobbyRead(t, peers[3], "mahjong_state", nil)
	if finished["phase"] != guiyang.PhaseTurn || finished["action_window_id"] == window {
		t.Fatal("reaction resolution did not open a new turn decision")
	}
}

func TestMahjongDecisionWindowSurvivesPostgresRestore(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("isolated decision window database unavailable")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	store := mahjongactive.NewService(db)
	fixture := referenceMahjongServer(t, 1, 4)
	r := stageReactionDecision(fixture, store, time.Now().UTC())
	defer func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		if r.revision > 0 {
			if err := store.Delete(ctx, r.matchID, r.revision); err != nil {
				t.Errorf("delete test checkpoint: %v", err)
			}
		}
	}()
	conn := fixture.connections[0][1]
	first := readMahjongDecision(t, conn, r.matchID, guiyang.PhaseReaction)
	// Make the opening and response stamps observably distinct in the wire clock.
	time.Sleep(25 * time.Millisecond)
	referenceSend(t, conn, reactionPass(first))
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != true {
		t.Fatalf("partial response failed: %v", result)
	}
	updated := readMahjongDecision(t, conn, r.matchID, guiyang.PhaseReaction)
	if updated["action_deadline_ms"] != first["action_deadline_ms"] {
		t.Fatal("checkpoint commit refreshed the reaction deadline")
	}

	// Restore from the committed database row with a fresh room manager.
	fixture.hub.stopping.Store(true)
	recovered := newMahjongHub(matchmaking.NewManager(room.NewManager()))
	recovered.checkpoints = store
	if err := recovered.restore(ctx); err != nil {
		t.Fatal(err)
	}
	resumed := recovered.rooms[r.id]
	if resumed == nil {
		t.Fatal("persisted room missing after restore")
	}
	resumed.mu.Lock()
	defer resumed.mu.Unlock()
	defer resumed.closeLocked()
	resumed.sendSnapshotLocked(fixture.clients[0][1], [4]bool{}, time.Now().UnixMilli())
	state := readMahjongDecision(t, conn, r.matchID, guiyang.PhaseReaction)
	if state["action_window_id"] == nil || state["action_window_id"] != first["action_window_id"] ||
		state["action_deadline_ms"] != first["action_deadline_ms"] || state["epoch"] != updated["epoch"] {
		t.Fatalf("restoration changed the live decision: initial=%v/%v restored=%v/%v", first["action_window_id"], first["action_deadline_ms"], state["action_window_id"], state["action_deadline_ms"])
	}
	if len(resumed.game.Options(1)) != 0 || len(resumed.game.Options(2)) == 0 {
		t.Fatal("restoration lost which seats still need to respond")
	}
}

func TestMahjongDecisionWindowRejectsExpiredResponseBeforeTimerRuns(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	r := stageReactionDecision(fixture, nil, time.Now().UTC())
	conn := fixture.connections[0][1]
	state := readMahjongDecision(t, conn, r.matchID, guiyang.PhaseReaction)
	r.mu.Lock()
	r.timer.Stop()
	r.decisionStart = time.Now().UTC().Add(-mahjongReactionTimeout)
	r.mu.Unlock()

	referenceSend(t, conn, reactionPass(state))
	if result := lobbyRead(t, conn, "mahjong_action_result", nil); result["ok"] != false {
		t.Fatal("late response was accepted while the timeout callback was pending")
	}
	r.mu.Lock()
	_, submitted := r.game.Submitted[1]
	r.scheduleTimeoutLocked(fixture.hub)
	r.mu.Unlock()
	if submitted {
		t.Fatal("late response changed the authority state")
	}
	next := readMahjongDecision(t, conn, r.matchID, guiyang.PhaseTurn)
	remaining := next["action_deadline_ms"].(float64) - next["server_now_ms"].(float64)
	if next["action_window_id"] == state["action_window_id"] || remaining < 14000 || remaining > 15000 {
		t.Fatal("timeout failed to advance the decision and start the next turn clock")
	}
}

func TestMahjongDecisionWindowIgnoresSupersededTimer(t *testing.T) {
	fixture := referenceMahjongServer(t, 1, 4)
	r := stageReactionDecision(fixture, nil, time.Now().UTC())
	r.mu.Lock()
	epoch, start := r.game.Epoch, r.decisionStart
	r.decisionStart = time.Now().UTC().Add(-mahjongReactionTimeout)
	r.scheduleTimeoutLocked(fixture.hub)
	// Hold the room lock until the old callback has been dispatched. Its epoch
	// still matches, so the callback must validate the scheduled timer itself.
	time.Sleep(25 * time.Millisecond)
	if r.timer.Stop() {
		r.mu.Unlock()
		t.Fatal("test setup did not dispatch the old timeout")
	}
	r.decisionStart = start
	r.scheduleTimeoutLocked(fixture.hub)
	r.mu.Unlock()

	time.Sleep(25 * time.Millisecond)
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.game.Epoch != epoch || r.game.Phase != guiyang.PhaseReaction {
		t.Fatal("superseded timer resolved the live decision")
	}
}

func stageReactionDecision(fixture *mahjongReferenceFixture, store mahjongCheckpointStore, when time.Time) *mahjongRoom {
	r := fixture.hub.rooms[fixture.rooms[0]]
	r.mu.Lock()
	defer r.mu.Unlock()
	fixture.hub.checkpoints = store
	game := r.game
	tile := game.Hands[0][0]
	game.Hands[0] = game.Hands[0][1:]
	game.Discards = append(game.Discards, guiyang.Discard{Seat: 0, Tile: tile})
	game.Phase = guiyang.PhaseReaction
	game.Epoch++
	game.PendingTile, game.PendingFrom, game.PendingKind = tile, 0, "discard"
	game.Candidates = map[int][]string{1: {"hu"}, 2: {"hu"}, 3: {"peng"}}
	game.Submitted = map[int]string{}
	r.commitLocked(fixture.hub, game, when, nil, mahjongCommand{}, func() {})
	return r
}

func reactionPass(state map[string]any) map[string]any {
	packet := map[string]any{"type": "mahjong_action", "match_id": state["match_id"], "command_id": "pass", "action": "pass"}
	if id, present := state["action_window_id"]; present {
		packet["action_window_id"] = id
	}
	return packet
}

func readMahjongDecision(t *testing.T, conn *websocket.Conn, matchID string, phase string) map[string]any {
	t.Helper()
	return lobbyRead(t, conn, "mahjong_state", func(state map[string]any) bool {
		return state["match_id"] == matchID && state["phase"] == phase && state["status"] == "playing"
	})
}
