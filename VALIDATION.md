# 第一期工程验证记录

验证日期：2026-09-30

## 已通过

1. Godot 产品组合脚本成功生成两个独立工程：
   - client/.generated/chinese_chess
   - client/.generated/mahjong
2. Go 后端在 golang:1.23-alpine 容器中执行 go test ./... 成功。
3. Go 后端 Linux 可执行文件构建成功。
4. Vue 3 + TypeScript 管理后台执行 vue-tsc --noEmit 和 vite build 成功。
5. Docker Compose 已实际启动 PostgreSQL、Redis、server、admin-web。
6. /health 返回 service/postgres/redis 全部 ok。
7. /api/v1/catalog 返回小板凳象棋和小板凳麻将·贵阳麻将两项。
8. POST /api/v1/auth/guest 可真实写入 PostgreSQL 并返回 AccountId。
9. POST /api/v1/rooms 可创建带 ProductId/GameId/RuleSetId/RuleVersion 的房间。
10. /api/v1/wallet 可查询家族级 xbd_point 资产，空账户按0返回。
11. /api/v1/ai/capabilities 返回6项AI预留能力。
12. 管理后台 http://localhost:5173 返回 HTTP 200。
13. 已安装并使用 Godot 4.7.2 对小板凳象棋、小板凳麻将两个生成工程执行 Headless 编辑器解析与主场景运行验证，均无脚本错误。
14. 客户端视觉基线已升级为 3D Tabletop：象棋棋盘/棋子、贵阳麻将牌/牌桌均使用三维模型，采用 StandardMaterial3D/PBR 材质与俯视/轻斜俯视摄像机。
15. 小板凳象棋双 WebSocket 客户端集成测试通过：红黑双方加入同一房间、权威走子、广播同步、回合切换及抢回合拒绝均通过。
16. 象棋服务端权威计时测试通过：双方就绪后下发对局/回合开始时间，合法走子后刷新下一回合开始时间，并下发60秒预警阈值与30秒倒计时配置。
17. Godot 计时界面运行验证通过：对局总时长、单步计时、圆形倒计时组件与程序化提醒音均可加载运行，未出现运行时异常。
18. 象棋客户端默认设计基线已切换为移动端 720×1280（9:16）竖屏，Boot/Login/Lobby/Matchmaking/Room/Game 全流程共用响应式移动端布局。
19. 登录、大厅、房间视觉已由临时白卡升级为分层真实界面：山水木屋 PNG 背景 + 可编辑 SVG 透明前景源 + 透明 PNG 运行资产 + Godot 实时文字/按钮控件，避免把账号、房间号和业务状态烘焙进图片。
20. 新增真实 Room（房间）阶段：快速匹配成功后双方进入同一 RoomId，服务端固定分配 red/black（红/黑）座位；两端分别 Ready（准备）后才将房间状态切换为 playing（对局中）。
21. 房间按钮已接真实交互：退出房间调用 /api/v1/matchmaking/cancel；准备调用 /api/v1/matchmaking/ready；邀请好友复制 RoomId；快速对局调用 /api/v1/matchmaking/quick。
22. 自动双客户端完整流程通过：BOOT→LOGIN→LOBBY→MATCHING→ROOM→GAME，两端 RoomId 完全一致。
23. 红黑座位一致性通过：房间页 ROOM_SEAT=red 的客户端进入 WebSocket 后 CHESS_JOINED color=red；ROOM_SEAT=black 的客户端进入后 CHESS_JOINED color=black。
24. Go 服务端重新构建时执行 go test ./... 全部通过；PostgreSQL、Redis、业务服务健康检查均为 ok。
25. 两个正常 Godot GUI 移动端调试窗口（450×800）已启动并停在新版登录页，进程正常响应，供人工执行完整 UI 交互验收。
26. `tools/render-chess-ui-assets.ps1` 已实际验证可重复将 12 个可编辑 SVG 透明前景源渲染为透明 PNG 运行资产；Godot 运行界面只加载 PNG，规避不同平台 SVG 导入器差异。
27. 象棋棋盘视觉已恢复为红檀木厚底座/边框 + 雕刻盘面，取消竹木棋盘 GLB 对檀木棋盘的覆盖；棋子继续复用金丝楠木三维模型，程序化降级棋子也使用金丝楠木纹理。
28. 单步超时改为服务端权威结束：60 秒正常思考 + 30 秒警示倒计时，总计 90 秒未落子即生成 finished 最终快照，end_reason=timeout、loser=当前执棋方、dissolved=true，并从活动房间目录释放该 RoomId。
29. 超时自动解散测试通过：TestChessTurnTimeoutDissolvesRoom 与 TestFinishRoomReleasesPlayersAndClosesRoom 均通过；超时后 /api/v1/admin/rooms 返回 total=0，原玩家可重新匹配新房间。
30. 正常吃将也统一进入服务端结算生命周期：保留 winner，end_reason=general_captured，并释放活动房间与双方匹配关系。
31. Godot 对局层新增结算弹窗：超时显示“对局已解散”，正常完成按本方阵营显示“本局胜利/本局失利”；展示对局时长、结束原因和 RoomId，并提供“查看棋局/返回大厅”。
32. 新增原创 move_wood.wav（木质落子声）与 bgm_guofeng.wav（国风背景音乐）；BGM 使用原创五声音阶程序合成的古筝拨弦、竹笛气息与古琴低音层，不使用第三方采样或受版权保护旋律。
33. 对局菜单新增“背景音乐：开/关”和“走棋音效：开/关”，背景音乐默认开启；计时警示音与走棋音效共用 SFX 开关。
34. 自动双客户端音频验证通过：两端均记录 CHESS_BGM playing=true；红方首步经服务端确认后，两端均记录 CHESS_MOVE_SOUND played。
35. 自动双客户端 90 秒超时集成验证通过：红方首步后黑方不走，两端均记录 CHESS_SETTLEMENT reason=timeout loser=black winner= dissolved=true，确认服务端解散结果已实际驱动客户端结算弹窗。
36. 本轮 Go 全量 go test ./... 再次通过；Godot 4.7.2 重新组合、资源导入与动态进入象棋对局均通过。
37. BGM 开关问题已复现并修复：原逻辑只 stop/play 单实例，在双客户端同机验收时另一个进程仍继续播放，听感上会误判为“开关无效”；现改为 AudioStreamPlayer.stream_paused（流暂停/恢复）+ 前台焦点控制，后台窗口自动暂停音乐。
38. BGM 自动切换验证通过：CHESS_BGM_VALIDATE_OFF 显示 enabled=false / paused=true；随后 CHESS_BGM_VALIDATE_ON 显示 enabled=true / paused=false，证明按钮状态已真实作用于播放器。
39. 棋子木纹问题确认包含 UV 缺陷：旧模型用 x/y/z 混合平面映射圆形棋子，圆周侧壁产生拉伸；已改为“侧壁圆柱 UV + 顶/底面独立平面 UV”，重建 GLB 后 UV 范围稳定为 0..1。
40. 金丝楠木源贴图分辨率为 1254×1254，Godot 导入为无损纹理并生成 Mipmap，因此低分辨率或有损压缩不是主要模糊来源。
41. 棋子材质已降低过强高光：wood roughness 0.14→0.32、face roughness 0.18→0.34、coat 0.60/0.50→0.18/0.16；Godot 运行时启用 Linear Mipmaps Anisotropic（线性多级纹理各向异性）过滤，并降低环境光/主光/补光强度。
42. Blender 5.2.1 已重新生成 chess_pieces.glb；重新导入后的材质与 UV 通过 Blender 二次检查，Godot 4.7.2 再次完整导入且自动双客户端对局无脚本错误。
43. 已从 `C:\Users\Administrator\Downloads\u_ej49m6thqx-chinese-guzheng-1-308264.mp3` 复制导入正式背景音乐资产，并按项目小写下划线规范重命名为 `client/games/chinese_chess/assets/audio/bgm_chinese_guzheng_01.mp3`；原下载文件保持不变。
44. 新古筝 BGM 文件 SHA-256 为 `0A31F28A07F3265EF62C4812EA58D508630086A4E70781BDE686675806837B04`，大小 7,680,768 字节；`bgm_guofeng.wav` 保留为目标平台导入失败时的降级备用音乐。
45. Godot 4.7.2 已实际扫描并重新导入 `bgm_chinese_guzheng_01.mp3`；双客户端运行日志均显示 `CHESS_BGM_SOURCE path=res://modules/games/chinese_chess/assets/audio/bgm_chinese_guzheng_01.mp3 stream=AudioStreamMP3`，证明当前默认播放源为新导入古筝音乐。
46. 新古筝 BGM 的开关验证通过：自动切换客户端记录 `CHESS_BGM_VALIDATE_OFF enabled=false paused=true`，随后 `CHESS_BGM_VALIDATE_ON enabled=true paused=false`；背景音乐暂停/恢复逻辑继续正常工作。

