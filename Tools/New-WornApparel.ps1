<#
.SYNOPSIS
    Draws WORN apparel sprites that actually line up with RimWorld's pawn bodies.

.DESCRIPTION
    The thing that blocked worn apparel for this whole project was not drawing - it
    was not knowing WHERE THE BODY IS. Vanilla's pawn and apparel art lives inside
    Unity asset bundles and cannot be measured from disk, so every previous attempt
    would have been guessing at alignment and finding out in game.

    Measured instead, from a full-torso garment shipped loose by an installed mod
    (Jumpsuit), across every body type and facing. These are the fraction of the
    256x256 canvas the body occupies:

        body    facing        x              y
        Fat     east      0.18-0.77      0.30-0.89
        Fat     n/s       0.19-0.81      0.30-0.88
        Female  east      0.29-0.62      0.31-0.88
        Female  n/s       0.32-0.68      0.30-0.88
        Hulk    east      0.23-0.73      0.28-0.97
        Hulk    n/s       0.21-0.78      0.27-0.97
        Male    east      0.34-0.66      0.34-0.83
        Male    n/s       0.30-0.69      0.34-0.84
        Thin    east      0.34-0.59      0.35-0.83
        Thin    n/s       0.40-0.59      0.34-0.84

    Ten unrelated mods' Male_south textures agreed to within a couple of percent,
    so this is the convention rather than one author's habit.

    CHILD IS INTERPOLATED, not measured - the sample garment shipped no child
    variant. It is scaled from Thin and is the one row here that should be checked
    in game rather than trusted.

    WHY NOT THE GENERATIVE PIPELINE. Worn apparel is not judged on how good the
    painting is, it is judged on whether it sits on the body. ControlNet moves
    edges by a few pixels, which is invisible on an item icon and fatal on a sprite
    that has to register with a shoulder. These are drawn and stay drawn.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [string] $OutRoot,
    [string] $Only
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot = if ($OutRoot) { $OutRoot } else { Join-Path $ModRoot 'Textures' }

$script:Outline = [System.Drawing.Color]::FromArgb(255, 32, 29, 26)

$Steel     = [System.Drawing.Color]::FromArgb(255, 128, 134, 140)
$SteelDk   = [System.Drawing.Color]::FromArgb(255,  92,  97, 102)
$SteelHi   = [System.Drawing.Color]::FromArgb(255, 164, 171, 178)
$Leather   = [System.Drawing.Color]::FromArgb(255,  84,  60,  44)
$Brass     = [System.Drawing.Color]::FromArgb(255, 158, 128,  72)

# Measured body footprints, as canvas fractions. north and south share a box.
$Bodies = @{
    'Male'   = @{ ns = @(0.30, 0.69, 0.34, 0.84); east = @(0.34, 0.66, 0.34, 0.83) }
    'Female' = @{ ns = @(0.32, 0.68, 0.30, 0.88); east = @(0.29, 0.62, 0.31, 0.88) }
    'Thin'   = @{ ns = @(0.40, 0.59, 0.34, 0.84); east = @(0.34, 0.59, 0.35, 0.83) }
    'Fat'    = @{ ns = @(0.19, 0.81, 0.30, 0.88); east = @(0.18, 0.77, 0.30, 0.89) }
    'Hulk'   = @{ ns = @(0.21, 0.78, 0.27, 0.97); east = @(0.23, 0.73, 0.28, 0.97) }
    # INTERPOLATED, NOT MEASURED. Verify this one in game.
    'Child'  = @{ ns = @(0.38, 0.62, 0.42, 0.82); east = @(0.40, 0.60, 0.42, 0.82) }
}

function New-Canvas {
    param([int] $Size = 256)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    [pscustomobject]@{ Bmp = $bmp; G = $g; S = $Size }
}

function Save-Worn {
    param([System.Drawing.Bitmap] $Bmp, [string] $RelPath)
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    # Bitmap.Save does NOT append an extension.
    $Bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
}

<# A filled polygon with the standard dark outline, in canvas fractions. #>
function Plate {
    param($g, [int]$S, [array]$Pts, [System.Drawing.Color]$Color, [single]$OutlineW = 0.024)
    $arr = @()
    foreach ($p in $Pts) { $arr += New-Object System.Drawing.PointF([single]($p[0] * $S), [single]($p[1] * $S)) }
    $poly = [System.Drawing.PointF[]]$arr
    $pen = New-Object System.Drawing.Pen($script:Outline, [single]($S * $OutlineW))
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    try { $g.DrawPolygon($pen, $poly) } finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillPolygon($b, $poly) } finally { $b.Dispose() }
}

