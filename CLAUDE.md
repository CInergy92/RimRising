# CLAUDE.md — RimRising working notes

Verified conventions for this project. Everything here was confirmed against files on disk or by
running the code. If something is unverified it says so explicitly.

**The rule that matters most: verify, never recall.** Before writing any def, open a vanilla def of
the same type and mirror its structure. If you cannot find a real example of a field, do not use
the field.

---

## Environment

| Thing | Value |
|---|---|
| Game version | `1.6.4871 rev590` (from `Version.txt`) |
| Game install | `D:\SteamLibrary\steamapps\common\RimWorld` |
| Mods folder | `D:\SteamLibrary\steamapps\common\RimWorld\Mods` (confirmed by user) |
| Vanilla defs | `<install>\Data\{Core,Royalty,Ideology,Biotech,Anomaly,Odyssey}\Defs\` |
| Player log | `%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log` |
| Mod config | `...\RimWorld by Ludeon Studios\Config\ModsConfig.xml` |
| packageId | `cinergy92.rimrising` |
| DLC owned | All five, all active |

Vanilla index size, as a sanity check for the validator: **11,586 defNames, 838 `Name=` abstract
defs, across 1,558 XML files.** If `Test-ModDefs.ps1` reports numbers far off these, the game
updated or the scan is broken.

---

## Dependencies

**Ten** third-party mods are declared in `About.xml`. Seven are used directly, all confirmed
installed and indexed; the other three are declared so the mod list tells the truth: `brrainz.harmony`
and `OskarPotocki.VanillaFactionsExpanded.Core` because Alpha Genes needs them and RimWorld does not
resolve transitive dependencies, and `EBSG.Framework` because EBSG's own `LoadFolders.xml` gates
`EBSG_FertilityShortening` behind it (see PROGRESS, "the fourth false green").

| Mod | packageId | Workshop | What we use it for |
|---|---|---|---|
| [NL] Facial Animation | `Nals.FacialAnimation` | 1635901197 | Required by EyeGenes2 |
| [BT] EyeGenes2 | `Oppey.EyeGenes2` | 2898151329 | 34 eye-color genes incl. `Eyes_Golden`. Caste-matched eyes for every Color. |
| Expanded Biotech Style Genes AiO | `EBSG.AiO` | 3020821838 | `EBSG_FertilityShortening` for lowRed early reproduction |
| Alpha Genes | `sarg.alphagenes` | 2891845502 | `AG_LargerBodySize`, `AG_SmallerBodySize` |
| Expanded Archite Genes | `EBSG.Archite` | 3039936922 | `EBSG_ArchiteWoundHealing` — cpx 6, arc 2, **met 0**. The def itself carries `MayRequireAnyOf="MoreBiotechStyleGenes.Mod,MoreWoundHealingGenes.Mod"`, so it only exists when one of those is active; our `<li>` mirrors the gate and Gold loses it cleanly otherwise. |
| Biotech Capacitor Genes | `Petre27.BiotechCapacitorGenes` | 2882220355 | `Capacity_Boost_Tier_N` — **+N met for +N cpx**, the Gold dial |
| Lifespan Expectancy Genes | `BobnikTheIII.LifespanExpectancyGenes` | 3364691662 | `ExtremeLifespanExtension` (Gold), `ShortLifespan` (Red) |

**The dependency surface is now large.** Every one is a required subscription for anyone else who
runs this mod. That is the user's explicit direction and each earns its place, but do not add
another without asking.

### The xenogerm metabolism floor — decompiled, not guessed

`ilspycmd` on `Assembly-CSharp.dll` (`RimWorld.GeneTuning`) gives the real numbers:

```csharp
public static readonly IntRange BiostatRange = new IntRange(-5, 5);
public const int BaseMaxComplexity = 6;

public static readonly SimpleCurve MetabolismToFoodConsumptionFactorCurve = new SimpleCurve
{
    new CurvePoint(-5f, 2.25f),
    new CurvePoint(0f,  1f),
    new CurvePoint(5f,  0.5f)
};
```

Three consequences that drive real decisions:

1. **A xenotype below −5 metabolism cannot be assembled as a xenogerm at all.**
   `GeneCreationDialogBase` blocks it with `MetabolismTooLowToCreateXenogerm`. Nothing warns you at
   design time — the Color simply becomes impossible to carve into. `Get-XenotypeBudget.ps1` now
   checks this.
2. **Metabolism −5 is 2.25x food, and the curve ends there.** `SimpleCurve` clamps at its
   endpoints, so anything below −5 still costs 2.25x and no more. Lowering the floor buys design
   room without an unbounded food penalty.
3. `BaseMaxComplexity` is 6; gene processors raise it. Gold at complexity 49 (43 on a profile where
   the gated `EBSG_ArchiteWoundHealing` is absent — see the dependency table) needs a serious
   assembler build-out.

`Source/RimRising/BiostatRangePatch.cs` widens the floor to **−10** by reflection at startup. The
field is `public static readonly`, so there is no setter, but it is a plain static field and
reflection assigns it fine — no Harmony needed, since no method body is being altered. It is a
global change affecting other mods too, which is acceptable for a total conversion but is not a
local tweak.

**The C# builds without a game install.** References come from `Krafs.Rimworld.Ref` (pinned to the
game build, 1.6.4871) and `Lib.Harmony` (pinned to the Harmony mod, 2.4.1, runtime excluded), not
HintPaths into Steam - so cloud sessions can compile. Bump both when the game or Harmony updates.
Decompiling still needs the real `Assembly-CSharp.dll`, which only exists on the user's machine.

**To decompile anything else:** `ilspycmd -t <FullTypeName> <path-to-Assembly-CSharp.dll>`.
Install with `dotnet tool install -g ilspycmd --version 8.2.0.7535 --add-source https://api.nuget.org/v3/index.json`
— the unpinned latest fails to install, and this machine's global NuGet feed is offline-only.

### The metabolism/complexity lever

This is the single most useful balance fact in the project. Biotech couples capability to
metabolism, and **every met-positive vanilla gene is itself a drawback** (hemogen dependency,
deathrest, instability, depression, UV sensitivity). So a xenotype that is good at everything
normally has to eat ruinously.

Three genes break that coupling:

| Gene | cpx | met | arc |
|---|---|---|---|
| `Capacity_Boost_Tier_1..5` | +5..+25 | **+5..+25** | 0 |
| `ArchiteMetabolism` | +6 | **+6** | +2 |
| `EBSG_ArchiteWoundHealing` | +6 | 0 | +2 |

They let a xenotype pay in **complexity** instead of in hunger or weakness. For this mod that is
free real estate, because complexity is the carving gate — spending there deepens the mechanic we
want deep. Gold went from met −20/cpx 26 to met −4/cpx 49 with no capability change at all
(cpx 43, arc 2 when `EBSG_ArchiteWoundHealing` is gated out).

Optional, in `loadAfter` only: `Nals.FacialAnimationExperimentals` (1635901197's companion; the user
commonly runs it, but the mod works without it).

