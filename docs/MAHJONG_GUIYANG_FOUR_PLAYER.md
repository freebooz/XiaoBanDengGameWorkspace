# 小板凳贵阳麻将乡村界面

登录用灯笼晚景和邻里牌桌，大厅用暖光院落横幅，好友房突出木质房号牌和四个座位，训练场展示独立教学场景。木纹主按钮、米白次按钮和柔和阴影贯穿各页。登录、大厅、好友房、训练、牌桌与结算共用用户指定的透明木牌 Logo，完整等比显示。

新版[四页效果图](../artifacts/mahjong_guiyang_series/redesign/concepts/flow.png)与[横屏牌桌效果图](../artifacts/mahjong_guiyang_series/redesign/concepts/table.png)用于确定布局、色彩和材质。原生牌桌采用深木色座位卡、墨绿桌布、圆形倒计时和按操作分色的按钮。示意牌面与示例数据均由客户端实际规则和状态取代。

## 页面与流程

| 页面 | 操作 | 客户端截图 |
| --- | --- | --- |
| 登录 | 首次游客登录，后续点继续游戏恢复账号。连接设置可展开修改服务地址，声音按钮控制音乐和音效 | [登录](../artifacts/mahjong_guiyang_series/redesign/native/login.png) · [横屏平板](../artifacts/mahjong_guiyang_series/redesign/login_native/tablet_wide_login.png) |
| 大厅 | 选玩法、快速开局、创建好友房、展开四位房号表单或进入训练场 | [大厅](../artifacts/mahjong_guiyang_series/redesign/native/lobby.png) · [加入房间](../artifacts/mahjong_guiyang_series/redesign/native/join_room.png) |
| 好友房 | 复制房号、查看座位和准备进度、准备、取消准备、离房 | [好友房](../artifacts/mahjong_guiyang_series/redesign/native/friend_room.png) · [自定义](../artifacts/mahjong_guiyang_series/redesign/native/custom_rules.png) |
| 对局 | 横屏点选三维手牌。动作区随服务端通知显示本回合可用的打出、碰、杠、胡或过。设置含低、中、高画质 | [对局](../artifacts/mahjong_guiyang_series/redesign/native/friend_table.png) · [重连](../artifacts/mahjong_guiyang_series/redesign/native/friend_table_reconnected.png) |
| 训练场 | 与三位电脑牌友完成一局，或进入本地摸打练习 | [训练场](../artifacts/mahjong_guiyang_series/redesign/native/training_hall.png) |
| 结算 | 查看四席分差、规则及实际翻鸡指示牌，返回大厅或同房再来 | [结算](../artifacts/mahjong_guiyang_series/redesign/native/settlement_next_round.png) |

## 好友房使用方式

四台设备在登录页连接同一个已运行的小板凳服务。房主在大厅选择贵阳捉鸡并创建好友房，其余三人点「加入房间」输入四位房号。提交期间锁定输入，失败时保留房号并显示反馈。四人准备前可取消自己的准备。全员准备后有 30 秒入桌，四席连接齐全时发牌。入桌超时，好友房保留席位并重新准备，快配释放座位。结算点「同房再来」保留房号及座位，四人重新准备后开启新局。点「返回大厅」离开好友房。短暂掉线可恢复原对局。若错过结算，仍在原好友房的客户端凭原对局 ID 重连后可查看自己的结算。

现有贵阳捉鸡 `guiyang@2.0.0` 使用万、筒、条共 108 张，规则和计分由 Go 服务裁决。客户端通过快照和通知更新大厅、对局及结算。

## 素材

`client/games/mahjong/guiyang/assets/ui/series/xbd_mahjong_brand.png` 为用户指定的 1774 × 887 RGBA 原图，SHA-256 为 `9E5DA1FEDC997BA58D083E809B941C069B1DC1C59CC7C67D7F32D2542D7577DD`。客户端用透明纹理、原色和等比布局显示。`xbd_mahjong_welcome.png` 是登录晚景。Godot 绘制按钮文字、玩家信息和状态。历史方案保存在 `artifacts/mahjong_guiyang_series/concepts`。

## 本地复验

从仓库根目录执行 `tools/compose-godot.ps1 mahjong`，用 Godot 4.7.2 导入 `client/.generated/mahjong`。四进程测试设置 `XBD_MAHJONG_SMOKE_GODOT` 为 Godot 可执行文件，设置 `XBD_MAHJONG_SMOKE_REMATCH=1`，从 `server` 执行 `go test ./internal/httpapi -run '^TestMahjongGuiyangFourPeers$' -count=1 -v`。可用 `XBD_MAHJONG_SMOKE_PREVIEW` 指定截图目录。

夹具回归使用四个独立 Godot 进程。真实服务回归设置 `XBD_MAHJONG_RELEASE_URL` 为本机隔离 API 地址，运行 `TestMahjongReleaseFourPeers`。窗口客户端使用 Vulkan，验证 `max_fps=0` 和 `vsync=0`。2026-11-13 四个真实游客账号经 PostgreSQL 登录、在同一房间完成两局 `guiyang@2.0.0`、暂离回座和续局，客户端重启后恢复原身份。公网、多设备实机和正式账号服务仍待对应环境验收。

新版将 `XBD_MAHJONG_RELEASE_CUSTOM_RULES=1`、`XBD_MAHJONG_RELEASE_RECONNECT=blackhole`、`XBD_MAHJONG_RELEASE_HISTORY=1` 用于真服务回归。分别核对四端锁定房规、断线期间禁用出牌、原座原手牌和重启后恢复两局本人战绩。设置 `XBD_MAHJONG_RELEASE_TABLET=1` 时，带界面的客户端以 1024 × 768 验证。截图见[平板大厅](../artifacts/mahjong_guiyang_series/redesign/tablet_native/lobby.png)与[平板牌桌](../artifacts/mahjong_guiyang_series/redesign/tablet_native/friend_table.png)。

2026-11-14，进行中的好友房和快速匹配会先把首发、合法动作和超时动作提交到 PostgreSQL，再确认或广播。API 启动时恢复原房号、座位、房规、牌墙、暗牌和回合，已确认命令按席位去重。`TestMahjongReleaseServiceRestart` 使用隔离 PostgreSQL 和 Redis，验证四个账号原座回桌和继续出牌。

好友房保存候场席位、准备状态、入桌截止时间和局次。公开战绩、结束活跃牌局及好友房结算快照同一事务提交。`TestMahjongFriendRoomAcrossAPIReboots` 使用五个先后运行的 API 进程，验证部分准备、离房、首发前对局 ID、四席结算和原房续局。两项重启测试需指定 `XBD_MAHJONG_RESTART_API`、`XBD_MAHJONG_TEST_POSTGRES_URL`、`XBD_MAHJONG_TEST_REDIS_ADDR`。数据库长时故障验证列在发布计划。

个人战绩支持分页及按局查看胡、杠、鸡分项。复盘可按步查看四席公开弃牌和副露，暗杠仅显示牌背。战绩和复盘仅供本局参赛账号查询。旧记录保留总分，缺失的分项或复盘由界面提示。设置 `XBD_MAHJONG_TEST_DB_OUTAGE=1` 后可运行 `TestMahjongReleasePreservesDecisionTimeAfterPostgresOutage`，验证数据库连接中断超过 15 秒后，原操作仅提交一次，下一次决策以 PostgreSQL 恢复写入时间为起点。
