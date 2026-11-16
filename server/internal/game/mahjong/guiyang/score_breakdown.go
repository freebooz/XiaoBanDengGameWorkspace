package guiyang

// ScoreBreakdown holds signed net transfers by seat. Each category is zero-sum.
type ScoreBreakdown struct {
	Hu   [4]int `json:"hu"`
	Gang [4]int `json:"gang"`
	Ji   [4]int `json:"ji"`
}

type scoreCategory uint8

const (
	scoreHu scoreCategory = iota
	scoreGang
	scoreJi
)

func (g *Game) transferScore(category scoreCategory, from, to, points int) {
	g.Scores[from] -= points
	g.Scores[to] += points
	if g.ScoreBreakdown == nil {
		return
	}
	var totals *[4]int
	switch category {
	case scoreHu:
		totals = &g.ScoreBreakdown.Hu
	case scoreGang:
		totals = &g.ScoreBreakdown.Gang
	case scoreJi:
		totals = &g.ScoreBreakdown.Ji
	default:
		panic("unknown Mahjong score category")
	}
	totals[from] -= points
	totals[to] += points
}

// SettlementScoreBreakdown returns a detached, verified copy for a finished
// round. A legacy checkpoint has no reliable category totals.
func (g *Game) SettlementScoreBreakdown() *ScoreBreakdown {
	if g.Phase != PhaseFinished || g.ScoreBreakdown == nil {
		return nil
	}
	breakdown := *g.ScoreBreakdown
	var hu, gang, ji int
	for seat, score := range g.Scores {
		if breakdown.Hu[seat]+breakdown.Gang[seat]+breakdown.Ji[seat] != score {
			return nil
		}
		hu += breakdown.Hu[seat]
		gang += breakdown.Gang[seat]
		ji += breakdown.Ji[seat]
	}
	if hu != 0 || gang != 0 || ji != 0 {
		return nil
	}
	return &breakdown
}
