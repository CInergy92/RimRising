<#
.SYNOPSIS
    Repaints every procedural item sprite through Z-Image-Turbo + ControlNet.

.DESCRIPTION
    The pipeline, end to end:

        New-ItemIcons.ps1  ->  silhouette masters (4x size, for a crisp edge map)
        Canny              ->  edge map
        Z-Image-Turbo      ->  repaint at denoise 1.0, geometry pinned by ControlNet
        Convert-GeneratedSprite.ps1 -> key background, trim, resize
        contact sheet      ->  choose a candidate by number

    WHY CONTROLNET AND NOT img2img. Measured on the razor: at denoise 0.45 the
    image barely changes, at 0.65 the silhouette is gone, and nothing in between
    both restyles and keeps the shape. These turbo models are distilled to cfg 1
    and 8 steps, so they have little restyling force at low denoise and no
    obedience at high. ControlNet constrains geometry through the edge map
    instead, which frees denoise to stay at 1.0 - the model repaints completely
    and the outline still survives.

    NOTHING IS INSTALLED AUTOMATICALLY. Candidates land in a review folder with a
    contact sheet per item. Pick one, then pass -Install to copy it into Textures.

    SILHOUETTES ARE THE SOURCE OF TRUTH. They are written to Art/Silhouettes, not
    over Textures. If finished art overwrote the masters, the next run would trace
    its own output and the shapes would drift a generation at a time.

.PARAMETER Only
    Substring filter on the texture path, to redo a single item.

.PARAMETER Install
    "<leaf>=<n>" pairs naming the winning candidate, e.g. -Install RR_Razor=3.
    Copies from the review folder into Textures and does no generation.

.EXAMPLE
    .\Tools\New-GeneratedArt.ps1
    .\Tools\New-GeneratedArt.ps1 -Only Razor -Variants 6
    .\Tools\New-GeneratedArt.ps1 -Install RR_Razor=3,RR_CarvingKit=1
