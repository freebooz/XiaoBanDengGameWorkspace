# 小板凳运营管理后台 V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有单文件 Demo 后台升级为品牌化、模块化、可持续扩展的“小板凳游戏运营平台”，完成登录、综合工作台、用户中心、游戏中心、房间中心、对局中心，并补齐一期所需只读管理 API。

**Architecture:** 前端继续使用 Vue 3 + TypeScript + Vite + Element Plus，引入 Vue Router（路由）与 Pinia（状态管理），按领域拆分页面、布局、服务与公共组件。Go 后端新增只读 Admin Service（管理服务）与管理查询 API，优先读取现有 PostgreSQL/Room Manager（房间管理器）真实数据；缺失数据返回空集合或明确 `data_source=development`，不伪造生产运营数字。

**Tech Stack:** Vue 3、TypeScript、Vite、Element Plus、Vue Router、Pinia、Vitest、Go 1.23、PostgreSQL、Redis、Docker Compose

**Spec:** `docs/superpowers/specs/2026-09-30-xiaobandeng-admin-design.md`

## Global Constraints

- 保留现有 `Vue 3 + TypeScript + Vite + Element Plus` 技术栈，不引入第二套 UI 框架。
- 新增 `vue-router（Vue 路由）` 与 `pinia（状态管理）`。
- 采用现代企业风：暖黑/深棕黑侧栏、米白内容区、小板凳橙金主色。
- 主品牌橙金固定为 `#D48A3A`，高亮浅金 `#F0B45A`，侧栏 `#181411`，内容背景 `#F5F2ED`。
- 表格正文约 `11px`，表头约 `12px`，保持紧凑风格。
- 核心 PC 验收宽度：1366×768、1440×900、1920×1080。
- 所有新增自研代码必须有清晰中文注释。
- 管理 API 第一轮只读，不实现踢人、强制关房、冻结账号等高风险写操作。
- 不伪造生产业务数字；缺失统计显示“待接入”或明确开发数据标识。
- 小板凳 Logo 必须进入登录页、侧栏、折叠品牌标识、Favicon。
- 当前工作区为增量修改，禁止清空重建工程。

## Review Focus

1. 后端完全离线时：登录页和后台框架仍可打开，工作台显示“服务离线”而不是白屏；Task 3/4 的前端测试必须覆盖。
2. 空数据库/无房间/无对局时：用户、房间、对局列表显示品牌化空状态，不出现 JS/Go 错误；Task 5/7/8 测试覆盖。
3. 1366×768 且侧栏展开时：核心表格和详情抽屉不得把主操作按钮挤出可视区；Task 9 响应式测试/人工验收覆盖。
4. Mock/开发数据存在时：页面必须显示“开发数据”标识，且不能与真实 API 数据混淆；Task 4/5 测试覆盖。
5. 浏览器直接刷新 `/users`、`/rooms`、`/matches` 时：路由必须正确恢复并渲染页面；Task 2 路由测试和 Nginx fallback 验证覆盖。

---

## File Structure

### 前端新增/重构

