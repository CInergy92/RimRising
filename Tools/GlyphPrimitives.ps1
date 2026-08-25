<#
.SYNOPSIS
    Shared drawing primitives for RimRising's icon generators.

.DESCRIPTION
    Dot-sourced by New-XenotypeIcons.ps1 and New-SymbolIcons.ps1 so both draw from
    one vocabulary and one caste palette. Extracted rather than duplicated: two
    copies of a rings-and-chevrons library would drift, and the whole value of the
    icon set is that a Gray gene icon and a Gray xenotype icon look related.

    All primitives work on a normalised 0..1 canvas, so a glyph recipe is
    independent of output resolution. $S is the pixel size, $g the Graphics, $pen
    the stroke.

    Contains no executable work - dot-sourcing it is safe.
#>

Add-Type -AssemblyName System.Drawing

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
