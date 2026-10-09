<#
    UI glyphs: issue icons, meme icons, role icons, the mod icon and the biome
    marks. Dot-sourced by New-AbilityIcons.ps1, which owns all of UI/.

    THESE ARE DRAWN, NOT GENERATED, and the reason is size. An issue icon sits in a
    dense ideoligion list at roughly 32px and a meme icon in a grid of a dozen
    others. A painted illustration turns to mush at that scale; a flat glyph with
    one strong shape does not. The same argument as the ability gizmos next door.

    The vocabulary is deliberately narrow - bars, rings, chevrons, blades - so
    fourteen marks read as one family rather than fourteen unrelated drawings.
#>

$script:GlyphInk   = [System.Drawing.Color]::FromArgb(255, 232, 228, 220)
$script:GlyphDim   = [System.Drawing.Color]::FromArgb(255, 148, 146, 142)
$script:GlyphGold  = [System.Drawing.Color]::FromArgb(255, 206, 168,  86)
$script:GlyphRed   = [System.Drawing.Color]::FromArgb(255, 168,  62,  58)
$script:GlyphSteel = [System.Drawing.Color]::FromArgb(255, 158, 168, 178)
$script:GlyphSand  = [System.Drawing.Color]::FromArgb(255, 176, 146, 104)
$script:GlyphGreen = [System.Drawing.Color]::FromArgb(255, 118, 148,  94)
$script:GlyphSky   = [System.Drawing.Color]::FromArgb(255,  96, 128, 150)

<# A thick stroked line in canvas fractions, with an outline pass beneath it. #>
function GBar {
    param($g, [int]$S, [single]$x1, [single]$y1, [single]$x2, [single]$y2,
          [single]$w, [System.Drawing.Color]$Color, [switch]$NoEdge)
    if (-not $NoEdge) {
        $pen = New-Object System.Drawing.Pen($script:Outline, [single](($w + 0.045) * $S))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        try { $g.DrawLine($pen, ($x1*$S), ($y1*$S), ($x2*$S), ($y2*$S)) } finally { $pen.Dispose() }
    }
    $pen = New-Object System.Drawing.Pen($Color, [single]($w * $S))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    try { $g.DrawLine($pen, ($x1*$S), ($y1*$S), ($x2*$S), ($y2*$S)) } finally { $pen.Dispose() }
}

function GPoly {
    param($g, [int]$S, [array]$Pts, [System.Drawing.Color]$Color)
    $arr = @()
    foreach ($p in $Pts) { $arr += New-Object System.Drawing.PointF([single]($p[0]*$S), [single]($p[1]*$S)) }
    $poly = [System.Drawing.PointF[]]$arr
    $pen = New-Object System.Drawing.Pen($script:Outline, [single]($S * 0.055))
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    try { $g.DrawPolygon($pen, $poly) } finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillPolygon($b, $poly) } finally { $b.Dispose() }
}

function GRing {
    param($g, [int]$S, [single]$cx, [single]$cy, [single]$r, [single]$w, [System.Drawing.Color]$Color)
    $pen = New-Object System.Drawing.Pen($script:Outline, [single](($w + 0.045) * $S))
    try { $g.DrawEllipse($pen, (($cx-$r)*$S), (($cy-$r)*$S), ($r*2*$S), ($r*2*$S)) } finally { $pen.Dispose() }
    $pen = New-Object System.Drawing.Pen($Color, [single]($w * $S))
    try { $g.DrawEllipse($pen, (($cx-$r)*$S), (($cy-$r)*$S), ($r*2*$S), ($r*2*$S)) } finally { $pen.Dispose() }
}

function GDisc {
    param($g, [int]$S, [single]$cx, [single]$cy, [single]$r, [System.Drawing.Color]$Color)
    $pen = New-Object System.Drawing.Pen($script:Outline, [single]($S * 0.055))
    try { $g.DrawEllipse($pen, (($cx-$r)*$S), (($cy-$r)*$S), ($r*2*$S), ($r*2*$S)) } finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillEllipse($b, (($cx-$r)*$S), (($cy-$r)*$S), ($r*2*$S), ($r*2*$S)) } finally { $b.Dispose() }
}

