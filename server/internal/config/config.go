package config

import (
	"os"
	"strconv"
)

// Config（运行配置）集中描述后端需要的环境变量。
// 真实微信密钥只允许通过部署环境注入，禁止写入仓库。
type Config struct {
	HTTPAddr        string
	PostgresURL     string
	RedisAddr       string
	RedisPassword   string
	RedisDB         int
	WeChatAppID     string
	WeChatAppSecret string
	WeChatMchID     string
	WeChatAPIV3Key  string
}

// Load（加载配置）读取环境变量并提供本地开发默认值。
func Load() Config {
	redisDB, _ := strconv.Atoi(getEnv("REDIS_DB", "0"))
	return Config{
		HTTPAddr:        getEnv("HTTP_ADDR", ":8080"),
		PostgresURL:     getEnv("POSTGRES_URL", "postgres://xbd:xbd_dev_password@localhost:5432/xbd?sslmode=disable"),
		RedisAddr:       getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:   getEnv("REDIS_PASSWORD", ""),
		RedisDB:         redisDB,
		WeChatAppID:     getEnv("WECHAT_APP_ID", ""),
		WeChatAppSecret: getEnv("WECHAT_APP_SECRET", ""),
		WeChatMchID:     getEnv("WECHAT_MCH_ID", ""),
		WeChatAPIV3Key:  getEnv("WECHAT_API_V3_KEY", ""),
	}
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}