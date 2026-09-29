package wallet

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Balance（钱包余额）展示家族级资产余额。
type Balance struct {
	AccountID string `json:"account_id"`
	AssetID string `json:"asset_id"`
	Scope string `json:"scope"`
	Amount int64 `json:"amount"`
}

// Service（钱包服务）以账本为事实来源，余额表只作为查询快照。
type Service struct { db *pgxpool.Pool }

// NewService（创建钱包服务）。
func NewService(db *pgxpool.Pool) *Service { return &Service{db:db} }

// GetFamilyBalance（查询家族级资产）返回可跨“小板凳”家族使用的非渠道受限资产。
func (s *Service) GetFamilyBalance(ctx context.Context, accountID string) (Balance,error) {
	const assetID="xbd_point"
	const scope="family"
	var amount int64
	err:=s.db.QueryRow(ctx,
		`SELECT balance FROM wallet_accounts WHERE account_id=$1 AND asset_id=$2 AND scope=$3`,
		accountID,assetID,scope,
	).Scan(&amount)
	if errors.Is(err,pgx.ErrNoRows) {
		return Balance{AccountID:accountID,AssetID:assetID,Scope:scope,Amount:0},nil
	}
	if err!=nil { return Balance{},fmt.Errorf("查询钱包失败: %w",err) }
	return Balance{AccountID:accountID,AssetID:assetID,Scope:scope,Amount:amount},nil
}