# --------------------------------------------------------------- issue glyphs

# A razor: the blade, edge on. The issue is who may hold one.
function Glyph-RazorBearing { param($g, [int]$S)
    GBar $g $S 0.22 0.80 0.80 0.22 0.085 $script:GlyphSteel
    GBar $g $S 0.18 0.84 0.30 0.72 0.150 $script:GlyphGold
}

# A cuirass. The issue is who may wear one.
function Glyph-ArmorBearing { param($g, [int]$S)
    GPoly $g $S @(@(0.50,0.20), @(0.74,0.32), @(0.70,0.66), @(0.50,0.80), @(0.30,0.66), @(0.26,0.32)) $script:GlyphSteel
    GBar  $g $S 0.50 0.34 0.50 0.70 0.070 $script:GlyphGold
}

# A blade over a spiral: cutting a new nature into someone.
function Glyph-Carving { param($g, [int]$S)
    GRing $g $S 0.46 0.56 0.24 0.075 $script:GlyphDim
    GBar  $g $S 0.26 0.80 0.80 0.24 0.075 $script:GlyphInk
    GDisc $g $S 0.46 0.56 0.075 $script:GlyphRed
}

# One bar above another, and an arrow between: rank, and which way it points.
function Glyph-ColorDeference { param($g, [int]$S)
    GBar $g $S 0.24 0.30 0.76 0.30 0.105 $script:GlyphGold
    GBar $g $S 0.32 0.72 0.68 0.72 0.105 $script:GlyphDim
    GBar $g $S 0.50 0.40 0.50 0.60 0.060 $script:GlyphInk
    GPoly $g $S @(@(0.50,0.66), @(0.58,0.54), @(0.42,0.54)) $script:GlyphInk
}

# Two rings, interlocked, of different weight. Union across the line.
function Glyph-InterColorUnion { param($g, [int]$S)
    GRing $g $S 0.39 0.50 0.21 0.080 $script:GlyphGold
    GRing $g $S 0.61 0.50 0.21 0.080 $script:GlyphRed
}

# ---------------------------------------------------------------- meme glyphs

# A stepped pyramid: the hierarchy, stated as plainly as it states itself.
function Glyph-ColorHierarchy { param($g, [int]$S)
    GPoly $g $S @(@(0.50,0.16), @(0.62,0.36), @(0.38,0.36)) $script:GlyphGold
    GPoly $g $S @(@(0.34,0.42), @(0.66,0.42), @(0.72,0.60), @(0.28,0.60)) $script:GlyphDim
    GPoly $g $S @(@(0.24,0.66), @(0.76,0.66), @(0.82,0.84), @(0.18,0.84)) $script:GlyphSteel
}

# The same three bars, levelled. The argument, in one shape.
function Glyph-ColorEquality { param($g, [int]$S)
    foreach ($y in @(0.32, 0.50, 0.68)) {
        GBar $g $S 0.20 $y 0.80 $y 0.105 $script:GlyphInk
    }
}

# A sun with rays, and nothing beneath it. Worship of the thing above.
function Glyph-GoldWorship { param($g, [int]$S)
    for ($i = 0; $i -lt 8; $i++) {
        $a = [Math]::PI * 2 * $i / 8
        $x1 = 0.50 + ([Math]::Cos($a) * 0.24); $y1 = 0.46 + ([Math]::Sin($a) * 0.24)
        $x2 = 0.50 + ([Math]::Cos($a) * 0.40); $y2 = 0.46 + ([Math]::Sin($a) * 0.40)
        GBar $g $S $x1 $y1 $x2 $y2 0.055 $script:GlyphGold
    }
    GDisc $g $S 0.50 0.46 0.20 $script:GlyphGold
}

# ----------------------------------------------------------------- role glyph

