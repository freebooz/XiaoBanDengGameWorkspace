# 象棋棋盘与棋子交付

更新：2026-09-30。当前版本以最新的简洁竹木棋墩参考为准。

## 当前文件

- `XBD_ChineseChess_Set.blend`：可编辑完整模型，含棋盘、14 种棋子母版、32 枚开局棋子与灯光相机。纹理已打包。
- `XBD_ChessBoard_engraved_preview.png`：无遮挡的棋盘全貌。
- `XBD_ChessBoard_groove_detail.png`：走棋线真实凹槽近景。
- `XBD_ChineseChess_Set_preview.png`：完整棋盘棋子效果图。
- `XBD_Game_red_preview.png`、`XBD_Game_black_preview.png`：实际 Godot 客户端两侧视角截图。
- `../../../client/games/chinese_chess/assets/models/chess_board.glb` 与 `chess_pieces.glb`：客户端已接入的模型。

## 本次修改

- 棋盘主体约 368 × 408 × 24 mm，平齐盘面，底部保留一体支脚和浅弧形让位。
- 主格线、河界边线、九宫斜线是真实减去木材的凹槽，主线约 1 mm 宽，中心深度 0.775 mm。
- 兵炮位标记同样阴刻，中心深度约 0.65 mm。槽内深棕色填色均低于盘面。
- 修复曲线转网格时端盖顶点未连接，导致凹槽切割未生效的问题；切割前检查封闭性。
- 棋子为黄色光泽金丝楠木，直径 32 mm，木质主体厚 10 mm。文字和圆圈采用平面红黑着色；文字与圆圈内缘至少保留约 2 mm 间距。
- 客户端使用 Blender 导出模型，并适配车的命名、材质照明和抗锯齿。

## 已验证

- 实际通过官方 Blender MCP 执行建模和导出。
- 在独立 Blender 进程重新打开保存文件，120 项结构、尺寸、材质、棋子和刻槽检查通过。结果见 `validation_report.json`、`validation.log`。
- Godot 导入 14 种母版、32 枚棋子及新棋盘；红黑双方视角共 180 个交点的投影与点击位置核对通过。结果见 `godot_runtime_review_final.log`。
- 已人工查看完整渲染、无遮挡棋盘、凹槽近景及游戏截图。
- 本次验证范围为资产与界面显示、坐标匹配；截图中的开局预览不代表联机对局或移动设备验收。

`XBD_ChineseChess_RedSandalwood_Archive.blend` 是此前雕花红檀木方案的存档。名称含 `BeforeFlushCorrection` 的文件及 `.blend1` 为历史备份，当前交付使用 `XBD_ChineseChess_Set.blend`。
