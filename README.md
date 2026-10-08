# XiaoBanDengGamePlatform（小板凳游戏平台）

开发主体：**Freebooz Studio（Freebooz 工作室）**。

本仓库是“小板凳”棋牌游戏产品家族的统一工作空间。统一业务后端和运营管理后台为“小板凳象棋”“小板凳麻将（贵阳麻将）”“小板凳斗地主”“小板凳掼蛋”提供独立客户端工程。

## 一期产品标识

- 小板凳象棋：`ProductId=xbd_chinese_chess`，`GameId=chinese_chess`，`RuleSetId=standard`。
- 小板凳麻将：`ProductId=xbd_mahjong`，`GameId=mahjong`，`RuleSetId=guiyang`。
- 小板凳斗地主：`ProductId=xbd_landlord`，`GameId=landlord`，`RuleSetId=classic_three_player`。
- 小板凳掼蛋：`ProductId=xbd_guandan`，`GameId=guandan`，`RuleSetId=classic_partnership`。
- 所有正式规则都必须保存 `RuleVersion（规则版本）`，历史版本不可原地覆盖。

## 目录

- `server/`：Go 统一业务后端。
- `admin-web/`：Vue 3 + TypeScript 统一管理后台。
- `client/`：Godot 共享客户端框架与游戏模块。
- `products/`：独立 App 产品清单与品牌配置。
- `protocol/`：公共协议与字段规范。
- `deploy/`：Docker、本地部署配置。
- `tools/`：产品组合与构建工具。
- `docs/`：设计和开发说明。

## Docker 启动

```powershell
Copy-Item .env.example .env
docker compose up --build
```

默认地址：

- 业务 API：http://localhost:8080
- 健康检查：http://localhost:8080/health
- 管理后台：http://localhost:5173
- PostgreSQL：localhost:5432
- Redis：localhost:6379

> 微信 AppId、商户号、APIv3 Key 等绝不写入仓库。示例值仅用于说明环境变量名称。

## Godot 产品组合

```powershell
powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 chinese_chess
powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 mahjong
powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 landlord
powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 guandan
```

生成目录：

```text
client/.generated/chinese_chess/
client/.generated/mahjong/
client/.generated/landlord/
client/.generated/guandan/
```

安装 Godot 4.x 后可直接打开对应生成目录的 `project.godot`。

### 贵阳麻将本地对局

先运行 `docker compose up -d --build server`，再执行 `powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 -Product mahjong`。使用 Godot 打开 `client/.generated/mahjong/project.godot`，启动四个客户端，分别点击“游客登录”“快速对局”“准备”，四人到齐后进入同一牌桌。

麻将对局使用从虚幻项目导入的三维桌模型、可复用立体牌身及源项目牌面，提供低、中、高画质。服务端按贵阳麻将默认规则管理四人座位、108 张万筒条牌、骰子开门、摸打碰杠胡、七对、抢杠胡、特殊鸡及结算；仅向每位玩家发送其本人暗牌。对局支持断线后在服务进程存活期间按原账号重连。移植范围和验证记录见 `docs/MAHJONG_PORT.md`。

斗地主使用 Blender 建模的三维牌桌和 63×88×1.3 毫米立体扑克牌，牌面为 54 张独立纹理，提供低、中、高画质。登录后可进入大厅、单人训练，或匹配三名玩家并准备开局；叫地主、出牌、比牌和结算由服务端判定。可编辑模型、玩法范围和验证方法见 `docs/LANDLORD.md`。

掼蛋采用四人搭档、双副 108 张牌，每人 27 张；支持级牌、红桃配牌、排名升级、贡还、抗贡与过 A。斗地主和掼蛋共同引用 `client/game_framework/card3d` 的唯一一套扑克模型与纹理，可编辑源在 `SourceAssets/Poker`。生成掼蛋产品后打开 `client/.generated/guandan/project.godot`，四个客户端分别登录、快速对局、准备即可开局；大厅提供三个电脑对手的训练。说明与验证记录见 `docs/GUANDAN.md`。

象棋、麻将、斗地主和掼蛋均提供登录、大厅、训练、房间、三维对局入口。登录页可填写并保存服务端地址：PC 本机可使用 `http://127.0.0.1:8080`；安卓手机或平板在同一局域网内应填写运行服务端的电脑 IP 地址，例如 `http://192.168.1.10:8080`。客户端以 720×1280 竖屏为基准等比显示，在手机、平板和 PC 窗口尺寸下保留完整操作区。已完成桌面窗口尺寸检查；Android 安装包和实体设备验收仍需导出模板及设备测试。

## 设计原则

1. 账号、后台、钱包、支付、社交、房间、匹配统一。
2. 独立 App 通过 ProductId 区分，具体游戏用 GameId 区分，地方玩法用 RuleSetId 区分。
3. 服务端权威规则；客户端只提交操作意图。
4. AI 是旁路智能能力，不能替代正式 RuleSet（规则集）判定。
5. 微信登录在服务端交换身份；客户端不得直接把微信 Token 当平台登录凭据。
6. 支付必须经过服务端验签/回调确认后入账。
7. 钱包使用 Ledger（账本）模型；资产保留 Family/Product/Game/Channel 使用范围。
8. 重要代码、接口和业务边界使用中文注释，便于人工审核。

更多内容见 `ARCHITECTURE.md` 与 `PHASE1.md`。