- `admin-web/src/main.ts`：应用入口，只注册 Router、Pinia、Element Plus。
- `admin-web/src/App.vue`：仅保留 `<router-view />`。
- `admin-web/src/app/router/index.ts`：路由定义和登录守卫。
- `admin-web/src/app/store/auth.ts`：管理员会话、开发 Mock 登录。
- `admin-web/src/app/store/platform.ts`：平台健康与目录公共状态。
- `admin-web/src/layouts/AdminLayout.vue`：后台三段式主布局。
- `admin-web/src/layouts/Sidebar.vue`：品牌导航与折叠。
- `admin-web/src/layouts/HeaderBar.vue`：面包屑、标题、管理员区。
- `admin-web/src/layouts/PageContainer.vue`：统一内容容器。
- `admin-web/src/components/BrandLogo.vue`：小板凳品牌 Logo 展示。
- `admin-web/src/components/MetricCard.vue`：指标卡。
- `admin-web/src/components/FilterBar.vue`：统一筛选条。
- `admin-web/src/components/StatusTag.vue`：统一状态标签。
- `admin-web/src/components/DetailDrawer.vue`：统一右侧详情抽屉。
- `admin-web/src/components/DevelopmentBadge.vue`：开发数据标识。
- `admin-web/src/modules/auth/LoginPage.vue`：品牌登录页。
- `admin-web/src/modules/dashboard/DashboardPage.vue`：综合工作台。
- `admin-web/src/modules/users/UsersPage.vue`：用户中心。
- `admin-web/src/modules/users/UserDetailDrawer.vue`：用户详情。
- `admin-web/src/modules/games/GamesPage.vue`：产品/游戏/规则中心。
- `admin-web/src/modules/rooms/RoomsPage.vue`：房间中心。
- `admin-web/src/modules/rooms/RoomDetailDrawer.vue`：房间详情。
- `admin-web/src/modules/matches/MatchesPage.vue`：对局中心。
- `admin-web/src/modules/matches/MatchDetailDrawer.vue`：对局详情/Event/Snapshot/Replay 结构。
- `admin-web/src/services/api/client.ts`：统一 HTTP 客户端。
- `admin-web/src/services/api/admin.ts`：管理 API。
- `admin-web/src/services/api/types.ts`：前后端 DTO 类型。
- `admin-web/src/assets/brand/logo.svg`：完整小板凳品牌 Logo。
- `admin-web/src/assets/brand/logo-mark.svg`：品牌图形标识。
- `admin-web/public/favicon.svg`：浏览器图标。
- `admin-web/src/styles/tokens.css`：品牌设计变量。
- `admin-web/src/styles/global.css`：全局样式。
- `admin-web/src/styles/element.css`：Element Plus 紧凑化覆盖。
- `admin-web/src/styles.css`：删除或改为兼容入口。
- `admin-web/src/**/*.spec.ts`：Vitest 单元/组件测试。
- `admin-web/vitest.config.ts`：前端测试配置。

### 后端新增/修改

- `server/internal/platform/admin/models.go`：管理后台 DTO。
- `server/internal/platform/admin/service.go`：只读管理查询服务。
- `server/internal/platform/admin/service_test.go`：管理服务测试。
- `server/internal/platform/room/manager.go`：补充 `Get(roomID string) (Room, bool)`。
- `server/internal/httpapi/admin_handlers.go`：Admin HTTP Handler（管理接口处理器）。
- `server/internal/httpapi/admin_handlers_test.go`：接口测试。
- `server/internal/httpapi/server.go`：注册管理接口并注入 Admin Service。

---

### Task 1: 前端依赖、测试基线与设计变量

**Files:**
- Modify: `admin-web/package.json`
- Create: `admin-web/vitest.config.ts`
- Create: `admin-web/src/styles/tokens.css`
- Create: `admin-web/src/styles/global.css`
- Create: `admin-web/src/styles/element.css`
- Modify: `admin-web/src/styles.css`
- Test: `admin-web/src/styles/design-tokens.spec.ts`

**Interfaces:**
- Produces: CSS 变量 `--xbd-brand-primary`、`--xbd-sidebar-bg`、`--xbd-page-bg`；测试命令 `npm run test`。
- Consumes: 无。

- [ ] **Step 1: 写失败测试**
  - 新建 `design-tokens.spec.ts`，断言 tokens 文件包含 `#D48A3A`、`#181411`、`#F5F2ED`，并断言 Element Plus 表格正文规则为 11px。

- [ ] **Step 2: 运行测试确认失败**
  - Run: `npm run test -- --run src/styles/design-tokens.spec.ts`
  - Expected: FAIL，原因是 Vitest/test script 或设计变量尚不存在。

- [ ] **Step 3: 安装并配置最小前端基础依赖**
  - 在 `package.json` 增加：
    - `vue-router`
    - `pinia`
    - devDependencies: `vitest`、`jsdom`、`@vue/test-utils`
  - scripts 增加 `test: "vitest"`。

