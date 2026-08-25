<#
.SYNOPSIS
    Draws top-down silhouettes for the Drachenjaeger and its turrets.

.DESCRIPTION
    Vehicle art is a different problem from item art and gets its own script.

    DIMENSIONS ARE NOT FREE, and they are not square. Measured from Vanilla
    Vehicles Expanded rather than assumed:

        Tier3_IFV   drawSize (4,6)  ->  north/south 512x768,  east 768x512
        Tier1_APC   drawSize (3,5)  ->  north/south 384x640
        Tier3_AntiAir CannonTop drawSize (5,5) -> 640x640

    The rule is 128 PX PER drawSize UNIT, with north/south portrait and east the
    same texture landscape. The Drachenjaeger is drawSize (6,8), so its body
    sprites are 768x1024 and 1024x768, and its turrets at drawSize (4,4) are
    512x512. The previous placeholders were 128x128 squares, which is wrong on
    both count and aspect.

    EAST AND SOUTH ARE ROTATIONS OF NORTH, deliberately. Generating each facing
    independently produces three subtly different machines - a different number of
    vents, a different cockpit - because nothing ties the three generations
    together. Rotating one silhouette guarantees all three describe the same
    vehicle, and for a radially symmetric six-armed walker the loss is small.

    FRAMING MUST BE FIXED. Turret render offsets are measured from the vehicle's
    centre, so the sprite cannot be trimmed to its content box - a tighter crop on
    one facing would slide the turrets off the arms. Everything is drawn into the
    full canvas at a fixed scale and stays there.

    TURRETS POINT NORTH AND PIVOT ON THE TEXTURE CENTRE, because turretType is
    Rotatable and the framework spins the texture about its middle.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [string] $OutRoot,
    [switch] $ToTextures,
    [switch] $Flat
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot =
    if     ($OutRoot)    { $OutRoot }
    elseif ($ToTextures) { Join-Path $ModRoot 'Textures' }
    else                 { Join-Path $ModRoot 'Art/Silhouettes' }

$script:Outline = [System.Drawing.Color]::FromArgb(255, 38, 34, 30)
$script:Flat    = [bool]$Flat

$Hull    = [System.Drawing.Color]::FromArgb(255,  92,  98, 104)
$HullDk  = [System.Drawing.Color]::FromArgb(255,  68,  73,  78)
$Plate   = [System.Drawing.Color]::FromArgb(255, 118, 124, 130)
$Brass   = [System.Drawing.Color]::FromArgb(255, 170, 138,  74)
$Glass   = [System.Drawing.Color]::FromArgb(255,  84, 110, 118)
$Amber   = [System.Drawing.Color]::FromArgb(255, 198, 150,  66)

function Shade([System.Drawing.Color] $c, [double] $f) {
    [System.Drawing.Color]::FromArgb($c.A,
        [Math]::Max(0, [Math]::Min(255, [int]($c.R * $f))),
        [Math]::Max(0, [Math]::Min(255, [int]($c.G * $f))),
        [Math]::Max(0, [Math]::Min(255, [int]($c.B * $f))))
}

<#
    A capsule on a NON-SQUARE canvas. Points are 0..1 on each axis independently,
    but the pen width is a fraction of $W only - scaling stroke width by two
    different numbers is not possible with one pen, and keying it to the short
    edge keeps limbs an even thickness.
#>
function V-Form {
    param($g, [int]$W, [int]$H, [array]$Pts, [single]$Width, [System.Drawing.Color]$Color, [switch]$NoHighlight)
    $px = @()
    foreach ($p in $Pts) {
        $px += New-Object System.Drawing.PointF([single]($p[0] * $W), [single]($p[1] * $H))
    }
    $body = [single]($Width * $W)

    $pen = New-Pen $script:Outline ([single]($body + ($W * 0.028)))
    try {
        if ($px.Count -eq 2) { $g.DrawLine($pen, $px[0], $px[1]) } else { $g.DrawLines($pen, [System.Drawing.PointF[]]$px) }
    } finally { $pen.Dispose() }

    $pen = New-Pen $Color $body
    try {
        if ($px.Count -eq 2) { $g.DrawLine($pen, $px[0], $px[1]) } else { $g.DrawLines($pen, [System.Drawing.PointF[]]$px) }
    } finally { $pen.Dispose() }

    if (-not $NoHighlight -and -not $script:Flat) {
        $off = $W * 0.010
        $hi = @()
        foreach ($p in $px) { $hi += New-Object System.Drawing.PointF([single]($p.X - $off), [single]($p.Y - $off)) }
        $pen = New-Pen (Shade $Color 1.22) ([single]($body * 0.32))
        try {
            if ($hi.Count -eq 2) { $g.DrawLine($pen, $hi[0], $hi[1]) } else { $g.DrawLines($pen, [System.Drawing.PointF[]]$hi) }
        } finally { $pen.Dispose() }
    }
}

