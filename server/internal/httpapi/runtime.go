package httpapi

import (
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

// Runtime owns the restored Mahjong state and the lifetime of its connections.
type Runtime struct {
	http.Handler
	server *Server
}

func (r *Runtime) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if req.URL.Path != "/health" && r.server.mahjong.stopping.Load() {
		w.Header().Set("Retry-After", "1")
		writeError(w, http.StatusServiceUnavailable, "服务正在交接，请稍后重试")
		return
	}
	r.Handler.ServeHTTP(w, req)
}

// Drain stops new connections, closes upgraded sockets, and waits for an
// in-flight checkpoint on each room before returning the writer lock.
func (r *Runtime) Drain() {
	s := r.server
	h := s.mahjong
	s.socketsMu.Lock()
	s.draining = true
	h.stopping.Store(true)
	s.monitor.stop()
	for conn := range s.sockets {
		_ = conn.Close()
	}
	s.socketsMu.Unlock()
	h.mu.Lock()
	for _, entry := range h.entries {
		entry.timer.Stop()
	}
	for _, room := range h.rooms {
		room.mu.Lock()
		room.closeLocked()
		room.mu.Unlock()
	}
	h.mu.Unlock()
	h.lobbyMu.Lock()
	for _, seat := range h.waitingDisconnects {
		seat.timer.Stop()
	}
	h.lobbyMu.Unlock()
}

type authenticatedMahjongSocket struct {
	accountID string
	digest    [32]byte
}

func (s *Server) closeMahjongSessions(accountID string, digest *[32]byte) {
	for socket, session := range s.sockets {
		if (accountID == "" || session.accountID == accountID) && (digest == nil || session.digest == *digest) {
			_ = socket.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "session_expired"), time.Now().Add(100*time.Millisecond))
			_ = socket.Close()
		}
	}
}

func (s *Server) removeMahjongSocket(conn *websocket.Conn) {
	s.socketsMu.Lock()
	delete(s.sockets, conn)
	s.socketsMu.Unlock()
}
