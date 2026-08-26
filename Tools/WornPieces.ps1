<#
    Draw routines for each worn piece, dot-sourced by New-WornApparel.ps1.

    Split into its own file purely for size: the alignment machinery and the
    measured body boxes live next door, and mixing three hundred lines of drawing
    in with them made both harder to read.

    Every shape here is derived from the body or head box it is handed. Nothing is
    positioned in absolute canvas coordinates, which is the whole reason one
    routine fits six body types.
#>

# Headgear footprint, measured the same way as the body boxes, from a dozen
# helmets shipped loose by installed mods. Plain helmets cluster tightly at
# x 0.29-0.70, y 0.26-0.70; the outliers are wide brims and oversized mech helms.
# Headgear has NO body-type variants - three files per piece, not eighteen.
$script:HeadBox = @(0.29, 0.70, 0.26, 0.70)

$script:Crimson   = [System.Drawing.Color]::FromArgb(255, 146,  40,  38)
$script:CrimsonDk = [System.Drawing.Color]::FromArgb(255,  92,  26,  26)
$script:CrimsonHi = [System.Drawing.Color]::FromArgb(255, 178,  56,  50)
$script:Glow      = [System.Drawing.Color]::FromArgb(255, 122, 168, 190)
$script:Black     = [System.Drawing.Color]::FromArgb(255,  30,  31,  35)
$script:BlackHi   = [System.Drawing.Color]::FromArgb(255,  52,  54,  60)
$script:Cloth     = [System.Drawing.Color]::FromArgb(255,  96, 102,  98)
$script:ClothDk   = [System.Drawing.Color]::FromArgb(255,  68,  73,  71)
$script:EyeAmber  = [System.Drawing.Color]::FromArgb(255, 198, 122,  58)

<# A filled circle, in canvas fractions. #>
function Dot {
    param($g, [int]$S, [single]$cx, [single]$cy, [single]$r, [System.Drawing.Color]$Color)
    $pen = New-Object System.Drawing.Pen($script:Outline, [single]($S * 0.020))
    try { $g.DrawEllipse($pen, (($cx - $r) * $S), (($cy - $r) * $S), ($r * 2 * $S), ($r * 2 * $S)) }
    finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillEllipse($b, (($cx - $r) * $S), (($cy - $r) * $S), ($r * 2 * $S), ($r * 2 * $S)) }
    finally { $b.Dispose() }
}

<#
    Recoil and pulse plate: angular crimson, gold trim, big pauldrons.

    One routine for both, because pulseArmor canonically IS recoilArmor with a
    shield generator and limb motors added - if the two did not share a silhouette
    the upgrade would not read as an upgrade. -Pulse adds the extras.

    Covers Torso, Neck, Shoulders, Arms AND Legs, so unlike duroArmor this runs the
    whole body box. The waist sits at about 52% down it, which is where the sample
    garment stops being torso and starts being legs.
