package httpapi

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
)

// The real PostgreSQL server commits the final transaction, but the API never
// receives its COMMIT acknowledgement. The API is killed before it can publish
// any terminal board state, and a fresh API process recovers from the database.
func TestMahjongSettlementCommittedBeforePublicationSurvivesCrash(t *testing.T) {
	checkMahjongSettlementCommitCrash(t, false)
}

func TestMahjongLostPostgresActionReplyReconcilesCommittedDiscard(t *testing.T) {
	checkMahjongSettlementCommitCrash(t, true)
}

func checkMahjongSettlementCommitCrash(t *testing.T, checkActionReply bool) {
	t.Helper()
	if os.Getenv("XBD_MAHJONG_TEST_COMMIT_CRASH") != "1" {
		t.Skip("set XBD_MAHJONG_TEST_COMMIT_CRASH=1 and the disposable restart API/DB endpoints")
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
	proxy := newSettlementCommitProxy(t, postgres.Host)
	proxiedPostgres := *postgres
	proxiedPostgres.Host = proxy.listener.Addr().String()
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
	first := launchRestartAPI(t, binary, endpoint, append(apiEnv, "POSTGRES_URL="+proxiedPostgres.String()))
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
	board, states, matchID := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	if checkActionReply {
		playWithLostPostgresActionReply(t, proxy, board, states, roomID, matchID)
		return
	}
	proxy.arm()
	moves := playUntilSettlementCommit(t, proxy, first, board, states, roomID, matchID)
	verifySettlementDatabaseRows(t, postgres.String(), matchID)
	wantEggs, wantDeltas := verifySettlementWalletRows(t, postgres.String(), matchID)
	second := launchRestartAPI(t, binary, endpoint, append(apiEnv, "POSTGRES_URL="+postgres.String()))
	if first.cmd.Process.Pid == second.cmd.Process.Pid {
		t.Fatal("expected a fresh API process after the committed settlement")
	}
	var terminal map[string]any
	for seat, guest := range guests {
		if loadRestartGuest(t, endpoint, guest.Token).ID != guest.ID {
			t.Fatalf("seat %d did not recover its original identity", seat)
		}
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint, guest)
		state := lobbyState(t, lobby[seat], "matched", 4, 0)
		verifyFriendRestartLobby(t, state, guests, roomID, seat, 1, matchID, []any{}, options)
		conn := joinRestartBoard(t, endpoint, guest, roomID, matchID, seat)
		settled := lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return msg["status"] == "finished" })
		verifyRestartIdentity(t, settled, guests, roomID, matchID, seat, options)
		if settled["can_rematch"] != true || settled["epoch"].(float64) <= states[seat]["epoch"].(float64) {
			t.Fatalf("seat %d did not recover the committed final epoch", seat)
		}
		if !reflect.DeepEqual(settled["egg_counts"], wantEggs) || !reflect.DeepEqual(settled["egg_deltas"], wantDeltas) {
			t.Fatalf("seat %d did not recover committed eggs after lost COMMIT reply", seat)
		}
		if seat == 0 {
			terminal = settled
		}
		for _, field := range []string{"scores", "score_breakdown", "reason", "discards", "winners"} {
			if !reflect.DeepEqual(terminal[field], settled[field]) {
				t.Fatalf("seat %d recovered an inconsistent settlement %s", seat, field)
			}
		}
	}
	verifyRestartedFriendHistory(t, endpoint, guests, matchID, terminal)
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	rematch, initial, nextMatch := startFriendRestartRound(t, endpoint, guests, roomID, "", options)
	if nextMatch == matchID {
		t.Fatal("rematch reused the recovered match ID")
	}
	for _, state := range initial {
		if !reflect.DeepEqual(state["egg_counts"], wantEggs) || state["egg_deltas"] != nil {
			t.Fatal("rematch wallet changed after committed crash recovery")
		}
	}
	seat, kind, tile := chooseFriendRestartAction(initial)
	if seat < 0 {
		t.Fatal("rematch has no legal action")
	}
	referenceSend(t, rematch[seat], restartAction(roomID, nextMatch, "after-settlement-crash", kind, tile))
	waitRestartAction(t, rematch[seat], "after-settlement-crash")
	verifySettlementDatabaseRows(t, postgres.String(), matchID)
	verifySettlementWalletRows(t, postgres.String(), matchID)
	t.Logf("MAHJONG_SETTLEMENT_COMMIT_CRASH_OK first_pid=%d second_pid=%d room=%s match=%s next_match=%s actions=%d restored_seats=4",
		first.cmd.Process.Pid, second.cmd.Process.Pid, roomID, matchID, nextMatch, moves)
}

