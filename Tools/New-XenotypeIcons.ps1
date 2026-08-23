<#
.SYNOPSIS
    Draws original geometric glyph icons for every Color and sub-tier xenotype,
    plus the mod's own gene icons.

.DESCRIPTION
    Replaces the flat labelled placeholder squares with a proper icon set.

    THESE ARE ORIGINAL DESIGNS. The published Red Rising sigils are copyrighted
    artwork and are NOT reproduced here, in whole or in part. What is borrowed is
    only the general idiom - terse geometric marks in the manner of alchemical
    symbols - which is a style, not an asset. Every composition below was drawn
    from scratch out of a shared primitive vocabulary.

    THE SYSTEM

    Each Color gets one composition built from rings, bars, triangles, chevrons,
    crescents, spokes, arrows and dots, chosen to evoke the caste's function.

    Sub-tiers inherit their parent's glyph and add a modifier mark, so lineage is
    readable at a glance: a Lurcher is visibly a Gray, an Ascomanni visibly an
    Obsidian. That is genuinely useful in a 21-xenotype list.

    COLOR

    RimWorld tints xenotype icons with XenotypeDef.IconColor, which is
    Color(0.75, 0.75, 0.75) - a uniform grey multiply. Uniform multiplication
    scales every channel equally, so hue survives and only brightness drops.
    Glyphs are therefore drawn in bright caste hues that stay legible at 75%.
    Verified by decompiling RimWorld.XenotypeDef.

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.

.PARAMETER Force
    Overwrite icons that already exist. On by default for this script, since its
    whole purpose is replacing earlier placeholders.

.PARAMETER Only
    Draw just one xenotype, by defName. Useful when iterating on a single glyph.

.EXAMPLE
    .\Tools\New-XenotypeIcons.ps1
.EXAMPLE
    .\Tools\New-XenotypeIcons.ps1 -Only RR_Gold
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [switch] $NoForce,
    [string] $Only
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