#>
[CmdletBinding()]
param(
    [string]   $ModRoot,
    [string]   $Only,
    [int]      $Variants = 4,
    [string[]] $Install,
    # Rebuild the contact sheets from candidates already on disk, generating
    # nothing. Useful after changing how the sheets are captioned or laid out.
    [switch]   $SheetsOnly,
    [string]   $Server = 'http://127.0.0.1:8188',
    [double]   $ControlStrength = 1.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot   = (Resolve-Path $ModRoot).Path
$silRoot   = Join-Path $ModRoot 'Art/Silhouettes'
$reviewDir = Join-Path $ModRoot 'Art/Review'
$texRoot   = Join-Path $ModRoot 'Textures'
$bs        = [string][char]92     # heredocs eat backslashes; build it explicitly

# One shared style clause. Z-Image-Turbo runs at cfg 1, so the negative prompt is
# inert - everything unwanted has to be excluded by stating what IS wanted.
$style = 'Drawn as a 2D game item sprite in the hand-painted art style of RimWorld: ' +
         'muted desaturated colours, a thick dark warm-grey outline around every form, ' +
         'soft rounded edges, one lighter highlight band along the upper left edge, ' +
         'matte hand-painted brushwork on worn well-used equipment, flat even lighting, ' +
         'plain empty black background.'

$items = @(
    [pscustomobject]@{
        Path = 'Things/Item/Equipment/WeaponMelee/RR_Razor'; Size = 256
        Subject = 'A razor: one long slender tapering blade of pale steel, with a short ' +
                  'dark leather-wrapped grip and a rounded brass pommel at the butt.'
    }
    [pscustomobject]@{
        Path = 'Things/Item/Equipment/WeaponRanged/RR_PulseFist'; Size = 256
        Subject = 'A pulse fist: a compact forearm-mounted energy weapon, a dull brass ' +
                  'body with a dark leather wrist strap and a round amber emitter aperture at the front.'
    }
    [pscustomobject]@{
        Path = 'Things/Weapons/RR_PulseCannon'; Size = 256
        Subject = 'A pulse cannon: a heavy energy weapon with a dark leather shoulder stock, ' +
                  'a long grey-steel barrel housing and a brass muzzle assembly, with a thin amber power conduit along the side.'
    }
    [pscustomobject]@{
        Path = 'Things/Item/Health/RR_CupidsKiss'; Size = 128
        Subject = 'A small bionic neural implant: a slender steel spine carrying four paired ' +
                  'rose-coloured contact pads and one amber indicator bead at its centre, a clinical medical component.'
    }
    [pscustomobject]@{
        Path = 'Things/Item/Health/RR_SynapticLattice'; Size = 128
        Subject = 'A bionic neural lattice implant: a teal hexagonal hub with six radiating ' +
                  'struts, each ending in a small steel node, a clinical medical component.'
    }
    [pscustomobject]@{
        Path = 'Things/Item/Health/RR_CarvingKit'; Size = 128
        Subject = 'A surgical tool roll: a dark brown leather case holding four upright ' +
                  'teal-handled surgical instruments, worn and stained with use.'
    }
    # The three stack variants share a seed so the set reads as one material.
    [pscustomobject]@{ Path = 'Things/Item/Resource/RR_Ionsteel/RR_Ionsteel_a'; Size = 128; Seed = 770311
        Subject = 'A single ingot of ion-steel: a blue-grey metal bar with worn chipped edges and a faint cold sheen.' }
    [pscustomobject]@{ Path = 'Things/Item/Resource/RR_Ionsteel/RR_Ionsteel_b'; Size = 128; Seed = 770311
        Subject = 'Two stacked ingots of ion-steel: blue-grey metal bars with worn chipped edges and a faint cold sheen.' }
    [pscustomobject]@{ Path = 'Things/Item/Resource/RR_Ionsteel/RR_Ionsteel_c'; Size = 128; Seed = 770311
        Subject = 'Three stacked ingots of ion-steel: blue-grey metal bars with worn chipped edges and a faint cold sheen.' }
)

# Projectiles are deliberately absent. They are 64px, are on screen for a handful
# of frames while rotating, and a 64px master upscaled 16x makes an edge map too
# soft to control anything. The procedural ones are better suited to the job.

if ($Only) { $items = @($items | Where-Object { $_.Path -like "*$Only*" }) }
if ($items.Count -eq 0) { throw "No items matched -Only '$Only'." }

# ------------------------------------------------------------------ install mode
if ($Install) {
    foreach ($spec in $Install) {
        foreach ($one in ($spec -split ',')) {
            if ($one -notmatch '^\s*(.+?)\s*=\s*(\d+)\s*$') { throw "Bad -Install spec '$one'. Expected <leaf>=<n>." }
            $leaf = $Matches[1]; $n = [int]$Matches[2]
            $item = $items | Where-Object { (Split-Path -Leaf $_.Path) -eq $leaf } | Select-Object -First 1
            if (-not $item) { throw "No item named '$leaf'." }
            $cand = Join-Path $reviewDir ("{0}_{1}.png" -f $leaf, $n)
            if (-not (Test-Path $cand)) { throw "No candidate at $cand. Generate first." }
            $dest = (Join-Path $texRoot ($item.Path -replace '/', $bs)) + '.png'
            Copy-Item -LiteralPath $cand -Destination $dest -Force
            Write-Host ("  installed  : {0} <- candidate {1}" -f $item.Path, $n) -ForegroundColor Green
        }
    }
    return
}

# --------------------------------------------------------------- generation mode
if (-not $SheetsOnly) {
    Write-Host 'Rendering flat silhouette masters at 4x...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'New-ItemIcons.ps1') -ModRoot $ModRoot -OutRoot $silRoot -Scale 4 -Flat | Out-Null
}

if (-not (Test-Path $reviewDir)) { $null = New-Item -ItemType Directory -Path $reviewDir -Force }

$sheets = @()
foreach ($item in $items) {
    $leaf = Split-Path -Leaf $item.Path
    $sil  = (Join-Path $silRoot ($item.Path -replace '/', $bs)) + '.png'
    if (-not (Test-Path $sil)) { Write-Warning "No silhouette for $($item.Path); skipping."; continue }

    Write-Host ""
    Write-Host ("=== {0}" -f $leaf) -ForegroundColor Cyan

    $seed = if ($item.PSObject.Properties['Seed']) { [int]$item.Seed } else { 0 }
    if ($SheetsOnly) {
        $n = @(Get-ChildItem -Path (Join-Path $reviewDir ("{0}_*.png" -f $leaf)) -File -ErrorAction SilentlyContinue).Count
        if ($n -eq 0) { Write-Warning "No candidates on disk for $leaf; skipping."; continue }
    }
    else {
    $raw = & (Join-Path $PSScriptRoot 'Invoke-ComfyPrompt.ps1') `
                -Pipeline zcontrol -Server $Server `
                -InitImage $sil -ControlStrength $ControlStrength `
                -Positive ($item.Subject + ' ' + $style) -Negative '' `
                -Width 1024 -Batch $Variants -Seed $seed `
                -Name $leaf -TimeoutSec 900

    $n = 0
    foreach ($file in $raw) {
        $n++
        $out = Join-Path $reviewDir ("{0}_{1}.png" -f $leaf, $n)
        & (Join-Path $PSScriptRoot 'Convert-GeneratedSprite.ps1') `
            -Path $file -OutFile $out -Size $item.Size | Out-Null
    }
    }

    # Current sprite first, so the sheet is a before/after. Cells are CAPTIONED
    # rather than numbered by position: the 'before' cell reads "now" and the
    # candidates read 1..n, so the caption on a cell is exactly what -Install
    # expects. Numbering by position would make cell N mean candidate N-1.
    $cmp = Join-Path $reviewDir ("_cmp_" + $leaf)
    if (Test-Path $cmp) { Remove-Item $cmp -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $cmp -Force
    $cur = (Join-Path $texRoot ($item.Path -replace '/', $bs)) + '.png'
    if (Test-Path $cur) { Copy-Item $cur (Join-Path $cmp '0_current.png') }
    for ($i = 1; $i -le $n; $i++) {
        Copy-Item (Join-Path $reviewDir ("{0}_{1}.png" -f $leaf, $i)) (Join-Path $cmp ("{0}_cand.png" -f $i))
    }
    $labels = @('now') + (1..$n | ForEach-Object { "$_" })
    $sheet = Join-Path $reviewDir ("sheet_{0}.png" -f $leaf)
    & (Join-Path $PSScriptRoot 'New-ContactSheet.ps1') -Path (Join-Path $cmp '*.png') `
        -Columns ($n + 1) -Cell $item.Size -Labels $labels -OutFile $sheet | Out-Null
    $sheets += $sheet
    Write-Host ("  sheet      : {0}" -f $sheet) -ForegroundColor Green
}

Write-Host ""
Write-Host "Review the sheets, then install with e.g.:" -ForegroundColor Cyan
Write-Host "  .$bs`Tools${bs}New-GeneratedArt.ps1 -Install RR_Razor=3" -ForegroundColor DarkGray
$sheets
