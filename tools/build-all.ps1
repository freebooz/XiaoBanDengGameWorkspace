$ErrorActionPreference = "Stop"

# build-all.ps1（一期统一构建脚本）
# Go/Node/Godot工具是否可用由本机环境决定；脚本不会伪造构建成功。
$workspace = Split-Path -Parent $PSScriptRoot

Write-Host "1/3 Compose Godot product projects"
& (Join-Path $PSScriptRoot "compose-godot.ps1") chinese_chess
& (Join-Path $PSScriptRoot "compose-godot.ps1") mahjong

Write-Host "2/3 Build Docker services"
Push-Location $workspace
try {
    docker compose build server admin-web
} finally {
    Pop-Location
}

Write-Host "3/3 Validate Godot projects"
$godot = Get-Command godot -ErrorAction SilentlyContinue
if($null -eq $godot){
    Write-Warning "Godot command not found; generated projects are ready, Windows/Android export skipped."
    exit 0
}

foreach($product in @("chinese_chess","mahjong")){
    $projectPath = Join-Path $workspace ("client\.generated\" + $product)
    & godot --headless --path $projectPath --editor --quit
    if($LASTEXITCODE -ne 0){ throw "Godot validation failed: $product" }
}