<# A tapering spike - the backpack rack, and the ion cleaver. #>
function V-Spike {
    param($g, [int]$W, [int]$H, [array]$Spine, [single]$WBase, [single]$WTip, [System.Drawing.Color]$Color)
    $n = $Spine.Count
    $a = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $b = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt $n; $i++) {
        $ia = [Math]::Max(0, $i - 1)
        $ib = [Math]::Min(($n - 1), ($i + 1))
        # Tangent in PIXELS, so the perpendicular is right on a non-square canvas.
        $dx = ([double]$Spine[$ib][0] - [double]$Spine[$ia][0]) * $W
        $dy = ([double]$Spine[$ib][1] - [double]$Spine[$ia][1]) * $H
        $len = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
        if ($len -lt 1e-9) { $len = 1e-9 }
        $nx = -$dy / $len
        $ny =  $dx / $len
        $t = 0.0
        if ($n -gt 1) { $t = [double]$i / ($n - 1) }
        $hw = ((([double]$WBase * (1.0 - $t)) + ([double]$WTip * $t)) / 2.0) * $W
        $cx = [double]$Spine[$i][0] * $W
        $cy = [double]$Spine[$i][1] * $H
        $axp = $cx + ($nx * $hw); $ayp = $cy + ($ny * $hw)
        $bxp = $cx - ($nx * $hw); $byp = $cy - ($ny * $hw)
        $a.Add((New-Object System.Drawing.PointF([single]$axp, [single]$ayp)))
        $b.Add((New-Object System.Drawing.PointF([single]$bxp, [single]$byp)))
    }
    $b.Reverse()
    $poly = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $poly.AddRange($a); $poly.AddRange($b)
    $arr = [System.Drawing.PointF[]]$poly.ToArray()
    $pen = New-Pen $script:Outline ([single]($W * 0.028))
    try { $g.DrawPolygon($pen, $arr) } finally { $pen.Dispose() }
    $br = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillPolygon($br, $arr) } finally { $br.Dispose() }
}

function V-Dot {
    param($g, [int]$W, [int]$H, [single]$cx, [single]$cy, [single]$r, [System.Drawing.Color]$Color)
    $rx = $r * $W
    $x = ($cx * $W) - $rx
    $y = ($cy * $H) - $rx
    $d = $rx * 2
    $pen = New-Pen $script:Outline ([single]($W * 0.028))
    try { $g.DrawEllipse($pen, $x, $y, $d, $d) } finally { $pen.Dispose() }
    $br = New-Object System.Drawing.SolidBrush($Color)
    try { $g.FillEllipse($br, $x, $y, $d, $d) } finally { $br.Dispose() }
}

function Save-Png {
    param([System.Drawing.Bitmap] $Bmp, [string] $RelPath)
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    # Bitmap.Save does NOT append an extension.
    $Bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("  + {0}" -f $RelPath) -ForegroundColor Green
}

# ------------------------------------------------------------- the Drachenjaeger
#
# Top-down, facing NORTH (up). From the def: a headless boxy giant, cockpit sunk
# between the shoulders where a neck should be, a spiked backpack, six arms with a
# particle cannon at every elbow.
$W = 768; $H = 1024
$body = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($body)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

# Backpack rack first, so everything else sits over it. Spikes splay rearward.
foreach ($sp in @(
    @(0.500, 0.735, 0.500, 0.900),
    @(0.380, 0.720, 0.250, 0.860),
    @(0.620, 0.720, 0.750, 0.860),
    @(0.300, 0.690, 0.120, 0.760),
    @(0.700, 0.690, 0.880, 0.760)
)) {
    V-Spike $g $W $H @(@($sp[0],$sp[1]), @($sp[2],$sp[3])) 0.075 0.006 $HullDk
}
V-Form $g $W $H @(@(0.500,0.620), @(0.500,0.730)) 0.44 $HullDk

# Legs, splayed back under the hull.
V-Form $g $W $H @(@(0.395,0.660), @(0.330,0.885)) 0.14 $HullDk
V-Form $g $W $H @(@(0.605,0.660), @(0.670,0.885)) 0.14 $HullDk

# Torso.
V-Form $g $W $H @(@(0.500,0.330), @(0.500,0.640)) 0.36 $Hull

# Shoulder blocks.
V-Form $g $W $H @(@(0.270,0.360), @(0.270,0.560)) 0.20 $Plate
V-Form $g $W $H @(@(0.730,0.360), @(0.730,0.560)) 0.20 $Plate

