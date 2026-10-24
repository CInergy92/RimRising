<#
.SYNOPSIS
    Copies the built mod into the RimWorld Mods folder, excluding development-only files.

.DESCRIPTION
    Mirrors the repo into MODS_FOLDER\RimRising, excluding /Source, /docs, /Tools,
    .git and other development artifacts. Uses robocopy /MIR so files deleted from
    the repo are also removed from the deployed copy.

    By default this runs Test-ModDefs.ps1 first and refuses to publish if it fails.
    Nothing is a candidate for publishing until it validates.

.PARAMETER ModsFolder
    RimWorld Mods folder. Confirmed default:
    D:\SteamLibrary\steamapps\common\RimWorld\Mods

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.

.PARAMETER FolderName
    Name of the deployed folder inside Mods. Defaults to RimRising.

.PARAMETER SkipValidation
    Publish without running Test-ModDefs.ps1 first. Use sparingly.

.PARAMETER WhatIf
    Show what robocopy would do without changing anything.

.EXAMPLE
    .\Tools\Publish-Mod.ps1
.EXAMPLE
    .\Tools\Publish-Mod.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $ModsFolder = 'D:\SteamLibrary\steamapps\common\RimWorld\Mods',
    [string] $ModRoot,
    [string] $FolderName = 'RimRising',
    [switch] $SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

Write-Host ''
Write-Host 'Publish-Mod' -ForegroundColor Cyan
Write-Host ("  source : {0}" -f $ModRoot) -ForegroundColor DarkGray

if (-not (Test-Path $ModsFolder)) {
    throw "Mods folder not found: '$ModsFolder'. Pass -ModsFolder with the correct path."
}

$destination = Join-Path $ModsFolder $FolderName
Write-Host ("  dest   : {0}" -f $destination) -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------- validate first

if (-not $SkipValidation) {
    $validator = Join-Path $PSScriptRoot 'Test-ModDefs.ps1'
    if (Test-Path $validator) {
        Write-Host '  running Test-ModDefs.ps1...' -ForegroundColor DarkGray
        & $validator -ModRoot $ModRoot
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  Validation failed. Not publishing.' -ForegroundColor Red
            Write-Host '  Re-run with -SkipValidation to override.' -ForegroundColor DarkGray
            Write-Host ''
            exit 1
        }
    } else {
        Write-Host '  Test-ModDefs.ps1 not found, skipping validation.' -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------ exclusions

# Development-only trees that must never ship inside the mod.
$excludeDirs = @(
    '.git'
    '.github'
    '.vs'
    '.claude'       # Claude Code project skills - dev tooling, not mod content
    '.git-rewrite'  # left behind by an abandoned git filter-branch; holds commit records
                    # with the author's personal email, and once reached the Mods copy
    'Source'
    'docs'
    'Tools'
    'Art'           # silhouette masters and generated candidates, not shipped art
    'Extras'        # separate local mods kept in this repo (CE patches); not part of RimRising
    'obj'
    'bin'
)

# Development-only files.
$excludeFiles = @(
    '*.ps1'
    '*.md'
    '*.sln'
    '*.csproj'
    '*.user'
    '.gitignore'
    '.gitattributes'
    # Written into About/ by RimWorld's Workshop uploader (decompiled: ModMetaData.PublishedFileIdPath)
    # and needed by every later upload to update the same item. /XF also keeps /MIR from purging
    # it, so a publish after the first upload does not orphan the Workshop item.
    'PublishedFileId.txt'
)

$robocopyArgs = @(
    $ModRoot
    $destination
    '/MIR'          # mirror, so deletions propagate
    '/NFL'          # no file list
    '/NDL'          # no directory list
    '/NJH'          # no job header
    '/NP'           # no progress
    '/R:2'          # retry twice
    '/W:1'          # wait 1s between retries
)
if ($excludeDirs.Count  -gt 0) { $robocopyArgs += '/XD'; $robocopyArgs += $excludeDirs }
if ($excludeFiles.Count -gt 0) { $robocopyArgs += '/XF'; $robocopyArgs += $excludeFiles }

if ($WhatIfPreference) { $robocopyArgs += '/L' }   # list only

if (-not $PSCmdlet.ShouldProcess($destination, 'mirror mod files')) {
    # ShouldProcess already declined; with -WhatIf we still want the robocopy /L preview.
    if (-not $WhatIfPreference) { return }
}

# A running RimWorld holds the mod assembly in a memory-mapped section, so
# robocopy cannot replace it and fails with ERROR 1224 after three retries. Every
# XML file copies fine, which is the trap: the publish looks mostly successful
# while the game keeps running the OLD code. Detect it up front and say so.
$assembly = Join-Path $ModRoot '1.6\Assemblies\RimRising.dll'
if ((Test-Path $assembly) -and -not $WhatIfPreference) {
    $running = @(Get-Process -Name 'RimWorldWin64' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $deployed = Join-Path $destination '1.6\Assemblies\RimRising.dll'
        $stale = $true
        if (Test-Path $deployed) {
            $stale = (Get-Item $assembly).Length -ne (Get-Item $deployed).Length -or
                     (Get-Item $assembly).LastWriteTime -gt (Get-Item $deployed).LastWriteTime
        }

        if ($stale) {
            Write-Host ''
            Write-Host '  RimWorld is running, and the assembly has changed.' -ForegroundColor Red
            Write-Host '  A running game memory-maps the DLL, so it cannot be replaced. The XML would' -ForegroundColor DarkYellow
            Write-Host '  publish while the game kept running the OLD code - a confusing half-update.' -ForegroundColor DarkYellow
            Write-Host ''
            Write-Host '  Close RimWorld and re-run.' -ForegroundColor Yellow
            Write-Host ''
            exit 1
        }

        Write-Host '  RimWorld is running, but the assembly is unchanged - XML-only publish.' -ForegroundColor DarkGray
    }
}

Write-Host '  mirroring...' -ForegroundColor DarkGray
$output = & robocopy @robocopyArgs 2>&1
$code = $LASTEXITCODE

$output | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host ("    {0}" -f $_.ToString().Trim()) -ForegroundColor DarkGray }

# robocopy exit codes: 0-7 are success variants, 8+ are genuine failures.
if ($code -ge 8) {
    Write-Host ''
    Write-Host ("  robocopy failed with exit code {0}" -f $code) -ForegroundColor Red
    Write-Host ''
    exit 1
}

Write-Host ''
if ($WhatIfPreference) {
    Write-Host '  Preview only, nothing written.' -ForegroundColor Yellow
} else {
    Write-Host ("  Published to {0}" -f $destination) -ForegroundColor Green
    Write-Host '  Restart RimWorld, or reload mods, to pick up the change.' -ForegroundColor DarkGray
}
Write-Host ''
exit 0
