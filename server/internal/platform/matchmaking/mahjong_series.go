package matchmaking

import (
	"slices"
	"strings"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
)

type MahjongSeriesScore struct {
	AccountID string
	Score     int
}

type MahjongSeries struct {
	Rounds int
	Scores []MahjongSeriesScore
}

func MahjongRotatesDealer(rule guiyang.RuleDescriptor) bool {
	return rule.RuleSet().RotatesDealer()
}

func (a MahjongAssignment) OpeningDealer() int {
	if !MahjongRotatesDealer(a.Rule) || a.CompletedRounds == 0 {
		return -1
	}
	if a.NextDealerAccount == "" {
		return a.NextDealer
	}
	if seat := slices.Index(a.PlayerAccountIDs, a.NextDealerAccount); seat >= 0 {
		return seat
	}
	return 0
}

// NextDealerAfterLeave preserves the incumbent by account as seats compact.
// If the incumbent leaves, the first remaining account takes over immediately.
func (a MahjongAssignment) NextDealerAfterLeave(remaining []string) (int, string) {
	dealer := a.OpeningDealer()
	if dealer < 0 || len(remaining) == 0 {
		return 0, ""
	}
	if dealer < len(a.PlayerAccountIDs) {
		if seat := slices.Index(remaining, a.PlayerAccountIDs[dealer]); seat >= 0 {
			return seat, remaining[seat]
		}
	}
	return 0, remaining[0]
}

func (s MahjongSeries) WithRound(players [4]string, scores [4]int) MahjongSeries {
	out := MahjongSeries{Rounds: s.Rounds + 1, Scores: slices.Clone(s.Scores)}
	for seat, account := range players {
		index := slices.IndexFunc(out.Scores, func(row MahjongSeriesScore) bool { return row.AccountID == account })
		if index < 0 {
			out.Scores = append(out.Scores, MahjongSeriesScore{AccountID: account, Score: scores[seat]})
		} else {
			out.Scores[index].Score += scores[seat]
		}
	}
	return out
}

// Scoreboard projects totals onto the current roster without exposing former accounts.
func (s MahjongSeries) Scoreboard(players []string) (scores, ranks []int) {
	scores = make([]int, len(players))
	ranks = make([]int, len(players))
	for seat, account := range players {
		for _, row := range s.Scores {
			if row.AccountID == account {
				scores[seat] = row.Score
				break
			}
		}
	}
	for seat, score := range scores {
		ranks[seat] = 1
		for _, other := range scores {
			if other > score {
				ranks[seat]++
			}
		}
	}
	return scores, ranks
}

func (s MahjongSeries) valid(completed int) bool {
	if s.Rounds < 0 || s.Rounds > completed || ((s.Rounds == 0) != (len(s.Scores) == 0)) {
		return false
	}
	if s.Rounds > 0 && (len(s.Scores) < 4 || (len(s.Scores)+3)/4 > s.Rounds) {
		return false
	}
	seen := make(map[string]bool, len(s.Scores))
	total := 0
	for _, row := range s.Scores {
		if row.AccountID == "" || strings.TrimSpace(row.AccountID) != row.AccountID || seen[row.AccountID] {
			return false
		}
		seen[row.AccountID] = true
		total += row.Score
	}
	return total == 0
}

func (a MahjongAssignment) roundHistory() mahjongRoundHistory {
	series := a.Series
	series.Scores = slices.Clone(series.Scores)
	return mahjongRoundHistory{a.CompletedRounds, a.PreviousMatchID, a.NextDealer, a.NextDealerAccount, series}
}
