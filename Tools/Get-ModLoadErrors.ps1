<#
.SYNOPSIS
    Reads the RimWorld player log and surfaces only the errors attributable to this mod.

.DESCRIPTION
    RimWorld's Player.log mixes our errors in with those of every other active mod.
    This script splits the log into blocks, classifies each as an error or not, and
    then keeps only the blocks that name this mod: its packageId, its mod name, its
    folder, or any defName carrying our RR_ prefix.

    Attribution is a heuristic, not a guarantee. A def-resolution error caused by our
    mod can be reported in terms of a vanilla def name and carry no marker of ours at
    all. Use -All when a run looks clean but the game still misbehaves.

.PARAMETER LogPath
    Player log. Verified default:
    %LOCALAPPDATA%\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log

.PARAMETER Previous
    Read Player-prev.log instead, i.e. the run before the current one.

.PARAMETER All
    Show every error block in the log, not just ours. Ours stay highlighted.

.PARAMETER Context
    Lines of trailing context to show per block. Default 4.

.EXAMPLE
    .\Tools\Get-ModLoadErrors.ps1
.EXAMPLE
    .\Tools\Get-ModLoadErrors.ps1 -All -Context 10
#>
[CmdletBinding()]
param(
    [string] $LogPath,
    [switch] $Previous,
    [switch] $All,
    [int]    $Context = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageId = 'cinergy92.rimrising'
$ModName   = 'RimRising'
$DefPrefix = 'RR_'
$FolderName = 'RimRising'

if (-not $LogPath) {
    $logDir = Join-Path $env:USERPROFILE 'AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios'
    $LogPath = Join-Path $logDir ($(if ($Previous) { 'Player-prev.log' } else { 'Player.log' }))
}

Write-Host ''
Write-Host 'Get-ModLoadErrors' -ForegroundColor Cyan
Write-Host ("  log : {0}" -f $LogPath) -ForegroundColor DarkGray

if (-not (Test-Path $LogPath)) {
    Write-Host ''
    Write-Host ("  Log not found: {0}" -f $LogPath) -ForegroundColor Red
    Write-Host '  Launch RimWorld at least once, then re-run.' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

$logInfo = Get-Item $LogPath
$age = (Get-Date) - $logInfo.LastWriteTime
Write-Host ("  age : {0:N1} hour(s) old, written {1}" -f $age.TotalHours, $logInfo.LastWriteTime) -ForegroundColor DarkGray
if ($age.TotalHours -gt 12) {
    Write-Host '  WARNING: this log is stale. It may predate your latest changes.' -ForegroundColor Yellow
}

$lines = Get-Content -Path $LogPath -Encoding UTF8

# -------------------------------------------------------------- error location

# RimWorld's log does NOT reliably separate entries with blank lines - the whole
# startup header arrives as one unbroken run. Splitting on blank lines therefore
# produced enormous blocks and smeared attribution across unrelated mods. The
# unit here is the matching LINE, with a few following lines as context.

# ------------------------------------------------------------- classification

# Patterns that mark a block as a red error in RimWorld's log.
#
# NOTE: several real RimWorld errors contain none of the words "error",
# "exception" or "failed". "Collection cannot init: No textures found at path X"
# is one, and this tool missed it on the first run while the bug was live. Add a
# pattern whenever a real error slips through rather than assuming coverage.
$errorPatterns = @(
    'Could not resolve cross-reference'
    'Could not find a type named'
    'Could not load'
    'XML error'
    'Config error in'
    'Exception'
    'error in .*: '
    '^\s*Error'
    'Failed to '
    'Unknown field'
    'Duplicate .* def'
    'defName .* is '
    # texture and graphic failures
    'Collection cannot init'
    'No textures found at path'
    'Could not get texture at path'
    'Texture .* not found'
    'Graphic .* not found'
    # def and content failures
    'cannot init'
    'is null or empty'
    'Missing .*Def'
    'tried to (get|find|use)'
)
$errorRegex = ($errorPatterns -join '|')

# Patterns that attribute a block to this mod.
$minePatterns = @(
    [regex]::Escape($PackageId)
    [regex]::Escape($ModName)
    [regex]::Escape($FolderName)
    [regex]::Escape($DefPrefix)
)
$mineRegex = ($minePatterns -join '|')

$errorBlocks = [System.Collections.Generic.List[object]]::new()

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch $errorRegex) { continue }

    $end = [Math]::Min($lines.Count - 1, $i + $Context)
    $text = $lines[$i..$end]

    # Attribute on the matching line plus its context, not on the whole file.
    $isMine = (($text -join "`n") -match $mineRegex)

    $errorBlocks.Add([pscustomobject]@{
        Line   = $i + 1
        Text   = $text
        IsMine = $isMine
    })
}

$errorBlocks = @($errorBlocks)
$mineBlocks  = @($errorBlocks | Where-Object { $_.IsMine })

Write-Host ("  {0} error block(s) in log, {1} attributable to this mod" -f $errorBlocks.Count, $mineBlocks.Count) -ForegroundColor DarkGray
Write-Host ''

# Comma operator: an if-expression returning an empty array unrolls to $null.
$toShow = if ($All) { , $errorBlocks } else { , $mineBlocks }

if ($toShow.Count -eq 0) {
    if ($All) {
        Write-Host '  No errors of any kind in this log.' -ForegroundColor Green
    } else {
        Write-Host '  No errors attributable to this mod.' -ForegroundColor Green
        if ($errorBlocks.Count -gt 0) {
            Write-Host ("  ({0} error(s) from other mods or vanilla. Re-run with -All to see them.)" -f $errorBlocks.Count) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    exit 0
}

foreach ($block in $toShow) {
    $tag   = if ($block.IsMine) { 'OURS ' } else { 'other' }
    $color = if ($block.IsMine) { 'Red' } else { 'DarkGray' }

    Write-Host ("  [{0}] Player.log:{1}" -f $tag, $block.Line) -ForegroundColor $color

    $first = $true
    foreach ($line in $block.Text) {
        $prefix = if ($first) { '      > ' } else { '        ' }
        Write-Host ("{0}{1}" -f $prefix, $line.TrimEnd()) -ForegroundColor $(if ($first) { $color } else { 'DarkGray' })
        $first = $false
    }
    Write-Host ''
}

if ($mineBlocks.Count -gt 0) {
    Write-Host ("  {0} error(s) attributable to this mod. Not clean." -f $mineBlocks.Count) -ForegroundColor Red
    Write-Host ''
    exit 1
}

Write-Host ''
exit 0
