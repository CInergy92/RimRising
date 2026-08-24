<#
.SYNOPSIS
    Generates flat colored PNG placeholders for every texture path a def references
    but does not have, so the mod is playable before any real art exists.

.DESCRIPTION
    Scans Defs/ and Patches/ for texture-path nodes, works out which paths have no
    file under Textures/, and writes a placeholder PNG for each at the dimensions
    RimWorld expects for that kind of asset.

    Placeholder color is derived deterministically from the texture path, so a given
    def keeps the same color between runs and distinct defs are visually separable
    in game. Each placeholder is labelled with the leaf name of its path.

    Sizes are taken from measured reference mods, not from memory:
      UI/Icons/Genes      128x128   (measured: Alpha Genes gene icons)
      UI/Icons/Xenotypes   64x64    (measured: Alpha Genes xenotype icons)
      Things/Item         128x128   (measured: Alpha Genes item textures)
      Things/Weapons      256x256   (measured: Combat Extended Guns)
      everything else     128x128   (default; revisit per asset type as we add them)

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.

.PARAMETER Force
    Overwrite placeholders that already exist.

.PARAMETER IncludeModArt
    Also generate About/Preview.png and the mod icon if missing.

.PARAMETER WhatIf
    Report what would be written without writing anything.

.EXAMPLE
    .\Tools\New-PlaceholderTextures.ps1
.EXAMPLE
    .\Tools\New-PlaceholderTextures.ps1 -IncludeModArt -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $ModRoot,
    [switch] $Force,
    [switch] $IncludeModArt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
$texturesRoot = Join-Path $ModRoot 'Textures'

# ------------------------------------------------------------- size resolution

# Ordered longest-prefix-first so more specific rules win.
# Measured across ~140 textures in installed mods, not assumed:
#   weapons  128x128 (117 samples; a few mods ship 256, 128 is the convention)
#   apparel  256x256 (24 samples)
#   items    128x128
#   gene     128x128, xenotype 64x64
$script:SizeRules = @(
    @{ Prefix = 'UI/Icons/Xenotypes';                Size = 64  }
    @{ Prefix = 'UI/Icons/Genes';                    Size = 128 }
    @{ Prefix = 'Things/Pawn/Humanlike/Apparel';     Size = 256 }
    @{ Prefix = 'Things/Item/Equipment/WeaponMelee'; Size = 128 }
    @{ Prefix = 'Things/Item/Equipment/WeaponRanged';Size = 128 }
    @{ Prefix = 'Things/Weapons';                    Size = 128 }
    @{ Prefix = 'Things/Item';                       Size = 128 }
    @{ Prefix = 'Things/Pawn';                       Size = 256 }
    @{ Prefix = 'Things/Apparel';                    Size = 256 }
    @{ Prefix = 'Things/Building';                   Size = 128 }
    @{ Prefix = 'UI';                                Size = 128 }
)
$script:DefaultSize = 128

