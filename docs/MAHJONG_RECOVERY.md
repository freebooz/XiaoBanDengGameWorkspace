# 麻将数据库恢复演练

麻将的权威数据保存在 PostgreSQL。恢复范围包含账号会话、好友房成员和准备状态、牌局计时与私有牌墙、已确认命令、结算、复盘及牌桌举报。Redis 在当前隔离部署中随恢复服务重新连接，恢复过程以 PostgreSQL 快照为准。

## 演练步骤

1. 在隔离源服务上完成一局，再从原房开始下一局并确认一次操作。保存四个测试客户端的会话以核对账户归属。停止源端的写入进程后再进行演练。
2. 从工作区执行以下命令。脚本读取源库，使用同一 PostgreSQL 镜像在新容器中恢复，比较关键表行数，并记录备份 SHA-256。临时监听只绑定本机回环地址。

   ```powershell
   pwsh -NoProfile -File tools/test-mahjong-backup.ps1 `
     -SourceContainer <disposable-postgres> -SourceUser xbd_probe `
     -SourceDatabase xbd_probe -KeepRestored
   ```

3. 使用输出中的端口连接恢复库，启动独立 API。检查服务、PostgreSQL 与 Redis 就绪。使用原客户端会话重新入座，检查原房、座位、手牌与弃牌，再提交一项合法操作。超过已保存的绝对截止时间时，服务按规则处理超时。另从四个原账号读取上一局的分项和复盘。
4. 生产切换须明确降为单一写入实例。先确认旧 API 停止受理、恢复库和本局权威状态可读，再切换接入点。遇到恢复后已产生的新操作时，先核对数据差异再决定如何回退。正式备份应使用发布环境的加密存储、访问权限和保留期限。演练脚本清理临时转储文件，只保留校验清单。

完成后按脚本给出的命令停止本次恢复容器。测试 `TestMahjongBackupRestorePreservesSessionsHistoryAndActiveTable` 可自动验证上述应用流程，要求 `XBD_MAHJONG_TEST_BACKUP_SCRIPT` 指向该脚本，`XBD_MAHJONG_TEST_BACKUP_SOURCE_CONTAINER` 指向隔离源库，另设置真实 API 重启测试的 PostgreSQL、Redis 和 API 路径。

## 同库更新

麻将 Compose 默认设置 `XBD_MAHJONG_SINGLE_WRITER=1`。部署时保持每个写入实例启用该设置并直连同一个 PostgreSQL 数据库。API 启动先申请数据库会话级写入锁，再运行迁移、恢复和开放监听。占用锁时启动第二个实例会失败。不要把两个使用不同数据库的实例当成共享对局的副本。

向旧实例发送 SIGTERM，待它关闭活跃麻将连接、停止牌局计时并退出后再启动新版。启动后核对 `/health`，让客户端以原会话重连。恢复沿用数据库中已保存的截止时间。`TestMahjongSingleWriterRejectsOverlapAndResumesLiveTable` 可自动校验竞争启动拒绝、退出后四席恢复和下一步出牌。隔离环境已在 Linux 验证 SIGTERM，在 Windows 验证进程中断。此部署允许短时重连，正式环境仍需量测切换时长。