function Bar {
    param($g, [int]$S, [single]$x1, [single]$y1, [single]$x2, [single]$y2, [single]$w, [System.Drawing.Color]$Color)
    $pen = New-Object System.Drawing.Pen($Color, [single]($w * $S))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    try { $g.DrawLine($pen, [single]($x1*$S), [single]($y1*$S), [single]($x2*$S), [single]($y2*$S)) } finally { $pen.Dispose() }
}

<#
    duroArmor: a stamped cuirass with shoulder caps.

    It covers Torso and Shoulders, so it occupies the UPPER part of the body box
    and stops well short of the legs. Everything is derived from the measured box
    rather than hard-coded, which is what makes it fit every body type.
#>
function Draw-DuroArmor {
    param($g, [int]$S, [array]$Box, [string]$Facing)

    $x0 = $Box[0]; $x1 = $Box[1]; $y0 = $Box[2]; $y1 = $Box[3]
    $w = $x1 - $x0
    $h = $y1 - $y0

    # The cuirass: top of the torso down to roughly the waist.
    $top    = $y0 + ($h * 0.06)
    $bottom = $y0 + ($h * 0.56)
    $left   = $x0 + ($w * 0.09)
    $right  = $x1 - ($w * 0.09)
    $midY   = ($top + $bottom) / 2

    Plate $g $S @(
        @($left,  ($top + ($h * 0.05))),
        @((($left + $right) / 2), $top),
        @($right, ($top + ($h * 0.05))),
        @($right, ($bottom - ($h * 0.10))),
        @((($left + $right) / 2), $bottom),
        @($left,  ($bottom - ($h * 0.10)))
    ) $Steel

    if ($Facing -eq 'east') {
        # Side on: one shoulder cap, and a plain flank. No centre seam - you would
        # not see it, and drawing one is how a side view starts looking wrong.
        Plate $g $S @(
            @($left,  ($top + ($h * 0.02))),
            @(($left + ($w * 0.42)), $top),
            @(($left + ($w * 0.42)), ($top + ($h * 0.16))),
            @($left,  ($top + ($h * 0.18)))
        ) $SteelDk
        Bar $g $S ($left + ($w * 0.14)) ($midY + ($h * 0.02)) ($right - ($w * 0.10)) ($midY + ($h * 0.02)) ($h * 0.05) $Leather
        return
    }

    # Shoulder caps, sitting proud of the cuirass on both sides.
    Plate $g $S @(
        @(($x0 - ($w * 0.04)), ($top + ($h * 0.10))),
        @(($x0 + ($w * 0.20)), ($top - ($h * 0.01))),
        @(($x0 + ($w * 0.24)), ($top + ($h * 0.18))),
        @(($x0 - ($w * 0.02)), ($top + ($h * 0.22)))
    ) $SteelDk
    Plate $g $S @(
        @(($x1 + ($w * 0.04)), ($top + ($h * 0.10))),
        @(($x1 - ($w * 0.20)), ($top - ($h * 0.01))),
        @(($x1 - ($w * 0.24)), ($top + ($h * 0.18))),
        @(($x1 + ($w * 0.02)), ($top + ($h * 0.22)))
    ) $SteelDk

    if ($Facing -eq 'south') {
        # Front: centre strap, collar stud, and a highlight along the upper left.
        Bar $g $S (($left + $right) / 2) ($top + ($h * 0.10)) (($left + $right) / 2) ($bottom - ($h * 0.04)) ($w * 0.09) $Leather
        Bar $g $S ($left + ($w * 0.10)) ($top + ($h * 0.12)) ($left + ($w * 0.10)) ($bottom - ($h * 0.14)) ($w * 0.05) $SteelHi
        $r = $w * 0.07
        $cx = (($left + $right) / 2) * $S
        $cy = ($top + ($h * 0.13)) * $S
        $pen = New-Object System.Drawing.Pen($script:Outline, [single]($S * 0.022))
        try { $g.DrawEllipse($pen, ($cx - ($r*$S)), ($cy - ($r*$S)), ($r*2*$S), ($r*2*$S)) } finally { $pen.Dispose() }
        $b = New-Object System.Drawing.SolidBrush($Brass)
        try { $g.FillEllipse($b, ($cx - ($r*$S)), ($cy - ($r*$S)), ($r*2*$S), ($r*2*$S)) } finally { $b.Dispose() }
    }
    else {
        # Back: a spine rib and two fastening straps. Deliberately plainer, which
        # is how you tell at a glance which way a pawn is facing.
        Bar $g $S (($left + $right) / 2) ($top + ($h * 0.06)) (($left + $right) / 2) ($bottom - ($h * 0.04)) ($w * 0.07) $SteelDk
        foreach ($f in @(0.26, 0.44)) {
            Bar $g $S ($left + ($w * 0.06)) ($top + ($h * $f)) ($right - ($w * 0.06)) ($top + ($h * $f)) ($h * 0.035) $Leather
        }
    }
}

