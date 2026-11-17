$ErrorActionPreference = "Stop"

# Render Chinese Chess mobile UI SVG source files into transparent PNG runtime assets.
# Usage:
# powershell -ExecutionPolicy Bypass -File tools/render-chess-ui-assets.ps1 E:\work\2026\XiaoBanDengGameWorkspace
$workspace = $args[0]
if ([string]::IsNullOrWhiteSpace($workspace)) {
    throw "Workspace root argument is required."
}

$sourceRoot = Join-Path $workspace "client\games\chinese_chess\assets\ui\mobile"
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "UI source directory was not found: $sourceRoot"
}
if (-not (Test-Path -LiteralPath $chrome)) {
    throw "Chrome was not found: $chrome"
}

$tempProfile = Join-Path $workspace ".tmp\chrome-ui"
if (Test-Path -LiteralPath $tempProfile) {
    Remove-Item -LiteralPath $tempProfile -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $tempProfile | Out-Null

try {
    Get-ChildItem -LiteralPath $sourceRoot -Filter "*.svg" -File | ForEach-Object {
        $svg = $_
        $text = Get-Content -LiteralPath $svg.FullName -Raw -Encoding UTF8
        $widthMatch = [regex]::Match($text, 'width="([0-9]+)"')
        $heightMatch = [regex]::Match($text, 'height="([0-9]+)"')
        if (-not $widthMatch.Success -or -not $heightMatch.Success) {
            throw "SVG width/height missing: $($svg.Name)"
        }

        $width = [int]$widthMatch.Groups[1].Value
        $height = [int]$heightMatch.Groups[1].Value
        if ($width -le 0 -or $height -le 0) {
            throw "Invalid SVG dimensions: $($svg.Name)"
        }

        $output = [System.IO.Path]::ChangeExtension($svg.FullName, ".png")
        $uriPath = $svg.FullName.Replace("\", "/")
        $uri = "file:///" + $uriPath
        $chromeArgs = @(
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--default-background-color=00000000",
            "--force-device-scale-factor=1",
            "--window-size=$width,$height",
            "--user-data-dir=$tempProfile",
            "--screenshot=$output",
            $uri
        )

        $process = Start-Process -FilePath $chrome -ArgumentList $chromeArgs -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
            throw "PNG render failed: $($svg.Name)"
        }
        Write-Host ("Rendered UI asset: " + [System.IO.Path]::GetFileName($output))
    }
}
finally {
    if (Test-Path -LiteralPath $tempProfile) {
        Remove-Item -LiteralPath $tempProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}