- [ ] **Step 4: 创建品牌变量和 Element Plus 紧凑主题**
  - `tokens.css` 固定设计值。
  - `element.css` 将表格正文约束为 11px、表头 12px，并统一卡片、按钮、输入框、抽屉圆角/边框。
  - `global.css` 负责全局布局、背景、字体和滚动条。

- [ ] **Step 5: 运行测试**
  - Run: `npm run test -- --run src/styles/design-tokens.spec.ts`
  - Expected: PASS。

- [ ] **Step 6: 构建验证**
  - Run: `npm run build`
  - Expected: TypeScript + Vite 构建通过。

---

### Task 2: 路由、Pinia 与后台主框架

**Files:**
- Modify: `admin-web/src/main.ts`
- Replace: `admin-web/src/App.vue`
- Create: `admin-web/src/app/router/index.ts`
- Create: `admin-web/src/app/store/auth.ts`
- Create: `admin-web/src/app/store/platform.ts`
- Create: `admin-web/src/layouts/AdminLayout.vue`
- Create: `admin-web/src/layouts/Sidebar.vue`
- Create: `admin-web/src/layouts/HeaderBar.vue`
- Create: `admin-web/src/layouts/PageContainer.vue`
- Test: `admin-web/src/app/router/router.spec.ts`

**Interfaces:**
- Produces:
  - `router`
  - `useAuthStore()`
  - `usePlatformStore()`
  - `AdminLayout.vue`
- Consumes: Task 1 品牌变量。

- [ ] **Step 1: 写路由失败测试**
  - 断言存在 `/login`、`/dashboard`、`/users`、`/games/products`、`/rooms`、`/matches`。
  - 断言未登录访问受保护路由会重定向 `/login`。
  - 断言开发 Mock 会话存在时直接刷新 `/users` 不被错误重定向。

- [ ] **Step 2: 运行测试确认失败**
  - Run: `npm run test -- --run src/app/router/router.spec.ts`
  - Expected: FAIL，现有项目无 router/store。

- [ ] **Step 3: 实现 `useAuthStore`**
  - 接口：
    - `isAuthenticated: boolean`
    - `adminName: string`
    - `loginDevelopment(): void`
    - `logout(): void`
  - 开发 Mock 登录仅在 `import.meta.env.DEV` 下可用。

- [ ] **Step 4: 实现路由和主布局**
  - `App.vue` 只保留 RouterView。
  - AdminLayout 内部使用 Sidebar + HeaderBar + RouterView。
  - Sidebar 支持折叠状态，状态由 app/platform store 管理。

- [ ] **Step 5: 运行路由测试**
  - Run: `npm run test -- --run src/app/router/router.spec.ts`
  - Expected: PASS。

- [ ] **Step 6: 构建验证**
  - Run: `npm run build`
  - Expected: PASS。

---

### Task 3: 小板凳品牌 Logo 与品牌登录页

**Files:**
- Create: `admin-web/src/assets/brand/logo.svg`
- Create: `admin-web/src/assets/brand/logo-mark.svg`
- Create: `admin-web/public/favicon.svg`
- Create: `admin-web/src/components/BrandLogo.vue`
- Create: `admin-web/src/components/DevelopmentBadge.vue`
- Create: `admin-web/src/modules/auth/LoginPage.vue`
- Modify: `admin-web/index.html`
- Modify: `admin-web/src/layouts/Sidebar.vue`
- Test: `admin-web/src/modules/auth/LoginPage.spec.ts`

**Interfaces:**
- Produces: `BrandLogo.vue` props `compact?: boolean`、`showSubtitle?: boolean`。
- Consumes: Task 1 样式、Task 2 auth store/router。

- [ ] **Step 1: 写登录页失败测试**
  - 断言显示“小板凳游戏运营平台”。
  - 开发环境显示“开发环境”标识。
  - 点击“开发管理员登录”调用 `loginDevelopment()` 并进入 `/dashboard`。
  - Logo alt/可访问文本存在。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/modules/auth/LoginPage.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 创建小板凳品牌 SVG**
  - 完整 Logo 使用“小板凳凳体图形 + 中文小板凳字标”的简洁矢量版本。
  - `logo-mark.svg` 只保留凳体图形，供侧栏折叠/Favicon 使用。
  - 不使用临时“凳”字色块。

