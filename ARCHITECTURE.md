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

### 2.1 三维表现基线

一期起，所有棋牌类游戏统一采用 3D Tabletop（桌面游戏三维表现）架构：棋盘、棋子、麻将牌、扑克牌、牌桌均为三维模型；材质统一使用 StandardMaterial3D/PBR（基于物理渲染）材质体系；主摄像机采用俯视或轻斜俯视构图；Godot 使用 Mobile Renderer（移动渲染器）作为 Windows/Android 共用视觉基线。2D 层仅承担 HUD、菜单、聊天、系统提示、AI 教学与复盘叠加。

共享目录 `client/game_framework/tabletop3d/` 提供 PBR 材质工厂、灯光、环境和俯视摄像机。具体游戏只负责创建自己的三维桌面内容，禁止重复搭建渲染基础设施。

### 2.2 对局计时基线

对局时长与单步计时统一采用服务端权威时间戳。服务端快照下发 `server_time_ms`、`match_started_at_ms`、`turn_started_at_ms`、`step_warning_seconds` 与 `step_countdown_seconds`；客户端只根据这些字段显示。第一期默认：单步前60秒正常计时，超过60秒进入30秒警示倒计时；倒计时首次出现和最后10秒提供声音提醒。是否在倒计时结束后判负、托管或自动出招由具体 RuleSet 决定，客户端不得自行裁决。

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