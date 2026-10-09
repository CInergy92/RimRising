<#
.SYNOPSIS
    Regenerate one worn-apparel set at high detail with fal, registered to its measured sprites.
.DESCRIPTION
    The user's direction (2026-10-08): worn items, weapons and vehicles are generative. The
    flat-panel sprites from Tools/Draw-PanelArmor.py stay the registration target: each one is
    the SILHOUETTE reference for its redraw, and Tools/Clean-GenWorn.py fits the result back
    onto it. One approved image of the set (normally Male south) is the STYLE reference for
    every other body type and facing, so the set reads as one piece of kit.

    For every <Prefix>_<Body>_<facing>.png in the base texture folder and, if present, the
    Realistic Body folder:
      1. the original sprite is kept in Art/Gen/<Set>/orig[RB]/ (first run only) - it is the
         fit target on every rerun;
      2. it is composited onto white (Tools/Prep-GenRef.py) and redrawn with
         openai/gpt-image-2/edit, refs = [silhouette, style];
      3. Tools/Clean-GenWorn.py fits it back, rebuilds the dye mask (-Dyed), outlines it.
    Resumable: a generation already on disk is reused, so a rerun only fills the gaps.
.EXAMPLE
    pwsh -File Tools/Gen-WornSet.ps1 -Set Pulse -Prefix RR_PulseArmor -Style Art/Gen/Armor/Pulse/gen_Male_south_2.png -Dyed -Desc "..."
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Set,
    [Parameter(Mandatory)] [string] $Prefix,
    [Parameter(Mandatory)] [string] $Style,
    [Parameter(Mandatory)] [string] $Desc,
    [switch] $Dyed,
    [string] $Folder = $Prefix,
    [string] $Blender = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root  = Split-Path $PSScriptRoot -Parent
$gen   = Join-Path $root "Art\Gen\Armor\$Set"
$style = (Resolve-Path (Join-Path $root $Style)).Path
$targets = @(
    @{ Tex = Join-Path $root "Textures\Things\Pawn\Humanlike\Apparel\$Folder"; Tag = '';   Legs = $false }
    @{ Tex = Join-Path $root "1.6\Mods\RealisticBody\Textures\Things\Pawn\Humanlike\Apparel\$Folder"; Tag = 'RB'; Legs = $true }
)
$views = @{
    south = 'seen from the FRONT'
    east  = 'seen from the RIGHT SIDE (profile, facing right)'
    north = 'seen from BEHIND (back view)'
}
$colour = if ($Dyed) { 'The dyed plates must be GOLD; everything else keeps the colours of image 2.' }
          else       { 'Keep the colours of image 2 exactly.' }

foreach ($t in $targets) {
    if (-not (Test-Path $t.Tex)) { continue }
    $orig = Join-Path $gen ("orig" + $t.Tag)
    New-Item -ItemType Directory -Force $orig | Out-Null
    $sprites = Get-ChildItem $t.Tex -Filter "$Prefix`_*_*.png" |
        Where-Object { $_.BaseName -match "^$([regex]::Escape($Prefix))_(\w+)_(south|east|north)$" }
    foreach ($sp in $sprites) {
        $null = $sp.BaseName -match "^$([regex]::Escape($Prefix))_(\w+?)_(south|east|north)$"   # lazy: \w swallows underscores
        $body, $facing = $Matches[1], $Matches[2]
        if ($body -eq 'Child') { continue }   # unreachable: apparel is adult-only by default (CLAUDE.md)
        $keep = Join-Path $orig $sp.Name
        if (-not (Test-Path $keep)) { Copy-Item $sp.FullName $keep }

        $stem = "gen$($t.Tag)_$body`_$facing"
        $out  = Join-Path $gen "$stem.png"
        if (-not (Test-Path $out)) {
            $ref = Join-Path $gen "ref$($t.Tag)_$body`_$facing.png"
            & $Blender -b --factory-startup --python (Join-Path $PSScriptRoot 'Prep-GenRef.py') -- $keep $ref 2>&1 | Out-Null
            $legs = if ($t.Legs) { ' Here the armour also covers both legs down to the feet; keep that leg armour.' } else { '' }
            $prompt = "Image 1 is the silhouette to keep; image 2 is the style to copy. Redraw the armour in image 1 - $Desc, $($views[$facing]) - with exactly the detail, materials, bevels, seams, rivets, flat cel shading and thick black outlines of image 2. KEEP image 1's exact silhouette, size and position on the canvas and its layout.$legs $colour Draw ONLY the armour: no person, no head, no hands, empty white where the body would show. Plain flat pure white background, no text, no shadow"
            um fal edit $prompt --ref $ref --ref $style --name $stem --out $gen --model openai/gpt-image-2/edit --set quality=medium 2>&1 | Select-Object -Last 1
            if (-not (Test-Path $out)) { Write-Warning "no image for $stem"; continue }
        }
        $args2 = @($out, $keep, $sp.FullName)
        if ($Dyed) { $args2 += '--dyed' }
        & $Blender -b --factory-startup --python (Join-Path $PSScriptRoot 'Clean-GenWorn.py') -- @args2 2>&1 |
            Select-String 'WROTE|Error|Traceback' | ForEach-Object { $_.Line.Trim() }
    }
}
Write-Host "DONE $Set"
