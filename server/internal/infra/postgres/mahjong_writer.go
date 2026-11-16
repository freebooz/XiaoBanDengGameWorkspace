package postgres

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// ClaimMahjongWriter uses a dedicated connection so pool reuse cannot release
// or carry this database's writer lock into unrelated queries.
func ClaimMahjongWriter(ctx context.Context, databaseURL string) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		return nil, errors.New("无法连接麻将写入协调数据库")
	}
	var acquired bool
	err = conn.QueryRow(ctx, `SELECT pg_try_advisory_lock(1208363364, 1)`).Scan(&acquired)
	if err != nil || !acquired {
		_ = conn.Close(ctx)
		if err != nil {
			return nil, errors.New("无法确认麻将写入锁")
		}
		return nil, errors.New("已有麻将服务持有数据库写入锁")
	}
	return conn, nil
}