$xenoDir = Join-Path $ModRoot 'Textures\UI\Icons\Xenotypes'
$geneDir = Join-Path $ModRoot 'Textures\UI\Icons\Genes'
foreach ($d in @($xenoDir, $geneDir)) {
    if (-not (Test-Path $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
}

# ----------------------------------------------------------------- primitives
#
# All primitives work on a normalised 0..1 canvas so a glyph recipe is independent
# of output resolution. $S is the pixel size, $g the Graphics, $pen the stroke.

function New-Pen {
    param([System.Drawing.Color] $Color, [single] $Width)
    $pen = New-Object System.Drawing.Pen($Color, $Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    return $pen
}

function Draw-Ring {
    param($g, $pen, [single]$S, [single]$cx, [single]$cy, [single]$r)
    $g.DrawEllipse($pen, ($cx - $r) * $S, ($cy - $r) * $S, $r * 2 * $S, $r * 2 * $S)
}

function Draw-Disc {
    param($g, [System.Drawing.Brush]$brush, [single]$S, [single]$cx, [single]$cy, [single]$r)
    $g.FillEllipse($brush, ($cx - $r) * $S, ($cy - $r) * $S, $r * 2 * $S, $r * 2 * $S)
}

function Draw-Line {
    param($g, $pen, [single]$S, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
    $g.DrawLine($pen, $x1 * $S, $y1 * $S, $x2 * $S, $y2 * $S)
}

function Draw-Arc {
    param($g, $pen, [single]$S, [single]$cx, [single]$cy, [single]$r, [single]$start, [single]$sweep)
    $g.DrawArc($pen, ($cx - $r) * $S, ($cy - $r) * $S, $r * 2 * $S, $r * 2 * $S, $start, $sweep)
}

function Draw-Poly {
    param($g, $pen, [single]$S, [array]$pts, [switch]$Close)
    $arr = @()
    foreach ($p in $pts) {
        $arr += New-Object System.Drawing.PointF([single]($p[0] * $S), [single]($p[1] * $S))
    }
    if ($Close) { $g.DrawPolygon($pen, [System.Drawing.PointF[]]$arr) }
    else        { $g.DrawLines($pen,   [System.Drawing.PointF[]]$arr) }
}

# Triangle centred on (cx,cy), circumradius r, pointing up or down.
function Draw-Triangle {
    param($g, $pen, [single]$S, [single]$cx, [single]$cy, [single]$r, [bool]$Up = $true)
    $dir = if ($Up) { -1 } else { 1 }
    $pts = @(
        @($cx,                        ($cy + $dir * $r)),
        @(($cx - $r * 0.866),         ($cy - $dir * $r * 0.5)),
        @(($cx + $r * 0.866),         ($cy - $dir * $r * 0.5))
    )
    Draw-Poly -g $g -pen $pen -S $S -pts $pts -Close
}

function Draw-Chevron {
    param($g, $pen, [single]$S, [single]$cx, [single]$cy, [single]$w, [single]$h, [bool]$Up = $true)
    $dir = if ($Up) { -1 } else { 1 }
    $pts = @(
        @(($cx - $w), $cy),
        @($cx, ($cy + $dir * $h)),
        @(($cx + $w), $cy)
    )
    Draw-Poly -g $g -pen $pen -S $S -pts $pts
}

# Arrow from (x1,y1) to (x2,y2) with a barbed head at the far end.
function Draw-Arrow {
    param($g, $pen, [single]$S, [single]$x1, [single]$y1, [single]$x2, [single]$y2, [single]$head = 0.09)
    Draw-Line -g $g -pen $pen -S $S -x1 $x1 -y1 $y1 -x2 $x2 -y2 $y2
    $ang = [Math]::Atan2($y2 - $y1, $x2 - $x1)
    foreach ($off in @(2.6, -2.6)) {
        $a = $ang + $off
        Draw-Line -g $g -pen $pen -S $S -x1 $x2 -y1 $y2 `
                  -x2 ([single]($x2 + [Math]::Cos($a) * $head)) `
                  -y2 ([single]($y2 + [Math]::Sin($a) * $head))
    }
}

# Spokes radiating between radius r1 and r2.
function Draw-Spokes {
    param($g, $pen, [single]$S, [single]$cx, [single]$cy, [single]$r1, [single]$r2,
          [int]$count, [single]$startDeg = -90, [single]$spanDeg = 360)
    for ($i = 0; $i -lt $count; $i++) {
        $deg = $startDeg + ($spanDeg / $count) * $i
        $a = $deg * [Math]::PI / 180
        Draw-Line -g $g -pen $pen -S $S `
            -x1 ([single]($cx + [Math]::Cos($a) * $r1)) -y1 ([single]($cy + [Math]::Sin($a) * $r1)) `
            -x2 ([single]($cx + [Math]::Cos($a) * $r2)) -y2 ([single]($cy + [Math]::Sin($a) * $r2))
    }
}

# Crescent: an arc pair, opening in the given direction.
function Draw-Crescent {
    param($g, $pen, [single]$S, [single]$cx, [single]$cy, [single]$r, [single]$openDeg = -90)
    Draw-Arc -g $g -pen $pen -S $S -cx $cx -cy $cy -r $r -start ($openDeg + 30) -sweep 300
}

# ------------------------------------------------------------------- palette

$palette = @{
    Gold     = '#E8C24A'; Bronzie = '#B08A46'; Silver = '#CBD2DA'; White = '#EFF2F6'
    Copper   = '#CE7C46'; Blue    = '#4FA6E8'; Yellow = '#E6D44F'; Green = '#5CC06B'
    Violet   = '#A97FD6'; Orange  = '#E38A38'; Gray   = '#9BA5AF'; Brown = '#9C7752'
    Obsidian = '#7E7A8C'; Pink    = '#E890B2'; Red    = '#D84C4C'
}

function ToColor([string] $hex) {
    [System.Drawing.ColorTranslator]::FromHtml($hex)
}

# ------------------------------------------------------------- glyph recipes
#
# Each recipe is a scriptblock receiving $g (Graphics), $pen, $brush and $S (size).
# Compositions are original; see the header note on copyright.

$glyphs = [ordered]@{

    # ---- highColors ----

    # Gold: a filled disc inside a ring, crowned with five rays over a full
    # baseline. Solid centre and a wide crown - the most emphatic mark in the set,
    # since it is the one a player looks for first.
    RR_Gold = @{ Color = $palette.Gold; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring   -g $g -pen $pen -S $S -cx 0.5 -cy 0.44 -r 0.21
        Draw-Disc   -g $g -brush $brush -S $S -cx 0.5 -cy 0.44 -r 0.10
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.44 -r1 0.25 -r2 0.40 -count 5 -startDeg -160 -spanDeg 140
        Draw-Line   -g $g -pen $pen -S $S -x1 0.20 -y1 0.82 -x2 0.80 -y2 0.82
    }}

    # Bronzie: the same frame, hollow and clipped. No filled centre, a bare three
    # rays, and a baseline broken in the middle - Gold's mark with the gilding
    # taken off it.
    RR_Bronzie = @{ Color = $palette.Bronzie; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring   -g $g -pen $pen -S $S -cx 0.5 -cy 0.44 -r 0.21
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.44 -r1 0.25 -r2 0.34 -count 3 -startDeg -140 -spanDeg 100
        Draw-Line   -g $g -pen $pen -S $S -x1 0.20 -y1 0.82 -x2 0.42 -y2 0.82
        Draw-Line   -g $g -pen $pen -S $S -x1 0.58 -y1 0.82 -x2 0.80 -y2 0.82
    }}

    # Silver: a diamond with two arrows climbing out of it.
    RR_Silver = @{ Color = $palette.Silver; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Poly  -g $g -pen $pen -S $S -pts @(@(0.5,0.44),@(0.68,0.64),@(0.5,0.84),@(0.32,0.64)) -Close
        Draw-Arrow -g $g -pen $pen -S $S -x1 0.42 -y1 0.44 -x2 0.28 -y2 0.20 -head 0.075
        Draw-Arrow -g $g -pen $pen -S $S -x1 0.58 -y1 0.44 -x2 0.72 -y2 0.20 -head 0.075
    }}

    # White: a vertical staff through a ring, crossed by the beam of a balance.
    RR_White = @{ Color = $palette.White; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Line -g $g -pen $pen -S $S -x1 0.5 -y1 0.12 -x2 0.5 -y2 0.88
        Draw-Ring -g $g -pen $pen -S $S -cx 0.5 -cy 0.62 -r 0.18
        Draw-Line -g $g -pen $pen -S $S -x1 0.24 -y1 0.30 -x2 0.76 -y2 0.30
        Draw-Line -g $g -pen $pen -S $S -x1 0.24 -y1 0.30 -x2 0.24 -y2 0.40
        Draw-Line -g $g -pen $pen -S $S -x1 0.76 -y1 0.30 -x2 0.76 -y2 0.40
    }}

    # Copper: a filing square struck through corner to corner.
    RR_Copper = @{ Color = $palette.Copper; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Poly -g $g -pen $pen -S $S -pts @(@(0.26,0.26),@(0.74,0.26),@(0.74,0.74),@(0.26,0.74)) -Close
        Draw-Line -g $g -pen $pen -S $S -x1 0.26 -y1 0.26 -x2 0.74 -y2 0.74
        Draw-Line -g $g -pen $pen -S $S -x1 0.74 -y1 0.26 -x2 0.26 -y2 0.74
    }}

    # ---- midColors ----

    # Blue: a climbing chevron under an open arc - a course held.
    RR_Blue = @{ Color = $palette.Blue; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Arc     -g $g -pen $pen -S $S -cx 0.5 -cy 0.58 -r 0.34 -start 200 -sweep 140
        Draw-Chevron -g $g -pen $pen -S $S -cx 0.5 -cy 0.62 -w 0.22 -h 0.26 -Up $true
        Draw-Line    -g $g -pen $pen -S $S -x1 0.5 -y1 0.62 -x2 0.5 -y2 0.86
    }}

    # Yellow: an inverted triangle over a bar - the drop and the table.
    RR_Yellow = @{ Color = $palette.Yellow; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Triangle -g $g -pen $pen -S $S -cx 0.5 -cy 0.42 -r 0.26 -Up $false
        Draw-Line     -g $g -pen $pen -S $S -x1 0.26 -y1 0.78 -x2 0.74 -y2 0.78
        Draw-Line     -g $g -pen $pen -S $S -x1 0.5  -y1 0.66 -x2 0.5  -y2 0.78
    }}

    # Green: a ring of nodes around a centre - a network.
    RR_Green = @{ Color = $palette.Green; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring   -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r 0.20
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r1 0.20 -r2 0.32 -count 6
        for ($i = 0; $i -lt 6; $i++) {
            $a = (-90 + 60 * $i) * [Math]::PI / 180
            Draw-Disc -g $g -brush $brush -S $S `
                -cx ([single](0.5 + [Math]::Cos($a) * 0.34)) `
                -cy ([single](0.5 + [Math]::Sin($a) * 0.34)) -r 0.045
        }
    }}

    # Violet: three arms thrown out from a small centre.
    RR_Violet = @{ Color = $palette.Violet; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Disc   -g $g -brush $brush -S $S -cx 0.5 -cy 0.52 -r 0.075
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.52 -r1 0.12 -r2 0.36 -count 3 -startDeg -90
        for ($i = 0; $i -lt 3; $i++) {
            $a = (-90 + 120 * $i) * [Math]::PI / 180
            $ex = 0.5 + [Math]::Cos($a) * 0.36
            $ey = 0.52 + [Math]::Sin($a) * 0.36
            Draw-Disc -g $g -brush $brush -S $S -cx ([single]$ex) -cy ([single]$ey) -r 0.05
        }
    }}

    # Orange: a toothed ring - the machine that everything else rides on.
    RR_Orange = @{ Color = $palette.Orange; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring   -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r 0.22
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r1 0.22 -r2 0.34 -count 8
        Draw-Disc   -g $g -brush $brush -S $S -cx 0.5 -cy 0.5 -r 0.055
    }}

    # Gray: crossed bars locked inside a ring - order, held down.
    RR_Gray = @{ Color = $palette.Gray; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r 0.30
        Draw-Line -g $g -pen $pen -S $S -x1 0.29 -y1 0.29 -x2 0.71 -y2 0.71
        Draw-Line -g $g -pen $pen -S $S -x1 0.71 -y1 0.29 -x2 0.29 -y2 0.71
    }}

    # Lurcher: the Gray mark, with a hunting chevron set beneath it.
    RR_Gray_Lurcher = @{ Color = $palette.Gray; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring    -g $g -pen $pen -S $S -cx 0.5 -cy 0.42 -r 0.26
        Draw-Line    -g $g -pen $pen -S $S -x1 0.32 -y1 0.24 -x2 0.68 -y2 0.60
        Draw-Line    -g $g -pen $pen -S $S -x1 0.68 -y1 0.24 -x2 0.32 -y2 0.60
        Draw-Chevron -g $g -pen $pen -S $S -cx 0.5 -cy 0.92 -w 0.20 -h 0.16 -Up $true
    }}

    # Fulgur Bellator: the Green network inside a hardened outer shell.
    RR_Green_FulgurBellator = @{ Color = $palette.Green; Draw = {
        param($g,$pen,$brush,$S)
        $thick = New-Pen -Color $pen.Color -Width ($pen.Width * 1.6)
        try { Draw-Ring -g $g -pen $thick -S $S -cx 0.5 -cy 0.5 -r 0.40 } finally { $thick.Dispose() }
        Draw-Ring   -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r 0.15
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.5 -r1 0.15 -r2 0.26 -count 6
    }}

    # ---- lowColors ----

    # Red: the surface line, and a shaft dropping away from it with rungs.
    #
    # Deliberately NOT a ringed downward arrow. That form sits too close to the
    # published Red sigil, and a ladder in a shaft says the same thing about the
    # caste without borrowing anyone's drawing.
    RR_Red = @{ Color = $palette.Red; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Line -g $g -pen $pen -S $S -x1 0.14 -y1 0.20 -x2 0.86 -y2 0.20
        Draw-Line -g $g -pen $pen -S $S -x1 0.34 -y1 0.20 -x2 0.34 -y2 0.86
        Draw-Line -g $g -pen $pen -S $S -x1 0.66 -y1 0.20 -x2 0.66 -y2 0.86
        foreach ($y in @(0.38, 0.56, 0.74)) {
            Draw-Line -g $g -pen $pen -S $S -x1 0.34 -y1 $y -x2 0.66 -y2 $y
        }
    }}

    # Ultraheavy: the same shaft under load - the surface line doubled, the rails
    # thickened, and weight bearing down on the whole thing.
    RR_Red_Ultraheavy = @{ Color = $palette.Red; Draw = {
        param($g,$pen,$brush,$S)
        $thick = New-Pen -Color $pen.Color -Width ($pen.Width * 1.6)
        try {
            Draw-Line -g $g -pen $thick -S $S -x1 0.10 -y1 0.16 -x2 0.90 -y2 0.16
            Draw-Line -g $g -pen $thick -S $S -x1 0.16 -y1 0.28 -x2 0.84 -y2 0.28
            Draw-Line -g $g -pen $thick -S $S -x1 0.32 -y1 0.28 -x2 0.32 -y2 0.88
            Draw-Line -g $g -pen $thick -S $S -x1 0.68 -y1 0.28 -x2 0.68 -y2 0.88
        } finally { $thick.Dispose() }
        foreach ($y in @(0.46, 0.68)) {
            Draw-Line -g $g -pen $pen -S $S -x1 0.32 -y1 $y -x2 0.68 -y2 $y
        }
    }}

    # Pink: a rising triangle beneath a single held point.
    RR_Pink = @{ Color = $palette.Pink; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Triangle -g $g -pen $pen -S $S -cx 0.5 -cy 0.60 -r 0.26 -Up $true
        Draw-Disc     -g $g -brush $brush -S $S -cx 0.5 -cy 0.16 -r 0.065
    }}

    # Rose: the Pink mark with the point ringed - the same thing, made precious.
    RR_Pink_Rose = @{ Color = $palette.Pink; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Triangle -g $g -pen $pen -S $S -cx 0.5 -cy 0.62 -r 0.24 -Up $true
        Draw-Disc     -g $g -brush $brush -S $S -cx 0.5 -cy 0.18 -r 0.055
        Draw-Ring     -g $g -pen $pen -S $S -cx 0.5 -cy 0.18 -r 0.13
    }}

    # Obsidian: a crescent opening upward - the ice, and what waits on it.
    RR_Obsidian = @{ Color = $palette.Obsidian; Draw = {
        param($g,$pen,$brush,$S)
        $thick = New-Pen -Color $pen.Color -Width ($pen.Width * 1.5)
        try { Draw-Crescent -g $g -pen $thick -S $S -cx 0.5 -cy 0.52 -r 0.32 -openDeg -90 } finally { $thick.Dispose() }
        Draw-Disc -g $g -brush $brush -S $S -cx 0.5 -cy 0.52 -r 0.07
    }}

    # Stained: the crescent barred across - marked, and shown off.
    RR_Obsidian_Stained = @{ Color = $palette.Obsidian; Draw = {
        param($g,$pen,$brush,$S)
        $thick = New-Pen -Color $pen.Color -Width ($pen.Width * 1.5)
        try { Draw-Crescent -g $g -pen $thick -S $S -cx 0.5 -cy 0.52 -r 0.32 -openDeg -90 } finally { $thick.Dispose() }
        Draw-Line -g $g -pen $pen -S $S -x1 0.22 -y1 0.52 -x2 0.78 -y2 0.52
        Draw-Disc -g $g -brush $brush -S $S -cx 0.5 -cy 0.52 -r 0.07
    }}

    # Ascomanni: the crescent gone outward - spines, and no Board to file them with.
    RR_Obsidian_Ascomanni = @{ Color = $palette.Obsidian; Draw = {
        param($g,$pen,$brush,$S)
        $thick = New-Pen -Color $pen.Color -Width ($pen.Width * 1.5)
        try { Draw-Crescent -g $g -pen $thick -S $S -cx 0.5 -cy 0.52 -r 0.30 -openDeg -90 } finally { $thick.Dispose() }
        Draw-Spokes -g $g -pen $pen -S $S -cx 0.5 -cy 0.52 -r1 0.32 -r2 0.44 -count 5 -startDeg 20 -spanDeg 300
    }}

    # Brown: stacked bars, narrowing - service, and how little of it is seen.
    RR_Brown = @{ Color = $palette.Brown; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Line -g $g -pen $pen -S $S -x1 0.22 -y1 0.30 -x2 0.78 -y2 0.30
        Draw-Line -g $g -pen $pen -S $S -x1 0.28 -y1 0.50 -x2 0.72 -y2 0.50
        Draw-Line -g $g -pen $pen -S $S -x1 0.34 -y1 0.70 -x2 0.66 -y2 0.70
        Draw-Disc -g $g -brush $brush -S $S -cx 0.5 -cy 0.88 -r 0.05
    }}
}

