<#
.SYNOPSIS
    Draws the weapon, implant and resource sprites, replacing the labelled
    placeholder squares.

.DESCRIPTION
    Shares Tools/GlyphPrimitives.ps1 with New-XenotypeIcons.ps1 so the whole icon
    set reads as one hand.

    THESE ARE ORIGINAL DESIGNS. Nothing is traced from the Red Rising artwork or
    from RimWorld's own sprites. They are built from the same primitive vocabulary
    as the caste glyphs: rings, bars, tapers and plates.

    WHAT THIS IS AND IS NOT

    These are FILLED, SHADED VECTOR SHAPES - clean, readable and consistent, and a
    large improvement on a coloured square with a word on it. They are not pixel
    art. A weapon sprite is small on screen and reads mostly as silhouette plus one
    highlight, which this can do honestly.

    Worn APPAREL is deliberately not attempted here. Those draw over the pawn body
    and have to match RimWorld's own silhouettes to look like anything but a smear;
    see the note at the bottom of this file.

    CONVENTION: RimWorld weapon sprites point EAST (right), hilt at the lower left,
    business end upper right. Verified against installed weapon textures.

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.
#>
[CmdletBinding()]
param([string] $ModRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot = Join-Path $ModRoot 'Textures'

# --------------------------------------------------------------- draw helpers

function Fill-Poly {
    param($g, [System.Drawing.Brush]$brush, [single]$S, [array]$pts)
    $arr = @()
    foreach ($p in $pts) {
        $arr += New-Object System.Drawing.PointF([single]($p[0] * $S), [single]($p[1] * $S))
    }
    $g.FillPolygon($brush, [System.Drawing.PointF[]]$arr)
}

function Fill-Rect {
    param($g, [System.Drawing.Brush]$brush, [single]$S, [single]$x, [single]$y, [single]$w, [single]$h)
    $g.FillRectangle($brush, $x * $S, $y * $S, $w * $S, $h * $S)
}

function Shade([System.Drawing.Color] $c, [double] $f) {
    $r = [Math]::Max(0, [Math]::Min(255, [int]($c.R * $f)))
    $g2 = [Math]::Max(0, [Math]::Min(255, [int]($c.G * $f)))
    $b = [Math]::Max(0, [Math]::Min(255, [int]($c.B * $f)))
    [System.Drawing.Color]::FromArgb($c.A, $r, $g2, $b)
}

<#
    Writes one sprite. The scriptblock receives $g (Graphics) and $S (pixel size),
    plus $base / $lit / $dark brushes and $edge pen already prepared, so a recipe is
    just shapes.
#>
function Write-Sprite {
    param(
        [string] $RelPath,
        [int]    $Size,
        [string] $HexColor,
        [scriptblock] $Draw
    )
    # .png MUST be appended. Bitmap.Save takes the format as a separate argument
    # and does NOT add an extension, so omitting it writes an extensionless file
    # beside the real one and reports success - which is exactly what happened.
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)

            $c     = ToColor $HexColor
            $base  = New-Object System.Drawing.SolidBrush($c)
            $lit   = New-Object System.Drawing.SolidBrush((Shade $c 1.35))
            $dark  = New-Object System.Drawing.SolidBrush((Shade $c 0.55))
            # A dark outline is what makes a small sprite read against any terrain.
            $edge  = New-Pen ([System.Drawing.Color]::FromArgb(235, 18, 18, 22)) ([single]($Size / 44))  # ~3px at 128, matching vanilla item sprites
            try {
                & $Draw $g $Size $base $lit $dark $edge
            } finally {
                $base.Dispose(); $lit.Dispose(); $dark.Dispose(); $edge.Dispose()
            }
        } finally { $g.Dispose() }
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }

    Write-Host ("  + {0}  ({1}x{1})" -f $RelPath, $Size) -ForegroundColor Green
}

# ------------------------------------------------------------------- the razor

# The signature weapon, so it gets the most care. A slender tapering blade with a
# slight curve, ribbed hilt at the lower left. The curve is what says "this can go
# limp and whip" without needing a second sprite.
Write-Sprite 'Things/Item/Equipment/WeaponMelee/RR_Razor' 128 '#D8DCE4' {
    param($g, $S, $base, $lit, $dark, $edge)

    $blade = @(@(0.28,0.74), @(0.46,0.60), @(0.66,0.42), @(0.86,0.20),
               @(0.90,0.26), @(0.72,0.50), @(0.52,0.68), @(0.34,0.80))
    Fill-Poly $g $base $S $blade
    Draw-Poly $g $edge $S $blade -Close

    # Edge highlight along the cutting side only.
    $hl = New-Pen ([System.Drawing.Color]::FromArgb(220, 255, 255, 255)) ([single]($S / 48))
    try { Draw-Poly $g $hl $S @(@(0.31,0.75), @(0.50,0.61), @(0.69,0.43), @(0.87,0.22)) }
    finally { $hl.Dispose() }

    # Hilt.
    $hilt = @(@(0.16,0.86), @(0.30,0.72), @(0.36,0.78), @(0.22,0.92))
    Fill-Poly $g $dark $S $hilt
    Draw-Poly $g $edge $S $hilt -Close
    Draw-Line $g $edge $S 0.21 0.83 0.27 0.89
    Draw-Line $g $edge $S 0.25 0.79 0.31 0.85
}

