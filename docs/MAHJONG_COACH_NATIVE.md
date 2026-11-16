# 麻将牌效 Rust 模块

当前小板凳 Godot 工程使用 Godot 4.7。牌效算法在 `rust-core`，Godot 绑定在 `rust-gdext`。分析输入只包含本人当前暗手牌的牌种计数、已知公开牌计数、牌墙配置、本人已完成副数和本次允许弃出的牌种。

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

Godot 适配层按贵阳捉鸡 `2.0.0` 和基础 108 `1.0.0` 的牌墙计算，遇到未知玩法或版本显示 `—`。服务器若为打出动作提供 `tile_id`，同牌种的其他实体也必须各自获准。被副露拿走的弃牌按 ID 归并，未公开的暗杠不扣具体牌种。快照若公开翻鸡指示牌，计为单独的一张已知牌。`last_discard` 和 `ji_events` 是公开动作记录，实体已在弃牌河或副露中统计。

结果中 `shanten.minimum` 为弃牌后的结构向听，`ukeireCount` 为所有结构有效牌的未见张数之和。每种有效牌含有 `tile` 和 `count`。同种牌只返回一行。排序先看向听，再看进张。进张基数使用模拟弃牌前的暗手牌及去重后的公开牌，以免把试打的牌再扣一次。`legalWaits` 返回 `not_checked`，当前模块没有规则番型验胡及风险模型。

## 回归

```powershell
$env:CARGO_TARGET_DIR = Join-Path $PWD '.tmp/mahjong-coach-rust/target'
cargo test --locked --manifest-path rust-core/Cargo.toml
$project = Join-Path $PWD 'client/.generated/mahjong'
godot --headless --path $project --import
godot --headless --path $project --script (Join-Path $PWD 'client/tests/mahjong_coach_bridge_smoke.gd') --disable-vsync --max-fps 0
```
