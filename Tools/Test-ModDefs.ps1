<#
.SYNOPSIS
    Validates every XML file under Defs/ and Patches/ before the mod is loaded by RimWorld.

.DESCRIPTION
    Runs five checks and returns a non-zero exit code if any of them fail:

      1. Malformed XML.
      2. Duplicate defName values within this mod.
      3. defName values that collide with a vanilla (Core or DLC) def.
      4. Texture paths referenced by a def with no matching file under Textures/.
      5. ParentName references that resolve to no Name= def, in this mod or vanilla.

    The vanilla def index is expensive to build (thousands of files), so it is
    cached under Tools/.cache/ and keyed on the game's Version.txt. Use
    -RefreshVanillaCache to force a rebuild after a game update.

.PARAMETER GameInstall
    RimWorld install root. Verified default: D:\SteamLibrary\steamapps\common\RimWorld

.PARAMETER ModRoot
    Repo root. Defaults to the parent of the folder holding this script.

.PARAMETER RefreshVanillaCache
    Rebuild the vanilla def index even if a valid cache exists.

.EXAMPLE
    .\Tools\Test-ModDefs.ps1
.EXAMPLE
    .\Tools\Test-ModDefs.ps1 -RefreshVanillaCache
#>
[CmdletBinding()]
param(
    [string] $GameInstall = 'D:\SteamLibrary\steamapps\common\RimWorld',
    [string] $ModRoot,
    [switch] $RefreshVanillaCache
)

# PowerShell's XML adapter shadows XmlElement.Name with the element's Name=
# ATTRIBUTE whenever one is present, so $node.Name on <ThingDef Name="Gun_Revolver">
# returns "Gun_Revolver", not "ThingDef". Every type test in this file therefore
# uses .LocalName. Using .Name silently skips every def carrying Name=, which in
# vanilla is 838 of them - the checks pass and inspect nothing.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModRoot) { $ModRoot = Split-Path -Parent $PSScriptRoot }
$ModRoot = (Resolve-Path $ModRoot).Path

# ---------------------------------------------------------------- diagnostics

$script:Problems = [System.Collections.Generic.List[object]]::new()

function Add-Problem {
    param(
        [ValidateSet('ERROR', 'WARN')] [string] $Severity,
        [string] $Check,
        [string] $File,
        [string] $Message
    )
    $script:Problems.Add([pscustomobject]@{
        Severity = $Severity
        Check    = $Check
        File     = $File
        Message  = $Message
    })
}

function Get-RelativePath {
    param([string] $Path, [string] $Base = $ModRoot)
    $Path -replace [regex]::Escape($Base + [IO.Path]::DirectorySeparatorChar), ''
}

# --------------------------------------------------------- vanilla def index

# List-valued ThingDef fields that append on inherit. Re-declaring a value an
# ancestor already has duplicates it. thingCategories is the one RimWorld actually
# reports ("has duplicate thingCategory X"); the rest fail silently.
$script:InheritedListFields = @(
    'thingCategories'
    'weaponClasses'
    'weaponTags'
    'tradeTags'
    'thingSetMakerTags'
    'techHediffsTags'
)

function Build-VanillaIndex {
    param([string] $DataRoot)

    $defNames  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $nameAttrs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $geneDefs  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $geneTemplates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $vanillaTexPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Hair genes that actually set a colour. Hair_ShortOnly / Hair_BaldOnly are
    # STYLE genes and set none, so a caste carrying only one of those still rolls
    # a random hair colour - which for a mod whose whole premise is that hair
    # reads the caste is a silent failure, not a cosmetic one.
    $hairColorGenes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    # Tags a PawnKindDef can ask for. A kind requesting a tag no THING carries
    # spawns the pawn with no weapon or no clothes and logs absolutely nothing.
    $weaponTags  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $apparelTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    # Abstract (Name=) defs and the list-valued fields they declare, so a child can
    # be checked for re-declaring something it already inherits. RimWorld APPENDS
    # list fields on inherit rather than replacing them, so a duplicate entry is
    # silently created - and for thingCategories it becomes a load-time config error.
    $abstracts = @{}

    $files = Get-ChildItem -Path $DataRoot -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -match '\\Defs\\' }

    Write-Host ("  indexing {0} vanilla XML files..." -f $files.Count) -ForegroundColor DarkGray

    foreach ($f in $files) {
        $doc = New-Object System.Xml.XmlDocument
        $doc.PreserveWhitespace = $false
        try { $doc.Load($f.FullName) } catch { continue }   # vanilla is assumed sound
        if (-not $doc.DocumentElement) { continue }

        foreach ($node in $doc.DocumentElement.ChildNodes) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

            $dn = $node.SelectSingleNode('defName')
            if ($dn -and $dn.InnerText) {
                $name = $dn.InnerText.Trim()
                [void]$defNames.Add($name)
                if ($node.LocalName -eq 'GeneDef')         {
                    [void]$geneDefs.Add($name)
                    if ($node.SelectSingleNode('hairColorOverride')) { [void]$hairColorGenes.Add($name) }
                }
                if ($node.LocalName -eq 'GeneTemplateDef') { [void]$geneTemplates.Add($name) }
            }

            # Tag vocabularies, taken from the things that CARRY the tags
            # (ThingDef/weaponTags and ThingDef/apparel/tags), never from the
            # PawnKindDefs that request them - otherwise a typo would validate
            # itself.
            if ($node.LocalName -eq 'ThingDef') {
                foreach ($li in $node.SelectNodes('weaponTags/li')) {
                    if ($li.InnerText) { [void]$weaponTags.Add($li.InnerText.Trim()) }
                }
                foreach ($li in $node.SelectNodes('apparel/tags/li')) {
                    if ($li.InnerText) { [void]$apparelTags.Add($li.InnerText.Trim()) }
                }
            }

            $na = $node.Attributes['Name']
            if ($na -and $na.Value) {
                $absName = $na.Value.Trim()
                [void]$nameAttrs.Add($absName)

                $pn = $node.Attributes['ParentName']
                $entry = @{
                    Parent = if ($pn) { $pn.Value.Trim() } else { $null }
                    Lists  = @{}
                }
                foreach ($lf in $script:InheritedListFields) {
                    $listNode = $node.SelectSingleNode($lf)
                    if (-not $listNode) { continue }
                    # Inherit="False" replaces rather than appends, so a child
                    # re-declaring under it is legitimate.
                    $inh = $listNode.Attributes['Inherit']
                    if ($inh -and $inh.Value -eq 'False') { continue }
                    $vals = @()
                    foreach ($li in $listNode.SelectNodes('li')) {
                        if ($li.InnerText) { $vals += $li.InnerText.Trim() }
                    }
                    if ($vals.Count -gt 0) { $entry.Lists[$lf] = $vals }
                }
                if (-not $abstracts.ContainsKey($absName)) { $abstracts[$absName] = $entry }
            }

            # Every texture path vanilla itself references. Vanilla art lives in
            # asset bundles so we cannot check the filesystem, but a path vanilla
            # uses is certainly real - and a non-RR_ path that appears NOWHERE in
            # vanilla is almost certainly a typo or an invention.
            foreach ($tex in $node.SelectNodes('.//*')) {
                if (-not (Test-IsTexturePathNode $tex.LocalName)) { continue }
                if ($tex.ChildNodes.Count -ne 1) { continue }
                if ([string]::IsNullOrWhiteSpace($tex.InnerText)) { continue }
                [void]$vanillaTexPaths.Add(($tex.InnerText.Trim() -replace '\\', '/').TrimStart('/'))
            }
        }
    }

    [pscustomobject]@{
        DefNames      = @($defNames)
        NameAttrs     = @($nameAttrs)
        GeneDefs      = @($geneDefs)
        GeneTemplates = @($geneTemplates)
        TexPaths      = @($vanillaTexPaths)
        HairColorGenes= @($hairColorGenes)
        WeaponTags    = @($weaponTags)
        ApparelTags   = @($apparelTags)
        Abstracts     = $abstracts
    }
}

