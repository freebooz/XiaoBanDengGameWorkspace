package guiyang

func (g *Game) settlementHands() [][]Tile {
	hands := make([][]Tile, len(g.Hands))
	for seat, held := range g.Hands {
		hand := append([]Tile{}, held...)
		if g.ClaimedWinTile != nil && containsSeat(g.Winners, seat) {
			hand = append(hand, *g.ClaimedWinTile)
		}
		SortHand(hand)
		hands[seat] = hand
	}
	return hands
}

type fanItem struct {
	Name string `json:"name"`
	Fan  int    `json:"fan"`
}

type seatFanBreakdown struct {
	Seat  int       `json:"seat"`
	Items []fanItem `json:"items"`
	Total int       `json:"total"`
}

func settlementFanBreakdown(details []HuDetail) []seatFanBreakdown {
	rows := make([]seatFanBreakdown, 0, len(details))
	for _, detail := range details {
		bonus := localWinMethodFan(detail.Kind)
		base := detail.Fan - bonus.Fan
		if detail.Pattern == "" || base <= 0 {
			continue
		}
		items := []fanItem{{Name: detail.Pattern, Fan: base}}
		if bonus.Fan > 0 {
			items = append(items, bonus)
		}
		rows = append(rows, seatFanBreakdown{Seat: detail.Seat, Items: items, Total: detail.Fan})
	}
	return rows
}
