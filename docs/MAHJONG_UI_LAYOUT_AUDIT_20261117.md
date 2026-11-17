# 小板凳麻将界面与三维牌桌复验

## 界面修正

| 范围 | 修正与验证 |
| --- | --- |
| 登录、游客、注册 | 登录组合与表单按安全区居中。紧凑横屏将资料和操作分栏。注册与游客使用左上品牌图。登录和注册冒烟覆盖 12 种窗口尺寸。 |
| 大厅、房间、账号、战绩、教学 | 短横屏首屏保留四项大厅主操作。公共 LOGO 固定在页头左上安全区，内容面板保持居中。11 个页面在 4 种窗口中通过 44 项品牌位置检查。 |
| 创建、加入、房间列表 | 创建房间的观战开关有可见标签。随机房号按钮固定为 104×52。房间列表按规则和版本筛选，320 px 和 390 px 窄屏的目录居中，房间数值更新后恢复可用按钮的键盘焦点。 |
| 弹窗 | 错误正文在短窗可读。规则、聊天、表情、选杠和牌友管理使用公共九宫格，正文可滚动，关闭区保持可达。退出、设置和结算按实际安全区定位。遮罩打开时，键盘焦点留在当前弹窗。 |
| 按钮与输入 | 共享文字测量会扣除各状态内边距、图标、箭头与描边，再决定字号。紧凑登录输入框至少 84×44。空间不足时内容换列或滚动。 |
| 牌桌 HUD | 规则、设置、返回、快捷聊天、表情和发语音使用相同圆形样式。1440×810 时实测 56×56。四席头像栏同为 178×76，左下栏与左家栏左对齐。昵称、房间号和回合提示字号减小。房间信息保留居中文字，底纹已移除。 |

## 牌桌渲染

相机依据顶部 HUD、底部互动区、内沿宽度和当前窗口选取最大可用视角。近处内沿与对家手牌上缘的投影中心对齐可用区域。渲染缓冲随实际物理像素重建，牌面光栅比例和最终合成比例均为 1.0。选牌与界面命中使用同一台相机的投影。

| Windows 原生窗口 | 牌桌渲染缓冲 | 手中首张牌的牌面 |
| --- | ---: | ---: |
| 640×360 | 640×334 | 29.0×34.1 px |
| 800×360 | 800×334 | 32.6×38.0 px |
| 1024×768 | 1024×726 | 54.8×58.4 px |
| 1280×800 | 1280×747 | 66.9×77.1 px |
| 1440×810 | 1440×750 | 74.9×87.7 px |
| 1600×720 | 1600×667 | 69.5×81.4 px |

1600×720 同口径基线为 65.1×75.9 px。640×360 为放大后的底部圆形按钮预留了空间，牌面尺寸受这段空间约束。桌面可调整窗口内的游戏维持横向牌桌构图。

## 灯光

| 灯光 | 位置与颜色 | 强度与阴影 |
| --- | --- | --- |
| 主光 | 单个聚光灯从左前上方照向桌心，离垂直约 31°，半锥角 55°，暖白约 4800 K | 1.18，使用唯一实时阴影 |
| 手牌补光 | 靠近玩家一侧的柔和点光，约 6000 K | 0.27，无投影 |
| 对角轮廓光 | 对角上方点光，约 7800 K | 均衡和高清为 0.15，省电档关闭，无投影 |
| 环境与高光 | 冷色低强度环境填光、静态 HDR 反射 | 均衡和高清应用 Filmic 色调映射，省电档保留线性 |

