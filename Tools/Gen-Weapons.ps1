<#
.SYNOPSIS
    Regenerate the weapon sprites at high detail with fal, registered to the measured ones.
.DESCRIPTION
    The user's direction (2026-10-08): weapons are generative. The code-drawn sprites
    (Tools/Draw-Weapons.py, Tools/Draw-Ranged.py) carry the measured orientation - melee
    diagonal lower-left to upper-right, guns horizontal with the muzzle right - and, for the
    razors, the geometry Melee Animation's tweak data was derived from. Each is the silhouette
    reference for its redraw, and Tools/Clean-GenWorn.py fits the result back onto its box, so
    pommel and tip land where they were. Re-derive the razors' tweak data afterwards anyway
    (Tools/Derive-MeleeTweak.py); a redraw can move the grip along the axis.

    Originals are kept in Art/Gen/Weapons/orig/ on the first run and are the fit target on every
    rerun. Resumable: an existing generation is reused.
#>
[CmdletBinding()]
param(
    [string[]] $Only,
    [string] $Blender = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$gen  = Join-Path $root 'Art\Gen\Weapons'
$orig = Join-Path $gen 'orig'
New-Item -ItemType Directory -Force $orig | Out-Null

$weapons = [ordered]@{
    'RR_Razor' = @('Things\Item\Equipment\WeaponMelee\RR_Razor',
        'a razor: a long slender flexible whip-sword blade (like an urumi) of pale polished steel with faint segment joints along it, a brass-fitted dark wrapped grip, a round brass pommel and a small amber thumb stud; lying diagonally from lower-left (pommel) to upper-right (tip)')
    'RR_ReaperRazor' = @('Things\Item\Equipment\WeaponMelee\RR_ReaperRazor',
        'the same kind of razor set into a sickle: a crescent blade of pale polished steel on a short brass-fitted dark grip with a round brass pommel and an amber thumb stud; grip at the lower left')
    'RR_RazorHeirloom' = @('Things\Item\Equipment\WeaponMelee\RR_RazorHeirloom',
        'an HEIRLOOM razor of an old Gold house (user, 2026-10-09: Golds put their family history or a great battle on the hilt and blade): the same long slender whip-sword blade (like an urumi) of pale polished steel, its whole length inlaid with an intricate fine GOLD frieze of a battle - tiny warriors, ships and a sun in thin gold lines along the flat of the blade; the hilt and pommel heavy GOLD, densely engraved with a family tree and crest, set with a deep red stone; lying diagonally from lower-left (pommel) to upper-right (tip)')
    'RR_SlingBlade' = @('Things\Item\Equipment\WeaponMelee\RR_SlingBlade',
        'a slingBlade, a miner''s tool: a curved hooked steel blade like a sickle, scratched and well sharpened, on a short dark haft wrapped in worn cloth tape with two steel ferrules; haft at the lower left, the hook at the upper right')
    'RR_PulseFist' = @('Things\Item\Equipment\WeaponRanged\RR_PulseFist',
        'a pulseFist: an armoured gold gauntlet worn on the forearm, a closed fist under the housing and a glowing cyan emitter ring at the front; lying horizontal, emitter pointing right')
    'RR_Scorcher' = @('Things\Item\Equipment\WeaponRanged\RR_Scorcher',
        'a scorcher: a cheap boxy grey energy carbine with a skeletal stock, a short barrel ringed with orange heat coils and vent slots; lying horizontal, muzzle pointing right')
    'RR_PulseCannon' = @('Things\Weapons\RR_PulseCannon',
        'a pulse cannon: a heavy suit-mounted energy cannon with a boxy grey housing, a shoulder brace, a thick barrel with three brass emitter collars and a cyan glowing muzzle; lying horizontal, muzzle pointing right')
}

foreach ($name in $weapons.Keys) {
    if ($Only -and $name -notin $Only) { continue }
    $rel, $desc = $weapons[$name]
    $tex  = Join-Path $root "Textures\$rel.png"
    $keep = Join-Path $orig "$name.png"
    if (-not (Test-Path $keep)) { Copy-Item $tex $keep }
    $out = Join-Path $gen "gen_$name.png"
    if (-not (Test-Path $out)) {
        $ref = Join-Path $gen "ref_$name.png"
        & $Blender -b --factory-startup --python (Join-Path $PSScriptRoot 'Prep-GenRef.py') -- $keep $ref 2>&1 | Out-Null
        $p = "Redraw this RimWorld weapon sprite with far more detail and craftsmanship, as a professional RimWorld mod artist would. It is $desc. KEEP the exact same silhouette, orientation, size and position on the canvas. Add bevels, engraving, rivets and wear, with flat cel shading lit from the upper left, thick pure black outlines and muted RimWorld colours. Only the weapon, no hands. Plain flat pure white background, no text, no shadow"
        um fal edit $p --ref $ref --name "gen_$name" --out $gen --model openai/gpt-image-2/edit --set quality=medium --n 2 2>&1 | Select-Object -Last 1
    }
}
Write-Host "GENERATED - review gen_<name>.png and gen_<name>_2.png, then fit the chosen one with Tools/Clean-GenWorn.py <gen> orig/<name>.png <texture> --outline 2"
