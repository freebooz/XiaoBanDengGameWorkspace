param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("chinese_chess","mahjong")]
    [string]$Product
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$productPath = Join-Path $workspace ("products\" + $Product + "\product.json")
$config = Get-Content $productPath -Raw -Encoding UTF8 | ConvertFrom-Json
$target = Join-Path $workspace ("client\.generated\" + $Product)

# compose-godot.ps1（Godot产品组合工具）
# 源模块只保留一份，本脚本按产品清单复制到临时工程，避免多个App长期复制公共源码。
if(Test-Path $target){ Remove-Item $target -Recurse -Force }
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

# 产品名和Android包名在生成工程中进行最小差异替换。
$projectFile = Join-Path $target "project.godot"
$projectText = Get-Content $projectFile -Raw -Encoding UTF8
$projectText = $projectText.Replace('config/name="XiaoBanDeng Product"', 'config/name="' + $config.display_name + '"')
[System.IO.File]::WriteAllText($projectFile, $projectText, [System.Text.UTF8Encoding]::new($false))

$exportFile = Join-Path $target "export_presets.cfg"
$exportText = Get-Content $exportFile -Raw -Encoding UTF8
$exportText = $exportText.Replace('package/unique_name="com.freebooz.xiaobandeng.product"', 'package/unique_name="' + $config.android_package + '"')
$exportText = $exportText.Replace('package/name="小板凳"', 'package/name="' + $config.display_name + '"')
[System.IO.File]::WriteAllText($exportFile, $exportText, [System.Text.UTF8Encoding]::new($false))

Write-Host ("Generated Godot project: " + $target)
Write-Host ("Product: " + $config.display_name + " / GameId=" + $config.game_id + " / RuleSetId=" + $config.rule_set_id)