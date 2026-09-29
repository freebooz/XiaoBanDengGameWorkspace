package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/account"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/ai"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/room"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// Server（HTTP服务）聚合一期API。业务规则留在service/engine层。
type Server struct {
	cfg config.Config
	db *pgxpool.Pool
	redis *redis.Client
	accounts *account.Service
	wallets *wallet.Service
	rooms *room.Manager
	ai *ai.Service
	upgrader websocket.Upgrader
}

// New（创建HTTP处理器）注册一期基础API与WebSocket入口。
func New(cfg config.Config,db *pgxpool.Pool,redisClient *redis.Client) http.Handler {
	s:=&Server{
		cfg:cfg,db:db,redis:redisClient,
		accounts:account.NewService(db),wallets:wallet.NewService(db),
		rooms:room.NewManager(),ai:ai.NewService(),
		upgrader:websocket.Upgrader{CheckOrigin:func(r *http.Request) bool{return true}},
	}
	mux:=http.NewServeMux()
	mux.HandleFunc("/health",s.health)
	mux.HandleFunc("/api/v1/catalog",s.catalog)
	mux.HandleFunc("/api/v1/auth/guest",s.guestLogin)
	mux.HandleFunc("/api/v1/wallet",s.wallet)
	mux.HandleFunc("/api/v1/rooms",s.roomsHandler)
	mux.HandleFunc("/api/v1/ai/capabilities",s.aiCapabilities)
	mux.HandleFunc("/ws",s.websocket)
	return cors(mux)
}

func (s *Server) health(w http.ResponseWriter,r *http.Request) {
	ctx,cancel:=context.WithTimeout(r.Context(),2*time.Second);defer cancel()
	status:=map[string]any{"service":"ok","postgres":"ok","redis":"ok","time":time.Now().UTC()}
	if err:=s.db.Ping(ctx);err!=nil{status["postgres"]=err.Error()}
	if err:=s.redis.Ping(ctx).Err();err!=nil{status["redis"]=err.Error()}
	writeJSON(w,http.StatusOK,status)
}
func (s *Server) catalog(w http.ResponseWriter,r *http.Request){writeJSON(w,http.StatusOK,map[string]any{"games":game.Catalog()})}
func (s *Server) guestLogin(w http.ResponseWriter,r *http.Request){
	if r.Method!=http.MethodPost{writeError(w,http.StatusMethodNotAllowed,"仅支持POST");return}
	info,err:=s.accounts.CreateGuest(r.Context())
	if err!=nil{writeError(w,http.StatusInternalServerError,err.Error());return}
	writeJSON(w,http.StatusCreated,info)
}
func (s *Server) wallet(w http.ResponseWriter,r *http.Request){
	accountID:=r.URL.Query().Get("account_id")
	if accountID==""{writeError(w,http.StatusBadRequest,"缺少account_id");return}
	balance,err:=s.wallets.GetFamilyBalance(r.Context(),accountID)
	if err!=nil{writeError(w,http.StatusInternalServerError,err.Error());return}
	writeJSON(w,http.StatusOK,balance)
}
func (s *Server) roomsHandler(w http.ResponseWriter,r *http.Request){
	switch r.Method{
	case http.MethodGet:
		writeJSON(w,http.StatusOK,map[string]any{"rooms":s.rooms.List()})
	case http.MethodPost:
		var req room.CreateRequest
		if err:=json.NewDecoder(r.Body).Decode(&req);err!=nil{writeError(w,http.StatusBadRequest,"请求体不是合法JSON");return}
		created,err:=s.rooms.Create(req)
		if err!=nil{writeError(w,http.StatusBadRequest,err.Error());return}
		writeJSON(w,http.StatusCreated,created)
	default:
		writeError(w,http.StatusMethodNotAllowed,"不支持的方法")
	}
}
func (s *Server) aiCapabilities(w http.ResponseWriter,r *http.Request){writeJSON(w,http.StatusOK,s.ai.Capabilities())}
func (s *Server) websocket(w http.ResponseWriter,r *http.Request){
	conn,err:=s.upgrader.Upgrade(w,r,nil);if err!=nil{return};defer conn.Close()
	_=conn.WriteJSON(map[string]any{"type":"connected","message":"小板凳实时连接已建立"})
	for{
		var message map[string]any
		if err:=conn.ReadJSON(&message);err!=nil{return}
		_=conn.WriteJSON(map[string]any{"type":"ack","payload":message})
	}
}
func writeJSON(w http.ResponseWriter,status int,data any){w.Header().Set("Content-Type","application/json; charset=utf-8");w.WriteHeader(status);_=json.NewEncoder(w).Encode(data)}
func writeError(w http.ResponseWriter,status int,message string){writeJSON(w,status,map[string]any{"error":message})}
func cors(next http.Handler)http.Handler{
	return http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
		w.Header().Set("Access-Control-Allow-Origin","*")
		w.Header().Set("Access-Control-Allow-Headers","Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Methods","GET,POST,PUT,DELETE,OPTIONS")
		if r.Method==http.MethodOptions{w.WriteHeader(http.StatusNoContent);return}
		next.ServeHTTP(w,r)
	})
}