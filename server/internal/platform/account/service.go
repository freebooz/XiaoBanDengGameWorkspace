package account

import (
	"context"
	"fmt"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Service（账号服务）统一维护游客、微信、手机号等身份最终映射到的 AccountId。
type Service struct { db *pgxpool.Pool }

// NewService（创建账号服务）。
func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

// CreateGuest（创建游客账号）提供第一期可运行的注册登录闭环。
func (s *Service) CreateGuest(ctx context.Context) (domain.GuestAccount, error) {
	id := uuid.New()
	now := time.Now().UTC()
	displayName := "游客-" + id.String()[:8]
	_, err := s.db.Exec(ctx,
		`INSERT INTO accounts(account_id, display_name, account_type, created_at) VALUES($1,$2,'guest',$3)`,
		id, displayName, now,
	)
	if err != nil { return domain.GuestAccount{}, fmt.Errorf("创建游客账号失败: %w", err) }
	return domain.GuestAccount{AccountID:id.String(), DisplayName:displayName, CreatedAt:now}, nil
}