function Get-PlaceholderSize {
    param([string] $TexPath)
    $normalized = ($TexPath -replace '\\', '/').TrimStart('/')
    foreach ($rule in ($script:SizeRules | Sort-Object { $_.Prefix.Length } -Descending)) {
        if ($normalized.StartsWith($rule.Prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $rule.Size
        }
    }
    return $script:DefaultSize
}

function Get-PathColor {
    param([string] $TexPath)
    # FNV-1a over the path, mapped to a mid-saturation HSV color so text stays legible.
    # Arithmetic is done in uint64 and masked back to 32 bits each round, because
    # the multiply overflows uint32 before PowerShell gets a chance to mask it.
    [uint64] $hash = 2166136261
    foreach ($ch in $TexPath.ToCharArray()) {
        $hash = $hash -bxor [uint64][int]$ch
        # 4294967295 spelled out: the literal 0xFFFFFFFF parses as Int32 -1 in PowerShell.
        $hash = ($hash * [uint64]16777619) -band [uint64]4294967295
    }
    $hue = [double]($hash % 360)
    $sat = 0.45
    $val = 0.70

    $c = $val * $sat
    $x = $c * (1 - [Math]::Abs((($hue / 60) % 2) - 1))
    $m = $val - $c
    switch ([int][Math]::Floor($hue / 60)) {
        0 { $r, $g, $b = $c, $x, 0 }
        1 { $r, $g, $b = $x, $c, 0 }
        2 { $r, $g, $b = 0, $c, $x }
        3 { $r, $g, $b = 0, $x, $c }
        4 { $r, $g, $b = $x, 0, $c }
        default { $r, $g, $b = $c, 0, $x }
    }
    [System.Drawing.Color]::FromArgb(
        255,
        [int](($r + $m) * 255),
        [int](($g + $m) * 255),
        [int](($b + $m) * 255)
    )
}

function New-PlaceholderPng {
    param(
        [string] $OutFile,
        [int]    $Size,
        [string] $Label,
        [System.Drawing.Color] $Color,
        # 'north' / 'east' / 'south' / '' - set for a WORN, directional texture.
        #
        # WHY THIS EXISTS. A flat opaque labelled square is orientation-blind AND
        # it hides the pawn underneath, so drawData offsets and scale cannot be
        # judged from it at all - which is exactly the report that prompted this.
        # A directional placeholder is drawn translucent, with an arrow showing
        # which way it thinks it is facing and a crosshair on its exact centre,
        # so a bad offset is visible as the crosshair sitting off the pawn.
        [string] $Facing = '',
        # Keep a directional placeholder solid. Worn apparel must be translucent
        # so the pawn shows through and offsets can be judged; a vehicle body has
        # nothing behind it, but still benefits from the facing arrow.
        [switch] $Opaque
    )

    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    try {
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $gfx.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

            # Directional placeholders are translucent so the pawn shows through.
            $fillColor = if ($Facing -and -not $Opaque) {
                [System.Drawing.Color]::FromArgb(105, $Color.R, $Color.G, $Color.B)
            } else { $Color }
            $brush = New-Object System.Drawing.SolidBrush($fillColor)
            try { $gfx.FillRectangle($brush, 0, 0, $Size, $Size) } finally { $brush.Dispose() }

            # Border, so the sprite's extent is obvious against any background.
            $penWidth = [Math]::Max(2, [int]($Size / 32))
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 255, 255, 255), $penWidth)
            try {
                $half = [int][Math]::Ceiling($penWidth / 2)
                $gfx.DrawRectangle($pen, $half, $half, $Size - ($half * 2) - 1, $Size - ($half * 2) - 1)
            } finally { $pen.Dispose() }

            if ($Facing) {
                $mid = [int]($Size / 2)
                $arm = [int]($Size / 6)

                # Origin crosshair. If the sprite is offset wrongly this will not
                # sit over the pawn, which is the whole point of drawing it.
                $cross = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 255, 40, 40), [Math]::Max(2, [int]($Size / 64)))
                try {
                    $gfx.DrawLine($cross, $mid - $arm, $mid, $mid + $arm, $mid)
                    $gfx.DrawLine($cross, $mid, $mid - $arm, $mid, $mid + $arm)
                    $r = [int]($Size / 16)
                    $gfx.DrawEllipse($cross, $mid - $r, $mid - $r, $r * 2, $r * 2)
                } finally { $cross.Dispose() }

                # Facing arrow. South points down the screen, north up, east right.
                $ax = 0; $ay = 0
                switch ($Facing) {
                    'north' { $ay = -1 }
                    'south' { $ay =  1 }
                    'east'  { $ax =  1 }
                    'west'  { $ax = -1 }
                }
                $len = [int]($Size / 3)
                $tipX = $mid + ($ax * $len); $tipY = $mid + ($ay * $len)
                $apen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 255, 255, 255), [Math]::Max(3, [int]($Size / 40)))
                try {
                    $apen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
                    $gfx.DrawLine($apen, $mid, $mid, $tipX, $tipY)
                } finally { $apen.Dispose() }
            }

            # Label, wrapped and centered. Small icons get a shortened label.
            $text = if ($Size -le 64 -and $Label.Length -gt 10) { $Label.Substring(0, 10) } else { $Label }
            $fontSize = [Math]::Max(6, [int]($Size / 12))
            $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold)
            try {
                $fmt = New-Object System.Drawing.StringFormat
                $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
                # On a directional placeholder the label moves to the top so it
                # does not sit on the centre crosshair, which is the one mark that
                # has to stay readable.
                $fmt.LineAlignment = if ($Facing) {
                    [System.Drawing.StringAlignment]::Near
                } else {
                    [System.Drawing.StringAlignment]::Center
                }
                # Compute first: New-Object Type(a, b, c) parses the parens as an
                # array literal, so inline arithmetic binds to the wrong operand.
                $pad = [int]($Size / 10)
                $inner = [float]($Size - ($pad * 2))
                $rect = New-Object System.Drawing.RectangleF -ArgumentList ([float]$pad), ([float]$pad), $inner, $inner

                $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 0, 0, 0))
                $fg     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                try {
                    $shifted = New-Object System.Drawing.RectangleF -ArgumentList ([float]($rect.X + 1)), ([float]($rect.Y + 1)), $rect.Width, $rect.Height
                    $gfx.DrawString($text, $font, $shadow, $shifted, $fmt)
                    $gfx.DrawString($text, $font, $fg, $rect, $fmt)
                } finally { $shadow.Dispose(); $fg.Dispose(); $fmt.Dispose() }
            } finally { $font.Dispose() }
        } finally { $gfx.Dispose() }

        $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
}

