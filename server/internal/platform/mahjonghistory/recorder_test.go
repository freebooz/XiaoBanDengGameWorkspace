package mahjonghistory

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestRecorderRetriesTheSameCompletedResult(t *testing.T) {
	recorder := &Recorder{pending: make(chan Result, 1)}
	result := Result{MatchID: "retry-match", Scores: [4]int{-3, 0, 0, 3}, Winners: []int{3}}
	attempts := []Result{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		recorder.run(func(_ context.Context, pending Result) error {
			attempts = append(attempts, pending)
			if len(attempts) == 1 {
				return errors.New("connection dropped before commit was acknowledged")
			}
			return nil
		})
	}()
	recorder.Submit(result)
	close(recorder.pending)
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("recorder did not finish the retry")
	}
	if len(attempts) != 2 || attempts[0].MatchID != result.MatchID || attempts[1].MatchID != result.MatchID || attempts[1].Scores != result.Scores || len(attempts[1].Winners) != 1 || attempts[1].Winners[0] != 3 {
		t.Fatalf("retry changed or discarded the completed result: %+v", attempts)
	}
}