func playWithLostPostgresActionReply(t *testing.T, proxy *settlementCommitProxy, board [4]*websocket.Conn, states [4]map[string]any, roomID, matchID string) {
	t.Helper()
	turn := int(states[0]["turn"].(float64))
	tile := states[turn]["hand"].([]any)[0].(map[string]any)["id"]
	const id = "lost-postgres-discard-reply"
	command := restartAction(roomID, matchID, id, "play", tile)
	proxy.armAction()
	referenceSend(t, board[turn], command)
	accepted := waitRestartAction(t, board[turn], id)
	select {
	case <-proxy.actionLost:
	default:
		t.Fatal("API accepted action without the intended suppressed PostgreSQL response")
	}
	for seat, conn := range board {
		states[seat] = lobbyRead(t, conn, "mahjong_state", func(msg map[string]any) bool { return restartHasDiscard(msg, turn, tile) })
		if len(states[seat]["discards"].([]any)) != 1 {
			t.Fatalf("seat %d saw duplicate or missing discard after lost reply", seat)
		}
	}
	referenceSend(t, board[turn], command)
	if replay := waitRestartAction(t, board[turn], id); !reflect.DeepEqual(replay, accepted) {
		t.Fatal("replaying the action after a lost database reply changed its acknowledgement")
	}
	referenceSend(t, board[turn], map[string]any{"type": "mahjong_join", "room_id": roomID, "match_id": matchID})
	lobbyRead(t, board[turn], "mahjong_joined", nil)
	compareRestartTable(t, states[turn], lobbyRead(t, board[turn], "mahjong_state", nil), turn)
	t.Log("MAHJONG_POSTGRES_ACTION_REPLY_LOST_OK committed_discard=1 same_ack=true")
}

func playUntilSettlementCommit(t *testing.T, proxy *settlementCommitProxy, api *restartTestAPI, board [4]*websocket.Conn, states [4]map[string]any, roomID, matchID string) int {
	t.Helper()
	for step := 1; step <= 120; step++ {
		seat, kind, tile := chooseFriendRestartAction(states)
		if seat < 0 {
			t.Fatal("active round has no legal action")
		}
		id := fmt.Sprintf("commit-crash-%d", step)
		conn := board[seat]
		referenceSend(t, conn, restartAction(roomID, matchID, id, kind, tile))
		type actionRead struct {
			transport error
			protocol  error
		}
		read := make(chan actionRead, 1)
		go func() {
			if err := conn.SetReadDeadline(time.Now().Add(4 * time.Second)); err != nil {
				read <- actionRead{protocol: err}
				return
			}
			for {
				var msg map[string]any
				if err := conn.ReadJSON(&msg); err != nil {
					read <- actionRead{transport: err}
					return
				}
				if msg["type"] == "mahjong_action_result" || msg["type"] == "mahjong_error" {
					if msg["command_id"] != id || msg["ok"] != true {
						read <- actionRead{protocol: fmt.Errorf("action %d was rejected", step)}
					} else {
						read <- actionRead{}
					}
					return
				}
				if msg["type"] == "mahjong_state" && msg["status"] == "finished" {
					read <- actionRead{protocol: fmt.Errorf("API published settlement before PostgreSQL replied")}
					return
				}
			}
		}()
		select {
		case <-proxy.committed:
			api.stop(t)
			result := <-read
			if result.protocol != nil {
				t.Fatal(result.protocol)
			}
			if result.transport == nil {
				t.Fatal("API acknowledged the settlement before receiving PostgreSQL COMMIT reply")
			}
			for peer, other := range board {
				if peer == seat {
					continue
				}
				other.SetReadDeadline(time.Now().Add(time.Second))
				for {
					var msg map[string]any
					if err := other.ReadJSON(&msg); err != nil {
						break
					}
					if msg["status"] == "finished" {
						t.Fatalf("seat %d got settlement before crash", peer)
					}
				}
			}
			return step
		case result := <-read:
			if result.protocol != nil || result.transport != nil {
				t.Fatalf("waiting for action or gated commit: %v %v", result.protocol, result.transport)
			}
		}
		for peer, other := range board {
			epoch := states[peer]["epoch"].(float64)
			states[peer] = lobbyRead(t, other, "mahjong_state", func(msg map[string]any) bool { return msg["epoch"].(float64) > epoch })
		}
	}
	t.Fatal("no settlement transaction observed after 120 legal actions")
	return 0
}

