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
    # TYPED sets. A flat name index cannot tell a ResearchProjectDef from a
    # ResearchTabDef, and that gap let a researchPrerequisite point at the research
    # TAB pass validation and then fail at load, silently taking the recipe with it.
    $researchProjects = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $weaponClasses    = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $weaponTags  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $apparelTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    # PreceptDef -> the memes it REQUIRES. IdeoFoundation filters a precept out
    # entirely when these are absent, so a meme cannot force a precept it does not
    # also supply the requirement for.
    $preceptReqMemes = @{}
    # Vanilla ABSTRACT RecipeDefs that hand recipeUsers to their children.
    # SurgeryInstallImplantBase is the one that matters: it supplies <li>Human</li>,
    # so every implant surgery inheriting it is reachable without any patch. Missing
    # this produced confident false positives on two working defs.
    $recipeUserAbstracts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    # Vanilla defs AND Name= abstracts that declare <tools> - 190 of them.
    #
    # CHECKED, AND THE OBVIOUS GUESS WAS WRONG: BaseWeapon, BaseGun and
    # BaseHumanMakeableGun do NOT declare tools, so a plain gun of ours inherits
    # none. (The first attempt at this concluded they did, because the regex used
    # to test it matched ParentName="BaseGun" as though it were Name="BaseGun".)
    #
    # The set is kept anyway because inheritance is still reachable: 190 vanilla
    # defs do carry tools, and one of ours parenting from any of them would
    # inherit plain Tool entries that CE casts to ToolCE and crashes on.
    $toolBearers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

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
                if ($node.LocalName -eq 'ResearchProjectDef') { [void]$researchProjects.Add($name) }
                if ($node.LocalName -eq 'WeaponClassDef')     { [void]$weaponClasses.Add($name) }
            }

            # Tag vocabularies, taken from the things that CARRY the tags
            # (ThingDef/weaponTags and ThingDef/apparel/tags), never from the
            # PawnKindDefs that request them - otherwise a typo would validate
            # itself.
            # $dn here is the defName NODE, not its text. Keying the table on the
            # node object would make every later lookup miss silently.
            if ($node.LocalName -eq 'RecipeDef') {
                $rna = $node.Attributes['Name']
                if ($rna -and $rna.Value -and $node.SelectSingleNode('recipeUsers')) {
                    [void]$recipeUserAbstracts.Add($rna.Value.Trim())
                }
            }

            if ($node.LocalName -eq 'PreceptDef' -and $dn -and $dn.InnerText) {
                $rm = @()
                foreach ($li in $node.SelectNodes('requiredMemes/li')) {
                    if ($li.InnerText) { $rm += $li.InnerText.Trim() }
                }
                $preceptReqMemes[$dn.InnerText.Trim()] = $rm
            }

            if ($node.LocalName -eq 'ThingDef' -and $node.SelectSingleNode('tools')) {
                # Recorded under BOTH its defName and its Name= attribute, because a
                # child can inherit from either.
                if ($dn -and $dn.InnerText) { [void]$toolBearers.Add($dn.InnerText.Trim()) }
                $na = $node.Attributes['Name']
                if ($na -and $na.Value) { [void]$toolBearers.Add($na.Value.Trim()) }
            }

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
        ResearchProjects = @($researchProjects)
        WeaponClasses = @($weaponClasses)
        TexPaths      = @($vanillaTexPaths)
        HairColorGenes= @($hairColorGenes)
        WeaponTags    = @($weaponTags)
        ApparelTags   = @($apparelTags)
        PreceptReqMemes = $preceptReqMemes
        RecipeUserAbstracts = @($recipeUserAbstracts)
        ToolBearers   = @($toolBearers)
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
    $cacheSchema = 10  # 10: ToolBearers, for CE inherited-tool detection

    if (-not $Refresh -and (Test-Path $cacheFile)) {
        try {
            $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cached.Version -eq $version -and $cached.Schema -eq $cacheSchema) {
                Write-Host ("  vanilla index: cache hit ({0} defs, {1} genes, game {2})" -f $cached.DefNames.Count, $cached.GeneDefs.Count, $version) -ForegroundColor DarkGray
                return [pscustomobject]@{
                    DefNames      = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.DefNames, [StringComparer]::Ordinal)
                    NameAttrs     = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.NameAttrs, [StringComparer]::Ordinal)
                    ResearchProjects = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.ResearchProjects, [StringComparer]::Ordinal)
                    WeaponClasses = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.WeaponClasses, [StringComparer]::Ordinal)
                    GeneDefs      = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.GeneDefs, [StringComparer]::Ordinal)
                    GeneTemplates = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.GeneTemplates, [StringComparer]::Ordinal)
                    TexPaths      = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.TexPaths, [StringComparer]::OrdinalIgnoreCase)
                    HairColorGenes= [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.HairColorGenes, [StringComparer]::Ordinal)
                    WeaponTags    = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.WeaponTags, [StringComparer]::Ordinal)
                    ApparelTags   = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.ApparelTags, [StringComparer]::Ordinal)
                    PreceptReqMemes = $cached.PreceptReqMemes
                    RecipeUserAbstracts = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.RecipeUserAbstracts, [StringComparer]::Ordinal)
                    ToolBearers   = [System.Collections.Generic.HashSet[string]]::new([string[]]$cached.ToolBearers, [StringComparer]::Ordinal)
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
        ResearchProjects = $idx.ResearchProjects
        WeaponClasses = $idx.WeaponClasses
        NameAttrs     = $idx.NameAttrs
        GeneDefs      = $idx.GeneDefs
        GeneTemplates = $idx.GeneTemplates
        TexPaths      = $idx.TexPaths
        HairColorGenes= $idx.HairColorGenes
        WeaponTags    = $idx.WeaponTags
        ApparelTags   = $idx.ApparelTags
        PreceptReqMemes = $idx.PreceptReqMemes
        RecipeUserAbstracts = $idx.RecipeUserAbstracts
        ToolBearers   = $idx.ToolBearers
        Abstracts     = $idx.Abstracts
    } | ConvertTo-Json -Depth 8 -Compress | Set-Content -Path $cacheFile -Encoding UTF8

    Write-Host ("  vanilla index: built ({0} defs, {1} abstract names, {2} genes, {3} gene templates)" -f $idx.DefNames.Count, $idx.NameAttrs.Count, $idx.GeneDefs.Count, $idx.GeneTemplates.Count) -ForegroundColor DarkGray

    [pscustomobject]@{
        DefNames      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.DefNames, [StringComparer]::Ordinal)
        ResearchProjects = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.ResearchProjects, [StringComparer]::Ordinal)
        WeaponClasses = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.WeaponClasses, [StringComparer]::Ordinal)
        NameAttrs     = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.NameAttrs, [StringComparer]::Ordinal)
        GeneDefs      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.GeneDefs, [StringComparer]::Ordinal)
        GeneTemplates = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.GeneTemplates, [StringComparer]::Ordinal)
        TexPaths      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.TexPaths, [StringComparer]::OrdinalIgnoreCase)
        HairColorGenes= [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.HairColorGenes, [StringComparer]::Ordinal)
        WeaponTags    = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.WeaponTags, [StringComparer]::Ordinal)
        ApparelTags   = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.ApparelTags, [StringComparer]::Ordinal)
        PreceptReqMemes = $idx.PreceptReqMemes
        RecipeUserAbstracts = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.RecipeUserAbstracts, [StringComparer]::Ordinal)
        ToolBearers   = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.ToolBearers, [StringComparer]::Ordinal)
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

