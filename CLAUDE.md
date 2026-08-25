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

**Seven** third-party mods are hard dependencies, all confirmed installed and indexed:

| Mod | packageId | Workshop | What we use it for |
|---|---|---|---|
| [NL] Facial Animation | `Nals.FacialAnimation` | 1635901197 | Required by EyeGenes2 |
| [BT] EyeGenes2 | `Oppey.EyeGenes2` | 2898151329 | 34 eye-color genes incl. `Eyes_Golden`. Caste-matched eyes for every Color. |
| Expanded Biotech Style Genes AiO | `EBSG.AiO` | 3020821838 | `EBSG_FertilityShortening` for lowRed early reproduction |
| Alpha Genes | `sarg.alphagenes` | 2891845502 | `AG_LargerBodySize`, `AG_SmallerBodySize` |
| Expanded Archite Genes | `EBSG.Archite` | 3039936922 | `EBSG_ArchiteWoundHealing` — cpx 6, arc 2, **met 0** |
| Biotech Capacitor Genes | `Petre27.BiotechCapacitorGenes` | 2882220355 | `Capacity_Boost_Tier_N` — **+N met for +N cpx**, the Gold dial |
| Lifespan Expectancy Genes | `BobnikTheIII.LifespanExpectancyGenes` | 3364691662 | `ExtremeLifespanExtension` (Gold), `ShortLifespan` (Red) |

**The dependency surface is now large.** Every one is a required subscription for anyone else who
runs this mod. That is the user's explicit direction and each earns its place, but do not add an
eighth without asking.

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
3. `BaseMaxComplexity` is 6; gene processors raise it. Gold at complexity 49 needs a serious
   assembler build-out.

`Source/RimRising/BiostatRangePatch.cs` widens the floor to **−10** by reflection at startup. The
field is `public static readonly`, so there is no setter, but it is a plain static field and
reflection assigns it fine — no Harmony needed, since no method body is being altered. It is a
global change affecting other mods too, which is acceptable for a total conversion but is not a
local tweak.

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
want deep. Gold went from met −20/cpx 26 to met −4/cpx 49 with no capability change at all.

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

**Unverified:** whether implanting a xenogerm assembled from an exact Color gene set makes the pawn
read as that Color, or as "Hybrid". That is C# behaviour in `Building_GeneAssembler` and is not
visible in XML. Must be tested in game before Milestone 2 is called done.

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

Apparel and pawn-worn sizes are still unverified. Measure at Milestone 4.

---

## Tooling

All in `/Tools`, PowerShell 7. Run from the repo root.

```bash
pwsh -File Tools/Test-ModDefs.ps1
```

| Script | Does |
|---|---|
| `Test-ModDefs.ps1` | Five checks: malformed XML, duplicate defName, vanilla collision, missing `RR_` texture, unresolvable `ParentName`. Exit 1 on any error. Caches the vanilla index under `Tools/.cache/`, keyed on `Version.txt`; pass `-RefreshVanillaCache` after a game update. |
| `New-PlaceholderTextures.ps1` | Writes flat colored labelled PNGs for referenced-but-missing `RR_*` paths. `-IncludeModArt` also does Preview/ModIcon. Color is a deterministic hash of the path, so it is stable between runs. |
| `Publish-Mod.ps1` | robocopy `/MIR` into the Mods folder, excluding `Source`, `docs`, `Tools`, `.git`, `*.ps1`, `*.md`. Runs the validator first and refuses to publish on failure. |
| `Get-ModLoadErrors.ps1` | Splits `Player.log` into blocks, keeps error blocks naming our packageId / mod name / folder / `RR_` prefix. `-All` shows everyone's. Warns when the log is stale. |

**Run `Test-ModDefs.ps1` before calling anything finished.** It has been negative-tested: a fixture
with all five fault classes produced five errors and exit 1.

---

## Mistakes made once — do not repeat

### `RimWorld\Source\` is not the game source

It exists and looks authoritative, but holds only **43 sample `.cs` files** Ludeon ships as modding
examples. There is no `XenotypeDef.cs`, no `GeneDef.cs`. Field verification comes from vanilla XML,
or from decompiling `RimWorldWin64_Data\Managed\Assembly-CSharp.dll`. No decompiler is installed;
`dotnet tool install -g ilspycmd` if one becomes necessary.

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

### Under Combat Extended, vehicle turrets need CE projectiles AND a CE extension

`VehicleTurret` forks its fire path on whether CE is loaded. With CE it calls
`CE_Utility.LaunchProjectileCE`, which needs both:

1. a `Vehicles.CETurretDataDefModExtension` supplying `ammoSet`, and
2. a **CE-native projectile** — CE casts it to its own type, so a vanilla
   `BaseBullet` descendant throws `InvalidCastException` on every shot.

Only name ammo sets from CE's own `Defs/` tree. CE defines hundreds more under
`ModPatches/<Some Mod>/` which exist only for players running that third mod.

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
