<#
.SYNOPSIS
    Draws UI icons and projectile sprites for RimRising's abilities.

.DESCRIPTION
    A third generator, with a boundary as sharp as the other two - see the icon
    ownership note in CLAUDE.md:

        New-XenotypeIcons.ps1  owns UI/Icons/Xenotypes and UI/Icons/Genes
        New-ItemIcons.ps1      owns the item/weapon silhouettes
        New-WornApparel.ps1    owns the worn apparel sprites
        New-AbilityIcons.ps1   owns the REST of UI/ - abilities, issues, memes,
                               roles, the mod icon - plus ability projectiles and
                               the biome marks

    These are NOT run through the generative art pass. A gizmo icon is read at
    32 px in a crowded button strip, where a painted illustration turns to mush and
    a flat high-contrast glyph does not. They are drawn, not generated, and they
    write straight to Textures rather than to Art/Silhouettes.

.PARAMETER OutRoot
    Where to write. Defaults to the mod's Textures tree.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [string] $OutRoot,
    # Draw only these UI paths (e.g. 'UI/Roles/RR_Role_Pilot'). Without it every
    # icon below is redrawn, which rewrites unchanged files too.
    [string[]] $Only
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
. (Join-Path $PSScriptRoot 'GlyphPrimitives.ps1')

$texRoot = if ($OutRoot) { $OutRoot } else { Join-Path $ModRoot 'Textures' }

$Outline = [System.Drawing.Color]::FromArgb(255, 30, 27, 24)
$Steel   = [System.Drawing.Color]::FromArgb(255, 196, 202, 208)
$Brass   = [System.Drawing.Color]::FromArgb(255, 198, 160,  86)

function Save-Icon {
    param([string] $RelPath, [int] $Size, [scriptblock] $Draw)
    $out = (Join-Path $texRoot ($RelPath -replace '/', [string][char]92)) + '.png'
    $dir = Split-Path -Parent $out
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)
            & $Draw $g $Size
        } finally { $g.Dispose() }
        # Bitmap.Save does NOT append an extension.
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
    Write-Host ("  + {0}" -f $RelPath) -ForegroundColor Green
}

# The whip-form gizmo and the razor-bearing issue icon are drawn by
# Tools/Draw-Weapons.py (whip_icon, razor(128)), from the same geometry as the
# weapon sprite. They were drawn here first; running this script used to put the
# stale versions back.

# The lash projectile was drawn here; the whip is no longer a projectile, and
# its line fleck is drawn by Tools/Draw-Weapons.py.

# Everything else under UI/, plus the biome marks. Drawing routines live in
# UIGlyphs.ps1, dot-sourced purely for size.
. (Join-Path $PSScriptRoot 'UIGlyphs.ps1')

$glyphs = @(
    @('UI/Issues/RR_ArmorBearing',      128, ${function:Glyph-ArmorBearing}),
    @('UI/Issues/RR_Carving',           128, ${function:Glyph-Carving}),
    @('UI/Issues/RR_ColorDeference',    128, ${function:Glyph-ColorDeference}),
    @('UI/Issues/RR_InterColorUnion',   128, ${function:Glyph-InterColorUnion}),
    @('UI/Memes/RR_ColorHierarchy',     128, ${function:Glyph-ColorHierarchy}),
    @('UI/Memes/RR_ColorEquality',      128, ${function:Glyph-ColorEquality}),
    @('UI/Memes/RR_GoldWorship',        128, ${function:Glyph-GoldWorship}),
    @('UI/Roles/RR_OlympicKnight',      128, ${function:Glyph-OlympicKnight}),
    @('UI/Roles/RR_Role_Physician', 128, ${function:Glyph-RolePhysician}),
    @('UI/Roles/RR_Role_Engineer', 128, ${function:Glyph-RoleEngineer}),
    @('UI/Roles/RR_Role_Pilot', 128, ${function:Glyph-RolePilot}),
    @('UI/Roles/RR_Role_Arbiter', 128, ${function:Glyph-RoleArbiter}),
    @('UI/Roles/RR_Role_Shaman', 128, ${function:Glyph-RoleShaman}),
    @('UI/Rituals/RR_RazorTrial', 128, ${function:Glyph-RazorTrial}),
    @('UI/Issues/RR_CasteLabor', 128, ${function:Glyph-CasteLabor}),
    @('UI/Abilities/RR_GhostCloak',     128, ${function:Glyph-GhostCloakAbility}),
    @('UI/RimRisingModIcon',             64, ${function:Glyph-ModIcon}),
    @('World/Biomes/RR_HeliumBarrens',  512, ${function:Glyph-HeliumBarrens}),
    @('World/Biomes/RR_TerraformedSteppe', 512, ${function:Glyph-TerraformedSteppe})
)

foreach ($gl in $glyphs) {
    $path = [string]$gl[0]; $size = [int]$gl[1]; $draw = $gl[2]
    if ($Only -and $path -notin $Only) { continue }
    Save-Icon $path $size $draw
}

Write-Host ''
Write-Host 'UI icons drawn. Flat glyphs on purpose: these are read at 32px in dense lists.'
