$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$workspace = Split-Path -Parent $PSScriptRoot
$output = Join-Path $workspace 'client\game_framework\card3d\assets\cards'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$ranks = @('3','4','5','6','7','8','9','10','J','Q','K','A','2')
$blueInk = [System.Drawing.Color]::FromArgb(24,84,177)
$suits = @(
    @{Name='spade'; Symbol='♠'; Color=$blueInk},
    @{Name='heart'; Symbol='♥'; Color=[System.Drawing.Color]::FromArgb(185,31,48)},
    @{Name='club'; Symbol='♣'; Color=$blueInk},
    @{Name='diamond'; Symbol='♦'; Color=[System.Drawing.Color]::FromArgb(185,31,48)}
)
$width=378; $height=528
$rankFont = [System.Drawing.Font]::new('Arial', 50, [System.Drawing.FontStyle]::Bold)
$suitFont = [System.Drawing.Font]::new('Segoe UI Symbol', 135, [System.Drawing.FontStyle]::Regular)
$smallFont = [System.Drawing.Font]::new('Segoe UI Symbol', 45, [System.Drawing.FontStyle]::Regular)
$jokerFont = [System.Drawing.Font]::new('Arial', 48, [System.Drawing.FontStyle]::Bold)
try {
    foreach($suit in $suits) {
        for($index=0;$index -lt 13;$index++) {
            $bmp = [System.Drawing.Bitmap]::new($width,$height)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $brush = [System.Drawing.SolidBrush]::new($suit.Color)
            $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(216,198,159),5)
            try {
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
                $g.Clear([System.Drawing.Color]::FromArgb(255,252,245))
                $g.DrawRectangle($pen,12,12,$width-24,$height-24)
                $g.DrawString($ranks[$index],$rankFont,$brush,18,22)
                $g.DrawString($suit.Symbol,$smallFont,$brush,21,94)
                $g.DrawString($suit.Symbol,$suitFont,$brush,107,184)
                $g.TranslateTransform($width,$height)
                $g.RotateTransform(180)
                $g.DrawString($ranks[$index],$rankFont,$brush,18,22)
                $g.DrawString($suit.Symbol,$smallFont,$brush,21,94)
                $path = Join-Path $output ('{0}_{1}.png' -f $suit.Name,$ranks[$index])
                $bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $brush.Dispose();$pen.Dispose();$g.Dispose();$bmp.Dispose() }
        }
    }
    foreach($kind in @('small_joker','big_joker','back')) {
        $bmp = [System.Drawing.Bitmap]::new($width,$height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            if($kind -eq 'back') {
                $g.Clear([System.Drawing.Color]::FromArgb(19,57,90))
                $gold=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(215,171,91),6)
                try {
                    $g.DrawRectangle($gold,18,18,$width-36,$height-36)
                    $g.DrawRectangle($gold,32,32,$width-64,$height-64)
                    $detail=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(169,135,80),3)
                    try {
                        $g.DrawLine($detail,189,100,302,264)
                        $g.DrawLine($detail,302,264,189,428)
                        $g.DrawLine($detail,189,428,76,264)
                        $g.DrawLine($detail,76,264,189,100)
                        $g.DrawEllipse($gold,121,196,136,136)
                    } finally { $detail.Dispose() }
                } finally { $gold.Dispose() }
            } else {
                $g.Clear([System.Drawing.Color]::FromArgb(255,252,245))
                $color = if($kind -eq 'big_joker') {[System.Drawing.Color]::FromArgb(183,33,45)} else {$blueInk}
                $brush = [System.Drawing.SolidBrush]::new($color)
                try {
                    $g.DrawString('JOKER',$jokerFont,$brush,27,39)
                    $g.DrawString('★',$suitFont,$brush,100,200)
                    $g.DrawString($(if($kind -eq 'big_joker') {'BIG'} else {'SMALL'}),$jokerFont,$brush,100,414)
                } finally { $brush.Dispose() }
            }
            $bmp.Save((Join-Path $output ($kind+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $g.Dispose();$bmp.Dispose() }
    }
} finally { $rankFont.Dispose();$suitFont.Dispose();$smallFont.Dispose();$jokerFont.Dispose() }
Write-Host ('Generated 55 card textures in '+$output)
