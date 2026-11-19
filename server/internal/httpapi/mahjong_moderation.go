package httpapi

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/game/mahjong/guiyang"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/mahjongmoderation"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/matchmaking"
)

type mahjongReportStore interface {
	Save(context.Context, mahjongmoderation.Report) error
}

func (h *mahjongHub) report(client *mahjongClient, message map[string]any) {
	commandID, _ := message["command_id"].(string)
	if strings.TrimSpace(commandID) == "" || len(commandID) > 128 {
		_ = client.writeJSON(map[string]any{"type": "mahjong_report_result", "ok": false, "command_id": "", "message": "缺少有效的举报命令编号"})
		return
	}
	report, err := h.reportForSeat(client, message)
	if err == nil {
		if h.moderation == nil {
			err = errors.New("举报服务暂时不可用，请稍后重试")
		} else {
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			if h.moderation.Save(ctx, report) != nil {
				err = errors.New("举报暂未保存，请稍后重试")
			}
			cancel()
		}
	}
	reply := map[string]any{"type": "mahjong_report_result", "command_id": commandID, "ok": err == nil, "message": ""}
	if err != nil {
		reply["message"] = err.Error()
	}
	_ = client.writeJSON(reply)
}

func (h *mahjongHub) reportForSeat(client *mahjongClient, message map[string]any) (mahjongmoderation.Report, error) {
	target, valid := jsonInt(message["target_seat"])
	matchID, _ := message["match_id"].(string)
	reason, _ := message["reason"].(string)
	if !valid || target < 0 || target >= 4 || !mahjongmoderation.ValidReason(reason) || matchID == "" {
		return mahjongmoderation.Report{}, errors.New("无效的举报座位、原因或对局编号")
	}
	room := h.boundBoard(client)
	if room == nil {
		return mahjongmoderation.Report{}, errors.New("请先加入麻将牌桌")
	}
	room.mu.Lock()
	defer room.mu.Unlock()
	_, connected := room.clients[client]
	if !connected || !room.started || room.kind == matchmaking.MahjongTraining || room.matchID != matchID || client.seat < 0 || client.seat >= 4 ||
		room.game.Players[client.seat] != client.accountID || room.game.Players[target] == "" || target == client.seat {
		return mahjongmoderation.Report{}, errors.New("只能举报本局另一位真实玩家")
	}
	if room.closed {
		if !room.retained || room.game.Phase != guiyang.PhaseFinished {
			return mahjongmoderation.Report{}, errors.New("此麻将牌桌已关闭")
		}
		assignment, ok := h.matches.MahjongAssignment(client.accountID)
		if !ok || assignment.RoomID != room.id || !assignment.Room.CreatedAt.Equal(room.createdAt) || assignment.PreviousMatchID != matchID || assignment.Start {
			return mahjongmoderation.Report{}, errors.New("此麻将牌桌已关闭")
		}
	}
	return mahjongmoderation.Report{
		MatchID: room.matchID, RoomID: room.id, Reason: reason,
		ReporterAccountID: client.accountID, ReporterSeat: client.seat,
		TargetAccountID: room.game.Players[target], TargetSeat: target,
	}, nil
}
