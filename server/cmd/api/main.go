package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/config"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/httpapi"
	"github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/postgres"
	redisinfra "github.com/freebooz-studio/xiaobandeng-game-platform/server/internal/infra/redis"
	"github.com/jackc/pgx/v5"
)

// main（服务入口）负责组装基础设施和HTTP/WSS服务。
func main() {
	cfg := config.Load()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	var writer *pgx.Conn
	if cfg.MahjongSingleWriter {
		claimed, err := postgres.ClaimMahjongWriter(ctx, cfg.PostgresURL)
		if err != nil {
			log.Fatal(err)
		}
		writer = claimed
		defer writer.Close(context.Background())
	}
	db, err := postgres.Connect(ctx, cfg.PostgresURL)
	if err != nil {
		log.Fatalf("连接 PostgreSQL 失败: %v", err)
	}
	defer db.Close()
	if err := postgres.Migrate(ctx, db); err != nil {
		log.Fatalf("执行数据库迁移失败: %v", err)
	}
	redisClient, err := redisinfra.Connect(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	if err != nil {
		log.Fatalf("连接 Redis 失败: %v", err)
	}
	defer redisClient.Close()

	handler, err := httpapi.NewRestored(ctx, cfg, db, redisClient)
	if err != nil {
		log.Fatalf("初始化 API 失败: %v", err)
	}
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: handler, ReadHeaderTimeout: 5 * time.Second}
	writerLost := make(chan struct{}, 1)
	stopCheck := make(chan struct{})
	writerCheckDone := make(chan struct{})
	if writer != nil {
		go monitorWriter(writer, stopCheck, writerCheckDone, writerLost)
	} else {
		close(writerCheckDone)
	}
	go func() {
		log.Printf("小板凳游戏平台服务启动: %s", cfg.HTTPAddr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP服务异常退出: %v", err)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	select {
	case <-stop:
	case <-writerLost:
		log.Print("麻将数据库写入锁连接失效，停止 API")
	}
	signal.Stop(stop)
	close(stopCheck)
	handler.Drain()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("优雅停止失败: %v", err)
		_ = server.Close()
	}
	<-writerCheckDone
}

func monitorWriter(writer *pgx.Conn, stop, done, lost chan struct{}) {
	defer close(done)
	timer := time.NewTicker(time.Second)
	defer timer.Stop()
	for {
		select {
		case <-stop:
			return
		case <-timer.C:
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			err := writer.Ping(ctx)
			cancel()
			if err != nil {
				lost <- struct{}{}
				return
			}
		}
	}
}
