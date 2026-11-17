package wallet

import (
	"context"
	"errors"
	"math"
	"slices"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const MahjongSettlementReason = "mahjong_settlement_eggs"

// SettleMahjongEggsTx posts one authoritative hand in its history/completion
// transaction. History owns the match-level idempotency gate. Scores remain the
// rule result; actual eggs are capped by each loser's locked balance. Winners
// share the collected eggs proportionally, with largest remainder then seat
// order deciding indivisible eggs. Training never calls this function.
func SettleMahjongEggsTx(ctx context.Context, tx pgx.Tx, matchID string, players [4]string, scores [4]int) error {
	if matchID == "" {
		return errors.New("缺少鸡蛋结算对局标识")
	}
	var total, positive int64
	seen := map[string]bool{}
	order := []int{0, 1, 2, 3}
	for seat, player := range players {
		id, err := uuid.Parse(player)
		if err != nil || id == uuid.Nil || seen[id.String()] || scores[seat] < -math.MaxInt32 || scores[seat] > math.MaxInt32 {
			return errors.New("无效的鸡蛋结算座位或分数")
		}
		players[seat] = id.String()
		seen[players[seat]] = true
		total += int64(scores[seat])
		if scores[seat] > 0 {
			positive += int64(scores[seat])
		}
	}
	if total != 0 {
		return errors.New("鸡蛋结算分数不守恒")
	}
	// Every settlement locks wallet rows in account order, not seating order.
	// Admin credits use the same row and arithmetic update, so no credit is lost.
	slices.SortFunc(order, func(a, b int) int {
		if players[a] < players[b] {
			return -1
		}
		if players[a] > players[b] {
			return 1
		}
		return 0
	})
	var balances, deltas, remainders [4]int64
	var collected int64
	for _, seat := range order {
		if _, err := tx.Exec(ctx, `INSERT INTO wallet_accounts(account_id,asset_id,scope,balance) VALUES($1,$2,$3,0) ON CONFLICT DO NOTHING`, players[seat], EggAssetID, FamilyScope); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `SELECT balance FROM wallet_accounts WHERE account_id=$1 AND asset_id=$2 AND scope=$3 FOR UPDATE`, players[seat], EggAssetID, FamilyScope).Scan(&balances[seat]); err != nil {
			return err
		}
		if balances[seat] < 0 {
			return errors.New("鸡蛋余额异常，结算未提交")
		}
		if scores[seat] < 0 {
			deltas[seat] = -min(balances[seat], -int64(scores[seat]))
			collected -= deltas[seat]
		}
	}
	var distributed int64
	var winners []int
	for seat, score := range scores {
		if score <= 0 {
			continue
		}
		product := collected * int64(score)
		deltas[seat], remainders[seat] = product/positive, product%positive
		distributed += deltas[seat]
		winners = append(winners, seat)
	}
	slices.SortFunc(winners, func(a, b int) int {
		if remainders[a] > remainders[b] {
			return -1
		}
		if remainders[a] < remainders[b] {
			return 1
		}
		return a - b
	})
	for _, seat := range winners {
		if distributed >= collected {
			break
		}
		deltas[seat]++
		distributed++
	}
	for _, seat := range order {
		ledgerID := uuid.NewSHA1(uuid.NameSpaceURL, []byte("urn:xbd:mahjong:eggs:"+matchID+":"+players[seat]))
		if _, err := tx.Exec(ctx, `INSERT INTO wallet_ledger(ledger_id,account_id,asset_id,scope,delta,reason,reference_id)
			VALUES($1,$2,$3,$4,$5,$6,$7)`, ledgerID, players[seat], EggAssetID, FamilyScope, deltas[seat], MahjongSettlementReason, matchID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE wallet_accounts SET balance=balance+$4,updated_at=clock_timestamp() WHERE account_id=$1 AND asset_id=$2 AND scope=$3`, players[seat], EggAssetID, FamilyScope, deltas[seat]); err != nil {
			return err
		}
	}
	return nil
}
