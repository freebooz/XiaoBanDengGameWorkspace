# 麻将举报审核

玩家在牌桌点开对手头像后可选择举报原因。后台按待审核、举报成立或已驳回筛选，可核对房号、局次、席位、原因和提交时间。结案记录由服务器保存审核员、结论、备注和时间。同一条举报只能结案一次，原操作的重试返回相同记录。

## 运行管理端

麻将部署以 `deploy/mahjong-local/compose.yml` 提供玩家入口。需要本机管理端时，在 Compose 中附加 `deploy/mahjong-local/admin.compose.yml`。管理端使用单独的回环 TLS 端口，浏览器和 API 同源。玩家入口的管理路由返回 404，原来的开发 Compose 不挂载管理员凭据。

`XBD_MAHJONG_ADMIN_CREDENTIALS` 指向 Compose 只读挂载的 JSON 文件。API 从 `XBD_ADMIN_CREDENTIAL_FILE` 读取，启动时拒绝格式错误或重复账号。为每位管理员生成独立的 32 字节随机值并使用无填充 Base64URL 表示。将该字符串的 SHA-256 十六进制摘要写入配置，通过受控凭据渠道单独发放原值。网页只在当前会话内存中使用原值。下方 `摘要` 替换为 64 位十六进制字符串。

```json
[
  {"name":"mahjong-reviewer", "token_sha256":"摘要", "capabilities":["mahjong:review"]}
]
```

`mahjong:review` 可处理举报。`platform:read` 可浏览既有运营统计和用户、房间、对局列表。按岗位授予权限，将摘要配置留在部署密钥目录。凭据撤销或轮换后，安全替换配置并按单写入者流程重启 API。关闭管理员浏览器标签页或点击退出会清除网页会话。正式环境的实名运营账号、SSO 和审计保留期限按发行渠道接入。

`wallet:grant_eggs` 可核对唯一有效玩家的昵称及余额，并发放鸡蛋。需要进入管理首页查看用户列表的运营人员同时配置 `platform:read`。每次发放记录操作人、目标昵称和请求编号，重试复用请求编号。好友房入座操作及鸡蛋通知请见 [麻将管理端实时监视与房间操作](MAHJONG_ADMIN_REALTIME.md)。

## 验收

从工作区运行 `pwsh -NoProfile -File tools/test-mahjong-linux-tls.ps1 -VerifyAdmin`。该验证生成一次性凭据并同源访问管理页面和举报接口，确认匿名拒绝、审核员可读队列且无平台读取权限、玩家入口持续隔离。附加 `-AdminBrowserProbe tools/test-mahjong-admin-browser.cjs` 可在安装了 Playwright 和 Chromium 的环境中验证浏览器完整流程，并从 PostgreSQL 核对同一笔结案。脚本使用隔离容器和预置举报，不向真实账号发送消息。

持久化验收 `TestMahjongAdminDispositionRealAPI` 从真实四人牌桌产生举报，验证审核员认证、结论唯一、重复请求和重启后的审核历史。
