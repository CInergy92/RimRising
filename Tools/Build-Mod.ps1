<#
.SYNOPSIS
    Builds the C# assembly into 1.6/Assemblies.

.DESCRIPTION
    Wraps `dotnet build` for Source/RimRising. The project targets net472 because
    RimWorld runs on Unity's Mono, and pulls reference assemblies from NuGet rather
    than requiring a .NET Framework targeting pack.

    Source/NuGet.config pins nuget.org for this folder only, because this machine's
    global NuGet config resolves to an offline Visual Studio feed that does not
    carry Microsoft.NETFramework.ReferenceAssemblies.

.PARAMETER Configuration
    Build configuration. Default Release.

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.

.EXAMPLE
    .\Tools\Build-Mod.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',
    [string] $ModRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

$project = Join-Path $ModRoot 'Source\RimRising\RimRising.csproj'

Write-Host ''
Write-Host 'Build-Mod' -ForegroundColor Cyan
Write-Host ("  project : {0}" -f $project) -ForegroundColor DarkGray
Write-Host ("  config  : {0}" -f $Configuration) -ForegroundColor DarkGray

if (-not (Test-Path $project)) {
    Write-Host '  No C# project found. Nothing to build.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

Write-Host ''
& dotnet build $project -c $Configuration --nologo
$code = $LASTEXITCODE

if ($code -ne 0) {
    Write-Host ''
    Write-Host ("  Build FAILED (exit {0})" -f $code) -ForegroundColor Red
    Write-Host ''
    exit 1
}

$dll = Join-Path $ModRoot '1.6\Assemblies\RimRising.dll'
if (Test-Path $dll) {
    $info = Get-Item $dll
    Write-Host ("  -> {0} ({1:N1} KB, {2})" -f $info.FullName, ($info.Length / 1KB), $info.LastWriteTime) -ForegroundColor Green
} else {
    Write-Host '  Build reported success but no DLL was produced. Check OutputPath.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

Write-Host ''
exit 0
