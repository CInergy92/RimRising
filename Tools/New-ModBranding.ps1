<#
.SYNOPSIS
    Builds the Workshop preview image and the mod icon.

.DESCRIPTION
    Two deliverables, two completely different jobs, which is why they are not
    made the same way.

    THE PREVIEW is a picture. It is 640x360 in a Workshop grid full of other
    mods' pictures, so it has to read as a scene in about a second. The
    background is generated art (Z-Image-Turbo, via New-GeneratedArt's pipeline),
    and this script only composites the wordmark onto it.

    THE ICON is 64x64. Nothing generative survives that size - a figure becomes
    four grey pixels - so it is drawn procedurally as a MARK: a stepped pyramid,
    gold at the apex falling to red at the base, which is the mod's whole subject
    in one shape. Same reasoning as the xenotype glyphs in New-XenotypeIcons.ps1.

    THE WORDMARK SAYS RIMRISING, NOT RED RISING. The placeholder it replaces said
    "RED RISING", which is the novels' title rather than this mod's name. Fronting
    someone else's title on a Workshop listing reads as though the mod were
    official, so the mod's own name leads and the source is credited underneath.

.PARAMETER Background
    The generated background to composite. Defaults to the chosen candidate.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [string] $Background = 'Art/Preview/RR_PreviewBg_00007_.png',
    [switch] $IconOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
$sep = [string][char]92

function Join-Rel { param([string] $Rel) return (Join-Path $ModRoot ($Rel -replace '/', $sep)) }

# Warm gold for the wordmark, the same family as the caste dyes rather than a
# picked yellow. Deep red ground for the icon.
$Gold     = [System.Drawing.Color]::FromArgb(255, 232, 200, 122)
$GoldDim  = [System.Drawing.Color]::FromArgb(255, 176, 142,  74)
$Crimson  = [System.Drawing.Color]::FromArgb(255, 124,  30,  30)
$CrimsonD = [System.Drawing.Color]::FromArgb(255,  74,  18,  18)
$Ink      = [System.Drawing.Color]::FromArgb(255,  26,  22,  20)

function Pick-Font {
    param([string[]] $Names, [single] $Size, [System.Drawing.FontStyle] $Style)
    $have = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
    foreach ($n in $Names) {
        if ($have -contains $n) { return (New-Object System.Drawing.Font($n, $Size, $Style)) }
    }
    return (New-Object System.Drawing.Font('Arial', $Size, $Style))
}

# ------------------------------------------------------------------ preview ---
if (-not $IconOnly) {
    $bgPath = Join-Rel $Background
    if (-not (Test-Path $bgPath)) { throw "Background not found: $bgPath" }

    # MemoryStream, not FromFile: FromFile holds the file open, and this script
    # may be re-run over its own output directory. See Convert-TintableIcon.ps1.
    $bytes  = [System.IO.File]::ReadAllBytes($bgPath)
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    $src    = [System.Drawing.Bitmap]::FromStream($stream)

    $W = 640; $H = 360
    $out = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($out)
        try {
            $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint  = [System.Drawing.Text.TextRenderingHint]::AntiAlias
            $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $W, $H)))

            # LEFT-BIASED scrim, not a band across the top. A full-width vertical
            # gradient darkened the sun and the figure's shoulders, which are the
            # two things the picture is actually for. This one only shades the
            # column the text sits in and is gone before it reaches the armour.
            $r = New-Object System.Drawing.Rectangle(0, 0, [int]($W * 0.58), $H)
            $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    $r,
                    [System.Drawing.Color]::FromArgb(170, 12, 8, 8),
                    [System.Drawing.Color]::FromArgb(0, 12, 8, 8),
                    [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $g.FillRectangle($lg, $r) } finally { $lg.Dispose() }

            # SIZED TO THE GAP, not picked. At 54pt the wordmark ran into the
            # figure's head - the clear sky left of the armour is about 250px wide
            # at this crop, so the title has to fit inside that.
            $title = Pick-Font @('Impact','Arial Black','Segoe UI Black') 37 ([System.Drawing.FontStyle]::Regular)
            $sub   = Pick-Font @('Bahnschrift','Segoe UI Semibold','Arial') 11 ([System.Drawing.FontStyle]::Bold)
            try {
                $x = 26; $y = 30

                # Drawn three times: a dark offset shadow so the letters hold
                # against a bright sky, then the fill, then a dim underline rule.
                $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 8, 5, 5))
                $fill   = New-Object System.Drawing.SolidBrush($Gold)
                try {
                    $g.DrawString('RIMRISING', $title, $shadow, [single]($x + 3), [single]($y + 3))
                    $g.DrawString('RIMRISING', $title, $fill,   [single]$x,        [single]$y)
                } finally { $shadow.Dispose(); $fill.Dispose() }

                $tw = $g.MeasureString('RIMRISING', $title).Width
                $ruleY = $y + 46
                $pen = New-Object System.Drawing.Pen($GoldDim, 2)
                try { $g.DrawLine($pen, [single]$x, [single]$ruleY, [single]($x + $tw - 12), [single]$ruleY) }
                finally { $pen.Dispose() }

                $sh2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190, 8, 5, 5))
                $f2  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 226, 214, 198))
                try {
                    $line = 'A RED RISING TOTAL CONVERSION'
                    $g.DrawString($line, $sub, $sh2, [single]($x + 2), [single]($ruleY + 8))
                    $g.DrawString($line, $sub, $f2,  [single]$x,        [single]($ruleY + 6))
                } finally { $sh2.Dispose(); $f2.Dispose() }
            } finally { $title.Dispose(); $sub.Dispose() }
        } finally { $g.Dispose() }

        $dest = Join-Rel 'About/Preview.png'
        $out.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "  + About/Preview.png  ($W x $H)" -ForegroundColor Green
    } finally { $out.Dispose(); $src.Dispose(); $stream.Dispose() }
}