function Get-VanillaIndex {
    param([string] $GameInstall, [switch] $Refresh)

    $versionFile = Join-Path $GameInstall 'Version.txt'
    if (-not (Test-Path $versionFile)) {
        throw "Cannot find Version.txt at '$versionFile'. Pass -GameInstall with the correct path."
    }
    $version = (Get-Content $versionFile -Raw).Trim()

    $cacheDir = Join-Path $PSScriptRoot '.cache'
    if (-not (Test-Path $cacheDir)) { $null = New-Item -ItemType Directory -Path $cacheDir }
    $cacheFile = Join-Path $cacheDir 'vanilla-defs.json'

    # Bumped whenever the cached shape changes, so an old cache is rebuilt rather
    # than read with missing fields.
    $cacheSchema = 6

    if (-not $Refresh -and (Test-Path $cacheFile)) {
        try {
            $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cached.Version -eq $version -and $cached.Schema -eq $cacheSchema) {
                Write-Host ("  vanilla index: cache hit ({0} defs, {1} genes, game {2})" -f $cached.DefNames.Count, $cached.GeneDefs.Count, $version) -ForegroundColor DarkGray
                return [pscustomobject]@{
                    DefNames      = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.DefNames, [StringComparer]::Ordinal)
                    NameAttrs     = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.NameAttrs, [StringComparer]::Ordinal)
                    GeneDefs      = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.GeneDefs, [StringComparer]::Ordinal)
                    GeneTemplates = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.GeneTemplates, [StringComparer]::Ordinal)
                    TexPaths      = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.TexPaths, [StringComparer]::OrdinalIgnoreCase)
                    HairColorGenes= [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.HairColorGenes, [StringComparer]::Ordinal)
                    WeaponTags    = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.WeaponTags, [StringComparer]::Ordinal)
                    ApparelTags   = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.ApparelTags, [StringComparer]::Ordinal)
                    Abstracts     = $cached.Abstracts
                    Version       = $version
                }
            }
            Write-Host ("  vanilla index: stale (cached {0}, installed {1}) - rebuilding" -f $cached.Version, $version) -ForegroundColor Yellow
        } catch {
            Write-Host '  vanilla index: cache unreadable - rebuilding' -ForegroundColor Yellow
        }
    }

    $dataRoot = Join-Path $GameInstall 'Data'
    if (-not (Test-Path $dataRoot)) { throw "Cannot find '$dataRoot'." }

    $idx = Build-VanillaIndex -DataRoot $dataRoot
    [pscustomobject]@{
        Version       = $version
        Schema        = $cacheSchema
        DefNames      = $idx.DefNames
        NameAttrs     = $idx.NameAttrs
        GeneDefs      = $idx.GeneDefs
        GeneTemplates = $idx.GeneTemplates
        TexPaths      = $idx.TexPaths
        HairColorGenes= $idx.HairColorGenes
        WeaponTags    = $idx.WeaponTags
        ApparelTags   = $idx.ApparelTags
        Abstracts     = $idx.Abstracts
    } | ConvertTo-Json -Depth 8 -Compress | Set-Content -Path $cacheFile -Encoding UTF8

    Write-Host ("  vanilla index: built ({0} defs, {1} abstract names, {2} genes, {3} gene templates)" -f $idx.DefNames.Count, $idx.NameAttrs.Count, $idx.GeneDefs.Count, $idx.GeneTemplates.Count) -ForegroundColor DarkGray

    [pscustomobject]@{
        DefNames      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.DefNames, [StringComparer]::Ordinal)
        NameAttrs     = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.NameAttrs, [StringComparer]::Ordinal)
        GeneDefs      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.GeneDefs, [StringComparer]::Ordinal)
        GeneTemplates = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.GeneTemplates, [StringComparer]::Ordinal)
        TexPaths      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.TexPaths, [StringComparer]::OrdinalIgnoreCase)
        HairColorGenes= [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.HairColorGenes, [StringComparer]::Ordinal)
        WeaponTags    = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.WeaponTags, [StringComparer]::Ordinal)
        ApparelTags   = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.ApparelTags, [StringComparer]::Ordinal)
        Abstracts     = $idx.Abstracts
        Version       = $version
    }
}

# --------------------------------------------------- dependency mod indexing

# Genes can come from mods we declare as dependencies, not just from vanilla.
# Without this, every reference to an EyeGenes2 or EBSG gene reads as a typo.
#
# Dependencies are read from our own About.xml rather than hardcoded, so the
# index follows the mod's declared requirements automatically.