# ------------------------------------------------- collect referenced textures

$script:TexturePathSuffixes = @('texpath', 'iconpath', 'graphicpath')

function Test-IsTexturePathNode {
    param([string] $NodeName)
    $lower = $NodeName.ToLowerInvariant()
    foreach ($suffix in $script:TexturePathSuffixes) {
        if ($lower.EndsWith($suffix)) { return $true }
    }
    return $false
}

Write-Host ''
Write-Host 'New-PlaceholderTextures' -ForegroundColor Cyan
Write-Host ("  mod root : {0}" -f $ModRoot) -ForegroundColor DarkGray

$xmlFiles = @(
    Get-ChildItem -Path $ModRoot -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\(Defs|Patches)\\' -and $_.FullName -notmatch '\\\.git\\' }
)

# texPath -> $true when the declared graphicClass derives from Graphic_Collection,
# which resolves the path as a FOLDER of images rather than a single file.
# Verified against Rimatomics (workshop 1127530465): its Graphic_StackCount
# texPaths are folders containing <leaf>_a / _b / _c.
$referenced = @{}

function Test-IsCollectionGraphicClass {
    param([string] $GraphicClass)
    if ([string]::IsNullOrWhiteSpace($GraphicClass)) { return $false }
    return $GraphicClass -match 'StackCount|Random|Collection'
}

# Classes that resolve texPath as a DIRECTIONAL SET - <leaf>_north/_east/_south -
# rather than as one file. Graphic_Multi is vanilla's; Vehicles.Graphic_Vehicle is
# Vehicle Framework's, confirmed by listing an installed VVE vehicle's textures.
# Graphic_Turret is explicitly NOT one: turrets ship a single file.
function Test-IsMultiGraphicClass {
    param([string] $GraphicClass)
    if ([string]::IsNullOrWhiteSpace($GraphicClass)) { return $false }
    if ($GraphicClass -match 'Graphic_Turret') { return $false }
    return $GraphicClass -match 'Graphic_Multi|Graphic_Vehicle'
}

foreach ($file in $xmlFiles) {
    $doc = New-Object System.Xml.XmlDocument
    try { $doc.Load($file.FullName) } catch {
        Write-Host ("  skipping malformed XML: {0}" -f $file.Name) -ForegroundColor Yellow
        continue
    }
    if (-not $doc.DocumentElement) { continue }

    foreach ($node in $doc.SelectNodes('//*')) {
        if (-not (Test-IsTexturePathNode $node.Name)) { continue }
        if ($node.ChildNodes.Count -ne 1) { continue }
        $val = $node.InnerText
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        $key = ($val.Trim() -replace '\\', '/').TrimStart('/')

        $graphicClass = $null
        if ($node.ParentNode) {
            $gc = $node.ParentNode.SelectSingleNode('graphicClass')
            if ($gc) { $graphicClass = $gc.InnerText.Trim() }
        }
        $isCollection = Test-IsCollectionGraphicClass -GraphicClass $graphicClass
        $isMulti      = Test-IsMultiGraphicClass      -GraphicClass $graphicClass

        # Apparel drawn ON a pawn needs per-facing textures, and the naming differs
        # by what the garment covers. Verified against installed mods:
        #
        #   headgear      AirwireHeadset_east.png          <path>_<dir>
        #   body apparel  BodyStrap_Fat_east.png           <path>_<BodyType>_<dir>
        #
        # A single flat file is not enough either way, and the game only throws
        # when a pawn EQUIPS the item - not at load - so a clean startup log proves
        # nothing here. Getting the headgear form right but not the body form is
        # exactly how scarabSkin and pulse armor both failed.
        $isWorn = ($node.Name -eq 'wornGraphicPath') -or
                  ($key -like 'Things/Pawn/Humanlike/Apparel/*')

        # Body apparel if it covers anything below the neck; head-only otherwise.
        $isBody = $false
        if ($isWorn -and $node.ParentNode) {
            $torsoGroups = @('Torso', 'Legs', 'Arms', 'Shoulders', 'Neck', 'Waist')
            foreach ($bp in $node.ParentNode.SelectNodes('bodyPartGroups/li')) {
                if ($torsoGroups -contains $bp.InnerText.Trim()) { $isBody = $true; break }
            }
        }

        if ($referenced.ContainsKey($key)) {
            $referenced[$key].Collection = $referenced[$key].Collection -or $isCollection
            $referenced[$key].Worn       = $referenced[$key].Worn -or $isWorn
            $referenced[$key].Body       = $referenced[$key].Body -or $isBody
            $referenced[$key].Multi      = $referenced[$key].Multi -or $isMulti
        } else {
            $referenced[$key] = @{ Collection = $isCollection; Worn = $isWorn; Body = $isBody; Multi = $isMulti }
        }
    }
}