**`Test-ModDefs.ps1` reads `modDependencies` from our own About.xml** and indexes those mods'
GeneDefs automatically, so gene cross-references resolve. Add a dependency to About.xml and the
validator picks it up with no code change. `Get-XenotypeBudget.ps1` does the same — it must, or its
totals silently omit third-party genes and produce plausible-but-wrong numbers.

---

## Naming

- **`RR_` prefix on every defName we own.** No exceptions. Chosen to avoid collisions with the
  user's active mods: `AG_` (Alpha Genes), `VFE`, `CE_` (Combat Extended), `BS_` (Big and Small).
- Def files mirror vanilla's own layout: `1.6/Defs/GeneDefs/`, `1.6/Defs/FactionDefs/`, and so on.
- Texture paths for assets we own always end in a leaf starting `RR_`. The tooling keys off this to
  tell our textures from vanilla's — see "Textures" below. Breaking this convention breaks the
  tooling.

---

## Verified XML conventions

Confirmed by reading vanilla files. Citation given for each.

### Abstract defs and inheritance

```xml
<FactionDef ParentName="FactionBase" Name="OutlanderFactionBase" Abstract="True">
```

`ParentName` on the child, `Name` on the parent, `Abstract="True"` to keep the parent from
loading as a real def. Attributes, not nodes.
*Source: `Core/Defs/FactionDefs/Factions_Misc.xml`*

### Optional-DLC and optional-mod content

```xml
<li MayRequire="Ludeon.RimWorld.Ideology">Structure_Animist</li>
<Starjack MayRequire="Ludeon.RimWorld.Biotech,Ludeon.RimWorld.Odyssey">0.025</Starjack>
```

`MayRequire` works on `<li>` elements and on value nodes. Multiple packageIds are comma-separated
in a single attribute.
*Source: `Core/Defs/FactionDefs/Factions_Misc.xml`*

### packageId matching is case-insensitive

Big and Small ships `IfModActive="Ludeon.Rimworld.Royalty"` (lowercase `w`) and works.
*Source: workshop `2894397737/LoadFolders.xml`*

### About.xml field safety

```xml
<modIconPath IgnoreIfNoMatchingField="True">UI/RimRisingModIcon</modIconPath>
```

`IgnoreIfNoMatchingField="True"` makes a field safe against game versions that lack it.
*Source: VFE Core `About.xml`*

### Implants are a triad in one file

Vanilla colocates the item `ThingDef`, the `HediffDef`, and the install `RecipeDef` in the same
file. `InstallBionicArm` is defined at line 169 of the same file as the hediff it installs.
**Follow this. Do not scatter implants across `ThingDefs_*` / `HediffDefs/` / `RecipeDefs/`.**
*Source: `Core/Defs/HediffDefs/BodyParts/Hediffs_BodyParts_Bionic.xml`*

### Patch style for cross-mod work

```xml
<Operation Class="PatchOperationFindMod">
  <mods><li>Some Mod</li></mods>
  <match Class="PatchOperationSequence">
    <operations>
      <li Class="PatchOperationAdd">
        <success>Always</success>
        <xpath>/Defs/GeneDef[defName = "X"]/damageFactors</xpath>
        <value><Y>0</Y></value>
      </li>
    </operations>
  </match>
</Operation>
```

Guard with `PatchOperationFindMod`; put `<success>Always</success>` on individual operations so an
upstream rename degrades quietly instead of spamming red errors.
*Source: Alpha Genes `1.6/Patches/AlphaMythologyPatch.xml`*

### Backstories are pinned per pawn kind, not per xenotype

```xml
<backstoryFiltersOverride>
  <li><categories><li>RR_Red</li><li>RR_Rising</li></categories></li>
</backstoryFiltersOverride>
```

`PawnKindDef.backstoryFiltersOverride` replaces the faction's `backstoryFilters` for that kind.
There is no xenotype-level hook in XML, so Color-specific bios only reach pawns generated from a
kind that carries the override; colonists and wanderers do not. Every category named must have
at least one Childhood and one Adulthood, or generation has nothing to pick.
*Source: VFE Medieval 2 `1.6/Defs/PawnKindDefs_Humanlikes/PawnKinds_Kingdom.xml`; BackstoryDef
fields from Vanilla Backstories Expanded `1.6/Defs/BackstoryDefs/`*

### In a cloud session, working mods on GitHub stand in for vanilla defs

The game is not on disk in the cloud, so "open a vanilla def of the same type" is impossible
there. The substitute that keeps the rule's spirit: shallow-clone a public mod that works on 1.6
and mirror *its* use of the field (`git clone --depth 1 --filter=blob:none`; the GitHub API is
blocked but raw clones work). Used so far: `juanosarg/AlphaAnimals`, `juanosarg/AlphaBiomes`,
`juanosarg/AlphaGenes`, `Vanilla-Expanded/VanillaBackstoriesExpanded`,
`Vanilla-Expanded/VanillaFactionsExpanded-Medieval2`, `Vanilla-Expanded/VanillaPlantsExpanded-MorePlants`.
A field seen in one of those is a field that loads; a vanilla defName they reference exists.
Anything with no such example is noted as unverified in the def's header.

---

## Biotech facts that shape the whole design

### Xenotype budgets live on genes, not on the xenotype

`XenotypeDef` has **no** metabolic or complexity field. The budget is the sum of its member genes'
`biostatMet` / `biostatCpx` / `biostatArc`. Balance per-gene and total per-Color.

Fields observed on vanilla `XenotypeDef`, and the only ones to use without finding a new example:
`defName`, `label`, `description`, `descriptionShort`, `iconPath`, `displayPriority`,
`factionlessGenerationWeight`, `inheritable`, `nameMaker`, `nameMakerFemale`,
`chanceToUseNameMaker`, `genes`.
*Source: `Biotech/Defs/GeneDefs/XenotypeDefs.xml`; biostat grep across all of `Biotech/Defs/GeneDefs/`*

### Carving maps onto vanilla xenogerm surgery

`ImplantXenogerm` (`workerClass` `Recipe_ImplantXenogerm`) already exists, and its outcome def
includes `SurgeryOutcomeComp_XenogermComplexity`, which lowers success as xenogerm complexity
rises. **A high-complexity Gold genome therefore makes carving dangerous for free, with no C#.**
*Source: `Biotech/Defs/RecipeDefs/Recipes_Surgery_Misc.xml`, `SurgeryOutcomeEffectDefs.xml`*

Also: xenogerm implantation grants **xenogenes**, which are not inherited, while `inheritable`
xenotypes pass on **endogenes**. So a carved pawn's children inherit their birth Color, not the
carved one. That matches the setting exactly. See `docs/DESIGN.md`.

### What it actually takes to assemble a Gold xenogerm

Verified against `Building_GeneExtractor`, `GeneUtility.GenerateGeneSet` and the
gene processor def. Carving a Gold the legitimate way is a late-game institutional
project, which suits the setting but is worth knowing before promising it:

| Requirement | Why |
|---|---|
| **22 gene processors** | `GeneticComplexityIncrease` is **2** each on a base of 6. Gold is complexity 49, so 6 + 2x22 = 50 (19 processors at the gated-out 43). |
| Archogenetics research + **archite capsules** | Gold carries `ArchiteMetabolism` (arc 2) and `EBSG_ArchiteWoundHealing` (arc 2). |
| Archite genepacks **bought from traders** | The extractor scores any gene with `biostatArc > 0` at weight **zero**. Archite genes can never be extracted from a captured Gold, only traded for. |
| Many extractions | `Building_GeneExtractor` takes a random weighted SUBSET per use, not the whole genome. |

Metabolism is not a problem: Gold is met -4, inside the widened -10..5 range.

**Consequence for design:** vanilla xenogerm assembly is a valid carving path but an
enormously long one, and it is gated behind trade for the archite genes. If carving is
meant to be a story beat rather than a megaproject, RimRising needs its own shorter
route - a Carver recipe that grants a Color directly. That is a design decision, not a
technical one.

### U1, answered: a carved pawn reads as BASELINER

Settled by decompiling `GeneUtility.ImplantXenogermItem`, not by guessing:

```csharp
pawn.genes.SetXenotype(XenotypeDefOf.Baseliner);
pawn.genes.xenotypeName = xenogerm.xenotypeName;   // free text the player typed
pawn.genes.iconDef      = xenogerm.iconDef;
foreach (GeneDef item in xenogerm.GeneSet.GenesListForReading)
    pawn.genes.AddGene(item, xenogene: true);
```

The xenotype is set to **Baseliner unconditionally**. Nothing is matched against any
`XenotypeDef`; all that survives is a name and an icon. So a carved pawn has every gene
of a Gold and, as far as `Pawn.genes.Xenotype` is concerned, is nobody.

**Never read `Pawn.genes.Xenotype` to decide caste.** Every check in this mod did, which
meant a carved Gold had no rung on the ladder, could not bear a razor and could not hold
a Society title - the one pawn the setting is about was the one case handled worst.

Use `RR_CasteIdentity.ColorOf(pawn)`, which tries birth first and then falls back to
matching the pawn's genes against each Color's gene set, most specific first.

---

## Faction relations are player-relative — NPC-to-NPC is not authorable

**Correct an instinct here before wasting time on it.** RimWorld does not let a mod set how two NPC
factions feel about each other. Decompiling `GoodwillSituationWorker` shows every method takes only
`Faction other`, and the concrete workers resolve the second party as `Faction.OfPlayer`:

```csharp
private bool Applies(Faction other)
{
    if (!Applies(Faction.OfPlayer, other)) { return Applies(other, Faction.OfPlayer); }
    return true;
}
```

So `GoodwillSituationDef` answers "how does this faction feel about the colony", nothing else.
`FactionDef` has no `startingGoodwill` either — NPC relations are randomised at worldgen.

What *is* authorable:

| Lever | Effect |
|---|---|
| `permanentEnemy` | permanently hostile to the player |
| `permanentEnemyToEveryoneExcept` | hostile to **all factions**, listing FactionDef defNames as exceptions. The only true NPC-to-NPC lever. |
| `naturalEnemy` | hostile to the player by default |
| `hostileToFactionlessHumanlikes` | |
| `GoodwillSituationDef` + `naturalGoodwillOffset` | player-relative goodwill, optionally keyed on memes |

**Consequence for this mod:** "the Society hates the resistance" cannot be expressed directly. The
version that works is ideoligion-driven and belongs in Milestone 5 — a `GoodwillSituationDef` keyed
on our Color-hierarchy memes, so a colony running the Society's ideoligion is liked by the Society
and loathed by the resistance, and the reverse. That is pure XML once the memes exist, and it is the
version that actually matters in play, since the player is the only party whose relations the game
simulates meaningfully.

---

## Textures

**Vanilla textures are not loose files.** There is no `Data/Core/Textures/` — vanilla art ships
inside Unity asset bundles. Consequences:

- We cannot verify a vanilla texture path from disk. `Test-ModDefs.ps1` therefore **errors** on a
  missing `RR_*` texture and only **warns** on a missing non-`RR_` one.
- Never write a placeholder over a non-`RR_` path; it would shadow real game art.

### Collection graphics resolve texPath as a FOLDER

**This cost a false green. Do not repeat it.**

Graphic classes deriving from `Graphic_Collection` — `Graphic_StackCount`, `Graphic_Random` —
resolve `texPath` as a **directory** and load every image inside it, conventionally
`<leaf>_a`, `_b`, `_c`. Pointing one at a single file produces this at load:

```
Collection cannot init: No textures found at path Things/Item/Resource/RR_Ionsteel
```

A naive file-exists check passes it, because a file really is sitting at that exact path. Both
tools are now graphic-class aware: `Test-ModDefs.ps1` requires at least one image *under*
`<texPath>/` for a collection class, and `New-PlaceholderTextures.ps1` emits a folder of `_a/_b/_c`
variants instead of one file.

*Verified against Rimatomics (workshop `1127530465`), whose `Graphic_StackCount` texPaths are
folders of `_a`/`_b`/`_c` files.*

The general lesson: **a texture check that only asks "does a file exist at this path" is not a
texture check.** The graphic class decides what the path means.

### Icon ownership — two generators, do not cross the streams

| Script | Owns |
|---|---|
| `New-XenotypeIcons.ps1` | `UI/Icons/Xenotypes/*` and `UI/Icons/Genes/*` — real geometric glyph artwork |
| `New-PlaceholderTextures.ps1` | everything else `RR_*` — labelled flat squares |

`New-PlaceholderTextures.ps1` explicitly skips the icon paths, **including under `-Force`**, so it
cannot silently undo the icon set. If you add a new xenotype, add its glyph recipe to
`New-XenotypeIcons.ps1`; do not let the placeholder script fill it.

### Xenotype icons are tinted, and hue survives

`RimWorld.XenotypeDef.IconColor` is `Color(0.75, 0.75, 0.75)` — a uniform grey multiply. Uniform
multiplication scales all channels equally, so **hue is preserved and only brightness drops**.
Caste-colored glyphs therefore read correctly in the UI. Verified by decompiling `XenotypeDef`.

Every glyph is drawn twice: a dark translucent underlay at 1.7x stroke width, then the colored
stroke on top, so marks keep their edges against both pale and dark backgrounds.

### Copyright line on the sigils

The published Red Rising sigils are copyrighted artwork by a named illustrator and are **not
reproduced**, in whole or in part. `New-XenotypeIcons.ps1` composes original marks from a shared
primitive vocabulary (rings, bars, triangles, chevrons, crescents, spokes, arrows, dots). Only the
*idiom* — terse geometric marks in the manner of alchemical symbols — is shared, and an idiom is a
style, not an asset.

