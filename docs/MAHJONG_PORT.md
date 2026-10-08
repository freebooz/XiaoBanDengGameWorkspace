# 贵阳麻将移植记录

## 来源与运行方式

- 只读来源：`E:\work\Game\MahjongGame` 的 `GuiyangMahjongCore` 规则模块、`SourceArt/UI` 牌面图片和 `SourceArt/3D/MahjongTableProduction` 桌模型及 PBR 贴图。
- 平台实现：Go 服务端 `server/internal/game/mahjong/guiyang` 和 `server/internal/httpapi/mahjong_realtime.go`；Godot 客户端 `client/games/mahjong/guiyang`。
- 产品标识：`xbd_mahjong` / `mahjong` / `guiyang` / `2.0.0`。
- 本地启动：在仓库根目录执行 `docker compose up -d --build server`，再执行 `powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 -Product mahjong`，用 Godot 打开 `client/.generated/mahjong/project.godot`。
- 四个客户端分别游客登录、快速对局、准备；开局后点击桌上的三维手牌，再点击“打出”。可用“碰”“明杠”“暗杠”“补杠”“胡”“过”按钮响应服务端给出的合法操作。

## 三维资源与训练

- `assets/models/mahjong_table.glb` 为源项目桌模型转换，保留了金属桌框、绿色台面、中心控制器和 10 张内嵌 PBR 贴图；导入时去除了原 GLB 中遮挡整桌的多余立方体。
- `assets/models/mahjong_tile.glb` 为可复用的立体牌身。27 种万、筒、条牌面沿用源项目 `SourceArt/UI/Tiles` 图片，按对局状态贴到模型面网格。牌身原资产仅有 Unreal `.uasset`，当前 Godot 牌身是可编辑的等比例重建模型，并非原 `.uasset` 网格直接导出。
- 编辑源文件在 `artifacts/mahjong_models/*.blend`；`tools/build_mahjong_models.py` 可重建运行资源，`tools/validate_mahjong_models.py` 可独立重开 `.blend` 和 `.glb` 验证网格与贴图。
- 对局使用真实三维桌和立体牌显示四方暗牌、手牌、弃牌和副露；客户端仅显示本人明牌。大厅“单人训练”提供独立的三维选牌、打牌、补牌练习，不连接实时房间。对局右上角可选低、中、高画质。

## 已移植的对局规则

- 四人匹配、座位固定、四人准备后开局；第五人进入另一个房间。房间号仍为平台四位数字。
- 108 张万、筒、条牌；三轮四张、每人一张、庄家补一张；三骰开门后顺时针抓牌；逆时针座次出牌。
- 服务端持有牌墙、暗牌和合法操作。客户端只提交操作意图与实体牌 ID，不接收其他人的暗牌和未摸牌墙。
- 碰、明杠、暗杠、补杠、胡、过；胡优先于杠、碰，支持一炮多响、七对和抢杠胡。普通点炮胡须已有完成的杠。
- 15 秒无操作自动出牌或过；杠分、基础胡分、固定幺鸡、黑八、翻鸡、冲锋鸡、责任鸡与流局结算。
- WebSocket 断线重连恢复同房间原座位、手牌和牌墙位置，前提是服务进程仍在运行。

## 验证与当前边界

- `go test ./...` 通过，覆盖四人匹配、牌型、实体牌校验、响应优先级、牌墙开门、完整超时流局、私有快照和重连。
- Godot 客户端脚本解析与牌桌渲染测试通过；四个实际客户端完成登录、匹配、准备、入座和多轮摸打，收到同一个房间的四个座位。
- Blender 已重新打开两个可编辑模型与 GLB；Godot 已实际渲染桌与手牌，三维手牌点击、打出及训练补牌脚本检查通过。
- 原始麻将牌 `SM_Mahjong50.uasset` 的直接 FBX 导出仍受本机 Unreal 启动时 VisionOS SDK 校验失败阻挡。`tools/export_unreal_mahjong_mesh.py` 保留了只读导出步骤，后续可以把直接导出的原牌网格替换当前重建牌身。
- 牌局状态目前保存在服务进程内存中。服务重启后的牌局恢复、Android 导出和设备端验收尚未完成。
- 平台一期游客接口和实时连接目前只以 `account_id` 标识玩家，尚无可验证的会话令牌；正式公网部署前需要完成平台统一身份认证。
