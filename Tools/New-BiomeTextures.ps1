<#
.SYNOPSIS
    Draws the seamless terrain patterns for this mod's two biomes.

.DESCRIPTION
    WHAT WENT WRONG BEFORE. BiomeDef.texture is not an icon. Decompiling
    BiomeDef.DrawMaterial shows it is assigned straight to mainTexture on a
    WorldTerrain material, which is TILED across the planet's hexes:

        cachedMat = MaterialAllocator.Create(WorldMaterials.WorldTerrain);
        cachedMat.mainTexture = ContentFinder<Texture2D>.Get(texture);

    The placeholder that filled this slot was an illustrated landscape - a green
    hill with a thick dark outline on a transparent field. Tiled, its outline
    became black bands and its hill became green bars, which is precisely what
    the planet looked like: striped patches that read as a broken texture,
    because they were one.

    So these are patterns, not pictures. Three rules follow from that:

      SEAMLESS. Every component is periodic over the image by construction - the
      low-frequency mottle is a sum of sines whose wavelengths divide the width
      exactly, so the left edge continues into the right with no seam to find.
      Nothing here is drawn with a brush, because a brush stroke near an edge
      cannot wrap.

      FULLY OPAQUE, EDGE TO EDGE. Any transparency shows the bare world sphere
      through it.

      NO OUTLINES AND LOW CONTRAST. At world zoom a tile is a few pixels; strong
      internal edges alias into exactly the banding being fixed. Amplitudes here
      are deliberately small - this is a surface, not a subject.
#>
[CmdletBinding()]
param(
    [string] $ModRoot,
    [int]    $Size = 512
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path
$sep = [string][char]92

function Write-BiomeTexture {
    param(
        [string] $Leaf,
        [int[]]  $Base,          # r,g,b
        [double] $Mottle,        # low-frequency amplitude
        [double] $Grain,         # per-pixel amplitude
        [double] $RowStripe,     # amplitude of a faint regular banding, 0 for none
        [int]    $Seed
    )

    $rand = New-Object System.Random($Seed)
    $w = $Size; $h = $Size

    # Written through LockBits rather than SetPixel: a quarter of a million
    # per-pixel calls through the interop layer takes minutes, and the same work
    # against a byte array takes about a second.
    $bmp  = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $data.Stride
        $buf = New-Object byte[] ($stride * $h)

        # Precompute a per-pixel grain field so it is stable and cheap.
        $tau = [Math]::PI * 2.0

        for ($y = 0; $y -lt $h; $y++) {
            $fy = $y / [double]$h
            $row = $y * $stride
            for ($x = 0; $x -lt $w; $x++) {
                $fx = $x / [double]$w

                # INTEGER wavelengths only - that is what makes it wrap. Three
                # octaves so the result reads as ground rather than as a ripple.
                $n  = [Math]::Sin($tau * 3 * $fx) * [Math]::Cos($tau * 2 * $fy)
                $n += 0.6 * [Math]::Sin($tau * 7 * $fx + 1.3) * [Math]::Cos($tau * 5 * $fy + 0.7)
                $n += 0.35 * [Math]::Sin($tau * 13 * $fx + 2.1) * [Math]::Cos($tau * 11 * $fy + 1.9)
                $n = $n / 1.95

                $d = $n * $Mottle

                if ($RowStripe -gt 0) {
                    # Faint regular banding: this biome is engineered farmland, and
                    # a whisper of field rows says so without becoming a pattern
                    # anybody consciously notices.
                    $d += [Math]::Sin($tau * 24 * $fy) * $RowStripe
                }

                $d += ($rand.NextDouble() - 0.5) * 2.0 * $Grain

                $i = $row + ($x * 4)
                # BGRA order.
                $buf[$i    ] = [byte][math]::Max(0, [math]::Min(255, [math]::Round($Base[2] + $d)))
                $buf[$i + 1] = [byte][math]::Max(0, [math]::Min(255, [math]::Round($Base[1] + $d)))
                $buf[$i + 2] = [byte][math]::Max(0, [math]::Min(255, [math]::Round($Base[0] + $d)))
                $buf[$i + 3] = 255
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $buf.Length)
    } finally { $bmp.UnlockBits($data) }

    $dir = (Join-Path $ModRoot 'Textures'), 'World', 'Biomes' -join $sep
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $out = ($dir, ($Leaf + '.png') -join $sep)
    try { $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
    Write-Host ("  + World/Biomes/{0}  ({1}x{1})" -f $Leaf, $Size) -ForegroundColor Green
}

# Terraformed steppe: fertile engineered grassland. Muted olive-green, and the
# only one that gets the row banding, because it is farmland laid out to a plan.
Write-BiomeTexture -Leaf 'RR_TerraformedSteppe' -Base @(104, 122,  76) `
                   -Mottle 13 -Grain 5 -RowStripe 3.5 -Seed 91

# Helium barrens: mined-out dust. Dull red-brown, more mottle and more grain, no
# banding at all - nothing laid this out.
Write-BiomeTexture -Leaf 'RR_HeliumBarrens' -Base @(132, 104,  84) `
                   -Mottle 17 -Grain 7 -RowStripe 0 -Seed 44
