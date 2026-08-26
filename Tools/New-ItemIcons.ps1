<#
.SYNOPSIS
    Draws the weapon, implant and resource sprites in RimWorld's idiom.

.DESCRIPTION
    A second attempt. The first was flat saturated polygons with hard corners and a
    black outline, and it read as an infographic rather than as RimWorld.

    WHAT VANILLA ACTUALLY DOES, measured from an installed weapon sprite rather than
    remembered:

      - MUTED, DESATURATED colour. Steel is a grey-blue, not silver; brass is a dull
        ochre, not yellow.
      - The outline is a dark WARM GREY, not black, and it is thick - proportionally
        heavier than feels right until you see it at game zoom.
      - Forms are ROUNDED. Nothing has a sharp polygon corner.
      - Shading is one subtle lighter band along the upper-left edge of each form,
        not a gradient and not a second flat colour block.
      - The silhouette runs DIAGONALLY, lower-left to upper-right, filling most of
        the canvas.

    THE TECHNIQUE. Rounded forms come from stroking a line with a wide round-capped
    pen rather than filling a polygon - a capsule, not a rectangle. Each form is laid
    down three times: a wide dark pass for the outline, a narrower pass in the base
    colour, then a thin offset pass for the highlight. That is what produces
    RimWorld's soft, slightly chunky look procedurally.

    SHAPES COME FROM THE REFERENCE. The razor is based on the urumi - a slender
    flexible whip-sword - so it is a long thin tapering blade, not the broad curved
    sabre drawn first. About a metre in sword form, toggling to a whip twice that
    length, which is why it carries a slight flex rather than a sabre's belly.

    THESE ARE ORIGINAL DESIGNS. Nothing is traced from Red Rising artwork or from
    RimWorld's sprites; only the idiom is shared, and an idiom is a style.

    Worn APPAREL is still not attempted here - see the note at the end.

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    # Where to write. Defaults to Art/Silhouettes, NOT Textures.
    #
    # Textures/ now holds finished art produced by New-GeneratedArt.ps1, which uses
    # these sprites as its ControlNet input. Writing here by default would mean that
    # merely re-running this script silently destroyed the shipped art, and that a
    # regeneration would trace its own previous output and drift a little further
    # every pass. Pass -ToTextures to get the old behaviour deliberately.
    [string] $OutRoot,
    [switch] $ToTextures,
    # Multiplier on every sprite's edge length. The art pass renders at 4x so the
    # Canny edge map is crisp; a 128px master upscaled to 1024 gives soft edges and
    # a correspondingly weak control signal.
    [int] $Scale = 1,
    # Suppress the highlight pass, producing a pure FORM map. Used as ControlNet
    # input: Canny traces the highlight band as a hard edge, and the model then
    # renders it literally as a chrome stripe down the middle of the blade. A
    # control image should describe shape and let the model decide the shading.
    [switch] $Flat
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot =
    if     ($OutRoot)     { $OutRoot }
    elseif ($ToTextures)  { Join-Path $ModRoot 'Textures' }
    else                  { Join-Path $ModRoot 'Art/Silhouettes' }

# RimWorld's outline is a dark warm grey. Pure black reads as clip-art.
$script:Outline = [System.Drawing.Color]::FromArgb(255, 38, 34, 30)
$script:Scale = $Scale
$script:Flat  = [bool]$Flat

function Shade([System.Drawing.Color] $c, [double] $f) {
    [System.Drawing.Color]::FromArgb($c.A,
        [Math]::Max(0, [Math]::Min(255, [int]($c.R * $f))),
        [Math]::Max(0, [Math]::Min(255, [int]($c.G * $f))),
        [Math]::Max(0, [Math]::Min(255, [int]($c.B * $f))))
}

function Draw-Path {
    param($g, $pen, [array]$pts)
    if ($pts.Count -eq 2) { $g.DrawLine($pen, $pts[0], $pts[1]) }
    else { $g.DrawLines($pen, [System.Drawing.PointF[]]$pts) }
}

<#
    A rounded capsule along a path, drawn outline-body-highlight. $Pts are
    normalised 0..1 points; $W is body width as a canvas fraction.
#>
function Stroke-Form {
    param($g, [single]$S, [array]$Pts, [single]$W, [System.Drawing.Color]$Color, [switch]$NoHighlight)

    # NOTE THE NAME. PowerShell variable names are CASE-INSENSITIVE, so a local
    # called $pts is the same variable as the parameter $Pts - assigning it empties
    # the input before the loop reads it, and the function silently draws nothing.
    # That produced zero-point paths and a bare "Parameter is not valid" from GDI+.
    $px = @()
    foreach ($p in $Pts) {
        $px += New-Object System.Drawing.PointF([single]($p[0] * $S), [single]($p[1] * $S))
    }

    $ow = ($W * $S) + ($S * 0.055)
    $pen = New-Pen $script:Outline ([single]$ow)
    try { Draw-Path $g $pen $px } finally { $pen.Dispose() }

    $pen = New-Pen $Color ([single]($W * $S))
    try { Draw-Path $g $pen $px } finally { $pen.Dispose() }

    if (-not $NoHighlight -and -not $script:Flat) {
        $off = $S * 0.018
        $hi = @()
        foreach ($p in $px) {
            $hi += New-Object System.Drawing.PointF([single]($p.X - $off), [single]($p.Y - $off))
        }
        $pen = New-Pen (Shade $Color 1.28) ([single]($W * $S * 0.34))
        try { Draw-Path $g $pen $hi } finally { $pen.Dispose() }
    }
}

