<#
.SYNOPSIS
    Draws UI icons and projectile sprites for RimRising's abilities.

.DESCRIPTION
    A third generator, with a boundary as sharp as the other two - see the icon
    ownership note in CLAUDE.md:

        New-XenotypeIcons.ps1  owns UI/Icons/Xenotypes and UI/Icons/Genes
        New-ItemIcons.ps1      owns the item/weapon silhouettes
        New-AbilityIcons.ps1   owns UI/Abilities and ability projectiles

    These are NOT run through the generative art pass. A gizmo icon is read at
    32 px in a crowded button strip, where a painted illustration turns to mush and
    a flat high-contrast glyph does not. They are drawn, not generated, and they
    write straight to Textures rather than to Art/Silhouettes.

.PARAMETER OutRoot
    Where to write. Defaults to the mod's Textures tree.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [string] $OutRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot = if ($OutRoot) { $OutRoot } else { Join-Path $ModRoot 'Textures' }

$Outline = [System.Drawing.Color]::FromArgb(255, 30, 27, 24)
$Steel   = [System.Drawing.Color]::FromArgb(255, 196, 202, 208)
$Brass   = [System.Drawing.Color]::FromArgb(255, 198, 160,  86)

function Save-Icon {
    param([string] $RelPath, [int] $Size, [scriptblock] $Draw)
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            & $Draw $g $Size
        } finally { $g.Dispose() }
        # Bitmap.Save does NOT append an extension.
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
    Write-Host ("  + {0}" -f $RelPath) -ForegroundColor Green
}

<# A tapering lash along a curve: wide at the grip, nothing at the tip. #>
function Draw-Lash {
    param($g, [int]$S, [array]$Pts, [single]$WBase, [System.Drawing.Color]$Color, [single]$OutlineScale = 0.09)
    $n = $Pts.Count
    $a = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $b = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt $n; $i++) {
        $ia = [Math]::Max(0, $i - 1)
        $ib = [Math]::Min(($n - 1), ($i + 1))
        $dx = ([double]$Pts[$ib][0] - [double]$Pts[$ia][0])
        $dy = ([double]$Pts[$ib][1] - [double]$Pts[$ia][1])
        $len = [Math]::Sqrt(($dx * $dx) + ($dy * $dy)); if ($len -lt 1e-9) { $len = 1e-9 }
        $nx = -$dy / $len; $ny = $dx / $len
        $t = 0.0; if ($n -gt 1) { $t = [double]$i / ($n - 1) }
        $hw = ([double]$WBase * (1.0 - $t) / 2.0) * $S
        $cx = [double]$Pts[$i][0] * $S
        $cy = [double]$Pts[$i][1] * $S
        $a.Add((New-Object System.Drawing.PointF([single]($cx + ($nx * $hw)), [single]($cy + ($ny * $hw)))))
        $b.Add((New-Object System.Drawing.PointF([single]($cx - ($nx * $hw)), [single]($cy - ($ny * $hw)))))
    }
    $b.Reverse()
    $poly = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $poly.AddRange($a); $poly.AddRange($b)
    $arr = [System.Drawing.PointF[]]$poly.ToArray()
    $pen = New-Object System.Drawing.Pen($Outline, [single]($S * $OutlineScale))
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    try { $g.DrawPolygon($pen, $arr) } finally { $pen.Dispose() }
    $br = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillPolygon($br, $arr) } finally { $br.Dispose() }
}

# --------------------------------------------------------- the whip-form gizmo
#
# An S-curved lash uncoiling from a short grip. Read at button size the curve is
# the whole message: it is the one shape in the mod that is not a straight line,
# so it cannot be confused with the razor's own rigid-blade icon.
Save-Icon 'UI/Abilities/RR_RazorWhip' 128 {
    param($g, $S)
    Draw-Lash $g $S @(
        @(0.16, 0.86), @(0.30, 0.66), @(0.52, 0.60), @(0.70, 0.44),
        @(0.66, 0.26), @(0.50, 0.20), @(0.36, 0.26)
    ) 0.20 $Steel
    # The grip, so it reads as a weapon rather than a length of rope.
    $pen = New-Object System.Drawing.Pen($Outline, [single]($S * 0.20))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    try { $g.DrawLine($pen, [single](0.10 * $S), [single](0.94 * $S), [single](0.21 * $S), [single](0.79 * $S)) } finally { $pen.Dispose() }
    $pen = New-Object System.Drawing.Pen($Brass, [single]($S * 0.13))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    try { $g.DrawLine($pen, [single](0.10 * $S), [single](0.94 * $S), [single](0.21 * $S), [single](0.79 * $S)) } finally { $pen.Dispose() }
}

# ------------------------------------------------------------- the lash itself
#
# The projectile. Projectiles are drawn small and in motion, so this is a bare
# tapering streak with no interior detail - anything finer is invisible at speed.
Save-Icon 'Things/Projectile/RR_RazorLash' 64 {
    param($g, $S)
    Draw-Lash $g $S @(
        @(0.10, 0.72), @(0.34, 0.60), @(0.60, 0.46), @(0.90, 0.30)
    ) 0.30 $Steel 0.07
}

Write-Host ''
Write-Host 'Ability icons drawn. These are flat glyphs on purpose: a gizmo is read at 32px.'
