# XiaoBanDengGamePlatform（小板凳游戏平台）

开发主体：**Freebooz Studio（Freebooz 工作室）**。

本仓库是“小板凳”棋牌游戏产品家族的统一工作空间。第一期交付统一业务后端、统一运营管理后台，以及“小板凳象棋”“小板凳麻将（贵阳麻将）”两个独立产品的 Windows PC 与 Android 客户端工程。

## 一期产品标识

- 小板凳象棋：`ProductId=xbd_chinese_chess`，`GameId=chinese_chess`，`RuleSetId=standard`。
- 小板凳麻将：`ProductId=xbd_mahjong`，`GameId=mahjong`，`RuleSetId=guiyang`。
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

Compose 默认使用管理后台的 Vite 开发镜像，可通过“开发管理员登录”进入后台，
用于本地联调；修改前端代码后运行 `docker compose up --build -d admin-web` 更新镜像。
需要单独检查生产构建时，可运行
`docker build --target production -t xbd-admin-production ./admin-web`。
生产构建不启用开发登录，正式管理员认证服务仍待接入。

> 微信 AppId、商户号、APIv3 Key 等绝不写入仓库。示例值仅用于说明环境变量名称。

## Godot 产品组合

```powershell
powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 chinese_chess
powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 mahjong
```

生成目录：

```text
client/.generated/chinese_chess/
client/.generated/mahjong/
```

安装 Godot 4.x 后可直接打开对应生成目录的 `project.godot`。

象棋客户端生命周期回归检查（先生成并导入象棋工程）：

```powershell
godot --headless --path client/.generated/chinese_chess --editor --quit
godot --headless --path client/.generated/chinese_chess --script ../../tests/chess_lifecycle_test.gd
```

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