47. 象棋运行棋盘已从平面 `engraved_chessboard.png` 视觉覆盖切换为真实 `chess_board.glb（三维棋盘模型）`；程序化平面棋盘仅保留为 GLB 资源异常时的降级路径。
48. “楚河 / 漢界”已按双方玩家阅读方向分别处理：Blender 验证 `Chu He=3.141593 rad（180°）`、`Han Jie=0°`，即楚河朝黑方、漢界朝红方，不再同向。
49. 三维棋盘最终导出尺寸为 `0.392 × 0.432 m`；Godot 运行时按棋格比例缩放后，棋子外缘到棋盘左右/上下边缘净空均为 `0.430` 游戏单位，四周边距完全一致，约为半个棋格宽度。
50. 红檀木棋盘新增 `red_sandalwood_woodgrain_normal.png（法线贴图）` 与 `red_sandalwood_woodgrain_roughness.png（粗糙度贴图）`，GLB 二次检查确认主材质 Normal/Roughness 均已连接。
51. Godot 运行时最终证据：`CHESS_GLTF_LOAD board=true pieces=true`；`CHESS_BOARD_PBR ... albedo=true normal=true roughness=true`；`CHESS_BOARD_CLEARANCE horizontal=0.430 vertical=0.430`，证明当前客户端实际使用新三维棋盘而非旧平面降级棋盘。
52. 手机与 PC 双端真实 GUI 验证继续通过：手机识别 `PHONE_PORTRAIT（手机竖屏）`，PC 识别 `DESKTOP（桌面布局）`；两端进入同一房间并保持服务端权威走棋、增强走棋音效和古筝 BGM 正常。

## 当前环境限制

Runner 本机已安装 Godot 4.7.2，并完成两个产品的 Headless（无界面）解析及主场景运行验证。Windows/Android 正式导出仍需要继续校验导出模板、Android SDK/JDK、签名与渠道配置。

## 尚未声称完成的生产能力

- 微信 OpenSDK 真机授权、微信商户真实下单/验签/退款联调需要真实 AppId、商户号和证书。
- 贵阳麻将完整胡牌、番型、结算规则必须依据最终业务规则逐条验收后实现。
- 中国象棋当前实现基础走子规则，完整长将、长捉、和棋等竞赛规则仍需补齐。
- 当前 WebSocket 已验证实时通信通道，完整多人牌局 Command→RuleSet→Event→State 调度将在后续迭代继续接入。
- Android 正式签名、渠道SDK和发布包需真实签名材料。
- AI 当前为标准接口、功能开关与客户端表现层预留，未伪造真实模型能力。