<#
.SYNOPSIS
    Draws the sprite a pawn is rendered as while flying on gravBoots.

.DESCRIPTION
    WHY THIS IS NOT IN New-ItemIcons.ps1. That script is the front half of the
    generative art pipeline: it writes silhouettes to Art/Silhouettes, and
    New-GeneratedArt.ps1 traces them with ControlNet to produce the shipped
    texture. This sprite must not go through that. Like worn apparel, it is not
    judged on how good the painting is - it is judged on whether it reads
    correctly at drawSize 1.4 while sliding up the screen, and ControlNet moving
    edges a few pixels would blur the one thing it has to communicate.

    THE MISTAKE THE FIRST VERSION MADE. Skyfallers travel up and down the screen,
    so the obvious instinct is to draw the subject from directly above, the way
    the drop pod it replaces is drawn. Drawn that way it came out as a dark
    horizontal capsule with two bright dots at the front, which reads as a car,
    because RimWorld does not draw people from above at ALL - pawns are drawn
    front-on, and a top-down human is not a shape any player has been taught to
    recognise in this game.

    So the figure here is drawn front-on like a pawn: head, shoulders, arms swept
    down and back, legs together. What communicates flight is not the viewing
    angle but the PLUME below the feet and the field bloom behind. A vertical
    figure with a plume under it reads as rising even though the drawing itself
    is the same orientation as a standing pawn.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

# Built explicitly rather than written as a literal: a bash heredoc silently eats
# backslashes in this environment, and the failure surfaces at runtime rather
# than at parse time. See CLAUDE.md.
$sep     = [string][char]92
$relPath = 'Things', 'Special', 'RR_GravAscent' -join $sep
$out     = (Join-Path $ModRoot 'Textures'), $relPath -join $sep
$out    += '.png'

$dir = Split-Path -Parent $out
if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
if ((Test-Path $out) -and -not $Force) {
    Write-Host "  = $relPath (exists; -Force to redraw)" -ForegroundColor DarkGray
    return
}

$size = 256
$mid  = $size / 2.0

# Muted, in the spirit of the rest of the mod's palette. A grav field is the one
# thing here allowed to be bright, but it is still a cold desaturated blue rather
# than a saturated cyan - vanilla has no neon.
$Outline  = [System.Drawing.Color]::FromArgb(255,  38,  34,  30)
$Slate    = [System.Drawing.Color]::FromArgb(255,  66,  72,  84)
$SlateHi  = [System.Drawing.Color]::FromArgb(255, 108, 118, 132)
$FieldIn  = [System.Drawing.Color]::FromArgb(150, 196, 220, 240)
$FieldMid = [System.Drawing.Color]::FromArgb( 70, 138, 176, 210)
$FieldOut = [System.Drawing.Color]::FromArgb(  0, 110, 148, 184)

# A round-capped stroke along a polyline. Every rounded form in this project comes
# from stroking a path with a wide pen rather than filling a polygon - a capsule,
# not a rectangle. See the art idiom notes in CLAUDE.md.
function Stroke-Line {
    param(
        [System.Drawing.Graphics] $G,
        [System.Drawing.Color] $Colour,
        [double] $Width,
        [double[]] $Points   # x0,y0, x1,y1, ...
    )
    $pen = New-Object System.Drawing.Pen($Colour, [single]$Width)
    try {
        $pen.StartCap    = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap      = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin    = [System.Drawing.Drawing2D.LineJoin]::Round
        for ($i = 0; $i -lt $Points.Length - 3; $i += 2) {
            $G.DrawLine($pen,
                [single]$Points[$i],     [single]$Points[$i + 1],
                [single]$Points[$i + 2], [single]$Points[$i + 3])
        }
    } finally { $pen.Dispose() }
}

