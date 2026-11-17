# 小板凳麻将乡村界面实施与验收记录

日期：2026-11-15。实现位于正式源码树，通过 `tools/compose-godot.ps1 -Product mahjong` 进入正常产品工程。此记录覆盖本轮已批准参考图及后续共用边框、九宫格、标题位置、屏幕适配、品牌资源修订；不代表全部 39 张界面已完成人工视觉验收。

## 已接入的真实入口

| 界面 | 源码（相对工作区） | 状态与行为 |
| --- | --- | --- |
| 登录、注册 | `client/games/mahjong/guiyang/mahjong_login_view.gd`、`mahjong_app.gd` | 实际账号密码、记住账号、显示密码、游客入口、注册及固定网关；三色按钮和版权版本来自产品信息 |
| 游客身份 | `mahjong_guest_identity_view.gd` | 昵称来自登录身份；继续进入现有大厅；宽屏左右分栏 |
| 大厅、快速匹配 | `mahjong_lobby_view.gd` | 真实余额、服务器玩法目录、匹配和准备事件；快速匹配已移除玩法名称横条 |
| 创建、加入、房间列表 | `mahjong_room_pages.gd` | 服务器玩法目录、四位房号、局数与规则、密码、键盘、过滤及房间订阅；宽屏分栏，窄屏滚动 |
| 设置 | `mahjong_settings_view.gd` | 共用四类导航；实际音频、音色、画质、规则及出牌辅助设置 |
| 本局结算 | `mahjong_settlement_view.gd` | 真实输赢、得分及翻鸡牌；查看规则、可用时再来一局、返回大厅 |
| 对局离开 | `guiyang_3d_screen.gd` | 继续打牌、关闭、离开共用现有导航；对局继续和超时托管文案对应实际流程 |
| 错误、退出确认 | `mahjong_error_view.gd`、`mahjong_app.gd` | 原生遮罩、消息和错误码、重试/取消/关闭、焦点恢复；过期页面重试隔离；退出默认聚焦继续游戏 |

页面初始化读取状态，后续沿用既有生命周期与数据事件。窗口改变通过尺寸通知重新布局，不重建表单或丢弃输入。未把参考图中的示例昵称、得分、房号或准备状态硬编码为正式业务数据。

## 公共资源与组件

| 公共项 | 唯一实现 / 资源 |
| --- | --- |
| Mahjong LOGO、返回按钮、主次按钮、字体、面板入口 | `client/games/mahjong/guiyang/mahjong_rural_modal.gd` |
| 九宫格按钮与边框切片 | `client/foundation/ui/aspect_nine_patch_style.gd`；正常、悬停、按下、选中、禁用继续由原生 Button 状态控制 |
| 新竹边框 + 宣纸 | `client/foundation/ui/nine_patch_panel_style.gd`；`assets/ui/harvest/bamboo_frame_approved.png` 与 `paper.png` |
| 覆盖上边框的标题 | `client/foundation/ui/overlapping_panel_title.gd`；跟随实际竹条位置更新 |
| 安全区与触控尺寸 | `mahjong_rural_theme.gd`；页面锚点、容器、断点、内容区滚动 |
| 对局按钮 | `mahjong_battle_art.gd` 使用同一九宫格机制；图标按比例显示 |
| 游客图、背景、按钮底图、独立图标 | `client/games/mahjong/guiyang/assets/ui/harvest/` |
| 字体 | 当前公共入口 `mahjong_rural_modal.gd::village_font()` 复用 `foundation/ui/fonts/NotoSansCJKsc-Bold.otf`；保留了同工作区并行更新的字体选择 |

最新竹框原稿逐字节复制，透明中心无需抠图；颜色和透明度保持原稿。九宫格切片为左 360、上 260、右 320、下 280，完整保留四角绳结与叶片；中间透明区域另铺宣纸，边缘沿对应轴重复延展。详见 [切片与来源说明](../client/games/mahjong/guiyang/assets/ui/harvest/PANEL_FRAME.md)。所有调用 `village_panel()` 或旧 `paper_frame()` 的页面使用同一新边框。

全屏页面按可用安全区展开，宽屏布局使用分栏；背景等比覆盖，LOGO 与图标保持比例。对话框仍按内容居中，不把弹窗遮罩当作面板拉伸。短屏内容可滚动，主要按钮、返回与关闭入口保持可达。此实现没有将整个页面作为一张背景图加透明点击区。

