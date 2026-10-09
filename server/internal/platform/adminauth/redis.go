package adminauth

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisStore（共享会话）支持多服务实例并通过 TTL 自动清除过期会话。
type RedisStore struct{ client *redis.Client }

func NewRedisStore(client *redis.Client) *RedisStore { return &RedisStore{client: client} }
func (s *RedisStore) Put(ctx context.Context, key string, value Session, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return s.client.Set(ctx, "xbd:admin:session:"+key, data, ttl).Err()
}
func (s *RedisStore) Get(ctx context.Context, key string) (Session, error) {
	data, err := s.client.Get(ctx, "xbd:admin:session:"+key).Bytes()
	if errors.Is(err, redis.Nil) {
		return Session{}, ErrUnauthorized
	}
	if err != nil {
		return Session{}, err
	}
	var session Session
	err = json.Unmarshal(data, &session)
	return session, err
}
func (s *RedisStore) Delete(ctx context.Context, key string) error {
	return s.client.Del(ctx, "xbd:admin:session:"+key).Err()
}

// AllowAttempt（原子节流）每个来源每分钟最多五次，避免非原子的计数与过期间隙。
func (s *RedisStore) AllowAttempt(ctx context.Context, key string) (bool, error) {
	count, err := s.client.Eval(ctx, `local n = redis.call('INCR', KEYS[1]); if n == 1 then redis.call('EXPIRE', KEYS[1], 60) end; return n`, []string{"xbd:admin:attempt:" + key}).Int64()
	return count <= 5, err
}