#>
function Draw-RecoilPlate {
    param($g, [int]$S, [array]$Box, [string]$Facing, [switch]$Pulse)

    $x0 = $Box[0]; $x1 = $Box[1]; $y0 = $Box[2]; $y1 = $Box[3]
    $w = $x1 - $x0; $h = $y1 - $y0
    $waist = $y0 + ($h * 0.52)
    $mid = ($x0 + $x1) / 2

    # Legs first, so the tassets overlap them rather than the other way round.
    $legIn = $w * 0.10
    Plate $g $S @(
        @(($x0 + $legIn), $waist), @(($mid - ($w * 0.04)), $waist),
        @(($mid - ($w * 0.05)), $y1), @(($x0 + $legIn - ($w * 0.01)), $y1)) $script:CrimsonDk
    Plate $g $S @(
        @(($mid + ($w * 0.04)), $waist), @(($x1 - $legIn), $waist),
        @(($x1 - $legIn + ($w * 0.01)), $y1), @(($mid + ($w * 0.05)), $y1)) $script:CrimsonDk

    Plate $g $S @(
        @($mid, ($y0 + ($h * 0.05))),
        @(($x1 - ($w * 0.06)), ($y0 + ($h * 0.14))),
        @(($x1 - ($w * 0.02)), ($y0 + ($h * 0.34))),
        @(($x1 - ($w * 0.10)), $waist),
        @($mid, ($waist + ($h * 0.06))),
        @(($x0 + ($w * 0.10)), $waist),
        @(($x0 + ($w * 0.02)), ($y0 + ($h * 0.34))),
        @(($x0 + ($w * 0.06)), ($y0 + ($h * 0.14)))) $script:Crimson

    if ($Facing -eq 'east') {
        # One pauldron and a plain flank. No centre ridge - you would not see it,
        # and drawing one is how a side view starts looking wrong.
        Plate $g $S @(
            @(($x0 - ($w * 0.06)), ($y0 + ($h * 0.10))),
            @(($x0 + ($w * 0.46)), ($y0 + ($h * 0.01))),
            @(($x0 + ($w * 0.50)), ($y0 + ($h * 0.22))),
            @(($x0 - ($w * 0.02)), ($y0 + ($h * 0.26)))) $script:CrimsonDk
        Bar $g $S ($x0 + ($w * 0.12)) ($y0 + ($h * 0.36)) ($x1 - ($w * 0.10)) ($y0 + ($h * 0.36)) ($h * 0.030) $Brass
        if ($Pulse) { Dot $g $S ($mid + ($w * 0.10)) ($y0 + ($h * 0.30)) ($w * 0.10) $script:Glow }
        return
    }

    # PAULDRONS ARE THE SILHOUETTE. Layered wings proud of the shoulder on both
    # sides; without them this is just another breastplate.
    foreach ($side in @(-1, 1)) {
        $ex = if ($side -lt 0) { $x0 } else { $x1 }
        $o = $w * 0.13 * $side
        Plate $g $S @(
            @(($ex + $o), ($y0 + ($h * 0.12))),
            @(($ex - ($o * 0.35)), ($y0 - ($h * 0.01))),
            @(($ex - ($o * 0.75)), ($y0 + ($h * 0.20))),
            @(($ex + ($o * 0.55)), ($y0 + ($h * 0.26)))) $script:CrimsonDk
        Bar $g $S ($ex + $o) ($y0 + ($h * 0.115)) ($ex - ($o * 0.35)) ($y0 - ($h * 0.005)) ($h * 0.020) $Brass
    }

    if ($Pulse) {
        # Servo blocks at the shoulder roots: the visible difference from plain
        # recoil plate, along with the emitter below.
        foreach ($side in @(-1, 1)) {
            $sx = $mid + ($w * 0.30 * $side)
            Plate $g $S @(
                @(($sx - ($w * 0.05)), ($y0 + ($h * 0.16))),
                @(($sx + ($w * 0.05)), ($y0 + ($h * 0.16))),
                @(($sx + ($w * 0.05)), ($y0 + ($h * 0.30))),
                @(($sx - ($w * 0.05)), ($y0 + ($h * 0.30)))) $script:CrimsonDk
        }
    }

    if ($Facing -eq 'south') {
        Plate $g $S @(
            @($mid, ($y0 + ($h * 0.10))),
            @(($mid + ($w * 0.09)), ($y0 + ($h * 0.26))),
            @($mid, $waist),
            @(($mid - ($w * 0.09)), ($y0 + ($h * 0.26)))) $script:CrimsonHi
        Plate $g $S @(
            @($mid, ($y0 + ($h * 0.02))),
            @(($mid + ($w * 0.11)), ($y0 + ($h * 0.09))),
            @($mid, ($y0 + ($h * 0.15))),
            @(($mid - ($w * 0.11)), ($y0 + ($h * 0.09)))) $Brass
        if ($Pulse) { Dot $g $S $mid ($y0 + ($h * 0.30)) ($w * 0.11) $script:Glow }
        foreach ($f in @(-0.18, 0.0, 0.18)) {
            $tx = $mid + ($w * $f)
            Plate $g $S @(
                @(($tx - ($w * 0.07)), ($waist - ($h * 0.01))),
                @(($tx + ($w * 0.07)), ($waist - ($h * 0.01))),
                @(($tx + ($w * 0.05)), ($waist + ($h * 0.13))),
                @(($tx - ($w * 0.05)), ($waist + ($h * 0.13)))) $script:CrimsonDk
        }
    }
    else {
        # Back: spine rib and two fastening bands, deliberately plainer. That is
        # how you tell at a glance which way a pawn is facing.
        Bar $g $S $mid ($y0 + ($h * 0.06)) $mid ($waist + ($h * 0.02)) ($w * 0.07) $script:CrimsonDk
        foreach ($f in @(0.22, 0.38)) {
            Bar $g $S ($x0 + ($w * 0.10)) ($y0 + ($h * $f)) ($x1 - ($w * 0.10)) ($y0 + ($h * $f)) ($h * 0.024) $Brass
        }
        if ($Pulse) { Dot $g $S $mid ($y0 + ($h * 0.30)) ($w * 0.09) $script:Glow }
    }
}