色温通过 sRGB 灯色近似，用项目的非物理能量倍率。麻将牌由实体牌身投影。牌面薄层保留可见渲染，取消重复的阴影通道。[Godot 灯光单位](https://docs.godotengine.org/en/latest/tutorials/3d/physical_light_and_camera_units.html) · [Godot 色调映射](https://docs.godotengine.org/en/latest/tutorials/3d/environment_and_post_processing.html)

Windows RTX 4090 的 1440×810 密集牌局中，阴影绘制调用从 225 降至 120。均衡档牌桌 GPU 耗时 P95 为 0.163 ms，旧基线为 0.152 ms。这项数据只描述该桌面 GPU 的牌桌渲染耗时。

## 主要源码与证据

- 牌桌、头像、按钮布局和输入投影见 [guiyang_3d_screen.gd](../client/games/mahjong/guiyang/guiyang_3d_screen.gd)。灯光见 [mahjong_table_theme.gd](../client/games/mahjong/guiyang/mahjong_table_theme.gd)，牌身投影见 [real_tile_model.gd](../client/games/mahjong/guiyang/real_tile_model.gd)。
- 公共九宫格、圆形按钮和字体内衬见 [mahjong_rural_modal.gd](../client/games/mahjong/guiyang/mahjong_rural_modal.gd)、[mahjong_button_caption.gd](../client/games/mahjong/guiyang/mahjong_button_caption.gd) 和 [overlapping_panel_title.gd](../client/foundation/ui/overlapping_panel_title.gd)。
- 入口与房间布局见 [mahjong_login_view.gd](../client/games/mahjong/guiyang/mahjong_login_view.gd)、[mahjong_app.gd](../client/games/mahjong/guiyang/mahjong_app.gd)、[mahjong_lobby_view.gd](../client/games/mahjong/guiyang/mahjong_lobby_view.gd) 和 [mahjong_room_pages.gd](../client/games/mahjong/guiyang/mahjong_room_pages.gd)。
- [1440×810 牌桌原生截图](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/transparent-room-header/1440x810-board.png) · [640×360 牌桌截图](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/transparent-room-header/640x360-board.png) · [桌面渲染记录](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/native-board/lighting.log)

桌面截图使用 Windows Godot Vulkan 原生渲染，用窗口尺寸模拟手机和平板。其中的牌局状态由测试夹具提供。

## 回归与真机

独立窗口验证通过六种尺寸的 56 px 圆形 HUD、四席同宽同高、左下头像位置及透明房间标题。固定测试窗口的密集牌面回归在 640×360、1024×768、1280×800、1440×810、1600×720 通过。大厅全流程的 70 项页面布局和 40 项设置布局也通过。动作合法性无窗口回归通过 52 项。动态测试窗口被系统改变尺寸时，原生脚本出现触控采样失败，随后按固定分辨率复验密集牌面。

Android 0.4.18 / 58 使用独立包名，安装到 MAA-AN10 后回读版本和 APK 哈希一致。手机登录页已渲染，两次启动均在游客操作前回到系统桌面。局内联网、帧时间和持续温升仍待真机验收。[安装记录](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/phone-perfnov17-0.4.18/device-install.json) · [真机启动记录](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/phone-perfnov17-0.4.18/device-run.json)

[电影布光技术参数与同机位对照](MAHJONG_CINEMATIC_LIGHTING_20261117.md)

## 头像在线状态与鸡蛋图标（本轮最终要求）

四席不再创建绿色圆点，头像使用原图及独立轻量材质：公开 `connected_seats` 为在线时保持原色，离线时去饱和显示灰色。首次快照、在线状态通知、断线、重新入座和观战快照触发更新；客户端失联或正在等待新快照时不沿用过期在线显示。状态不依赖谁正在出牌，未占座不会显示为在线。

余额右侧增加 [可编辑鸡蛋 SVG](../client/games/mahjong/guiyang/assets/ui/rice_field_hud/egg.svg)，采用柔和蛋壳渐变、细暖色边缘及透明背景。先为图标和间距预留宽度，再拟合数字字号，最后将数字与图标整组居中。图标等比缩放、输入穿透，保留真实余额、零值和完整余额提示。

验证使用 Windows Godot 4.7.2、RTX 4090、Vulkan Mobile，关闭 VSync 且 `max_fps=0`，均为桌面模拟尺寸与测试牌局：

- `mahjong_avatar_presence_smoke.gd`：16 组观察座位/当前回合组合、响应/定缺/结算、断线后布局、重新入座、新快照、旧 epoch 和观战均通过；每种状态检查真实头像材质而非仅检查文字。
- 四比例 1280×720、1600×720、1280×800、1200×900 检查头像颜色、绿点节点不存在、数值之后的鸡蛋图标及卡片内边界。
- `mahjong_seat_balance_smoke.gd`：0、100、9999、12345678 均完整显示；通过字号度量和原生红色数字像素统计验证，图标未压住数字或超出卡片。
- [16:9 最终截图](../.tmp/coach-context-godot-green/avatar-presence/presence_1280x720.png)、[20:9](../.tmp/coach-context-godot-green/avatar-presence/presence_1600x720.png)、[16:10](../.tmp/coach-context-godot-green/avatar-presence/presence_1280x800.png)、[4:3](../.tmp/coach-context-godot-green/avatar-presence/presence_1200x900.png)；[头像与四比例日志](../.tmp/coach-context-godot-green/egg-presence-native.log)、[余额可见性日志](../.tmp/coach-context-godot-green/egg-balance-native.log)。

本小节为最新要求：删除状态圆点，以头像灰度表示离线，数值后显示鸡蛋图标。本轮未重新构建或安装 Android APK，也未将桌面模拟称为手机/平板实机验收。

## 2026-11-17 追加：圆形风盘、金色房间信息与屏幕边距

本节更新上文房间信息字号及 HUD 边距的描述。房间号、局数、余牌仍使用真实快照组成的同一个标签，保留无底纹设置；最终字号在同一窗口、同一文案的旧自适应拟合结果上增加 3，字体改为金色 `#ffd36a`。增加发生在拟合之后，避免新字号再次被原高度约束缩回去。无框标签不再保留木纹端帽所需的内边距，长文案可使用两侧工具区之间的安全宽度；原九宫格素材及其已有调用保持有效。

| Windows 原生窗口 | 普通房号原字号 → 新字号 | 16 位房号原字号 → 新字号 | 标题与边距证据 |
| --- | ---: | ---: | --- |
| 1280×720（16:9） | 17 → 20 | 17 → 20 | [普通房号](../.tmp/room-heading-gold-20261117/header_1280x720.png) |
| 1600×720（20:9） | 17 → 20 | 17 → 20 | [长房号](../.tmp/room-heading-gold-20261117/header_1600x720_long.png) |
| 1280×800（16:10） | 17 → 20 | 17 → 20 | [普通房号](../.tmp/room-heading-gold-20261117/header_1280x800.png) |
| 1200×900（4:3） | 18 → 21 | 17 → 20 | [长房号](../.tmp/room-heading-gold-20261117/header_1200x900_long.png) |

上表为 Godot 字号回读；窗口缩放后的物理字高由现有画布比例决定。另验证了 720×1280、720×405、1440×810，共 7 种窗口、14 组文案；16 位房号、24/24 局和余牌 108 均未裁切。字号对照直接调用改动前备份的拟合函数，而非用修改后的同一函数充当基线。[原生验证脚本](../.tmp/room-heading-gold-20261117/verify_room_heading.gd) · [原生日志：0 失败](../.tmp/room-heading-gold-20261117/native.log) · [原九宫格回归：4 比例、3 文案通过](../.tmp/room-heading-gold-20261117/nine_patch_regression.log)

Logo、左下聊天/表情/语音组、左家和自身玩家卡以左安全边为基准；右家卡以右安全边为基准，间距均为 10 个实际屏幕像素。换算使用完整画布与控件变换的水平比例，不以设计坐标或 `factor` 代替物理像素。七种窗口的控件边距回读均为 `10.00 px`，上方对家保持居中。按钮保留 56 px 触控区域，聊天与表情入口通过 Godot 输入事件真实点击打开，玩家卡没有覆盖可操作牌面。

后续补正了 Logo 的可见边缘：原 `sign.png` 为 1819×865，透明外边距及居中等比留白会使可见图案比控件边缘更靠内。现在通过 `AtlasTexture` 引用原图，并用 `get_used_rect()` 仅裁去完全透明的外围区域，等比从控件左边缘绘制；不修改原 PNG、RGB 或纵横比。最终可见图案靠近安全边内 10 px。按钮和玩家卡原图内部少量透明像素保持原样，其 10 px 指控件外边界。最终 Logo 外观见下一节的 `actions_*` 截图；本节较早的 `header_*` 截图只用于字号和布局对照，不代表后续在线状态外观。

风盘在 [mahjong_wind_dial.gd](../client/games/mahjong/guiyang/mahjong_wind_dial.gd) 内改为 96 段圆形旋转剖面：木盘、两道铜边及计时槽同步圆化，圆周及倒角使用连续法线，删除叶片网格和叶片构造函数。原直径 `0.294`、木盘标高 `0.001–0.026`、计时锚点 `y=0.031`、位置与四风牌保持不变。验证覆盖 16 组查看座位/庄家组合，只有庄家牌呈金色，与当前回合无关；六种窗口下倒计时投影仍对准中心。

圆盘 headless 与 Windows RTX 4090/Vulkan 原生验证均退出 0。生产文件与验证镜像 SHA-256 一致：`A25740D1FB84F664B973421B0DA4F01A99AD8ECB0820D0BB2D6727171881F994`。[圆盘原生日志](../.tmp/dealer-dial-circle-20261117/native.log) · [模型近景](../.tmp/dealer-dial-circle-20261117/dial_closeup.png)（仅用于检查模型，近景使用临时放大相机，不代表最终 HUD）

## 2026-11-17 追加：操作按钮固定在手牌上方中央

`_layout_response_actions()` 的水平锚点固定为三维牌桌可用区域的中心。它不随独立摸牌或选牌导致的手牌包围盒变化移动，也不改动手牌、相机或玩家卡的位置。取消把动作拆散到左右空隙的 `_place_separate_actions()`；空间不足时依次减少列数、紧凑排列或居中分行，每一行独立对齐同一中心线。避让只在中心线上调整高度和对称宽度。多行兜底按完整行数计算高度，并保留按钮真实最小宽度，避免 Godot 最小尺寸把实际按钮撑向一侧。

合法性、动作种类、选中牌 ID、等待服务器确认及失败重试链路未作修改。真实快照没有可执行动作时操作组隐藏。单个打出与多个响应按钮使用稳定的共同底边，留在抬起手牌的投影上方；极短的 640×360 窗口因触控尺寸和中心计时区域约束向上排列，仍不移到左右两侧。

原生专项验证覆盖 640×360、1280×720、1600×720、1280×800、1200×900，每种尺寸分别验证 0、1、3 个合法按钮，共 15 组。逐按钮检查屏幕可达、至少 48 px 触控尺寸、每行精确居中、互不覆盖、不覆盖真实牌面/向听标签/玩家卡。Godot 真实触控分别提交选中的实体牌 ID 和合法 `pass`，只提交一次；快照切换不移动玩家卡。最终结果为 `CENTERED_ACTIONS_RESULT=true`，进程退出 0。[专项脚本](../.tmp/centered-actions-20261117/verify_centered_actions.gd) · [最终原生日志](../.tmp/centered-actions-20261117/native.log)

| 比例 | 最终原生截图 |
| --- | --- |
| 16:9 | [1280×720 单个打出](../.tmp/centered-actions-20261117/actions_1280x720_1.png) |
| 20:9 | [1600×720 多个响应](../.tmp/centered-actions-20261117/actions_1600x720_3.png) |
| 16:10 | [1280×800 多个响应](../.tmp/centered-actions-20261117/actions_1280x800_3.png) |
| 4:3 | [1200×900 多个响应](../.tmp/centered-actions-20261117/actions_1200x900_3.png) |
| 极短窗口 | [640×360 多个响应](../.tmp/centered-actions-20261117/actions_640x360_3.png) |

另通过现有动作合法性 52 项 headless 回归，以及密集牌局 10 个场景×4 个查看座位的 40 组 headless 回归，覆盖四家碰杠、四杠与溢出弃牌、真实牌面遮挡及各响应按钮触控。测试中的密集四按钮是专门的展示压力夹具，不表示真实牌局可以在四杠后继续开杠。[动作合法性日志](../.tmp/room-heading-gold-20261117/action_legality_headless.log) · [密集牌局日志](../.tmp/centered-actions-20261117/dense_headless.log)

最终操作区截图对应 `guiyang_3d_screen.gd` SHA-256：`7353D2461462494BD4A97D86B0DF9A95CF5F803D1D0F8D9A8263C5FB1ACFDB10`，与运行镜像一致。此版本已按最新要求删除绿点，由头像颜色表达在线状态；该状态链的专项验收另行记录。前置备份与只读差异复核同时发现并保留了独立 Android 视口日志改动，没有回退并行工作。

以上原生验证均为 Windows Godot 4.7.2、RTX 4090、Vulkan Forward Mobile，回读 `Engine.max_fps=0`、`VSync=0`。Godot 缓存经本次进程的 `APPDATA` 指向工程 `.tmp`，未修改全局环境。窗口尺寸用于桌面模拟手机和平板，牌局由夹具提供；本节不构成真机安全区、真实联网或玩家人工验收。