func verifySettlementDatabaseRows(t *testing.T, pgURL, matchID string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, pgURL)
	if err != nil {
		t.Fatal("could not connect directly to disposable PostgreSQL to verify commit")
	}
	defer conn.Close(ctx)
	var completion, active, history, members int
	err = conn.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM mahjong_active_completions WHERE match_id=$1),
		(SELECT count(*) FROM mahjong_active_matches WHERE match_id=$1),
		(SELECT count(*) FROM mahjong_match_results WHERE public_match_id=$2 AND public_replay IS NOT NULL AND score_breakdown IS NOT NULL),
		(SELECT count(*) FROM mahjong_match_members p JOIN mahjong_match_results r USING(match_id) WHERE r.public_match_id=$2)`, matchID, matchID).Scan(&completion, &active, &history, &members)
	if err != nil {
		t.Fatalf("read committed Mahjong row counts: %v", err)
	}
	if completion != 1 || active != 0 || history != 1 || members != 4 {
		t.Fatalf("settlement did not commit exactly once: completion=%d active=%d history=%d members=%d", completion, active, history, members)
	}
}

func verifySettlementWalletRows(t *testing.T, pgURL, matchID string) ([]any, []any) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, pgURL)
	if err != nil {
		t.Fatal("could not inspect isolated settlement wallets")
	}
	defer conn.Close(ctx)
	rows, err := conn.Query(ctx, `SELECT p.seat,l.delta,w.balance FROM mahjong_match_results r
		JOIN mahjong_match_members p USING(match_id) JOIN wallet_ledger l ON l.account_id=p.account_id AND l.reference_id=r.public_match_id
		AND l.reason='mahjong_settlement_eggs' AND l.asset_id='xbd_egg' AND l.scope='family'
		JOIN wallet_accounts w ON w.account_id=l.account_id AND w.asset_id=l.asset_id AND w.scope=l.scope
		WHERE r.public_match_id=$1 ORDER BY p.seat`, matchID)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var eggs, deltas []any
	var total int64
	for rows.Next() {
		var seat int
		var delta, balance int64
		if err := rows.Scan(&seat, &delta, &balance); err != nil {
			t.Fatal(err)
		}
		if seat != len(eggs) || balance < 0 || balance != 100+delta {
			t.Fatalf("invalid committed wallet seat=%d balance=%d delta=%d", seat, balance, delta)
		}
		eggs = append(eggs, float64(balance))
		deltas = append(deltas, float64(delta))
		total += delta
	}
	if rows.Err() != nil || len(eggs) != 4 || total != 0 {
		t.Fatalf("crash settlement ledger count=%d sum=%d err=%v", len(eggs), total, rows.Err())
	}
	return eggs, deltas
}

type settlementCommitProxy struct {
	listener    net.Listener
	mu          sync.Mutex
	active      map[net.Conn]net.Conn
	armed       bool
	actionArmed bool
	actionLost  chan struct{}
	committed   chan struct{}
	closed      chan struct{}
	workers     sync.WaitGroup
}

func newSettlementCommitProxy(t *testing.T, upstream string) *settlementCommitProxy {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := &settlementCommitProxy{listener: listener, active: make(map[net.Conn]net.Conn), committed: make(chan struct{}), actionLost: make(chan struct{}), closed: make(chan struct{})}
	p.workers.Add(1)
	go func() {
		defer p.workers.Done()
		for {
			client, err := listener.Accept()
			if err != nil {
				return
			}
			server, err := net.DialTimeout("tcp", upstream, time.Second)
			if err != nil {
				client.Close()
				continue
			}
			p.mu.Lock()
			select {
			case <-p.closed:
				p.mu.Unlock()
				client.Close()
				server.Close()
				return
			default:
			}
			p.active[client] = server
			p.workers.Add(1)
			p.mu.Unlock()
			go p.forward(client, server)
		}
	}()
	t.Cleanup(func() {
		listener.Close()
		p.mu.Lock()
		close(p.closed)
		for client, server := range p.active {
			client.Close()
			server.Close()
		}
		p.mu.Unlock()
		p.workers.Wait()
	})
	return p
}

func (p *settlementCommitProxy) arm() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.armed = true
}

func (p *settlementCommitProxy) armAction() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.actionArmed = true
}

func (p *settlementCommitProxy) holdAction() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	armed := p.actionArmed
	p.actionArmed = false
	return armed
}

func (p *settlementCommitProxy) holdCommit() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !p.armed {
		return false
	}
	p.armed = false
	close(p.committed)
	return true
}

func (p *settlementCommitProxy) forward(client, server net.Conn) {
	defer p.workers.Done()
	defer func() {
		p.mu.Lock()
		delete(p.active, client)
		p.mu.Unlock()
	}()
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = io.Copy(server, client)
		client.Close()
		server.Close()
	}()
	defer func() {
		client.Close()
		server.Close()
		<-done
	}()
	var header [5]byte
	holdAction := false
	for {
		if _, err := io.ReadFull(server, header[:]); err != nil {
			return
		}
		length := binary.BigEndian.Uint32(header[1:])
		if length < 4 || length > 16<<20 {
			return
		}
		payload := make([]byte, length-4)
		if _, err := io.ReadFull(server, payload); err != nil {
			return
		}
		if header[0] == 'C' && string(payload) == "COMMIT\x00" && p.holdCommit() {
			// Keep API's socket open so EOF cannot trigger a successful retry
			// before the test kills the API. The sender exits when it is killed.
			<-done
			return
		}
		if header[0] == 'C' && string(payload) == "UPDATE 1\x00" && p.holdAction() {
			holdAction = true
		}
		if holdAction {
			if header[0] == 'Z' && string(payload) == "I" {
				// The implicit transaction is complete. Drop this connection
				// before the API sees the response and let it reconcile by SQL.
				close(p.actionLost)
				return
			}
			continue
		}
		if _, err := client.Write(header[:]); err != nil {
			return
		}
		if _, err := client.Write(payload); err != nil {
			return
		}
	}
}