Write-Host ("  found    : {0} referenced texture path(s)" -f $referenced.Count) -ForegroundColor DarkGray

# Only generate for paths this mod owns. A non-RR_ path is almost certainly a
# vanilla texture living inside a Unity asset bundle, and writing a placeholder
# over one of those would shadow real game art.
$owned   = @($referenced.Keys | Where-Object { (($_ -split '/')[-1]) -like 'RR_*' })
$foreign = @($referenced.Keys | Where-Object { (($_ -split '/')[-1]) -notlike 'RR_*' })

if ($foreign.Count -gt 0) {
    Write-Host ("  skipping : {0} non-RR_ path(s), assumed vanilla" -f $foreign.Count) -ForegroundColor DarkGray
}

# New-XenotypeIcons.ps1 owns the xenotype glyphs and our own gene icons, and draws
# real artwork rather than labelled squares. Never overwrite those here - not even
# with -Force, which would otherwise silently undo the whole icon set.
$ownedElsewhere = @($owned | Where-Object {
    $_ -like 'UI/Icons/Xenotypes/*' -or $_ -like 'UI/Icons/Genes/*'
})
if ($ownedElsewhere.Count -gt 0) {
    $owned = @($owned | Where-Object { $ownedElsewhere -notcontains $_ })
    Write-Host ("  skipping : {0} icon path(s) owned by New-XenotypeIcons.ps1" -f $ownedElsewhere.Count) -ForegroundColor DarkGray
}

$created = 0
$skipped = 0