- [ ] **Step 4: 实现登录页和侧栏 Logo**
  - 登录页现代企业风，不使用游戏客户端复杂背景。
  - 侧栏展开显示 Logo + “小板凳 / 游戏运营平台”，折叠仅显示 mark。

- [ ] **Step 5: 测试并构建**
  - Run: `npm run test -- --run src/modules/auth/LoginPage.spec.ts && npm run build`
  - Expected: PASS。

---

### Task 4: Go 只读管理 API 基础层

**Files:**
- Create: `server/internal/platform/admin/models.go`
- Create: `server/internal/platform/admin/service.go`
- Create: `server/internal/platform/admin/service_test.go`
- Create: `server/internal/httpapi/admin_handlers.go`
- Create: `server/internal/httpapi/admin_handlers_test.go`
- Modify: `server/internal/platform/room/manager.go`
- Modify: `server/internal/httpapi/server.go`

**Interfaces:**
- Produces:
  - `admin.NewService(db *pgxpool.Pool, rooms *room.Manager) *admin.Service`
  - `func (s *Service) Overview(ctx context.Context) (Overview, error)`
  - `func (s *Service) ListUsers(ctx context.Context, q UserQuery) (Page[UserSummary], error)`
  - `func (s *Service) ListMatches(ctx context.Context, q MatchQuery) (Page[MatchSummary], error)`
  - `func (s *Service) MatchDetail(ctx context.Context, matchID string) (MatchDetail, error)`
  - `func (m *room.Manager) Get(roomID string) (room.Room, bool)`
- HTTP:
  - `GET /api/v1/admin/overview`
  - `GET /api/v1/admin/users`
  - `GET /api/v1/admin/rooms`
  - `GET /api/v1/admin/rooms/{roomId}`
  - `GET /api/v1/admin/matches`
  - `GET /api/v1/admin/matches/{matchId}`
- Consumes: 现有 PostgreSQL schema、room.Manager。

- [ ] **Step 1: 写管理服务失败测试**
  - 空数据库时 Overview 返回 0，而非伪造数据。
  - ListUsers 支持 page/page_size/status 过滤。
  - ListMatches 返回现有 `game_matches` 记录或空数组。
  - MatchDetail 查不到时返回明确 not-found error。

- [ ] **Step 2: 运行失败测试**
  - Run: `go test ./internal/platform/admin ./internal/httpapi -run Admin -v`
  - Expected: FAIL，admin package/handler 尚不存在。

- [ ] **Step 3: 实现 Admin DTO 与 Service**
  - Overview 字段：`registered_users`、`active_rooms`、`total_matches`、`service_time`、`data_source`。
  - 当前没有 DAU/在线用户可靠数据时返回 `null/0 + data_source="partial"`，前端显示“待接入”，禁止随机数。

- [ ] **Step 4: 扩展 room.Manager**
  - 新增 `Get(roomID string) (Room, bool)`。
  - List 结果按 `CreatedAt DESC` 排序，保证后台稳定展示。

- [ ] **Step 5: 实现 Admin HTTP handlers**
  - 参数错误返回 400。
  - 不存在详情返回 404。
  - 数据库错误返回 500。
  - 所有 JSON 字段采用 snake_case。

- [ ] **Step 6: 运行测试**
  - Run: `go test ./... -v`
  - Expected: PASS。

---

### Task 5: 前端 API 服务层与降级/开发数据策略

**Files:**
- Replace: `admin-web/src/api.ts` 为兼容转发或移除旧调用
- Create: `admin-web/src/services/api/types.ts`
- Create: `admin-web/src/services/api/client.ts`
- Create: `admin-web/src/services/api/admin.ts`
- Test: `admin-web/src/services/api/admin.spec.ts`

**Interfaces:**
- Produces:
  - `adminApi.overview()`
  - `adminApi.users(query)`
  - `adminApi.rooms(query)`
  - `adminApi.roomDetail(roomId)`
  - `adminApi.matches(query)`
  - `adminApi.matchDetail(matchId)`
  - `platformApi.health()`
  - `platformApi.catalog()`
