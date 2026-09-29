package redis

import (
	"context"
	"fmt"

	goredis "github.com/redis/go-redis/v9"
)

// Connect（连接Redis）创建客户端并验证可用性。
func Connect(ctx context.Context, address, password string, db int) (*goredis.Client, error) {
	client := goredis.NewClient(&goredis.Options{Addr: address, Password: password, DB: db})
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("Redis健康检查失败: %w", err)
	}
	return client, nil
}