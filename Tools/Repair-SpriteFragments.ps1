<#
.SYNOPSIS
    Joins pieces of a sprite that came out floating loose, or removes them.

.DESCRIPTION
    Generated sprites keep producing DETACHED FRAGMENTS: a pommel that renders as a
    sphere sitting beside the grip, a blade lying next to the hand rather than in
    it. The cause is upstream - a shape with its own closed outline in the control
    image comes back as its own object - but once a piece of art is otherwise
    exactly right, regenerating it to fix one gap throws away everything good about
    it. The reference-guided rerun of the razor lost the serrated edge and thinned
    the blade into a pen.

    So this repairs the image instead. It finds every connected region of opaque
    pixels, treats the largest as the body, and for each remaining fragment either

      BRIDGES it - drawing a bar from the fragment to the nearest point of the
      body, in the body's own colours, UNDERNEATH the existing art so no detail is
      painted over - or

      REMOVES it, with -Drop.

    Colours are sampled from the sprite rather than assumed: the fill comes from
    the body pixel nearest the join, and the outline from the darkest opaque pixel
    in the image, which in this art idiom is always the outline itself.

.PARAMETER MinFragment
    Ignore regions smaller than this many pixels, so antialiasing crumbs and
    stray specks are not treated as parts of the design.

.EXAMPLE
    .\Tools\Repair-SpriteFragments.ps1 -Path razor.png -OutFile razor_fixed.png
    .\Tools\Repair-SpriteFragments.ps1 -Path razor.png -Drop
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,
    [string] $OutFile,
    [switch] $Drop,
    [int]    $MinFragment = 200,
    [double] $BridgeWidth = 0.62,
    # Below RimWorld's dark warm-grey outline (~38,34,30) and above a black
    # background. At 42 the fill treats the outline as background and flows
    # through it, which is what split the razor into six pieces.
    [int]    $Tolerance   = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Path).Path)
$w = $src.Width; $h = $src.Height
$bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose(); $src.Dispose()

$rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$bytes = New-Object byte[] ($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

# If the image is still opaque, key the background out first, same border flood
# fill as Convert-GeneratedSprite: interior darks must survive, and RimWorld's
# outline is very dark.
if ($bytes[3] -gt 8) {
    $bgB = $bytes[0]; $bgG = $bytes[1]; $bgR = $bytes[2]
    $visited = New-Object 'bool[]' ($w * $h)
    $stack = New-Object System.Collections.Generic.Stack[int]
    for ($x = 0; $x -lt $w; $x++) { $stack.Push($x); $stack.Push((($h - 1) * $w) + $x) }
    for ($y = 0; $y -lt $h; $y++) { $stack.Push($y * $w); $stack.Push(($y * $w) + $w - 1) }
    while ($stack.Count -gt 0) {
        $i = $stack.Pop()
        if ($visited[$i]) { continue }
        $visited[$i] = $true
        $px = $i % $w; $py = [math]::Floor($i / $w)
        $o = ($py * $stride) + ($px * 4)
        if ([math]::Abs($bytes[$o]     - $bgB) -gt $Tolerance) { continue }
        if ([math]::Abs($bytes[$o + 1] - $bgG) -gt $Tolerance) { continue }
        if ([math]::Abs($bytes[$o + 2] - $bgR) -gt $Tolerance) { continue }
        $bytes[$o + 3] = 0
        if ($px -gt 0)      { $stack.Push($i - 1) }
        if ($px -lt $w - 1) { $stack.Push($i + 1) }
        if ($py -gt 0)      { $stack.Push($i - $w) }
        if ($py -lt $h - 1) { $stack.Push($i + $w) }
    }
    # WRITE THE ALPHA BACK. Keying only the local byte array leaves the bitmap
    # itself fully opaque, and the composite at the end then draws that opaque
    # original straight over the bridges - producing an output pixel-identical to
    # the input while every log line claims success.
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    Write-Host '  keyed the background first (image arrived opaque)' -ForegroundColor DarkGray
}

# Label connected regions of opaque pixels.
$label = New-Object 'int[]' ($w * $h)
$sizes = New-Object 'System.Collections.Generic.List[int]'
$sizes.Add(0)                     # label 0 means unlabelled
$next = 1
$queue = New-Object System.Collections.Generic.Queue[int]
for ($i = 0; $i -lt ($w * $h); $i++) {
    if ($label[$i] -ne 0) { continue }
    $px = $i % $w; $py = [math]::Floor($i / $w)
    if ($bytes[($py * $stride) + ($px * 4) + 3] -le 8) { continue }
    $count = 0
    $label[$i] = $next
    $queue.Enqueue($i)
    while ($queue.Count -gt 0) {
        $j = $queue.Dequeue()
        $count++
        $jx = $j % $w; $jy = [math]::Floor($j / $w)
        foreach ($d in @(-1, 1, -$w, $w)) {
            $k = $j + $d
            if ($k -lt 0 -or $k -ge ($w * $h)) { continue }
            if ($d -eq -1 -and $jx -eq 0) { continue }
            if ($d -eq 1 -and $jx -eq ($w - 1)) { continue }
            if ($label[$k] -ne 0) { continue }
            $kx = $k % $w; $ky = [math]::Floor($k / $w)
            if ($bytes[($ky * $stride) + ($kx * 4) + 3] -le 8) { continue }
            $label[$k] = $next
            $queue.Enqueue($k)
        }
    }
    $sizes.Add($count)
    $next++
}

$real = @()
for ($n = 1; $n -lt $sizes.Count; $n++) { if ($sizes[$n] -ge $MinFragment) { $real += $n } }
if ($real.Count -eq 0) { throw 'No opaque regions found. Is the image blank?' }

$main = $real[0]
foreach ($n in $real) { if ($sizes[$n] -gt $sizes[$main]) { $main = $n } }
$fragments = @($real | Where-Object { $_ -ne $main })

Write-Host ("  regions    : {0} (body {1:N0} px, {2} fragment(s))" -f $real.Count, $sizes[$main], $fragments.Count) -ForegroundColor DarkGray
if ($fragments.Count -eq 0) {
    Write-Host '  nothing detached - image already whole.' -ForegroundColor Green
}

# The outline colour is the darkest opaque pixel in this idiom.
$darkR = 255; $darkG = 255; $darkB = 255; $darkSum = 1000
for ($y = 0; $y -lt $h; $y += 2) {
    for ($x = 0; $x -lt $w; $x += 2) {
        $o = ($y * $stride) + ($x * 4)
        if ($bytes[$o + 3] -le 200) { continue }
        $sum = [int]$bytes[$o] + $bytes[$o + 1] + $bytes[$o + 2]
        if ($sum -lt $darkSum) { $darkSum = $sum; $darkB = $bytes[$o]; $darkG = $bytes[$o + 1]; $darkR = $bytes[$o + 2] }
    }
}

$bmp.UnlockBits($data)

if ($Drop -and $fragments.Count -gt 0) {
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    foreach ($f in $fragments) {
        for ($i = 0; $i -lt ($w * $h); $i++) {
            if ($label[$i] -ne $f) { continue }
            $px = $i % $w; $py = [math]::Floor($i / $w)
            $bytes[($py * $stride) + ($px * 4) + 3] = 0
        }
        Write-Host ("  removed    : fragment of {0:N0} px" -f $sizes[$f]) -ForegroundColor Yellow
    }
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    $bmp.UnlockBits($data)
}
elseif ($fragments.Count -gt 0) {
    # Bridges are drawn on their own layer and the original art composited OVER
    # them, so a bar can fill the gap without covering any existing detail.
    $under = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $ug = [System.Drawing.Graphics]::FromImage($under)
    $ug.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    foreach ($f in $fragments) {
        # Fragment centroid, and its rough radius from the pixel count.
        $sx = 0.0; $sy = 0.0
        for ($i = 0; $i -lt ($w * $h); $i++) {
            if ($label[$i] -ne $f) { continue }
            $sx += $i % $w; $sy += [math]::Floor($i / $w)
        }
        $fcx = $sx / $sizes[$f]; $fcy = $sy / $sizes[$f]
        $frad = [math]::Sqrt($sizes[$f] / [math]::PI)

        # Nearest body pixel to that centroid.
        $bestD = [double]::MaxValue; $bx = 0; $by = 0
        for ($i = 0; $i -lt ($w * $h); $i++) {
            if ($label[$i] -ne $main) { continue }
            $px = $i % $w; $py = [math]::Floor($i / $w)
            $dx = $px - $fcx; $dy = $py - $fcy
            $d = ($dx * $dx) + ($dy * $dy)
            if ($d -lt $bestD) { $bestD = $d; $bx = $px; $by = $py }
        }

        # Fill colour sampled a little inside the body from the join, so the bar
        # matches the material it grows out of instead of picking up its outline.
        $data2 = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        [System.Runtime.InteropServices.Marshal]::Copy($data2.Scan0, $bytes, 0, $bytes.Length)
        $bmp.UnlockBits($data2)
        $vx = $bx - $fcx; $vy = $by - $fcy
        $vl = [math]::Sqrt(($vx * $vx) + ($vy * $vy)); if ($vl -lt 1) { $vl = 1 }
        $ix = [int][math]::Round($bx + (($vx / $vl) * ($frad * 0.9)))
        $iy = [int][math]::Round($by + (($vy / $vl) * ($frad * 0.9)))
        $ix = [math]::Max(0, [math]::Min($w - 1, $ix)); $iy = [math]::Max(0, [math]::Min($h - 1, $iy))
        $o = ($iy * $stride) + ($ix * 4)
        $fill = if ($bytes[$o + 3] -gt 200) {
            [System.Drawing.Color]::FromArgb(255, $bytes[$o + 2], $bytes[$o + 1], $bytes[$o])
        } else {
            [System.Drawing.Color]::FromArgb(255, 150, 150, 150)
        }

        $bw = [single]($frad * 2 * $BridgeWidth)
        $outline = [System.Drawing.Color]::FromArgb(255, $darkR, $darkG, $darkB)
        $p1 = New-Object System.Drawing.PointF([single]$fcx, [single]$fcy)
        $p2 = New-Object System.Drawing.PointF([single]$bx, [single]$by)

        $pen = New-Object System.Drawing.Pen($outline, [single]($bw + ($w * 0.022)))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $ug.DrawLine($pen, $p1, $p2); $pen.Dispose()

        $pen = New-Object System.Drawing.Pen($fill, $bw)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $ug.DrawLine($pen, $p1, $p2); $pen.Dispose()

        Write-Host ("  bridged    : fragment of {0:N0} px at ({1:N0},{2:N0}) to body at ({3},{4}), bar {5:N0} px" -f `
            $sizes[$f], $fcx, $fcy, $bx, $by, $bw) -ForegroundColor Green
    }

    $ug.DrawImage($bmp, 0, 0, $w, $h)
    $ug.Dispose()
    $bmp.Dispose()
    $bmp = $under
}

if (-not $OutFile) {
    $dir = Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path
    $OutFile = Join-Path $dir ([System.IO.Path]::GetFileNameWithoutExtension($Path) + '_repaired.png')
}
if ([System.IO.Path]::GetExtension($OutFile) -eq '') { $OutFile += '.png' }
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("  wrote      : {0}" -f $OutFile) -ForegroundColor Green
$OutFile
