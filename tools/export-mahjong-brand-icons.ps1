param(
    [string]$SourceImage,
    [string]$PreviewDirectory = 'artifacts/mahjong-ui-review-20261115/branding'
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$assetDirectory = Join-Path $workspace 'client/games/mahjong/guiyang/assets/ui/series'
$originalPath = Join-Path $assetDirectory 'xbd_mahjong_app_icon_source.png'
$previewPath = [IO.Path]::GetFullPath($PreviewDirectory, $workspace)
if (-not $previewPath.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Icon previews must remain inside the workspace.'
}
New-Item -ItemType Directory -Force -Path $assetDirectory, $previewPath | Out-Null
if ($SourceImage) {
    if (-not (Test-Path -LiteralPath $SourceImage -PathType Leaf)) { throw 'Source image does not exist.' }
    Copy-Item -LiteralPath $SourceImage -Destination $originalPath -Force
}
if (-not (Test-Path -LiteralPath $originalPath)) { throw 'Pass the approved source image on the first run.' }

Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::FromFile($originalPath)
if ($source.Width -ne $source.Height) { $source.Dispose(); throw 'Approved Mahjong icon must be square.' }

function New-ScaledBitmap([int]$Size, [int]$ArtworkSize = 0, [bool]$Opaque = $false) {
    if ($ArtworkSize -le 0) { $ArtworkSize = $Size }
    $bitmap = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($(if ($Opaque) { [Drawing.Color]::Black } else { [Drawing.Color]::Transparent }))
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $offset = [int](($Size - $ArtworkSize) / 2)
        $graphics.DrawImage($source, [Drawing.Rectangle]::new($offset, $offset, $ArtworkSize, $ArtworkSize),
            0, 0, $source.Width, $source.Height, [Drawing.GraphicsUnit]::Pixel)
    } finally { $graphics.Dispose() }
    return $bitmap
}

function Save-Png([Drawing.Bitmap]$Bitmap, [string]$Path) {
    $Bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
}

function Save-MaskPreview([Drawing.Bitmap]$Foreground, [string]$Mask, [int]$VisibleDiameter) {
    $size = 432
    $inset = ($size - $VisibleDiameter) / 2
    $output = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($output)
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        if ($Mask -eq 'circle') {
            $path.AddEllipse($inset, $inset, $VisibleDiameter, $VisibleDiameter)
        } else {
            $arc = [int]($VisibleDiameter * 0.32)
            $far = $inset + $VisibleDiameter - $arc
            $path.AddArc($inset, $inset, $arc, $arc, 180, 90)
            $path.AddArc($far, $inset, $arc, $arc, 270, 90)
            $path.AddArc($far, $far, $arc, $arc, 0, 90)
            $path.AddArc($inset, $far, $arc, $arc, 90, 90)
            $path.CloseFigure()
        }
        $graphics.SetClip($path)
        $graphics.FillRectangle([Drawing.Brushes]::Black, 0, 0, $size, $size)
        $graphics.DrawImageUnscaled($Foreground, 0, 0)
        Save-Png $output (Join-Path $previewPath ('android-' + $Mask + '-' + $VisibleDiameter + '.png'))
    } finally { $path.Dispose(); $graphics.Dispose(); $output.Dispose() }
}

