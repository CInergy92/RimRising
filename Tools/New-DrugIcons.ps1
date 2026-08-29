<#
.SYNOPSIS
    Draws the five drug item icons, three stack variants each.

.DESCRIPTION
    WHY THESE ARE NOT GENERATED. Two reasons, and the second is the practical one.

    First, a pill is a shape rather than a painting. There is nothing for
    ControlNet to add to a lozenge that the silhouette did not already say, which
    is the opposite of the weapons, where the generated pass supplies material and
    wear that no procedural drawing was going to.

    Second, and decisive: drug ThingDefs use Graphic_StackCount, which resolves
    texPath as a FOLDER and loads every image inside it - conventionally _a, _b
    and _c, drawn as DIFFERENT arrangements so a stack of five does not look like
    one pill photocopied. See the collection-graphics note in CLAUDE.md. The
    generative pipeline writes one file per item, so it cannot produce that set at
    all without three separate passes and a lot of stitching.

    So each drug is drawn three times here: one unit, two units, three units,
    which is exactly what vanilla's own drug textures do.

    Follows the measured RimWorld idiom from CLAUDE.md - rounded forms from
    stroking with a wide round-capped pen rather than filling a polygon, a thick
    dark warm-grey outline rather than black, muted colour, and ONE lighter band
    along the upper-left.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [int]    $Size = 128
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
$sep = [string][char]92

$Outline = [System.Drawing.Color]::FromArgb(255, 38, 34, 30)

function Shade { param([System.Drawing.Color] $C, [double] $F)
    $r=[int][math]::Max(0,[math]::Min(255,[math]::Round($C.R*$F)))
    $g=[int][math]::Max(0,[math]::Min(255,[math]::Round($C.G*$F)))
    $b=[int][math]::Max(0,[math]::Min(255,[math]::Round($C.B*$F)))
    return [System.Drawing.Color]::FromArgb($C.A,$r,$g,$b)
}

# A capsule: stroke a short line with a wide round-capped pen. Outline pass first
# and wider, then the body, then one highlight offset up-left.
function Cap {
    param($G, [int]$S, [double]$x1, [double]$y1, [double]$x2, [double]$y2,
          [double]$w, [System.Drawing.Color]$Col, [switch]$NoHi)
    foreach ($pass in @(
        @{ C = $Outline; W = $w + 0.055 },
        @{ C = $Col;     W = $w }
    )) {
        $pen = New-Object System.Drawing.Pen($pass.C, [single]($pass.W * $S))
        try {
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
            $G.DrawLine($pen, [single]($x1*$S), [single]($y1*$S), [single]($x2*$S), [single]($y2*$S))
        } finally { $pen.Dispose() }
    }
    if (-not $NoHi) {
        $pen = New-Object System.Drawing.Pen((Shade $Col 1.30), [single](($w * 0.28) * $S))
        try {
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
            $o = $w * 0.24
            $G.DrawLine($pen, [single](($x1 - $o*0.3)*$S), [single](($y1 - $o)*$S),
                              [single](($x2 - $o*0.3)*$S), [single](($y2 - $o)*$S))
        } finally { $pen.Dispose() }
    }
}

function Disc {
    param($G, [int]$S, [double]$cx, [double]$cy, [double]$r, [System.Drawing.Color]$Col)
    $ob = New-Object System.Drawing.SolidBrush($Outline)
    $fb = New-Object System.Drawing.SolidBrush($Col)
    try {
        $ro = $r + 0.028
        $G.FillEllipse($ob, [single](($cx-$ro)*$S), [single](($cy-$ro)*$S), [single](2*$ro*$S), [single](2*$ro*$S))
        $G.FillEllipse($fb, [single](($cx-$r)*$S),  [single](($cy-$r)*$S),  [single](2*$r*$S),  [single](2*$r*$S))
    } finally { $ob.Dispose(); $fb.Dispose() }
}

function Write-Icon {
    param([string] $Folder, [string] $Leaf, [scriptblock] $Draw)
    $dir = (Join-Path $ModRoot 'Textures'), 'Things', 'Item', 'Drug', $Folder -join $sep
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $out = ($dir, ($Leaf + '.png') -join $sep)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            & $Draw $g $Size
        } finally { $g.Dispose() }
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
    Write-Host ("  + {0}/{1}" -f $Folder, $Leaf) -ForegroundColor Green
}

# ----------------------------------------------------------------- palettes ---
$Grey    = [System.Drawing.Color]::FromArgb(255, 158, 158, 166)   # zoladone
$Glass   = [System.Drawing.Color]::FromArgb(255, 176, 190, 196)   # ampoule glass
$Fluid   = [System.Drawing.Color]::FromArgb(255, 198, 108,  62)   # mjolnir fluid
$Steel   = [System.Drawing.Color]::FromArgb(255, 138, 145, 152)
$Bone    = [System.Drawing.Color]::FromArgb(255, 222, 218, 206)   # nazopran tablet
$Bread   = [System.Drawing.Color]::FromArgb(255, 104,  74,  50)   # god's bread
$BreadHi = [System.Drawing.Color]::FromArgb(255, 146, 110,  74)
$Ash     = [System.Drawing.Color]::FromArgb(255, 132, 122, 118)   # fever cloud
$AshRed  = [System.Drawing.Color]::FromArgb(255, 150,  78,  70)