# Gene icons, drawn at 128 rather than 64.
$geneGlyphs = [ordered]@{
    RR_Fertility_Reduced = @{ Color = '#B8C4D0'; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Ring -g $g -pen $pen -S $S -cx 0.5 -cy 0.44 -r 0.24
        Draw-Line -g $g -pen $pen -S $S -x1 0.5 -y1 0.68 -x2 0.5 -y2 0.90
        Draw-Line -g $g -pen $pen -S $S -x1 0.36 -y1 0.80 -x2 0.64 -y2 0.80
        Draw-Line -g $g -pen $pen -S $S -x1 0.22 -y1 0.72 -x2 0.78 -y2 0.16
    }}
    RR_HighbornAppetite = @{ Color = '#E8C24A'; Draw = {
        param($g,$pen,$brush,$S)
        Draw-Arc  -g $g -pen $pen -S $S -cx 0.5 -cy 0.50 -r 0.30 -start 20 -sweep 320
        Draw-Line -g $g -pen $pen -S $S -x1 0.32 -y1 0.30 -x2 0.32 -y2 0.62
        Draw-Line -g $g -pen $pen -S $S -x1 0.50 -y1 0.26 -x2 0.50 -y2 0.62
        Draw-Line -g $g -pen $pen -S $S -x1 0.68 -y1 0.30 -x2 0.68 -y2 0.62
        Draw-Line -g $g -pen $pen -S $S -x1 0.32 -y1 0.62 -x2 0.68 -y2 0.62
    }}
}

