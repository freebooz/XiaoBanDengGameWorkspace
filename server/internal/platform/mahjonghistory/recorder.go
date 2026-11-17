package mahjonghistory

import (
	"context"
	"errors"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

const pendingResults = 256

// Recorder keeps database write latency out of the room locks. Each Save is
// transactional and safe to retry after an ambiguous commit response.
type Recorder struct {
	pending chan Result
}

func NewRecorder(service *Service) *Recorder {
	recorder := &Recorder{pending: make(chan Result, pendingResults)}
	for range 2 {
		go recorder.run(service.Save)
	}
	return recorder
}

func (r *Recorder) Submit(result Result) {
	select {
	case r.pending <- result:
	default:
		log.Printf("mahjong history queue full; match_id=%s", result.MatchID)
	}
}

func (r *Recorder) run(save func(context.Context, Result) error) {
	for result := range r.pending {
		var err error
		for _, delay := range []time.Duration{0, 250 * time.Millisecond, time.Second, 4 * time.Second, 10 * time.Second} {
			time.Sleep(delay)
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			err = save(ctx, result)
			cancel()
			if err == nil {
				break
			}
			var databaseFailure *pgconn.PgError
			if errors.As(err, &databaseFailure) && len(databaseFailure.Code) >= 2 && databaseFailure.Code[:2] == "23" {
				break // A data integrity violation cannot be repaired by retrying.
			}
		}
		if err != nil {
			log.Printf("mahjong history write failed; match_id=%s", result.MatchID)
		}
	}
}