# Three arrangements per drug: one unit, two, three. Same objects, moved - which
# is what makes a stack read as a stack rather than as one item drawn larger.
$Layouts = @(
    @{ Leaf = '_a'; N = 1 },
    @{ Leaf = '_b'; N = 2 },
    @{ Leaf = '_c'; N = 3 }
)

# Offsets used when more than one unit is shown.
#
# KEYED ON THE COUNT, and note the leading commas. An array literal holding ONE
# array unrolls - @(@(0.5,0.52)) is not a one-element list of pairs, it is a
# two-element list of doubles, and the draw loop then tries to index into a
# Double. The comma operator forces the wrapper to survive. Same root cause as
# the HashSet-return trap recorded in CLAUDE.md.
$Spots = @{
    1 = @( ,@(0.50, 0.52) )
    2 = @( @(0.38, 0.60), @(0.62, 0.44) )
    3 = @( @(0.32, 0.63), @(0.52, 0.44), @(0.70, 0.62) )
}

foreach ($L in $Layouts) {
    $n = $L.N
    $pts = $Spots[$n]

    # ---- zoladone: a grey scored lozenge -------------------------------------
    Write-Icon 'RR_Zoladone' ('RR_Zoladone' + $L.Leaf) {
        param($g, $S)
        foreach ($p in $pts) {
            $cx = $p[0]; $cy = $p[1]
            Cap $g $S ($cx - 0.115) ($cy + 0.045) ($cx + 0.115) ($cy - 0.045) 0.135 $Grey
            # The score line, which is what makes it a pill rather than a bean.
            Cap $g $S ($cx - 0.020) ($cy + 0.052) ($cx + 0.020) ($cy - 0.052) 0.018 (Shade $Grey 0.62) -NoHi
        }
    }

    # ---- mjolnir-6: a glass ampoule with a metal collar ----------------------
    Write-Icon 'RR_Mjolnir6' ('RR_Mjolnir6' + $L.Leaf) {
        param($g, $S)
        foreach ($p in $pts) {
            $cx = $p[0]; $cy = $p[1]
            Cap $g $S ($cx - 0.130) ($cy + 0.100) ($cx + 0.090) ($cy - 0.070) 0.115 $Glass
            # Fluid inside, shorter and darker so it reads as a level.
            Cap $g $S ($cx - 0.105) ($cy + 0.080) ($cx + 0.020) ($cy - 0.015) 0.070 $Fluid -NoHi
            # Collar and needle at the top end.
            Cap $g $S ($cx + 0.080) ($cy - 0.062) ($cx + 0.125) ($cy - 0.096) 0.090 $Steel
            Cap $g $S ($cx + 0.132) ($cy - 0.102) ($cx + 0.190) ($cy - 0.146) 0.028 (Shade $Steel 0.72) -NoHi
        }
    }

    # ---- nazopran: a flat scored tablet --------------------------------------
    Write-Icon 'RR_Nazopran' ('RR_Nazopran' + $L.Leaf) {
        param($g, $S)
        foreach ($p in $pts) {
            $cx = $p[0]; $cy = $p[1]
            Disc $g $S $cx $cy 0.125 $Bone
            Cap  $g $S ($cx - 0.070) $cy ($cx + 0.070) $cy 0.020 (Shade $Bone 0.66) -NoHi
        }
    }

    # ---- god's bread: a dark pressed cake with fungus flecks -----------------
    Write-Icon 'RR_GodsBread' ('RR_GodsBread' + $L.Leaf) {
        param($g, $S)
        foreach ($p in $pts) {
            $cx = $p[0]; $cy = $p[1]
            # Squarer than the pills: pressed in a mould, not rolled.
            Cap $g $S ($cx - 0.085) ($cy + 0.020) ($cx + 0.085) ($cy - 0.020) 0.165 $Bread
            foreach ($f in @(@(-0.045, -0.030), @(0.030, 0.015), @(-0.005, 0.045))) {
                Disc $g $S ($cx + $f[0]) ($cy + $f[1]) 0.022 $BreadHi
            }
        }
    }

    # ---- fever cloud: a coarse heap of grey-red powder -----------------------
    Write-Icon 'RR_FeverCloud' ('RR_FeverCloud' + $L.Leaf) {
        param($g, $S)
        foreach ($p in $pts) {
            $cx = $p[0]; $cy = $p[1]
            # A low mound rather than a pill - this one is burned, not swallowed.
            Cap $g $S ($cx - 0.105) ($cy + 0.065) ($cx + 0.105) ($cy + 0.065) 0.115 $Ash
            Cap $g $S ($cx - 0.050) ($cy + 0.010) ($cx + 0.050) ($cy + 0.010) 0.090 (Shade $Ash 1.12)
            # The red in it, which is the whole reason it has that name.
            Disc $g $S ($cx - 0.030) ($cy + 0.030) 0.026 $AshRed
            Disc $g $S ($cx + 0.042) ($cy + 0.055) 0.022 $AshRed
        }
    }
}
