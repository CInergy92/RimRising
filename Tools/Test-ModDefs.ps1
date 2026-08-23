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

function Build-VanillaIndex {
    param([string] $DataRoot)

    $defNames  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $nameAttrs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $geneDefs  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $geneTemplates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

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
                if ($node.Name -eq 'GeneDef')         { [void]$geneDefs.Add($name) }
                if ($node.Name -eq 'GeneTemplateDef') { [void]$geneTemplates.Add($name) }
            }

            $na = $node.Attributes['Name']
            if ($na -and $na.Value) { [void]$nameAttrs.Add($na.Value.Trim()) }
        }
    }

    [pscustomobject]@{
        DefNames      = @($defNames)
        NameAttrs     = @($nameAttrs)
        GeneDefs      = @($geneDefs)
        GeneTemplates = @($geneTemplates)
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
    $cacheSchema = 2

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
    } | ConvertTo-Json -Depth 3 -Compress | Set-Content -Path $cacheFile -Encoding UTF8

    Write-Host ("  vanilla index: built ({0} defs, {1} abstract names, {2} genes, {3} gene templates)" -f $idx.DefNames.Count, $idx.NameAttrs.Count, $idx.GeneDefs.Count, $idx.GeneTemplates.Count) -ForegroundColor DarkGray

    [pscustomobject]@{
        DefNames      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.DefNames, [StringComparer]::Ordinal)
        NameAttrs     = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.NameAttrs, [StringComparer]::Ordinal)
        GeneDefs      = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.GeneDefs, [StringComparer]::Ordinal)
        GeneTemplates = [System.Collections.Generic.HashSet[string]]::new([string[]]$idx.GeneTemplates, [StringComparer]::Ordinal)
        Version       = $version
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

    $isPatch = $doc.DocumentElement.Name -eq 'Patch'

    foreach ($node in $doc.DocumentElement.ChildNodes) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

        if (-not $isPatch) {
            # --- check 2 + 3: defName duplicates and vanilla collisions ------
            $dnNode = $node.SelectSingleNode('defName')
            if ($dnNode -and $dnNode.InnerText) {
                $dn = $dnNode.InnerText.Trim()

                if ($seenDefNames.ContainsKey($dn)) {
                    Add-Problem -Severity ERROR -Check 'DuplicateDefName' -File $rel `
                        -Message ("defName '{0}' already defined in {1}" -f $dn, $seenDefNames[$dn])
                } else {
                    $seenDefNames[$dn] = $rel
                }

                if ($vanilla.DefNames.Contains($dn)) {
                    Add-Problem -Severity ERROR -Check 'VanillaCollision' -File $rel `
                        -Message ("defName '{0}' collides with a vanilla def. Rename it (RR_ prefix)." -f $dn)
                }
            }

            # --- record our own GeneDefs ------------------------------------
            if ($node.Name -eq 'GeneDef' -and $dnNode -and $dnNode.InnerText) {
                [void]$modGeneDefs.Add($dnNode.InnerText.Trim())
            }

            # --- check 6: queue <genes><li> refs from XenotypeDefs ----------
            if ($node.Name -eq 'XenotypeDef') {
                $owner = if ($dnNode) { $dnNode.InnerText.Trim() } else { '<unnamed>' }
                foreach ($g in $node.SelectNodes('genes/li')) {
                    $gName = $g.InnerText
                    if ([string]::IsNullOrWhiteSpace($gName)) { continue }
                    $geneRefs.Add([pscustomobject]@{
                        Gene  = $gName.Trim()
                        File  = $rel
                        Owner = $owner
                    })
                }
            }

            # --- record Name= for ParentName resolution ---------------------
            $nameAttr = $node.Attributes['Name']
            if ($nameAttr -and $nameAttr.Value) { [void]$modNameAttrs.Add($nameAttr.Value.Trim()) }

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

        # --- check 4: texture paths -----------------------------------------
        foreach ($texNode in $node.SelectNodes('.//*')) {
            if (-not (Test-IsTexturePathNode $texNode.Name)) { continue }
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
                        -Message ("<{0}> '{1}' uses {2}, which needs a FOLDER of images at that path (<leaf>_a, _b, _c), not a single file. Run New-PlaceholderTextures.ps1." -f $texNode.Name, $texPath, $graphicClass)
                } else {
                    Add-Problem -Severity ERROR -Check 'MissingTexture' -File $rel `
                        -Message ("<{0}> '{1}' has no file under Textures/. Run New-PlaceholderTextures.ps1." -f $texNode.Name, $texPath)
                }
            } else {
                Add-Problem -Severity WARN -Check 'UnverifiedTexture' -File $rel `
                    -Message ("<{0}> '{1}' not found under Textures/ - assumed vanilla, cannot verify from disk." -f $texNode.Name, $texPath)
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

    $underscore = $ref.Gene.IndexOf('_')
    if ($underscore -gt 0) {
        $prefix = $ref.Gene.Substring(0, $underscore)
        if ($vanilla.GeneTemplates.Contains($prefix)) { continue }
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
