param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("chinese_chess","mahjong","landlord","guandan")]
    [string]$Product,
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$productPath = Join-Path $workspace ("products\" + $Product + "\product.json")
$config = Get-Content $productPath -Raw -Encoding UTF8 | ConvertFrom-Json
$target = Join-Path $workspace ("client\.generated\" + $Product)
if ($OutputDirectory) {
    $target = [System.IO.Path]::GetFullPath($OutputDirectory, $workspace)
    if (-not $target.StartsWith($workspace + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $target)) {
        throw 'OutputDirectory must be a new directory under the workspace.'
    }
}

# compose-godot.ps1（Godot产品组合工具）
# 源模块只保留一份，本脚本按产品清单复制到临时工程，避免多个App长期复制公共源码。
$expectedTarget = [System.IO.Path]::GetFullPath((Join-Path $workspace ("client\.generated\" + $Product)))
if(Test-Path -LiteralPath $target){
    $resolvedTarget = (Resolve-Path -LiteralPath $target).ProviderPath
    if($resolvedTarget -ne $expectedTarget){ throw "Generated project path does not match the intended target: $resolvedTarget" }
    if((Get-Item -LiteralPath $target).Attributes -band [System.IO.FileAttributes]::ReparsePoint){ throw "Refusing to remove a redirected generated directory: $resolvedTarget" }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item (Join-Path $workspace "client\app_shell\*") $target -Recurse -Force
Copy-Item $productPath (Join-Path $target "product.json") -Force

$moduleRoot = Join-Path $target "modules"
New-Item -ItemType Directory -Force -Path $moduleRoot | Out-Null

foreach($module in $config.modules){
    $source = Join-Path $workspace ("client\" + $module)
    $destination = Join-Path $moduleRoot $module
    $destinationParent = Split-Path -Parent $destination
    if(-not(Test-Path $destinationParent)){ New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null }
    Copy-Item $source $destination -Recurse -Force
}

# 麻将使用独立四人大厅，避免象棋的双座位流程和界面进入麻将产品。
if($Product -eq "mahjong"){
    Copy-Item (Join-Path $workspace "client\games\mahjong\guiyang\mahjong_app.gd") (Join-Path $target "scripts\main.gd") -Force
    $coach = Join-Path $workspace '.tmp/mahjong-coach/native'
    $coachConfig = Join-Path $coach 'mahjong_coach.gdextension'
    if (Test-Path -LiteralPath $coachConfig -PathType Leaf) {
        $coachTarget = Join-Path $moduleRoot 'games/mahjong/guiyang/native'
        New-Item -Path $coachTarget -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $coachConfig -Destination $coachTarget
        $libraryEntries = [regex]::Matches([IO.File]::ReadAllText($coachConfig), '(?m)^(?:windows\.x86_64|android\.arm64)\s*=\s*"res://modules/games/mahjong/guiyang/native/([\w.]+)"\r?$')
        foreach ($entry in $libraryEntries) {
            $library = Join-Path $coach $entry.Groups[1].Value
            Copy-Item -LiteralPath $library -Destination $coachTarget
        }
    }
}
if($Product -eq "landlord"){
    Copy-Item (Join-Path $workspace "client\games\landlord\landlord_app.gd") (Join-Path $target "scripts\main.gd") -Force
}
if($Product -eq "guandan"){
    Copy-Item (Join-Path $workspace "client\games\guandan\guandan_app.gd") (Join-Path $target "scripts\main.gd") -Force
}

# 产品名和Android包名在生成工程中进行最小差异替换。
$projectFile = Join-Path $target "project.godot"
$projectText = Get-Content $projectFile -Raw -Encoding UTF8
$projectText = $projectText.Replace('config/name="XiaoBanDeng Product"', 'config/name="' + $config.display_name + '"')
if ($config.application_icon) {
    $projectText = $projectText.Replace('[application]', "[application]`nconfig/icon=`"$($config.application_icon)`"")
}
if ($config.application_version) {
    $projectText = $projectText.Replace('[application]', "[application]`nconfig/version=`"$($config.application_version)`"")
}
[System.IO.File]::WriteAllText($projectFile, $projectText, [System.Text.UTF8Encoding]::new($false))

$exportFile = Join-Path $target "export_presets.cfg"
$exportText = Get-Content $exportFile -Raw -Encoding UTF8
$exportText = $exportText.Replace('package/unique_name="com.freebooz.xiaobandeng.product"', 'package/unique_name="' + $config.android_package + '"')
$exportText = $exportText.Replace('package/name="小板凳"', 'package/name="' + $config.display_name + '"')
if ($config.application_version) {
    $exportText = $exportText -replace '(?m)^version/name="[^"]*"', ('version/name="' + $config.application_version + '"')
}
if ($config.windows_icon) {
    $exportText = $exportText.Replace('[preset.0.options]', "[preset.0.options]`napplication/icon=`"$($config.windows_icon)`"")
}
if ($config.android_adaptive_icon) {
    $exportText = $exportText.Replace('[preset.1.options]', "[preset.1.options]`nlauncher_icons/adaptive_foreground_432x432=`"$($config.android_adaptive_icon)`"")
}
if ($config.android_icon) {
    $exportText = $exportText.Replace('[preset.1.options]', "[preset.1.options]`nlauncher_icons/main_192x192=`"$($config.android_icon)`"")
}
if ($config.android_adaptive_background) {
    $exportText = $exportText.Replace('[preset.1.options]', "[preset.1.options]`nlauncher_icons/adaptive_background_432x432=`"$($config.android_adaptive_background)`"")
}
[System.IO.File]::WriteAllText($exportFile, $exportText, [System.Text.UTF8Encoding]::new($false))

Write-Host ("Generated Godot project: " + $target)
Write-Host ("Product: " + $config.display_name + " / GameId=" + $config.game_id + " / RuleSetId=" + $config.rule_set_id)