<#
    A TAPERING BLADE along a spine, filled as a polygon.

    Stroke-Form cannot draw a blade. It strokes a round-capped pen, so every form
    it makes has a constant width and a domed end - which is a baton, not a sword,
    and reads as one in game however it is shaded. Width has to vary along the
    length and reach zero at the tip, and that means an explicit polygon: walk the
    spine, offset each point perpendicular by a half-width interpolated from base
    to tip, and close the two sides into one outline.

    Drawn outline-then-fill like Stroke-Form, so the fill covers the inner half of
    the stroke and leaves RimWorld's thick dark edge outside.
#>
function Stroke-Taper {
    param($g, [single]$S, [array]$Spine, [single]$WBase, [single]$WTip, [System.Drawing.Color]$Color)

    $n = $Spine.Count
    $sideA = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $sideB = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $crest = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'

    for ($i = 0; $i -lt $n; $i++) {
        # Local tangent from the neighbours, so interior points follow the curve.
        $ia = [Math]::Max(0, $i - 1)
        $ib = [Math]::Min(($n - 1), ($i + 1))
        $dx = [double]$Spine[$ib][0] - [double]$Spine[$ia][0]
        $dy = [double]$Spine[$ib][1] - [double]$Spine[$ia][1]
        $len = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
        if ($len -lt 1e-9) { $len = 1e-9 }
        $nx = -$dy / $len
        $ny =  $dx / $len

        $t = 0.0
        if ($n -gt 1) { $t = [double]$i / ($n - 1) }
        $hw = ((([double]$WBase * (1.0 - $t)) + ([double]$WTip * $t)) / 2.0)

        $px = [double]$Spine[$i][0]
        $py = [double]$Spine[$i][1]
        # Arithmetic into variables first: inside an array literal the comma binds
        # before the minus and PowerShell subtracts from an array instead.
        $ax = ($px + ($nx * $hw)) * $S
        $ay = ($py + ($ny * $hw)) * $S
        $bx = ($px - ($nx * $hw)) * $S
        $by = ($py - ($ny * $hw)) * $S
        $cx = ($px - ($nx * $hw * 0.45)) * $S
        $cy = ($py - ($ny * $hw * 0.45)) * $S
        $sideA.Add((New-Object System.Drawing.PointF([single]$ax, [single]$ay)))
        $sideB.Add((New-Object System.Drawing.PointF([single]$bx, [single]$by)))
        $crest.Add((New-Object System.Drawing.PointF([single]$cx, [single]$cy)))
    }

    $sideB.Reverse()
    $poly = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $poly.AddRange($sideA)
    $poly.AddRange($sideB)
    $arr = [System.Drawing.PointF[]]$poly.ToArray()

    $pen = New-Pen $script:Outline ([single]($S * 0.055))
    try { $g.DrawPolygon($pen, $arr) } finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillPolygon($b, $arr) } finally { $b.Dispose() }

    # The bevel runs along the upper-left face, which for a lower-left to
    # upper-right spine is the -n side.
    if (-not $script:Flat) {
        $pen = New-Pen (Shade $Color 1.28) ([single]($S * [double]$WBase * 0.30))
        try { $g.DrawLines($pen, [System.Drawing.PointF[]]$crest.ToArray()) } finally { $pen.Dispose() }
    }
}

<# A rounded blob - knobs, apertures, rivets. #>
function Stroke-Dot {
    param($g, [single]$S, [single]$cx, [single]$cy, [single]$r, [System.Drawing.Color]$Color)
    $pen = New-Pen $script:Outline ([single]($S * 0.055))
    try { Draw-Ring $g $pen $S $cx $cy $r } finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { Draw-Disc $g $b $S $cx $cy $r } finally { $b.Dispose() }
}

<#
    A FACETED PLATE - an arbitrary filled polygon with the standard dark outline.

    Everything else here is built from round-capped capsules, because that is
    RimWorld's idiom. Red Rising armour is the opposite: hard-edged, bevelled,
    angular plate. Capsules cannot express that at any size, so armour gets
    polygons and the softness comes from the thick outline instead.
#>
function Stroke-Plate {
    param($g, [single]$S, [array]$Pts, [System.Drawing.Color]$Color, [switch]$NoOutline)
    $arr = @()
    foreach ($p in $Pts) {
        $arr += New-Object System.Drawing.PointF([single]($p[0] * $S), [single]($p[1] * $S))
    }
    $poly = [System.Drawing.PointF[]]$arr
    if (-not $NoOutline) {
        $pen = New-Pen $script:Outline ([single]($S * 0.055))
        try { $g.DrawPolygon($pen, $poly) } finally { $pen.Dispose() }
    }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillPolygon($b, $poly) } finally { $b.Dispose() }
}

