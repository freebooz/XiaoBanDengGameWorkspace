# 小板凳游戏平台技术架构基线

## 1. 标识体系

平台统一使用五级标识：

```text
ProductId（独立产品）
  ↓
GameCategory（游戏类别）
  ↓
GameId（具体游戏）
  ↓
RuleSetId（规则集/地方玩法）
  ↓
RuleVersion（规则版本）
```

例如贵阳麻将：`xbd_mahjong / tile / mahjong / guiyang / 1.0.0`。

## 2. 客户端分层

```text
Product（产品壳）
  ↓
Game Module（具体游戏）
  ↓
Game Framework（Board/Tile/Card）
  ↓
Foundation（账号/网络/房间/UI/支付/AI协议）
```

Godot 产品采用“构建时组合”，不依赖运行时下载可执行代码。共享源码由 `tools/compose-godot.ps1` 按产品清单复制到临时生成工程。

## 3. 服务端分层

```text
HTTP/WSS Gateway
  ↓
Platform Services
  ├─ Account / Identity
  ├─ Product / Game Catalog
  ├─ Room / Matchmaking
  ├─ Wallet / Payment / Commerce
  ├─ Replay / Ranking / Operation
  └─ AI Gateway（预留）
  ↓
Game Framework
  ├─ BoardGameCore（棋盘类核心）
  ├─ TileGameCore（牌张类核心）
  └─ CardGameCore（扑克牌类核心，二期）
  ↓
RuleSet
```

服务端游戏处理原则：`Command（玩家意图） → RuleSet（确定性规则验证） → Event（游戏事件） → State（权威状态）`。

## 4. AI 边界

AI 支持 VsAI、Tutorial、Hint、Coach、Puzzle、ReplayAnalysis。
AI 只接收经过 VisibilityFilter（可见性过滤）的玩家可见状态和 LegalActions（合法动作集合）。客户端不得直接调用外部模型。模型不可进入正式多人对局的权威规则判定链路。

## 5. 账号与商业能力

统一 AccountId（平台账号）关联微信 OpenID/UnionID、手机号、游客身份。所有游戏共享同一账号，但独立维护 GameProfile（游戏档案）。

支付由 PaymentProvider（支付渠道接口）抽象。微信支付是一期启用渠道；Apple IAP、Google Play 等保留适配接口。钱包资产保存 Scope（使用范围），避免把不同商店规则下的付费资产无条件跨 App 共用。

## 6. 数据

- PostgreSQL：账号、商品、支付、钱包账本、战绩、规则版本、对局索引等长期数据。
- Redis：会话、在线状态、匹配队列、房间路由、短期快照。
- Game Node 内存：高频实时牌局/棋局状态。
- Snapshot + Event：用于重连、回放、客服复核和未来 AI 数据集。