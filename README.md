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

Compose 默认使用管理后台的 Vite 开发镜像，经同源代理访问业务 API。
开发和生产模式均需要服务端颁发的管理员凭据。使用根目录 Compose 联调时，需在服务端挂载凭据文件并配置 `XBD_ADMIN_CREDENTIAL_FILE`。
修改前端代码后运行 `docker compose up --build -d admin-web` 更新镜像；
单独检查生产构建可运行 `docker build --target production -t xbd-admin-production ./admin-web`。
管理员凭据与权限配置见 [麻将运营权限](docs/MAHJONG_MODERATION_OPERATIONS.md)。

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

象棋客户端生命周期回归检查（先生成并导入象棋工程）：

```powershell
godot --headless --path client/.generated/chinese_chess --editor --quit
godot --headless --path client/.generated/chinese_chess --script ../../tests/chess_lifecycle_test.gd --disable-vsync --max-fps 0
```

### 小板凳麻将本地对局

执行 `powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 -Product mahjong`，用 Godot 打开 `client/.generated/mahjong/project.godot`，并配置约定开发域名的公共测试 CA。游客登录后可选择贵阳捉鸡或基础 108。快速开局可自动匹配。好友房由一人创建，另外三人凭四位房号加入，准备后开局。人机训练可与三位电脑按所选规则对局。[开发域名与证书配置](docs/MAHJONG_WIFI_DOMAIN.md)

麻将对局使用导入的三维桌、牌身及牌面，提供低、中、高画质。服务端按房间锁定的版本处理牌墙、碰杠胡、超时和结算，仅向每位玩家发送其本人暗牌。服务进程存活且本局未结束时可按原账号回桌。玩法、预览和验证见 [麻将大厅、好友房与训练房](docs/MAHJONG_ONLINE_UI.md)；原始移植记录见 [贵阳麻将移植记录](docs/MAHJONG_PORT.md)。

斗地主使用 Blender 建模的三维牌桌和 63×88×1.3 毫米立体扑克牌，牌面为 54 张独立纹理，提供低、中、高画质。登录后可进入大厅、单人训练，或匹配三名玩家并准备开局；叫地主、出牌、比牌和结算由服务端判定。可编辑模型、玩法范围和验证方法见 `docs/LANDLORD.md`。

掼蛋采用四人搭档、双副 108 张牌，每人 27 张；支持级牌、红桃配牌、排名升级、贡还、抗贡与过 A。斗地主和掼蛋共同引用 `client/game_framework/card3d` 的唯一一套扑克模型与纹理，可编辑源在 `SourceAssets/Poker`。生成掼蛋产品后打开 `client/.generated/guandan/project.godot`，四个客户端分别登录、快速对局、准备即可开局；大厅提供三个电脑对手的训练。说明与验证记录见 `docs/GUANDAN.md`。

象棋、麻将、斗地主和掼蛋均提供登录、大厅、训练、房间和三维对局入口。生成工程默认使用 `https://api.xbd.freeboozstudio.test`。联调包使用该域名的有效证书，对局沿用同一域名的 WSS。回环服务用于隔离自动化测试。登录与大厅按实际窗口和安全区布局，进入对局后切换横屏，退出牌桌后恢复大厅显示。对局保留真实三维模型、透视相机、独立世界和低、中、高画质。扑克的黑桃、梅花和小王使用蓝色墨迹，红桃、方块和大王使用红色。横屏截图见 `artifacts/landscape/`。

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
