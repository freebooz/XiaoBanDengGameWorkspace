# 小板凳麻将登录与大厅

启动后显示登录首页并检查所选服务器。游客登录通过真实服务端创建或恢复会话，显示服务端昵称，再由玩家点击「进入游戏大厅」建立大厅连接。账号登录及注册使用同一个账号服务。勾选「记住账号」仅保存用户名，密码不写入本机设置。

## 资源与接入

| 位置 | 用途 |
| --- | --- |
| `client/games/mahjong/guiyang/assets/ui/login_rural/` | 独立乡村背景、品牌、透明按钮底图、图标与游客头像 |
| `client/games/mahjong/guiyang/assets/ui/lobby_rural/` | 大厅入口插画、房间导航、键盘底图和叶饰 |
| `client/games/mahjong/guiyang/mahjong_app.gd` | 登录、游客身份、账号登录注册、会话、大厅进入 |
| `client/games/mahjong/guiyang/mahjong_lobby_view.gd` | 大厅牌桌、诊断状态、规则选择和已有入口 |
| `client/games/mahjong/guiyang/mahjong_room_pages.gd` | 创建、加入、公开房间列表及手机和平板布局 |
| `client/foundation/ui/portrait_flow.gd` | 将现有象棋及纸牌入口居中放入安全区；交给三维游戏后的对局根节点充满窗口 |
| `server/internal/platform/account/` | 四字昵称分配、名称占用、用户名密码注册及会话 |
| `AGENTS.md` | 自动适配手机、平板与 PC 的项目级策略 |

大厅支持快速匹配、创建和加入四人房、公开房间列表、自定义规则、训练场、个人中心和战绩。房主可选择 8、16 或 24 局，生成四位房号并设置四位数字密码。密码房通过房号和密码加入。服务端确认房号是否可用，并在最后一局结算后释放房间。旧房间的局数沿用原设置。

公开列表在打开时订阅有权限的大厅连接，随房间变化更新，可手动刷新并按玩法、人数和局数筛选。进房及对局数据以服务端为准。当前玩法为贵阳捉鸡和基础 108。微信、手机号和密码找回需要身份服务接入。

隔离本地服务的玩家与管理端地址由 `tools/test-mahjong-linux-tls.ps1` 输出。客户端需信任本次 CA，管理端需具备 `platform:read` 权限。真实 Android 设备、系统安全区和触摸性能需在实体设备验收。
