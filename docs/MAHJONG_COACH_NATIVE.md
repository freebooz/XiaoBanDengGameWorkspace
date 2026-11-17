# 麻将牌效 Rust 模块

当前小板凳 Godot 工程使用 Godot 4.7。牌效算法在 `rust-core`，Godot 绑定在 `rust-gdext`。分析输入包含本人暗手牌、去重公开牌、牌墙配置、本人已完成副数/副露牌种及允许弃出的牌种。上下文分析另接收剩余牌数、公开定缺/副露/杠/报听及规则开关；不读取他人暗手或隐藏牌墙。

## 本地构建

安装 Rust MSVC 工具链并在 Visual Studio x64 开发者 PowerShell 中运行。Android 构建使用支持 ARM64 的 Android NDK。

```powershell
rustup target add aarch64-linux-android
./tools/build-mahjong-coach.ps1 -AndroidNdk <NDK目录>
./tools/compose-godot.ps1 -Product mahjong
```

仅构建 Windows 开发版本时使用 `-WindowsOnly`。构建结果写入当前项目的 `.tmp/mahjong-coach/native`。麻将产品组合脚本直接复制已有扩展和库，组合时不会运行 Cargo。Windows 发布目录需要把 DLL 与 EXE、PCK 一同保留。Android 导出将 ARM64 库装入 APK 的 `lib/arm64-v8a`。扩展缺失时，本地牌效按界面约定显示 `—`。

## 调用约定

`MahjongCoachBridge.analyze_all(hand, visible, totals, meld_count, legal)` 的前三项使用长度为 34 的 `PackedInt32Array`。`legal` 包含当前可以弃出的牌种索引。下标 0–8 为万，9–17 为筒，18–26 为条，27–33 为字牌。108 张规则将字牌总数设为 0。

Godot 适配层支持贵阳捉鸡 `2.0.0` / `3.0.0`、基础 108 `1.0.0` 和遵义定缺 `1.0.0`，遇到未知玩法或版本显示 `—`。服务器若为打出动作提供 `tile_id`，同牌种的其他实体也必须各自获准。被副露拿走的弃牌按 ID 归并，未公开的暗杠不扣具体牌种。快照若公开翻鸡指示牌，计为单独的一张已知牌。`last_discard` 和 `ji_events` 是公开动作记录，实体已在弃牌河或副露中统计。

结果中 `shanten.minimum` 为结构向听，弃牌分析取弃牌后的手牌；`ukeireCount` 为所有结构有效牌的未见张数之和。每种有效牌含有 `tile` 和 `count`。同种牌只返回一行。进张基数使用模拟弃牌前的暗手牌及去重后的公开牌，以免把试打的牌再扣一次。`legalWaits` 返回 `not_checked`，结构完成并不代表已通过服务端完整规则验胡。

实际对局使用 `analyze_discards_with_context(hand, visible, totals, meld_count, own_meld_tiles, legal, context)`；等牌状态使用 `analyze_hand_with_context`。并列候选按公开风险、Q/K 有限前瞻、放杠与鸡牌暴露等因素继续排序。`rank` 为返回的推荐顺序，客户端只在轮到本人时默认选中合法实体，玩家手动选择优先，出牌仍须输入提交。

`lookAheadEvaluated` 为真时 `q` / `k` 才表示实际展开的前瞻指标；为假或旧扩展缺少字段时，不能把零显示成已计算结果。Q/K 和风险计数不是概率或鸡蛋收益。接炮候选目前筛选杠/定缺等已输入资格，不涵盖所有过胡状态；操作资格仍以服务端为准。`rankingReason` 解释与紧邻下一名的区别，最后一名的 `stable` 不表示它与第一名同分。研究、排序定义和实测边界见 [研究记录](MAHJONG_AI_RESEARCH_20261117.md)。

## 回归

```powershell
$env:CARGO_TARGET_DIR = Join-Path $PWD '.tmp/mahjong-coach-rust/target'
cargo test --locked --manifest-path rust-core/Cargo.toml
$project = Join-Path $PWD 'client/.generated/mahjong'
godot --headless --path $project --import
godot --headless --path $project --script (Join-Path $PWD 'client/tests/mahjong_coach_bridge_smoke.gd') --disable-vsync --max-fps 0
```
