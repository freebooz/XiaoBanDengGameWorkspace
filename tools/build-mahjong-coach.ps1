[CmdletBinding()]
param(
    [string] $Cargo = 'cargo',
    [string] $AndroidNdk = $env:ANDROID_NDK_HOME,
    [switch] $WindowsOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root '.tmp/mahjong-coach/native'
$targets = Join-Path $root '.tmp/mahjong-coach-rust/target'
$manifest = Join-Path $root 'rust-gdext/Cargo.toml'
$originalTargets = $env:CARGO_TARGET_DIR
$originalLinker = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
$libraries = [ordered]@{
    'windows.x86_64' = 'mahjong_coach_gdext.dll'
}
try {
    $env:CARGO_TARGET_DIR = $targets
    & $Cargo build --locked --release --manifest-path $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Windows Mahjong coach extension failed to build.' }
    if (-not $WindowsOnly) {
        if (-not $AndroidNdk) { throw 'Set AndroidNdk or use WindowsOnly for a Windows development build.' }
        $ndkBin = Join-Path $AndroidNdk 'toolchains/llvm/prebuilt/windows-x86_64/bin'
        $ndkClang = Join-Path $ndkBin 'clang.exe'
        if (-not (Test-Path -LiteralPath $ndkClang -PathType Leaf)) { throw 'Android NDK clang is missing.' }
        $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $ndkClang
        $originalAndroidFlags = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS
        try {
            $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS = '-C link-arg=--target=aarch64-linux-android24 -C link-arg=-Wl,-z,max-page-size=16384'
            & $Cargo build --locked --release --target aarch64-linux-android --manifest-path $manifest
            if ($LASTEXITCODE -ne 0) { throw 'Android Mahjong coach extension failed to build.' }
        } finally {
            $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS = $originalAndroidFlags
        }
        $libraries['android.arm64'] = 'libmahjong_coach_gdext.so'
    }
    New-Item -Path $destination -ItemType Directory -Force | Out-Null
    $config = @('[configuration]', 'entry_symbol = "gdext_rust_init"', 'compatibility_minimum = "4.7"', 'reloadable = false', '', '[libraries]')
    foreach ($entry in $libraries.GetEnumerator()) {
        $target = if ($entry.Key -eq 'android.arm64') { 'aarch64-linux-android/release' } else { 'release' }
        $source = Join-Path $targets "$target/$($entry.Value)"
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $config += "$($entry.Key) = `"res://modules/games/mahjong/guiyang/native/$($entry.Value)`""
    }
    $config | Set-Content -LiteralPath (Join-Path $destination 'mahjong_coach.gdextension') -Encoding utf8NoBOM
    Write-Output "MAHJONG_COACH_NATIVE_READY $destination"
} finally {
    $env:CARGO_TARGET_DIR = $originalTargets
    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $originalLinker
}
