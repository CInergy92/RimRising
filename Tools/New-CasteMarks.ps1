<#
.SYNOPSIS
    Draws the caste-mark tattoos (StyleDefs/Styles_RimRising.xml).
.DESCRIPTION
    Glyph art on skin, so drawn rather than generated - the same argument as the UI
    glyphs, and a tattoo is a few strokes the game clips to the skin anyway.

    TattooDef.GraphicFor (decompiled) is a Graphic_Multi with the CutoutSkinOverlay
    shader, masked by the head (face tattoos) or the naked body (body tattoos), so:
      - one texture per facing: _south, _east, _north;
      - CUTOUT: alpha is tested, not blended, so strokes are drawn fully opaque;
      - colour is the texture's own (PawnRenderNode_Tattoo multiplies alpha by 0.8),
        so the marks are drawn in ink colours.
    Placement uses the measured boxes in CLAUDE.md: the head box 0.29-0.70 x
    0.26-0.70 for face marks, the Male body box for body marks. Anything spilling
    off the skin is clipped by the mask.

    The marks are original: lattice traces for a Blue, tribal bands for an Obsidian,
    a unit tally for a Gray. None is a published sigil.
#>
[CmdletBinding()]
param([string] $OutRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if (-not $OutRoot) { $OutRoot = Join-Path $root 'Textures\Things\Pawn\Humanlike\Tattoos' }
$S = 128

$Cyan  = [System.Drawing.Color]::FromArgb(255,  40, 120, 150)
$Black = [System.Drawing.Color]::FromArgb(255,  28,  26,  30)
# Lighter than the Obsidian black: it has to read on dark skin too (rrtestmode=marks).
$Navy  = [System.Drawing.Color]::FromArgb(255,  58,  84, 128)

function New-Mark {
    param([string] $Name, [string] $Facing, [scriptblock] $Draw)
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        # Cutout shader: hard edges read cleaner than antialiasing that gets tested away.
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
        $g.Clear([System.Drawing.Color]::Transparent)
        & $Draw $g
    } finally { $g.Dispose() }
    $out = Join-Path $OutRoot ("{0}_{1}.png" -f $Name, $Facing)
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  + $out"
}

function L { param($g, [System.Drawing.Color]$c, [single]$w, [array]$pts)
    $pen = New-Object System.Drawing.Pen($c, [single]($w * $S))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Square
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $arr = @(); foreach ($p in $pts) { $arr += New-Object System.Drawing.PointF([single]($p[0]*$S), [single]($p[1]*$S)) }
    try { $g.DrawLines($pen, [System.Drawing.PointF[]]$arr) } finally { $pen.Dispose() }
}
function D { param($g, [System.Drawing.Color]$c, [single]$x, [single]$y, [single]$r)
    $b = New-Object System.Drawing.SolidBrush($c)
    try { $g.FillRectangle($b, [single](($x-$r)*$S), [single](($y-$r)*$S), [single](2*$r*$S), [single](2*$r*$S)) } finally { $b.Dispose() }
}
function P { param($g, [System.Drawing.Color]$c, [array]$pts)
    $arr = @(); foreach ($p in $pts) { $arr += New-Object System.Drawing.PointF([single]($p[0]*$S), [single]($p[1]*$S)) }
    $b = New-Object System.Drawing.SolidBrush($c)
    try { $g.FillPolygon($b, [System.Drawing.PointF[]]$arr) } finally { $b.Dispose() }
}

