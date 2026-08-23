<#
.SYNOPSIS
    Reports the metabolic, complexity and archite totals for this mod's xenotypes,
    alongside vanilla's, so Colors can be balanced against real numbers.

.DESCRIPTION
    A XenotypeDef has no budget fields of its own. Its totals are the sum of its
    member genes' biostatMet / biostatCpx / biostatArc. This script does that sum,
    resolving three kinds of gene reference:

      1. GeneDefs in this mod.
      2. GeneDefs in Core, Biotech and Odyssey.
      3. Template-generated genes (AptitudeRemarkable_Mining and the like), which
         do not exist as GeneDefs in XML - the game synthesises them at runtime
         from GeneTemplateDefs. These resolve via the prefix before the first
         underscore, inheriting biostats through the template's ParentName chain.

    Case 3 is an inference, not something the game exposes. Ordering is reliable;
    treat exact figures as provisional until checked against the in-game gene
    assembler. Any gene that resolves by none of the three routes is listed in the
    Unresolved column, and a non-empty Unresolved column means the totals are wrong.

.PARAMETER GameInstall
    RimWorld install root.

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.

.PARAMETER IncludeVanilla
    Also list vanilla xenotypes, for comparison.

.EXAMPLE
    .\Tools\Get-XenotypeBudget.ps1
.EXAMPLE
    .\Tools\Get-XenotypeBudget.ps1 -IncludeVanilla
#>
[CmdletBinding()]
param(
    [string] $GameInstall = 'D:\SteamLibrary\steamapps\common\RimWorld',
    [string] $ModRoot,
    [switch] $IncludeVanilla
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

$dataRoot = Join-Path $GameInstall 'Data'
if (-not (Test-Path $dataRoot)) { throw "Cannot find '$dataRoot'. Pass -GameInstall." }

# ------------------------------------------------------------ gene index

$genes      = @{}
$templRaw   = @{}
$templParent = @{}

$geneSources = @(
    (Join-Path $dataRoot 'Core\Defs\GeneDefs')
    (Join-Path $dataRoot 'Biotech\Defs\GeneDefs')
    (Join-Path $dataRoot 'Odyssey\Defs\GeneDefs')
    (Join-Path $ModRoot  '1.6\Defs\GeneDefs')
) | Where-Object { Test-Path $_ }

# Genes also come from declared dependency mods (EyeGenes2, EBSG, Alpha Genes).
# Without these the totals silently exclude every third-party gene, which is
# worse than failing - it produces plausible but wrong numbers.
$aboutPath = Join-Path $ModRoot 'About\About.xml'
$depFiles = @()
if (Test-Path $aboutPath) {
    $aboutDoc = New-Object System.Xml.XmlDocument
    try { $aboutDoc.Load($aboutPath) } catch { $aboutDoc = $null }

    if ($aboutDoc) {
        $depIds = @()
        foreach ($n in $aboutDoc.SelectNodes('/ModMetaData/modDependencies/li/packageId')) {
            if ($n.InnerText -and $n.InnerText -notmatch '^(?i)ludeon\.rimworld') {
                $depIds += $n.InnerText.Trim().ToLowerInvariant()
            }
        }

        if ($depIds.Count -gt 0) {
            $searchRoots = @(
                (Join-Path $GameInstall 'Mods')
                (Join-Path (Split-Path -Parent (Split-Path -Parent $GameInstall)) 'workshop\content\294100')
            ) | Where-Object { Test-Path $_ }

            foreach ($root in $searchRoots) {
                Get-ChildItem -Path (Join-Path $root '*\About\About.xml') -ErrorAction SilentlyContinue | ForEach-Object {
                    $md = New-Object System.Xml.XmlDocument
                    try { $md.Load($_.FullName) } catch { return }
                    $pkgId = $md.SelectSingleNode('/ModMetaData/packageId')
                    if (-not $pkgId -or -not $pkgId.InnerText) { return }
                    if ($depIds -notcontains $pkgId.InnerText.Trim().ToLowerInvariant()) { return }

                    $modPath = Split-Path -Parent (Split-Path -Parent $_.FullName)
                    $script:depFiles += @(
                        Get-ChildItem -Path $modPath -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.FullName -match '\\Defs\\' }
                    )
                }
            }
        }
    }
}

$allGeneFiles = @(Get-ChildItem $geneSources -Filter *.xml -File) + $depFiles

foreach ($file in $allGeneFiles) {
    $doc = New-Object System.Xml.XmlDocument
    try { $doc.Load($file.FullName) } catch { continue }
    if (-not $doc.DocumentElement) { continue }

    foreach ($node in $doc.DocumentElement.ChildNodes) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

        $dnNode = $node.SelectSingleNode('defName')
        $nameAttr = $node.Attributes['Name']
        $key = if ($dnNode) { $dnNode.InnerText.Trim() }
               elseif ($nameAttr) { $nameAttr.Value.Trim() }
               else { $null }
        if (-not $key) { continue }

        $stat = {
            param($n)
            $x = $node.SelectSingleNode($n)
            if ($x) { [int]$x.InnerText } else { $null }
        }
        $rec = [pscustomobject]@{
            Met = & $stat 'biostatMet'
            Cpx = & $stat 'biostatCpx'
            Arc = & $stat 'biostatArc'
        }

        if ($node.Name -eq 'GeneDef') {
            $genes[$key] = $rec
        } elseif ($node.Name -eq 'GeneTemplateDef') {
            $templRaw[$key] = $rec
            $p = $node.Attributes['ParentName']
            if ($p) { $templParent[$key] = $p.Value.Trim() }
        }
    }
}