# --------------------------------------------------------------------- render

function Write-Glyph {
    param(
        [string] $OutFile,
        [int]    $Size,
        [string] $HexColor,
        [scriptblock] $Draw
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)

            $color = ToColor $HexColor
            $stroke = [single]([Math]::Max(2.0, $Size / 14.0))

            # Dark underlay, drawn slightly wider, so the glyph keeps its edges on
            # a pale background as well as a dark one.
            $shadow = New-Pen -Color ([System.Drawing.Color]::FromArgb(150, 12, 12, 16)) -Width ($stroke * 1.7)
            $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 12, 12, 16))
            try { & $Draw $g $shadow $shadowBrush ([single]$Size) }
            finally { $shadow.Dispose(); $shadowBrush.Dispose() }

            $pen = New-Pen -Color $color -Width $stroke
            $brush = New-Object System.Drawing.SolidBrush($color)
            try { & $Draw $g $pen $brush ([single]$Size) }
            finally { $pen.Dispose(); $brush.Dispose() }
        } finally { $g.Dispose() }

        $dir = Split-Path -Parent $OutFile
        if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
}

Write-Host ''
Write-Host 'New-XenotypeIcons' -ForegroundColor Cyan
Write-Host ("  xenotypes : {0}" -f $xenoDir) -ForegroundColor DarkGray
Write-Host ''