# ---------------------------------------------------------------- pulse weapons

Write-Sprite 'Things/Item/Equipment/WeaponRanged/RR_PulseFist' 128 '#C9A227' {
    param($g, $S, $base, $lit, $dark, $edge)

    # A gauntlet: knuckle plate, wrist cuff, emitter aperture at the front.
    $cuff = @(@(0.18,0.40), @(0.40,0.34), @(0.44,0.66), @(0.22,0.72))
    Fill-Poly $g $dark $S $cuff
    Draw-Poly $g $edge $S $cuff -Close

    $plate = @(@(0.40,0.32), @(0.72,0.36), @(0.74,0.64), @(0.44,0.68))
    Fill-Poly $g $base $S $plate
    Draw-Poly $g $edge $S $plate -Close

    Draw-Line $g $edge $S 0.52 0.34 0.54 0.66
    Draw-Line $g $edge $S 0.62 0.35 0.64 0.65

    Draw-Disc $g $lit  $S 0.80 0.50 0.11
    Draw-Ring $g $edge $S 0.80 0.50 0.11
    Draw-Disc $g $dark $S 0.80 0.50 0.045
}

Write-Sprite 'Things/Weapons/RR_PulseCannon' 128 '#B9932A' {
    param($g, $S, $base, $lit, $dark, $edge)

    $body = @(@(0.10,0.42), @(0.44,0.38), @(0.46,0.62), @(0.12,0.66))
    Fill-Poly $g $dark $S $body
    Draw-Poly $g $edge $S $body -Close

    $barrel = @(@(0.44,0.44), @(0.82,0.46), @(0.82,0.58), @(0.46,0.60))
    Fill-Poly $g $base $S $barrel
    Draw-Poly $g $edge $S $barrel -Close

    # Muzzle bell.
    $bell = @(@(0.80,0.38), @(0.93,0.44), @(0.93,0.60), @(0.80,0.66))
    Fill-Poly $g $lit $S $bell
    Draw-Poly $g $edge $S $bell -Close

    Draw-Line $g $edge $S 0.56 0.45 0.56 0.59
    Draw-Line $g $edge $S 0.66 0.455 0.66 0.585
}

# ------------------------------------------------------------------ projectiles

Write-Sprite 'Things/Projectile/RR_PulseWave' 64 '#F2D765' {
    param($g, $S, $base, $lit, $dark, $edge)
    Draw-Disc $g $base $S 0.5 0.5 0.30
    Draw-Disc $g $lit  $S 0.5 0.5 0.16
}

Write-Sprite 'Things/Projectile/RR_ParticleLance' 64 '#8FD8FF' {
    param($g, $S, $base, $lit, $dark, $edge)
    Fill-Poly $g $base $S @(@(0.14,0.44), @(0.86,0.48), @(0.86,0.52), @(0.14,0.56))
    Fill-Poly $g $lit  $S @(@(0.50,0.465), @(0.86,0.487), @(0.86,0.513), @(0.50,0.535))
}

Write-Sprite 'Things/Projectile/RR_Warhead' 64 '#C4553B' {
    param($g, $S, $base, $lit, $dark, $edge)
    $body = @(@(0.20,0.42), @(0.68,0.42), @(0.88,0.50), @(0.68,0.58), @(0.20,0.58))
    Fill-Poly $g $base $S $body
    Draw-Poly $g $edge $S $body -Close
    Fill-Poly $g $dark $S @(@(0.20,0.42), @(0.30,0.30), @(0.34,0.42))
    Fill-Poly $g $dark $S @(@(0.20,0.58), @(0.30,0.70), @(0.34,0.58))
}

# --------------------------------------------------------------------- implants

