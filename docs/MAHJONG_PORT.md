# 贵阳麻将移植记录

2026-10-09：对局已按最新黑金翡翠会所参考图重设计，三维黑金牌桌、直立真实手牌、方形头像与切角玩家卡片、中央真实回合倒计时、五色圆按钮和选牌描边均已接入。规则／设置／退出、聊天／表情、实际录音发送与本地席位静音继续可用，操作提交后等待服务器确认。界面与验证记录见 [参考界面说明](MAHJONG_REFERENCE_UI.md)。继续采用 108 张贵阳捉鸡玩法，不吃牌、无字牌，未添加血战或八局赛制。

## 来源与运行方式

- 只读来源：`E:\work\Game\MahjongGame` 的 `GuiyangMahjongCore` 规则模块、`SourceArt/UI` 牌面图片和 `SourceArt/3D/MahjongTableProduction` 桌模型及 PBR 贴图。
- 平台实现：Go 服务端 `server/internal/game/mahjong/guiyang` 和 `server/internal/httpapi/mahjong_realtime.go`；Godot 客户端 `client/games/mahjong/guiyang`。
- 产品标识：`xbd_mahjong` / `mahjong` / `guiyang` / `2.0.0`。
- 本地启动：在仓库根目录执行 `docker compose up -d --build server`，再执行 `powershell -ExecutionPolicy Bypass -File tools/compose-godot.ps1 -Product mahjong`，用 Godot 打开 `client/.generated/mahjong/project.godot`。
- 四个客户端分别游客登录、快速对局、准备；开局后点击桌上的三维手牌，再点击“打出”。可用“碰”“明杠”“暗杠”“补杠”“胡”“过”按钮响应服务端给出的合法操作。

## 三维资源与训练

- `assets/models/mahjong_table.glb` 为源项目桌模型转换，保留了金属桌框、绿色台面、中心控制器和 10 张内嵌 PBR 贴图；导入时去除了原 GLB 中遮挡整桌的多余立方体。
- 2026-10-09：`assets/models/mahjong_tile.glb` 已替换为源项目 `Saved/Diagnostics/Mahjong50/SM_Mahjong50_Characters_1.fbx` 中真实导出的 Mahjong50 网格，尺寸 36 × 50 × 26 毫米、1,332 个三角面。保留圆角、原始双色分层遮罩与法线，正面是原网格的两块三角面，没有叠加界面牌面平面。27 种游戏牌面使用同一张 4K PBR 图集，包含底色、凹刻法线和 ORM；完整图集保留 34 种牌面资源，玩法仍只用万、筒、条。
- 牌模型的规范编辑源为 `SourceAssets/Mahjong/mahjong_tile.blend`，兼容副本保留在 `artifacts/mahjong_models/mahjong_tile.blend`；牌桌编辑源仍在 `artifacts/mahjong_models/mahjong_table.blend`。`tools/import_real_mahjong_tile.py` 只读导入原 FBX 和贴图，`tools/build_mahjong_models.py` 的完整重建也调用同一牌模型管线；`tools/validate_real_mahjong_tile.py` 验证保存模型的尺寸、闭合、UV、共享角点法线、分层颜色通道和贴图色彩空间。
- 对局使用真实三维桌和立体牌显示四方暗牌、手牌、弃牌和副露；客户端仅显示本人明牌。大厅“单人训练”提供独立的三维选牌、打牌、补牌练习，不连接实时房间。对局右上角可选低、中、高画质。

## 已移植的对局规则

2026-10-08 界面改为横屏：深色金边牌桌、四方玩家卡片、右侧选牌与响应操作。自己的手牌放大并向玩家倾斜；牌面单独减弱反光，牌身保留原材料。844×390 手机比例、1024×768 平板和 1440×810 PC Vulkan 截图在 `artifacts/landscape/mahjong_*.png`。十四张牌真实 GUI 触屏/鼠标选择、三档画质拾取、六种响应和结算/训练返回检查通过；Vulkan 像素检查确认万字红色墨迹未被高光洗白。

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
- 本次使用原项目已有的诊断 FBX 和四张 PBR 贴图，已实际替换原简化牌身，不需要重新启动 Unreal 导出 `.uasset`。来源与材质说明见 [真实牌模型](MAHJONG_REAL_TILES.md)。
- 牌局状态目前保存在服务进程内存中。服务重启后的牌局恢复、Android 导出和设备端验收尚未完成。
- 平台一期游客接口和实时连接目前只以 `account_id` 标识玩家，尚无可验证的会话令牌；正式公网部署前需要完成平台统一身份认证。
