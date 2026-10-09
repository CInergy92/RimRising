---
name: validate
description: Run RimRising's validation tooling and turn the output into a fix list. Use this after ANY change under 1.6/ (Defs, Patches, Mods), Textures/, WeaponTweakData/ or Source/, before telling the user something is finished, and whenever they say "validate", "check the mod", "run the validator", "is it clean", "did it load", "check the log" or ask why the game is throwing red errors. Also use it when a game launch just happened and the log needs reading. Do not skip it because a change looked trivial - the project's history is a list of trivial changes that loaded with errors.
---

# /validate

RimRising's working agreement is that nothing is done until the game loads it with zero
red errors. This skill is the step between "I edited a file" and "it is done": it runs the
static validator, the C# build when source changed, and the game-log reader when a launch
has happened, and turns their output into a list of things to fix, each pointed at the
CLAUDE.md entry that explains it.

Run everything from the repo root.

## 1. Static validation

```
pwsh -File Tools/Test-ModDefs.ps1
```

Exit 1 means at least one ERROR. The report lines look like:

```
  ERROR [CheckName] 1.6/Defs/Some/File.xml
      message
  WARN  [CheckName] 1.6/Defs/Some/File.xml
```

`-RefreshVanillaCache` is only needed after a game update; the cache is keyed on the game's
`Version.txt` and rebuilds itself otherwise. If the summary line reports a vanilla index far
from **11,586 defNames / 838 abstract defs / 1,558 files**, the scan is broken or the game
updated; say so rather than trusting the result.

**If `pwsh` or the game install is unavailable** (cloud sessions), run the fallback:

```
python3 Tools/Check-ModDefs.py
```

It catches malformed XML, unresolved `RR_` references, gated-folder leaks, missing `RR_`
textures (graphic-class aware), DefOf and Keyed mismatches. It cannot see vanilla, so a
vanilla defName typo passes it. Say which validator ran; a clean fallback run is not a clean
run.

## 2. Build, when C# changed

If anything under `Source/` changed since the last build:

```
pwsh -File Tools/Build-Mod.ps1
```

The DLL in `1.6/Assemblies/` must match `Source/`, or the game runs old code while the
source says otherwise. In the cloud there is no .NET; say the build was not run and that the
DLL is stale relative to the source.

## 3. Game log, when a launch happened

```
pwsh -File Tools/Get-ModLoadErrors.ps1
```

It keeps only error blocks naming this mod (packageId, mod name, folder, `RR_` prefix) and
warns when the log predates the current session. Two caveats to carry into the report:

- Attribution is a heuristic. A failure our data causes inside another mod's code often
  names only that mod - Combat Extended's `Verb_MeleeAttackCE` NRE on unpatched tools is
  the canonical case. If the run looks clean but the game misbehaves, rerun with `-All`.
- A def fix does not repair things already created from the old def (faction leaders,
  serialized vehicle components). Before calling a fix failed, check whether the thing being
  examined predates it.

## 4. Report

Lead with the verdict in one line: clean, or N errors and M warnings, and which validator
produced it. Then one bullet per problem, in this shape:

- **CheckName** - `path/to/file.xml` - what is wrong in plain words - what to do.

Group repeats of the same check. For the checks below, the "what to do" is already written;
point at it rather than re-deriving it.

| Check | Where the answer is |
|---|---|
| `CEToolsUnpatched` | CLAUDE.md "Under Combat Extended, EVERY `<tools>` entry must be a `ToolCE`" |
| `MissingTextureCollection` | CLAUDE.md "Collection graphics resolve texPath as a FOLDER" |
| `MissingWornGraphicMask` | CLAUDE.md "Worn apparel" - the mask is required when `useWornGraphicMask` is set |
| `PreceptNotGuaranteed` | CLAUDE.md "associatedMemes does not make a precept happen" - add it to the meme's `requireOne` |
| `RequireOneUnsatisfiable` | CLAUDE.md "A requireOne group can be unsatisfiable" - clone the precept without the gate |
| `VehiclePairBroken` | CLAUDE.md "Vehicle Framework needs a triad" - `thingToSpawn` must point back |
| `MeleeAnimTweakDataMissing` | CLAUDE.md "Melee Animation animates nothing it has no tweak data for" - `Tools/Derive-MeleeTweak.py` |
| `XenotypeUnreachable`, `RecipeUnreachable` | the def exists but nothing spawns, sells or unlocks it; wire it or delete it |
| `GatedGeneUnavailable` | the gene lives behind `MayRequireAnyOf` on another mod; mirror the gate on our `<li>` |
| `UnknownPawnKindTag` | an `apparelTags` / `weaponTags` entry nothing carries; typo or missing tag on the item |
| missing non-`RR_` texture (WARN) | vanilla art is in asset bundles and cannot be checked from disk; never write a placeholder over it |
| missing `RR_` texture (ERROR) | `pwsh -File Tools/New-PlaceholderTextures.ps1`, unless it is under `UI/Icons/Xenotypes` or `UI/Icons/Genes`, which `New-XenotypeIcons.ps1` owns |

Warnings are not noise. List them; say which are known-accepted (the vanilla texture paths
that cannot be verified from disk) and which are new.

## 5. What this skill does not do

It does not fix anything. It does not declare a feature finished: that still needs a game
launch and the "what to click" steps in `docs/PROGRESS.md`. And it does not replace reading
the report - a check name alone is not a diagnosis, so quote the message line too.
