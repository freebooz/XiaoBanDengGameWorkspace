# 小板凳麻将牌桌电影布光

## 采用的配置

以暖色斜上方主光塑造牌身和木框，用近相机的中性补光照亮立牌上的红、绿、黑牌字。对角冷光分离蓝色牌背与深绿桌面。村口背景保持独立曝光。这个分工采用电影布光中的主光、补光和分离光，并根据牌桌的镜头和材质调整。 [ARRI 灯光手册](https://www.arri.com/resource/blob/127830/409091c612f371b0c68b41d9dcb636db/arri-lighting-handbook-english-data.pdf) · [ASC《Chef’s Table》摄影访谈](https://theasc.com/article/chefs-table-a-tasting-menu/)

| 光源 | Godot 类型和位置，单位米 | 颜色 | 能量倍率 | 细节 |
| --- | --- | --- | ---: | --- |
| 主光 | `SpotLight3D`，`(-0.60, 1.20, 0.42)`，指向桌心 | `#FFE5CB`，约 4800 K | 1.18 | 相对相机前方偏左约 55°，仰角约 58.6°。光锥半角 55°，范围 2.7 m，距离衰减 0.45，角度衰减 0.55，镜面 0.46。 |
| 手牌补光 | `OmniLight3D`，`(0, 0.30, 0.82)` | `#FFF7EF`，约 6000 K | 0.27 | 范围 1.48 m，衰减 1.30，镜面 0.32，无投影。 |
| 对角轮廓光 | `OmniLight3D`，`(0.64, 0.44, -0.64)` | `#DCEAFF`，约 7800 K | 0.15 | 范围 1.30 m，衰减 1.30，镜面 0.32，无投影。省电档关闭。 |
| 环境和反射 | `WorldEnvironment`，静态 HDR 软箱反射 | 环境色 `#EBEFF4` | 0.11 | 阴影保持层次，木框和牌身保留宽而连续的反光。 |

项目沿用 Godot 非物理能量倍率，色温是灯色的 sRGB 近似。实际牌面接收的照度还取决于位置、表面法线和衰减。主光是唯一实时投影光，使用 PCF，`light_size=0`、不透明度 `0.72`、偏移 `0.012`、法线偏移 `0.16`，均衡档模糊 `1.30`。牌身投下接触阴影，牌面薄层保留正常可见渲染。 [Godot 物理灯光单位](https://docs.godotengine.org/en/4.7/tutorials/3d/physical_light_and_camera_units.html) · [Godot 阴影参数](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html)

均衡及高清档使用 `Filmic`，曝光 `1.06`，白点 `1.75`。这组参数在原生测试中抬高了立牌中间调，同时保留亮部层次。桌布、木面和麻将字纹继续使用原有材质。 [Godot 4.7 色调映射](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html#tonemap) · [Mobile 白点限制](https://docs.godotengine.org/en/4.7/classes/class_environment.html#class-environment-property-tonemap-white)

## 同机位对照

Windows RTX 4090，Godot Vulkan Forward Mobile，1440×810 窗口，1440×750 三维缓冲。三组使用相同的机位、麻将模型、牌面和阴影几何。每组预热 45 帧后采样 144 帧。亮度值为手牌正面区域 5,035 个同位置像素的 8 位 sRGB 加权亮度中位数。

| 方案 | 手牌区域亮度中位数 | 牌桌 GPU P95 |
| --- | ---: | ---: |
| 旧灯位和线性色调映射 | 135.5 | 0.201 ms |
| 新冷暖布光和线性色调映射 | 166.4 | 0.160 ms |
| 推荐冷暖布光与 Filmic | 186.9 | 0.160 ms |

推荐方案中，该采样区域没有 RGB 三通道均达 252 的像素。使用同一套冷暖灯光时，线性和 Filmic 的桌面 GPU P95 在该轮采样精度内一致。三组首轮顺序固定，旧布光行的 GPU 差值不用于宣称性能提升。

[原灯光原生图](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/cinematic-light-study/legacy-linear.png) · [冷暖灯光加线性色调映射](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/cinematic-light-study/warm-cool-linear.png) · [推荐方案原生图](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/cinematic-light-study/balanced-filmic.png) · [原始采样日志](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/cinematic-light-study/lighting-study.log)

## 手机预算

| 画质档 | 实际聚光阴影图 | 抗锯齿 | 色调与装饰 |
| --- | ---: | --- | --- |
| 省电 | 512²，Soft Very Low PCF | 2× MSAA | Linear，保留手牌补光，关闭轮廓光，128² 静态反射。 |
| 均衡 | 1024²，Soft Low PCF | 2× MSAA | Filmic，保留轮廓光，128² 静态反射。 |
| 高清 | 2048²，Soft Low PCF | 4× MSAA | Filmic，保留轮廓光，256² 静态反射，适合实测仍有余量的设备。 |

Godot 位置阴影图集为 1024、2048、4096，每档只启用一个象限，所以实际阴影图边长减半。三档始终按原生物理像素渲染，避免放大低分辨率牌面。移动版优先维持一个投影光、关闭景深和泛光、使用静态反射。若 GPU 带宽成为瓶颈，先比较省电档的 2× MSAA 与关闭，再根据细边和斜角的可读性决定。 [Godot Mobile 架构](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html) · [Godot 抗锯齿](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) · [Arm 移动渲染通道指南](https://documentation-service.arm.com/static/6560a5942c8b3557fee70a16)

真机观察冷启动、静止桌面、连续摸打、密集副露和持续运行 15–20 分钟后的帧时间与温度。以 60 Hz 流畅度作为首轮验收目标时，建议用 16.67 ms 整帧时间和 GPU P95 ≤12 ms 作为项目预算。调试保持不限帧。当设备对 Godot SurfaceView 缺少完整 FrameTimeline 数据时，同时读取引擎 GPU 计时、系统图层呈现间隔和热状态。 [Android 帧时间分析](https://developer.android.com/android-performance-analyzer/analyze/frame-times) · [Perfetto FrameTimeline](https://perfetto.dev/docs/data-sources/frametimeline) · [Android 热性能](https://developer.android.com/games/optimize/adpf/thermal)

本次 0.4.18 独立包已在 MAA-AN10 安装并显示真实登录页。手机两次在游客操作前回到系统桌面，因此局内帧时间和持续热负载仍待测。桌面数据不能替代手机结果。 [真机运行记录](C:/Users/Administrator/.codex/visualizations/2026/11/11/01a1cb06-1fab-7d23-9d87-b19ce61acf79/mahjong-ui-layout-audit-20261117/phone-perfnov17-0.4.18/device-run.json)

实现见 [mahjong_table_theme.gd](../client/games/mahjong/guiyang/mahjong_table_theme.gd) 与 [牌身投影设置](../client/games/mahjong/guiyang/real_tile_model.gd)。
