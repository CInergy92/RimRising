<#
.SYNOPSIS
    Turns a generated 1024px image on a flat background into a game-ready sprite.

.DESCRIPTION
    Generated art is opaque, oversized and sitting on a background. RimWorld needs
    a trimmed, transparent, correctly-sized PNG. This does the three steps:

      1. Key the background out by FLOOD FILLING inward from the border.
      2. Trim to the content bounding box, with an optional margin.
      3. Resize to the target square, letterboxed so nothing is distorted.

    Why flood fill rather than a luminance threshold: RimWorld's art idiom uses a
    thick DARK WARM-GREY outline, which a global "dark means background" test
    eats, leaving the sprite with a chewed, semi-transparent edge. The background
    is the region connected to the border, so that is what gets removed - interior
    darks are untouched no matter how dark they are.

.PARAMETER Tolerance
    How far a pixel may differ from the sampled background colour and still count
    as background, 0-255 per channel. Raise it for a vignetted or noisy
    background, lower it if the fill starts eating into the sprite.

.PARAMETER Size
    Output edge length. Per CLAUDE.md: weapons 256, items and gene icons 128,
    xenotype icons 64.

.EXAMPLE
    .\Tools\Convert-GeneratedSprite.ps1 -Path gen.png -OutFile RR_Razor.png -Size 256
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,
    [string] $OutFile,
    # Square shorthand. -OutWidth/-OutHeight override it for non-square targets
    # such as vehicle bodies, whose north/south sprites are portrait and east
    # landscape.
    [int]    $Size      = 256,
    [int]    $OutWidth  = 0,
    [int]    $OutHeight = 0,
    [int]    $Tolerance = 42,
    [int]    $Margin    = 4,
    [switch] $NoTrim
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if ($OutWidth  -le 0) { $OutWidth  = $Size }
if ($OutHeight -le 0) { $OutHeight = $Size }

$src = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Path).Path)
$w = $src.Width; $h = $src.Height

# Work on a 32bpp copy so LockBits layout is predictable.
$bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose(); $src.Dispose()

$rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$bytes = New-Object byte[] ($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

# Sample the four corners and take the median-ish as the background colour, so a
# stray bright corner pixel does not define the key.
# NOTE: a pipeline over @(@(0,0), @(1,0)) UNROLLS the inner arrays into a flat
# list of ints, so the corners have to be walked with an explicit index.
$cornerX = @(0, ($w - 1), 0, ($w - 1))
$cornerY = @(0, 0, ($h - 1), ($h - 1))
$sumR = 0.0; $sumG = 0.0; $sumB = 0.0
for ($c = 0; $c -lt 4; $c++) {
    $o = $cornerY[$c] * $stride + $cornerX[$c] * 4
    $sumB += $bytes[$o]; $sumG += $bytes[$o + 1]; $sumR += $bytes[$o + 2]
}
$bgB = $sumB / 4; $bgG = $sumG / 4; $bgR = $sumR / 4
Write-Host ("  background : rgb({0:N0},{1:N0},{2:N0}) tolerance {3}" -f $bgR, $bgG, $bgB, $Tolerance) -ForegroundColor DarkGray

# Iterative flood fill from every border pixel. A stack-based scan rather than
# recursion - a 1024x1024 fill would blow the call stack.
$visited = New-Object 'bool[]' ($w * $h)
$stack = New-Object System.Collections.Generic.Stack[int]
for ($x = 0; $x -lt $w; $x++) { $stack.Push($x); $stack.Push(($h - 1) * $w + $x) }
for ($y = 0; $y -lt $h; $y++) { $stack.Push($y * $w); $stack.Push($y * $w + $w - 1) }

$cleared = 0
while ($stack.Count -gt 0) {
    $i = $stack.Pop()
    if ($visited[$i]) { continue }
    $visited[$i] = $true

    $px = $i % $w
    $py = [math]::Floor($i / $w)
    $o = $py * $stride + $px * 4
    if ([math]::Abs($bytes[$o]     - $bgB) -gt $Tolerance) { continue }
    if ([math]::Abs($bytes[$o + 1] - $bgG) -gt $Tolerance) { continue }
    if ([math]::Abs($bytes[$o + 2] - $bgR) -gt $Tolerance) { continue }

    $bytes[$o + 3] = 0
    $cleared++

    if ($px -gt 0)      { $stack.Push($i - 1) }
    if ($px -lt $w - 1) { $stack.Push($i + 1) }
    if ($py -gt 0)      { $stack.Push($i - $w) }
    if ($py -lt $h - 1) { $stack.Push($i + $w) }
}

[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$bmp.UnlockBits($data)
Write-Host ("  keyed out  : {0:N0} px ({1:P1} of frame)" -f $cleared, ($cleared / ($w * $h))) -ForegroundColor DarkGray

# Content bounding box from the alpha we just wrote.
$minX = $w; $minY = $h; $maxX = -1; $maxY = -1
if (-not $NoTrim) {
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            if ($bytes[$row + $x * 4 + 3] -gt 8) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
}
if ($NoTrim) {
    # Not a failure: the scan above was skipped on purpose, so maxX is still -1.
    # Falling into the branch below would cry wolf on every vehicle sprite.
    $minX = 0; $minY = 0; $maxX = $w - 1; $maxY = $h - 1
}
elseif ($maxX -lt 0) {
    Write-Warning 'Everything was keyed out - the whole image matched the background. Lower -Tolerance.'
    $minX = 0; $minY = 0; $maxX = $w - 1; $maxY = $h - 1
}

$cw = $maxX - $minX + 1
$ch = $maxY - $minY + 1
Write-Host ("  content    : {0}x{1} at ({2},{3})" -f $cw, $ch, $minX, $minY) -ForegroundColor DarkGray

# Letterbox into the target square. Scale from the LONGER edge so the sprite
# keeps its aspect ratio - a stretched weapon reads instantly as wrong.
$availW = $OutWidth  - 2 * $Margin
$availH = $OutHeight - 2 * $Margin
$scale = [math]::Min($availW / $cw, $availH / $ch)
$dw = [math]::Max(1, [int]($cw * $scale))
$dh = [math]::Max(1, [int]($ch * $scale))

$out = New-Object System.Drawing.Bitmap($OutWidth, $OutHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$og = [System.Drawing.Graphics]::FromImage($out)
$og.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$og.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$og.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$destX = [int](($OutWidth  - $dw) / 2)
$destY = [int](($OutHeight - $dh) / 2)
$dest = New-Object System.Drawing.Rectangle($destX, $destY, $dw, $dh)
$srcR = New-Object System.Drawing.Rectangle($minX, $minY, $cw, $ch)
$og.DrawImage($bmp, $dest, $srcR, [System.Drawing.GraphicsUnit]::Pixel)
$og.Dispose(); $bmp.Dispose()

if (-not $OutFile) {
    $OutFile = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path) `
                         ([System.IO.Path]::GetFileNameWithoutExtension($Path) + "_${OutWidth}x${OutHeight}.png")
}
# Bitmap.Save does NOT append an extension - the path must already carry it.
if ([System.IO.Path]::GetExtension($OutFile) -eq '') { $OutFile += '.png' }
$out.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$out.Dispose()

Write-Host ("  wrote      : {0} ({1}x{2})" -f $OutFile, $OutWidth, $OutHeight) -ForegroundColor Green
$OutFile