<# An oval - Stroke-Dot only makes circles, and an aegis is specifically oval. #>
function Stroke-Oval {
    param($g, [single]$S, [single]$cx, [single]$cy, [single]$rx, [single]$ry, [System.Drawing.Color]$Color)
    $x = ($cx - $rx) * $S
    $y = ($cy - $ry) * $S
    $ow = $rx * 2 * $S
    $oh = $ry * 2 * $S
    $pen = New-Pen $script:Outline ([single]($S * 0.055))
    try { $g.DrawEllipse($pen, $x, $y, $ow, $oh) } finally { $pen.Dispose() }
    $b = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillEllipse($b, $x, $y, $ow, $oh) } finally { $b.Dispose() }
}

function Write-Sprite {
    param([string] $RelPath, [int] $Size, [scriptblock] $Draw)

    # .png MUST be appended: Bitmap.Save takes the format as a separate argument and
    # does NOT add an extension. Omitting it writes an extensionless file beside the
    # real one and still reports success - how the first version silently did nothing.
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

    $Size = $Size * $script:Scale
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            & $Draw $g $Size
        } finally { $g.Dispose() }
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
    Write-Host ("  + {0}" -f $RelPath) -ForegroundColor Green
}

# Muted palette, in the spirit of vanilla rather than picked bright.
$Steel   = [System.Drawing.Color]::FromArgb(255, 138, 145, 152)
$SteelHi = [System.Drawing.Color]::FromArgb(255, 178, 186, 194)
$Brass   = [System.Drawing.Color]::FromArgb(255, 170, 138,  74)
$Leather = [System.Drawing.Color]::FromArgb(255, 104,  70,  50)
$Ion     = [System.Drawing.Color]::FromArgb(255, 122, 142, 168)
$Flesh   = [System.Drawing.Color]::FromArgb(255, 150,  96, 112)
$Teal    = [System.Drawing.Color]::FromArgb(255,  96, 142, 136)
$Amber   = [System.Drawing.Color]::FromArgb(255, 198, 150,  66)
$Olive   = [System.Drawing.Color]::FromArgb(255, 150, 162, 132)   # pale service green
# Red Rising's armour palette, taken from the concept turnaround: deep red over
# black with gold trim, not the grey-blue steel everything else here uses.
$Crimson   = [System.Drawing.Color]::FromArgb(255, 146,  40,  38)
$CrimsonDk = [System.Drawing.Color]::FromArgb(255,  92,  26,  26)

# ------------------------------------------------------------------- the razor
#
# An urumi: slender, near-straight, tapering, with a slight flex. Diagonal
# lower-left to upper-right like every vanilla weapon. Gold's weapon, so a brass
# hilt against a pale polyenne blade.
# PROPORTION IS WHAT MAKES IT READ AS A BLADE. Drawn in game the previous version
# looked like a baton, and the reason was not shading: the grip took a third of the
# length and the blade was a constant-width capsule with a domed end. A sword
# silhouette is mostly blade, and the blade narrows the whole way to a point.
# Grip is now about a quarter of the length and the blade is a Stroke-Taper.
Write-Sprite 'Things/Item/Equipment/WeaponMelee/RR_Razor' 128 {
    param($g, $S)
    # Three spine points, the middle one lifted a little off the straight line, so
    # the blade carries the urumi's slight flex rather than being dead straight.
    Stroke-Taper $g $S @(@(0.295,0.715), @(0.618,0.388), @(0.955,0.052)) 0.058 0.004 $SteelHi
    # The pommel is a WIDER CAPSULE DRAWN UNDER THE GRIP, not a Stroke-Dot on top
    # of it. A dot draws its own complete dark ring, which Canny reads as a closed
    # contour independent of the grip - and a ControlNet pass then renders it as a
    # sphere floating loose beside the weapon. Anything meant to read as part of a
    # form has to share that form's silhouette, with no closed outline of its own.
    Stroke-Form $g $S @(@(0.108,0.902), @(0.145,0.865)) 0.112 $Brass
    Stroke-Form $g $S @(@(0.145,0.865), @(0.300,0.710)) 0.082 $Brass
    # A collar over the joint, so blade and grip meet at a hilt rather than just
    # overlapping.
    Stroke-Form $g $S @(@(0.292,0.722), @(0.322,0.692)) 0.098 $Brass
    # The shape-sensor stud: the toggle between blade and whip. This one stays a
    # dot - it sits well inside the grip and is meant to read as a separate rivet.
    Stroke-Dot  $g $S 0.205 0.805 0.021 $Amber
}