- Consumes: Task 4 HTTP API。

- [ ] **Step 1: 写 API 失败/空数据测试**
  - 500/网络错误必须 throw 结构化 `ApiError`。
  - 空数组保持空数组，不生成 Mock 业务数字。
  - 当显式 DevelopmentProvider 被使用时返回 `data_source="development"`。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/services/api/admin.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 实现统一客户端**
  - `apiGet<T>(path, query?)`
  - 统一 timeout、JSON 错误读取、URLSearchParams。
  - API base 继续使用 `VITE_API_BASE_URL`。

- [ ] **Step 4: 实现 admin/platform API**
  - 严格使用 Task 4 DTO 名称。
  - 开发数据提供者独立文件/分支，页面不可直接写假数组。

- [ ] **Step 5: 测试**
  - Run: `npm run test -- --run src/services/api/admin.spec.ts`
  - Expected: PASS。

---

### Task 6: 综合工作台

**Files:**
- Create: `admin-web/src/components/MetricCard.vue`
- Create: `admin-web/src/components/StatusTag.vue`
- Create: `admin-web/src/modules/dashboard/DashboardPage.vue`
- Create: `admin-web/src/modules/dashboard/DashboardPage.spec.ts`
- Modify: `admin-web/src/app/router/index.ts`

**Interfaces:**
- Produces: `DashboardPage`。
- Consumes: `adminApi.overview`、`platformApi.health`、`platformApi.catalog`。

- [ ] **Step 1: 写工作台失败测试**
  - 后端在线显示服务/PostgreSQL/Redis 状态。
  - registered_users/active_rooms/total_matches 显示真实值。
  - 不可用指标显示“待接入”。
  - API 报错显示“服务离线”卡片且页面仍渲染。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/modules/dashboard/DashboardPage.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 实现工作台**
  - 第一行 MetricCard。
  - 第二行产品运行概览 + 服务健康。
  - 在线趋势区域先使用“待接入”占位，不生成虚假曲线。
  - 使用品牌色和精致卡片阴影，不使用默认 Element Plus 视觉。

- [ ] **Step 4: 测试与构建**
  - Run: `npm run test -- --run src/modules/dashboard/DashboardPage.spec.ts && npm run build`
  - Expected: PASS。

---

### Task 7: 用户中心

**Files:**
- Create: `admin-web/src/components/FilterBar.vue`
- Create: `admin-web/src/components/DetailDrawer.vue`
- Create: `admin-web/src/modules/users/UsersPage.vue`
- Create: `admin-web/src/modules/users/UserDetailDrawer.vue`
- Create: `admin-web/src/modules/users/UsersPage.spec.ts`
- Modify: `admin-web/src/app/router/index.ts`

**Interfaces:**
- Produces: 用户列表与详情抽屉。
- Consumes: `adminApi.users`。

- [ ] **Step 1: 写失败测试**
  - 空数据显示 EmptyState。
  - AccountId/status 条件改变后查询参数正确。
  - 点击用户打开抽屉。
  - 开发字段显示 DevelopmentBadge，不伪装成生产数据。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/modules/users/UsersPage.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 实现用户列表**
  - 字段：AccountId、昵称、账号类型、状态、注册时间。
  - 微信绑定/最近登录/在线状态数据模型缺失时显示“待接入”。

- [ ] **Step 4: 实现详情抽屉**
  - Tabs：基础资料、身份绑定、游戏档案、登录记录、平台资产。
  - 只有真实字段展示值；其余使用 EmptyState/待接入。

- [ ] **Step 5: 测试与构建**
  - Run: `npm run test -- --run src/modules/users/UsersPage.spec.ts && npm run build`
  - Expected: PASS。

---

### Task 8: 游戏中心

**Files:**
- Create: `admin-web/src/modules/games/GamesPage.vue`
- Create: `admin-web/src/modules/games/GamesPage.spec.ts`
- Modify: `admin-web/src/app/router/index.ts`