function Draw-RecoilArmor { param($g, [int]$S, [array]$Box, [string]$Facing) Draw-RecoilPlate $g $S $Box $Facing }
# NO HELM IS DRAWN. pulseArmor covers FullHead, but the helm folds back into the
# collar when unsealed, so a bare head is the correct rendering rather than a gap -
# and the head stays mechanically protected either way. Drawing one would also have
# required knowing where the head sits in BODY space, which the measured head box
# does NOT give: those numbers are in head-node space, and using them here produced
# a helmet swallowing two thirds of the torso.
function Draw-PulseArmor { param($g, [int]$S, [array]$Box, [string]$Facing) Draw-RecoilPlate $g $S $Box $Facing -Pulse }

<#
    scarabSkin: a suit that takes in light and renders itself pitch black.

    Deliberately the OPPOSITE of the plate - no pauldrons, no trim, no silhouette
    beyond the body itself. If this read as armour it would be wrong, because the
    entire point of it is that it does not read at all.
#>
function Draw-ScarabSkin {
    param($g, [int]$S, [array]$Box, [string]$Facing)
    $x0 = $Box[0]; $x1 = $Box[1]; $y0 = $Box[2]; $y1 = $Box[3]
    $w = $x1 - $x0; $h = $y1 - $y0; $mid = ($x0 + $x1) / 2
    $waist = $y0 + ($h * 0.52)

    Plate $g $S @(
        @(($x0 + ($w * 0.10)), $waist), @(($mid - ($w * 0.03)), $waist),
        @(($mid - ($w * 0.04)), $y1), @(($x0 + ($w * 0.09)), $y1)) $script:Black
    Plate $g $S @(
        @(($mid + ($w * 0.03)), $waist), @(($x1 - ($w * 0.10)), $waist),
        @(($x1 - ($w * 0.09)), $y1), @(($mid + ($w * 0.04)), $y1)) $script:Black
    Plate $g $S @(
        @($mid, ($y0 + ($h * 0.02))),
        @(($x1 - ($w * 0.05)), ($y0 + ($h * 0.12))),
        @(($x1 - ($w * 0.08)), $waist),
        @(($x0 + ($w * 0.08)), $waist),
        @(($x0 + ($w * 0.05)), ($y0 + ($h * 0.12)))) $script:Black

    if ($Facing -eq 'south') {
        foreach ($f in @(0.20, 0.32, 0.44)) {
            Bar $g $S ($x0 + ($w * 0.14)) ($y0 + ($h * $f)) ($x1 - ($w * 0.14)) ($y0 + ($h * $f)) ($h * 0.014) $script:BlackHi
        }
    }
    elseif ($Facing -eq 'north') {
        Bar $g $S $mid ($y0 + ($h * 0.06)) $mid $waist ($w * 0.05) $script:BlackHi
    }
    else {
        Bar $g $S ($x0 + ($w * 0.30)) ($y0 + ($h * 0.12)) ($x0 + ($w * 0.30)) $waist ($w * 0.05) $script:BlackHi
    }
}

