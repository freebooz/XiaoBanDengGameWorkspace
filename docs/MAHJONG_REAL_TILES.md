# 真实麻将牌模型与材质

2026-10-09，实际导入原麻将项目的牌身，替换此前三个简单几何体与界面牌面图片。

## 来源与形体

- 只读来源：`E:/work/Game/MahjongGame/Saved/Diagnostics/Mahjong50/SM_Mahjong50_Characters_1.fbx`，原 Unreal 项目已有的网格诊断导出，非根据图片重新拼接。
- 实际尺寸：宽 36、长 50、厚 26 毫米；1,332 个三角面。坐标转换后正面朝上、底面高度为零。
- 保留原圆角、正面过渡法线和双色分层遮罩。模型分成 `TileBody` 与 `TileFace` 两个可复用材质部件，焊接后为闭合实体。正面复用原有的两个三角面，无重叠平面。
- 编辑源：`SourceAssets/Mahjong/mahjong_tile.blend`；规范运行资源：`client/games/mahjong/guiyang/assets/models/mahjong_tile.glb`。

## 材质与 UV

- 乳白树脂与绿色背层：粗糙度 0.27／0.25、非金属、适量清漆；原模型顶点 R 分层遮罩显式输出为 `COLOR_0`，游戏共享 `tile_resin.gdshader` 处理双色。GLB 牌身的默认材质用于承载遮罩，完整双色效果须通过项目共享材质或保存的 Blender 材质查看。
- 牌面复用原项目 `T_Mahjong50_FaceAtlas_{BaseColor,Normal,ORM,Height}.png`，从 8192 × 4096 转为 4096 × 2048。运行时使用底色、凹刻法线、AO／粗糙度，Height 保留为作者资源，没有将凹刻宣称为额外雕刻几何。
- 图集每张牌有效区对应原图宽 704、高 1024、横向步距 896、起点 160。三个游戏花色只更改图集偏移，共享纹理和网格。没有整图拉伸、镜像或每张牌复制贴图。
- 底色用 sRGB，法线与 ORM 用线性数据；ORM 红通道为 AO、绿通道为粗糙度。源法线与高度梯度一致，保留 OpenGL 方向。
- 牌面使用不透明材质，避免原界面图透明混合造成的平面边缘。对手使用无图案的空白正面，绿色背面朝玩家，客户端不创建对手的暗牌图案。
- 手牌整体比例从 2.15 调整为 2.50，以维持原屏幕宽度；物理牌身比例与网格未被拉伸。

## 检查结果

- 独立空场景重开 `.blend` 和 GLB：实际尺寸、几何闭合、UV 上下左右、共享角点法线连续、双色颜色通道、PBR 贴图及资产哈希检查通过。
- Godot 4.7.2 Vulkan 原生检查：真实 `COLOR_0`、27 张牌材质缓存与共享纹理、无效牌空白面检查通过。
- 1440 × 810、844 × 390、1024 × 768 Windows 窗口：十四张手牌实际 GUI 鼠标／触屏事件、低中高三档画质、完整牌面和控件边界、四方 48 张公开弃牌、红色字迹像素、训练与返回检查通过。这些为桌面移动比例模拟，未执行手机硬件验收。
- Blender 产品近景：`artifacts/mahjong_models/real_mahjong_tile_preview.png`；游戏真实材质近景：`real_mahjong_native_closeup.png`；三种比例：`real_mahjong_{pc,phone,tablet}.png`。

## 重建

用 Blender 后台执行 `tools/import_real_mahjong_tile.py`，再从空场景执行 `tools/validate_real_mahjong_tile.py`。输出只写入本项目。运行 `tools/compose-godot.ps1 mahjong` 后重新导入模型，可执行 `client/tests/real_mahjong_tile_smoke.gd` 和 `client/tests/mahjong_screen_smoke.gd`。

原 FBX 与原始贴图的 SHA256 以及当前导出文件哈希保存在 `assets/models/model_manifest.json`。旧简化牌身备份保存在 `artifacts/mahjong_models/before_real_tile_import`。
