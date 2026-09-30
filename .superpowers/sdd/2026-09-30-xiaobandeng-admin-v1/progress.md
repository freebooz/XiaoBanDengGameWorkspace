# SDD ledger — plan: docs/superpowers/plans/2026-09-30-xiaobandeng-admin-v1.md
Ruling: 在当前 main 工作区直接增量执行 — 用户明确要求在当前 HWebCodex 项目修改完成后重新发布，且工作区含前序已确认的未提交游戏端修改；新建独立 worktree 会丢失/分叉这些状态并阻碍原路径部署 — 成本：若当前 main 需后续拆分提交，需要人工按文件范围整理提交。
Pre-flight: Task 1 → Task 2 consumes brand CSS tokens; consistent.
Pre-flight: Task 2 → Task 3 consumes router/auth store/layout; consistent.
Pre-flight: Task 4 → Task 5 consumes Admin HTTP DTOs; consistent.
Pre-flight: Task 5 → Tasks 6-10 consume adminApi/platformApi; consistent.
Pre-flight: Tasks 6-10 → Task 11 consumes shared layout/styles; consistent.
Pre-flight: Tasks 1-11 → Task 12 consumes full frontend/backend build; consistent.
Task 1: Ruling: 后台 Node 构建基线升级为 Node 22 — 新依赖链明确要求 Node >=22，Node 20 安装出现 EBADENGINE — 成本：旧 Node 20 开发机需升级或使用 Docker。
Task 1: complete (tests: design-tokens 2/2 PASS; npm run build PASS).
Task 2: complete (tests: router 3/3 PASS; npm run build PASS).
Task 3: Ruling: 登录测试改用 vi.waitFor 等待 Vue Router 异步导航 — 登录状态已立即变更，失败仅来自测试等待不足 — 成本：无生产行为变化。
Task 3: complete (tests: LoginPage 2/2 PASS; npm run build PASS).
Task 4: complete (tests: go test ./... PASS; Admin service/HTTP/room/match tests PASS).
Task 5: complete (tests: API service 3/3 PASS; npm run build PASS).
Task 6: complete (tests: Dashboard 3/3 PASS; npm run build PASS).