# ------------------------------------------------------- the Reaper's razor
#
# A razor holds whatever shape its bearer sets it to, and Darrow sets his into a
# sickle - the slingBlade a Red cuts helium from Martian rock with. That is the
# point of it: the most feared weapon in the Society, wearing the shape of a
# mining tool.
#
# So this is NOT a correction to the ordinary razor, which is correctly a slim
# straight blade. It is the same object shaped differently, and it gets its own
# def for that reason.
Write-Sprite 'Things/Item/Equipment/WeaponMelee/RR_ReaperRazor' 128 {
    param($g, $S)
    # The crescent, as a COMPUTED ARC. Hand-placing six spine points produced a
    # visibly faceted blade: Stroke-Taper joins its points with straight segments,
    # so a 160 degree sweep needs far more of them than a nearly straight razor
    # does. Sampling a circle gives a clean curve and keeps the geometry honest.
    $acx = 0.40; $acy = 0.38; $arad = 0.38
    $aStart = 111.0; $aEnd = -53.0
    $steps = 18
    $spine = @()
    for ($i = 0; $i -le $steps; $i++) {
        $t = [double]$i / $steps
        $ang = ($aStart + (($aEnd - $aStart) * $t)) * [Math]::PI / 180.0
        $sx = $acx + ($arad * [Math]::Cos($ang))
        $sy = $acy + ($arad * [Math]::Sin($ang))
        # Comma operator: without it a two-element array unrolls into the outer
        # array and the spine becomes a flat list of numbers.
        $spine += , @($sx, $sy)
    }
    Stroke-Taper $g $S $spine 0.088 0.005 $SteelHi

    # SEGMENT JOINTS AND A CUTTING EDGE, because a smooth crescent came back
    # looking blunt and unbroken next to the straight razor. The razor's blade is
    # visibly divided into sections by dark bands and carries a distinct edge; the
    # sickle needs the same marks or the two do not read as the same object made
    # by the same hands. Both have to be in the SILHOUETTE - Canny is what carries
    # them into the generated art, and no prompt wording substitutes for that.
    foreach ($bt in @(0.24, 0.46, 0.68)) {
        $bang = ($aStart + (($aEnd - $aStart) * $bt)) * [Math]::PI / 180.0
        $bcx = $acx + ($arad * [Math]::Cos($bang))
        $bcy = $acy + ($arad * [Math]::Sin($bang))
        # Perpendicular to the arc at this point is simply the radial direction.
        $rx = [Math]::Cos($bang); $ry = [Math]::Sin($bang)
        $half = ((0.088 * (1.0 - $bt)) + (0.005 * $bt)) / 2.0
        $b1x = $bcx - ($rx * $half); $b1y = $bcy - ($ry * $half)
        $b2x = $bcx + ($rx * $half); $b2y = $bcy + ($ry * $half)
        Stroke-Form $g $S @(@($b1x,$b1y), @($b2x,$b2y)) 0.016 (Shade $Steel 0.55) -NoHighlight
    }

    # The edge, a hairline running along the INNER curve - the side a sickle cuts
    # with. Offset toward the arc centre by most of the half-width so it sits on
    # the cutting side rather than down the middle.
    $edge = @()
    for ($i = 0; $i -le $steps; $i++) {
        $t = [double]$i / $steps
        $ang = ($aStart + (($aEnd - $aStart) * $t)) * [Math]::PI / 180.0
        $half = ((0.088 * (1.0 - $t)) + (0.005 * $t)) / 2.0
        $off = $half * 0.55
        $ex = $acx + (($arad - $off) * [Math]::Cos($ang))
        $ey = $acy + (($arad - $off) * [Math]::Sin($ang))
        $edge += , @($ex, $ey)
    }
    Stroke-Taper $g $S $edge 0.026 0.004 (Shade $SteelHi 1.18)

    # Grip, and a brass ferrule where blade meets haft.
    Stroke-Form $g $S @(@(0.105,0.900), @(0.150,0.855)) 0.120 $Brass
    Stroke-Form $g $S @(@(0.150,0.855), @(0.268,0.738)) 0.092 $Leather
    Stroke-Form $g $S @(@(0.255,0.752), @(0.290,0.717)) 0.106 $Brass
    Stroke-Dot  $g $S 0.196 0.808 0.024 $Amber
}

# ------------------------------------------------------------------- the aegis
#
# A buckler that projects an OVAL field - the shape is the canonical detail, so it
# is an oval rather than the round shield the word suggests. The physical part is
# only the rim and the boss the hand grips; the oval is projected. Drawn as one
# connected form throughout, because a rim floating clear of its boss is exactly
# how the razor's pommel became a sphere lying beside the weapon.
Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_Aegis/RR_Aegis' 128 {
    param($g, $S)
    # THE OVAL IS ENTIRELY FIELD. The first version put a steel ring inside the
    # oval, and the model duly read the whole thing as a rimmed metal shield with a
    # glowing centre - a physical buckler, which is the wrong object. An aegis is
    # projected light; the ONLY solid part is the emitter the hand holds. So there
    # is one oval, no frame inside it, and a brass boss at the middle.
    Stroke-Oval $g $S 0.50 0.50 0.300 0.435 $Ion       # the projected field, all of it
    Stroke-Dot  $g $S 0.50 0.50 0.115 $Brass           # the emitter boss - the only metal
    Stroke-Dot  $g $S 0.50 0.50 0.048 $Amber           # its core
}

# ---------------------------------------------------------------- pulse weapons