# Resolve template biostats through the ParentName chain: the concrete templates
# carry the numbers, but an abstract base may supply some of them.
$templates = @{}
foreach ($k in $templRaw.Keys) {
    $m = $templRaw[$k].Met; $c = $templRaw[$k].Cpx; $a = $templRaw[$k].Arc
    $cur = $k; $guard = 0
    while ($guard -lt 6 -and $templParent.ContainsKey($cur)) {
        $cur = $templParent[$cur]; $guard++
        if ($templRaw.ContainsKey($cur)) {
            if ($null -eq $m) { $m = $templRaw[$cur].Met }
            if ($null -eq $c) { $c = $templRaw[$cur].Cpx }
            if ($null -eq $a) { $a = $templRaw[$cur].Arc }
        }
    }
    $templates[$k] = [pscustomobject]@{
        Met = [int]($m ?? 0); Cpx = [int]($c ?? 0); Arc = [int]($a ?? 0)
    }
}

function Resolve-Gene {
    param([string] $Name)
    if ($genes.ContainsKey($Name)) {
        $g = $genes[$Name]
        return [pscustomobject]@{
            Met = [int]($g.Met ?? 0); Cpx = [int]($g.Cpx ?? 0); Arc = [int]($g.Arc ?? 0); Ok = $true
        }
    }
    $i = $Name.IndexOf('_')
    if ($i -gt 0) {
        $prefix = $Name.Substring(0, $i)
        if ($templates.ContainsKey($prefix)) {
            $t = $templates[$prefix]
            return [pscustomobject]@{ Met = $t.Met; Cpx = $t.Cpx; Arc = $t.Arc; Ok = $true }
        }
    }
    return [pscustomobject]@{ Met = 0; Cpx = 0; Arc = 0; Ok = $false }
}

# ------------------------------------------------------- xenotype totals

function Get-XenotypeRows {
    param([string[]] $Paths, [string] $Source)

    $rows = @()
    foreach ($file in (Get-ChildItem $Paths -Filter *.xml -File -Recurse -ErrorAction SilentlyContinue)) {
        $doc = New-Object System.Xml.XmlDocument
        try { $doc.Load($file.FullName) } catch { continue }
        if (-not $doc.DocumentElement) { continue }

        foreach ($node in $doc.DocumentElement.ChildNodes) {
            if ($node.Name -ne 'XenotypeDef') { continue }
            $dnNode = $node.SelectSingleNode('defName')
            if (-not $dnNode) { continue }

            $met = 0; $cpx = 0; $arc = 0; $count = 0
            $unresolved = @()
            foreach ($g in $node.SelectNodes('genes/li')) {
                $name = $g.InnerText.Trim()
                if (-not $name) { continue }
                $count++
                $r = Resolve-Gene -Name $name
                if ($r.Ok) { $met += $r.Met; $cpx += $r.Cpx; $arc += $r.Arc }
                else { $unresolved += $name }
            }

            $inh = $node.SelectSingleNode('inheritable')
            $wt  = $node.SelectSingleNode('factionlessGenerationWeight')

            $rows += [pscustomobject]@{
                Source     = $Source
                Xenotype   = $dnNode.InnerText.Trim()
                Genes      = $count
                Met        = $met
                Cpx        = $cpx
                Arc        = $arc
                Inherit    = if ($inh) { $inh.InnerText } else { '-' }
                Weight     = if ($wt) { $wt.InnerText } else { '-' }
                Unresolved = ($unresolved -join ',')
            }
        }
    }
    return $rows
}

$modPaths = @(Join-Path $ModRoot '1.6\Defs\GeneDefs') | Where-Object { Test-Path $_ }
$rows = @()
if ($modPaths) { $rows += Get-XenotypeRows -Paths $modPaths -Source 'mod' }

if ($IncludeVanilla) {
    $vanillaPaths = @(
        (Join-Path $dataRoot 'Biotech\Defs\GeneDefs')
        (Join-Path $dataRoot 'Odyssey\Defs\GeneDefs')
    ) | Where-Object { Test-Path $_ }
    $rows += Get-XenotypeRows -Paths $vanillaPaths -Source 'vanilla'
}

Write-Host ''
Write-Host 'Get-XenotypeBudget' -ForegroundColor Cyan
Write-Host ("  {0} gene defs, {1} gene templates indexed" -f $genes.Count, $templates.Count) -ForegroundColor DarkGray
Write-Host ''

if ($rows.Count -eq 0) {
    Write-Host '  No XenotypeDefs found.' -ForegroundColor Yellow
    Write-Host ''
    return
}

$rows | Sort-Object Source, Cpx -Descending | Format-Table -AutoSize

$broken = @($rows | Where-Object { $_.Unresolved })
if ($broken.Count -gt 0) {
    Write-Host ("  WARNING: {0} xenotype(s) reference genes that did not resolve." -f $broken.Count) -ForegroundColor Red
    Write-Host '  Their totals above are WRONG. Fix the references first.' -ForegroundColor Red
    Write-Host ''
} else {
    Write-Host '  All gene references resolved.' -ForegroundColor Green
    Write-Host '  Reminder: template-gene biostats are inferred. Confirm against the in-game gene assembler.' -ForegroundColor DarkGray
    Write-Host ''
}
