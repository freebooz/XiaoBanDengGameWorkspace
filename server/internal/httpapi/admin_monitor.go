package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

const (
	monitorCoalesceFor    = 250 * time.Millisecond
	monitorHealthEvery    = 5 * time.Second
	monitorHeartbeatEvery = 15 * time.Second
	monitorMaxStreams     = 16
)

// The game can mark the view stale without allocating, reading room state or
// waiting for any monitor client to catch up.
type monitorSignal struct {
	mu       sync.Mutex
	wake     map[chan struct{}]struct{}
	done     chan struct{}
	stopped  bool
	healthMu sync.Mutex
	health   [3]monitorService
}

func newMonitorSignal() *monitorSignal {
	return &monitorSignal{wake: make(map[chan struct{}]struct{}), done: make(chan struct{})}
}

func (m *monitorSignal) notify() {
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for listener := range m.wake {
		select {
		case listener <- struct{}{}:
		default:
		}
	}
}

func (m *monitorSignal) subscribe() (chan struct{}, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.stopped || len(m.wake) >= monitorMaxStreams {
		return nil, false
	}
	wake := make(chan struct{}, 1)
	m.wake[wake] = struct{}{}
	return wake, true
}

func (m *monitorSignal) unsubscribe(wake chan struct{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.wake, wake)
}

func (m *monitorSignal) stop() {
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.stopped {
		m.stopped = true
		close(m.done)
	}
}

type monitorService struct {
	ID        string    `json:"id"`
	Status    string    `json:"status"`
	CheckedAt time.Time `json:"checked_at"`
}

func (s *Server) monitorServices(requestCtx context.Context) [3]monitorService {
	s.monitor.healthMu.Lock()
	defer s.monitor.healthMu.Unlock()
	if cached := s.monitor.health; time.Since(cached[0].CheckedAt) < monitorHealthEvery {
		return cached
	}
	ctx, cancel := context.WithTimeout(requestCtx, 2*time.Second)
	defer cancel()
	postgresReady := make(chan bool, 1)
	go func() { postgresReady <- s.db != nil && s.db.Ping(ctx) == nil }()
	redisReady := s.redis != nil && s.redis.Ping(ctx).Err() == nil
	services := [3]monitorService{
		{ID: "api", Status: "ok", CheckedAt: time.Now().UTC()},
		{ID: "postgres", Status: monitorAvailable(<-postgresReady), CheckedAt: time.Now().UTC()},
		{ID: "redis", Status: monitorAvailable(redisReady), CheckedAt: time.Now().UTC()},
	}
	if s.mahjong.stopping.Load() {
		services[0].Status = "draining"
	} else if services[1].Status != "ok" || services[2].Status != "ok" {
		services[0].Status = "unavailable"
	}
	if requestCtx.Err() == nil {
		s.monitor.health = services
	}
	return services
}

func monitorAvailable(ok bool) string {
	if ok {
		return "ok"
	}
	return "unavailable"
}

func (s *Server) adminMonitorSnapshot(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.monitorSnapshot(s.monitorServices(r.Context())))
}

func (s *Server) adminMonitorStream(w http.ResponseWriter, r *http.Request) {
	wake, subscribed := s.monitor.subscribe()
	if !subscribed {
		w.Header().Set("Retry-After", "2")
		writeError(w, http.StatusServiceUnavailable, "实时监视连接暂不可用")
		return
	}
	defer s.monitor.unsubscribe(wake)

	controller := http.NewResponseController(w)
	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("X-Accel-Buffering", "no")
	sendSnapshot := func(data monitorSnapshot) error {
		body, err := json.Marshal(data)
		if err != nil {
			return err
		}
		return writeMonitorFrame(w, controller, "event: snapshot\ndata: %s\n\n", body)
	}

	// Subscribe before reading so changes during the initial projection trigger
	// a new frame and can't be lost.
	services := s.monitorServices(r.Context())
	if sendSnapshot(s.monitorSnapshot(services)) != nil {
		return
	}
	heartbeat := time.NewTicker(monitorHeartbeatEvery)
	defer heartbeat.Stop()
	health := time.NewTicker(monitorHealthEvery)
	defer health.Stop()
	timer := time.NewTimer(monitorCoalesceFor)
	timer.Stop()
	defer timer.Stop()
	var changed <-chan time.Time
	for {
		select {
		case <-r.Context().Done():
			return
		case <-s.monitor.done:
			return
		case <-wake:
			if changed == nil {
				timer.Reset(monitorCoalesceFor)
				changed = timer.C
			}
		case <-changed:
			changed = nil
			if sendSnapshot(s.monitorSnapshot(services)) != nil {
				return
			}
		case <-health.C:
			services = s.monitorServices(r.Context())
			// Refresh the probe timestamps and status even while every room is idle.
			if sendSnapshot(s.monitorSnapshot(services)) != nil {
				return
			}
		case <-heartbeat.C:
			if writeMonitorFrame(w, controller, ": heartbeat\n\n") != nil {
				return
			}
		}
	}
}

func writeMonitorFrame(w http.ResponseWriter, controller *http.ResponseController, format string, args ...any) error {
	// Bound a slow reader without carrying a write deadline across idle intervals.
	_ = controller.SetWriteDeadline(time.Now().Add(3 * time.Second))
	defer controller.SetWriteDeadline(time.Time{})
	if _, err := fmt.Fprintf(w, format, args...); err != nil {
		return err
	}
	return controller.Flush()
}