Write-Sprite 'Things/Item/Equipment/WeaponRanged/RR_PulseFist' 128 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.22,0.62), @(0.40,0.54)) 0.20 $Leather
    Stroke-Form $g $S @(@(0.40,0.55), @(0.68,0.45)) 0.24 $Brass
    Stroke-Form $g $S @(@(0.46,0.44), @(0.64,0.39)) 0.055 $Steel
    Stroke-Dot  $g $S 0.78 0.42 0.115 $Steel
    Stroke-Dot  $g $S 0.78 0.42 0.050 $Amber
}

Write-Sprite 'Things/Weapons/RR_PulseCannon' 128 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.14,0.70), @(0.40,0.58)) 0.19 $Leather
    Stroke-Form $g $S @(@(0.36,0.60), @(0.78,0.36)) 0.145 $Steel
    Stroke-Form $g $S @(@(0.74,0.38), @(0.90,0.29)) 0.185 $Brass
    Stroke-Form $g $S @(@(0.46,0.50), @(0.66,0.39)) 0.036 $Amber
}

# -------------------------------------------------------------------- scorcher
#
# A cheap carbine: long thin barrel, plain stock, nothing ornamental. It has to
# read as the poor relation of the pulseFist at a glance in an inventory list.
# IT HAS TO READ AS A FIREARM. The first version was three capsules in a line,
# which is a shape, not a gun - ControlNet rendered exactly that and it came out
# an abstract tube. A gun is legible from four things and they all have to be in
# the silhouette: a raked GRIP below and behind, a TRIGGER GUARD loop, a boxy
# RECEIVER, and a BARREL projecting past everything else.
Write-Sprite 'Things/Item/Equipment/WeaponRanged/RR_Scorcher' 128 {
    param($g, $S)
    # ORDER MATTERS AS MUCH AS POSITION. The first attempt drew the barrel first
    # and the receiver last, so the housing swallowed the barrel and the receiver
    # covered every cooling fin - the gun had no muzzle and no texture. Back to
    # front: frame, then grip and trigger, then the shroud, then the fins on it,
    # and the barrel LAST so it reads as lying in front and projecting clear.
    Stroke-Form $g $S @(@(0.282,0.556), @(0.575,0.503)) 0.170 $Steel    # receiver
    Stroke-Form $g $S @(@(0.300,0.585), @(0.238,0.862)) 0.175 $Leather  # grip, raked back
    # Trigger guard: a loop ATTACHED at both ends. A guard drawn as a free-
    # floating arc is the razor's pommel mistake over again.
    Stroke-Form $g $S @(@(0.330,0.628), @(0.392,0.706), @(0.478,0.636)) 0.040 $Steel
    Stroke-Form $g $S @(@(0.386,0.618), @(0.394,0.676)) 0.032 $Steel    # trigger

    Stroke-Form $g $S @(@(0.505,0.498), @(0.815,0.452)) 0.215 $Olive    # ribbed shroud

    # Cooling fins across the shroud. They give Canny interior detail to hold, so
    # the shroud does not come back as a featureless slab.
    $ax = 0.815 - 0.505; $ay = 0.452 - 0.498
    $al = [Math]::Sqrt(($ax * $ax) + ($ay * $ay))
    $nx = -$ay / $al; $ny = $ax / $al
    foreach ($t in @(0.12, 0.30, 0.48, 0.66, 0.84)) {
        $cx = 0.505 + ($ax * $t)
        $cy = 0.498 + ($ay * $t)
        $x1 = $cx - ($nx * 0.082); $y1 = $cy - ($ny * 0.082)
        $x2 = $cx + ($nx * 0.082); $y2 = $cy + ($ny * 0.082)
        Stroke-Form $g $S @(@($x1,$y1), @($x2,$y2)) 0.026 (Shade $Olive 0.66) -NoHighlight
    }

    # Barrel last, sitting below the shroud's centreline and running well past its
    # front face, which is what makes the thing read as a gun rather than a box.
    Stroke-Form $g $S @(@(0.545,0.548), @(0.960,0.485)) 0.072 (Shade $Steel 0.52)
    Stroke-Dot  $g $S 0.470 0.528 0.028 $Amber                          # charge light
}

# ------------------------------------------------------------------- duroArmor
#
# A stamped cuirass with shoulder caps, drawn front on the way vanilla draws its
# armour ITEM icons - the worn sprites are a separate directional set and are not
# generated here.
Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_DuroArmor/RR_DuroArmor' 128 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.50,0.36), @(0.50,0.70)) 0.42 $Steel      # breastplate
    Stroke-Form $g $S @(@(0.245,0.375), @(0.245,0.455)) 0.185 $Steel # shoulder cap
    Stroke-Form $g $S @(@(0.755,0.375), @(0.755,0.455)) 0.185 $Steel # shoulder cap
    Stroke-Form $g $S @(@(0.50,0.42), @(0.50,0.66)) 0.055 $Leather   # centre seam
    Stroke-Dot  $g $S 0.500 0.430 0.045 $Brass                       # collar stud
}

