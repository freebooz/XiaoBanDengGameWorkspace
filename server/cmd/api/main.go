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
)

// main（服务入口）负责组装基础设施和HTTP/WSS服务。
func main(){
	cfg:=config.Load()
	ctx,cancel:=context.WithTimeout(context.Background(),15*time.Second);defer cancel()
	db,err:=postgres.Connect(ctx,cfg.PostgresURL)
	if err!=nil{log.Fatalf("连接 PostgreSQL 失败: %v",err)}
	defer db.Close()
	if err:=postgres.Migrate(ctx,db);err!=nil{log.Fatalf("执行数据库迁移失败: %v",err)}
	redisClient,err:=redisinfra.Connect(ctx,cfg.RedisAddr,cfg.RedisPassword,cfg.RedisDB)
	if err!=nil{log.Fatalf("连接 Redis 失败: %v",err)}
	defer redisClient.Close()

	server:=&http.Server{Addr:cfg.HTTPAddr,Handler:httpapi.New(cfg,db,redisClient),ReadHeaderTimeout:5*time.Second}
	go func(){
		log.Printf("小板凳游戏平台服务启动: %s",cfg.HTTPAddr)
		if err:=server.ListenAndServe();err!=nil && err!=http.ErrServerClosed{log.Fatalf("HTTP服务异常退出: %v",err)}
	}()
	stop:=make(chan os.Signal,1)
	signal.Notify(stop,syscall.SIGINT,syscall.SIGTERM)
	<-stop
	shutdownCtx,shutdownCancel:=context.WithTimeout(context.Background(),10*time.Second);defer shutdownCancel()
	if err:=server.Shutdown(shutdownCtx);err!=nil{log.Printf("优雅停止失败: %v",err)}
}