$bmp = New-Object System.Drawing.Bitmap($size, $size)
try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)

        # ---- the field bloom -------------------------------------------------
        # PathGradientBrush rather than a stack of translucent circles. Stacked
        # circles band visibly once the sprite is scaled up on screen, and the
        # banding reads as concentric hard edges - which is to say, as an object.
        # Centred BELOW the figure, at the boots, because that is where the field
        # is generated and an evenly centred glow reads as a halo instead.
        $glowR  = $size * 0.46
        $glowCy = $mid + $size * 0.16
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        try {
            $gp.AddEllipse([single]($mid - $glowR), [single]($glowCy - $glowR),
                           [single]($glowR * 2), [single]($glowR * 2))
            $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp)
            try {
                $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
                $blend.Colors    = @($FieldOut, $FieldMid, $FieldIn)
                $blend.Positions = @(0.0, 0.5, 1.0)
                $pgb.InterpolationColors = $blend
                $g.FillEllipse($pgb, [single]($mid - $glowR), [single]($glowCy - $glowR),
                                     [single]($glowR * 2), [single]($glowR * 2))
            } finally { $pgb.Dispose() }
        } finally { $gp.Dispose() }

        # ---- the plume -------------------------------------------------------
        # A downward taper under the feet: wide and bright at the boots, fading to
        # nothing at the bottom edge. This is the single element that turns a
        # standing figure into a rising one, so it is drawn before the figure and
        # deliberately overlaps the legs.
        $plumeTop = $mid + $size * 0.165
        $plumeEnd = $size * 0.99
        $steps = 40
        for ($i = 0; $i -lt $steps; $i++) {
            $t = $i / [double]($steps - 1)
            $y = $plumeTop + ($plumeEnd - $plumeTop) * $t
            $w = $size * (0.098 * (1.0 - $t) + 0.010)
            $a = [int](205 * (1.0 - $t) * (1.0 - $t * 0.55))
            if ($a -le 2) { continue }
            $b = New-Object System.Drawing.SolidBrush(
                [System.Drawing.Color]::FromArgb($a, 214, 234, 248))
            try {
                $g.FillEllipse($b, [single]($mid - $w), [single]($y - $size * 0.024),
                                   [single]($w * 2), [single]($size * 0.048))
            } finally { $b.Dispose() }
        }

        # ---- the wearer, drawn front-on the way a pawn is ---------------------
        $headR  = $size * 0.056
        $headCy = $mid - $size * 0.170
        $shY    = $mid - $size * 0.088      # shoulder line
        $hipY   = $mid + $size * 0.010
        $footY  = $mid + $size * 0.150
        $shW    = $size * 0.072

        # Two passes: a wider dark outline, then the body colour inside it, so the
        # figure keeps a hard edge against the bright field behind it.
        foreach ($pass in @(
            @{ Col = $Outline; Torso = $size * 0.118; Limb = $size * 0.062 },
            @{ Col = $Slate;   Torso = $size * 0.086; Limb = $size * 0.036 }
        )) {
            # Arms, swept down and back from the shoulders - the posture of
            # someone being carried by their feet rather than flying head-first.
            Stroke-Line $g $pass.Col $pass.Limb @(
                ($mid - $shW), $shY,
                ($mid - $shW - $size * 0.058), ($shY + $size * 0.088))
            Stroke-Line $g $pass.Col $pass.Limb @(
                ($mid + $shW), $shY,
                ($mid + $shW + $size * 0.058), ($shY + $size * 0.088))

            # Torso: shoulders down to hips, one wide vertical capsule.
            Stroke-Line $g $pass.Col $pass.Torso @($mid, $shY, $mid, $hipY)

            # Legs, held together and trailing very slightly.
            Stroke-Line $g $pass.Col $pass.Limb @(
                ($mid - $size * 0.036), $hipY, ($mid - $size * 0.036), $footY)
            Stroke-Line $g $pass.Col $pass.Limb @(
                ($mid + $size * 0.036), $hipY, ($mid + $size * 0.036), $footY)
        }

        # One highlight band along the upper-left of the torso. One band, not a
        # gradient - that is how vanilla shades.
        Stroke-Line $g $SlateHi ($size * 0.026) @(
            ($mid - $size * 0.024), ($shY + $size * 0.014),
            ($mid - $size * 0.024), ($hipY - $size * 0.014))

        # Head last, overlapping the shoulders so the figure stays one connected
        # mass. A detached disc is exactly how the razor's pommel once became a
        # sphere lying beside the weapon.
        $ob = New-Object System.Drawing.SolidBrush($Outline)
        $sb = New-Object System.Drawing.SolidBrush($Slate)
        try {
            $r1 = $headR * 1.30
            $g.FillEllipse($ob, [single]($mid - $r1), [single]($headCy - $r1),
                                [single]($r1 * 2), [single]($r1 * 2))
            $g.FillEllipse($sb, [single]($mid - $headR), [single]($headCy - $headR),
                                [single]($headR * 2), [single]($headR * 2))
        } finally { $ob.Dispose(); $sb.Dispose() }

        # ---- the boots -------------------------------------------------------
        # The brightest points in the sprite, at the ankles, drawn over the legs.
        # They are what names the effect: without them this is any jump pack.
        foreach ($dx in @(-0.036, 0.036)) {
            $bx = $mid + $size * $dx
            $br = $size * 0.028
            $b = New-Object System.Drawing.SolidBrush(
                [System.Drawing.Color]::FromArgb(240, 234, 248, 255))
            try {
                $g.FillEllipse($b, [single]($bx - $br), [single]($footY - $br * 0.8),
                                   [single]($br * 2), [single]($br * 1.6))
            } finally { $b.Dispose() }
        }
    } finally { $g.Dispose() }
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $bmp.Dispose() }

Write-Host "  + $relPath" -ForegroundColor Green