# ----------------------------------------------------------------- recoilArmor
#
# Interlocking plates that coil around the wearer. The banding is the whole
# identity of the thing, so the icon is a cuirass built from stacked overlapping
# bands rather than the single stamped shell duroArmor gets - the two have to be
# distinguishable side by side in a stockpile at 64px.
Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_RecoilArmor/RR_RecoilArmor' 128 {
    param($g, $S)
    # The skirt of hanging tassets, drawn first so the cuirass overlaps them.
    foreach ($sx in @(0.375, 0.500, 0.625)) {
        $l = $sx - 0.052; $r = $sx + 0.052
        Stroke-Plate $g $S @(@($l,0.660), @($r,0.660), @(($r - 0.014),0.815), @(($l + 0.014),0.815)) $CrimsonDk
    }
    # PAULDRONS FIRST AND BIGGEST. They are the whole silhouette - a layered
    # angular wing jutting up and outboard of the shoulder. Without them this is
    # just another breastplate.
    Stroke-Plate $g $S @(@(0.320,0.395), @(0.075,0.300), @(0.030,0.415), @(0.115,0.505), @(0.320,0.500)) $Crimson
    Stroke-Plate $g $S @(@(0.680,0.395), @(0.925,0.300), @(0.970,0.415), @(0.885,0.505), @(0.680,0.500)) $Crimson
    # Gold trim along the leading edge of each pauldron.
    Stroke-Form $g $S @(@(0.310,0.392), @(0.080,0.303)) 0.030 $Brass -NoHighlight
    Stroke-Form $g $S @(@(0.690,0.392), @(0.920,0.303)) 0.030 $Brass -NoHighlight

    # The cuirass: a sculpted plastron, faceted rather than domed.
    Stroke-Plate $g $S @(@(0.500,0.290), @(0.665,0.360), @(0.690,0.500), @(0.640,0.640),
                         @(0.500,0.710), @(0.360,0.640), @(0.310,0.500), @(0.335,0.360)) $Crimson
    # Raised sternum ridge running down the centre.
    Stroke-Plate $g $S @(@(0.500,0.345), @(0.556,0.455), @(0.500,0.665), @(0.444,0.455)) (Shade $Crimson 1.22)
    # Gold collar throat plate, and the amber vent below it.
    Stroke-Plate $g $S @(@(0.500,0.286), @(0.575,0.330), @(0.500,0.372), @(0.425,0.330)) $Brass
    Stroke-Dot   $g $S 0.500 0.560 0.042 $Amber
}

# ------------------------------------------------------------------ pulseArmor
#
# Canonically recoilArmor WITH a shield generator and limb motors added, so it is
# drawn as the same suit carrying more: doubled pauldrons, servo blocks at the
# shoulder roots, a shield emitter on the plastron, and a deeper skirt. If the two
# did not share a silhouette the upgrade would not read as an upgrade.
Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_PulseArmor/RR_PulseArmor' 128 {
    param($g, $S)
    foreach ($sx in @(0.345, 0.448, 0.552, 0.655)) {
        $l = $sx - 0.046; $r = $sx + 0.046
        Stroke-Plate $g $S @(@($l,0.672), @($r,0.672), @(($r - 0.012),0.855), @(($l + 0.012),0.855)) $CrimsonDk
    }
    # Doubled pauldrons: a big outer wing with a second plate layered over it.
    Stroke-Plate $g $S @(@(0.315,0.372), @(0.040,0.258), @(0.000,0.398), @(0.088,0.512), @(0.315,0.505)) $Crimson
    Stroke-Plate $g $S @(@(0.685,0.372), @(0.960,0.258), @(1.000,0.398), @(0.912,0.512), @(0.685,0.505)) $Crimson
    Stroke-Plate $g $S @(@(0.300,0.402), @(0.128,0.330), @(0.104,0.428), @(0.188,0.486), @(0.300,0.480)) (Shade $Crimson 1.20)
    Stroke-Plate $g $S @(@(0.700,0.402), @(0.872,0.330), @(0.896,0.428), @(0.812,0.486), @(0.700,0.480)) (Shade $Crimson 1.20)
    Stroke-Form $g $S @(@(0.305,0.369), @(0.045,0.262)) 0.030 $Brass -NoHighlight
    Stroke-Form $g $S @(@(0.695,0.369), @(0.955,0.262)) 0.030 $Brass -NoHighlight

    # Servo blocks at the shoulder roots - the limb motors, and the visible
    # difference from a plain recoilArmor.
    Stroke-Plate $g $S @(@(0.268,0.418), @(0.330,0.398), @(0.330,0.492), @(0.268,0.472)) $CrimsonDk
    Stroke-Plate $g $S @(@(0.732,0.418), @(0.670,0.398), @(0.670,0.492), @(0.732,0.472)) $CrimsonDk

    Stroke-Plate $g $S @(@(0.500,0.268), @(0.688,0.348), @(0.718,0.502), @(0.660,0.662),
                         @(0.500,0.742), @(0.340,0.662), @(0.282,0.502), @(0.312,0.348)) $Crimson
    Stroke-Plate $g $S @(@(0.500,0.325), @(0.562,0.440), @(0.500,0.690), @(0.438,0.440)) (Shade $Crimson 1.22)
    Stroke-Plate $g $S @(@(0.500,0.264), @(0.580,0.312), @(0.500,0.356), @(0.420,0.312)) $Brass
    # The shield generator on the plastron. This is the whole upgrade in one mark.
    Stroke-Dot $g $S 0.500 0.512 0.088 $Ion
    Stroke-Dot $g $S 0.500 0.512 0.042 (Shade $Ion 1.45)
}

