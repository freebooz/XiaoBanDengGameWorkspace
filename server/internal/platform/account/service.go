package account

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/platform/wallet"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const sessionLifetime = 90 * 24 * time.Hour

var ErrInvalidSession = errors.New("登录会话已失效")

type Session struct {
	domain.GuestAccount
	ExpiresAt time.Time `json:"expires_at"`
}

type GuestLogin struct {
	Session
	Token string `json:"session_token"`
}

// Service（账号服务）统一维护游客、微信、手机号等身份最终映射到的 AccountId。
type Service struct{ db *pgxpool.Pool }

// NewService（创建账号服务）。
func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

// CreateGuest persists the account and a recoverable session in one transaction.
func (s *Service) CreateGuest(ctx context.Context) (GuestLogin, error) {
	return s.createAccount(ctx, "guest", nil)
}

func (s *Service) createAccount(ctx context.Context, accountType string, credential *passwordCredential) (GuestLogin, error) {
	if s.db == nil {
		return GuestLogin{}, errors.New("账号数据库不可用")
	}
	id, err := uuid.NewRandom()
	if err != nil {
		return GuestLogin{}, fmt.Errorf("生成账号标识失败: %w", err)
	}
	now := time.Now().UTC().Truncate(time.Microsecond)
	var login GuestLogin
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		name, err := allocateGuestDefaultName(ctx, tx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO accounts(account_id, display_name, account_type, created_at) VALUES($1,$2,$3,$4)`,
			id, name, accountType, now); err != nil {
			return err
		}
		if credential != nil {
			if err := credential.insert(ctx, tx, id); err != nil {
				return err
			}
		}
		if err := wallet.CreditNewPlayerWelcomeEggs(ctx, tx, id); err != nil {
			return err
		}
		login, err = issueSession(ctx, tx, domain.GuestAccount{AccountID: id.String(), DisplayName: name, CreatedAt: now}, now)
		return err
	})
	if err != nil {
		return GuestLogin{}, fmt.Errorf("创建账号会话失败: %w", err)
	}
	return login, nil
}

func issueSession(ctx context.Context, tx pgx.Tx, account domain.GuestAccount, now time.Time) (GuestLogin, error) {
	var secret [32]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return GuestLogin{}, fmt.Errorf("生成会话凭据失败: %w", err)
	}
	expires := now.Add(sessionLifetime)
	hash := sha256.Sum256(secret[:])
	if _, err := tx.Exec(ctx, `INSERT INTO account_sessions(token_hash, account_id, expires_at, created_at) VALUES($1,$2,$3,$4)`,
		hash[:], uuid.MustParse(account.AccountID), expires, now); err != nil {
		return GuestLogin{}, err
	}
	return GuestLogin{Session: Session{GuestAccount: account, ExpiresAt: expires}, Token: base64.RawURLEncoding.EncodeToString(secret[:])}, nil
}

// Session resolves a credential without returning or storing the original token.
func (s *Service) Session(ctx context.Context, token string) (Session, error) {
	hash, err := digestSessionToken(token)
	if err != nil {
		return Session{}, err
	}
	if s.db == nil {
		return Session{}, errors.New("账号数据库不可用")
	}
	var session Session
	err = s.db.QueryRow(ctx, `SELECT a.account_id::text,a.display_name,a.created_at,s.expires_at
		FROM account_sessions s JOIN accounts a ON a.account_id=s.account_id
		WHERE s.token_hash=$1 AND s.expires_at>NOW() AND a.status='active'`, hash[:]).Scan(
		&session.AccountID, &session.DisplayName, &session.CreatedAt, &session.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrInvalidSession
	}
	if err != nil {
		return Session{}, fmt.Errorf("读取会话失败: %w", err)
	}
	return session, nil
}

func digestSessionToken(token string) ([32]byte, error) {
	if len(token) != base64.RawURLEncoding.EncodedLen(32) {
		return [32]byte{}, ErrInvalidSession
	}
	secret, err := base64.RawURLEncoding.Strict().DecodeString(token)
	if err != nil || len(secret) != 32 {
		return [32]byte{}, ErrInvalidSession
	}
	return sha256.Sum256(secret), nil
}