# Six arms - three a side. Upper arm out to an elbow, then the cannon barrel.
foreach ($arm in @(
    @(0.255, 0.385, 0.130, 0.345),
    @(0.250, 0.470, 0.105, 0.470),
    @(0.255, 0.555, 0.130, 0.615)
)) {
    $ex = $arm[2]; $ey = $arm[3]
    V-Form  $g $W $H @(@($arm[0],$arm[1]), @($ex,$ey)) 0.115 $Hull
    V-Dot   $g $W $H $ex $ey 0.058 $Plate
    $bx = $ex - 0.070; $by = $ey - 0.090
    V-Spike $g $W $H @(@($ex,$ey), @($bx,$by)) 0.062 0.022 $HullDk
    # Mirrored arm.
    $mx0 = 1.0 - $arm[0]; $mex = 1.0 - $ex; $mbx = 1.0 - $bx
    V-Form  $g $W $H @(@($mx0,$arm[1]), @($mex,$ey)) 0.115 $Hull
    V-Dot   $g $W $H $mex $ey 0.058 $Plate
    V-Spike $g $W $H @(@($mex,$ey), @($mbx,$by)) 0.062 0.022 $HullDk
}

# The ion cleaver, held out on the lower right arm.
V-Spike $g $W $H @(@(0.845,0.610), @(0.930,0.400), @(0.965,0.230)) 0.085 0.005 $Plate

# Cockpit, sunk between the shoulders where a neck should be. No head above it.
V-Form $g $W $H @(@(0.500,0.300), @(0.500,0.360)) 0.26 $Plate
V-Form $g $W $H @(@(0.500,0.300), @(0.500,0.330)) 0.17 $Glass
V-Dot  $g $W $H 0.500 0.268 0.036 $Amber

$g.Dispose()

Save-Png $body 'Things/Vehicles/RR_Drachenjager/RR_Drachenjager_north'

# East and south are ROTATIONS of the same silhouette, so all three facings are
# unarguably the same machine. RotateFlip changes the pixel dimensions for the 90
# degree case, which is exactly what the landscape east sprite needs.
$east = New-Object System.Drawing.Bitmap($body)
$east.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone)
Save-Png $east 'Things/Vehicles/RR_Drachenjager/RR_Drachenjager_east'
$east.Dispose()

$south = New-Object System.Drawing.Bitmap($body)
$south.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone)
Save-Png $south 'Things/Vehicles/RR_Drachenjager/RR_Drachenjager_south'
$south.Dispose()
$body.Dispose()

# ------------------------------------------------------------------- the turrets
#
# Rotatable, so each points NORTH and pivots on the centre of its own texture.
$T = 512

$pc = New-Object System.Drawing.Bitmap($T, $T, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($pc)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
# A cannon is MOSTLY BARREL. Two earlier attempts buried the barrels under a fat
# breech and an even fatter clamp, and produced a featureless egg with two tips
# poking out of the top. Note also that a V-Form whose two points nearly coincide
# is not a short bar, it is a CIRCLE of the pen width - which is how the "clamp"
# became a blob.
#
# The pivot sits at the texture centre because turretType is Rotatable and the
# framework spins the texture about its middle; the breech is placed around that
# point and the barrels run forward from it.
V-Spike $g $T $T @(@(0.415,0.545), @(0.415,0.080)) 0.100 0.062 $HullDk  # left barrel
V-Spike $g $T $T @(@(0.585,0.545), @(0.585,0.080)) 0.100 0.062 $HullDk  # right barrel
V-Form  $g $T $T @(@(0.500,0.500), @(0.500,0.745)) 0.32 $Hull           # breech
V-Dot   $g $T $T 0.500 0.500 0.090 $Plate                               # pivot
V-Dot   $g $T $T 0.500 0.665 0.042 $Amber                               # charge port
$g.Dispose()
Save-Png $pc 'Things/Vehicles/RR_Drachenjager/RR_Drachenjager_ParticleCannon'
$pc.Dispose()

$wr = New-Object System.Drawing.Bitmap($T, $T, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($wr)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
# Same rule as the cannon: pivot on the texture centre, tubes running forward from
# it, and the body no wider than it needs to be to hold them.
V-Form $g $T $T @(@(0.500,0.500), @(0.500,0.720)) 0.44 $HullDk          # rack body
foreach ($x in @(0.365, 0.455, 0.545, 0.635)) {
    V-Form  $g $T $T @(@($x,0.560), @($x,0.250)) 0.076 $Hull            # launch tube
    V-Spike $g $T $T @(@($x,0.275), @($x,0.110)) 0.072 0.012 $Brass     # warhead nose
}
V-Dot  $g $T $T 0.500 0.500 0.085 $Plate                                # pivot
$g.Dispose()
Save-Png $wr 'Things/Vehicles/RR_Drachenjager/RR_Drachenjager_WarheadRack'
$wr.Dispose()

Write-Host ''
Write-Host 'Drachenjaeger silhouettes drawn: body 768x1024 / 1024x768, turrets 512x512.'