# ------------------------------------------------- apparel INVENTORY icons
#
# The worn sprites live in New-WornApparel.ps1 and are drawn, not generated. These
# are the separate ITEM icons - what the piece looks like lying in a stockpile -
# and those do go through the generative pass like every other item.

Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_DemonHelm/RR_DemonHelm' 128 {
    param($g, $S)
    Stroke-Plate $g $S @(@(0.50,0.16), @(0.78,0.34), @(0.74,0.70), @(0.50,0.86), @(0.26,0.70), @(0.22,0.34)) (Shade $Steel 0.34)
    foreach ($side in @(-1, 1)) {
        $ex = 0.50 + (0.14 * $side)
        Stroke-Plate $g $S @(
            @(($ex - (0.09 * $side)), 0.48), @(($ex + (0.06 * $side)), 0.42),
            @(($ex + (0.07 * $side)), 0.56), @(($ex - (0.07 * $side)), 0.58)) $Amber
    }
    Stroke-Form $g $S @(@(0.50,0.62), @(0.50,0.80)) 0.055 (Shade $Steel 0.48) -NoHighlight
}

Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_GhostCloak/RR_GhostCloak' 128 {
    param($g, $S)
    # Folded, the way cloth reads as cloth in an inventory slot rather than as a
    # flat sheet: a hood above a bundled fall.
    Stroke-Plate $g $S @(@(0.50,0.12), @(0.68,0.28), @(0.50,0.42), @(0.32,0.28)) (Shade $Teal 0.72)
    Stroke-Plate $g $S @(@(0.30,0.36), @(0.70,0.36), @(0.80,0.84), @(0.20,0.84)) $Teal
    foreach ($x in @(0.38, 0.50, 0.62)) {
        Stroke-Form $g $S @(@($x,0.42), @(($x + (($x - 0.50) * 0.5)),0.80)) 0.045 (Shade $Teal 0.80) -NoHighlight
    }
}

Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_ScarabSkin/RR_ScarabSkin' 128 {
    param($g, $S)
    # A folded bodysuit. Almost black on purpose - it takes in light, and an icon
    # that reads as bright armour would be the wrong object.
    Stroke-Plate $g $S @(@(0.22,0.30), @(0.78,0.30), @(0.78,0.74), @(0.22,0.74)) (Shade $Steel 0.26)
    Stroke-Plate $g $S @(@(0.30,0.22), @(0.50,0.30), @(0.70,0.22), @(0.70,0.32), @(0.30,0.32)) (Shade $Steel 0.34)
    foreach ($y in @(0.42, 0.54, 0.66)) {
        Stroke-Form $g $S @(@(0.28,$y), @(0.72,$y)) 0.032 (Shade $Steel 0.40) -NoHighlight
    }
}

# -------------------------------------------------------------------- gravBoots
#
# A PAIR, seen three-quarters on. One boot reads as a boot; two read as gravBoots,
# and the difference matters in a stockpile list. Three parallel latches per boot
# is the canonical detail and the thing that stops them looking like footwear.
Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_GravBoots/RR_GravBoots' 128 {
    param($g, $S)
    foreach ($o in @(-0.155, 0.155)) {
        $x = 0.50 + $o
        # Shaft and foot, as one angular boot.
        Stroke-Plate $g $S @(
            @(($x - 0.085), 0.24), @(($x + 0.085), 0.24),
            @(($x + 0.095), 0.66), @(($x + 0.175), 0.70),
            @(($x + 0.175), 0.82), @(($x - 0.095), 0.82),
            @(($x - 0.095), 0.66)) $Steel
        # The three latches.
        foreach ($ly in @(0.32, 0.44, 0.56)) {
            Stroke-Form $g $S @(@(($x - 0.085),$ly), @(($x + 0.090),$ly)) 0.042 $Brass -NoHighlight
        }
        # The emitter in the sole, which is the whole point of the object.
        Stroke-Form $g $S @(@(($x - 0.085),0.775), @(($x + 0.165),0.775)) 0.048 $Ion -NoHighlight
    }
}

# ------------------------------------------------------------------- skipBoots
#
# The same pair read as the LIGHT option: a low-cut boot rather than a tall shaft,
# one strap instead of three latches, and side vents where the gravBoots carry a
# sole emitter. At icon size the height difference is what separates them.
Write-Sprite 'Things/Pawn/Humanlike/Apparel/RR_SkipBoots/RR_SkipBoots' 128 {
    param($g, $S)
    foreach ($o in @(-0.155, 0.155)) {
        $x = 0.50 + $o
        Stroke-Plate $g $S @(
            @(($x - 0.080), 0.44), @(($x + 0.080), 0.44),
            @(($x + 0.090), 0.68), @(($x + 0.170), 0.72),
            @(($x + 0.170), 0.82), @(($x - 0.090), 0.82),
            @(($x - 0.090), 0.68)) $Steel
        Stroke-Form $g $S @(@(($x - 0.080),0.52), @(($x + 0.086),0.52)) 0.040 $Brass -NoHighlight
        # Air vents down the flank: condensed air, not gravity.
        foreach ($vy in @(0.60, 0.66, 0.72)) {
            Stroke-Form $g $S @(@(($x - 0.070),$vy), @(($x + 0.010),$vy)) 0.022 (Shade $Steel 0.60) -NoHighlight
        }
    }
}

