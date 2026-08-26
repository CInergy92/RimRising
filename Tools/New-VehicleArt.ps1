<#
.SYNOPSIS
    Repaints the Drachenjaeger's five sprites through Z-Image-Turbo + ControlNet.

.DESCRIPTION
    Same pipeline as New-GeneratedArt.ps1, with three differences that matter:

    NON-SQUARE OUTPUT. Vehicle bodies are 128 px per drawSize unit with north and
    south portrait and east landscape, so the converter is driven by explicit
    -OutWidth/-OutHeight rather than a single square size.

    NO TRIMMING, NO MARGIN. Turret render offsets are measured from the vehicle's
    centre. Trimming each facing to its own content box would scale and shift the
    three sprites differently and slide the turrets off the arms, so the frame is
    kept exactly as generated.

    ONLY ONE FACING IS GENERATED. The other two are ROTATIONS OF THE FINISHED ART.

    Generating all three from rotated control maps on a shared seed was not enough:
    a shared seed does not force a shared design when the control image differs, so
    the three facings came back with different brass work and different cockpits -
    recognisably three machines. Since the east and south control maps were already
    rotations of the north one, rotating the finished sprite instead costs nothing
    geometrically and makes the three facings identical by construction.

    The trade is that lighting rotates with the sprite. That is why the prompt asks
    for flat even lighting: with no strong light direction there is nothing in the
    image that rotating can contradict.

.EXAMPLE
    .\Tools\New-VehicleArt.ps1
    .\Tools\New-VehicleArt.ps1 -Install RR_Drachenjager_north=2