Where an obvious form would land too close to a published mark, it was deliberately changed: Red is
a shaft-and-rungs ladder rather than a ringed downward arrow, because the latter sits too near the
real Red sigil.

Sub-tiers inherit the parent glyph plus a modifier, so lineage is readable at a glance across a
21-xenotype list.

### Directional placeholders are translucent on purpose

A flat opaque labelled square is useless for judging a worn sprite: it is
orientation-blind AND it hides the pawn underneath, so `drawData` offsets and
scale cannot be assessed at all. This was reported from the starShell -
"impossible to tell the draw with the placeholder", which was exactly right.

`New-PlaceholderTextures.ps1` therefore draws any WORN, directional texture
(`_north` / `_east` / `_south`, with or without a body-type segment) as:

- a **translucent** fill, so the pawn shows through
- a red **crosshair on the exact centre** - if the offset is wrong, the crosshair
  visibly sits off the pawn, which is the whole diagnostic
- a white **arrow** in the facing direction, so a swapped facing is obvious
- the facing letter, and the label moved to the top clear of the crosshair

Non-directional placeholders (items, weapons, UI icons) stay opaque; there is
nothing behind them to align to.

### Reference for the real art pass

Ludeon's own texture guide: https://rimworldwiki.com/wiki/Modding_Tutorials/Textures
Read it before replacing any placeholder with real artwork - the placeholders here
are correctly *sized* and correctly *named*, which is all the tooling can verify.
Everything about masks, alpha, and how a graphic is actually authored is in there.

### Measured dimensions

Taken from installed reference mods, not from memory:

| Kind | Size | Measured from |
|---|---|---|
| Gene icon (`UI/Icons/Genes`) | 128x128 | Alpha Genes |
| Xenotype icon (`UI/Icons/Xenotypes`) | 64x64 | Alpha Genes |
| Item (`Things/Item`) | 128x128 | Alpha Genes |
| Weapon (`Things/Weapons`) | 256x256 | Combat Extended Guns |
| Everything else | 128x128 | **default, unverified — measure before relying on it** |

### Worn apparel: where the body actually is

**Measured, and this was the thing blocking worn apparel entirely.** Vanilla's pawn
and apparel art lives inside Unity asset bundles, so alignment could never be
checked from disk - every attempt would have been guessing and finding out in game.

Taken from a full-torso garment shipped loose by an installed mod (`Jumpsuit`), as
the fraction of a **256x256** canvas the body occupies:

| body | facing | x | y |
|---|---|---|---|
| Fat | east | 0.18-0.77 | 0.30-0.89 |
| Fat | north/south | 0.19-0.81 | 0.30-0.88 |
| Female | east | 0.29-0.62 | 0.31-0.88 |
| Female | north/south | 0.32-0.68 | 0.30-0.88 |
| Hulk | east | 0.23-0.73 | 0.28-0.97 |
| Hulk | north/south | 0.21-0.78 | 0.27-0.97 |
| Male | east | 0.34-0.66 | 0.34-0.83 |
| Male | north/south | 0.30-0.69 | 0.34-0.84 |
| Thin | east | 0.34-0.59 | 0.35-0.83 |
| Thin | north/south | 0.40-0.59 | 0.34-0.84 |

Ten unrelated mods' `Male_south` textures agreed to within a couple of percent, so
this is the convention rather than one author's habit. **Child is interpolated from
Thin, not measured** - the sample garment shipped no child variant, and that row is
the one to check in game.

`Tools/New-WornApparel.ps1` derives every shape from these boxes rather than
hard-coding coordinates, which is what makes one drawing fit six body types.

**SUPERSEDED 2026-10-08 - high-detail art IS generative now.** The user's direction:
"Anything that needs high detail like worn items and weapons need to be generative",
then "Same with vehicles". Worn apparel, weapons and vehicles are generated (fal) and
cleaned up by script; code-drawn art is for low-detail things only (loose items, icons,
glyphs).

The old concern still stands, and is now what the cleanup has to solve: a sprite is
judged on whether it sits on the body, and a generative model moves edges. So the
measurements above remain the registration target - generate the detail, then fit the
result back onto the measured box / the procedural silhouette by script. The starShell
(`Tools/Clean-GenStarShell.py`) is the first worked example.

The general pipeline, used for every armour, the demonHelm and every weapon:
`Tools/Gen-WornSet.ps1` (armour, all bodies and facings, base and Realistic Body) and
`Tools/Gen-Weapons.ps1` feed each existing sprite to `openai/gpt-image-2/edit` as the silhouette
reference plus ONE approved style image, then `Tools/Clean-GenWorn.py` cuts out the white, fits the
result onto the original's box (`--width-only` lets a redesign rise past the old top, as the horned
helm does), turns GOLD into the dye mask (`--dyed`) and outlines it. Originals are kept in
`Art/Gen/*/orig/` as the fit target for reruns; both scripts are resumable. Lessons: pick the style
image by eye before batching; check the game's Realistic Body folder too, since the user runs it and it
overrides Male/Female/Thin; `\w+` in a body-name regex swallows the prefix's underscores (use lazy);
a run that writes "no image" is usually `Exhausted balance` on fal - read the CLI's error before
assuming the content was refused.

The body boxes above are confirmed in play for the adult types, tint included.

**The Child row is unreachable, so it never needs measuring.**
`ApparelProperties.developmentalStageFilter` defaults to `DevelopmentalStage.Adult` in
C# - it is a field default, not something a def has to opt into - and nothing in this
mod nor any of its parent defs (`ArmorMachineableBase`, `ApparelMakeableBase`,
`ApparelBase`) overrides it. Every garment here is adult-only for free.

That row was interpolated from Thin rather than measured, because the sample garment
shipped no child variant. The 15 `*_Child_*` textures under `Textures/` are therefore
dead weight, kept only because they cost 68K and would be needed the moment any def
opted a garment in.

---

## Tooling

All in `/Tools`, run from the repo root. **Use whichever language suits the job** — the user's
direction; PowerShell is not required. Most existing tooling is PowerShell 7, and the 3D apparel
pipeline is Python run inside Blender (`Render-ApparelPasses.py`, `Compose-WornApparel.py`),
because Blender ships its own Python and numpy and needs no extra installs.

```bash
pwsh -File Tools/Test-ModDefs.ps1
```

