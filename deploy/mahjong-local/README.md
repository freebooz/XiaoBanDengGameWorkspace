# 麻将 Linux 后端与本机 HTTPS 验证

在工作区根目录运行 `pwsh -NoProfile -File tools/test-mahjong-linux-tls.ps1`。需要 PowerShell 7、Linux 容器模式的 Docker Compose 和 OpenSSL。脚本默认查找 PATH 中的 OpenSSL，也支持 `-OpenSslPath` 指定路径。运行会从当前服务端源码构建 Linux 镜像，在独立 Compose 项目中连接 PostgreSQL 和 Redis，并生成七天有效的本机测试 CA 与服务端证书。

通过时输出 `MAHJONG_TLS_OK`。验证检查可信 HTTPS、游客登录与会话恢复、未认证访问拒绝、已认证 WSS 订阅和大厅首包。诊断进程仅信任本次证书链，继续校验主机名，且不修改系统证书库。

使用 `-KeepRunning` 保留已验证的实例，供同一台机器上的客户端连接。默认选择临时端口，也可以指定 `-Port 18443`。使用输出中的 `https://127.0.0.1:<port>` 和本次 `ca.crt`，按客户端支持的方式显式信任该测试 CA。运行结束后执行脚本输出的 `down -v` 命令，只会清除此验证项目及其数据库卷。验证运行产生的文件位于工作区 `.tmp` 中，以输出的项目名标识。

## 暴露范围

- 仅 Nginx 的 TLS 端口绑定本机回环地址。API、PostgreSQL、Redis 在内部 Compose 网络中通信。
- 客户端可访问健康状态、目录、游客登录、账号注册与密码登录、会话恢复、麻将 WSS 和本人战绩。边缘 `/health` 依据内部后端及依赖就绪情况返回简要状态，详细依赖结果留在内部。
- 管理接口、通用 WebSocket、钱包及其他服务端路由均不经过此代理发布。运行中的内部详细健康可用 `docker compose ... exec -T api wget -qO- http://127.0.0.1:8080/health` 查询。

该配置面向隔离本机验证。外部域名、公开证书、移动端信任链和真实设备网络均需在正式部署环境另行验收。

## 管理端实时监视

同时传入 `-VerifyMonitor -KeepRunning` 可启动独立管理端。可用 `-AdminPort` 固定本机管理端口。程序输出管理端的 `/monitor` 地址。运行前可由当前进程环境传入测试凭据 `XBD_MAHJONG_MONITOR_CREDENTIAL`，服务配置只保存其 SHA-256 摘要。正式环境继续使用管理端权限配置中的 `platform:read`。详见[麻将运营权限](../../docs/MAHJONG_MODERATION_OPERATIONS.md)。

综合工作台、实时监视和房间中心以有权限的会话订阅 `GET /api/v1/admin/monitor/stream`。请使用与客户端同一 Compose 项目输出的管理地址。依赖健康每 5 秒探测一次。玩家网关不发布监视接口。麻将可以显示大厅闲置、等待、对局、断线重连与结算中的玩家。其他接入游戏当前从房间与对局连接统计，未接入的大厅状态用破折号显示。