输入框和数字按钮按用户追加要求调整为原基准高度的 **1.25 倍（增加 25%）**，统一通过 `mahjong_rural_theme.gd::form_control_height()` 计算；重复缩放窗口不会累乘。文字、图标、数据与行为保持各自原有尺寸和语义。

## 品牌和平台图标

- 启动图：`client/foundation/ui/branding/freeboozstudio_splash.png`，配置在 `client/app_shell/project.godot`，使用用户的 Freeboozstudio 原稿。
- 应用图标：`client/games/mahjong/guiyang/assets/ui/series/xbd_mahjong_app_icon*`；产品映射在 `products/mahjong/product.json`，由 `tools/compose-godot.ps1` 写入生成工程与导出配置。
- 可重复导出脚本：`tools/export-mahjong-brand-icons.ps1`。包含 PNG 多尺寸、Windows ICO、Android 自适应前景与背景；圆形及圆角矩形遮罩预览在验收目录 `branding/`。
- 登录显示产品实际版本 `0.1.0`，没有使用效果图示例版本 `1.0.0` 或把规则版本当成应用版本。

## 验证证据与边界

总目录：`artifacts/mahjong-ui-review-20261115/`。

- 正常组合工程的原生资源导入：`validation/final-shared-import.log`。新工程首次读取公共字体主题发生导入次序错误，字体导入完成后复验零错误；初次记录保留在 `validation/cold-font-import.log`。
- 六个主要页面 7 种尺寸、42 组页面布局，另有四类设置的 28 组布局，共 30 张原生截图：`validation/final-harvest-native.log`。尺寸为 941×1672、390×844、1280×720、1600×720、1024×768、1280×800、1440×900。验证实际点击、输入保留、房间命令、错误后重试、系统返回、目录订阅清理及标题与竹框对齐。
- 登录与注册额外覆盖 1920×1080、2560×1080；9 种尺寸与 15 张截图位于 `login/`；加高 25% 后的实际鼠标、键盘、焦点、返回、退出取消/确认见 `validation/input-height-login-native.log` 与 `runtime-review-final.json`。
- 原生九宫格检查：`validation/final-ninepatch-native.log`；五类按钮三种尺寸五种状态及新面板角部比例检查。
- 错误流程：`validation/final-error-flow-native.log`；验证重试一次、保留表单、焦点恢复、拒绝迟到回调和恢复后关闭。
- 离开牌桌：`validation/final-leave-native.log`；4 种横屏比例及继续/关闭/离开，截图为 `leave_*.png`。
- 错误弹窗 7 种尺寸的遮罩、焦点及一次重试：`final-error-modal-native.log`；结算 6 种横屏比例、牌分/鸡蛋变动区分、缺失账本标识及关闭重开/再来一局：`final-settlement-native.log`。
- 最终正常组合的会话、大厅流程、登录适配、向听进张、错误流程与九宫格集成回归：`validation/integrated-*.log`；对应 `-error.log` 为空。
- 隔离 HTTPS/WSS 实际注册、账号登录和大厅连接：`validation/new-login-real-tls-native.log`。该记录不是固定网关验收；本轮检查固定测试域名 HTTPS 时仍有 TLS 连接问题。

本轮专用 TLS 测试服务已停止，容器与数据卷保留。自动审批拒绝了删除测试数据卷的操作，因此没有执行数据销毁；停止记录见 `validation/tls-fixture-stop.log`。

原生截图均来自 Windows Godot 4.7.2 / Vulkan / RTX 4090；手机和平板为桌面比例模拟。调试运行使用 `--disable-vsync --max-fps 0`，运行时不限帧读回见登录报告。没有声称 Android/iPad 真机安装、软键盘、麦克风音质、移动 GPU 性能或云网关验收通过。

微信登录和找回密码的服务接口尚未配置，点击显示真实未配置提示。设置参考图中尚无业务支持的震动、自动准备、自动理牌、二次确认、独立音量、贵阳话、独立阴影/特效/牌面切换没有伪造可用控件；当前使用已有实际设置。启动图已做原稿校验和配置读回，但启动瞬间的原生截图未捕获。视觉相似度仍以本轮原生截图交人工审验，不宣称逐像素完全相同。

本轮保留了同工作区的结算账本并行更新，显示真实鸡蛋变动；没有账本字段时显示「— 鸡蛋」。该信息增加后，1672×941 结算末位玩家的附加牌分行需要局部轻滚，主要操作保持可达。修复了共享面板动态内边距更新引发的同步尺寸递归：重入合并为延迟更新，完整更新四边后再收敛；最终往返尺寸回归未再出现递归错误。
