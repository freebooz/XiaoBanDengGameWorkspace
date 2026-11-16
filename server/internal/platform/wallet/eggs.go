package wallet

import (
	"context"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const (
	GuestWelcomeEggs = 100
	MaximumEggGrant  = 1_000_000

	guestWelcomeReason  = "guest_welcome_eggs"
	adminEggGrantReason = "admin_egg_grant"
)

var (
	ErrInvalidEggGrant  = errors.New("请填写有效的玩家昵称、加蛋数量和请求编号")
	ErrPlayerNotFound   = errors.New("未找到此昵称的有效玩家")
	ErrAmbiguousPlayer  = errors.New("此昵称对应多个有效玩家，请核对昵称")
	ErrEggGrantConflict = errors.New("该请求编号已用于不同的加蛋操作")
)

type EggGrant struct {
	DisplayName string    `json:"display_name"`
	Amount      int64     `json:"amount"`
	RequestID   uuid.UUID `json:"request_id"`
}

type EggGrantReceipt struct {
	EggGrant
	AccountID string `json:"account_id"`
	AssetID   string `json:"asset_id"`
	Balance   int64  `json:"balance"`
}

type eggCredit struct {
	id          uuid.UUID
	accountID   string
	amount      int64
	reason      string
	operator    string
	displayName string
}

// CreditGuestWelcomeEggs runs inside the account creation transaction.
func CreditGuestWelcomeEggs(ctx context.Context, tx pgx.Tx, accountID uuid.UUID) error {
	_, applied, err := creditEggs(ctx, tx, eggCredit{id: accountID, accountID: accountID.String(), amount: GuestWelcomeEggs, reason: guestWelcomeReason})
	if err == nil && !applied {
		return errors.New("游客鸡蛋奖励已处理")
	}
	return err
}

func (s *Service) GrantEggs(ctx context.Context, operator string, request EggGrant) (EggGrantReceipt, error) {
	request.DisplayName = strings.TrimSpace(request.DisplayName)
	if request.DisplayName == "" || utf8.RuneCountInString(request.DisplayName) > 64 || strings.ContainsRune(request.DisplayName, 0) ||
		request.Amount < 1 || request.Amount > MaximumEggGrant || request.RequestID == uuid.Nil || operator == "" {
		return EggGrantReceipt{}, ErrInvalidEggGrant
	}
	if s.db == nil {
		return EggGrantReceipt{}, errors.New("钱包数据库不可用")
	}
	receipt := EggGrantReceipt{EggGrant: request, AssetID: EggAssetID}
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		err := replayEggGrant(ctx, tx, operator, &receipt)
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		player, err := findEggGrantPlayer(ctx, tx, request.DisplayName)
		if err != nil {
			return err
		}
		balance, applied, err := creditEggs(ctx, tx, eggCredit{
			id: request.RequestID, accountID: player, amount: request.Amount,
			reason: adminEggGrantReason, operator: operator, displayName: request.DisplayName,
		})
		if err != nil {
			return err
		}
		if !applied {
			return replayEggGrant(ctx, tx, operator, &receipt)
		}
		receipt.AccountID = player
		receipt.Balance = balance
		return nil
	})
	return receipt, err
}

func findEggGrantPlayer(ctx context.Context, tx pgx.Tx, displayName string) (string, error) {
	rows, err := tx.Query(ctx, `SELECT account_id::text FROM accounts WHERE display_name=$1 AND status='active'
		ORDER BY account_id LIMIT 2 FOR SHARE`, displayName)
	if err != nil {
		return "", err
	}
	players, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return "", err
	}
	switch len(players) {
	case 0:
		return "", ErrPlayerNotFound
	case 1:
		return players[0], nil
	default:
		return "", ErrAmbiguousPlayer
	}
}

func creditEggs(ctx context.Context, tx pgx.Tx, credit eggCredit) (int64, bool, error) {
	insert, err := tx.Exec(ctx, `INSERT INTO wallet_ledger
		(ledger_id,account_id,asset_id,scope,delta,reason,performed_by,target_display_name)
		VALUES($1,$2,$3,$4,$5,$6,NULLIF($7,''),NULLIF($8,'')) ON CONFLICT DO NOTHING`,
		credit.id, credit.accountID, EggAssetID, FamilyScope, credit.amount, credit.reason, credit.operator, credit.displayName)
	if err != nil || insert.RowsAffected() == 0 {
		return 0, false, err
	}
	var balance int64
	err = tx.QueryRow(ctx, `INSERT INTO wallet_accounts(account_id,asset_id,scope,balance)
		VALUES($1,$2,$3,$4) ON CONFLICT(account_id,asset_id,scope) DO UPDATE SET
		balance=wallet_accounts.balance + excluded.balance, updated_at=clock_timestamp() RETURNING balance`,
		credit.accountID, EggAssetID, FamilyScope, credit.amount).Scan(&balance)
	return balance, true, err
}

func replayEggGrant(ctx context.Context, tx pgx.Tx, operator string, receipt *EggGrantReceipt) error {
	var name, asset, scope, reason, author string
	var amount int64
	err := tx.QueryRow(ctx, `SELECT ledger.account_id::text, ledger.asset_id, ledger.scope, ledger.delta, ledger.reason,
		COALESCE(ledger.performed_by,''), COALESCE(ledger.target_display_name,''), COALESCE(wallet.balance,0)
		FROM wallet_ledger ledger LEFT JOIN wallet_accounts wallet USING (account_id,asset_id,scope)
		WHERE ledger.ledger_id=$1`, receipt.RequestID).Scan(&receipt.AccountID, &asset, &scope, &amount, &reason, &author, &name, &receipt.Balance)
	if err != nil {
		return err
	}
	if reason != adminEggGrantReason || asset != EggAssetID || scope != FamilyScope || author != operator || name != receipt.DisplayName || amount != receipt.Amount {
		return ErrEggGrantConflict
	}
	return nil
}
