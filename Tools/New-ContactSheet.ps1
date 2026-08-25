<#
.SYNOPSIS
    Tiles several generated images into one contact sheet for review.

.DESCRIPTION
    Reviewing a batch one file at a time is slow and, when the reviewer is an
    assistant reading images into context, expensive. This tiles them into a
    single grid with an index number drawn on each cell, so a batch can be judged
    in one look and referred to by number.

    Cells are letterboxed, never stretched: aspect ratio is preserved so a
    silhouette can be judged honestly.

.EXAMPLE
    .\Tools\New-ContactSheet.ps1 -Path $env:TEMP/RimRisingArt/RR_Razor_z_*.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string[]] $Path,
    [string] $OutFile,
    [int]    $Cell    = 384,
    [int]    $Columns = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$files = @(Get-ChildItem -Path $Path -File | Sort-Object Name)
if ($files.Count -eq 0) { throw "No images matched: $($Path -join ', ')" }

if ($Columns -le 0) { $Columns = [math]::Ceiling([math]::Sqrt($files.Count)) }
$rows = [math]::Ceiling($files.Count / $Columns)

if (-not $OutFile) {
    $dir = Split-Path -Parent $files[0].FullName
    $OutFile = Join-Path $dir 'contactsheet.png'
}

$w = $Columns * $Cell
$h = $rows * $Cell
$sheet = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::FromArgb(255, 24, 24, 28))

$font  = New-Object System.Drawing.Font('Consolas', 20, [System.Drawing.FontStyle]::Bold)
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$black = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 0, 0, 0))
$grid  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 70, 70, 78))

for ($i = 0; $i -lt $files.Count; $i++) {
    $col = $i % $Columns
    $row = [math]::Floor($i / $Columns)
    $cx  = $col * $Cell
    $cy  = $row * $Cell

    $img = [System.Drawing.Image]::FromFile($files[$i].FullName)
    try {
        # Letterbox: scale to fit, never distort.
        $scale = [math]::Min($Cell / $img.Width, $Cell / $img.Height)
        $dw = [int]($img.Width  * $scale)
        $dh = [int]($img.Height * $scale)
        $dx = $cx + [int](($Cell - $dw) / 2)
        $dy = $cy + [int](($Cell - $dh) / 2)
        $g.DrawImage($img, $dx, $dy, $dw, $dh)
    } finally { $img.Dispose() }

    $g.DrawRectangle($grid, $cx, $cy, $Cell - 1, $Cell - 1)
    $label = ($i + 1).ToString()
    $g.FillRectangle($black, $cx + 4, $cy + 4, 34, 32)
    $g.DrawString($label, $font, $white, ($cx + 9), ($cy + 6))
}

$g.Dispose()
# Bitmap.Save does NOT append an extension - the path must already carry it.
if ([System.IO.Path]::GetExtension($OutFile) -eq '') { $OutFile += '.png' }
$sheet.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

Write-Host ("  sheet      : {0} ({1} images, {2}x{3})" -f $OutFile, $files.Count, $Columns, $rows) -ForegroundColor Green
$OutFile
