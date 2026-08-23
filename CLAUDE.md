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
5. Bash heredocs choke on this repo's markdown. Use the file-writing tool for docs, not `cat <<EOF`.

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