**Interfaces:**
- Produces: 产品/游戏/规则集统一查看页。
- Consumes: `platformApi.catalog()`。

- [ ] **Step 1: 写失败测试**
  - 必须展示 `xbd_chinese_chess / chinese_chess / standard / 1.0.0`。
  - 必须展示 `xbd_mahjong / mahjong / guiyang / 1.0.0`。
  - ProductId、GameId、RuleSetId、RuleVersion 为独立列。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/modules/games/GamesPage.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 实现游戏中心**
  - 顶部产品统计。
  - 筛选产品/类别/启用状态。
  - 表格与规则版本状态标签。

- [ ] **Step 4: 测试与构建**
  - Run: `npm run test -- --run src/modules/games/GamesPage.spec.ts && npm run build`
  - Expected: PASS。

---

### Task 9: 房间中心

**Files:**
- Create: `admin-web/src/modules/rooms/RoomsPage.vue`
- Create: `admin-web/src/modules/rooms/RoomDetailDrawer.vue`
- Create: `admin-web/src/modules/rooms/RoomsPage.spec.ts`
- Modify: `admin-web/src/app/router/index.ts`

**Interfaces:**
- Produces: 实时房间列表和详情。
- Consumes: `adminApi.rooms`、`adminApi.roomDetail`。

- [ ] **Step 1: 写失败测试**
  - 空房间显示空状态。
  - GameId/RuleSet/State 过滤参数正确。
  - 点击 RoomId 打开详情抽屉。
  - 1366 宽度时表格可横向滚动而不是压缩关键列。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/modules/rooms/RoomsPage.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 实现房间中心**
  - 列表：RoomId、ProductId、GameId、RuleSetId、RuleVersion、状态、创建时间、当前时长。
  - 详情抽屉：房间摘要、规则信息、玩家/座位（未接入显示待接入）、连接状态（未接入显示待接入）。
  - 不提供强制关闭/踢人按钮。

- [ ] **Step 4: 测试与构建**
  - Run: `npm run test -- --run src/modules/rooms/RoomsPage.spec.ts && npm run build`
  - Expected: PASS。

---

### Task 10: 对局中心

**Files:**
- Create: `admin-web/src/modules/matches/MatchesPage.vue`
- Create: `admin-web/src/modules/matches/MatchDetailDrawer.vue`
- Create: `admin-web/src/modules/matches/MatchesPage.spec.ts`
- Modify: `admin-web/src/app/router/index.ts`

**Interfaces:**
- Produces: 对局列表、Event/Snapshot/Replay 详情结构。
- Consumes: `adminApi.matches`、`adminApi.matchDetail`。

- [ ] **Step 1: 写失败测试**
  - 空 game_matches 时显示 EmptyState。
  - RuleVersion 独立显示。
  - started_at/finished_at 计算对局时长。
  - Detail 中 Event/Snapshot 无记录时显示“暂无记录”，不产生假回放数据。

- [ ] **Step 2: 运行失败测试**
  - Run: `npm run test -- --run src/modules/matches/MatchesPage.spec.ts`
  - Expected: FAIL。

- [ ] **Step 3: 实现对局列表**
  - MatchId、ProductId、GameId、RuleSetId、RuleVersion、状态、开始、结束、时长。

- [ ] **Step 4: 实现详情抽屉**
  - Tabs：摘要、玩家、Event、Snapshot、Replay。
  - Replay 第一轮为只读入口；无数据时明确不可用。

- [ ] **Step 5: 测试与构建**
  - Run: `npm run test -- --run src/modules/matches/MatchesPage.spec.ts && npm run build`
  - Expected: PASS。

---

### Task 11: 视觉精修、导航占位与响应式验收

**Files:**
- Modify: `admin-web/src/layouts/Sidebar.vue`
- Modify: `admin-web/src/layouts/HeaderBar.vue`
- Modify: `admin-web/src/styles/global.css`
- Modify: `admin-web/src/styles/element.css`
- Create: `admin-web/src/modules/common/ComingSoonPage.vue`
- Modify: `admin-web/src/app/router/index.ts`
- Test: `admin-web/src/layouts/AdminLayout.spec.ts`