# ------------------------------------------------------------------ projectiles

Write-Sprite 'Things/Projectile/RR_PulseWave' 64 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.34,0.58), @(0.66,0.42)) 0.20 $Amber -NoHighlight
}

Write-Sprite 'Things/Projectile/RR_ParticleLance' 64 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.16,0.62), @(0.84,0.38)) 0.070 $Ion -NoHighlight
}

Write-Sprite 'Things/Projectile/RR_Warhead' 64 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.24,0.62), @(0.70,0.42)) 0.155 $Steel
    Stroke-Form $g $S @(@(0.68,0.43), @(0.84,0.36)) 0.075 $Leather
}

# --------------------------------------------------------------------- implants

Write-Sprite 'Things/Item/Health/RR_CupidsKiss' 128 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.36,0.20), @(0.50,0.50), @(0.62,0.80)) 0.062 $Steel
    foreach ($y in @(0.28, 0.42, 0.56, 0.70)) {
        # Arithmetic into variables first - inside @($x, $y - 0.1) the comma binds
        # before the minus and PowerShell subtracts from an array. Trap #1.
        $x  = 0.36 + (($y - 0.20) * 0.433)
        $x1 = $x - 0.11
        $x2 = $x + 0.11
        Stroke-Form $g $S @(@($x1,$y), @($x2,$y)) 0.055 $Flesh
    }
    Stroke-Dot $g $S 0.50 0.50 0.052 $Amber
}

Write-Sprite 'Things/Item/Health/RR_SynapticLattice' 128 {
    param($g, $S)
    for ($i = 0; $i -lt 6; $i++) {
        $a = [Math]::PI * 2 * $i / 6
        $x = 0.50 + [Math]::Cos($a) * 0.30
        $y = 0.50 + [Math]::Sin($a) * 0.30
        Stroke-Form $g $S @(@(0.50,0.50), @($x,$y)) 0.045 $Teal
    }
    Stroke-Dot $g $S 0.50 0.50 0.135 $Teal
    for ($i = 0; $i -lt 6; $i++) {
        $a = [Math]::PI * 2 * $i / 6
        $x = 0.50 + [Math]::Cos($a) * 0.30
        $y = 0.50 + [Math]::Sin($a) * 0.30
        Stroke-Dot $g $S $x $y 0.050 $Steel
    }
}

Write-Sprite 'Things/Item/Health/RR_CarvingKit' 128 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.22,0.66), @(0.78,0.50)) 0.30 $Leather
    for ($i = 0; $i -lt 4; $i++) {
        $x  = 0.30 + ($i * 0.14)
        $y  = 0.657 - ($i * 0.040)
        $yt = $y - 0.085
        $yb = $y + 0.070
        Stroke-Form $g $S @(@($x,$yt), @($x,$yb)) 0.056 $Teal
    }
}

# -------------------------------------------------------------------- resources

# Graphic_StackCount resolves the path as a FOLDER, so three variants. Three
# explicit calls: a single-element array of bars UNROLLS in PowerShell and the loop
# would then iterate over numbers instead of bars. Trap #2.
function Write-Ionsteel {
    param([string] $Variant, [array] $Bars)
    # NOT .GetNewClosure(). A closure binds the scriptblock to a fresh module
    # scope, which captures variables but CANNOT see this script's own functions -
    # so Stroke-Form goes missing the moment the script is invoked from another
    # script instead of run directly. It works standalone and fails under the art
    # pass, which is the worst way for it to fail. A $script: variable carries the
    # bars across instead, and the scriptblock stays in normal script scope.
    $script:IonsteelBars = $Bars
    Write-Sprite ("Things/Item/Resource/RR_Ionsteel/RR_Ionsteel_" + $Variant) 128 {
        param($g, $S)
        foreach ($b in $script:IonsteelBars) {
            Stroke-Form $g $S @(@($b[0],$b[1]), @($b[2],$b[3])) 0.155 $Ion
        }
    }
}

Write-Ionsteel 'a' @(
    ,@(0.32,0.62, 0.66,0.44)
)
Write-Ionsteel 'b' @(
    @(0.24,0.56, 0.56,0.38),
    @(0.44,0.74, 0.76,0.56)
)
Write-Ionsteel 'c' @(
    @(0.20,0.50, 0.50,0.34),
    @(0.38,0.68, 0.70,0.50),
    @(0.28,0.86, 0.58,0.70)
)

Write-Host ''
Write-Host 'Weapons, implants and resources redrawn in the muted RimWorld idiom.' -ForegroundColor Cyan
Write-Host 'Worn apparel is still not generated here - it draws over the pawn body' -ForegroundColor DarkGray
Write-Host 'and has to match RimWorld''s own silhouettes.' -ForegroundColor DarkGray