# Dot-sourced AFTER the helpers above, because the piece routines call Plate, Bar
# and the shared palette. Split out purely for size.
. (Join-Path $PSScriptRoot 'WornPieces.ps1')

$Pieces = @{
    'RR_DuroArmor'   = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_DuroArmor/RR_DuroArmor';     Draw = ${function:Draw-DuroArmor} }
    'RR_RecoilArmor' = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_RecoilArmor/RR_RecoilArmor'; Draw = ${function:Draw-RecoilArmor} }
    'RR_PulseArmor'  = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_PulseArmor/RR_PulseArmor';   Draw = ${function:Draw-PulseArmor} }
    'RR_ScarabSkin'  = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_ScarabSkin/RR_ScarabSkin';   Draw = ${function:Draw-ScarabSkin} }
    'RR_GhostCloak'  = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_GhostCloak/RR_GhostCloak';   Draw = ${function:Draw-GhostCloak} }
}

# Headgear is a different shape of problem: one texture per FACING, no body-type
# variants at all, and it registers against the head rather than the torso.
$Headgear = @{
    'RR_DemonHelm' = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_DemonHelm/RR_DemonHelm'; Draw = ${function:Draw-DemonHelm} }
}

# Exosuit modules: three facings like headgear, but drawn to the FRAMEWORK's own
# footprint at 512, not to the vanilla body boxes - see the note in WornPieces.ps1
# for why those do not apply here and why this set is the one that is unverified.
$Exosuit = @{
    'RR_StarShellCore'      = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_StarShell/RR_StarShellCore';  Draw = ${function:Draw-StarShellCore} }
    'RR_StarShellHead'      = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_StarShell/RR_StarShellHead';  Draw = ${function:Draw-StarShellHead} }
    'RR_StarShellCannonArm' = @{ Path = 'Things/Pawn/Humanlike/Apparel/RR_StarShell/RR_StarShellArm';   Draw = ${function:Draw-StarShellCannonArm} }
}

$made = 0
foreach ($name in $Pieces.Keys) {
    if ($Only -and $name -notlike "*$Only*") { continue }
    $piece = $Pieces[$name]
    foreach ($body in $Bodies.Keys) {
        foreach ($facing in @('north', 'east', 'south')) {
            $key = if ($facing -eq 'east') { 'east' } else { 'ns' }
            $box = $Bodies[$body][$key]
            $c = New-Canvas 256
            try {
                & $piece.Draw $c.G $c.S $box $facing
                Save-Worn $c.Bmp ("{0}_{1}_{2}" -f $piece.Path, $body, $facing)
                $made++
            } finally { $c.G.Dispose(); $c.Bmp.Dispose() }
        }
    }
    Write-Host ("  + {0}  ({1} variants)" -f $name, ($Bodies.Count * 3)) -ForegroundColor Green
}

foreach ($name in $Headgear.Keys) {
    if ($Only -and $name -notlike "*$Only*") { continue }
    $piece = $Headgear[$name]
    foreach ($facing in @('north', 'east', 'south')) {
        $c = New-Canvas 256
        try {
            & $piece.Draw $c.G $c.S $script:HeadBox $facing
            Save-Worn $c.Bmp ("{0}_{1}" -f $piece.Path, $facing)
            $made++
        } finally { $c.G.Dispose(); $c.Bmp.Dispose() }
    }
    Write-Host ("  + {0}  (3 facings, headgear - no body types)" -f $name) -ForegroundColor Green
}

foreach ($name in $Exosuit.Keys) {
    if ($Only -and $name -notlike "*$Only*") { continue }
    $piece = $Exosuit[$name]
    foreach ($facing in @('north', 'east', 'south')) {
        $c = New-Canvas 512
        try {
            & $piece.Draw $c.G $c.S $script:ExoBox $facing
            Save-Worn $c.Bmp ("{0}_{1}" -f $piece.Path, $facing)
            $made++
        } finally { $c.G.Dispose(); $c.Bmp.Dispose() }
    }
    Write-Host ("  + {0}  (3 facings, exosuit module at 512)" -f $name) -ForegroundColor Green
}

Write-Host ''
Write-Host ("{0} worn sprites written. Body and head boxes are MEASURED; Child is interpolated." -f $made)
Write-Host 'The starShell set is drawn to the exosuit framework footprint and is NOT verified.'
