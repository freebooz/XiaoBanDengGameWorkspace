# 小板凳麻将乡村风弹窗

在对局点击右上角「设置」打开游戏设置。服务器发来已完成的牌局快照后进入本局结算。关闭结算后，可在当前牌桌点击「本局结算」重新查看。返回大厅、查看规则及可用时的同房再来一局继续走原有入口。

## 工程接入

| 文件 | 职责 |
| --- | --- |
| `client/games/mahjong/guiyang/guiyang_3d_screen.gd` | 打开面板和传入实际快照，复用音频与画质设置、结算和下一局入口 |
| `client/games/mahjong/guiyang/mahjong_settings_view.gd` | 四类设置导航，实际音频开关、报牌音色、三档画质和只读规则，设置即时生效并保存 |
| `client/games/mahjong/guiyang/mahjong_settlement_view.gd` | 结果徽章、四席头像、带符号得分、牌型与原有翻鸡牌信息 |
| `client/games/mahjong/guiyang/mahjong_rural_modal.gd` | 两个弹窗共享九宫格框、纸面、题签、按钮、图标、开关和列表样式 |
| `client/games/mahjong/guiyang/assets/ui/rural_modal/` | 分离的木框、纸纹、题签、村景、竹叶、木凳、陶器、按钮与控件图案 |

只显示项目现有的设置项。音频没有独立主音量；当前设置采用即时保存，因此底部保留「完成」。结算展示服务器已有得分字段；当前弹窗可查看规则，回放继续从现有战绩入口打开。

尺寸、切片与素材来源见[弹窗素材说明](../client/games/mahjong/guiyang/assets/ui/rural_modal/ASSETS.md)。
