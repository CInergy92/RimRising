<#
.SYNOPSIS
    Generates the world-map textures for RimRising's custom biomes.

.DESCRIPTION
    A BiomeDef's <texture> is the flat tint painted onto its tiles on the planet
    view. Vanilla and mod biome textures are 512x512 squares of a single colour
    with a light noise grain over it - verified by measuring an installed mod's
    Textures/World/Biomes/AspenForest.png, which is exactly that.

    So this is not placeholder art in the way the weapon and apparel textures are.
    A flat tinted square IS the finished form for this asset type; only the colour
    is a judgement call.
#>
[CmdletBinding()]
param(
    [string] $ModRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Measured from a shipped biome texture, not assumed.
$size = 512

$biomes = @(
    @{ Name = 'RR_TerraformedSteppe'; R = 106; G = 122; B =  58
       Note = 'planted green, slightly yellow - a managed grassland, not a wild one' }
    @{ Name = 'RR_HeliumBarrens';     R = 150; G = 133; B = 106
       Note = 'pale dust ochre, drained of colour by hard light' }
)

$outDir = Join-Path $ModRoot 'Textures/World/Biomes'
if (-not (Test-Path $outDir)) { $null = New-Item -ItemType Directory -Path $outDir -Force }

# Fixed seed so re-running produces byte-identical files and does not churn the
# repository with meaningless diffs.
$rand = New-Object System.Random 20260824

foreach ($b in $biomes) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    try {
        for ($y = 0; $y -lt $size; $y++) {
            for ($x = 0; $x -lt $size; $x++) {
                # +/-6 of grain, matching the subtle mottling on shipped textures.
                $n = $rand.Next(-6, 7)
                $r = [Math]::Max(0, [Math]::Min(255, $b.R + $n))
                $g = [Math]::Max(0, [Math]::Min(255, $b.G + $n))
                $bl = [Math]::Max(0, [Math]::Min(255, $b.B + $n))
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $bl))
            }
        }
        $out = Join-Path $outDir ($b.Name + '.png')
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host ("  {0}.png  {1}x{1}  rgb({2},{3},{4})  - {5}" -f $b.Name, $size, $b.R, $b.G, $b.B, $b.Note) -ForegroundColor Green
    } finally {
        $bmp.Dispose()
    }
}

Write-Host ("Wrote {0} biome textures to {1}" -f $biomes.Count, $outDir) -ForegroundColor Cyan
