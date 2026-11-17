[CmdletBinding()]
param([string] $Godot = 'godot')

$ErrorActionPreference = "Stop"

# build-all.ps1（一期统一构建脚本）
# Go/Node/Godot工具是否可用由本机环境决定；脚本不会伪造构建成功。
$workspace = Split-Path -Parent $PSScriptRoot
$godotCommand = Get-Command $Godot -ErrorAction Stop
$games = [ordered]@{
    chinese_chess = 'res://modules/games/chinese_chess/chinese_chess_3d_screen.gd'
    mahjong = 'res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd'
    landlord = 'res://modules/games/landlord/landlord_3d_screen.gd'
    guandan = 'res://modules/games/guandan/guandan_3d_screen.gd'
}

Write-Host "1/3 Compose Godot product projects"
foreach ($product in $games.Keys) {
    & (Join-Path $PSScriptRoot "compose-godot.ps1") -Product $product
}

Write-Host "2/3 Build Docker services"
Push-Location $workspace
try {
    docker compose build server admin-web
    if ($LASTEXITCODE -ne 0) { throw "Docker service build failed (exit $LASTEXITCODE)." }
    docker build --target build ./admin-web
    if ($LASTEXITCODE -ne 0) { throw "Admin production bundle failed (exit $LASTEXITCODE)." }
} finally {
    Pop-Location
}

Write-Host "3/3 Validate Godot projects"
foreach ($product in $games.Keys) {
    $projectPath = Join-Path $workspace ("client/.generated/" + $product)
    & $godotCommand --headless --path $projectPath --editor --import --quit --disable-vsync --max-fps 0
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $product" }
    foreach ($entry in @('res://scripts/main.gd', $games[$product])) {
        & $godotCommand --headless --path $projectPath --check-only --script $entry --disable-vsync --max-fps 0
        if ($LASTEXITCODE -ne 0) { throw "Godot validation failed for ${product}: $entry" }
    }
}