foreach ($texPath in ($owned | Sort-Object)) {
    $size  = Get-PlaceholderSize -TexPath $texPath
    $leaf  = ($texPath -split '/')[-1]
    $label = $leaf -replace '^RR_', ''
    $color = Get-PathColor -TexPath $texPath

    if ($referenced[$texPath].Collection) {
        # Collection graphic: the path is a folder, and RimWorld loads every image
        # inside it. Three variants matches the vanilla stack-size convention.
        $folder = Join-Path $texturesRoot ($texPath -replace '/', '\')
        foreach ($variant in @('a', 'b', 'c')) {
            $outFile = Join-Path $folder ("{0}_{1}.png" -f $leaf, $variant)
            if ((Test-Path $outFile) -and -not $Force) { $skipped++; continue }
            if (-not $PSCmdlet.ShouldProcess($outFile, "write ${size}x${size} placeholder")) { continue }
            New-PlaceholderPng -OutFile $outFile -Size $size -Label ("{0}`n{1}" -f $label, $variant) -Color $color
            Write-Host ("  + {0}/{1}_{2}.png  ({3}x{3}, collection)" -f $texPath, $leaf, $variant, $size) -ForegroundColor Green
            $created++
        }
        continue
    }

    if ($referenced[$texPath].Multi -and -not $referenced[$texPath].Worn) {
        $base = Join-Path $texturesRoot ($texPath -replace '/', [string][char]92)
        $made = 0
        foreach ($d in @('south', 'north', 'east')) {
            $outFile = "{0}_{1}.png" -f $base, $d
            if ((Test-Path $outFile) -and -not $Force) { $skipped++; continue }
            if (-not $PSCmdlet.ShouldProcess($outFile, "write ${size}x${size} placeholder")) { continue }
            $tag = $d.Substring(0, 1).ToUpper()
            # Facing marks but opaque: unlike worn apparel there is no pawn
            # underneath to see through, and a vehicle drawn facing the wrong way
            # is still worth catching at a glance.
            New-PlaceholderPng -OutFile $outFile -Size $size -Label ("{0}`n{1}" -f $label, $tag) -Color $color -Facing $d -Opaque
            $created++; $made++
        }
        if ($made -gt 0) {
            Write-Host ("  + {0}  ({1}x{1}, directional, {2} files)" -f $texPath, $size, $made) -ForegroundColor Green
        }
        continue
    }

    if ($referenced[$texPath].Worn) {
        $base = Join-Path $texturesRoot ($texPath -replace '/', '\')

        # Always a bare base file - that is the inventory icon.
        $variants = @( @{ Suffix = ''; Tag = 'icon'; Facing = '' } )

        if ($referenced[$texPath].Body) {
            # Body apparel: one texture per body type per facing. Baby is omitted;
            # nothing here is sized for an infant.
            foreach ($bt in @('Male', 'Female', 'Thin', 'Fat', 'Hulk', 'Child')) {
                foreach ($d in @('south', 'north', 'east')) {
                    $variants += @{ Suffix = "_${bt}_${d}"; Tag = "$bt`n$($d.Substring(0,1).ToUpper())"; Facing = $d }
                }
            }
        } else {
            foreach ($d in @('south', 'north', 'east')) {
                $variants += @{ Suffix = "_$d"; Tag = $d.Substring(0, 1).ToUpper(); Facing = $d }
            }
        }

        $kind = if ($referenced[$texPath].Body) { 'body' } else { 'headgear' }
        foreach ($v in $variants) {
            $outFile = "{0}{1}.png" -f $base, $v.Suffix
            if ((Test-Path $outFile) -and -not $Force) { $skipped++; continue }
            if (-not $PSCmdlet.ShouldProcess($outFile, "write ${size}x${size} placeholder")) { continue }
            New-PlaceholderPng -OutFile $outFile -Size $size -Label ("{0}`n{1}" -f $label, $v.Tag) -Color $color -Facing $v.Facing
            $created++
        }
        Write-Host ("  + {0}  ({1}x{1}, {2}, {3} files)" -f $texPath, $size, $kind, $variants.Count) -ForegroundColor Green
        continue
    }

    $outFile = Join-Path $texturesRoot (($texPath -replace '/', '\') + '.png')
    if ((Test-Path $outFile) -and -not $Force) { $skipped++; continue }
    if (-not $PSCmdlet.ShouldProcess($outFile, "write ${size}x${size} placeholder")) { continue }

    New-PlaceholderPng -OutFile $outFile -Size $size -Label $label -Color $color
    Write-Host ("  + {0}  ({1}x{1})" -f $texPath, $size) -ForegroundColor Green
    $created++
}

# ------------------------------------------------------------------- mod art

if ($IncludeModArt) {
    $modArt = @(
        @{ Path = (Join-Path $ModRoot 'About\Preview.png');                    W = 640; H = 360; Label = 'RED RISING' }
        @{ Path = (Join-Path $ModRoot 'About\ModIcon.png');                    W = 64;  H = 64;  Label = 'RR' }
        @{ Path = (Join-Path $ModRoot 'Textures\UI\RedRisingModIcon.png');     W = 64;  H = 64;  Label = 'RR' }
    )

    foreach ($art in $modArt) {
        if ((Test-Path $art.Path) -and -not $Force) { $skipped++; continue }
        if (-not $PSCmdlet.ShouldProcess($art.Path, "write $($art.W)x$($art.H) placeholder")) { continue }

        $dir = Split-Path -Parent $art.Path
        if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

        # Non-square, so build these directly rather than via New-PlaceholderPng.
        $bmp = New-Object System.Drawing.Bitmap($art.W, $art.H)
        try {
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
                $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 92, 26, 26))
                try { $gfx.FillRectangle($bg, 0, 0, $art.W, $art.H) } finally { $bg.Dispose() }

                $font = New-Object System.Drawing.Font('Segoe UI', [Math]::Max(8, [int]($art.H / 6)), [System.Drawing.FontStyle]::Bold)
                try {
                    $fmt = New-Object System.Drawing.StringFormat
                    $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
                    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
                    $fg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 235, 200, 120))
                    try {
                        $rect = New-Object System.Drawing.RectangleF -ArgumentList ([float]0), ([float]0), ([float]$art.W), ([float]$art.H)
                        $gfx.DrawString($art.Label, $font, $fg, $rect, $fmt)
                    } finally { $fg.Dispose(); $fmt.Dispose() }
                } finally { $font.Dispose() }
            } finally { $gfx.Dispose() }
            $bmp.Save($art.Path, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bmp.Dispose() }

        Write-Host ("  + {0}  ({1}x{2})" -f (Split-Path -Leaf $art.Path), $art.W, $art.H) -ForegroundColor Green
        $created++
    }
}

Write-Host ''
Write-Host ("  {0} created, {1} already present" -f $created, $skipped)
Write-Host ''