try {
    $sizes = @(16, 24, 32, 48, 64, 128, 192, 256, 512, 1024)
    foreach ($size in $sizes) {
        $bitmap = New-ScaledBitmap $size
        try {
            Save-Png $bitmap (Join-Path $assetDirectory ('xbd_mahjong_app_icon_' + $size + '.png'))
            if ($size -eq 1024) { Save-Png $bitmap (Join-Path $assetDirectory 'xbd_mahjong_app_icon.png') }
        } finally { $bitmap.Dispose() }
    }

    # PNG-compressed ICO frames preserve all alpha channels; Windows selects the closest DPI size.
    $icoSizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @($icoSizes | ForEach-Object { ,([IO.File]::ReadAllBytes((Join-Path $assetDirectory ('xbd_mahjong_app_icon_' + $_ + '.png')))) })
    $icoPath = Join-Path $assetDirectory 'xbd_mahjong_app_icon.ico'
    $stream = [IO.File]::Create($icoPath)
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$icoSizes.Count)
        $offset = 6 + $icoSizes.Count * 16
        for ($i = 0; $i -lt $icoSizes.Count; $i++) {
            $dimension = $(if ($icoSizes[$i] -eq 256) { 0 } else { $icoSizes[$i] })
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    } finally { $writer.Dispose(); $stream.Dispose() }

    # 108dp canvas at xxxhdpi; original art is centered at 64dp, with no color transform.
    # Inspect both the conservative 66dp circle and the usual 72dp launcher masks.
    $foreground = New-ScaledBitmap 432 256
    $background = [Drawing.Bitmap]::new(432, 432, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $backgroundGraphics = [Drawing.Graphics]::FromImage($background)
    try {
        $backgroundGraphics.Clear([Drawing.Color]::Black)
        Save-Png $foreground (Join-Path $assetDirectory 'xbd_mahjong_app_icon_adaptive.png')
        Save-Png $background (Join-Path $assetDirectory 'xbd_mahjong_app_icon_adaptive_background.png')
        Save-MaskPreview $foreground 'circle' 264
        Save-MaskPreview $foreground 'circle' 288
        Save-MaskPreview $foreground 'rounded-square' 288
    } finally { $foreground.Dispose(); $backgroundGraphics.Dispose(); $background.Dispose() }

    # Read back every ICO frame header and PNG dimensions instead of assuming export success.
    $icoBytes = [IO.File]::ReadAllBytes($icoPath)
    if ([BitConverter]::ToUInt16($icoBytes, 2) -ne 1 -or [BitConverter]::ToUInt16($icoBytes, 4) -ne $icoSizes.Count) {
        throw 'Invalid generated ICO directory.'
    }
    for ($i = 0; $i -lt $icoSizes.Count; $i++) {
        $entry = 6 + 16 * $i
        $frameSize = [BitConverter]::ToUInt32($icoBytes, $entry + 8)
        $frameOffset = [BitConverter]::ToUInt32($icoBytes, $entry + 12)
        if ($frameOffset + $frameSize -gt $icoBytes.Length) { throw 'ICO frame extends beyond the file.' }
        $frameStream = [IO.MemoryStream]::new($icoBytes, $frameOffset, $frameSize)
        $decoded = [Drawing.Image]::FromStream($frameStream)
        try {
            if ($decoded.Width -ne $icoSizes[$i] -or $decoded.Height -ne $icoSizes[$i]) { throw 'Incorrect ICO frame dimensions.' }
        } finally { $decoded.Dispose(); $frameStream.Dispose() }
    }
    # System.Drawing's legacy selector caps at 128; the 256px PNG entry was decoded above.
    $nativeIcon = [Drawing.Icon]::new($icoPath, 128, 128)
    try {
        if ($nativeIcon.Width -ne 128 -or $nativeIcon.Height -ne 128) { throw 'Windows icon decoder did not load the requested 128px frame.' }
    } finally { $nativeIcon.Dispose() }
    $manifest = [ordered]@{
        original_sha256 = (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash
        original_width = $source.Width
        original_height = $source.Height
        png_sizes = $sizes
        ico_sizes = $icoSizes
        windows_icon_decoder_128px_verified = $true
        adaptive_canvas_px = 432
        adaptive_artwork_px = 256
        rgb_processing = 'Proportional bicubic resize only; no tint, gamma compensation, sharpness or recoloring.'
        adaptive_background = '#000000 (same as original corners)'
        android_documentation = 'https://developer.android.com/develop/ui/compose/system/icon_design_adaptive'
        native_desktop_install_verified = $false
        android_install_verified = $false
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $previewPath 'icon-export-manifest.json') -Encoding utf8
    Write-Output ('MAHJONG_BRAND_ICONS_OK PNG=' + $sizes.Count + ' ICO=' + $icoSizes.Count + ' adaptive=432 original=' + $source.Width)
} finally { $source.Dispose() }