#>
[CmdletBinding()]
param(
    [string]   $ModRoot,
    [string]   $Only,
    [int]      $Variants = 4,
    [string[]] $Install,
    [switch]   $SheetsOnly,
    [string]   $Server = 'http://127.0.0.1:8188',
    [double]   $ControlStrength = 0.85,
    [int]      $Seed = 4471902
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot   = (Resolve-Path $ModRoot).Path
$silRoot   = Join-Path $ModRoot 'Art/Silhouettes'
$reviewDir = Join-Path $ModRoot 'Art/Review'
$texRoot   = Join-Path $ModRoot 'Textures'
$bs        = [string][char]92

$style = 'Muted desaturated grey-blue steel armour with dull brass fittings and worn ' +
         'scuffed paint, a thick dark warm-grey outline around every form, soft rounded ' +
         'edges, flat even lighting, hand-painted 2D game sprite in the art style of ' +
         'RimWorld, plain empty black background, no shadow.'

$mech = 'Overhead top-down view, seen from directly above, of a huge six-armed armoured ' +
        'battle walker: a boxy headless torso with a sunken cockpit canopy set between the ' +
        'shoulders, three arms down each side each ending in a particle cannon, a rack of ' +
        'spikes across its back, two heavy legs, and a long blade held out to one side. '

# South is the master facing and the only body sprite generated. North and east
# are derived from whichever south candidate gets installed.
#
#   north = south turned 180
#   east  = south turned 270 clockwise
#
# which follows from how the silhouettes are built: east is north turned 90 and
# south is north turned 180, so east is south turned 270.
$items = @(
    [pscustomobject]@{ Path='Things/Vehicles/RR_Drachenjager/RR_Drachenjager_south'
                       W=768; H=1024; Subject=$mech }
    [pscustomobject]@{ Path='Things/Vehicles/RR_Drachenjager/RR_Drachenjager_north'
                       W=768; H=1024; Subject=$mech
                       DerivedFrom='RR_Drachenjager_south'; Rotate='Rotate180FlipNone' }
    [pscustomobject]@{ Path='Things/Vehicles/RR_Drachenjager/RR_Drachenjager_east'
                       W=1024; H=768; Subject=$mech
                       DerivedFrom='RR_Drachenjager_south'; Rotate='Rotate270FlipNone' }
    [pscustomobject]@{ Path='Things/Vehicles/RR_Drachenjager/RR_Drachenjager_ParticleCannon'
                       W=512; H=512
                       Subject='Overhead top-down view, seen from directly above, of a twin-barrelled ' +
                               'particle cannon turret: two long parallel barrels pointing away, a compact ' +
                               'breech block behind them and a round pivot ring at the centre. ' }
    [pscustomobject]@{ Path='Things/Vehicles/RR_Drachenjager/RR_Drachenjager_WarheadRack'
                       W=512; H=512
                       Subject='Overhead top-down view, seen from directly above, of a four-tube missile ' +
                               'launcher rack: four launch tubes side by side with brass warhead noses ' +
                               'pointing away, a heavy mounting block and a round pivot ring at the centre. ' }
)

if ($Only) { $items = @($items | Where-Object { $_.Path -like "*$Only*" }) }
if ($items.Count -eq 0) { throw "No vehicle sprites matched -Only '$Only'." }

if ($Install) {
    foreach ($spec in $Install) {
        foreach ($one in ($spec -split ',')) {
            if ($one -notmatch '^\s*(.+?)\s*=\s*(\d+)\s*$') { throw "Bad -Install spec '$one'. Expected <leaf>=<n>." }
            $leaf = $Matches[1]; $n = [int]$Matches[2]
            $item = $items | Where-Object { (Split-Path -Leaf $_.Path) -eq $leaf } | Select-Object -First 1
            if (-not $item) { throw "No vehicle sprite named '$leaf'." }
            $cand = Join-Path $reviewDir ("{0}_{1}.png" -f $leaf, $n)
            if (-not (Test-Path $cand)) { throw "No candidate at $cand." }
            if ($item.PSObject.Properties['DerivedFrom']) {
                throw "$leaf is derived from $($item.DerivedFrom) and is not installed directly. Install the master and the rotations are written for you."
            }
            $dest = (Join-Path $texRoot ($item.Path -replace '/', $bs)) + '.png'
            # A brand new sprite has no folder yet, and Copy-Item will not make one.
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path $destDir)) { $null = New-Item -ItemType Directory -Path $destDir -Force }
            Copy-Item -LiteralPath $cand -Destination $dest -Force
            Write-Host ("  installed  : {0} <- candidate {1}" -f $item.Path, $n) -ForegroundColor Green

            # Write every facing derived from this one, so the three can never
            # drift apart: they are the same pixels, turned.
            Add-Type -AssemblyName System.Drawing
            foreach ($d in $items) {
                if (-not $d.PSObject.Properties['DerivedFrom']) { continue }
                if ($d.DerivedFrom -ne $leaf) { continue }
                $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $dest).Path)
                try {
                    $rot = New-Object System.Drawing.Bitmap($img)
                    $rot.RotateFlip([System.Drawing.RotateFlipType]::($d.Rotate))
                    $dd = (Join-Path $texRoot ($d.Path -replace '/', $bs)) + '.png'
                    $rot.Save($dd, [System.Drawing.Imaging.ImageFormat]::Png)
                    Write-Host ("  derived    : {0} ({1}, {2}x{3})" -f $d.Path, $d.Rotate, $rot.Width, $rot.Height) -ForegroundColor Green
                    $rot.Dispose()
                } finally { $img.Dispose() }
            }
        }
    }
    return
}

if (-not $SheetsOnly) {
    Write-Host 'Rendering flat vehicle silhouettes...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'New-VehicleIcons.ps1') -ModRoot $ModRoot -OutRoot $silRoot -Flat | Out-Null
}
if (-not (Test-Path $reviewDir)) { $null = New-Item -ItemType Directory -Path $reviewDir -Force }