# Content belonging to mods we integrate with OPTIONALLY - the ones named by
# IfModActive in our own LoadFolders.xml.
#
# Defs inside a gated folder legitimately reference that mod's abstract bases and
# its textures. The starShell's modules descend from the Exosuit Framework's
# ModuleApparelCore; the Drachenjaeger's turrets point at Vehicle Framework's
# UI/Gizmos/FireRate_Single. Neither is ours and neither is vanilla's, so without
# this the ParentName and texture checks report every one of them as missing - and
# the tempting "fix" would be to weaken those checks, which would cost the real
# typo detection they exist for.
#
# Scoped per folder: content from an optional mod only satisfies a def that
# actually lives in the folder gated on that mod.
function Get-OptionalIntegrationAbstracts {
    param([string] $ModRoot, [hashtable] $ModPaths)

    $result = @{}   # gated folder (backslashes, lowercase) -> @{ Abstracts; TexFiles }

    $lfPath = Join-Path $ModRoot 'LoadFolders.xml'
    if (-not (Test-Path $lfPath)) { return $result }

    $doc = New-Object System.Xml.XmlDocument
    try { $doc.Load($lfPath) } catch { return $result }

    foreach ($li in $doc.SelectNodes('//li')) {
        $attr = $li.Attributes['IfModActive']
        if (-not $attr -or -not $attr.Value) { continue }
        if ([string]::IsNullOrWhiteSpace($li.InnerText)) { continue }

        $folder = $li.InnerText.Trim().Replace('/', '\').Trim('\').ToLowerInvariant()
        $names  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $texes  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $coreDefs  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $patchDefs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

        foreach ($id in ($attr.Value -split ',')) {
            $key = $id.Trim().ToLowerInvariant()
            if (-not $key) { continue }
            if (-not $ModPaths.ContainsKey($key)) { continue }   # not installed; cannot check

            $modPath = $ModPaths[$key]

            $files = Get-ChildItem -Path $modPath -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -match '\\Defs\\' }
            foreach ($f in $files) {
                $d = New-Object System.Xml.XmlDocument
                try { $d.Load($f.FullName) } catch { continue }
                if (-not $d.DocumentElement) { continue }
                foreach ($node in $d.DocumentElement.ChildNodes) {
                    if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    $na = $node.Attributes['Name']
                    if ($na -and $na.Value) { [void]$names.Add($na.Value.Trim()) }
                }
            }

            # Texture paths the gated mod ships, relative to its Textures/ root and
            # without the extension - the same form a def writes them in. Both .png
            # and .dds count; RimWorld accepts either.
            # defNames the gated mod supplies, split by whether they come from
            # its own Defs tree or from a per-third-party-mod patch folder. CE
            # ships hundreds of ammo sets under ModPatches/<Some Mod>/ which only
            # exist for players who also run that mod - naming one is a silent
            # break for everyone else.
            foreach ($f2 in $files) {
                $isPatchFolder = $f2.FullName -like ('*' + [char]92 + 'ModPatches' + [char]92 + '*') -or
                                 $f2.FullName -like '*/ModPatches/*'
                $d2 = New-Object System.Xml.XmlDocument
                try { $d2.Load($f2.FullName) } catch { continue }
                if (-not $d2.DocumentElement) { continue }
                foreach ($dn2 in $d2.SelectNodes('//defName')) {
                    if ([string]::IsNullOrWhiteSpace($dn2.InnerText)) { continue }
                    $nm = $dn2.InnerText.Trim()
                    if ($isPatchFolder) { [void]$patchDefs.Add($nm) } else { [void]$coreDefs.Add($nm) }
                }
            }

            $art = Get-ChildItem -Path $modPath -Recurse -File -Include *.png, *.dds -ErrorAction SilentlyContinue
            foreach ($tf in $art) {
                $full = $tf.FullName.Replace('\', '/')
                $marker = '/Textures/'
                $idx = $full.LastIndexOf($marker)
                if ($idx -lt 0) { continue }
                $rel = $full.Substring($idx + $marker.Length)
                $dot = $rel.LastIndexOf('.')
                if ($dot -gt 0) { $rel = $rel.Substring(0, $dot) }
                [void]$texes.Add($rel)
            }
        }

        if ($names.Count -gt 0 -or $texes.Count -gt 0 -or $coreDefs.Count -gt 0) {
            $result[$folder] = @{ Abstracts = $names; TexFiles = $texes; CoreDefs = $coreDefs; PatchDefs = $patchDefs }
        }
    }
    return $result
}

# A def inside a LoadFolders-gated folder may point at a texture shipped by the
# mod that folder is gated on. Scoped to the folder for the same reason the
# ParentName check is: content from an optional mod must not silently excuse a
# typo in a def that has nothing to do with it.
function Test-TextureFromGatedMod {
    param([string] $RelFile, [string] $TexPath, [hashtable] $Optional)

    $sep  = [char]92   # backslash, spelled this way so no escaping layer can eat it
    $file = $RelFile.Replace('/', $sep).ToLowerInvariant()
    $tex  = $TexPath.Replace($sep, '/').Trim('/')
    foreach ($folder in $Optional.Keys) {
        if (-not $file.StartsWith($folder + $sep)) { continue }
        if ($Optional[$folder].TexFiles.Contains($tex)) { return $true }
    }
    return $false
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
# 'portrait' covers StorytellerDef.portraitLarge / portraitTiny. Left out
# originally, so a storyteller's art was invisible to BOTH tools: nothing
# generated it and nothing complained it was missing. A storyteller with no
# portrait shows as a blank slot on the selection page.
$script:TexturePathSuffixes = @('texpath', 'iconpath', 'graphicpath', 'portrait', 'portraitlarge', 'portraittiny')

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

# Graphic classes that resolve texPath as a DIRECTIONAL SET rather than one file,
# loading <leaf>_north / _east / _south beside it.
#
# Same lesson as the collection classes, learned the same way. A single file was
# written for the Drachenjaeger's body, the file-exists check passed, and in game
# the vehicle did not appear in the architect menu at all while the UI thread
# threw a NullReferenceException on every frame. Nothing named the texture.
#
# Vehicles.Graphic_Vehicle is Vehicle Framework's own multi-directional class -
# confirmed by listing an installed VVE vehicle's textures, which ship _north,
# _east and _south for the body and a single file for the turret.
function Test-IsMultiGraphicClass {
    param([string] $GraphicClass)
    if ([string]::IsNullOrWhiteSpace($GraphicClass)) { return $false }
    if ($GraphicClass -match 'Graphic_Turret') { return $false }   # single file
    return $GraphicClass -match 'Graphic_Multi|Graphic_Vehicle'
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
        [switch] $AsCollection,
        [switch] $AsMulti
    )
    $p = $TexPath.Trim().TrimStart('/')

    if ($AsMulti) {
        # A directional class needs the three facings present. West is not
        # required: RimWorld mirrors the east texture horizontally for it, which
        # this project confirmed by observation - a placeholder rendered with its
        # label and facing arrow reversed on a west-facing pawn.
        #
        # Note the plain branch below accepts a bare file OR any one directional
        # variant, which is right for a single graphic and wrong here. That
        # leniency is exactly what let a one-file vehicle body pass.
        foreach ($suffix in @('_north', '_east', '_south')) {
            if (-not $Available.Contains($p + $suffix)) { return $false }
        }
        return $true
    }

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

$optionalAbstracts = Get-OptionalIntegrationAbstracts -ModRoot $ModRoot -ModPaths $modPaths
if ($optionalAbstracts.Keys.Count -gt 0) {
    foreach ($k in $optionalAbstracts.Keys) {
        Write-Host ("  optional : {0} -> {1} abstract(s), {2} texture(s) from the mod it is gated on" -f $k, $optionalAbstracts[$k].Abstracts.Count, $optionalAbstracts[$k].TexFiles.Count) -ForegroundColor DarkGray
    }
}
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
# Our own defNames, type-agnostic, for resolving references we make to ourselves.
$modDefNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
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

# Set if any PawnKindDef we ship declares factionLeader true. Computed up front
# because the FactionDef check needs it and def order in the scan is arbitrary.
$script:AnyFactionLeaderKind = $false
foreach ($pf in (Get-ChildItem -Path (Join-Path $ModRoot '1.6') -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue)) {
    $txt = Get-Content $pf.FullName -Raw -ErrorAction SilentlyContinue
    if ($txt -and $txt -match '<factionLeader>\s*[Tt]rue\s*</factionLeader>') {
        $script:AnyFactionLeaderKind = $true
        break
    }
}

# Tags our OWN ThingDefs carry, and every tag our PawnKindDefs ask for. Resolved
# after the scan, because a kind may legitimately request a tag declared by a
# thing defined later in the same run.
$modWeaponTags  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$modApparelTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$tagRefs = [System.Collections.Generic.List[object]]::new()
$ammoSetRefs = [System.Collections.Generic.List[object]]::new()

# Memes we own, and every precept they GUARANTEE through requireOne or
# selectOneOrNone. Compared after the scan against the precepts that merely claim
# the meme through associatedMemes.
$modMemes         = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$memeGuaranteed   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$preceptMemeRefs  = [System.Collections.Generic.List[object]]::new()
$requireOneGroups = [System.Collections.Generic.List[object]]::new()

# Recipes we define, and whether anything can actually run them.
$recipeRefs = [System.Collections.Generic.List[object]]::new()

# Research a def says it depends on. Unresolvable ones are reported by RimWorld as
# "Could not resolve cross-reference" and then the dependent def never unlocks.
$researchRefs = [System.Collections.Generic.List[object]]::new()
# Mod-side TYPED indexes, so a reference can be checked against the right kind of
# def rather than against every name in the game.
$modResearchProjects = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$modWeaponClasses    = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$weaponClassRefs     = [System.Collections.Generic.List[object]]::new()
$ourThings           = @{}   # our ThingDefs: parent, own tools, CE tools - for inheritance walking
$maskedApparel       = @{}   # defName -> file + wornGraphicPath, for mask checking
$abstractRecipeUsers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

# Every xenotype we define, and every xenotype some PawnKindDef can actually
# produce. A Color in the first set and not the second can never spawn.
$modXenotypes      = [System.Collections.Generic.List[object]]::new()
$kindProducedXenos = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$modPreceptReqMemes = @{}

# Vehicle Framework's VehicleDef <-> VehicleBuildDef pair. They must point at each
# other and neither direction is optional.
$vehicleDefs   = @{}   # defName -> buildDef it names
$vehicleBuilds = @{}   # defName -> thingToSpawn it names
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

        # <ammoSet> for a Combat Extended turret extension. Collected OUTSIDE the
        # non-patch branch below, because ours arrives through a
        # PatchOperationAddModExtension and would otherwise never be seen - which
        # is exactly how the first version of this check passed while inspecting
        # nothing.
        foreach ($asNode in $node.SelectNodes('.//ammoSet')) {
            if ([string]::IsNullOrWhiteSpace($asNode.InnerText)) { continue }
            $ammoSetRefs.Add([pscustomobject]@{ File = $rel; Name = $asNode.InnerText.Trim() })
        }

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
                    [void]$modDefNames.Add($dn)
                    if ($node.LocalName -eq 'ResearchProjectDef') { [void]$modResearchProjects.Add($dn) }
                    if ($node.LocalName -eq 'WeaponClassDef')     { [void]$modWeaponClasses.Add($dn) }
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
            # <prerequisites> means research only on a ResearchProjectDef; on other
            # def types the same node name means something else entirely.
            if ($node.LocalName -eq 'ResearchProjectDef' -and $dnNode) {
                foreach ($li in $node.SelectNodes('prerequisites/li')) {
                    if ($li.InnerText -and -not $li.Attributes['MayRequire']) {
                        $researchRefs.Add([pscustomobject]@{ File=$rel; Def=$dnNode.InnerText.Trim(); Ref=$li.InnerText.Trim() })
                    }
                }
            }
            if ($dnNode) {
                foreach ($rp in $node.SelectNodes('.//researchPrerequisite')) {
                    if ($rp.InnerText -and -not $rp.Attributes['MayRequire']) {
                        $researchRefs.Add([pscustomobject]@{ File=$rel; Def=$dnNode.InnerText.Trim(); Ref=$rp.InnerText.Trim() })
                    }
                }
                foreach ($rp in $node.SelectNodes('.//researchPrerequisites/li')) {
                    if ($rp.InnerText -and -not $rp.Attributes['MayRequire']) {
                        $researchRefs.Add([pscustomobject]@{ File=$rel; Def=$dnNode.InnerText.Trim(); Ref=$rp.InnerText.Trim() })
                    }
                }
            }

            # Apparel that asks for a worn-graphic mask. Collected so the masks
            # themselves can be checked for existence below.
            if ($dnNode -and $node.SelectSingleNode('apparel/useWornGraphicMask[text()="true"]')) {
                $wgpNode = $node.SelectSingleNode('apparel/wornGraphicPath')
                if ($wgpNode -and $wgpNode.InnerText) {
                    $maskedApparel[$dnNode.InnerText.Trim()] = [pscustomobject]@{
                        File = $rel
                        Path = $wgpNode.InnerText.Trim()
                    }
                }
            }

            # Any def with melee tools. Collected here rather than filtered to
            # weapons, because apparel and buildings can carry tools too and CE
            # casts them all the same way.
            if ($node.LocalName -eq 'ThingDef') {
                $pnAttr = $node.Attributes['ParentName']
                $nmAttr = $node.Attributes['Name']
                $key = if ($dnNode -and $dnNode.InnerText) { $dnNode.InnerText.Trim() }
                       elseif ($nmAttr -and $nmAttr.Value) { $nmAttr.Value.Trim() }
                       else { $null }
                if ($key) {
                    $ourThings[$key] = [pscustomobject]@{
                        File     = $rel
                        Parent   = if ($pnAttr) { $pnAttr.Value.Trim() } else { $null }
                        OwnTools = [bool]$node.SelectSingleNode('tools')
                        InlineCE = [bool]$node.SelectSingleNode('tools/li[@Class="CombatExtended.ToolCE"]')
                        Concrete = [bool]($dnNode -and $dnNode.InnerText)
                    }
                }
            }

            if ($dnNode) {
                foreach ($wc in $node.SelectNodes('weaponClasses/li')) {
                    if ($wc.InnerText -and -not $wc.Attributes['MayRequire']) {
                        $weaponClassRefs.Add([pscustomobject]@{ File=$rel; Def=$dnNode.InnerText.Trim(); Ref=$wc.InnerText.Trim() })
                    }
                }
            }

            if ($node.LocalName -eq 'RecipeDef' -and -not $dnNode) {
                # Abstract. Record it only if it hands recipeUsers to its children.
                $na2 = $node.Attributes['Name']
                if ($na2 -and $na2.Value -and $node.SelectSingleNode('recipeUsers')) {
                    [void]$abstractRecipeUsers.Add($na2.Value.Trim())
                }
            }

            if ($node.LocalName -eq 'RecipeDef' -and $dnNode) {
                $recipeRefs.Add([pscustomobject]@{
                    File  = $rel
                    Def   = $dnNode.InnerText.Trim()
                    Users = ($node.SelectSingleNode('recipeUsers') -ne $null)
                    Parent = if ($node.Attributes['ParentName']) { $node.Attributes['ParentName'].Value.Trim() } else { $null }
                })
            }

            if ($node.LocalName -eq 'MemeDef' -and $dnNode) {
                [void]$modMemes.Add($dnNode.InnerText.Trim())
                foreach ($li in $node.SelectNodes('requireOne/li/li')) {
                    if ($li.InnerText) { [void]$memeGuaranteed.Add($li.InnerText.Trim()) }
                }
                foreach ($grp in $node.SelectNodes('requireOne/li')) {
                    $members = @()
                    foreach ($li in $grp.SelectNodes('li')) {
                        if ($li.InnerText) { $members += $li.InnerText.Trim() }
                    }
                    if ($members.Count -gt 0) {
                        $requireOneGroups.Add([pscustomobject]@{
                            File = $rel; Meme = $dnNode.InnerText.Trim(); Members = $members
                        })
                    }
                }
                foreach ($li in $node.SelectNodes('selectOneOrNone/precepts/li')) {
                    if ($li.InnerText) { [void]$memeGuaranteed.Add($li.InnerText.Trim()) }
                }
            }

            if ($node.LocalName -eq 'PreceptDef' -and $dnNode) {
                $ourRm = @()
                foreach ($li in $node.SelectNodes('requiredMemes/li')) {
                    if ($li.InnerText) { $ourRm += $li.InnerText.Trim() }
                }
                $modPreceptReqMemes[$dnNode.InnerText.Trim()] = $ourRm

                foreach ($li in $node.SelectNodes('associatedMemes/li')) {
                    if (-not $li.InnerText) { continue }
                    $preceptMemeRefs.Add([pscustomobject]@{
                        File = $rel; Precept = $dnNode.InnerText.Trim(); Meme = $li.InnerText.Trim()
                    })
                }
            }

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

                    # A faction with pawnGroupMakers but no possible leader
                    # generates with leader = null and the log fills with
                    # "Faction leader for <name> is null". All seven of ours did.
                    #
                    # Faction.TryGenerateNewLeader (decompiled) considers only
                    # fixedLeaderKinds, or options in the COMBAT group whose
                    # PawnKindDef sets factionLeader true. The combat-group route
                    # cannot be resolved from this file alone, so this only fires
                    # when fixedLeaderKinds is absent AND no kind in the file
                    # declares factionLeader - which is the case that actually bit.
                    if ($node.SelectSingleNode('pawnGroupMakers') -and
                        -not $node.SelectSingleNode('fixedLeaderKinds') -and
                        -not $script:AnyFactionLeaderKind) {
                        Add-Problem -Severity ERROR -Check 'FactionNoLeader' -File $rel `
                            -Message ("FactionDef '{0}' has pawnGroupMakers but no <fixedLeaderKinds>, and no PawnKindDef in this mod sets <factionLeader>true</factionLeader>. It will generate with no leader." -f $owner)
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
                $modXenotypes.Add([pscustomobject]@{ File = $rel; Name = $dnNode.InnerText.Trim() })
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

            # An AbilityDef that can only ever target its own caster must say so, or
            # clicking the gizmo drops the pawn into target-selection mode and waits
            # for a click the targetParams can never accept. NOTHING IS LOGGED: an
            # ability with no reachable target is not a load error, it is just inert.
            #
            # Two distinct faults, both hit for real by the first ghostCloak:
            #   1. self-only but targetRequired is not false
            #   2. canTargetSelf true alongside canTargetPawns false - self IS a
            #      pawn, so this excludes the only legal target. Always a bug.
            # Vehicle Framework pairs a VehicleDef with a VehicleBuildDef, each
            # naming the other. Collected here and resolved after the scan.
            # The element is <Vehicles.VehicleDef>. A dot is not a namespace
            # separator in XML, so LocalName is the whole dotted string - an
            # equality test against 'VehicleDef' silently matches nothing.
            if ($dnNode -and $node.LocalName -match '(^|\.)VehicleDef$') {
                $bd = $node.SelectSingleNode('buildDef')
                $vehicleDefs[$dnNode.InnerText.Trim()] = @{
                    Build = if ($bd) { $bd.InnerText.Trim() } else { $null }
                    File  = $rel
                }
            }
            if ($dnNode -and $node.LocalName -match '(^|\.)VehicleBuildDef$') {
                $ts = $node.SelectSingleNode('thingToSpawn')
                $vehicleBuilds[$dnNode.InnerText.Trim()] = @{
                    Spawn = if ($ts) { $ts.InnerText.Trim() } else { $null }
                    File  = $rel
                }
            }

            if ($node.LocalName -eq 'AbilityDef' -and $dnNode) {
                $abName = $dnNode.InnerText.Trim()
                $tp = $node.SelectSingleNode('verbProperties/targetParams')
                if ($tp) {
                    $selfNode = $tp.SelectSingleNode('canTargetSelf')
                    $canSelf  = $selfNode -and $selfNode.InnerText.Trim() -match '^(?i)true$'

                    $pawnsNode = $tp.SelectSingleNode('canTargetPawns')
                    if ($canSelf -and $pawnsNode -and $pawnsNode.InnerText.Trim() -match '^(?i)false$') {
                        Add-Problem -Severity ERROR -Check 'AbilityUntargetable' -File $rel `
                            -Message ("AbilityDef '{0}' sets canTargetSelf true and canTargetPawns false. Self is a pawn, so this excludes the only legal target and the ability can never be cast." -f $abName)
                    }

                    # Self-only = self allowed and nothing else turned on.
                    $othersOn = $false
                    foreach ($c in $tp.ChildNodes) {
                        if ($c.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                        if ($c.LocalName -eq 'canTargetSelf') { continue }
                        if ($c.LocalName -notlike 'canTarget*') { continue }
                        if ($c.InnerText.Trim() -match '^(?i)true$') { $othersOn = $true; break }
                    }

                    if ($canSelf -and -not $othersOn) {
                        $tr = $node.SelectSingleNode('targetRequired')
                        if (-not $tr -or $tr.InnerText.Trim() -notmatch '^(?i)false$') {
                            Add-Problem -Severity ERROR -Check 'AbilityUntargetable' -File $rel `
                                -Message ("AbilityDef '{0}' can only target itself but does not set <targetRequired>false</targetRequired>. The gizmo will appear and do nothing when clicked." -f $abName)
                        }
                    }
                }
            }

            if ($node.LocalName -eq 'PawnKindDef' -and $dnNode) {
                foreach ($xc in $node.SelectNodes('xenotypeSet/xenotypeChances/*')) {
                    if ($xc.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                        [void]$kindProducedXenos.Add($xc.LocalName)
                    }
                }
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
            $isMulti      = Test-IsMultiGraphicClass      -GraphicClass $graphicClass

            if (Test-TextureResolves -TexPath $texPath -Available $modTextures -AsCollection:$isCollection -AsMulti:$isMulti) { continue }

            # A path we own must exist. A path we do not own is probably a
            # vanilla texture, and vanilla textures ship inside Unity asset
            # bundles rather than as loose files, so we cannot confirm them
            # from disk. Fail on ours, warn on theirs.
            $leaf = ($texPath -split '[\\/]')[-1]
            if ($leaf -like 'RR_*') {
                if ($isCollection) {
                    Add-Problem -Severity ERROR -Check 'MissingTextureCollection' -File $rel `
                        -Message ("<{0}> '{1}' uses {2}, which needs a FOLDER of images at that path (<leaf>_a, _b, _c), not a single file. Run New-PlaceholderTextures.ps1." -f $texNode.LocalName, $texPath, $graphicClass)
                } elseif ($isMulti) {
                    Add-Problem -Severity ERROR -Check 'MissingTextureDirectional' -File $rel `
                        -Message ("<{0}> '{1}' uses {2}, which needs _north, _east and _south files beside that path, not a single file. Run New-PlaceholderTextures.ps1." -f $texNode.LocalName, $texPath, $graphicClass)
                } else {
                    Add-Problem -Severity ERROR -Check 'MissingTexture' -File $rel `
                        -Message ("<{0}> '{1}' has no file under Textures/. Run New-PlaceholderTextures.ps1." -f $texNode.LocalName, $texPath)
                }
            } elseif ($vanilla.TexPaths.Contains($texPath)) {
                # Vanilla references this exact path itself, so it is real even
                # though it lives in an asset bundle we cannot inspect. Silent.
            } elseif (Test-TextureFromGatedMod -RelFile $rel -TexPath $texPath -Optional $optionalAbstracts) {
                # Shipped by the mod this folder is gated on - Vehicle Framework
                # owns UI/Gizmos/FireRate_Single, for instance. Scoped to the
                # folder, so it cannot excuse a bad path anywhere else.
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

    # A def living in a LoadFolders-gated folder may parent from an abstract
    # belonging to the mod that folder is gated on. Scoped to that folder, so an
    # abstract from an optional mod cannot accidentally satisfy a def elsewhere.
    $refFile = $ref.File.Replace('/', '\').ToLowerInvariant()
    $viaOptional = $false
    foreach ($folder in $optionalAbstracts.Keys) {
        if (-not $refFile.StartsWith($folder + '\')) { continue }
        if ($optionalAbstracts[$folder].Abstracts.Contains($ref.Parent)) { $viaOptional = $true; break }
    }
    if ($viaOptional) { continue }

    Add-Problem -Severity ERROR -Check 'MissingParent' -File $ref.File `
        -Message ("def '{0}' has ParentName='{1}' which matches no Name= def in this mod, in vanilla, or in a mod our LoadFolders gates on." -f $ref.Def, $ref.Parent)
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

# --- recipe reachability ------------------------------------------------------
#
# A RecipeDef does not appear anywhere just because it exists. A production recipe
# needs recipeUsers naming the bench; a SURGERY has to be listed in the target's own
# ThingDef <recipes>, which for people means patching Human - vanilla wires
# ImplantXenogerm exactly that way in Races_Humanlike.xml.
#
# Miss it and the recipe loads with zero errors, passes every other check here, and
# is simply never offered. Fifteen carving surgeries nearly shipped that way.
#
# A recipe counts as reachable if it declares recipeUsers, inherits them from one of
# our abstracts, or its defName appears anywhere under 1.6/Patches.
$patchText = ''
$patchDir = Join-Path $ModRoot '1.6\Patches'
if (Test-Path $patchDir) {
    foreach ($pf in (Get-ChildItem -Path $patchDir -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue)) {
        $patchText += (Get-Content $pf.FullName -Raw)
    }
}

foreach ($ref in $recipeRefs) {
    if ($ref.Users) { continue }

    $inherits = $false
    $cur = $ref.Parent
    $guard = 0
    while ($cur -and $guard -lt 10) {
        $guard++
        $match = @($recipeRefs | Where-Object { $_.Def -eq $cur })
        if ($abstractRecipeUsers.Contains($cur)) { $inherits = $true; break }
        if ($vanilla.RecipeUserAbstracts -and $vanilla.RecipeUserAbstracts.Contains($cur)) { $inherits = $true; break }
        if ($vanilla.NameAttrs.Contains($cur) -and -not $modAbstracts.ContainsKey($cur)) { break }
        if ($match.Count -gt 0 -and $match[0].Users) { $inherits = $true; break }
        if ($modAbstracts.ContainsKey($cur)) { $cur = $modAbstracts[$cur].Parent } else { break }
    }
    if ($inherits) { continue }

    if ($patchText -and $patchText.Contains($ref.Def)) { continue }

    Add-Problem -Severity ERROR -Check 'RecipeUnreachable' -File $ref.File `
        -Message ("RecipeDef '{0}' has no <recipeUsers> and is named in no patch, so nothing can ever run it. A surgery must be added to the target ThingDef's <recipes> list - for people that means patching Human." -f $ref.Def)
}

# --- xenotype reachability ----------------------------------------------------
#
# Every pawn kind in this mod sets useFactionXenotypes false and pins its own
# Color, so a FactionDef's xenotypeSet is NEVER consulted for our kinds. A Color
# with no pawn kind therefore appears nowhere in the game at all - and nothing
# reports it, because the xenotype loads cleanly and the faction happily lists it
# in a table that is never read.
#
# Found the hard way: White, Blue, Violet and Pink shipped unreachable, which
# presented as their name prefixes "not working".
foreach ($x in $modXenotypes) {
    if ($kindProducedXenos.Contains($x.Name)) { continue }
    Add-Problem -Severity ERROR -Check 'XenotypeUnreachable' -File $x.File `
        -Message ("XenotypeDef '{0}' is produced by no PawnKindDef. Our kinds all set useFactionXenotypes false, so a faction xenotypeSet cannot spawn it either - it will never appear on any pawn." -f $x.Name)
}

# --- requireOne satisfiability ------------------------------------------------
#
# A meme's requireOne forces the ideoligion to take ONE precept from each group.
# But IdeoFoundation filters out any precept whose requiredMemes are absent, so a
# group where EVERY member needs some other meme can be satisfied by nothing.
#
# This is not hypothetical. Vanilla's Scarification_Minor, _Heavy and _Extreme all
# carry requiredMemes PainIsVirtue, so requiring scarification from a meme that
# does not also supply PainIsVirtue silently yields no scarification precept at
# all - which is exactly the trap this project walked into.
#
# A group is safe when at least one member is unconditionally selectable: it has
# no requiredMemes, or lists this meme among them.
foreach ($grp in $requireOneGroups) {
    $anySafe = $false
    $why = @()
    foreach ($m in $grp.Members) {
        $req = $null
        if ($modPreceptReqMemes.ContainsKey($m))          { $req = $modPreceptReqMemes[$m] }
        elseif ($vanilla.PreceptReqMemes -and $vanilla.PreceptReqMemes.PSObject.Properties[$m]) {
            $req = $vanilla.PreceptReqMemes.PSObject.Properties[$m].Value
        }

        if (-not $req -or @($req).Count -eq 0) { $anySafe = $true; break }
        if (@($req) -contains $grp.Meme)       { $anySafe = $true; break }
        $why += ("{0} needs {1}" -f $m, (@($req) -join '/'))
    }

    if (-not $anySafe) {
        Add-Problem -Severity ERROR -Check 'RequireOneUnsatisfiable' -File $grp.File `
            -Message ("MemeDef '{0}' has a <requireOne> group no ideoligion can satisfy on this meme alone - {1}. IdeoFoundation drops a precept whose requiredMemes are absent, so the group yields nothing and the issue is silently skipped." -f $grp.Meme, ($why -join '; '))
    }
}

# --- precept guarantee resolution ---------------------------------------------
#
# associatedMemes on a PreceptDef makes it ELIGIBLE for an ideoligion carrying
# that meme. It does NOT make ideoligion generation pick it. With no "none" option
# on the issue, a generated ideoligion can carry the meme and take no stance on
# that issue at all - so the precept never applies, and nothing anywhere says so.
#
# This is how the razor lock and the Color ladder both shipped inert: the issue
# still shows in the ideoligion UI (every issue does), so the omission looks like
# it worked. requireOne on the MemeDef is the vanilla lever that forces the pick.
#
# Only our own memes are checked. A precept associated with a VANILLA meme cannot
# be guaranteed from here, and that is a legitimate design choice rather than a
# fault.
foreach ($ref in $preceptMemeRefs) {
    if (-not $modMemes.Contains($ref.Meme)) { continue }
    if ($memeGuaranteed.Contains($ref.Precept)) { continue }

    Add-Problem -Severity ERROR -Check 'PreceptNotGuaranteed' -File $ref.File `
        -Message ("PreceptDef '{0}' claims meme '{1}' through associatedMemes, but that meme's <requireOne> never lists it. Generation may take the meme and skip this precept entirely, leaving it inert with no error. Add it to requireOne, or to selectOneOrNone if it is meant to be optional." -f $ref.Precept, $ref.Meme)
}

# --- ammoSet resolution -------------------------------------------------------
#
# An <ammoSet> naming something that does not exist makes the CE turret extension
# resolve to nothing, and the turret throws InvalidCastException on every shot -
# with no load error, because the patch applied fine and the def is well formed.
#
# The subtler trap, hit for real: Combat Extended defines hundreds of ammo sets
# under ModPatches/<Some Mod>/, which only exist for players who ALSO run that
# mod. AmmoSet_40mmRocket is one of them. Naming it works on this machine and
# silently breaks for everyone else, so those only warn rather than pass.
#
# Not scoped per folder like the abstracts and textures are: an ammoSet is a
# Combat Extended concept wherever the patch happens to live, and our vehicle CE
# patch deliberately sits in the Vehicles folder so it needs BOTH mods.
$allCoreDefs  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$allPatchDefs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($k in $optionalAbstracts.Keys) {
    foreach ($d in $optionalAbstracts[$k].CoreDefs)  { [void]$allCoreDefs.Add($d) }
    foreach ($d in $optionalAbstracts[$k].PatchDefs) { [void]$allPatchDefs.Add($d) }
}

if ($allCoreDefs.Count -gt 0) {
    foreach ($ref in $ammoSetRefs) {
        if ($allCoreDefs.Contains($ref.Name)) { continue }
        if ($allPatchDefs.Contains($ref.Name)) {
            Add-Problem -Severity WARN -Check 'AmmoSetFromModPatch' -File $ref.File `
                -Message ("<ammoSet> '{0}' exists only inside a ModPatches folder, so it is present only for players who also run that third mod. Pick one from the mod's own Defs tree." -f $ref.Name)
            continue
        }
        Add-Problem -Severity ERROR -Check 'UnknownAmmoSet' -File $ref.File `
            -Message ("<ammoSet> '{0}' matches no def in any mod our LoadFolders gates on. The turret extension will resolve to nothing and throw on every shot." -f $ref.Name)
    }
}

# --- research reference resolution --------------------------------------------
#
# A research prerequisite naming something that does not exist logs
# "Could not resolve cross-reference to ResearchProjectDef named X" once at load and
# is then easy to miss among everyone else's warnings - but the dependent project
# never becomes researchable, so everything gated behind it is unreachable forever.
#
# That is exactly how fifteen carving surgeries stayed invisible: RR_Carving listed
# a prerequisite called GeneticEngineering, which is not a real def. Biotech's gene
# research is Xenogermination.
# TYPE MATTERS, not just existence. RR_Artificer is this mod's research TAB, and
# pointing a researchPrerequisite at it passed a name-only check while RimWorld
# reported "Could not resolve cross-reference to ResearchProjectDef" at load and
# dropped the recipe. Checking the name alone is how that shipped.
foreach ($ref in $researchRefs) {
    if ($modResearchProjects -and $modResearchProjects.Contains($ref.Ref)) { continue }
    if ($vanilla.ResearchProjects -and $vanilla.ResearchProjects.Contains($ref.Ref)) { continue }
    if ($allCoreDefs -and $allCoreDefs.Contains($ref.Ref))  { continue }
    if ($allPatchDefs -and $allPatchDefs.Contains($ref.Ref)) { continue }

    $known = ($modDefNames -and $modDefNames.Contains($ref.Ref)) -or $vanilla.DefNames.Contains($ref.Ref)
    if ($known) {
        Add-Problem -Severity ERROR -Check 'ResearchRefWrongType' -File $ref.File `
            -Message ("'{0}' requires research '{1}'. A def by that name exists, but it is NOT a ResearchProjectDef - most likely a ResearchTabDef. RimWorld drops the cross-reference at load and the recipe never appears." -f $ref.Def, $ref.Ref)
    }
    else {
        Add-Problem -Severity ERROR -Check 'UnknownResearchRef' -File $ref.File `
            -Message ("'{0}' requires research '{1}', which is not a def anywhere. The project will never unlock and everything gated behind it is unreachable." -f $ref.Def, $ref.Ref)
    }
}

# --- weaponClasses resolution -------------------------------------------------
#
# Same failure, quieter: an unknown WeaponClassDef logs one cross-reference warning
# and is then simply absent, so any balance or AI behaviour keyed on the class does
# nothing. MeleeSharp looks entirely plausible and does not exist; the real one is
# MeleePiercer.
foreach ($ref in $weaponClassRefs) {
    if ($vanilla.WeaponClasses -and $vanilla.WeaponClasses.Contains($ref.Ref)) { continue }
    if ($modWeaponClasses -and $modWeaponClasses.Contains($ref.Ref)) { continue }
    if ($allCoreDefs -and $allCoreDefs.Contains($ref.Ref)) { continue }

    Add-Problem -Severity ERROR -Check 'UnknownWeaponClass' -File $ref.File `
        -Message ("'{0}' lists weaponClass '{1}', which is not a WeaponClassDef anywhere. It resolves to nothing at load." -f $ref.Def, $ref.Ref)
}

# --- Combat Extended: every melee tool must be replaced with a ToolCE ----------
#
# THIS ONE CRASHED THE GAME AND NAMED NOBODY. Under CE,
# Verb_MeleeAttackCE.DamageInfosToApply casts every tool on the weapon to
# CombatExtended.ToolCE and reads armour penetration straight off the result, so a
# weapon left with vanilla <li> tools throws a NullReferenceException on EVERY
# SWING. What the player sees is:
#
#   Exception ticking <pawn>: System.NullReferenceException
#     at CombatExtended.Verb_MeleeAttackCE+<DamageInfosToApply>d__38.MoveNext
#
# with no frame naming this mod - the fault is entirely inside CE, caused by data
# we shipped. The Reaper's razor was added months after the CE patch file and
# nobody went back to it.
#
# GUNS ARE NOT EXEMPT. PatchOperationMakeGunCECompatible was decompiled to be
# sure: it rewrites statBases, costList, verb properties, comps, weapon classes,
# tags and research, and never touches <tools>. CE patches every vanilla gun's
# tools in a separate PatchOperationReplace for that reason, so a gun's stock or
# grip bash crashes exactly the same way.
$ceToolsDir = Join-Path $ModRoot '1.6\mods\CombatExtended\Patches'
if (Test-Path $ceToolsDir) {
    $cePatchText = (Get-ChildItem $ceToolsDir -Filter '*.xml' -Recurse |
                    ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"

    # INHERITED TOOLS COUNT. RimWorld inherits <tools> like any other field, so a
    # def of ours can hand CE a set of plain Tool entries without declaring one.
    # The weapon BASE abstracts turn out not to carry tools - that was checked, not
    # assumed - but 190 other vanilla defs do, and CE patches tools by defName only,
    # so anything of ours descending from one of those is exposed.
    function Test-HasTools {
        param([string] $Name)
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $cur = $Name
        while ($cur -and $seen.Add($cur)) {
            if ($vanilla.ToolBearers -and $vanilla.ToolBearers.Contains($cur)) { return $true }
            if ($ourThings.ContainsKey($cur)) {
                if ($ourThings[$cur].OwnTools) { return $true }
                $cur = $ourThings[$cur].Parent
                continue
            }
            break
        }
        return $false
    }

    foreach ($dName in $ourThings.Keys) {
        $info = $ourThings[$dName]
        if (-not $info.Concrete) { continue }
        if ($info.InlineCE) { continue }
        if (-not (Test-HasTools $dName)) { continue }

        $pattern = 'defName="' + [regex]::Escape($dName) + '"\]/tools'
        if ($cePatchText -match $pattern) { continue }

        $how = if ($info.OwnTools) { 'has <tools>' } else { "inherits <tools> from '$($info.Parent)'" }
        Add-Problem -Severity ERROR -Check 'CEToolsUnpatched' -File $info.File `
            -Message ("'{0}' {1} but has no PatchOperationReplace on its /tools in 1.6\mods\CombatExtended\Patches. Under CE, Verb_MeleeAttackCE casts every tool to ToolCE, so a vanilla Tool throws a NullReferenceException on every melee swing - and the stack trace names only CE. Guns need this too: PatchOperationMakeGunCECompatible does not touch tools." -f $dName, $how)
    }
}

# --- worn graphic masks must actually exist -----------------------------------
#
# useWornGraphicMask swaps the shader to CutoutComplex and makes Graphic_Multi
# look for <sprite>m beside each sprite - verified by decompiling
# ApparelGraphicRecordGetter and Graphic_Multi.Init. If the mask is absent the
# game does NOT complain: ContentFinder is called with reportFailure: false, so a
# missing mask is a silent null and the shader falls back to dyeing the whole
# garment, which is the exact bug the mask was added to fix.
#
# Masks are generated by New-WornApparel.ps1 from the same drawing code as the
# sprite, so the realistic failure is forgetting to regenerate after adding a
# body type, not hand-authoring one wrong.
foreach ($dName in $maskedApparel.Keys) {
    $info  = $maskedApparel[$dName]
    # Get-ModTextureSet stores forward slashes. Building this with backslashes
    # matched nothing, and the check passed while doing absolutely nothing -
    # caught only because it was negative-tested.
    $prefix = $info.Path
    $sprites = @($modTextures | Where-Object {
        $_ -like ($prefix + '_*') -and $_ -notlike '*m'
    })
    if ($sprites.Count -eq 0) { continue }

    $missing = @($sprites | Where-Object { $modTextures -notcontains ($_ + 'm') })
    if ($missing.Count) {
        Add-Problem -Severity ERROR -Check 'MissingWornGraphicMask' -File $info.File `
            -Message ("'{0}' sets useWornGraphicMask but {1} of its {2} worn sprites have no matching mask beside them (first: {3}m). ContentFinder loads masks with reportFailure false, so a missing mask is silent and the whole garment takes the caste dye instead. Re-run Tools/New-WornApparel.ps1." -f $dName, $missing.Count, $sprites.Count, $missing[0])
    }
}


# --- vehicle def/build pair resolution ----------------------------------------
#
# VehicleDef.buildDef and VehicleBuildDef.thingToSpawn are a mutual pair. Missing
# either half loads WITHOUT A SINGLE ERROR and produces an empty square in the
# architect menu, because Vehicles.Rendering.VehicleGui.GizmoOnGUIWithMaterial
# opens with
#
#     VehicleDef thingToSpawn = buildDef.thingToSpawn;
#
# and dereferences thingToSpawn.graphicData on the next line - so the gizmo throws
# a NullReferenceException on every frame the tab is open, roughly a hundred a
# second, and nothing in the load log names the def responsible. The only thing
# that identifies it is the OnGUI stack trace.
foreach ($vName in $vehicleDefs.Keys) {
    $v = $vehicleDefs[$vName]
    if (-not $v.Build) {
        Add-Problem -Severity ERROR -Check 'VehiclePairBroken' -File $v.File `
            -Message ("VehicleDef '{0}' has no <buildDef>, so it can never be built." -f $vName)
        continue
    }
    if (-not $vehicleBuilds.ContainsKey($v.Build)) {
        Add-Problem -Severity ERROR -Check 'VehiclePairBroken' -File $v.File `
            -Message ("VehicleDef '{0}' names buildDef '{1}', which is not a VehicleBuildDef in this mod." -f $vName, $v.Build)
        continue
    }
    $back = $vehicleBuilds[$v.Build].Spawn
    if (-not $back) {
        Add-Problem -Severity ERROR -Check 'VehiclePairBroken' -File $vehicleBuilds[$v.Build].File `
            -Message ("VehicleBuildDef '{0}' has no <thingToSpawn>. The architect gizmo dereferences it immediately and will throw on every frame while showing an empty square." -f $v.Build)
    } elseif ($back -ne $vName) {
        Add-Problem -Severity ERROR -Check 'VehiclePairBroken' -File $vehicleBuilds[$v.Build].File `
            -Message ("VehicleBuildDef '{0}' has thingToSpawn '{1}' but is named as the buildDef of '{2}'. The pair must point at each other." -f $v.Build, $back, $vName)
    }
}

foreach ($bName in $vehicleBuilds.Keys) {
    if (-not $vehicleBuilds[$bName].Spawn) {
        # Already reported above if some VehicleDef points here; this catches an
        # orphan blueprint that nothing references.
        $referencedBy = @($vehicleDefs.Keys | Where-Object { $vehicleDefs[$_].Build -eq $bName })
        if ($referencedBy.Count -eq 0) {
            Add-Problem -Severity ERROR -Check 'VehiclePairBroken' -File $vehicleBuilds[$bName].File `
                -Message ("VehicleBuildDef '{0}' has no <thingToSpawn> and no VehicleDef names it as a buildDef." -f $bName)
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
