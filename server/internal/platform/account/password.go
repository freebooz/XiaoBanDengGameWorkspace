package account

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/domain"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/argon2"
)

var (
	ErrInvalidRegistration  = errors.New("账号须为 3 到 32 位字母、数字或下划线，首位须为字母或数字。密码须为 8 到 128 个字符")
	ErrUsernameTaken        = errors.New("该账号已被注册")
	ErrInvalidPasswordLogin = errors.New("账号或密码错误")
	usernamePattern         = regexp.MustCompile(`^[a-z0-9][a-z0-9_]{2,31}$`)
)

const passwordScheme = "argon2id-v1"

type passwordCredential struct {
	username string
	salt     []byte
	digest   []byte
}

func (c passwordCredential) insert(ctx context.Context, tx pgx.Tx, id uuid.UUID) error {
	tag, err := tx.Exec(ctx, `INSERT INTO account_password_credentials(username,account_id,salt,password_hash,scheme)
		VALUES($1,$2,$3,$4,$5) ON CONFLICT (username) DO NOTHING`, c.username, id, c.salt, c.digest, passwordScheme)
	if err == nil && tag.RowsAffected() != 1 {
		return ErrUsernameTaken
	}
	return err
}

func normalizeUsername(raw string) string {
	value := strings.TrimSpace(raw)
	for _, character := range value {
		if character > 127 {
			return ""
		}
	}
	return strings.ToLower(value)
}

func validPassword(password string) bool {
	if len(password) > 512 || !utf8.ValidString(password) {
		return false
	}
	characters := utf8.RuneCountInString(password)
	return characters >= 8 && characters <= 128
}

func passwordDigest(password string, salt []byte) []byte {
	// Argon2id v1 uses two passes, 19 MiB, one lane, and a 32-byte digest.
	return argon2.IDKey([]byte(password), salt, 2, 19*1024, 1, 32)
}

func (s *Service) Register(ctx context.Context, username, password string) (GuestLogin, error) {
	username = normalizeUsername(username)
	if !usernamePattern.MatchString(username) || !validPassword(password) {
		return GuestLogin{}, ErrInvalidRegistration
	}
	if s.db == nil {
		return GuestLogin{}, errors.New("账号数据库不可用")
	}
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return GuestLogin{}, fmt.Errorf("无法生成密码盐: %w", err)
	}
	credential := passwordCredential{username: username, salt: salt, digest: passwordDigest(password, salt)}
	return s.createAccount(ctx, "registered", &credential)
}

func (s *Service) Login(ctx context.Context, username, password string) (GuestLogin, error) {
	username = normalizeUsername(username)
	if !usernamePattern.MatchString(username) || !validPassword(password) {
		return GuestLogin{}, ErrInvalidPasswordLogin
	}
	if s.db == nil {
		return GuestLogin{}, errors.New("账号数据库不可用")
	}
	var salt, digest []byte
	var scheme string
	var profile domain.GuestAccount
	err := s.db.QueryRow(ctx, `SELECT a.account_id::text,a.display_name,a.created_at,c.salt,c.password_hash,c.scheme
		FROM account_password_credentials c JOIN accounts a USING (account_id)
		WHERE c.username=$1 AND a.status='active'`, username).Scan(
		&profile.AccountID, &profile.DisplayName, &profile.CreatedAt, &salt, &digest, &scheme)
	if errors.Is(err, pgx.ErrNoRows) {
		// Unknown accounts still pay the same password derivation cost.
		salt, digest, scheme = make([]byte, 16), make([]byte, 32), passwordScheme
	} else if err != nil {
		return GuestLogin{}, fmt.Errorf("读取账号密码凭据失败: %w", err)
	}
	if scheme != passwordScheme || len(salt) != 16 || len(digest) != 32 {
		return GuestLogin{}, ErrInvalidPasswordLogin
	}
	if subtle.ConstantTimeCompare(passwordDigest(password, salt), digest) != 1 || profile.AccountID == "" {
		return GuestLogin{}, ErrInvalidPasswordLogin
	}
	var login GuestLogin
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		// Serializes issuing a session against any account deactivation.
		if err := tx.QueryRow(ctx, `SELECT display_name FROM accounts WHERE account_id=$1 AND status='active' FOR SHARE`,
			uuid.MustParse(profile.AccountID)).Scan(&profile.DisplayName); err != nil {
			return err
		}
		var err error
		login, err = issueSession(ctx, tx, profile, time.Now().UTC().Truncate(time.Microsecond))
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return GuestLogin{}, ErrInvalidPasswordLogin
	}
	if err != nil {
		return GuestLogin{}, fmt.Errorf("创建登录会话失败: %w", err)
	}
	return login, nil
}
