# 象棋棋盘与棋子交付

更新：2026-09-30。采用用户最新 `codex-clipboard-3d5064aa-4bef-4a0a-882e-3f77d1e88161.png`，保留楚河、汉界各自朝向。

## 当前文件

- `XBD_ChineseChess_Set.blend`：可编辑完整模型，含棋盘、14 种棋子母版、32 枚开局棋子与灯光相机。纹理已打包。
- `XBD_ChessBoard_engraved_preview.png`：无遮挡的棋盘全貌。
- `XBD_ChessBoard_groove_detail.png`：走棋线真实凹槽近景。
- `XBD_ChineseChess_Set_preview.png`：完整棋盘棋子效果图。
- `XBD_Game_red_preview.png`、`XBD_Game_black_preview.png`：实际 Godot 客户端两侧视角截图。
- `XBD_Game_quality_menu.png`：前端低、中、高画质菜单；`XBD_ChessBoard_corner_detail.png`：圆角与侧壁。
- `../../../client/games/chinese_chess/assets/models/chess_board.glb` 与 `chess_pieces.glb`：客户端已接入的模型。

## 本次修改

- 红檀木棋盘 412 × 452 × 6 mm，平整底面，无底座和支脚。四角为半径 6 mm 的凸圆角，四周棋子外缘留白均为 28 mm。
- 主格线、河界边线、九宫斜线是真实减去木材的凹槽，主线约 1 mm 宽，中心深度 0.775 mm。
- 兵炮位标记同样阴刻，中心深度约 0.65 mm。槽内深棕色填色均低于盘面。
- 修复曲线转网格时端盖顶点未连接，导致凹槽切割未生效的问题；切割前检查封闭性。
- 棋子为黄色光泽金丝楠木，直径 36 mm、厚 10 mm。木纹对比减至原图的 25%；文字和圆圈采用平面红黑着色，内边距约 2.4 mm。
- 客户端使用 Blender 导出模型，并适配车的命名、材质照明和抗锯齿。
- 盘面改为同一连续仿射平面 UV，消除旧分段插值约 21.54 像素的非线性偏移。走棋槽和棋子落点跟随原图交点，GLB extras 的 `grid_x_m` / `grid_y_m` 传递相同物理坐标，图片不做局部拉伸。
- 四角侧壁沿整个周长连续展开，使用盘面图片的无装饰木纹条带，避免转角映射跳变。纹理边缘延伸，前端关闭重复。
- 盘面清漆 coat 0.20、coat roughness 0.24、base roughness 0.40；棋子 coat 0.58、coat roughness 0.12、normal strength 0.08。
- 最新源图与打包图片 SHA-256：`EC7B2623FD1A0C9FBB974645847CEB95CD824B02EFC7A0D5DC18CF1EE6C27EAF`。

## 前端视角与画质

摄像机采用透视投影，FOV 45°，距盘面高度 13.7、环绕半径 6.05（游戏单位）。前后沿投影宽度比约 1.302，匹配参考图的前宽后窄轮廓，红黑双方相差 180°。

菜单 → 画质，即时切换并自动保存到 `user://chinese_chess_visuals.cfg`，默认中档。

| 档位 | 棋盘渲染尺寸 | 抗锯齿 | 阴影 / 纹理过滤 |
| --- | --- | --- | --- |
| 低 · 流畅 | 750 × 855 | 2× MSAA | 无阴影 / Mipmap |
| 中 · 均衡 | 1000 × 1140 | 4× MSAA | 阴影 / 各向异性 Mipmap |
| 高 · 精细 | 1500 × 1710 | 8× MSAA | 阴影 / 各向异性 Mipmap |

档位不改变相机角度、模型尺寸或棋局，拾取计算使用实际渲染尺寸。

## 已验证

- 实际通过官方 Blender MCP 执行建模和导出。
- 在独立 Blender 进程重开保存文件，120 项结构、尺寸与刻槽检查，以及最新图片一致性、圆角和连续 UV 检查通过。UV 最大残差约 0.00009 像素。结果见 `validation_report.json`、`saved_model_validation.log`。
- Godot 导入 14 母版、32 棋子；两侧 180 个交点投影与点击核对、透视轮廓和四角可见性通过，见 `game_visual_validation.log`。
- 三档切换和保存重载、两侧共 540 次点击及三种菜单布局通过，见 `render_quality_validation.log`。六种屏幕布局分类通过，见 `layout_validation.log`。
- 已人工查看完整渲染、无遮挡棋盘、凹槽近景及游戏截图。
- 以上为本机资产与客户端验证，移动设备性能尚未实机测量。截图中的开局预览不代表联机对局验收。

`XBD_ChineseChess_RedSandalwood_Archive.blend` 是此前雕花红檀木方案的存档。名称含 `BeforeFlushCorrection` 的文件及 `.blend1` 为历史备份，当前交付使用 `XBD_ChineseChess_Set.blend`。
