<#
.SYNOPSIS
    Makes a generated apparel ICON safe to tint, and writes its mask.

.DESCRIPTION
    THE SAME BUG THE WORN SPRITES HAD. CompColorable multiplies the whole texture
    by one dye, so an item icon painted deep crimson can only ever get darker and
    redder under a caste colour. The worn sprites were fixed by redrawing them on
    a neutral base; the icons cannot be redrawn, because they are ControlNet
    output that was chosen by eye and regenerating them would produce a different
    weapon.

    So this transforms the icon instead, which keeps the artwork exactly:

      1. Pixels that should take the dye are DESATURATED, preserving luminance.
         (206,202,194)-grade neutral x a gold dye is gold; crimson x gold is mud.
      2. Pixels that should keep their own colour - the emitter teal and the gold
         trim - are left untouched.
      3. A mask is written naming which is which.

    MASK NAMING DIFFERS BY GRAPHIC CLASS, and getting it wrong fails silently.
    Decompiled:

      Graphic_Single.MaskSuffix = "_m"   ->  RR_PulseArmor_m.png
      Graphic_Multi              "m"     ->  RR_PulseArmor_Male_southm.png

    Both are loaded with reportFailure: false, so a wrong name is not an error -
    the shader simply dyes everything, which is the bug you were fixing.

    The def must also carry <shaderType>CutoutComplex</shaderType> in its
    graphicData; unlike apparel, an item icon has no useWornGraphicMask flag to
    swap the shader for it.

.PARAMETER Icon
    Path to the icon PNG, relative to the mod root or absolute.

.PARAMETER WhatIf
    Report the classification without writing anything.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string[]] $Icon,
    [string] $ModRoot,
    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

# Hue windows for the two things that must survive a caste dye. Taken from the
# generated icons themselves rather than picked: the emitter reads about 180 and
# the trim about 45.
$TealLo  = 150.0; $TealHi  = 215.0
$GoldLo  =  28.0; $GoldHi  =  65.0

$MaskDyed  = [System.Drawing.Color]::FromArgb(255, 255, 0, 0)
$MaskFixed = [System.Drawing.Color]::FromArgb(255,   0, 0, 0)

foreach ($rel in $Icon) {
    $path = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $ModRoot $rel }
    if (-not (Test-Path $path)) { Write-Host "  ! not found: $rel" -ForegroundColor Red; continue }
    $path = (Resolve-Path $path).Path

    # Loaded through a MemoryStream, NOT Bitmap.FromFile. FromFile keeps the file
    # open for the lifetime of the Bitmap, so saving back over the same path
    # throws "A generic error occurred in GDI+" - which is GDI's way of saying
    # almost anything, and here means the file is locked by the object writing it.
    $bytes  = [System.IO.File]::ReadAllBytes($path)
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    $src = [System.Drawing.Bitmap]::FromStream($stream)
    try {
        $w = $src.Width; $h = $src.Height
        $out  = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $mask = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $dyed = 0; $fixed = 0
            for ($y = 0; $y -lt $h; $y++) {
                for ($x = 0; $x -lt $w; $x++) {
                    $p = $src.GetPixel($x, $y)
                    if ($p.A -eq 0) {
                        $out.SetPixel($x, $y, $p)
                        $mask.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                        continue
                    }

                    $hue = $p.GetHue()
                    $sat = $p.GetSaturation()
                    $keep = ($sat -gt 0.15) -and (
                              (($hue -ge $TealLo) -and ($hue -le $TealHi)) -or
                              (($hue -ge $GoldLo) -and ($hue -le $GoldHi)))

                    if ($keep) {
                        # Left exactly as painted, and marked black so the dye
                        # skips it.
                        $out.SetPixel($x, $y, $p)
                        $mask.SetPixel($x, $y, $MaskFixed)
                        $fixed++
                    } else {
                        # Desaturate to the SAME luminance rather than to the
                        # average of the channels. Rec. 601 weights, because a
                        # flat average turns saturated red into a mid grey and
                        # loses every bit of the panel shading with it.
                        $lum = [int][math]::Round(
                            (0.299 * $p.R) + (0.587 * $p.G) + (0.114 * $p.B))
                        # Nudged up: multiplying by a dye only ever darkens, so a
                        # base that already sits mid-grey produces a muddy result
                        # even when it is neutral.
                        $lum = [int][math]::Min(255, [math]::Round($lum * 1.35) + 26)
                        $out.SetPixel($x, $y,
                            [System.Drawing.Color]::FromArgb($p.A, $lum, $lum, $lum))
                        $mask.SetPixel($x, $y, $MaskDyed)
                        $dyed++
                    }
                }
            }

            $maskPath = [System.IO.Path]::ChangeExtension($path, $null).TrimEnd('.') + '_m.png'
            $pct = if (($dyed + $fixed) -gt 0) { (100.0 * $fixed / ($dyed + $fixed)) } else { 0 }
            Write-Host ("  {0}  dyed {1}px, kept {2}px ({3:N1}% accent)" -f `
                (Split-Path $path -Leaf), $dyed, $fixed, $pct) -ForegroundColor Green

            if ($WhatIf) {
                Write-Host "    -WhatIf: nothing written" -ForegroundColor DarkGray
            } else {
                $out.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
                $mask.Save($maskPath, [System.Drawing.Imaging.ImageFormat]::Png)
                Write-Host ("    + {0}" -f (Split-Path $maskPath -Leaf)) -ForegroundColor DarkGray
            }
        } finally { $out.Dispose(); $mask.Dispose() }
    } finally { $src.Dispose(); $stream.Dispose() }
}
