<#
.SYNOPSIS
    Finds vanilla defs to mirror: by defName, by def type, or by a field they contain.
.DESCRIPTION
    Greps the game's Data/*/Defs tree and prints file:line for each hit, so a session can
    open a real example of the same type before writing a def. Searches every DLC folder,
    so the result says which DLC a thing belongs to - which matters for MayRequire.
.PARAMETER DefName
    Exact defName to find, e.g. Cobra. Prints the file and the line of its <defName>.
.PARAMETER DefType
    Def element name, e.g. ThingDef, GeneDef. Lists files containing at least one.
    Combine with -Contains to narrow to defs of that type whose FILE also contains the text.
.PARAMETER Contains
    Literal text to look for, e.g. "<plant>" or "growMinGlow". Prints file:line.
.PARAMETER GameInstall
    RimWorld install root. Verified default: D:\SteamLibrary\steamapps\common\RimWorld
.EXAMPLE
    .\Find-VanillaDef.ps1 -DefName Cobra
.EXAMPLE
    .\Find-VanillaDef.ps1 -DefType ThingDef -Contains "<plant>"
.EXAMPLE
    .\Find-VanillaDef.ps1 -Contains backstoryFiltersOverride
#>
[CmdletBinding()]
param(
    [string] $DefName,
    [string] $DefType,
    [string] $Contains,
    [string] $GameInstall = 'D:\SteamLibrary\steamapps\common\RimWorld'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dataRoot = Join-Path $GameInstall 'Data'
if (-not (Test-Path $dataRoot)) {
    Write-Error "No Data folder at $dataRoot. Pass -GameInstall, or, in a cloud session, clone a reference mod instead (see CLAUDE.md)."
}

# Backstories live in Data/Core/Backstories, not under Defs, so search both.
$files = Get-ChildItem -Path $dataRoot -Recurse -Filter *.xml -File |
    Where-Object { $_.FullName -match '[\\/](Defs|Backstories)[\\/]' }

function Show-Hit {
    param($Match)
    $rel = $Match.Path.Substring($dataRoot.Length).TrimStart('\', '/')
    Write-Host ("{0}:{1}  {2}" -f $rel, $Match.LineNumber, $Match.Line.Trim())
}

if ($DefName) {
    $pattern = [regex]::Escape("<defName>$DefName</defName>")
    $hits = $files | Select-String -Pattern $pattern
    if (-not $hits) { Write-Host "No def named $DefName under $dataRoot"; exit 1 }
    $hits | ForEach-Object { Show-Hit $_ }
    exit 0
}

if ($DefType -and -not $Contains) {
    $pattern = "<$DefType[\s>]"
    $files | Select-String -Pattern $pattern -List | ForEach-Object {
        Write-Host ($_.Path.Substring($dataRoot.Length).TrimStart('\', '/'))
    }
    exit 0
}

if ($Contains) {
    $candidates = $files
    if ($DefType) {
        $candidates = $files | Select-String -Pattern "<$DefType[\s>]" -List | ForEach-Object { Get-Item $_.Path }
    }
    $hits = $candidates | Select-String -SimpleMatch -Pattern $Contains
    if (-not $hits) { Write-Host "Nothing contains '$Contains'"; exit 1 }
    $hits | ForEach-Object { Show-Hit $_ }
    exit 0
}

Write-Host 'Give -DefName, -DefType, or -Contains. See the help header.'
exit 1
