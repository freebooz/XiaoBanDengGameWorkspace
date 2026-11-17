package guiyang

// ScoreBreakdown holds signed net transfers by seat. Each category is zero-sum.
type ScoreBreakdown struct {
	Hu      [4]int `json:"hu"`
	Gang    [4]int `json:"gang"`
	Ji      [4]int `json:"ji"`
	ChaJiao [4]int `json:"cha_jiao"`
}

type ScoreTransfer struct {
	Payer    int    `json:"payer"`
	Receiver int    `json:"receiver"`
	Category string `json:"category"`
	Reason   string `json:"reason"`
	Amount   int    `json:"amount"`
	HandType string `json:"hand_type,omitempty"`
}

type scoreCategory uint8

const (
	scoreHu scoreCategory = iota
	scoreGang
	scoreJi
	scoreChaJiao
)

var scoreCategoryNames = [...]string{"hu", "gang", "ji", "cha_jiao"}

func (g *Game) recordScore(category scoreCategory, from, to, points int, reason, handType string) {
	if points <= 0 {
		return
	}
	g.transferScore(category, from, to, points)
	g.ScoreLedger = append(g.ScoreLedger, ScoreTransfer{Payer: from, Receiver: to, Category: scoreCategoryNames[category], Reason: reason, Amount: points, HandType: handType})
}

func (g *Game) SettlementScoreTransfers() []ScoreTransfer {
	breakdown := g.SettlementScoreBreakdown()
	if !g.Rules.Dingque() || breakdown == nil {
		return nil
	}
	var totals ScoreBreakdown
	for _, entry := range g.ScoreLedger {
		if entry.Payer < 0 || entry.Payer >= 4 || entry.Receiver < 0 || entry.Receiver >= 4 || entry.Payer == entry.Receiver || entry.Amount <= 0 || entry.Reason == "" {
			return nil
		}
		var category *[4]int
		switch entry.Category {
		case "hu":
			category = &totals.Hu
		case "gang":
			category = &totals.Gang
		case "ji":
			category = &totals.Ji
		case "cha_jiao":
			category = &totals.ChaJiao
		default:
			return nil
		}
		category[entry.Payer] -= entry.Amount
		category[entry.Receiver] += entry.Amount
	}
	if totals != *breakdown {
		return nil
	}
	return append([]ScoreTransfer{}, g.ScoreLedger...)
}

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
	case scoreChaJiao:
		totals = &g.ScoreBreakdown.ChaJiao
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
	var hu, gang, ji, chaJiao int
	for seat, score := range g.Scores {
		if breakdown.Hu[seat]+breakdown.Gang[seat]+breakdown.Ji[seat]+breakdown.ChaJiao[seat] != score {
			return nil
		}
		hu += breakdown.Hu[seat]
		gang += breakdown.Gang[seat]
		ji += breakdown.Ji[seat]
		chaJiao += breakdown.ChaJiao[seat]
	}
	if hu != 0 || gang != 0 || ji != 0 || chaJiao != 0 {
		return nil
	}
	return &breakdown
}