**Interfaces:**
- Produces: 后续商业/AI/活动/客服风控/系统管理统一 ComingSoon 页面。
- Consumes: Tasks 1-10。

- [ ] **Step 1: 写布局测试**
  - 侧栏展开/折叠 Logo 正确。
  - 导航激活态使用品牌橙金。
  - 1366 宽度测试类下 Header/内容不溢出。
  - ComingSoon 页面明确“建设中”，不显示空白卡。

- [ ] **Step 2: 实现视觉精修**
  - Sidebar 220px 展开、64px 折叠。
  - Header 高度约 64px。
  - 内容区 padding 18-20px。
  - 卡片、抽屉、筛选条统一圆角/阴影。
  - 表格维持 11px 正文、12px 表头。

- [ ] **Step 3: 运行全量前端测试**
  - Run: `npm run test -- --run`
  - Expected: PASS。

- [ ] **Step 4: 构建验证**
  - Run: `npm run build`
  - Expected: PASS。

---

### Task 12: Docker、Nginx 路由回退与端到端烟测

**Files:**
- Modify if required: `admin-web/Dockerfile`
- Modify if required: `admin-web/nginx.conf` 或项目实际 Nginx 配置
- Modify: `VALIDATION.md`
- Modify: `README.md`

**Interfaces:**
- Produces: 可通过 Docker Compose 访问的最终运营后台。
- Consumes: 全部前置任务。

- [ ] **Step 1: 验证 Nginx SPA fallback**
  - `/dashboard`、`/users`、`/rooms`、`/matches` 直接访问均返回后台 SPA。

- [ ] **Step 2: 构建后端与后台镜像**
  - Run: `docker compose build server admin-web`
  - Expected: PASS，后端内部 `go test ./...` 通过，前端 `npm run build` 通过。

- [ ] **Step 3: 启动服务**
  - Run: `docker compose up -d`
  - Expected: PostgreSQL/Redis/server/admin-web 均 Running/Healthy。

- [ ] **Step 4: API 烟测**
  - Run:
    - `GET /health`
    - `GET /api/v1/admin/overview`
    - `GET /api/v1/admin/users`
    - `GET /api/v1/admin/rooms`
    - `GET /api/v1/admin/matches`
  - Expected: HTTP 200；空数据返回空集合，不返回伪造数字。

- [ ] **Step 5: 页面烟测**
  - `http://localhost:5173/login`
  - `http://localhost:5173/dashboard`
  - `http://localhost:5173/users`
  - `http://localhost:5173/games/products`
  - `http://localhost:5173/rooms`
  - `http://localhost:5173/matches`
  - Expected: 全部可加载；刷新路径不 404。

- [ ] **Step 6: 更新验证文档**
  - 记录版本、通过命令、真实/待接入数据边界、登录方式、访问地址。
  - 禁止写“已完成”但未实际验证的能力。

---

## Self-Review

### Spec coverage
- 品牌 Logo：Task 3。
- 现代企业视觉：Task 1/3/11。
- 登录页：Task 3。
- Router/Pinia/模块化：Task 2。
- 综合工作台：Task 6。
- 用户中心：Task 7。
- 游戏中心：Task 8。
- 房间中心：Task 9。
- 对局中心：Task 10。
- 后续模块边界：Task 11。
- 管理 API：Task 4/5。
- Docker/路由/响应式/离线降级：Task 2/6/11/12。
- 11px 紧凑表格：Task 1/11。
- 中文注释与真实数据边界：Global Constraints + 各任务。

### Type consistency
- 后端统一使用 `admin.Service`，前端统一从 `services/api/admin.ts` 消费。
- Product/Game/RuleSet/RuleVersion 字段保持现有 snake_case API。
- Room 详情使用现有 `Room` 结构，不在第一轮虚构玩家座位字段。
- Match/Event/Snapshot 直接映射现有数据库表，缺记录即空集合。

### Proportion
计划按 12 个可独立验收任务拆分，每个任务都有测试/构建检查，不包含可由实现者自行推导的大段实现代码。
