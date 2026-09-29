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

## 当前环境限制

Runner 本机当前未发现 Godot 命令，因此未执行 Godot Headless（无界面）解析/导出验证。
产品组合工程、project.godot、Windows/Android export_presets.cfg 已生成，可在安装 Godot 4.x 后继续验证。

## 尚未声称完成的生产能力

- 微信 OpenSDK 真机授权、微信商户真实下单/验签/退款联调需要真实 AppId、商户号和证书。
- 贵阳麻将完整胡牌、番型、结算规则必须依据最终业务规则逐条验收后实现。
- 中国象棋当前实现基础走子规则，完整长将、长捉、和棋等竞赛规则仍需补齐。
- 当前 WebSocket 已验证实时通信通道，完整多人牌局 Command→RuleSet→Event→State 调度将在后续迭代继续接入。
- Android 正式签名、渠道SDK和发布包需真实签名材料。
- AI 当前为标准接口、功能开关与客户端表现层预留，未伪造真实模型能力。