# ---------------------------------------------------------------- digiTat (Blue)
# Right-angled traces with nodes over the scalp and down a temple: the lattice.
New-Mark 'RR_DigiTat' 'south' { param($g)
    L $g $Cyan 0.022 @(@(0.40,0.30), @(0.40,0.36), @(0.46,0.36), @(0.46,0.30))
    L $g $Cyan 0.022 @(@(0.60,0.30), @(0.60,0.38), @(0.54,0.38))
    L $g $Cyan 0.022 @(@(0.34,0.36), @(0.34,0.46))
    L $g $Cyan 0.022 @(@(0.66,0.34), @(0.66,0.46))
    foreach ($n in @(@(0.46,0.30), @(0.54,0.38), @(0.34,0.46), @(0.66,0.46))) { D $g $Cyan $n[0] $n[1] 0.018 }
}
New-Mark 'RR_DigiTat' 'east' { param($g)
    L $g $Cyan 0.022 @(@(0.38,0.30), @(0.38,0.38), @(0.48,0.38), @(0.48,0.32))
    L $g $Cyan 0.022 @(@(0.44,0.38), @(0.44,0.50))
    L $g $Cyan 0.022 @(@(0.54,0.30), @(0.60,0.30), @(0.60,0.40))
    foreach ($n in @(@(0.48,0.32), @(0.44,0.50), @(0.60,0.40))) { D $g $Cyan $n[0] $n[1] 0.018 }
}
New-Mark 'RR_DigiTat' 'north' { param($g)
    L $g $Cyan 0.022 @(@(0.38,0.32), @(0.38,0.42), @(0.50,0.42), @(0.50,0.30))
    L $g $Cyan 0.022 @(@(0.62,0.32), @(0.62,0.42), @(0.56,0.42), @(0.56,0.52))
    foreach ($n in @(@(0.50,0.30), @(0.56,0.52), @(0.38,0.32))) { D $g $Cyan $n[0] $n[1] 0.018 }
}

# ------------------------------------------------------- stained brow (Obsidian)
# One downward chevron in the middle of the forehead.
#
# Keep face marks on the forehead. Two lessons from rrtestmode=marks (2026-10-24):
#  - the face is NOT clipped to the head's outline: strokes past the jaw draw on the
#    neck and collar (the first design, a band across the eyes ear to ear, read as a
#    blindfold and "goes off their skin" - the user);
#  - head shapes vary (Facial Animation draws its own), so the lower face moves from
#    pawn to pawn. Cheek streaks at y 0.62-0.68 sat on the cheeks of one head and on
#    the neck of the next. The forehead, y 0.42-0.47, is skin on every head seen.
New-Mark 'RR_ObsidianStainFace' 'south' { param($g)
    L $g $Black 0.026 @(@(0.445,0.43), @(0.50,0.468), @(0.555,0.43))
}
New-Mark 'RR_ObsidianStainFace' 'east' { param($g)
    L $g $Black 0.026 @(@(0.56,0.43), @(0.60,0.465), @(0.64,0.435))
}
# From behind the face is hidden; nothing shows.
New-Mark 'RR_ObsidianStainFace' 'north' { param($g) }

# ------------------------------------------------------- tribal stain (Obsidian)
# Chevron bands across the chest and shoulders; on the back, the same bands.
function Chevrons { param($g, [single]$cx, [single]$top, [single]$half)
    for ($i = 0; $i -lt 3; $i++) {
        $y = $top + ($i * 0.075)
        L $g $Black 0.03 @(@(($cx - $half), $y), @($cx, ($y + 0.05)), @(($cx + $half), $y))
    }
}
New-Mark 'RR_ObsidianStain' 'south' { param($g) Chevrons $g 0.50 0.44 0.16; L $g $Black 0.03 @(@(0.30,0.42), @(0.30,0.56)); L $g $Black 0.03 @(@(0.70,0.42), @(0.70,0.56)) }
New-Mark 'RR_ObsidianStain' 'north' { param($g) Chevrons $g 0.50 0.42 0.16 }
New-Mark 'RR_ObsidianStain' 'east'  { param($g) L $g $Black 0.03 @(@(0.40,0.44), @(0.40,0.60)); L $g $Black 0.03 @(@(0.48,0.44), @(0.48,0.60)); L $g $Black 0.03 @(@(0.56,0.44), @(0.56,0.60)) }

# ----------------------------------------------------------- legion mark (Gray)
# The unit on the upper arm: a tally of bars under a chevron. Worn on the left
# arm, which is the image's right from the front and its left from behind.
function Legion { param($g, [single]$x, [single]$y)
    L $g $Navy 0.03 @(@(($x - 0.05), ($y + 0.04)), @($x, $y), @(($x + 0.05), ($y + 0.04)))
    for ($i = 0; $i -lt 3; $i++) { L $g $Navy 0.024 @(@(($x - 0.045), ($y + 0.08 + $i * 0.045)), @(($x + 0.045), ($y + 0.08 + $i * 0.045))) }
}
New-Mark 'RR_LegionMark' 'south' { param($g) Legion $g 0.63 0.42 }
New-Mark 'RR_LegionMark' 'north' { param($g) Legion $g 0.37 0.42 }
New-Mark 'RR_LegionMark' 'east'  { param($g) Legion $g 0.50 0.46 }

Write-Host 'Caste marks drawn.'