| Script | Does |
|---|---|
| `Test-ModDefs.ps1` | Started as five checks (malformed XML, duplicate defName, vanilla collision, missing `RR_` texture, unresolvable `ParentName`) and now runs about forty named checks — among them `CEToolsUnpatched`, `PreceptNotGuaranteed`, `RequireOneUnsatisfiable`, `VehiclePairBroken`, `MissingTextureCollection`, `MissingWornGraphicMask`, `MeleeAnimTweakDataMissing`, `XenotypeUnreachable`, `RecipeUnreachable`, `GatedGeneUnavailable`. The script's own `.DESCRIPTION` header still lists only the original five. Exit 1 on any error. Caches the vanilla index under `Tools/.cache/`, keyed on `Version.txt`; pass `-RefreshVanillaCache` after a game update. |
| `New-PlaceholderTextures.ps1` | Writes flat colored labelled PNGs for referenced-but-missing `RR_*` paths. `-IncludeModArt` also does Preview/ModIcon. Color is a deterministic hash of the path, so it is stable between runs. |
| `Publish-Mod.ps1` | robocopy `/MIR` into the Mods folder, excluding the directories `.git`, `.github`, `.vs`, `Source`, `docs`, `Tools`, `Art`, `obj`, `bin` and the files `*.ps1`, `*.md`, `*.sln`, `*.csproj`, `*.user`, `.gitignore`, `.gitattributes`. `WeaponTweakData/` and `Sounds/` ship. Runs the validator first and refuses to publish on failure. |
| `Get-ModLoadErrors.ps1` | Splits `Player.log` into blocks, keeps error blocks naming our packageId / mod name / folder / `RR_` prefix. `-All` shows everyone's. Warns when the log is stale. |
| `Check-ModDefs.py` | **Cloud fallback** for `Test-ModDefs.ps1`: no game install or PowerShell needed. Malformed XML, unresolved `RR_` refs, gated-folder leaks, missing `RR_` textures (graphic-class aware), DefOf and Keyed checks. Cannot see vanilla, so a vanilla defName typo passes it. Exit 1 on error. Needs `lxml` and `Pillow`. |

Two project skills wrap this: **`/validate`** runs the validator, the build when `Source/` changed and the
log reader when a launch happened, and turns the report into a fix list keyed to this file's headings.
**`/newdef`** is "verify, never recall" as a procedure, with a per-type table of which file to open first
(`.claude/skills/newdef/references/sources.md`) and a grep script for the vanilla tree.

**Run `Test-ModDefs.ps1` before calling anything finished.** It has been negative-tested: a fixture
with the original five fault classes produced five errors and exit 1, and later checks were
negative-tested as they were added (see PROGRESS).

---

## Mistakes made once — do not repeat

### `RimWorld\Source\` is not the game source

It exists and looks authoritative, but holds only **43 sample `.cs` files** Ludeon ships as modding
examples. There is no `XenotypeDef.cs`, no `GeneDef.cs`. Field verification comes from vanilla XML,
or from decompiling `RimWorldWin64_Data\Managed\Assembly-CSharp.dll` with `ilspycmd` — install and
usage are under "Dependencies" above (the version must be pinned; the unpinned install fails).

### associatedMemes does not make a precept happen

**This shipped two features completely inert.** `associatedMemes` on a `PreceptDef`
makes it *eligible* for an ideoligion carrying that meme. It does **not** make
generation pick it, and with no "none" option on the issue a generated ideoligion
can carry the meme and take no stance on that issue at all.

The issue still appears in the ideoligion UI - every issue does - so the omission
looks like it worked. The razor lock and the Color ladder both passed inspection
this way while doing nothing.

`requireOne` on the **MemeDef** is the lever that forces the pick: a list of lists,
one precept taken from each inner list. Mirrored from Ideology's
`Memes_GroupRelation.xml`. `Test-ModDefs.ps1` now enforces this
(`PreceptNotGuaranteed`).

### A requireOne group can be unsatisfiable

`IdeoFoundation` drops any precept whose `requiredMemes` are absent. So a
`requireOne` group whose every member needs some *other* meme is satisfied by
nothing, silently.

Vanilla's `Scarification_Minor`, `_Heavy` and `_Extreme` all require `PainIsVirtue`.
Requiring scarification from a meme that does not also supply `PainIsVirtue` yields
no scarification precept at all. (`Scarification_Horrible` is the inverse - it
*conflicts* with `PainIsVirtue`.)

Where the required meme is unwanted, clone the precept without the gate rather than
patching `requiredMemes` off vanilla's - see `Precepts_Scarification.xml`. Patching
vanilla would hand the content to every other ideoligion in the player's game.
Checked by `RequireOneUnsatisfiable`.

### Never raise a HistoryEvent during pawn generation

RimWorld fabricates backstory relationships and hands out weapons while generating
pawns, long before a player faction exists. `IdeoUtility.Notify_HistoryEvent` walks
caravans, maps and the player faction, so raising an event then throws.

`HistoryEventsManager` catches and logs it, so nothing breaks - but the log fills at
every world creation and **the trace stops at the catch site**, so nothing in it
points at the mod responsible.

Guard with `ProgramState.Playing` plus `Faction.OfPlayerSilentFail != null`.
Checking `Find.HistoryEventsManager` is not enough; it already exists by then.

### PowerShell variable names are CASE-INSENSITIVE

`$pts` and `$Pts` are the same variable. A local named like its parameter in a
different case **silently empties the parameter** before the body reads it:

```powershell
function Stroke-Form {
    param([array] $Pts)
    $pts = @()                    # this just cleared $Pts
    foreach ($p in $Pts) { ... }  # iterates nothing
}
```

The function then draws nothing and GDI+ reports a bare "Parameter is not valid"
from somewhere else entirely. Cost a full debugging round; the stack trace pointed
at the drawing call, not at the assignment.

### RimWorld's art idiom, measured

Taken from an installed weapon sprite rather than remembered, and the difference
between this and the first attempt was the difference between "RimWorld" and
"infographic":

- **Muted, desaturated** colour. Steel is grey-blue, brass is dull ochre.
- The outline is **pure black**, and thick. (Corrected 2026-10-08: sampled from VAE, VTE and VFE
  sprites, `(0,0,0)` is the most common outline colour in every one. An earlier note here said dark
  warm grey, never black - measured from a single weapon, and wrong as a rule.)
- Forms are **rounded** - no sharp polygon corners anywhere.
- Shading is **one** lighter band along the upper-left edge. Not a gradient.
- Silhouette runs **diagonally**, lower-left to upper-right, filling most of the canvas.

Procedurally, rounded forms come from stroking a path with a wide round-capped pen
rather than filling a polygon - a capsule, not a rectangle - laid down three times:
wide dark outline, narrower body colour, thin offset highlight. See
`Tools/New-ItemIcons.ps1`.

**Shapes come from the reference too.** A razor is based on the *urumi*, a slender
flexible whip-sword - a long thin tapering blade, not a curved sabre.

### Heredocs eat backslashes in this environment

Writing PowerShell through a bash heredoc silently strips backslashes, even a quoted
`<<'PY'` one. `Replace('/', '\')` arrives as `Replace('/', '')`, which throws at
runtime rather than failing at parse time. It happened three times in one session; one
instance wrote three PNGs to `Textures/ThingsVehiclesRR_Drachenjager*.png` and reported
success.

**Use the file-writing tool for anything containing a backslash**, or build the
separator explicitly: `[char]92`, `[string][char]92`.

### Vehicle Framework needs a triad, and the halves must point at each other

Same shape as the implant triad, and just as unforgiving:

| Def | Names |
|---|---|
| `Vehicles.VehicleDef` | `buildDef`, plus `components` and turret keys |
| `Vehicles.VehicleTurretDef` | one per weapon, matched by the VehicleDef's `turretIds` |
| `Vehicles.VehicleBuildDef` | **`thingToSpawn`, pointing back at the VehicleDef** |

Omitting `thingToSpawn` loads with zero errors and produces an **empty architect slot**
plus a NullReferenceException every frame the tab is open, because
`VehicleGui.GizmoOnGUIWithMaterial` dereferences it immediately. Nothing in the load log
names the def; only the OnGUI stack trace does.

`<components>` is also mandatory: a vehicle's total health is their **sum**, so with none
declared the health tab throws on open. Parent from the framework's `BaseVehiclePawn`,
not from Vanilla Vehicles Expanded's `VehiclePawn_Armored` — VVE's chain adds its own
comps and would make VVE a second requirement.

### Under Combat Extended, EVERY `<tools>` entry must be a `ToolCE`

**This crashed the game and named nobody.** `Verb_MeleeAttackCE.DamageInfosToApply`
casts each tool on the weapon to `CombatExtended.ToolCE` and reads armour penetration
off the result, so a weapon left with vanilla `<li>` tools throws a
`NullReferenceException` on **every swing**. The log shows:

```
Exception ticking <pawn>: System.NullReferenceException
  at CombatExtended.Verb_MeleeAttackCE+<DamageInfosToApply>d__38.MoveNext
```

Not one frame names this mod. The fault is entirely inside CE, caused by our data.

**Guns are not exempt.** `PatchOperationMakeGunCECompatible` was decompiled to check:
it rewrites `statBases`, `costList`, verb properties, comps, weapon classes, tags and
the research prereq, and **never touches `<tools>`**. CE patches every vanilla gun's
tools in a separate `PatchOperationReplace` for exactly this reason, so a stock or
grip bash crashes the same way a sword does.

Weapon part groups — `Handle`, `Edge`, `Grip`, `Stock`, `Barrel`, `Muzzle` — are
**CE's own** `BodyPartGroupDef`s (`CE/Defs/Bodies/BodyPartGroups.xml`), not vanilla.
They are only nameable from inside the CE-gated patch folder.

`Test-ModDefs.ps1` now fails on any def with `<tools>` that has no
`PatchOperationReplace` on its `/tools` (`CEToolsUnpatched`), negative-tested.

Calibration lives in CE's own `Patches/Core/ThingDefs_Misc/Weapons_Guns.xml` — copy
those numbers rather than converting vanilla ones. CE's `armorPenetrationSharp` is in
millimetres of steel, not a 0..1 fraction.

### Under Combat Extended, vehicle turrets need CE projectiles AND a CE extension

`VehicleTurret` forks its fire path on whether CE is loaded. With CE it calls
`CE_Utility.LaunchProjectileCE`, which needs both:

1. a `Vehicles.CETurretDataDefModExtension` supplying `ammoSet`, and
2. a **CE-native projectile** — CE casts it to its own type, so a vanilla
   `BaseBullet` descendant throws `InvalidCastException` on every shot.

Only name ammo sets from CE's own `Defs/` tree. CE defines hundreds more under
`ModPatches/<Some Mod>/` which exist only for players running that third mod.

### Melee Animation animates nothing it has no tweak data for

Reported from play as "the razors don't work with the melee animations mod", with **nothing in the
log** — from Melee Animation's side nothing went wrong, it simply has no data for the weapon.

Decompiled from `zAnimationMod.dll` (workshop `2944488802`, `co.uk.epicguru.meleeanimation`).
Everything is keyed on a per-weapon JSON. With none registered, `ReqInput` comes out empty:

```csharp
TypeFlags = td?.MeleeWeaponType ?? 0;
(SizeFlags, CategoryFlags) = td?.GetCategory() ?? (0, 0);
```

Every `AnimDef` requirement is then unsatisfiable, so the weapon falls back to vanilla's static
equipped sprite: no idle, no attack, no duel, no execution. `IdleControllerComp` says it outright —
`if (val != null && def.IsMeleeWeapon() && TryGetTweakData() != null)`.

**No patch to their mod is needed.** `TweakDataManager.MakeOverrideTweakDataFileMap` walks every
*active* mod's own `WeaponTweakData/` folder and indexes the JSON by bare file name, so a file we
ship wins the lookup. The name is fixed by `ItemTweakData.MakeFileName`:

```
<defName>_<packageId>.json          # _steam / _local / _copy suffixes stripped
```

So ours live in `WeaponTweakData/` at the repo root — **not** under `1.6/` — and ship because
`Publish-Mod.ps1` excludes only `Source`, `docs`, `Tools`, `Art`, `obj`, `bin`. A
`<packageId>.txt` holding the mod's display name sits beside them; the in-game tweak editor writes
one and uses it to label the group.

#### Deriving the numbers without the in-game editor

The author hand-tunes these in a visual editor (`ItemTweakData`'s def constructor sets
`Rotation = 0` and derives nothing), so there is no oracle in the code. The convention was
recovered by measuring four reference sprites against their shipped JSON:

| weapon | sprite principal axis | `Rotation` in the JSON |
|---|---|---|
| `AG_ForsakenLongBlade` | 39.9° | 40 |
| `AG_ForsakenSpear` | 45.6° | 45 |
| `AG_ForsakenBulkSword` | 47.6° | 45 |
| `AG_ForsakenBattleAxe` | 66.8° | 65 |

`Rotation` is the sprite's own principal axis, CCW from +X with +Y up. The rest is one frame:
**origin at the canvas centre, units of canvas widths** (equal to world units while `drawSize` is 1),
projected onto that axis.

```
OffX       = -(t of the grip point)
BladeStart = OffX + (t where the blade begins)
BladeEnd   = OffX + (t of the far end of the sprite)
```

Checked both ways: reconstructing `BladeEnd` for the long blade gives 0.661 against the shipped
0.641, and for the spear 0.691 against 0.679 — inside 2%, which is the author nudging the tip a
hair inside the last antialiased pixel. Do the same.

`MeleeWeaponType` is the flags enum `Long_Blunt 1, Long_Sharp 2, Long_Stab 4, Short_Blunt 8,
Short_Sharp 16, Short_Stab 32`; a sword is 6, a curved cutting weapon 2.

**Both razors are 6, and the Reaper's razor is deliberately not the 2 its sprite suggests.** The
type decides which executions the weapon qualifies for, and the difference is large: 6 matches
fifteen of them, 2 matches five once the two behead animations are discounted for shipping at
`relativeProbability 0`. Classifying the Reaper's razor by its drawn sickle would have been reading
the sprite instead of the setting — a razor holds whatever shape its bearer sets it to, so it is
only a sickle while Darrow wants one. Do not "correct" this back on the strength of the artwork.

`HandsMode` serialises as
an integer — `1` is main-hand-only, and 536 of the 3,107 shipped files use it. Size is not authored:
`IdleClassifier` derives it from `max(BladeLength, |BladeEnd|)`, Tiny at ≤0.63 and Colossal at ≥1.37.

