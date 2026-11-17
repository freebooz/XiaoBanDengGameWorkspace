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

function New-ScaledBitmap([int]$Size, [int]$ArtworkSize = 0, [Drawing.Bitmap]$Artwork = $source) {
    if ($ArtworkSize -le 0) { $ArtworkSize = $Size }
    $bitmap = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $offset = [int](($Size - $ArtworkSize) / 2)
        $graphics.DrawImage($Artwork, [Drawing.Rectangle]::new($offset, $offset, $ArtworkSize, $ArtworkSize),
            0, 0, $Artwork.Width, $Artwork.Height, [Drawing.GraphicsUnit]::Pixel)
    } finally { $graphics.Dispose() }
    return $bitmap
}

function New-AndroidArtwork([Drawing.Bitmap]$Artwork, [int]$TrimOffset) {
    $width = $Artwork.Width
    $height = $Artwork.Height
    $leftEdge = [int[]]::new($height)
    $rightEdge = [int[]]::new($height)
    # Trace the gold rim from both sides of each row without inspecting the artwork inside it.
    for ($y = 0; $y -lt $height; $y++) {
        foreach ($side in @(1, -1)) {
            $x = if ($side -eq 1) { 0 } else { $width - 1 }
            while ($x -ge 0 -and $x -lt $width) {
                $pixel = $Artwork.GetPixel($x, $y)
                if ($pixel.A -gt 0 -and $pixel.R -ge 112 -and $pixel.G -ge 58 -and $pixel.R + 16 -ge $pixel.B) { break }
                $x += $side
            }
            if ($x -lt 0 -or $x -ge $width) { throw "No golden rim in source row $y." }
            if ($side -eq 1) { $leftEdge[$y] = $x } else { $rightEdge[$y] = $x }
        }
    }

    $isolated = [Drawing.Bitmap]::new($width + 2 * $TrimOffset, $height + 2 * $TrimOffset, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [Drawing.Graphics]::FromImage($isolated)
        try {
            $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.DrawImageUnscaled($Artwork, $TrimOffset, $TrimOffset)
        } finally { $graphics.Dispose() }

        for ($y = 0; $y -lt $height; $y++) {
            $leftTrim = $leftEdge[$y]
            $rightTrim = $rightEdge[$y]
            for ($dy = -$TrimOffset; $dy -le $TrimOffset; $dy++) {
                $row = $y + $dy
                if ($row -lt 0 -or $row -ge $height) { continue }
                $dx = [Math]::Floor([Math]::Sqrt($TrimOffset * $TrimOffset - $dy * $dy))
                $leftTrim = [Math]::Min($leftTrim, $leftEdge[$row] - $dx)
                $rightTrim = [Math]::Max($rightTrim, $rightEdge[$row] + $dx)
            }
            foreach ($side in @(1, -1)) {
                $start = if ($side -eq 1) { 0 } else { $width - 1 }
                $edge = if ($side -eq 1) { $leftEdge[$y] } else { $rightEdge[$y] }
                $gold = $Artwork.GetPixel($edge, $y)
                for ($x = $start; $x -ne $edge; $x += $side) {
                    $pixel = $Artwork.GetPixel($x, $y)
                    $color = [Drawing.Color]::Transparent
                    if ($x -ge $leftTrim -and $x -le $rightTrim -and $pixel.R -gt 12) {
                        # Remove the black matte from partially covered gold pixels in the 2px fringe.
                        $alpha = [Math]::Min(255, [int][Math]::Round($pixel.A * $pixel.R / $gold.R))
                        $color = [Drawing.Color]::FromArgb($alpha, $gold.R, $gold.G, $gold.B)
                    }
                    $isolated.SetPixel($x + $TrimOffset, $y + $TrimOffset, $color)
                }
            }
        }
        return $isolated
    } catch {
        $isolated.Dispose()
        throw
    }
}

function Save-Png([Drawing.Bitmap]$Bitmap, [string]$Path) {
    $Bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
}

$androidArtwork = $null
try {
    $trimOffset = 2
    $androidArtwork = New-AndroidArtwork $source $trimOffset
    Save-Png $androidArtwork (Join-Path $previewPath 'android-transparent-source.png')
    $sizes = @(16, 24, 32, 48, 64, 128, 192, 256, 512, 1024)
    foreach ($size in $sizes) {
        $artwork = if ($size -eq 192) { $androidArtwork } else { $source }
        $bitmap = New-ScaledBitmap $size -Artwork $artwork
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

    $launcherSize = 432
    $foreground = New-ScaledBitmap $launcherSize -Artwork $androidArtwork
    try {
        # Godot exports this slot at every Android density. The candidate template uses it as a plain bitmap.
        Save-Png $foreground (Join-Path $assetDirectory 'xbd_mahjong_app_icon_adaptive.png')
        Save-Png $foreground (Join-Path $previewPath 'android-transparent-432.png')
    } finally { $foreground.Dispose() }

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
        android_source_trim_offset_px = $trimOffset
        android_transparent_source_px = $androidArtwork.Width
        android_launcher_bitmap_px = $launcherSize
        android_launcher_background_alpha = 0
        rgb_processing = 'Preserve original RGB inside the golden rim. Remove the black matte from the two-pixel exterior fringe.'
        native_desktop_install_verified = $false
        android_install_verified = $false
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $previewPath 'icon-export-manifest.json') -Encoding utf8
    Write-Output ('MAHJONG_BRAND_ICONS_OK PNG=' + $sizes.Count + ' ICO=' + $icoSizes.Count + ' adaptive=432 original=' + $source.Width)
} finally {
    if ($androidArtwork) { $androidArtwork.Dispose() }
    $source.Dispose()
}