function Get-DeclaredDependencies {
    param([string] $ModRoot)

    $aboutPath = Join-Path $ModRoot 'About\About.xml'
    if (-not (Test-Path $aboutPath)) { return @() }

    $doc = New-Object System.Xml.XmlDocument
    try { $doc.Load($aboutPath) } catch { return @() }

    $ids = @()
    foreach ($node in $doc.SelectNodes('/ModMetaData/modDependencies/li/packageId')) {
        if ($node.InnerText) { $ids += $node.InnerText.Trim() }
    }
    # DLC are part of the vanilla Data scan already; skip them here.
    return @($ids | Where-Object { $_ -notmatch '^(?i)ludeon\.rimworld' })
}

function Get-InstalledModPaths {
    param([string] $GameInstall)

    $searchRoots = @(
        (Join-Path $GameInstall 'Mods')
        (Join-Path (Split-Path -Parent (Split-Path -Parent $GameInstall)) 'workshop\content\294100')
    ) | Where-Object { Test-Path $_ }

    $map = @{}
    foreach ($root in $searchRoots) {
        Get-ChildItem -Path (Join-Path $root '*\About\About.xml') -ErrorAction SilentlyContinue | ForEach-Object {
            $doc = New-Object System.Xml.XmlDocument
            try { $doc.Load($_.FullName) } catch { return }
            # NOT $pid - that is a read-only PowerShell automatic variable.
            $pkgId = $doc.SelectSingleNode('/ModMetaData/packageId')
            if (-not $pkgId -or -not $pkgId.InnerText) { return }
            $key = $pkgId.InnerText.Trim().ToLowerInvariant()
            # First match wins; a packageId should be unique across installs.
            if (-not $map.ContainsKey($key)) {
                $map[$key] = Split-Path -Parent (Split-Path -Parent $_.FullName)
            }
        }
    }
    return , $map
}

# RimWorld does not resolve transitive dependencies. If a mod we require itself
# requires something we do not declare, the user gets no warning in the mod list -
# they find out from a red log. This catches that at build time instead.
function Test-TransitiveDependencies {
    param([string[]] $PackageIds, [hashtable] $ModPaths)

    $declared = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $PackageIds) { [void]$declared.Add($id) }

    $missing = @{}

    foreach ($id in $PackageIds) {
        $key = $id.ToLowerInvariant()
        if (-not $ModPaths.ContainsKey($key)) { continue }

        $aboutPath = Join-Path $ModPaths[$key] 'About\About.xml'
        if (-not (Test-Path $aboutPath)) { continue }

        $doc = New-Object System.Xml.XmlDocument
        try { $doc.Load($aboutPath) } catch { continue }

        $depName = $doc.SelectSingleNode('/ModMetaData/name')
        $label = if ($depName) { $depName.InnerText.Trim() } else { $id }

        foreach ($node in $doc.SelectNodes('/ModMetaData/modDependencies/li/packageId')) {
            if (-not $node.InnerText) { continue }
            $req = $node.InnerText.Trim()
            # DLC are covered by our own modDependencies / the vanilla scan.
            if ($req -match '^(?i)ludeon\.rimworld') { continue }
            if ($declared.Contains($req)) { continue }
            if (-not $missing.ContainsKey($req)) { $missing[$req] = @() }
            $missing[$req] += $label
        }
    }
    return , $missing
}