Write-Sprite 'Things/Item/Health/RR_CupidsKiss' 128 '#B8607F' {
    param($g, $S, $base, $lit, $dark, $edge)
    # A segmented spinal lattice: vertebral clasps down a central line.
    Draw-Line $g $edge $S 0.50 0.16 0.50 0.84
    for ($i = 0; $i -lt 5; $i++) {
        # Arithmetic computed into variables FIRST. Inside @(0.34, $y - 0.045) the
        # comma binds before the minus, so PowerShell evaluates (0.34,$y) - 0.045
        # and throws op_Subtraction on Object[]. Trap #1 in CLAUDE.md, hit again.
        $y  = 0.22 + ($i * 0.14)
        $yt = $y - 0.045
        $yb = $y + 0.045
        $seg = @(@(0.34,$yt), @(0.66,$yt), @(0.66,$yb), @(0.34,$yb))
        Fill-Poly $g $(if ($i % 2) { $dark } else { $base }) $S $seg
        Draw-Poly $g $edge $S $seg -Close
    }
    Draw-Disc $g $lit  $S 0.50 0.50 0.055
    Draw-Ring $g $edge $S 0.50 0.50 0.055
}

Write-Sprite 'Things/Item/Health/RR_SynapticLattice' 128 '#6FD3C4' {
    param($g, $S, $base, $lit, $dark, $edge)
    # A contact mesh: hub, spokes, and a ring of pads.
    Draw-Ring $g $edge $S 0.50 0.50 0.34
    Draw-Spokes $g $edge $S 0.50 0.50 0.12 0.34 8
    Draw-Disc $g $base $S 0.50 0.50 0.14
    Draw-Ring $g $edge $S 0.50 0.50 0.14
    for ($i = 0; $i -lt 8; $i++) {
        $a = [Math]::PI * 2 * $i / 8
        $x = 0.50 + [Math]::Cos($a) * 0.34
        $y = 0.50 + [Math]::Sin($a) * 0.34
        Draw-Disc $g $lit  $S $x $y 0.055
        Draw-Ring $g $edge $S $x $y 0.055
    }
}

Write-Sprite 'Things/Item/Health/RR_CarvingKit' 128 '#7FB4A8' {
    param($g, $S, $base, $lit, $dark, $edge)
    # A sealed tray of vials.
    $tray = @(@(0.14,0.30), @(0.86,0.30), @(0.86,0.74), @(0.14,0.74))
    Fill-Poly $g $dark $S $tray
    Draw-Poly $g $edge $S $tray -Close
    for ($i = 0; $i -lt 4; $i++) {
        $x  = 0.235 + ($i * 0.176)
        $xl = $x - 0.055
        $xr = $x + 0.055
        $v = @(@($xl,0.38), @($xr,0.38), @($xr,0.66), @($xl,0.66))
        Fill-Poly $g $base $S $v
        Draw-Poly $g $edge $S $v -Close
        Fill-Rect $g $lit $S $xl 0.38 0.11 0.07
    }
}

# -------------------------------------------------------------------- resources

# Graphic_StackCount resolves the path as a FOLDER, so three variants. Each is a
# different chunk arrangement rather than a different colour, which is what makes a
# growing stack read as a pile.
#
# Written as three explicit calls rather than a nested array. A single-element
# array of chunks UNROLLS in PowerShell, so the loop ended up iterating over points
# instead of chunks and indexing a Double. Trap #2 in CLAUDE.md.

function Write-Ionsteel {
    param([string] $Variant, [array] $Chunks)
    Write-Sprite ("Things/Item/Resource/RR_Ionsteel/RR_Ionsteel_" + $Variant) 128 '#8FA6C4' {
        param($g, $S, $base, $lit, $dark, $edge)
        foreach ($chunk in $Chunks) {
            Fill-Poly $g $base $S $chunk
            Draw-Poly $g $edge $S $chunk -Close
            # One lit facet per chunk, so it reads as metal rather than as a blob.
            Fill-Poly $g $lit  $S @($chunk[0], $chunk[1], $chunk[2])
            Draw-Poly $g $edge $S @($chunk[0], $chunk[1], $chunk[2]) -Close
        }
    }.GetNewClosure()
}

Write-Ionsteel 'a' @(
    ,@(@(0.22,0.62), @(0.40,0.34), @(0.62,0.40), @(0.52,0.70))
)
Write-Ionsteel 'b' @(
    @(@(0.18,0.58), @(0.36,0.32), @(0.56,0.42), @(0.44,0.68)),
    @(@(0.52,0.72), @(0.66,0.50), @(0.84,0.60), @(0.72,0.80))
)
Write-Ionsteel 'c' @(
    @(@(0.14,0.54), @(0.30,0.28), @(0.50,0.38), @(0.38,0.62)),
    @(@(0.46,0.68), @(0.60,0.44), @(0.78,0.54), @(0.66,0.76)),
    @(@(0.30,0.80), @(0.44,0.66), @(0.58,0.78), @(0.44,0.90))
)

Write-Host ''
Write-Host 'Weapons, implants and resources written.' -ForegroundColor Cyan
Write-Host 'Worn apparel is NOT generated here - it draws over the pawn body and' -ForegroundColor DarkGray
Write-Host 'needs to match RimWorld''s own silhouettes. See docs/PROGRESS.md.' -ForegroundColor DarkGray