`Tools/Test-ModDefs.ps1` checks this (`MeleeAnimTweakDataMissing`, WARN — Melee Animation is not a
declared dependency). It counts a def as melee when it has or inherits `<tools>` and declares no
`verbs/li/defaultProjectile`, which mirrors `IsWeapon && !IsRangedWeapon`.

**Not our fault, in the same log:** `[MeleeAnim] Failed: failed to spawn flyer.` is the *lasso*.
`GrappleFlyer.MakeGrappleFlyer` returns null when the victim is already standing on the target cell
or has despawned. `[MeleeAnim] <pawn> has bad job: Wait_Combat. Cancelling animation.` is
`AnimRenderer` dropping an animation whose pawn got re-tasked. Neither involves weapon data.

### Judge worn art in game, beside other mods' armour - the scripted test scene

`Source/RimRising/TestScene.cs` is a dormant `MapComponent` that only runs when the game is started
with `-rrtestscene`. Run:

```
RimWorldWin64.exe -quicktest -rrtestscene rrtestout=<dir> -rrtestquit -screen-fullscreen 0 -screen-width 1920 -screen-height 1080
```

`-quicktest` is RimWorld's own flag (`Verse.QuickStarter`): a fresh map with the current mod list,
so RimSort's list is never touched. The scene clears ground, sets noon, spawns factionless Baseliner
pawns (one per body type, per facing, per armour, ours dyed gold), pauses, and writes one screenshot
per **body type x facing** with all armours side by side, via `ScreenCapture`. It logs
`[RimRising] TESTSCENE DONE` and exits. The armour list is at the top of the file; missing defs
are skipped and named in the log.

Three things it had to learn:
- **Camera+ (`brrainz.cameraplus`) owns the zoom.** It maps `rootSize` from an input range of 11-60
  onto its own curve, so `rootSize` is not cells, and below 11 that curve raises a negative to a
  fractional power and the camera goes NaN (a blank shot of bare ground). The scene bisects
  `rootSize` inside the valid range against `Camera.orthographicSize`, which Camera+ itself writes.
- **The debug log auto-opens on any red error** and other mods log plenty; the scene closes every
  window before each capture.
- **Colonists fill the colonist bar** - the test pawns are factionless.

What the first comparison showed (pulse armour, 3D pipeline, 2026-10-08): other mods' armour is a
few big flat panels with heavy outlines, and it **extends beyond the body** - pauldrons, chest
plates, collars - which is what makes it read as armour. Fitting exactly to the body outline reads
as a bodysuit. The user's bodies also show two legs at the bottom (their body/face mods); armour
sprites follow that.

### Worn armour is drawn as flat panels - Tools/Draw-PanelArmor.py

After the 3D render was judged in game (mottled, skinny), pulse armour was redrawn the way every
comparison armour is built, and that is the method for worn armour from here on:

- **Each panel is its own shape with its own thick outline**, drawn back to front so plates overlap
  and read as separate pieces. Outlines measured against the others in game: 6 px silhouette, 4 px
  per panel at 256 - half that looked soft beside them.
- **Shading is by plane**, light from the left: each panel's right face is the darker one. Not edge
  bevels, not gradients.
- **Armour extends past the body.** Measured overhang past the Male box, per side: VAE heavy marine
  ~0.40, AG Forsaken ~0.45, VFE legionnaire ~0.27, VAE trooper ~0.10. Pulse armour sits near 0.3.
- **Fixed-size features stay fixed size.** Pauldrons scaled with the box were enormous on Fat and
  spindly on Thin; `Frame.k` converts a width given in Male box widths into each body's units.
- **Define the waist and hips with dark suit showing between plates**, or the lower half reads as one
  block - a tabard, not plate.
- **The sprite stops at the hips.** Legs belong to the body, or to a leg mod.

Designs are coordinates in body-box units, so one design fits all five bodies. `--icon` draws the
item icon from the same front design, so icon and worn sprite cannot drift apart.
`New-WornApparel.ps1` no longer draws pulse armour.

### Every worn armour is a Draw-PanelArmor.py design

`pulse`, `recoil`, `duro`, `scarab` and `cloak` in `DESIGNS`, each registered as
`(function, dyed?, has Realistic Body legs?)`. Only dyed designs write tint masks. The five are
deliberately distinct at a glance: pulse is a few big shells with a generator pack; recoil is stacked
**lames** ("plates that coil around the body"); duro is a bare stamped cuirass with no suit under
it, so the pawn's own clothes show; scarab is a near-black fitted skin with a diagonal weave and no
bulk; the cloak is a shoulder **mantle** over falling panels. A cloak without the mantle read as
trousers from the front, and its item icon shows its back for the same reason (`ICON_FACING`).

**Headgear** is a design too (`helm`, the demonHelm): it registers against the head, so it draws in
the measured head box (0.29-0.70 x 0.26-0.70) with one texture per facing and no body types, scaled
by `HELM_SCALE` 0.80 - drawn straight into the box it came out a third bigger than vanilla's marine
helmet on the same heads, because the design pads past the box to cover hair.

**Realistic Body variants** (`--rb`) exist for every design that covers the legs: plate greaves for
the two plate suits, skin-tight legs for scarabSkin, a longer hem for the cloak. All five carry
`THIGAPPE_IgnoreTag`. duroArmor is torso-only, so its base sprites serve everywhere.

**Test-scene rules learned the hard way:** dye only `RR_CasteColored` armour, the same rule
`CasteArmor.cs` applies in play - every apparel has a `CompColorable`, and dyeing anything `RR_`
turned duroArmor, scarabSkin and the cloak gold. Pin test pawns to adult age: Biotech draws 13-18
year olds smaller, and one teenage Hulk made pulse armour look undersized.

### Weapons are drawn flat too - Tools/Draw-Weapons.py

The razor family (both weapon sprites - which are also their ground and inventory icons - the
whip-form ability icon, the lash projectile and the razor-bearing precept icon) is drawn by
`Tools/Draw-Weapons.py` in vanilla's weapon idiom: a heavy dark outline, a two-tone blade split along
its length, at most one accent. The ControlNet-painted razor it replaced was the one soft,
thin-outlined object in the test scene's ground row beside vanilla's longsword, monosword, plasma
sword and gladius. The ground row also settled orientation: our diagonal razors lie at the same
angle as vanilla's own weapons.

**Weapon geometry is load-bearing.** Melee Animation's tweak data is derived from where the hand
closes on the sprite. After any redraw, re-derive with `Tools/Derive-MeleeTweak.py` - it was checked
by reproducing the shipped values exactly from the old sprites before being trusted on new ones.
The precept icon uses `razor(128, inset=0.07)`; the weapon sprite must keep `inset=0`.

`TestScene.cs` has `rrtestmode=weapons`: each weapon on the ground, then held by drafted colonists.
Melee Animation draws a drafted pawn's weapon through its idle animation, which only starts once game
time runs - paused at once, every held weapon, vanilla's included, was absent - so that mode runs
~2.5 s before pausing.

