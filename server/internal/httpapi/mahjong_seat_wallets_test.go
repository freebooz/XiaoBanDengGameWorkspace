package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

func TestMahjongSeatWalletsAreParticipantScopedAndRefresh(t *testing.T) {
	url := os.Getenv("XBD_MAHJONG_PRIVACY_TEST_POSTGRES_URL")
	if url == "" {
		t.Skip("requires isolated PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	db, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatal("could not connect to isolated Mahjong wallet database")
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	accounts := account.NewService(db)
	s := buildServer(config.Config{}, db, nil, accounts)
	adminToken, operator := eggWalletToken(t, "seat-wallet-operator", adminGrantEggs)
	s.adminPrincipals = []adminPrincipal{operator}
	var queries atomic.Int32
	s.mahjong.seatWallets = func(ctx context.Context, ids []string) (map[string]wallet.EggProfile, error) {
		queries.Add(1)
		return s.wallets.GetFamilyEggProfiles(ctx, ids)
	}
	handler := s.routes()
	endpoint := httptest.NewServer(handler)
	defer endpoint.Close()

	var players [4]restartGuest
	var lobby, board [4]*websocket.Conn
	wantNames := make([]any, 4)
	for seat := range players {
		guest, err := accounts.CreateGuest(ctx)
		if err != nil {
			t.Fatal(err)
		}
		players[seat], wantNames[seat] = restartGuest{ID: guest.AccountID, Token: guest.Token}, guest.DisplayName
		lobby[seat] = subscribeFriendRestartLobby(t, endpoint.URL, players[seat])
		lobbyState(t, lobby[seat], "idle", 0, 0)
	}
	// Keep a valid legacy player account with no egg row and an earlier currency.
	if _, err := db.Exec(ctx, `DELETE FROM wallet_accounts WHERE account_id=$1 AND asset_id=$2 AND scope=$3`, players[1].ID, wallet.EggAssetID, wallet.FamilyScope); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `INSERT INTO wallet_accounts(account_id,asset_id,scope,balance) VALUES($1,'xbd_point','family',999)`, players[1].ID); err != nil {
		t.Fatal(err)
	}
	assertProjection := func(state map[string]any, eggs []any) {
		t.Helper()
		if !reflect.DeepEqual(state["egg_counts"], eggs) || !reflect.DeepEqual(state["player_names"], wantNames) {
			t.Fatalf("wrong seat profiles: egg_counts=%v player_names=%v", state["egg_counts"], state["player_names"])
		}
	}

	lobbyCommand(t, lobby[0], "create", "", "guiyang", "2.0.0", true)
	roomID := lobbyState(t, lobby[0], "waiting", 1, 0)["room_id"].(string)
	for seat := 1; seat < 4; seat++ {
		lobbyCommand(t, lobby[seat], "join", roomID, "", "", true)
	}
	for _, conn := range lobby {
		lobbyCommand(t, conn, "ready", roomID, "", "", true)
	}
	outsider := loadRestartGuest(t, endpoint.URL, "")
	outsiderBoard := restartSocket(t, endpoint.URL, outsider)
	referenceSend(t, outsiderBoard, map[string]any{"type": "mahjong_join", "room_id": roomID})
	if denial := lobbyRead(t, outsiderBoard, "mahjong_error", nil); denial["operation"] != "join" || denial["egg_counts"] != nil || denial["player_names"] != nil {
		t.Fatal("outsider must not receive seat profiles")
	}

	for seat, player := range players {
		board[seat] = joinRestartBoard(t, endpoint.URL, player, roomID, "", seat)
	}
	wantEggs := []any{float64(100), float64(0), float64(100), float64(100)}
	var initial [4]map[string]any
	for seat, conn := range board {
		initial[seat] = lobbyRead(t, conn, "mahjong_state", func(state map[string]any) bool { return state["status"] == "playing" })
		assertProjection(initial[seat], wantEggs)
	}
	if queries.Load() != 1 {
		t.Fatalf("first four connections made %d wallet queries, want one", queries.Load())
	}
	matchID := initial[0]["match_id"].(string)
	board[2] = joinRestartBoard(t, endpoint.URL, players[2], roomID, matchID, 2)
	assertProjection(lobbyRead(t, board[2], "mahjong_state", nil), wantEggs)
	if queries.Load() != 2 {
		t.Fatalf("reconnect made %d total wallet queries, want two", queries.Load())
	}

	grant := wallet.EggGrant{DisplayName: wantNames[0].(string), Amount: 25, RequestID: uuid.New()}
	if code := eggWalletRequest(handler, http.MethodPost, eggGrantPath, adminToken, grant).Code; code != http.StatusOK {
		t.Fatalf("admin grant returned %d", code)
	}
	wantEggs[0] = float64(125)
	for _, conn := range board {
		refreshed := lobbyRead(t, conn, "mahjong_state", func(state map[string]any) bool {
			return reflect.DeepEqual(state["egg_counts"], wantEggs)
		})
		assertProjection(refreshed, wantEggs)
		if refreshed["match_id"] != matchID || refreshed["epoch"] != initial[0]["epoch"] {
			t.Fatal("wallet update altered gameplay identity or epoch")
		}
	}
	turn := int(initial[0]["turn"].(float64))
	tile := initial[turn]["hand"].([]any)[0].(map[string]any)["id"]
	referenceSend(t, board[turn], restartAction(roomID, matchID, "seat-wallet-discard", "play", tile))
	waitRestartAction(t, board[turn], "seat-wallet-discard")
	assertProjection(lobbyRead(t, board[turn], "mahjong_state", func(state map[string]any) bool {
		return state["epoch"].(float64) > initial[0]["epoch"].(float64)
	}), wantEggs)
	if queries.Load() != 3 {
		t.Fatalf("normal gameplay made an unexpected wallet query: got %d total, want initial/reconnect/grant only", queries.Load())
	}
}

func TestMahjongSeatWalletUnknownValuesAreNullable(t *testing.T) {
	room := &mahjongRoom{seatProfiles: [4]mahjongSeatProfile{{
		EggProfile: wallet.EggProfile{DisplayName: "田里阿福"}, known: true,
	}}}
	state := map[string]any{}
	room.addSeatProfilesLocked(state)
	encoded, err := json.Marshal(state)
	if err != nil || string(encoded) != `{"egg_counts":[0,null,null,null],"player_names":["田里阿福",null,null,null]}` {
		t.Fatalf("zero or unavailable profiles encoded incorrectly: %s (%v)", encoded, err)
	}
}
