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
        [System.Drawing.Color] $Color
    )

    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    try {
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $gfx.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

            $brush = New-Object System.Drawing.SolidBrush($Color)
            try { $gfx.FillRectangle($brush, 0, 0, $Size, $Size) } finally { $brush.Dispose() }

            # Border, so the sprite's extent is obvious against any background.
            $penWidth = [Math]::Max(2, [int]($Size / 32))
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 255, 255, 255), $penWidth)
            try {
                $half = [int][Math]::Ceiling($penWidth / 2)
                $gfx.DrawRectangle($pen, $half, $half, $Size - ($half * 2) - 1, $Size - ($half * 2) - 1)
            } finally { $pen.Dispose() }

            # Label, wrapped and centered. Small icons get a shortened label.
            $text = if ($Size -le 64 -and $Label.Length -gt 10) { $Label.Substring(0, 10) } else { $Label }
            $fontSize = [Math]::Max(6, [int]($Size / 12))
            $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold)
            try {
                $fmt = New-Object System.Drawing.StringFormat
                $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
                $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
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

        # Apparel drawn ON a pawn needs per-facing textures: <path>_north, _south
        # and _east, plus a bare <path> for the inventory icon. A single flat file
        # is not enough and the game throws a missing-texture error the moment the
        # apparel is equipped rather than at load, so nothing catches it until a
        # pawn puts it on.
        #
        # Verified against installed mods: AirwireHeadset ships _east, _north,
        # _south and a base file in one folder.
        $isWorn = ($node.Name -eq 'wornGraphicPath') -or
                  ($key -like 'Things/Pawn/Humanlike/Apparel/*')

        if ($referenced.ContainsKey($key)) {
            $referenced[$key].Collection = $referenced[$key].Collection -or $isCollection
            $referenced[$key].Worn       = $referenced[$key].Worn -or $isWorn
        } else {
            $referenced[$key] = @{ Collection = $isCollection; Worn = $isWorn }
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

    if ($referenced[$texPath].Worn) {
        # Worn apparel: one texture per facing, plus a bare base file for the
        # inventory icon. Facing is labelled so a mis-rotated sprite is obvious.
        $base = Join-Path $texturesRoot ($texPath -replace '/', '\')
        $variants = @(
            @{ Suffix = '';       Tag = 'icon' }
            @{ Suffix = '_south'; Tag = 'S' }
            @{ Suffix = '_north'; Tag = 'N' }
            @{ Suffix = '_east';  Tag = 'E' }
        )
        foreach ($v in $variants) {
            $outFile = "{0}{1}.png" -f $base, $v.Suffix
            if ((Test-Path $outFile) -and -not $Force) { $skipped++; continue }
            if (-not $PSCmdlet.ShouldProcess($outFile, "write ${size}x${size} placeholder")) { continue }
            New-PlaceholderPng -OutFile $outFile -Size $size -Label ("{0}`n{1}" -f $label, $v.Tag) -Color $color
            Write-Host ("  + {0}{1}.png  ({2}x{2}, worn)" -f $texPath, $v.Suffix, $size) -ForegroundColor Green
            $created++
        }
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
