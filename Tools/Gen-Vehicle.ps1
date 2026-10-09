<#
.SYNOPSIS
    Regenerate the Drachenjager's sprites at high detail with fal, registered to the old ones.
.DESCRIPTION
    The user's direction (2026-10-08): vehicles are generative, like worn items and weapons. The
    existing sprites carry Vehicle Framework's layout - body 768x1024 (north/south) and 1024x768
    (east), turrets 512x512 drawn at their own drawSize - so each is the silhouette reference for
    its redraw and Tools/Clean-GenWorn.py fits the result back onto its box. One approved body view
    is the style reference for the rest. Originals are kept in Art/Gen/Vehicles/<name>/orig/.
    Resumable. The def's shader is plain Cutout, so the art keeps its own colours (no tint mask).
#>
[CmdletBinding()]
param(
    [string] $Style = 'Art/Gen/Vehicles/Drachenjager/dj_south_3.png',
    [string] $Blender = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$gen  = Join-Path $root 'Art\Gen\Vehicles\Drachenjager'
$tex  = Join-Path $root 'Textures\Things\Vehicles\RR_Drachenjager'
$style = (Resolve-Path (Join-Path $root $Style)).Path

# Canon (user, 2026-10-09): a headless boxy humanoid with a spiked backpack, the cockpit hunched
# low between the shoulders, six jointed arms with particle cannons on the elbows, ion cleavers,
# nuclear warheads. The first, crab-legged design was wrong and is not a reference.
$what = 'the Drachenjaeger: a gigantic war mech shaped like a headless boxy human - broad armoured torso, the cockpit hunched low between the shoulders in place of a head, a spiked backpack holding nuclear warheads, six jointed arms with particle cannons on the elbows, two gripping huge ion cleavers, dark steel with dull brass trim'
$pieces = [ordered]@{
    'RR_Drachenjager_south' = "$what, seen from directly ABOVE with its front at the BOTTOM of the image"
    'RR_Drachenjager_north' = "$what, seen from directly ABOVE with its front at the TOP of the image (the back of the hull towards the viewer at the bottom)"
    'RR_Drachenjager_east'  = "$what, seen from the RIGHT SIDE in profile, facing right, legs striding beneath the hull"
    'RR_Drachenjager_ParticleCannon' = 'its arm-mounted particle cannon turret seen from directly ABOVE, barrels pointing UP: a rounded armoured mount with twin long barrels, the same dark steel and brass'
    'RR_Drachenjager_WarheadRack' = 'its back-mounted warhead rack turret seen from directly ABOVE, pointing UP: an armoured mount carrying a row of four brass-tipped missiles, the same dark steel and brass'
}

foreach ($name in $pieces.Keys) {
    $keep = Join-Path $gen "orig\$name.png"
    $out  = Join-Path $gen "gen_$name.png"
    if ($name -eq 'RR_Drachenjager_south') { Copy-Item $style $out -Force }
    if (-not (Test-Path $out)) {
        $ref = Join-Path $gen "ref_$name.png"
        if ($name -like '*_east' -or $name -like '*_north') {
            # Body views: the new design only. The old crab sprite would pull the shape back.
            $p = "Draw the exact same machine as this image - $($pieces[$name]) - with exactly its design, detail, materials, rivets, seams, hydraulic joints, flat cel shading and thick black outlines. Plain flat pure white background, no text, no shadow"
            um fal edit $p --ref $style --name "gen_$name" --out $gen --model openai/gpt-image-2/edit --set quality=medium 2>&1 | Select-Object -Last 1
        } else {
            $p = "Image 1 gives the size and position on the canvas; image 2 is the machine whose style to copy. Draw $($pieces[$name]), with exactly the detail, materials, rivets, seams, flat cel shading and thick black outlines of image 2, filling about the same area as image 1. Plain flat pure white background, no text, no shadow"
            um fal edit $p --ref $ref --ref $style --name "gen_$name" --out $gen --model openai/gpt-image-2/edit --set quality=medium 2>&1 | Select-Object -Last 1
        }
        if (-not (Test-Path $out)) { Write-Warning "no image for $name"; continue }
    }
    & $Blender -b --factory-startup --python (Join-Path $PSScriptRoot 'Clean-GenWorn.py') -- $out $keep (Join-Path $tex "$name.png") --outline 4 --contain 2>&1 |
        Select-String 'WROTE|Error|Traceback' | ForEach-Object { $_.Line.Trim() }
}
Write-Host 'DONE Drachenjager'
