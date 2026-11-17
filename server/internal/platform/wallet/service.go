package wallet

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	EggAssetID  = "xbd_egg"
	FamilyScope = "family"
)

// Balance（钱包余额）展示家族级资产余额。
type Balance struct {
	AccountID string `json:"account_id"`
	AssetID   string `json:"asset_id"`
	Scope     string `json:"scope"`
	Amount    int64  `json:"amount"`
}

type EggProfile struct {
	DisplayName string
	Amount      int64
}

// Service（钱包服务）以账本为事实来源，余额表只作为查询快照。
type Service struct{ db *pgxpool.Pool }

// NewService（创建钱包服务）。
func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

// GetFamilyBalance（查询家族级资产）返回可跨“小板凳”家族使用的非渠道受限资产。
func (s *Service) GetFamilyBalance(ctx context.Context, accountID string) (Balance, error) {
	if s.db == nil {
		return Balance{}, errors.New("钱包数据库不可用")
	}
	result := Balance{AccountID: accountID, AssetID: EggAssetID, Scope: FamilyScope}
	var amount int64
	err := s.db.QueryRow(ctx,
		`SELECT balance FROM wallet_accounts WHERE account_id=$1 AND asset_id=$2 AND scope=$3`,
		accountID, EggAssetID, FamilyScope,
	).Scan(&amount)
	if errors.Is(err, pgx.ErrNoRows) {
		return result, nil
	}
	if err != nil {
		return Balance{}, fmt.Errorf("查询钱包失败: %w", err)
	}
	result.Amount = amount
	return result, nil
}

// GetFamilyEggProfiles returns a batch snapshot for active accounts. An active
// legacy account without an egg wallet has zero eggs.
func (s *Service) GetFamilyEggProfiles(ctx context.Context, accountIDs []string) (map[string]EggProfile, error) {
	if s.db == nil {
		return nil, errors.New("钱包数据库不可用")
	}
	rows, err := s.db.Query(ctx, `SELECT a.account_id::text, a.display_name, COALESCE(w.balance,0)
		FROM accounts a
		LEFT JOIN wallet_accounts w ON w.account_id=a.account_id AND w.asset_id=$2 AND w.scope=$3
		WHERE a.status='active' AND a.account_id=ANY($1::text[]::uuid[])`, accountIDs, EggAssetID, FamilyScope)
	if err != nil {
		return nil, fmt.Errorf("查询牌友资料失败: %w", err)
	}
	defer rows.Close()
	profiles := make(map[string]EggProfile, len(accountIDs))
	for rows.Next() {
		var accountID string
		var profile EggProfile
		if err := rows.Scan(&accountID, &profile.DisplayName, &profile.Amount); err != nil {
			return nil, fmt.Errorf("读取牌友资料失败: %w", err)
		}
		profiles[accountID] = profile
	}
	return profiles, rows.Err()
}
