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
param([string] $ModRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot = Join-Path $ModRoot 'Textures'

# RimWorld's outline is a dark warm grey. Pure black reads as clip-art.
$script:Outline = [System.Drawing.Color]::FromArgb(255, 38, 34, 30)

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

    if (-not $NoHighlight) {
        $off = $S * 0.018
        $hi = @()
        foreach ($p in $px) {
            $hi += New-Object System.Drawing.PointF([single]($p.X - $off), [single]($p.Y - $off))
        }
        $pen = New-Pen (Shade $Color 1.28) ([single]($W * $S * 0.34))
        try { Draw-Path $g $pen $hi } finally { $pen.Dispose() }
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

function Write-Sprite {
    param([string] $RelPath, [int] $Size, [scriptblock] $Draw)

    # .png MUST be appended: Bitmap.Save takes the format as a separate argument and
    # does NOT add an extension. Omitting it writes an extensionless file beside the
    # real one and still reports success - how the first version silently did nothing.
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

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
Write-Sprite 'Things/Item/Equipment/WeaponMelee/RR_Razor' 128 {
    param($g, $S)
    Stroke-Form $g $S @(@(0.30,0.72), @(0.50,0.52)) 0.075 $SteelHi
    Stroke-Form $g $S @(@(0.48,0.54), @(0.68,0.34)) 0.058 $SteelHi
    Stroke-Form $g $S @(@(0.66,0.36), @(0.87,0.14)) 0.034 $SteelHi
    Stroke-Form $g $S @(@(0.17,0.85), @(0.31,0.71)) 0.105 $Brass
    Stroke-Dot  $g $S 0.155 0.865 0.045 $Brass
    # The shape-sensor stud: the toggle between blade and whip.
    Stroke-Dot  $g $S 0.245 0.775 0.026 $Amber
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
    Write-Sprite ("Things/Item/Resource/RR_Ionsteel/RR_Ionsteel_" + $Variant) 128 {
        param($g, $S)
        foreach ($b in $Bars) {
            Stroke-Form $g $S @(@($b[0],$b[1]), @($b[2],$b[3])) 0.155 $Ion
        }
    }.GetNewClosure()
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
