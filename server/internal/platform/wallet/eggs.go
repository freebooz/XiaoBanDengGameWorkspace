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
	NewPlayerWelcomeEggs = 500
	MaximumEggGrant      = 1_000_000

	// Keep the persisted reason stable so existing welcome ledger entries and
	// their grant-once index continue to apply to every account type.
	welcomeEggsReason   = "guest_welcome_eggs"
	adminEggGrantReason = "admin_egg_grant"
)

var (
	ErrInvalidEggGrant       = errors.New("请填写有效的玩家昵称、加蛋数量和请求编号")
	ErrInvalidEggPlayer      = errors.New("请填写有效的玩家昵称")
	ErrPlayerNotFound        = errors.New("未找到此昵称的有效玩家")
	ErrAmbiguousPlayer       = errors.New("此昵称对应多个有效玩家，请核对昵称")
	ErrEggGrantConflict      = errors.New("该请求编号已用于不同的加蛋操作")
	ErrEggGrantTargetChanged = errors.New("玩家昵称或账号状态已变化，请重新查询")
)

type EggGrant struct {
	DisplayName       string    `json:"display_name"`
	Amount            int64     `json:"amount"`
	RequestID         uuid.UUID `json:"request_id"`
	ExpectedAccountID string    `json:"expected_account_id,omitempty"`
}

type EggPlayerBalance struct {
	AccountID   string `json:"account_id"`
	DisplayName string `json:"display_name"`
	AssetID     string `json:"asset_id"`
	Balance     int64  `json:"balance"`
}

type EggGrantReceipt struct {
	EggPlayerBalance
	Amount    int64     `json:"amount"`
	RequestID uuid.UUID `json:"request_id"`
}

type eggCredit struct {
	id          uuid.UUID
	accountID   string
	amount      int64
	reason      string
	operator    string
	displayName string
}

// CreditNewPlayerWelcomeEggs runs only inside the new account transaction,
// never on login or session restoration. Existing balances are not topped up.
func CreditNewPlayerWelcomeEggs(ctx context.Context, tx pgx.Tx, accountID uuid.UUID) error {
	_, applied, err := creditEggs(ctx, tx, eggCredit{id: accountID, accountID: accountID.String(), amount: NewPlayerWelcomeEggs, reason: welcomeEggsReason})
	if err == nil && !applied {
		return errors.New("新玩家鸡蛋奖励已处理")
	}
	return err
}

func (s *Service) GrantEggs(ctx context.Context, operator string, request EggGrant) (EggGrantReceipt, error) {
	displayName, validName := normalizeEggDisplayName(request.DisplayName)
	if !validName ||
		request.Amount < 1 || request.Amount > MaximumEggGrant || request.RequestID == uuid.Nil || operator == "" {
		return EggGrantReceipt{}, ErrInvalidEggGrant
	}
	if request.ExpectedAccountID != "" {
		expected, err := uuid.Parse(request.ExpectedAccountID)
		if err != nil || expected == uuid.Nil || len(request.ExpectedAccountID) != 36 {
			return EggGrantReceipt{}, ErrInvalidEggGrant
		}
		request.ExpectedAccountID = expected.String()
	}
	if s.db == nil {
		return EggGrantReceipt{}, errors.New("钱包数据库不可用")
	}
	receipt := EggGrantReceipt{
		EggPlayerBalance: EggPlayerBalance{DisplayName: displayName, AssetID: EggAssetID},
		Amount:           request.Amount, RequestID: request.RequestID,
	}
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		err := replayEggGrant(ctx, tx, operator, request.ExpectedAccountID, &receipt)
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		player, err := findEggPlayer(ctx, tx, selectEggPlayer+" FOR SHARE OF a", displayName)
		if request.ExpectedAccountID != "" && (errors.Is(err, ErrPlayerNotFound) || errors.Is(err, ErrAmbiguousPlayer) ||
			(err == nil && player.AccountID != request.ExpectedAccountID)) {
			return ErrEggGrantTargetChanged
		}
		if err != nil {
			return err
		}
		balance, applied, err := creditEggs(ctx, tx, eggCredit{
			id: request.RequestID, accountID: player.AccountID, amount: request.Amount,
			reason: adminEggGrantReason, operator: operator, displayName: displayName,
		})
		if err != nil {
			return err
		}
		if !applied {
			return replayEggGrant(ctx, tx, operator, request.ExpectedAccountID, &receipt)
		}
		receipt.AccountID = player.AccountID
		receipt.Balance = balance
		return nil
	})
	return receipt, err
}

func (s *Service) LookupEggPlayer(ctx context.Context, displayName string) (EggPlayerBalance, error) {
	name, valid := normalizeEggDisplayName(displayName)
	if !valid {
		return EggPlayerBalance{}, ErrInvalidEggPlayer
	}
	if s.db == nil {
		return EggPlayerBalance{}, errors.New("钱包数据库不可用")
	}
	return findEggPlayer(ctx, s.db, selectEggPlayer, name)
}

func normalizeEggDisplayName(value string) (string, bool) {
	name := strings.TrimSpace(value)
	return name, name != "" && utf8.ValidString(name) && utf8.RuneCountInString(name) <= 64 && !strings.ContainsRune(name, 0)
}

const selectEggPlayer = `SELECT a.account_id::text, a.display_name, $2::text, COALESCE(w.balance,0)
	FROM accounts a
	LEFT JOIN wallet_accounts w ON w.account_id=a.account_id AND w.asset_id=$2 AND w.scope=$3
	WHERE a.display_name=$1 AND a.status='active'
	ORDER BY a.account_id LIMIT 2`

type eggPlayerQuerier interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

func findEggPlayer(ctx context.Context, db eggPlayerQuerier, statement, displayName string) (EggPlayerBalance, error) {
	rows, err := db.Query(ctx, statement, displayName, EggAssetID, FamilyScope)
	if err != nil {
		return EggPlayerBalance{}, err
	}
	players, err := pgx.CollectRows(rows, pgx.RowToStructByPos[EggPlayerBalance])
	if err != nil {
		return EggPlayerBalance{}, err
	}
	switch len(players) {
	case 0:
		return EggPlayerBalance{}, ErrPlayerNotFound
	case 1:
		return players[0], nil
	default:
		return EggPlayerBalance{}, ErrAmbiguousPlayer
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

func replayEggGrant(ctx context.Context, tx pgx.Tx, operator, expectedAccountID string, receipt *EggGrantReceipt) error {
	var name, asset, scope, reason, author string
	var amount int64
	err := tx.QueryRow(ctx, `SELECT ledger.account_id::text, ledger.asset_id, ledger.scope, ledger.delta, ledger.reason,
		COALESCE(ledger.performed_by,''), COALESCE(ledger.target_display_name,''), COALESCE(wallet.balance,0)
		FROM wallet_ledger ledger LEFT JOIN wallet_accounts wallet USING (account_id,asset_id,scope)
		WHERE ledger.ledger_id=$1`, receipt.RequestID).Scan(&receipt.AccountID, &asset, &scope, &amount, &reason, &author, &name, &receipt.Balance)
	if err != nil {
		return err
	}
	if reason != adminEggGrantReason || asset != EggAssetID || scope != FamilyScope || author != operator || name != receipt.DisplayName || amount != receipt.Amount ||
		(expectedAccountID != "" && expectedAccountID != receipt.AccountID) {
		return ErrEggGrantConflict
	}
	return nil
}