# --------------------------------------------------------------------- icon ---
# A stepped pyramid: four rungs, gold at the apex falling to red at the base.
# The mod's subject in one shape, and the only kind of thing that survives 64px.
function Write-Icon {
    param([string] $Rel, [int] $Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            # Ground: a dark red field, so the mark reads on both the light and
            # dark mod-list rows.
            $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)),
                    $Crimson, $CrimsonD,
                    [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            try { $g.FillRectangle($bg, 0, 0, $Size, $Size) } finally { $bg.Dispose() }

            # Four rungs. Width grows downward, colour falls from gold to red -
            # the hierarchy, drawn as what it is.
            $rungs = @(
                @{ W = 0.20; Col = [System.Drawing.Color]::FromArgb(255, 232, 200, 122) },
                @{ W = 0.38; Col = [System.Drawing.Color]::FromArgb(255, 198, 166, 104) },
                @{ W = 0.56; Col = [System.Drawing.Color]::FromArgb(255, 176, 132,  92) },
                @{ W = 0.74; Col = [System.Drawing.Color]::FromArgb(255, 196,  84,  74) }
            )
            $top    = $Size * 0.16
            $gap    = $Size * 0.045
            $rungH  = ($Size * 0.66 - ($gap * 3)) / 4.0
            $mid    = $Size / 2.0

            for ($i = 0; $i -lt $rungs.Count; $i++) {
                $w = $Size * $rungs[$i].W
                $y = $top + ($i * ($rungH + $gap))
                $x = $mid - ($w / 2.0)

                # Outline first and wider, so each rung keeps its edge against the
                # one below it - the same two-pass idiom the sprites use.
                $ob = New-Object System.Drawing.SolidBrush($Ink)
                try {
                    $g.FillRectangle($ob, [single]($x - $Size * 0.022), [single]($y - $Size * 0.018),
                                          [single]($w + $Size * 0.044), [single]($rungH + $Size * 0.036))
                } finally { $ob.Dispose() }

                $fb = New-Object System.Drawing.SolidBrush($rungs[$i].Col)
                try { $g.FillRectangle($fb, [single]$x, [single]$y, [single]$w, [single]$rungH) }
                finally { $fb.Dispose() }
            }
        } finally { $g.Dispose() }

        $dest = Join-Rel $Rel
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host ("  + {0}  ({1} x {1})" -f $Rel, $Size) -ForegroundColor Green
    } finally { $bmp.Dispose() }
}

# Both copies: About/ModIcon.png is the convention, Textures/UI is what
# About.xml's modIconPath actually points at.
Write-Icon 'About/ModIcon.png' 64
Write-Icon 'Textures/UI/RimRisingModIcon.png' 64