$count = 0
foreach ($name in $glyphs.Keys) {
    if ($Only -and $name -ne $Only) { continue }
    $spec = $glyphs[$name]
    $out = Join-Path $xenoDir "$name.png"
    if ((Test-Path $out) -and $NoForce) { continue }
    Write-Glyph -OutFile $out -Size 64 -HexColor $spec.Color -Draw $spec.Draw
    Write-Host ("  + {0}" -f $name) -ForegroundColor Green
    $count++
}

foreach ($name in $geneGlyphs.Keys) {
    if ($Only -and $name -ne $Only) { continue }
    $spec = $geneGlyphs[$name]
    # Gene icon filenames follow the iconPath in the defs, which drop the underscore
    # style used by defNames.
    $file = switch ($name) {
        'RR_Fertility_Reduced' { 'RR_FertilityReduced' }
        default                { $name }
    }
    $out = Join-Path $geneDir "$file.png"
    if ((Test-Path $out) -and $NoForce) { continue }
    Write-Glyph -OutFile $out -Size 128 -HexColor $spec.Color -Draw $spec.Draw
    Write-Host ("  + {0}" -f $file) -ForegroundColor Green
    $count++
}

Write-Host ''
Write-Host ("  {0} icon(s) written" -f $count)
Write-Host ''
