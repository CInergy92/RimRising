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

$PackageId = 'cinergy92.redrising'
$ModName   = 'Red Rising'
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

# ------------------------------------------------------------- block splitting

# RimWorld writes each error as a message line followed by an indented stack
# trace, with blank lines between entries.
$blocks = [System.Collections.Generic.List[object]]::new()
$current = [System.Collections.Generic.List[string]]::new()
$startLine = 1

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) {
        if ($current.Count -gt 0) {
            $blocks.Add([pscustomobject]@{ Line = $startLine; Text = $current.ToArray() })
            $current.Clear()
        }
        $startLine = $i + 2
        continue
    }
    if ($current.Count -eq 0) { $startLine = $i + 1 }
    $current.Add($line)
}
if ($current.Count -gt 0) {
    $blocks.Add([pscustomobject]@{ Line = $startLine; Text = $current.ToArray() })
}

# ------------------------------------------------------------- classification

# Patterns that mark a block as a red error in RimWorld's log.
$errorPatterns = @(
    'Could not resolve cross-reference'
    'Could not find a type named'
    'Could not load UnityEngine.Texture2D at'
    'XML error'
    'Config error in'
    'Exception'
    'error in .*: '
    '^\s*Error'
    'Failed to '
    'Unknown field'
    'Duplicate .* def'
    'defName .* is '
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

$errorBlocks = @($blocks | Where-Object { ($_.Text -join "`n") -match $errorRegex })
$mineBlocks  = @($errorBlocks | Where-Object { ($_.Text -join "`n") -match $mineRegex })

Write-Host ("  {0} error block(s) in log, {1} attributable to this mod" -f $errorBlocks.Count, $mineBlocks.Count) -ForegroundColor DarkGray
Write-Host ''

$toShow = if ($All) { $errorBlocks } else { $mineBlocks }

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
    $joined = $block.Text -join "`n"
    $isMine = $joined -match $mineRegex

    $tag   = if ($isMine) { 'OURS ' } else { 'other' }
    $color = if ($isMine) { 'Red' } else { 'DarkGray' }

    Write-Host ("  [{0}] Player.log:{1}" -f $tag, $block.Line) -ForegroundColor $color

    $shown = 0
    foreach ($line in $block.Text) {
        if ($shown -ge ($Context + 1)) {
            Write-Host ("        ... {0} more line(s)" -f ($block.Text.Count - $shown)) -ForegroundColor DarkGray
            break
        }
        Write-Host ("        {0}" -f $line.TrimEnd()) -ForegroundColor $color
        $shown++
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
