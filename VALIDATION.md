# 第一期工程验证记录

验证日期：2026-09-29

## 已通过

1. Godot 产品组合脚本成功生成两个独立工程：
   - client/.generated/chinese_chess
   - client/.generated/mahjong
2. Go 后端在 golang:1.23-alpine 容器中执行 go test ./... 成功。
3. Go 后端 Linux 可执行文件构建成功。
4. Vue 3 + TypeScript 管理后台执行 vue-tsc --noEmit 和 vite build 成功。
5. Docker Compose 已实际启动 PostgreSQL、Redis、server、admin-web。
6. /health 返回 service/postgres/redis 全部 ok。
7. /api/v1/catalog 返回小板凳象棋和小板凳麻将·贵阳麻将两项。
8. POST /api/v1/auth/guest 可真实写入 PostgreSQL 并返回 AccountId。
9. POST /api/v1/rooms 可创建带 ProductId/GameId/RuleSetId/RuleVersion 的房间。
10. /api/v1/wallet 可查询家族级 xbd_point 资产，空账户按0返回。
11. /api/v1/ai/capabilities 返回6项AI预留能力。
12. 管理后台 http://localhost:5173 返回 HTTP 200。
13. 已安装并使用 Godot 4.7.2 对小板凳象棋、小板凳麻将两个生成工程执行 Headless 编辑器解析与主场景运行验证，均无脚本错误。
14. 客户端视觉基线已升级为 3D Tabletop：象棋棋盘/棋子、贵阳麻将牌/牌桌均使用三维模型，采用 StandardMaterial3D/PBR 材质与俯视/轻斜俯视摄像机。
15. 小板凳象棋双 WebSocket 客户端集成测试通过：红黑双方加入同一房间、权威走子、广播同步、回合切换及抢回合拒绝均通过。
16. 象棋服务端权威计时测试通过：双方就绪后下发对局/回合开始时间，合法走子后刷新下一回合开始时间，并下发60秒预警阈值与30秒倒计时配置。
17. Godot 计时界面运行验证通过：对局总时长、单步计时、圆形倒计时组件与程序化提醒音均可加载运行，未出现运行时异常。

## 当前环境限制

Runner 本机已安装 Godot 4.7.2，并完成两个产品的 Headless（无界面）解析及主场景运行验证。Windows/Android 正式导出仍需要继续校验导出模板、Android SDK/JDK、签名与渠道配置。

## 尚未声称完成的生产能力

- 微信 OpenSDK 真机授权、微信商户真实下单/验签/退款联调需要真实 AppId、商户号和证书。
- 贵阳麻将完整胡牌、番型、结算规则必须依据最终业务规则逐条验收后实现。
- 中国象棋当前实现基础走子规则，完整长将、长捉、和棋等竞赛规则仍需补齐。
- 当前 WebSocket 已验证实时通信通道，完整多人牌局 Command→RuleSet→Event→State 调度将在后续迭代继续接入。
- Android 正式签名、渠道SDK和发布包需真实签名材料。
- AI 当前为标准接口、功能开关与客户端表现层预留，未伪造真实模型能力。