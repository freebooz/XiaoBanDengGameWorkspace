# 小板凳横屏对局与斗地主参考界面

更新日期：2026-10-09。

## 已实现

四款游戏对局均采用横屏，保留登录、大厅、训练和房间流程。公共界面使用深玉色、暖金边框、统一玩家卡片；对局结束后恢复大厅显示。每个三维视口拥有独立场景，避免多个客户端的牌桌和手牌混在一起。

| 游戏 | 对局布局 |
| --- | --- |
| 象棋 | 中央三维棋盘，左侧对手在上、自己在下，右侧操作与状态 |
| 麻将 | 黑金三维桌、翡翠提花桌布、四方切角玩家卡片、直立真实手牌、中央回合倒计时、五色响应圆按钮和独立打出入口 |
| 斗地主 | 园林背景、左右人物、木纹三维桌、底部大手牌、顶部底牌和倍数、六项主要动作及工具栏 |
| 掼蛋 | 四人三维桌，自己在下、搭档在上，两排 27 张手牌和右侧出牌操作 |

斗地主与掼蛋继续共用一套三维扑克牌。黑桃、梅花和小王改为蓝色，红牌保持红色；增大牌点，减弱反光，修正叠牌深度和点击选择。

## 斗地主按钮

抢地主、不抢、加倍、不加倍、提示、出牌、不出均接入真实服务器规则；非法阶段及轮次禁用，倒计时使用服务器截止时间。断线或尚未收到新状态时禁用发送，失败时保留弹窗和选择。

设置实际切换低、中、高画质、音乐和音效；背包切换免费牌背和桌面并保存；规则显示当前玩法；退出返回大厅。理牌在点数和花色间切换并保留选牌，收起实际隐藏三维手牌。

聊天、表情和免费道具由服务器校验后同桌广播；语音按住录制、松开发送，最长五秒。战绩仅记录实际收到的结算，标记训练局并防止重复保存。按钮明细和版本兼容说明见 [斗地主说明](LANDLORD.md)。

## 预览

以下为 Windows Godot 实际渲染；比例预览使用固定测试牌局，实际训练截图来自真实服务。

| 游戏 | PC 1440×810 | 手机比例 844×390 | 平板比例 1024×768 |
| --- | --- | --- | --- |
| 象棋 | [预览](../artifacts/landscape/chinese_chess_pc.png) | [预览](../artifacts/landscape/chess_phone.png) | [预览](../artifacts/landscape/chess_tablet.png) |
| 麻将 | [预览](../artifacts/landscape/mahjong_club_pc.png) | [预览](../artifacts/landscape/mahjong_club_phone.png) | [预览](../artifacts/landscape/mahjong_club_tablet.png) |
| 斗地主 | [预览](../artifacts/landscape/landlord_pc.png) | [预览](../artifacts/landscape/landlord_phone.png) | [预览](../artifacts/landscape/landlord_tablet.png) |
| 掼蛋 | [预览](../artifacts/landscape/guandan_pc.png) | [预览](../artifacts/landscape/guandan_phone.png) | [预览](../artifacts/landscape/guandan_tablet.png) |

[斗地主真实训练操作截图](../artifacts/landscape/landlord_training_live.png)。园林、角色和桌面贴图的生成提示及用途见 [美术资源记录](../client/games/landlord/assets/ui/ARTWORK.md)。牌桌和牌均使用原有真实三维模型。

麻将最新黑金参考布局及实际按钮／语音说明见 [麻将参考界面](MAHJONG_REFERENCE_UI.md)；[此前湖景版四客户端牌局截图](../artifacts/landscape/mahjong_reference_live.png) 为之前联网验收的记录。

## 验证记录

| 检查 | 结果 |
| --- | --- |
| 四产品组装和 Godot 导入 | 通过，无脚本导入错误 |
| 横屏、按钮边界、三维视口比例、大厅显示恢复 | 通过 |
| 象棋模型点击与实际触摸分发 | 通过，触摸不会重复走两次 |
| 麻将 14 张手牌、牌面可读性、六项反应、三档画质 | 通过，原生 Vulkan 渲染与点击检查 |
| 掼蛋训练与四客户端房间 1431 | 通过，108 张私有牌、独立三维场景、出牌、离开及大厅恢复 |
| 斗地主三个实际客户端房间 7852 | 通过，完整叫分/加倍/提示/出牌/不出/结算，聊天广播、战绩去重和大厅恢复 |
| 斗地主实际登录、大厅、训练和界面操作 | 通过，真实服务和原生客户端 |
| 语音编码、播放、五秒运输 | 通过，8 kHz 与 16 kHz 的最大 PCM 消息实际发送并接收 |
| 服务端全量 Go 测试及新增规则/社交/运输校验 | 通过，服务已重新构建并运行 |
| 独立代码复核 | 连接就绪、发送错误和语音容量问题已修复并复核通过 |

手机和平板比例测试运行于 Windows；实体 Android 安装、麦克风权限与音质、设备帧率仍需要设备验收。象棋本次调整界面和点击流程，原有联网悔棋、提示、求和处理范围未在本次扩展。

## 启动

运行平台服务后，使用 `tools/compose-godot.ps1` 分别生成 `chinese_chess`、`mahjong`、`landlord` 或 `guandan` 产品。在 Godot 打开对应 `client/.generated/<产品>/project.godot`，游客登录后选择训练或快速对局。
