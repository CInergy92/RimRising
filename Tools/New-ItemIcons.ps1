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