<#
    ghostCloak: Shell layer, so it is drawn OVER everything else and has to read as
    cloth rather than plate. Falls WIDER than the body and stops short of the feet,
    which is what makes a cloak read as a cloak instead of as a coat of paint.
#>
function Draw-GhostCloak {
    param($g, [int]$S, [array]$Box, [string]$Facing)
    $x0 = $Box[0]; $x1 = $Box[1]; $y0 = $Box[2]; $y1 = $Box[3]
    $w = $x1 - $x0; $h = $y1 - $y0; $mid = ($x0 + $x1) / 2

    Plate $g $S @(
        @($mid, ($y0 - ($h * 0.01))),
        @(($x1 + ($w * 0.10)), ($y0 + ($h * 0.16))),
        @(($x1 + ($w * 0.14)), ($y1 - ($h * 0.06))),
        @(($x0 - ($w * 0.14)), ($y1 - ($h * 0.06))),
        @(($x0 - ($w * 0.10)), ($y0 + ($h * 0.16)))) $script:Cloth

    if ($Facing -eq 'north') {
        Plate $g $S @(
            @($mid, ($y0 - ($h * 0.06))),
            @(($mid + ($w * 0.20)), ($y0 + ($h * 0.06))),
            @($mid, ($y0 + ($h * 0.20))),
            @(($mid - ($w * 0.20)), ($y0 + ($h * 0.06)))) $script:ClothDk
    }
    else {
        Bar $g $S $mid ($y0 + ($h * 0.12)) $mid ($y1 - ($h * 0.10)) ($w * 0.045) $script:ClothDk
    }
}

<#
    demonHelm: a black helm shaped subtly like a screaming face. Headgear, so it
    takes the HEAD box and has no body-type variants. At this size the two slanted
    eye slits ARE the face - anything finer disappears.
#>
function Draw-DemonHelm {
    param($g, [int]$S, [array]$Box, [string]$Facing)
    $x0 = $Box[0]; $x1 = $Box[1]; $y0 = $Box[2]; $y1 = $Box[3]
    $w = $x1 - $x0; $h = $y1 - $y0; $mid = ($x0 + $x1) / 2

    Plate $g $S @(
        @($mid, $y0),
        @(($x1 - ($w * 0.04)), ($y0 + ($h * 0.20))),
        @(($x1 - ($w * 0.10)), ($y1 - ($h * 0.12))),
        @($mid, $y1),
        @(($x0 + ($w * 0.10)), ($y1 - ($h * 0.12))),
        @(($x0 + ($w * 0.04)), ($y0 + ($h * 0.20)))) $script:Black

    if ($Facing -eq 'south') {
        foreach ($side in @(-1, 1)) {
            $ex = $mid + ($w * 0.19 * $side)
            Plate $g $S @(
                @(($ex - ($w * 0.11 * $side)), ($y0 + ($h * 0.36))),
                @(($ex + ($w * 0.07 * $side)), ($y0 + ($h * 0.30))),
                @(($ex + ($w * 0.09 * $side)), ($y0 + ($h * 0.44))),
                @(($ex - ($w * 0.09 * $side)), ($y0 + ($h * 0.47)))) $script:EyeAmber
        }
        Bar $g $S $mid ($y0 + ($h * 0.56)) $mid ($y1 - ($h * 0.10)) ($w * 0.06) $script:BlackHi
    }
    elseif ($Facing -eq 'east') {
        Plate $g $S @(
            @(($mid + ($w * 0.06)), ($y0 + ($h * 0.30))),
            @(($x1 - ($w * 0.08)), ($y0 + ($h * 0.26))),
            @(($x1 - ($w * 0.06)), ($y0 + ($h * 0.44))),
            @(($mid + ($w * 0.06)), ($y0 + ($h * 0.46)))) $script:EyeAmber
    }
    else {
        Bar $g $S $mid ($y0 + ($h * 0.18)) $mid ($y1 - ($h * 0.14)) ($w * 0.08) $script:BlackHi
    }
}