# A blade inside a laurel: the knighthoods.
function Glyph-OlympicKnight { param($g, [int]$S)
    GBar $g $S 0.50 0.78 0.50 0.20 0.080 $script:GlyphSteel
    GBar $g $S 0.38 0.34 0.62 0.34 0.070 $script:GlyphGold
    foreach ($side in @(-1, 1)) {
        for ($i = 0; $i -lt 3; $i++) {
            $y = 0.50 + ($i * 0.11)
            $x = 0.50 + (0.20 * $side)
            GBar $g $S $x $y ($x + (0.10 * $side)) ($y - 0.08) 0.055 $script:GlyphGold
        }
    }
}

# --------------------------------------------------------------- the mod icon

# Read at 64px in a mod list, so it is one mark: a rising chevron over a bar.
function Glyph-ModIcon { param($g, [int]$S)
    GPoly $g $S @(@(0.50,0.16), @(0.84,0.54), @(0.66,0.54), @(0.50,0.34), @(0.34,0.54), @(0.16,0.54)) $script:GlyphRed
    GBar  $g $S 0.20 0.74 0.80 0.74 0.110 $script:GlyphGold
}

# -------------------------------------------------------------- biome glyphs
#
# 512px, and drawn much simpler than that size suggests: a biome mark is read on
# the world map at a glance, next to a dozen vanilla ones.

function Glyph-HeliumBarrens { param($g, [int]$S)
    GPoly $g $S @(@(0.06,0.70), @(0.34,0.50), @(0.58,0.68), @(0.80,0.54), @(0.94,0.64), @(0.94,0.94), @(0.06,0.94)) $script:GlyphSand
    GBar  $g $S 0.62 0.62 0.62 0.20 0.075 $script:GlyphSteel
    GPoly $g $S @(@(0.62,0.14), @(0.72,0.30), @(0.52,0.30)) $script:GlyphSteel
}

function Glyph-TerraformedSteppe { param($g, [int]$S)
    GPoly $g $S @(@(0.06,0.94), @(0.06,0.66), @(0.30,0.52), @(0.56,0.66), @(0.78,0.54), @(0.94,0.64), @(0.94,0.94)) $script:GlyphGreen
    GBar  $g $S 0.20 0.40 0.20 0.24 0.055 $script:GlyphSky
    GBar  $g $S 0.34 0.36 0.34 0.22 0.055 $script:GlyphSky
    GBar  $g $S 0.48 0.40 0.48 0.26 0.055 $script:GlyphSky
}

# ------------------------------------------------------------ ability glyphs

# A hooded figure with its trailing edge broken up: there, and then not.
function Glyph-GhostCloakAbility { param($g, [int]$S)
    GPoly $g $S @(@(0.50,0.14), @(0.70,0.30), @(0.66,0.48), @(0.34,0.48), @(0.30,0.30)) $script:GlyphDim
    GPoly $g $S @(@(0.34,0.46), @(0.66,0.46), @(0.78,0.86), @(0.22,0.86)) $script:GlyphSteel
    foreach ($x in @(0.34, 0.50, 0.66)) {
        GBar $g $S $x 0.56 $x 0.80 0.045 $script:GlyphDim -NoEdge
    }
}

# ------------------------------------------- second content pass (2026-10-09)
#
# The five Color roles, the trial by razor and the caste-labour issue. Each role
# is drawn in its Color's own hue so the role list reads by caste at a glance;
# the marks are generic tools of the trade, not the published sigils (CLAUDE.md,
# copyright line on the sigils).

$script:GlyphYellow   = [System.Drawing.Color]::FromArgb(255, 222, 196,  84)
$script:GlyphOrange   = [System.Drawing.Color]::FromArgb(255, 214, 128,  58)
$script:GlyphBlue     = [System.Drawing.Color]::FromArgb(255,  92, 140, 206)
$script:GlyphWhite    = [System.Drawing.Color]::FromArgb(255, 236, 234, 228)
$script:GlyphObsidian = [System.Drawing.Color]::FromArgb(255,  70,  66,  78)

# Physician (Yellow): a staff with a cross-piece, and a drop.
function Glyph-RolePhysician { param($g, [int]$S)
    GBar  $g $S 0.50 0.82 0.50 0.20 0.085 $script:GlyphYellow
    GBar  $g $S 0.30 0.40 0.70 0.40 0.085 $script:GlyphYellow
    GDisc $g $S 0.70 0.70 0.085 $script:GlyphRed
}

