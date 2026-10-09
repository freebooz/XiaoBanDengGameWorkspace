# 2026-10-09 管理后台剩余问题修改记录

## 范围与基线

继续原草稿 PR #1 的 `48f87ea1f12c7f65e9a545a8db252a31c063497c`。不修改主分支，不添加管理写操作。
后台仍基于 Vue 3、TypeScript、Element Plus、Vue Router、Pinia；接口沿用原有分层。
本轮只实现剩余项中已有真实基础的能力，不伪造麻将对局、支付结算、账号认证玩家或视频回放。

## 修改

1. 只读管理员认证：bcrypt 口令哈希由部署环境提供；Redis 服务端会话；12小时 HttpOnly/SameSite Cookie；生产安全 Cookie 默认开启。登录失败节流，未配置或认证服务故障拒绝访问。管理查询统一验证会话，业务接口仅 GET。
2. 浏览器登录、刷新恢复、注销、离线重试；移除开发 localStorage 授权。会话恢复与业务请求均绑定身份代次，迟到响应不能覆盖新登录。
3. 象棋复用现有 `game_matches/game_events/game_snapshots`，增量字段与历史席位表。双方就绪保存初始快照；合法走子、事件、快照及结果事务性更新；非法指令不写入；失败撤回棋盘且停止房间。
4. 同一目录贯通 HTTP 房间、WebSocket 与管理查询；显示座位、客户端标识和本进程连接事实。玩家断线记录 aborted，替补就绪创建新 UUID，不覆盖历史。
5. 原对局详情接口新增事件/快照独立分页参数，使用 COUNT/LIMIT/OFFSET。前端支持跨页快照逐帧查看；有效象棋坐标展示只读棋盘，未知格式保留 JSON。
6. 开发来源在混合列表逐行标识，详情也明确标识；概览排除显式 development 房间和对局。历史 source=NULL 记录仍保留。
7. Element Plus 按需装载，品牌覆盖使用 body 作用域，避免路由 CSS 后加载覆盖11px正文和橙金色。Vite/Nginx同源代理；可信代理配置与来源头覆写防止伪造 IP。
8. 添加隔离数据库/Redis 集成测试、可复跑的浏览器脚本与 GitHub Actions 工作流。

## 已实际执行

- `npm test -- --run`：98项通过，14个测试文件。包含认证、恢复/注销、旧业务401竞态、可信来源代理、空态/失败/离线/重试、分页筛选、详情竞态、回放及混合开发来源。
- `npm run build`：TypeScript 类型检查、生产构建通过。最大 JS 文件150.17kB，gzip58.57kB；原基线1035.15kB/gzip341.42kB，缩减85.49%；无500kB告警。入口CSS12.17kB。
- Go 1.23.12：`go test -race -count=1 ./...`通过；未设连接参数的标准数据库/Redis用例明确 skip。`go build ./cmd/api`通过。
- 真实 Redis 7.2.7、实际 Go HTTP/WebSocket 服务与 PGlite 0.5.8 PostgreSQL 引擎/socket：`TestAdminRealServices`通过，验证幂等迁移、真实登录、未授权401、写操作405、合法/非法走子、席位/快照/事件持久化、服务端分页、断线中止、历史与会话跨实例恢复及注销。
- 生产dist经 Vite preview 同源代理，实际 Chromium/Playwright 完成15组烟测：真实Cookie登录/注销、双客户端走子、房间连接、事件、快照棋盘、回放、查询空态；1366×768、1440×900、1920×1080加载/刷新/11px正文/12px表头/品牌色/页面宽度。HTTP500和离线由明确网络注入验证。
- 独立审查发现并修复：开发来源漏标、旧业务401清新身份、懒加载样式覆盖及代理共享限流来源；均补回归。

PGlite 是嵌入式 PostgreSQL 引擎，其连接复用不等同标准多进程 PostgreSQL。以上兼容联调不能替代 PostgreSQL 17 的并发验证、Docker镜像与Nginx运行验证。

## 标准服务自动化验证

工作流 `.github/workflows/admin-readonly.yml` 使用 PostgreSQL17、Redis7服务，执行 Go race、真实仓储迁移/事务回滚/并发序号、API→WebSocket→管理查询，再执行前端回归及 Docker 两种前端/后端镜像构建、Nginx配置校验和生产镜像真实浏览器烟测。

实际运行已完成并全部成功：

- 验证提交：`9a0e82d703b1cb91ff18d23fc20179f51020c8cc`。
- [GitHub Actions 实际运行结果](https://github.com/freebooz/XiaoBanDengGameWorkspace/actions/runs/37876375300)，另一次push触发运行也成功。
- 标准 PostgreSQL17/Redis7 的 Go race 与真实仓储/HTTP集成通过，包含迁移幂等及旧记录保留、创建/走子事务回滚、同序号并发只能成功一次、分页及跨实例历史/会话读取。
- 前端98项回归、TypeScript与生产构建通过。
- 后端、开发前端、生产前端三个Docker镜像构建通过；生产镜像 `nginx -t` 与 `docker compose config --quiet` 通过。
- 实际生产Nginx镜像代理实际Go服务与标准数据库，15组真实Chromium烟测全部通过；浏览器结果由工作流上传为 `admin-browser-results`。

当前本地仍没有 Docker。标准容器验证来自上述实际CI运行，不能描述为本地执行；本地PGlite结果另列，未混同。

## 复跑

```bash
cd server
go test -race -count=1 ./...
# 使用隔离测试库/Redis，不能指向生产；真实仓储测试自动建立随机临时schema。
TEST_POSTGRES_URL="$ISOLATED_TEST_DSN" TEST_REDIS_ADDR="$ISOLATED_TEST_REDIS" \
XBD_TEST_POSTGRES_DSN="$ISOLATED_TEST_DSN" go test -race -count=1 ./...
cd ../admin-web
npm ci
npm test -- --run
npm run build
npx playwright install chromium
# 启动隔离后端/代理并显式开启 development 房间，注入测试凭据。
TEST_ADMIN_BASE_URL="$ISOLATED_ADMIN_URL" TEST_ADMIN_USERNAME="$TEST_OPERATOR" \
TEST_ADMIN_PASSWORD="$TEST_PASSWORD" node scripts/readonly-smoke.mjs
```

## 剩余边界

- 生产部署须配置管理员秘密、HTTPS安全Cookie及精确可信代理；不交付共享默认口令。
- 活动房间目录与棋盘仍在当前进程内存，不跨节点聚合，不在崩溃后重建；崩溃遗留playing记录没有自动恢复/中止策略。不能无差别中止其他节点拥有的对局。
- client_id 为客户端标识，不是平台认证账号；未扩展游戏指令权限或玩家账号系统。
- 当前Godot象棋演示仍使用固定 `manual-chess-001` 房间。开发演示必须显式开启 `DEVELOPMENT_ROOMS=true`；正式模式须由大厅/房间创建流程提供已有目录中的 room_id。此次未修改或运行Godot客户端。
- 只读回放读取已有快照，不提供视频；未接入麻将真实牌局、资金结算或完整竞赛规则。
- 此记录的后续提交只更新文档；实际程序代码与上述全绿验证提交一致。
