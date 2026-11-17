package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	adminplatform "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/admin"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/ai"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongactive"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjonghistory"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongmoderation"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongrooms"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// Server（HTTP服务）聚合一期API。业务规则留在service/engine层。
type Server struct {
	cfg             config.Config
	db              *pgxpool.Pool
	redis           *redis.Client
	accounts        accountSessions
	passwordAuth    passwordAuthLimiter
	wallets         *wallet.Service
	rooms           *room.Manager
	ai              *ai.Service
	chess           *chessHub
	mahjong         *mahjongHub
	mahjongHistory  mahjongHistoryReader
	landlord        *landlordHub
	guandan         *guandanHub
	admin           adminReader
	adminPrincipals []adminPrincipal
	adminReviews    adminMahjongReviews
	monitor         *monitorSignal
	matchmaking     *matchmaking.Manager
	upgrader        websocket.Upgrader
	socketsMu       sync.Mutex
	sockets         map[*websocket.Conn]authenticatedPlayerSocket
	draining        bool
}

// New（创建HTTP处理器）注册一期基础API与WebSocket入口。
func New(cfg config.Config, db *pgxpool.Pool, redisClient *redis.Client) http.Handler {
	return newServer(cfg, db, redisClient, account.NewService(db))
}

func NewRestored(ctx context.Context, cfg config.Config, db *pgxpool.Pool, redisClient *redis.Client) (*Runtime, error) {
	principals, err := loadAdminCredentials(cfg.AdminCredentialFile)
	if err != nil {
		return nil, err
	}
	s := buildServer(cfg, db, redisClient, account.NewService(db))
	s.adminPrincipals = principals
	s.mahjong.checkpoints = mahjongactive.NewService(db)
	s.mahjong.friendStore = mahjongrooms.NewService(db)
	s.mahjong.moderation = mahjongmoderation.NewService(db)
	s.adminReviews = mahjongmoderation.NewService(db)
	if err := s.mahjong.restore(ctx); err != nil {
		return nil, err
	}
	return &Runtime{Handler: s.routes(), server: s}, nil
}

func newServer(cfg config.Config, db *pgxpool.Pool, redisClient *redis.Client, accounts accountSessions) http.Handler {
	return buildServer(cfg, db, redisClient, accounts).routes()
}

func buildServer(cfg config.Config, db *pgxpool.Pool, redisClient *redis.Client, accounts accountSessions) *Server {
	roomManager := room.NewManager()
	matchManager := matchmaking.NewManager(roomManager)
	mahjongMatches := matchmaking.NewManager(roomManager)
	s := &Server{
		cfg: cfg, db: db, redis: redisClient,
		accounts: accounts, wallets: wallet.NewService(db),
		rooms: roomManager, ai: ai.NewService(), chess: newChessHub(matchManager), mahjong: newMahjongHub(mahjongMatches), landlord: newLandlordHub(matchManager), guandan: newGuandanHub(matchManager),
		admin:       adminplatform.NewService(db, roomManager),
		matchmaking: matchManager,
		upgrader:    websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }},
		monitor:     newMonitorSignal(),
	}
	s.mahjong.monitor = s.monitor
	s.chess.monitor = s.monitor
	s.landlord.monitor = s.monitor
	s.guandan.monitor = s.monitor
	if db != nil {
		s.mahjong.seatWallets = s.wallets.GetFamilyEggProfiles
		history := mahjonghistory.NewService(db)
		s.mahjong.settlementEggDeltas = history.EggDeltas
		s.mahjongHistory = history
		s.mahjong.recordHistory = history.Save
		s.mahjong.saveHistory = history.SaveTx
	}
	return s
}