### The starShell is the one generated worn sprite - Tools/Clean-GenStarShell.py

The code-drawn starShell was judged "much lower quality" beside The Dead Man's Switch - MobileDragoon
(the installed mod that builds real suits on the Exosuit Framework), and the user chose
generate-and-clean-up. It is an exception to "worn apparel does not go through the generative
pipeline", and it works because an exosuit module does not register against a body type's
shoulders: it only has to sit in the Dragoon's measured footprint.

- Generated with fal: the front view with `openai/gpt-image-2`, the other facings and the hood and arm
  with the edit endpoints, the front view as reference so all three match. Prompts and request ids are
  in `Art/Gen/StarShell/fal_manifest.jsonl`; only the images actually used are kept.
- **gpt-image-2 on fal no longer takes `background=transparent`** (HTTP 422). Generate on flat white
  and cut out by border flood fill.
- **nano-banana's edit kept the front view and bolted a cannon on when asked for a side view.**
  gpt-image-2's edit endpoint, with "no arms, no weapons" spelled out, gave a true profile.
- Cleanup: greyscale (the framework's `colorGenerator` tint multiplies everything), fit to the
  footprint (core y 0.10-0.97 of 512, hood the middle half, arm rotated per facing like the
  Dragoon's), 6 px black outline at 512. Rerun the script after replacing any source image.
- Defs: no `drawData` offset on the core (the Dragoon's cores have none) and default scale on the
  hood; the old `(0,0,0.35)` and `1.6` lifted and inflated the placeholder.

### THIGAPPE refits apparel it has no data for - opt out with THIGAPPE_IgnoreTag

The user runs [NL] Realistic Body with Apparel Paper Pattern and **THIGAPPE**, which warps any
apparel lacking APP data onto Realistic Body's contours with a generic mask. In the test scene that
gave pulse armour a bust and hips it was never drawn with, and pushed the pauldrons onto a faded,
soft-edged side layer - the texture itself was verified fully opaque. Other armour mods look clean
because they ship refit data.

THIGAPPE's `1.6/Patches/THIGAPPE_GlobalIgnores.xml` skips any apparel whose `apparel/tags` has
`THIGAPPE_IgnoreTag`. Pulse armour carries it; a plain string tag, inert without THIGAPPE. The cost:
on Realistic Body, bare shins show below the hip plates. Real support would be APP fine-tune Defs.

### A faction that confers titles needs royalTitleInheritanceRelations

`Pawn_RoyaltyTracker.SetTitle` assigns an heir on every grant, and
`RoyalTitleInheritanceWorker.FindHeir` walks `faction.def.royalTitleInheritanceRelations` with no
null check; vanilla skips the search only for the Empire. Both our royal factions shipped without
the list, so **every Society title grant threw**. It loaded clean and went unnoticed until a pawn
kind used `titleRequired` and generation looped on the exception. Checked by
`RoyalFactionNoInheritance`.

PawnGenerator order (decompiled): ideoligion, then **title, then gear**. So `titleRequired` on a
kind is enough to make title-gated apparel wearable at generation.

### More test-scene modes

- `rrtestmode=kinds` generates ten of each kind in `TestScene.Kinds` for a faction that fields it,
  logging Colour, titles, weapon and apparel. No screenshots; read `Player.log` for `KINDS`.
- `rrtestmode=whip`: drafted Golds lash targets in four armours, eight rounds, logging damage per
  lash. The targets are factionless and **flee** when hurt, and a lash at a pawn running out of reach
  ends without firing. The scene puts them back on their marks every round. Casters are rerolled if
  they come out pacifist.

### Combat Extended and damage with no verb

CE resolves a **deflected** sharp hit as blunt, taking the blunt penetration from the attacking
melee verb. A DamageInfo built in code (the whip lash) has none, so CE falls back to the DamageDef's
`defaultArmorPenetration`, and failing that logs "has null verb, overriding AP" and uses **50**.
Give such damage its own DamageDef (`RR_RazorLash`, parent `CutBase`) and set the default in the CE
folder.

### Persisted state does not retroactively update

A def fix does not repair things already created from the old def. Faction leaders are
fixed at worldgen; a `VehiclePawn` serializes its own component list. Both looked like
failed fixes and were not. **When a fix appears not to have taken, check whether the
thing being examined predates it.**

### PowerShell traps hit while writing the tooling

1. **`New-Object Type(a, b, $x - 1)` parses the parens as an array literal**, so the arithmetic
   binds to the wrong operand and you get `[System.Object[]] does not contain op_Subtraction`.
   Compute into variables first and use `-ArgumentList`.
2. **Returning a `HashSet` from a function unrolls it.** An empty set becomes `$null`, a populated
   one becomes `Object[]`. Return `, $set` with the comma operator, or wrap it in a `pscustomobject`.
3. **The literal `0xFFFFFFFF` parses as Int32 `-1`.** Casting that to an unsigned type throws.
   Write `4294967295`, or suffix the literal.
4. **`$x = if (...) { @() }` assigns `$null`**, because the empty array unrolls. Same root cause as
   (2). Use `, @()`. This bit `Get-ModLoadErrors.ps1` on its first clean run.
5. **`$pid` is a read-only automatic variable.** Assigning it throws
   "Cannot overwrite variable PID because it is read-only or constant." Use `$pkgId`.
6. Bash heredocs choke on this repo's markdown. Use the file-writing tool for docs, not `cat <<EOF`.

### RimSort "Missing Publish Field ID" is expected

RimSort flags local mods for having no Publish Field ID. That field only exists on Workshop-published
mods, so a local development mod will always be flagged. **Not an error, no action.** It resolves
itself if and when the mod is published to the Workshop. Package ID is separate and is present.

### grep note

`grep -P` is unavailable in this environment (locale is not UTF-8). Use basic or extended regex,
or `sed`.

---

## Working agreements

- One commit per logical unit, message naming the milestone.
- `docs/PROGRESS.md` tracks milestone status, open questions, known errors.
- `docs/DESIGN.md` holds content design. **The user is the authority on the setting.** When a
  decision is a lore judgment call rather than a technical one, put options to them; do not pick.
- Nothing is done until the game loads it with zero red errors. After each module, tell the user
  exactly what to click in game to verify.
- Stop and ask before anything that needs C# where XML was assumed, or a DLC that is not owned.
- No copyrighted text or assets. Concept and faction names are fine; verbatim prose is not. All
  descriptions are original writing.
- **Nothing sexual is ever applied to, or implied about, anyone under 18.** The user's standing
  rule, and it covers flavour text as well as mechanics: childhood backstories, child pawns,
  reproductive surgery (`RR_CarveReproduction` is minAllowedAge 18 for this reason). The setting's
  Pinks are trained for pleasure work as adults; their childhood text describes music, manners and
  service, never that. A Garden childhood saying Pinks were "taught to please" was rewritten on
  merge for exactly this.
