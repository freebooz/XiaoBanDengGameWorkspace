# 麻将候选包构建

`tools/export-mahjong-candidate.ps1` 从当前工作区组合独立的麻将工程，在新的输出目录中导入资源，生成 Windows x64 以及 Android ARM64 包。构建清单记录版本、默认服务地址、引擎版本和包的 SHA-256。Windows 运行时需要将同名 EXE 与 PCK 放在同一目录。

```powershell
pwsh -NoProfile -File tools/export-mahjong-candidate.ps1 `
  -Godot <Godot-console.exe> -TemplateArchive <matching-export-templates.tpz> `
  -Version 0.2.0 -VersionCode 2 -Server https://majiang.example.com `
  -AndroidSdk <Android-SDK-directory> -JavaSdk <JDK-directory>
```

脚本要求与编辑器版本一致的 Godot 导出模板。本机的 Android 安装测试可使用 APK，面向 Google Play 的发行仍需按商店要求生成 AAB。 [Godot Android 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)

外部 HTTPS 地址的 Android 构建从进程环境读取 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`、`GODOT_ANDROID_KEYSTORE_RELEASE_USER`、`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`。Windows 发行证书签名按实际发布环境处理。

## 本机 TLS 验证

先用 `tools/test-mahjong-linux-tls.ps1 -KeepRunning` 启动隔离 Linux 测试服务。将其输出的本机 HTTPS 地址传给 `-Server`，并将对应的 `ca.crt` 传给 `-LocalTestCA`。此配置仅接受回环地址，并且只打包公开 CA 证书。本机测试 APK 使用临时签名。测试结束后按 Linux 验证说明清理服务。

验证 Windows 包时使用独立账号资料目录，并传入 `--disable-vsync --max-fps 0`。在测试服务上核对四个客户端分别进入大厅并获得同房的四个不同座位。Android 先以 `apksigner verify` 核对签名，再检查包 ID `com.freebooz.xiaobandeng.mahjong`、版本、ARM64 和麦克风及网络权限。实机还需核对首登、横屏对局、触控、重连、麦克风拒绝及信任链。