$sheets = @()
foreach ($item in $items) {
    $leaf = Split-Path -Leaf $item.Path
    if ($item.PSObject.Properties['DerivedFrom']) {
        Write-Host ("  {0}: derived from {1} at install time, not generated." -f $leaf, $item.DerivedFrom) -ForegroundColor DarkGray
        continue
    }
    $sil  = (Join-Path $silRoot ($item.Path -replace '/', $bs)) + '.png'
    if (-not (Test-Path $sil)) { Write-Warning "No silhouette for $($item.Path); skipping."; continue }

    Write-Host ''
    Write-Host ("=== {0}  ({1}x{2})" -f $leaf, $item.W, $item.H) -ForegroundColor Cyan

    $n = 0
    if ($SheetsOnly) {
        $n = @(Get-ChildItem -Path (Join-Path $reviewDir ("{0}_*.png" -f $leaf)) -File -ErrorAction SilentlyContinue).Count
        if ($n -eq 0) { Write-Warning "No candidates on disk for $leaf; skipping."; continue }
    }
    else {
        # A 768x1024 body at batch 4 with ControlNet attached faults the GPU
        # ("RuntimeError: Fault failed: 2" out of KSampler). The turrets are a
        # quarter of the pixels and are fine at full batch, so cap by area rather
        # than lowering it for everything.
        $batch = $Variants
        if (($item.W * $item.H) -gt (640 * 640)) { $batch = [Math]::Min($Variants, 2) }
        $long = [Math]::Max($item.W, $item.H)
        $raw = & (Join-Path $PSScriptRoot 'Invoke-ComfyPrompt.ps1') `
                    -Pipeline zcontrol -Server $Server `
                    -InitImage $sil -ControlStrength $ControlStrength `
                    -Positive ($item.Subject + $style) -Negative '' `
                    -Width $long -Batch $batch -Seed $Seed `
                    -Name $leaf -TimeoutSec 1200
        foreach ($file in $raw) {
            $n++
            $out = Join-Path $reviewDir ("{0}_{1}.png" -f $leaf, $n)
            # NoTrim and no margin: the frame has to survive exactly as generated.
            & (Join-Path $PSScriptRoot 'Convert-GeneratedSprite.ps1') `
                -Path $file -OutFile $out -OutWidth $item.W -OutHeight $item.H `
                -NoTrim -Margin 0 | Out-Null
        }
    }

    $cmp = Join-Path $reviewDir ("_cmp_" + $leaf)
    if (Test-Path $cmp) { Remove-Item $cmp -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $cmp -Force
    $cur = (Join-Path $texRoot ($item.Path -replace '/', $bs)) + '.png'
    # Track whether a 'before' cell actually exists. A brand new sprite has no
    # current texture, and prepending 'now' unconditionally then shifts every
    # caption by one - so candidate 1 gets labelled 'now' and -Install installs
    # the wrong image. This is the same off-by-one the captions were added to
    # prevent in the first place.
    $hasCurrent = Test-Path $cur
    if ($hasCurrent) { Copy-Item $cur (Join-Path $cmp '0_current.png') }
    for ($i = 1; $i -le $n; $i++) {
        Copy-Item (Join-Path $reviewDir ("{0}_{1}.png" -f $leaf, $i)) (Join-Path $cmp ("{0}_cand.png" -f $i))
    }
    $labels = @(); if ($hasCurrent) { $labels += 'now' }; $labels += (1..$n | ForEach-Object { "$_" })
    $sheet = Join-Path $reviewDir ("sheet_{0}.png" -f $leaf)
    & (Join-Path $PSScriptRoot 'New-ContactSheet.ps1') -Path (Join-Path $cmp '*.png') `
        -Columns $(if ($hasCurrent) { $n + 1 } else { $n }) -Cell 340 -Labels $labels -OutFile $sheet | Out-Null
    $sheets += $sheet
    Write-Host ("  sheet      : {0}" -f $sheet) -ForegroundColor Green
}

Write-Host ''
Write-Host 'Review, then install with e.g.:' -ForegroundColor Cyan
Write-Host "  pwsh -File Tools/New-VehicleArt.ps1 -Install RR_Drachenjager_north=2" -ForegroundColor DarkGray
$sheets