# Engineer (Orange): a gear ring crossed by a spanner.
function Glyph-RoleEngineer { param($g, [int]$S)
    for ($i = 0; $i -lt 8; $i++) {
        $a = $i * [Math]::PI / 4
        $x1 = 0.46 + 0.20 * [Math]::Cos($a); $y1 = 0.54 + 0.20 * [Math]::Sin($a)
        $x2 = 0.46 + 0.29 * [Math]::Cos($a); $y2 = 0.54 + 0.29 * [Math]::Sin($a)
        GBar $g $S $x1 $y1 $x2 $y2 0.075 $script:GlyphOrange
    }
    GRing $g $S 0.46 0.54 0.19 0.075 $script:GlyphOrange
    GBar  $g $S 0.30 0.70 0.82 0.18 0.080 $script:GlyphSteel
}

# Pilot (Blue): a swept wing over a heading line.
function Glyph-RolePilot { param($g, [int]$S)
    GPoly $g $S @(@(0.14,0.62), @(0.50,0.26), @(0.86,0.62), @(0.70,0.62), @(0.50,0.44), @(0.30,0.62)) $script:GlyphBlue
    GBar  $g $S 0.50 0.58 0.50 0.84 0.075 $script:GlyphSteel
}

# Arbiter (White): a balance.
function Glyph-RoleArbiter { param($g, [int]$S)
    GBar  $g $S 0.50 0.80 0.50 0.22 0.070 $script:GlyphWhite
    GBar  $g $S 0.20 0.32 0.80 0.32 0.070 $script:GlyphWhite
    GPoly $g $S @(@(0.12,0.58), @(0.32,0.58), @(0.22,0.38)) $script:GlyphDim
    GPoly $g $S @(@(0.68,0.58), @(0.88,0.58), @(0.78,0.38)) $script:GlyphDim
    GBar  $g $S 0.34 0.82 0.66 0.82 0.070 $script:GlyphWhite
}

# Shaman (Obsidian): the god's gold crescent, a spear standing through it. (A
# crossbar under a disc read as the female sign - avoided.)
function Glyph-RoleShaman { param($g, [int]$S)
    GDisc $g $S 0.46 0.40 0.27 $script:GlyphGold
    GDisc $g $S 0.58 0.33 0.25 $script:GlyphObsidian
    GBar  $g $S 0.50 0.88 0.50 0.30 0.065 $script:GlyphSteel
    GPoly $g $S @(@(0.50,0.10), @(0.60,0.30), @(0.40,0.30)) $script:GlyphSteel
}

# Trial by razor: two razors crossed inside a ring - two duelists, one circle.
function Glyph-RazorTrial { param($g, [int]$S)
    GRing $g $S 0.50 0.50 0.32 0.060 $script:GlyphRed
    GBar  $g $S 0.24 0.78 0.78 0.24 0.070 $script:GlyphSteel
    GBar  $g $S 0.22 0.24 0.76 0.78 0.070 $script:GlyphSteel
    GBar  $g $S 0.20 0.80 0.30 0.70 0.130 $script:GlyphGold
    GBar  $g $S 0.20 0.20 0.30 0.30 0.130 $script:GlyphGold
}

# Caste labour: a pick above a dividing bar, a quill below - whose work is whose.
function Glyph-CasteLabor { param($g, [int]$S)
    GBar  $g $S 0.18 0.50 0.82 0.50 0.070 $script:GlyphDim
    GBar  $g $S 0.30 0.40 0.62 0.14 0.065 $script:GlyphSand
    GPoly $g $S @(@(0.52,0.12), @(0.76,0.20), @(0.70,0.28)) $script:GlyphSteel
    GBar  $g $S 0.36 0.86 0.64 0.60 0.060 $script:GlyphInk
    GPoly $g $S @(@(0.60,0.58), @(0.72,0.56), @(0.68,0.68)) $script:GlyphInk
}