func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.health)
	mux.HandleFunc("/api/v1/catalog", s.catalog)
	mux.HandleFunc("/api/v1/auth/guest", s.guestLogin)
	mux.HandleFunc("POST /api/v1/auth/register", s.passwordRegister)
	mux.HandleFunc("POST /api/v1/auth/login", s.passwordLogin)
	mux.HandleFunc("/api/v1/auth/session", s.authSession)
	mux.HandleFunc("POST /api/v1/auth/logout", s.authLogout)
	mux.HandleFunc("POST /api/v1/auth/delete-request", s.authDeleteRequest)
	mux.HandleFunc("/api/v1/mahjong/ws", s.mahjongWebSocket)
	mux.HandleFunc("/api/v1/mahjong/history", s.listMahjongHistory)
	mux.HandleFunc("/api/v1/mahjong/history/", s.mahjongHistoryDetail)
	mux.HandleFunc("/api/v1/wallet", s.wallet)
	mux.HandleFunc("/api/v1/rooms", s.roomsHandler)
	mux.HandleFunc("/api/v1/matchmaking/quick", s.quickMatch)
	mux.HandleFunc("/api/v1/matchmaking/ready", s.roomReady)
	mux.HandleFunc("/api/v1/matchmaking/cancel", s.cancelMatch)
	mux.HandleFunc("/api/v1/ai/capabilities", s.aiCapabilities)
	mux.HandleFunc("/api/v1/admin/session", s.adminSession)
	mux.HandleFunc("GET /api/v1/admin/wallet/eggs/player", s.lookupAdminEggPlayer)
	mux.HandleFunc("POST /api/v1/admin/wallet/eggs/grant", s.grantAdminEggs)
	mux.HandleFunc("GET /api/v1/admin/monitor/snapshot", s.adminRead(s.adminMonitorSnapshot))
	mux.HandleFunc("GET /api/v1/admin/monitor/stream", s.adminRead(s.adminMonitorStream))
	mux.HandleFunc("/api/v1/admin/mahjong/reports", s.adminMahjongReports)
	mux.HandleFunc("POST /api/v1/admin/mahjong/reports/{id}/resolve", s.resolveAdminMahjongReport)
	mux.HandleFunc("POST /api/v1/admin/mahjong/rooms/{id}/admission", s.adminSetMahjongRoomAdmission)
	mux.HandleFunc("GET /api/v1/admin/mahjong/rooms/{id}/operations", s.adminRead(s.adminMahjongRoomOperations))
	mux.HandleFunc("/api/v1/admin/overview", s.adminRead(s.adminOverview))
	mux.HandleFunc("/api/v1/admin/users", s.adminRead(s.adminUsers))
	mux.HandleFunc("/api/v1/admin/rooms", s.adminRead(s.adminRooms))
	mux.HandleFunc("/api/v1/admin/rooms/", s.adminRead(s.adminRoomRoute))
	mux.HandleFunc("/api/v1/admin/matches", s.adminRead(s.adminMatches))
	mux.HandleFunc("/api/v1/admin/matches/", s.adminRead(s.adminMatchRoute))
	mux.HandleFunc("/ws", s.websocket)
	return cors(mux)
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	if s.mahjong != nil && s.mahjong.stopping.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"service": "draining"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	status := map[string]any{"service": "ok", "postgres": "ok", "redis": "ok", "time": time.Now().UTC()}
	code := http.StatusOK
	if s.db == nil || s.db.Ping(ctx) != nil {
		status["postgres"] = "unavailable"
		code = http.StatusServiceUnavailable
	}
	if s.redis == nil || s.redis.Ping(ctx).Err() != nil {
		status["redis"] = "unavailable"
		code = http.StatusServiceUnavailable
	}
	if code != http.StatusOK {
		status["service"] = "unavailable"
	}
	writeJSON(w, code, status)
}
func (s *Server) catalog(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"games": game.Catalog()})
}
func (s *Server) roomsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{"rooms": s.rooms.List()})
	case http.MethodPost:
		if _, ok := s.requireSession(w, r); !ok {
			return
		}
		var req room.CreateRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "请求体不是合法JSON")
			return
		}
		if req.GameID == string(domain.GameMahjong) || req.ProductID == string(domain.ProductMahjong) {
			writeError(w, http.StatusBadRequest, "请从麻将大厅创建房间")
			return
		}
		created, err := s.rooms.Create(req)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		s.monitor.notify()
		writeJSON(w, http.StatusCreated, created)
	default:
		writeError(w, http.StatusMethodNotAllowed, "不支持的方法")
	}
}
func (s *Server) aiCapabilities(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.ai.Capabilities())
}
func (s *Server) websocket(w http.ResponseWriter, r *http.Request) {
	conn, session, ok := s.upgradePlayerSocket(w, r)
	if !ok {
		return
	}
	defer s.removePlayerSocket(conn)
	defer conn.Close()
	expiry := closeSocketAtExpiry(conn, session.ExpiresAt)
	defer expiry.Stop()
	// A five-second 16kHz mono voice clip needs at most 214kB of base64.
	// Bound the websocket frame before JSON allocation for every sub-protocol.
	conn.SetReadLimit(256 << 10)
	client := newChessClient(conn)
	defer s.chess.disconnect(client)
	landlordClient := newLandlordClient(client)
	defer s.landlord.disconnect(landlordClient)
	guandanClient := newGuandanClient(client)
	defer s.guandan.disconnect(guandanClient)
	_ = client.writeJSON(map[string]any{"type": "connected", "message": "小板凳实时连接已建立"})
	for {
		var message map[string]any
		if err := conn.ReadJSON(&message); err != nil {
			return
		}
		if !time.Now().Before(session.ExpiresAt) {
			return
		}
		kind, _ := message["type"].(string)
		switch kind {
		case "chess_join", "landlord_join", "guandan_join":
			if message["client_id"] != session.AccountID {
				_ = client.writeJSON(map[string]any{
					"type": strings.TrimSuffix(kind, "_join") + "_error", "code": "account_mismatch",
					"message": "账号与当前登录会话不符",
				})
				continue
			}
		}
		// 象棋实时子协议由服务端权威房间消费；其他一期消息仍保留通用ACK便于后续扩展。
		if s.chess.handle(client, message) {
			continue
		}
		if strings.HasPrefix(kind, "mahjong_") {
			_ = client.writeJSON(map[string]any{"type": "mahjong_error", "message": "请通过已登录的麻将专用连接入座"})
			continue
		}
		if s.landlord.handle(landlordClient, message) {
			continue
		}
		if s.guandan.handle(guandanClient, message) {
			continue
		}
		_ = client.writeJSON(map[string]any{"type": "ack", "payload": message})
	}
}
func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{"error": message})
}
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
