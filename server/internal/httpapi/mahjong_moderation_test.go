package httpapi

import (
	"context"
	"testing"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongmoderation"
)

type reportProbe struct{ saved chan mahjongmoderation.Report }

func (p reportProbe) Save(_ context.Context, report mahjongmoderation.Report) error {
	p.saved <- report
	return nil
}

func TestMahjongReportUsesBoundGameplaySeats(t *testing.T) {
	f := referenceMahjongServer(t, 1, 4)
	probe := reportProbe{saved: make(chan mahjongmoderation.Report, 8)}
	f.hub.moderation = probe
	room := f.hub.rooms[f.rooms[0]]
	lobbyOnly, _ := f.connect(t)
	for _, tc := range []struct {
		name          string
		seat          int
		match, reason string
		ok            bool
	}{
		{name: "unbound", seat: 1, match: room.matchID, reason: "spam"},
		{name: "self", seat: 0, match: room.matchID, reason: "spam"},
		{name: "old match", seat: 1, match: "stale", reason: "spam"},
		{name: "nonenum", seat: 1, match: room.matchID, reason: "arbitrary"},
		{name: "peer", seat: 1, match: room.matchID, reason: "voice_abuse", ok: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			conn := f.connections[0][0]
			if tc.name == "unbound" {
				conn = lobbyOnly
			}
			referenceSend(t, conn, map[string]any{"type": "mahjong_report", "command_id": "report-test", "target_seat": tc.seat, "match_id": tc.match, "reason": tc.reason, "reporter_id": "forged", "room_id": "other", "text": "private"})
			result := mahjongReferenceRead(t, conn, "mahjong_report_result")
			if result["command_id"] != "report-test" || result["ok"] != tc.ok {
				t.Fatalf("unexpected report ack: %v", result)
			}
			select {
			case report := <-probe.saved:
				if !tc.ok || report.ReporterAccountID != room.game.Players[0] || report.TargetAccountID != room.game.Players[1] || report.ReporterSeat != 0 || report.TargetSeat != 1 || report.RoomID != room.id || report.MatchID != room.matchID || report.Reason != tc.reason {
					t.Fatalf("unexpected saved moderation report: %+v", report)
				}
			default:
				if tc.ok {
					t.Fatal("accepted report did not reach the store")
				}
			}
		})
	}
}
