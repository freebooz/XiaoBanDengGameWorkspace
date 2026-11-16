# 斗地主参考登录页

更新日期：2026-10-09。

## 设计与实现

采用用户提供的乡村夜景竖版登录设计，保留大树、木质“小板凳斗地主”招牌、灯笼、山村和下方打牌人物。中央手机号、密码、登录、微信和游客入口由原生可操作控件实现，文字与输入不烘焙到图片中。

- `client/games/landlord/landlord_login_screen.gd`：背景、奶油色输入框、木质按钮、密码显示切换、能力说明和连接设置。
- `client/games/landlord/login_icon.gd`：可缩放的手机号、密码、眼睛、微信和游客图标。
- `client/games/landlord/landlord_app.gd`：产品登录请求、连接状态和现有大厅衔接。
- `client/games/landlord/assets/ui/login/`：原始参考、清理表单后的背景、透明控件图集和区域数据。来源、生成提示、哈希及图集边缘的细小彩色残留见 [ASSETS.md](../client/games/landlord/assets/ui/login/ASSETS.md)。

登录沿用产品的 720×1280 竖版画布，等比显示；对局的横屏模式保持现有流程。密码默认隐藏，切换显示状态保留输入。手机输入框指定电话号码和密码键盘类型。

## 当前入口能力

| 入口 | 当前行为 |
| --- | --- |
| 手机号、密码输入 | 真实编辑控件；密码可显示或隐藏 |
| 登录、微信登录、注册、忘记密码 | 明确提示暂未开放，保留在登录页；不发送输入的手机号或密码 |
| 游客登录 | 向已确认且连接检查通过的服务器发送空对象游客认证请求，成功进入现有大厅 |
| 连接设置 | 编辑服务器地址，确认后检查新地址；取消或重新打开时丢弃未确认草稿 |

当前服务只提供游客认证，没有手机号、微信、注册或密码恢复接口。对应入口的说明不代替实际账号认证。

## 状态处理

启动连接检查与登录使用同一界面。检查当前服务器成功前禁用游客按钮，连接设置仍可使用。切换服务器会替换原连接检查；旧地址的迟到结果不能开放新地址的登录。连接及重新连接保留已输入内容。

登录提交期间禁用游客按钮和连接设置，避免重复请求。登录失败后恢复重试入口并显示实际错误；无效登录响应留在登录页。服务器地址只在确认设置时应用，不读取取消的草稿。

## 验证与范围

生成工程：`tools/compose-godot.ps1 landlord`。

`landlord_login_smoke.gd` 使用真实界面和产品状态代码，只替换 HTTP 传输边界；覆盖启动、更换服务器、迟到响应、取消设置、密码切换、账号能力说明、游客防重复、失败重试、输入保留及登录响应进入大厅。原生运行注入鼠标点击和触摸事件。弹窗边界按嵌入窗口的逻辑坐标核对，避免将 720×1280 画布尺寸与操作系统像素混用。

Windows Godot 4.7.2 Vulkan 窗口验证：

| 运行窗口 | 验证内容 | 登录视口截图 |
| --- | --- | --- |
| 320×568 | 小屏控件与弹窗边界、完整交互流程 | 无单独截图 |
| 480×854 | 手机比例、完整交互流程 | `artifacts/landscape/landlord_login_phone.png`，480×853 |
| 1024×768 | 平板比例、完整交互流程 | `artifacts/landscape/landlord_login_tablet.png`，432×768 |
| 1440×900 | PC 比例、完整交互流程 | `artifacts/landscape/landlord_login_pc.png`，506×900 |

截图是等比竖版登录视口，不包含 PC 或平板窗口两侧的留白。原生视口的像素取整可能使高度少一个像素。

本轮日志：`.tmp/landlord_login_import_final.log`、`.tmp/landlord_login_small_phone_final.log`、`.tmp/landlord_login_phone_final.log`、`.tmp/landlord_login_tablet_final.log`、`.tmp/landlord_login_pc_final.log`、`.tmp/landlord_login_readiness_green.log`。另运行已有 `client/tests/login_layout_smoke.gd`，日志 `.tmp/landlord_login_layout_final.log`。

这些检查验证界面和产品回调，未作为当前真实服务器认证、Android 安装、实体手机键盘或微信授权的验收证据。