# Folders inside a dependency that its own LoadFolders.xml gates behind an
# IfModActive we do not satisfy. Defs in there DO NOT LOAD, and indexing them
# produced a false green: EBSG_FertilityShortening lives in 1.6/Mods/EBSGFull,
# gated on EBSG.Framework, and resolved fine in the validator while failing in
# the game.
function Get-GatedFolders {
    param([string] $ModPath, [string[]] $ActivePackageIds)

    $gated = @()
    $lf = Get-ChildItem -Path $ModPath -Filter 'LoadFolders.xml' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $lf) { return , $gated }

    $doc = New-Object System.Xml.XmlDocument
    try { $doc.Load($lf.FullName) } catch { return , $gated }

    foreach ($li in $doc.SelectNodes('//li')) {
        $folder = $li.InnerText
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        $folder = $folder.Trim().Trim('/')
        if ($folder -eq '' -or $folder -eq '/') { continue }

        $ifActive = $li.Attributes['IfModActive']
        if (-not $ifActive) { continue }

        # Satisfied if EVERY required id is one we declare (comma-separated list).
        $required = @($ifActive.Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $satisfied = $true
        foreach ($r in $required) {
            if ($r -match '^(?i)ludeon\.rimworld') { continue }   # DLC, assume present
            if ($ActivePackageIds -notcontains $r.ToLowerInvariant()) { $satisfied = $false; break }
        }
        if (-not $satisfied) { $gated += ($folder -replace '/', '\') }
    }
    return , $gated
}

function Build-DependencyGeneIndex {
    param([string[]] $PackageIds, [hashtable] $ModPaths)

    $genes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $missing = @()
    $skippedGated = 0
    $skippedMayRequire = 0

    $active = @($PackageIds | ForEach-Object { $_.ToLowerInvariant() })

    foreach ($id in $PackageIds) {
        $key = $id.ToLowerInvariant()
        if (-not $ModPaths.ContainsKey($key)) { $missing += $id; continue }

        $modPath = $ModPaths[$key]
        $gatedFolders = Get-GatedFolders -ModPath $modPath -ActivePackageIds $active

        $files = Get-ChildItem -Path $modPath -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -match '\\Defs\\' }

        foreach ($f in $files) {
            $rel = $f.FullName.Substring($modPath.Length).TrimStart('\')

            $inGated = $false
            foreach ($g in $gatedFolders) {
                if ($rel.StartsWith($g + '\', [StringComparison]::OrdinalIgnoreCase)) { $inGated = $true; break }
            }
            if ($inGated) { $skippedGated++; continue }

            $doc = New-Object System.Xml.XmlDocument
            try { $doc.Load($f.FullName) } catch { continue }
            if (-not $doc.DocumentElement) { continue }

            foreach ($node in $doc.DocumentElement.ChildNodes) {
                if ($node.LocalName -ne 'GeneDef') { continue }

                # A def carrying MayRequire / MayRequireAnyOf only exists when those
                # mods are active. EBSG_ArchiteWoundHealing is gated this way.
                $skip = $false
                foreach ($attrName in @('MayRequire', 'MayRequireAnyOf')) {
                    $attr = $node.Attributes[$attrName]
                    if (-not $attr) { continue }
                    $ids = @($attr.Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    $ids = @($ids | Where-Object { $_ -notmatch '^(?i)ludeon\.rimworld' })
                    if ($ids.Count -eq 0) { continue }

                    if ($attrName -eq 'MayRequireAnyOf') {
                        $ok = $false
                        foreach ($i in $ids) { if ($active -contains $i.ToLowerInvariant()) { $ok = $true; break } }
                        if (-not $ok) { $skip = $true }
                    } else {
                        foreach ($i in $ids) { if ($active -notcontains $i.ToLowerInvariant()) { $skip = $true; break } }
                    }
                }
                if ($skip) { $skippedMayRequire++; continue }

                $dn = $node.SelectSingleNode('defName')
                if ($dn -and $dn.InnerText) { [void]$genes.Add($dn.InnerText.Trim()) }
            }
        }
    }

    return [pscustomobject]@{
        Genes              = $genes
        Missing            = $missing
        SkippedGated       = $skippedGated
        SkippedMayRequire  = $skippedMayRequire
    }
}

# ------------------------------------------------------------ texture lookup

# Node names that carry a texture path. Derived by grepping vanilla Core,
# Biotech and Ideology Defs: texPath, iconPath, uiIconPath, wornGraphicPath,
# graphicPath, factionIconPath, activateTexPath, and many more all share one of
# these suffixes, so we match on suffix rather than enumerating.
$script:TexturePathSuffixes = @('texpath', 'iconpath', 'graphicpath')

function Test-IsTexturePathNode {
    param([string] $NodeName)
    $lower = $NodeName.ToLowerInvariant()
    foreach ($suffix in $script:TexturePathSuffixes) {
        if ($lower.EndsWith($suffix)) { return $true }
    }
    return $false
}

# Graphic classes deriving from Graphic_Collection resolve texPath as a FOLDER and
# load every image inside it, conventionally <leaf>_a, _b, _c. Pointing one at a
# single file produces "Collection cannot init: No textures found at path ..." at
# load time, which a naive file-exists check happily passes.
# Verified against Rimatomics (workshop 1127530465), whose Graphic_StackCount
# texPaths are folders of _a/_b/_c files.
function Test-IsCollectionGraphicClass {
    param([string] $GraphicClass)
    if ([string]::IsNullOrWhiteSpace($GraphicClass)) { return $false }
    return $GraphicClass -match 'StackCount|Random|Collection'
}

# For a texPath node, find the graphicClass declared alongside it.
function Get-SiblingGraphicClass {
    param([System.Xml.XmlNode] $TexNode)
    if (-not $TexNode.ParentNode) { return $null }
    $gc = $TexNode.ParentNode.SelectSingleNode('graphicClass')
    if ($gc) { return $gc.InnerText.Trim() }
    return $null
}

function Get-ModTextureSet {
    param([string] $TexturesRoot)

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    if (Test-Path $TexturesRoot) {
        Get-ChildItem -Path $TexturesRoot -Recurse -File -Include *.png, *.jpg -ErrorAction SilentlyContinue |
            ForEach-Object {
                $rel = $_.FullName.Substring($TexturesRoot.Length).TrimStart('\', '/')
                $rel = [IO.Path]::ChangeExtension($rel, $null).TrimEnd('.')
                [void]$set.Add(($rel -replace '\\', '/'))
            }
    }

    # Comma operator: PowerShell unrolls IEnumerable on return, which would turn an
    # empty set into $null and a populated one into a plain array.
    return , $set
}

function Test-TextureResolves {
    param(
        [string] $TexPath,
        [System.Collections.Generic.HashSet[string]] $Available,
        [switch] $AsCollection
    )
    $p = $TexPath.Trim().TrimStart('/')

    if ($AsCollection) {
        # Must be a folder holding at least one image, i.e. at least one known
        # texture path starts with "<texPath>/". A file sitting AT the path does
        # not satisfy a collection.
        $prefix = $p + '/'
        foreach ($known in $Available) {
            if ($known.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }

    if ($Available.Contains($p)) { return $true }
    # RimWorld also accepts directional variants of a single-graphic base path.
    foreach ($suffix in @('_north', '_south', '_east', '_west')) {
        if ($Available.Contains($p + $suffix)) { return $true }
    }
    return $false
}

# ------------------------------------------------------------- main sequence

Write-Host ''
Write-Host 'Test-ModDefs' -ForegroundColor Cyan
Write-Host ("  mod root : {0}" -f $ModRoot) -ForegroundColor DarkGray
Write-Host ("  game     : {0}" -f $GameInstall) -ForegroundColor DarkGray

$vanilla = Get-VanillaIndex -GameInstall $GameInstall -Refresh:$RefreshVanillaCache

$declaredDeps = @(Get-DeclaredDependencies -ModRoot $ModRoot)
$depGenes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

if ($declaredDeps.Count -gt 0) {
    $modPaths = Get-InstalledModPaths -GameInstall $GameInstall
    $depIndex = Build-DependencyGeneIndex -PackageIds $declaredDeps -ModPaths $modPaths
    $depGenes = $depIndex.Genes
    Write-Host ("  deps     : {0} declared, {1} gene(s) indexed ({2} file(s) skipped as LoadFolders-gated, {3} gene(s) skipped as MayRequire-gated)" -f $declaredDeps.Count, $depGenes.Count, $depIndex.SkippedGated, $depIndex.SkippedMayRequire) -ForegroundColor DarkGray
    foreach ($m in $depIndex.Missing) {
        Add-Problem -Severity WARN -Check 'DependencyNotInstalled' -File 'About/About.xml' `
            -Message ("declared dependency '{0}' is not installed, so its defs cannot be verified." -f $m)
    }

    $transitive = Test-TransitiveDependencies -PackageIds $declaredDeps -ModPaths $modPaths
    foreach ($req in $transitive.Keys) {
        Add-Problem -Severity ERROR -Check 'MissingTransitiveDependency' -File 'About/About.xml' `
            -Message ("'{0}' is required by {1}, but we do not declare it. RimWorld does not resolve transitive dependencies, so the user gets no warning - add it to modDependencies." -f $req, (($transitive[$req] | Sort-Object -Unique) -join ', '))
    }
}

$texturesRoot = Join-Path $ModRoot 'Textures'
$modTextures = Get-ModTextureSet -TexturesRoot $texturesRoot
Write-Host ("  textures : {0} files under Textures/" -f $modTextures.Count) -ForegroundColor DarkGray

$xmlFiles = @(
    Get-ChildItem -Path $ModRoot -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\(Defs|Patches)\\' -and $_.FullName -notmatch '\\\.git\\' }
)

Write-Host ("  scanning : {0} mod XML files" -f $xmlFiles.Count) -ForegroundColor DarkGray
Write-Host ''

if ($xmlFiles.Count -eq 0) {
    Write-Host 'No XML files found under Defs/ or Patches/. Nothing to validate.' -ForegroundColor Yellow
    exit 0
}

# defName -> list of files, for duplicate detection
$seenDefNames = @{}
# Name= attributes declared by this mod, for ParentName resolution
$modNameAttrs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
# deferred ParentName checks: resolution needs the full mod-wide Name set first
$parentRefs = [System.Collections.Generic.List[object]]::new()
# GeneDefs this mod declares, for cross-reference resolution
$modGeneDefs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
# deferred <genes><li> checks from XenotypeDefs
$geneRefs = [System.Collections.Generic.List[object]]::new()
# our own Name= abstracts, and deferred inherited-list checks
$modAbstracts = @{}
$listRefs = [System.Collections.Generic.List[object]]::new()

# Tags our OWN ThingDefs carry, and every tag our PawnKindDefs ask for. Resolved
# after the scan, because a kind may legitimately request a tag declared by a
# thing defined later in the same run.
$modWeaponTags  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$modApparelTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$tagRefs = [System.Collections.Generic.List[object]]::new()
# patch xpaths aimed at our own defs, resolved once every def is known
$patchRefs = [System.Collections.Generic.List[object]]::new()

foreach ($file in $xmlFiles) {
    $rel = Get-RelativePath $file.FullName

    # --- check 1: malformed XML ---------------------------------------------
    $doc = New-Object System.Xml.XmlDocument
    try {
        $doc.Load($file.FullName)
    } catch {
        Add-Problem -Severity ERROR -Check 'XML' -File $rel -Message $_.Exception.Message
        continue
    }
    if (-not $doc.DocumentElement) {
        Add-Problem -Severity ERROR -Check 'XML' -File $rel -Message 'File has no root element.'
        continue
    }

    $isPatch = $doc.DocumentElement.LocalName -eq 'Patch'

    foreach ($node in $doc.DocumentElement.ChildNodes) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

        if (-not $isPatch) {
            # --- check 2 + 3: defName duplicates and vanilla collisions ------
            $dnNode = $node.SelectSingleNode('defName')
            if ($dnNode -and $dnNode.InnerText) {
                $dn = $dnNode.InnerText.Trim()

                # defNames are unique PER DEF TYPE, not globally. Vanilla relies on
                # this: Joywire is simultaneously a HediffDef, a ThingDef and part
                # of a RecipeDef triad, all sharing one name. An implant is always
                # written this way, so a type-blind duplicate check rejects correct
                # XML - which it did, on our own synaptic lattice.
                $dupKey = "{0}|{1}" -f $node.LocalName, $dn
                if ($seenDefNames.ContainsKey($dupKey)) {
                    Add-Problem -Severity ERROR -Check 'DuplicateDefName' -File $rel `
                        -Message ("{0} '{1}' already defined in {2}" -f $node.LocalName, $dn, $seenDefNames[$dupKey])
                } else {
                    $seenDefNames[$dupKey] = $rel
                }

                if ($vanilla.DefNames.Contains($dn)) {
                    Add-Problem -Severity ERROR -Check 'VanillaCollision' -File $rel `
                        -Message ("defName '{0}' collides with a vanilla def. Rename it (RR_ prefix)." -f $dn)
                }
            }

            # --- check 7: def-type required fields --------------------------
            #
            # RimWorld reports most missing fields as config errors at load, but a
            # missing settlementTexturePath is worse than that: Settlement.Material
            # passes a null path to ContentFinder and throws while DRAWING the world
            # map. It presents to the player as "the planet will not generate", with
            # nothing in the startup log to explain it.
            if ($node.LocalName -eq 'FactionDef') {
                $isAbstract = $node.Attributes['Abstract']
                $hidden = $node.SelectSingleNode('hidden')
                $isHidden = $hidden -and $hidden.InnerText.Trim() -eq 'true'
                $owner = if ($dnNode) { $dnNode.InnerText.Trim() } else { '<abstract>' }

                if (-not $isAbstract -and -not $isHidden) {
                    foreach ($required in @('settlementTexturePath', 'maxPawnCostPerTotalPointsCurve', 'backstoryFilters')) {
                        if (-not $node.SelectSingleNode($required)) {
                            Add-Problem -Severity ERROR -Check 'FactionMissingField' -File $rel `
                                -Message ("FactionDef '{0}' has no <{1}>. Required for a settled humanlike faction; a missing settlementTexturePath crashes world map rendering." -f $owner, $required)
                        }
                    }
                }
            }

            # A role precept with no nameMaker throws inside
            # Precept_Role.GenerateNameRaw the moment an ideoligion containing it
            # is generated - GrammarResolver is called unconditionally. That took
            # out Dialog_ChooseMemes, Page_ConfigureIdeo and WorldGenStep together,
            # for 2831 errors, none of which named this mod.
            #
            # Detected structurally: our role defs inherit preceptClass from a
            # vanilla abstract, so the reliable signal is a ParentName chain
            # reaching a known role base.
            if ($node.LocalName -eq 'PreceptDef' -and $dnNode) {
                $parentAttr2 = $node.Attributes['ParentName']
                if ($parentAttr2) {
                    $roleBases = @('PreceptRoleSingleBase', 'PreceptRoleMultiBase')
                    $chain = @()
                    $cur2 = $parentAttr2.Value.Trim()
                    $guard2 = 0
                    while ($cur2 -and $guard2 -lt 10) {
                        $guard2++
                        $chain += $cur2
                        if ($modAbstracts.ContainsKey($cur2)) { $cur2 = $modAbstracts[$cur2].Parent }
                        else { break }
                    }
                    $isRole = @($chain | Where-Object { $roleBases -contains $_ }).Count -gt 0

                    if ($isRole -and -not $node.SelectSingleNode('nameMaker')) {
                        # Might be inherited from one of our own abstracts.
                        $inheritedNamer = $false
                        foreach ($anc in $chain) {
                            if ($modAbstracts.ContainsKey($anc) -and $modAbstracts[$anc].HasNameMaker) { $inheritedNamer = $true; break }
                        }
                        if (-not $inheritedNamer) {
                            Add-Problem -Severity ERROR -Check 'RoleMissingNameMaker' -File $rel `
                                -Message ("role precept '{0}' has no <nameMaker>. Precept_Role.GenerateNameRaw throws without one, taking ideoligion generation and worldgen with it." -f $dnNode.InnerText.Trim())
                        }
                    }
                }
            }

            # Every Color must state its own hair colour and eye colour. This is
            # not cosmetic polish: with Facial Animation installed, a xenotype
            # carrying no eye gene gets a RANDOMLY GENERATED eyeball colour, and
            # one carrying only a hair STYLE gene (Hair_ShortOnly, Hair_BaldOnly -
            # they have no hairColorOverride) gets a random hair colour. Both load
            # with zero errors and are only visible by looking at a pawn's face,
            # which is exactly the kind of silent failure this script exists for.
            if ($node.LocalName -eq 'XenotypeDef' -and $dnNode) {
                $xt = $dnNode.InnerText.Trim()
                $genesNode = $node.SelectSingleNode('genes')
                if ($genesNode) {
                    $hairColor = 0; $eyeGene = 0
                    foreach ($li in $genesNode.SelectNodes('li')) {
                        $g = $li.InnerText.Trim()
                        if ($vanilla.HairColorGenes.Contains($g)) { $hairColor++ }
                        if ($g -like 'Eyes_*') { $eyeGene++ }
                    }
                    if ($hairColor -eq 0) {
                        Add-Problem -Severity ERROR -Check 'XenotypeMissingAppearanceGene' -File $rel `
                            -Message ("XenotypeDef '{0}' has no hair COLOUR gene (one carrying hairColorOverride). Hair_ShortOnly and Hair_BaldOnly are style genes and set no colour, so this caste rolls random hair." -f $xt)
                    }
                    if ($eyeGene -eq 0) {
                        Add-Problem -Severity ERROR -Check 'XenotypeMissingAppearanceGene' -File $rel `
                            -Message ("XenotypeDef '{0}' has no Eyes_* gene. Facial Animation assigns a random eyeball colour when no gene claims one." -f $xt)
                    }
                }
            }

            if ($node.LocalName -eq 'ThingDef') {
                foreach ($li in $node.SelectNodes('weaponTags/li')) {
                    if ($li.InnerText) { [void]$modWeaponTags.Add($li.InnerText.Trim()) }
                }
                foreach ($li in $node.SelectNodes('apparel/tags/li')) {
                    if ($li.InnerText) { [void]$modApparelTags.Add($li.InnerText.Trim()) }
                }
            }

            if ($node.LocalName -eq 'PawnKindDef' -and $dnNode) {
                $kindName = $dnNode.InnerText.Trim()
                foreach ($li in $node.SelectNodes('weaponTags/li')) {
                    if ($li.InnerText) {
                        $tagRefs.Add([pscustomobject]@{ File=$rel; Def=$kindName; Kind='weaponTags'; Tag=$li.InnerText.Trim() })
                    }
                }
                foreach ($li in $node.SelectNodes('apparelTags/li')) {
                    if ($li.InnerText) {
                        $tagRefs.Add([pscustomobject]@{ File=$rel; Def=$kindName; Kind='apparelTags'; Tag=$li.InnerText.Trim() })
                    }
                }
            }

            if ($node.LocalName -eq 'PawnKindDef') {
                $owner = if ($dnNode) { $dnNode.InnerText.Trim() } else { '<abstract>' }
                # weaponMoney with no weaponTags is a load-time config error.
                # Abstract bases may legitimately split the pair across the chain,
                # so only concrete defs declaring one without the other are flagged.
                if ($dnNode -and $node.SelectSingleNode('weaponMoney') -and -not $node.SelectSingleNode('weaponTags')) {
                    Add-Problem -Severity ERROR -Check 'PawnKindWeaponMoney' -File $rel `
                        -Message ("PawnKindDef '{0}' sets weaponMoney but no weaponTags. Remove the money, or give it tags." -f $owner)
                }
            }

            # --- record our own GeneDefs ------------------------------------
            if ($node.LocalName -eq 'GeneDef' -and $dnNode -and $dnNode.InnerText) {
                [void]$modGeneDefs.Add($dnNode.InnerText.Trim())
            }

            # --- check 6: queue <genes><li> refs from XenotypeDefs ----------
            if ($node.LocalName -eq 'XenotypeDef') {
                $owner = if ($dnNode) { $dnNode.InnerText.Trim() } else { '<unnamed>' }
                foreach ($g in $node.SelectNodes('genes/li')) {
                    $gName = $g.InnerText
                    if ([string]::IsNullOrWhiteSpace($gName)) { continue }

                    # Our own reference may carry MayRequire, mirroring the gate on
                    # the gene it points at. Such a reference is allowed to dangle:
                    # the game drops it when the gate is unsatisfied.
                    $gated = $false
                    foreach ($attrName in @('MayRequire', 'MayRequireAnyOf')) {
                        if ($g.Attributes[$attrName]) { $gated = $true }
                    }

                    $geneRefs.Add([pscustomobject]@{
                        Gene   = $gName.Trim()
                        File   = $rel
                        Owner  = $owner
                        Gated  = $gated
                    })
                }
            }

            # --- record Name= for ParentName resolution ---------------------
            $nameAttr = $node.Attributes['Name']
            $parentAttrEarly = $node.Attributes['ParentName']

            # Collect this def's own list-field declarations once; used both to
            # register our abstracts and to queue the inherited-duplicate check.
            $ownLists = @{}
            foreach ($lf in $script:InheritedListFields) {
                $listNode = $node.SelectSingleNode($lf)
                if (-not $listNode) { continue }
                $inh = $listNode.Attributes['Inherit']
                if ($inh -and $inh.Value -eq 'False') { continue }
                $vals = @()
                foreach ($li in $listNode.SelectNodes('li')) {
                    if ($li.InnerText) { $vals += $li.InnerText.Trim() }
                }
                if ($vals.Count -gt 0) { $ownLists[$lf] = $vals }
            }

            if ($nameAttr -and $nameAttr.Value) {
                [void]$modNameAttrs.Add($nameAttr.Value.Trim())
                $modAbstracts[$nameAttr.Value.Trim()] = @{
                    Parent       = if ($parentAttrEarly) { $parentAttrEarly.Value.Trim() } else { $null }
                    Lists        = $ownLists
                    HasNameMaker = [bool]$node.SelectSingleNode('nameMaker')
                }
            }

            if ($parentAttrEarly -and $ownLists.Count -gt 0) {
                $listRefs.Add([pscustomobject]@{
                    Def    = if ($dnNode) { $dnNode.InnerText.Trim() } elseif ($nameAttr) { $nameAttr.Value.Trim() } else { '<unnamed>' }
                    Parent = $parentAttrEarly.Value.Trim()
                    Lists  = $ownLists
                    File   = $rel
                })
            }

            # --- check 5: queue ParentName ----------------------------------
            $parentAttr = $node.Attributes['ParentName']
            if ($parentAttr -and $parentAttr.Value) {
                $parentRefs.Add([pscustomobject]@{
                    Parent = $parentAttr.Value.Trim()
                    File   = $rel
                    Def    = if ($dnNode) { $dnNode.InnerText.Trim() } else { '<abstract>' }
                })
            }
        }

        # --- check 9: patch xpaths targeting our own defs --------------------
        #
        # A PatchOperation whose xpath matches nothing does NOTHING, silently -
        # there is no error, the def simply never gets patched. That is fine for a
        # cross-mod patch guarded by PatchOperationFindMod, but a patch of ours
        # aimed at one of OUR defs that no longer exists is always a bug, and the
        # usual cause is a rename.
        #
        # Only RR_ targets are checked. A patch aimed at a vanilla or third-party
        # def is legitimately outside what we can verify.
        if ($isPatch) {
            foreach ($xp in $node.SelectNodes('.//xpath')) {
                if ([string]::IsNullOrWhiteSpace($xp.InnerText)) { continue }
                foreach ($m in [regex]::Matches($xp.InnerText, 'defName\s*=\s*"(RR_[A-Za-z0-9_]+)"')) {
                    $patchRefs.Add([pscustomobject]@{
                        Target = $m.Groups[1].Value
                        File   = $rel
                    })
                }
            }
            # CE's PatchOperationMakeGunCECompatible names its target directly
            # rather than through an xpath.
            foreach ($dnDirect in $node.SelectNodes('.//defName')) {
                $v = $dnDirect.InnerText
                if ($v -and $v.Trim().StartsWith('RR_')) {
                    $patchRefs.Add([pscustomobject]@{
                        Target = $v.Trim()
                        File   = $rel
                    })
                }
            }
        }

        # --- check 4: texture paths -----------------------------------------
        foreach ($texNode in $node.SelectNodes('.//*')) {
            if (-not (Test-IsTexturePathNode $texNode.LocalName)) { continue }
            if ($texNode.ChildNodes.Count -ne 1) { continue }
            $texPath = $texNode.InnerText
            if ([string]::IsNullOrWhiteSpace($texPath)) { continue }
            $texPath = $texPath.Trim()

            $graphicClass = Get-SiblingGraphicClass -TexNode $texNode
            $isCollection = Test-IsCollectionGraphicClass -GraphicClass $graphicClass

            if (Test-TextureResolves -TexPath $texPath -Available $modTextures -AsCollection:$isCollection) { continue }

            # A path we own must exist. A path we do not own is probably a
            # vanilla texture, and vanilla textures ship inside Unity asset
            # bundles rather than as loose files, so we cannot confirm them
            # from disk. Fail on ours, warn on theirs.
            $leaf = ($texPath -split '[\\/]')[-1]
            if ($leaf -like 'RR_*') {
                if ($isCollection) {
                    Add-Problem -Severity ERROR -Check 'MissingTextureCollection' -File $rel `
                        -Message ("<{0}> '{1}' uses {2}, which needs a FOLDER of images at that path (<leaf>_a, _b, _c), not a single file. Run New-PlaceholderTextures.ps1." -f $texNode.LocalName, $texPath, $graphicClass)
                } else {
                    Add-Problem -Severity ERROR -Check 'MissingTexture' -File $rel `
                        -Message ("<{0}> '{1}' has no file under Textures/. Run New-PlaceholderTextures.ps1." -f $texNode.LocalName, $texPath)
                }
            } elseif ($vanilla.TexPaths.Contains($texPath)) {
                # Vanilla references this exact path itself, so it is real even
                # though it lives in an asset bundle we cannot inspect. Silent.
            } else {
                # Not ours, and vanilla never references it either. Almost always a
                # typo or an invented path - "World/WorldObjects/Expanding/Settlement"
                # looks plausible and does not exist.
                Add-Problem -Severity ERROR -Check 'UnknownTexturePath' -File $rel `
                    -Message ("<{0}> '{1}' is not under Textures/ and is referenced nowhere in vanilla. Check for a typo, or add the file." -f $texNode.LocalName, $texPath)
            }
        }
    }
}

# --- check 5 resolution ------------------------------------------------------
foreach ($ref in $parentRefs) {
    if ($modNameAttrs.Contains($ref.Parent)) { continue }
    if ($vanilla.NameAttrs.Contains($ref.Parent)) { continue }
    Add-Problem -Severity ERROR -Check 'MissingParent' -File $ref.File `
        -Message ("def '{0}' has ParentName='{1}' which matches no Name= def in this mod or vanilla." -f $ref.Def, $ref.Parent)
}

# --- check 9 resolution: patch targets ---------------------------------------
#
# seenDefNames is keyed "DefType|defName", so the comparison is on the tail.
foreach ($ref in $patchRefs) {
    $found = $false
    foreach ($k in $seenDefNames.Keys) {
        $bar = $k.IndexOf('|')
        if ($bar -ge 0 -and $k.Substring($bar + 1) -eq $ref.Target) { $found = $true; break }
    }
    if (-not $found) {
        Add-Problem -Severity ERROR -Check 'PatchTargetMissing' -File $ref.File `
            -Message ("patch targets '{0}', which this mod does not define. A patch whose xpath matches nothing fails SILENTLY - the usual cause is a rename." -f $ref.Target)
    }
}

# --- check 8: list values already supplied by an ancestor --------------------
#
# RimWorld APPENDS list fields on inherit. Re-declaring a value the parent chain
# already has creates a duplicate entry. For thingCategories that surfaces as
# "Config error: has duplicate thingCategory X"; for weaponTags, tradeTags and the
# rest it happens silently and the def just carries the value twice.
#
# Caught the razor declaring thingCategories WeaponsMelee, weaponClasses Melee and
# tradeTags WeaponMelee, all three of which BaseMeleeWeapon already provides.

function Get-InheritedListValues {
    param([string] $ParentName, [hashtable] $ModAbstracts, $VanillaAbstracts)

    $result = @{}
    $cur = $ParentName
    $guard = 0

    while ($cur -and $guard -lt 12) {
        $guard++
        $entry = $null
        if ($ModAbstracts.ContainsKey($cur)) {
            $entry = $ModAbstracts[$cur]
        } elseif ($VanillaAbstracts -and $VanillaAbstracts.PSObject.Properties[$cur]) {
            $entry = $VanillaAbstracts.PSObject.Properties[$cur].Value
        }
        if (-not $entry) { break }

        $lists = $entry.Lists
        if ($lists) {
            foreach ($field in $script:InheritedListFields) {
                $vals = $null
                if ($lists -is [hashtable]) {
                    if ($lists.ContainsKey($field)) { $vals = $lists[$field] }
                } elseif ($lists.PSObject.Properties[$field]) {
                    $vals = $lists.PSObject.Properties[$field].Value
                }
                if (-not $vals) { continue }
                if (-not $result.ContainsKey($field)) { $result[$field] = @() }
                $result[$field] += @($vals)
            }
        }

        $cur = if ($entry.Parent) { $entry.Parent } else { $null }
    }
    return , $result
}

foreach ($ref in $listRefs) {
    $inherited = Get-InheritedListValues -ParentName $ref.Parent -ModAbstracts $modAbstracts -VanillaAbstracts $vanilla.Abstracts
    foreach ($field in $ref.Lists.Keys) {
        if (-not $inherited.ContainsKey($field)) { continue }
        foreach ($val in $ref.Lists[$field]) {
            if ($inherited[$field] -contains $val) {
                Add-Problem -Severity ERROR -Check 'DuplicateInheritedListValue' -File $ref.File `
                    -Message ("'{0}' re-declares <{1}> value '{2}', which it already inherits from '{3}'. List fields append on inherit - remove it, or mark the list Inherit=False." -f $ref.Def, $field, $val, $ref.Parent)
            }
        }
    }
}

# --- pawn kind tag resolution -------------------------------------------------
#
# A PawnKindDef asks for gear by TAG. If no ThingDef anywhere carries that tag,
# the pawn simply spawns without a weapon, or without clothes, and the game logs
# NOTHING AT ALL - the request is a filter, and an empty filter is not an error.
#
# This was found the hard way: four tags on new merchant pawn kinds had to be
# hand-verified against vanilla because nothing else could have caught a typo.
# The vocabulary is indexed from the things that CARRY the tags, never from the
# kinds that request them, so a typo cannot validate itself.
foreach ($ref in $tagRefs) {
    $known = if ($ref.Kind -eq 'weaponTags') { $vanilla.WeaponTags } else { $vanilla.ApparelTags }
    $mine  = if ($ref.Kind -eq 'weaponTags') { $modWeaponTags }      else { $modApparelTags }
    if ($known.Contains($ref.Tag)) { continue }
    if ($mine.Contains($ref.Tag))  { continue }

    Add-Problem -Severity ERROR -Check 'UnknownPawnKindTag' -File $ref.File `
        -Message ("PawnKindDef '{0}' asks for <{1}> '{2}', which no ThingDef carries. The pawn will spawn without that gear and nothing will be logged." -f $ref.Def, $ref.Kind, $ref.Tag)
}

# --- check 6 resolution: XenotypeDef gene references -------------------------
#
# A xenotype naming a gene that does not exist produces "Could not resolve
# cross-reference" at load. With fourteen xenotypes referencing well over a
# hundred gene names between them, catching typos here rather than in the log is
# the difference between one pass and a dozen.
#
# Template-generated genes (AptitudeRemarkable_Mining, Skin_LightGray, ...) do
# not exist as GeneDefs in XML; the game synthesises them at runtime from
# GeneTemplateDefs. We accept "<KnownTemplate>_<anything>" as plausible. That is
# an approximation: it will not catch a bad suffix such as
# AptitudeRemarkable_Blacksmithing. Those still surface in the game log.
foreach ($ref in $geneRefs) {
    if ($modGeneDefs.Contains($ref.Gene))      { continue }
    if ($vanilla.GeneDefs.Contains($ref.Gene)) { continue }
    if ($depGenes.Contains($ref.Gene))         { continue }

    $underscore = $ref.Gene.IndexOf('_')
    if ($underscore -gt 0) {
        $prefix = $ref.Gene.Substring(0, $underscore)
        if ($vanilla.GeneTemplates.Contains($prefix)) { continue }
    }

    if ($ref.Gated) {
        # Explicitly gated by the author. The game drops the reference cleanly when
        # the gate is unsatisfied, so this is a note rather than a fault.
        Add-Problem -Severity WARN -Check 'GatedGeneUnavailable' -File $ref.File `
            -Message ("xenotype '{0}' references gene '{1}', which is MayRequire-gated and not available in the current dependency set. It will be skipped at load." -f $ref.Owner, $ref.Gene)
        continue
    }

    Add-Problem -Severity ERROR -Check 'MissingGene' -File $ref.File `
        -Message ("xenotype '{0}' references gene '{1}', which is not a GeneDef in this mod or vanilla and does not match a known gene template." -f $ref.Owner, $ref.Gene)
}

# ----------------------------------------------------------------- reporting

$errors = @($script:Problems | Where-Object Severity -eq 'ERROR')
$warns  = @($script:Problems | Where-Object Severity -eq 'WARN')

foreach ($p in $warns) {
    Write-Host ("  WARN  [{0}] {1}" -f $p.Check, $p.File) -ForegroundColor Yellow
    Write-Host ("        {0}" -f $p.Message) -ForegroundColor DarkYellow
}
foreach ($p in $errors) {
    Write-Host ("  ERROR [{0}] {1}" -f $p.Check, $p.File) -ForegroundColor Red
    Write-Host ("        {0}" -f $p.Message) -ForegroundColor DarkRed
}

Write-Host ''
Write-Host ("  {0} defs, {1} error(s), {2} warning(s)" -f $seenDefNames.Count, $errors.Count, $warns.Count)

if ($errors.Count -gt 0) {
    Write-Host '  FAILED' -ForegroundColor Red
    Write-Host ''
    exit 1
}

Write-Host '  PASSED' -ForegroundColor Green
Write-Host ''
exit 0
