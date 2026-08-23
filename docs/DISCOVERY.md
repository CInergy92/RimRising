# DISCOVERY — Red Rising Total Conversion

Phase 0 findings. Written before any mod content exists.
Date of scan: 2026-08-23. Everything below was read off disk, not recalled.

---

## 1. Game version — VERIFIED

`D:\SteamLibrary\steamapps\common\RimWorld\Version.txt`

```
1.6.4871 rev590
```

**Target version is 1.6.** All version-specific folders will be `1.6/`.

### Version discrepancies worth knowing

| Source | Version string |
|---|---|
| `Version.txt` (install) | `1.6.4871 rev590` |
| `Config\ModsConfig.xml` (last written by the game) | `1.6.4633 rev1260` |

The config was written by an older 1.6 build; the game has since patched. Same minor version, so
no `LoadFolders.xml` consequence. It does mean **the game has not been launched since the last
update**, which matters for log-based verification (see section 6).

### DLC present on disk — VERIFIED

`Data/` contains: `Core`, `Royalty`, `Ideology`, `Biotech`, `Anomaly`, `Odyssey` — all five
expansions, all five listed under `<knownExpansions>` and all five active in `ModsConfig.xml`.
The CONFIG block's DLC_OWNED line is confirmed by the filesystem.

---

## 2. Def type inventory and best vanilla examples

Paths are relative to `D:\SteamLibrary\steamapps\common\RimWorld\Data\`.

### Milestone 2 — the Color system (Biotech)

| Def type | Best vanilla example | Notes |
|---|---|---|
| `XenotypeDef` | `Biotech/Defs/GeneDefs/XenotypeDefs.xml` | 319 lines, ~12 xenotypes. Dirtmole and Genie are the closest structural analogues to a Color: a themed gene bundle with real upsides and real costs. |
| `GeneDef` | `Biotech/Defs/GeneDefs/GeneDefs_Misc.xml` | General-purpose genes. |
| `GeneDef` (aptitudes/stat) | `Biotech/Defs/GeneDefs/GeneDefs_Endogenes.xml` | |
| `GeneDef` (ability-granting) | `Biotech/Defs/GeneDefs/GeneDefs_Abilities.xml` | |
| `GeneDef` (skin/eye/hair spectrum) | `Biotech/Defs/GeneDefs/GeneDefs_Spectrum.xml` | Directly relevant — Colors need colored skin/eyes/hair. |
| `GeneTemplateDef` | `Biotech/Defs/GeneDefs/GeneTemplateDefs.xml` | How vanilla mass-generates aptitude genes. |
| `GeneCategoryDef` | `Biotech/Defs/GeneDefs/GeneCategoryDefs.xml` | We will need our own category for Color genes. |
| `XenotypeIconDef` | `Biotech/Defs/GeneDefs/XenotypeIconDefs.xml` | |
| `XenotypeDef` (Odyssey additions) | `Odyssey/Defs/GeneDefs/XenotypeDefs.xml` | Starjack — proof Odyssey adds xenotypes too. |

**Budget fields — VERIFIED present in vanilla `GeneDef`:** `biostatMet`, `biostatCpx`, `biostatArc`.
Confirmed by grepping all of `Biotech/Defs/GeneDefs/*.xml`; those three and no others.

**IMPORTANT — VERIFIED:** `XenotypeDef` has **no** metabolic or complexity field of its own. A
xenotype's totals are the sum of its member genes' `biostat*` values. Balancing therefore happens
per-gene, not per-xenotype. Fields actually observed on vanilla `XenotypeDef`: `defName`, `label`,
`description`, `descriptionShort`, `iconPath`, `displayPriority`, `factionlessGenerationWeight`,
`inheritable`, `nameMaker`, `nameMakerFemale`, `chanceToUseNameMaker`, `genes`. I will not use any
field outside that set without finding another example first.

### Milestone 3 — factions and pawn kinds

| Def type | Best vanilla example | Notes |
|---|---|---|
| `FactionDef` (abstract base + inheritance) | `Core/Defs/FactionDefs/Factions_Misc.xml` (699 lines) | Contains `OutlanderFactionBase` — the cleanest `ParentName`/`Abstract="True"` pattern, plus `xenotypeSet`, `backstoryFilters`, `structureMemeWeights`, `allowedCultures`, `techLevel`. |
| `FactionDef` (large, with `pawnGroupMakers`) | `Royalty/Defs/FactionDefs/Faction_Empire.xml` | The best model for a stratified faction with distinct roles per pawn group. Highest-value reference for the Society. |
| `FactionDef` (hidden / no settlement) | `Core/Defs/FactionDefs/Factions_Hidden.xml` | Also contains `pawnGroupMakers`. |
| `FactionDef` (player) | `Core/Defs/FactionDefs/Factions_Player.xml` | Needed for player-faction starts in M6. |
| `FactionDef` (Biotech, xenotype-flavored) | `Biotech/Defs/FactionDefs/Factions_Misc.xml` | Also has `pawnGroupMakers`. |
| `PawnKindDef` (humanlike) | `Core/Defs/PawnKindDefs_Humanlikes/PawnKinds_Outlander.xml` | |
| `PawnKindDef` (spacer / high-tech) | `Core/Defs/PawnKindDefs_Humanlikes/PawnKinds_Spacer.xml` | Closest tech tier to ours. |
| `PawnKindDef` (Biotech, xenotype-bound) | `Biotech/Defs/PawnKindDefs_Humanlikes/` | Shows how a PawnKind pins a xenotype. |
| `PawnGroupKindDef` | `Core/Defs/Misc/PawnGroupKindDefs/` | |
| `BackstoryDef` | `Core/Defs/BackstoryDefs/` | Caste-specific backstories live here. |
| `CultureDef` | `Core/Defs/CultureDefs/`, `Royalty/Defs/CultureDefs/` | Drives naming; relevant for Color-specific names. |
| `RulePackDef` (name makers) | `Core/Defs/RulePackDefs/` | |
| `TraderKindDef` | `Core/Defs/TraderKindDefs/` | |

**VERIFIED syntax details from `Factions_Misc.xml`:**

- `MayRequire="Ludeon.RimWorld.Ideology"` attribute on `<li>` and on value nodes for optional-DLC content.
- Multiple packageIds comma-separated in one attribute: `MayRequire="Ludeon.RimWorld.Biotech,Ludeon.RimWorld.Odyssey"`.
- `ParentName="FactionBase" Name="OutlanderFactionBase" Abstract="True"` — the abstract-def idiom.
- `xenotypeSet` / `xenotypeChances` is how a faction weights which xenotypes its pawns roll.

### Milestone 4 — tech and equipment

| Def type | Best vanilla example | Notes |
|---|---|---|
| `ThingDef` melee, energy tier | `Royalty/Defs/ThingDefs_Misc/Weapons/MeleeUltratech.xml` | Monosword / zeushammer class. **This is the tier a razor sits at.** |
| `ThingDef` melee, persona | `Royalty/Defs/ThingDefs_Misc/Weapons/MeleeBladelink.xml` | Bonded-weapon mechanics, if razors should bond to their bearer. |
| `ThingDef` melee, baseline | `Core/Defs/ThingDefs_Misc/Weapons/MeleeMedieval.xml` | |
| `ThingDef` ranged, spacer | `Core/Defs/ThingDefs_Misc/Weapons/RangedSpacer.xml` | Charge rifles — the tier for pulse weapons. |
| `ThingDef` weapon abstract bases | `Core/Defs/ThingDefs_Misc/Weapons/BaseWeapons.xml` | Parent defs to inherit from. |
| `ThingDef` apparel, powered | `Core/Defs/ThingDefs_Misc/Apparel_Various.xml` | Power armor. |
| `ThingDef` apparel, elite | `Royalty/Defs/ThingDefs_Misc/Apparel_Royal.xml` | Cataphract — best model for Gold / Obsidian armor. |
| `ThingDef` apparel, psychic gear | `Royalty/Defs/ThingDefs_Misc/Apparel_Psychic.xml` | |
| `ThingDef` items / resources | `Core/Defs/ThingDefs_Items/Items_Resource_Manufactured.xml` | |
| `RecipeDef` (crafting) | `Core/Defs/RecipeDefs/Recipes_Production.xml` | |
| `RecipeDef` (surgery, non-implant) | `Core/Defs/RecipeDefs/Recipes_Surgery_Misc.xml` | |
| **Implant triad** | `Core/Defs/HediffDefs/BodyParts/Hediffs_BodyParts_Bionic.xml` | **Key finding — see below.** |
| Implant triad, high tier | `Core/Defs/HediffDefs/BodyParts/Hediffs_BodyParts_Archotech.xml` | |
| Implant triad, Royalty | `Royalty/Defs/HediffDefs/Hediffs_BodyParts_Bionic_Empire.xml` | |
| Implant abstract bases | `Core/Defs/HediffDefs/BodyParts/Hediffs_BodyParts_Base.xml` | The `Recipe_InstallImplant` worker bases live here. |
| `ResearchProjectDef` | `Core/Defs/ResearchProjectDefs/ResearchProjects_1.xml` | |
| `ResearchTabDef` | `Core/Defs/ResearchProjectDefs/ResearchTabs.xml` and `Anomaly/Defs/ResearchTabDefs/ResearchTabs.xml` | Anomaly's is the better model for a *custom, conditionally-visible* tab (`visibleByDefault`, `generalTitle`, `generalDescription`, `tutorTag`). |
| `StatDef` | `Core/Defs/Stats/` | |
| `DamageDef` | `Core/Defs/DamageDefs/` | Needed for energy-melee damage types. |

**VERIFIED convention worth copying:** vanilla colocates all three defs of an implant — the item
`ThingDef`, the `HediffDef`, and the install `RecipeDef` — in the *same file*.
`Hediffs_BodyParts_Bionic.xml` defines `InstallBionicArm` at line 169, right after the hediff it
installs. Our implants will follow the same one-file-per-implant-family layout rather than
scattering across `ThingDefs_*` / `HediffDefs/` / `RecipeDefs/`.

### Milestone 5 — ideology and hierarchy (Ideology)

| Def type | Best vanilla example | Notes |
|---|---|---|
| `MemeDef` — **supremacy** | `Ideology/Defs/MemeDefs/Memes_GenderSupremacy.xml` | **The single most relevant vanilla file in the game for this mod.** It is a working implementation of "one group is innately superior, with mechanical consequences." The Color hierarchy is structurally the same shape. |
| `MemeDef` — group relation | `Ideology/Defs/MemeDefs/Memes_GroupRelation.xml` | Supremacist / subordinate framings. |
| `MemeDef` — primacy | `Ideology/Defs/MemeDefs/Memes_Primacy.xml` | |
| `MemeDef` — structure | `Ideology/Defs/MemeDefs/Memes_Structures_Basic.xml` | |
| `PreceptDef` — roles | `Ideology/Defs/PreceptDefs/Precepts_Role.xml` | Caste roles with abilities and apparel requirements. |
| `PreceptDef` — slavery | `Ideology/Defs/PreceptDefs/Precepts_Slavery.xml` | Directly applicable to the Red labor base. |
| `PreceptDef` — apparel | `Ideology/Defs/PreceptDefs/Precepts_Apparel.xml` | Caste-mandated dress. |
| `PreceptDef` — transhumanism | `Ideology/Defs/PreceptDefs/Precepts_Transhumanism.xml` | Attitudes toward implants / carving. |
| `PreceptDef` — scarification | `Ideology/Defs/PreceptDefs/Precepts_Scarification.xml` | Body-marking as caste marker. |
| `ThoughtDef` — role | `Ideology/Defs/ThoughtDefs/Thoughts_IdeoRole.xml` | |
| `ThoughtDef` — social situation | `Ideology/Defs/ThoughtDefs/Thoughts_Situation_Social.xml` | Where "crossed caste lines" thoughts belong. |
| `ThoughtDef` — terror | `Ideology/Defs/ThoughtDefs/Thoughts_Memory_Terror.xml` | |
| `HistoryEventDef` | `Core/Defs/HistoryEventDefs/`, `Biotech/Defs/HistoryEventDefs/` | The hook precepts react to. Caste violations become history events. |
| `RitualPatternDef` | `Ideology/Defs/PreceptDefs/RitualPatternDefs/` | |
| `IdeoFoundationDef` | `Ideology/Defs/IdeoFoundationDefs/` | |
| Preconfigured ideoligion | `Ideology/Defs/PreconfiguredIdeos/` | Lets us ship a ready-made Society ideoligion. |
| **Xenotype precepts** | `Biotech/Defs/PreceptDefs/Precepts_Xenotype.xml` | **Biotech + Ideology crossover — xenotype-based precepts already exist in vanilla.** This is the bridge between M2 and M5, and it is how "your Color determines your standing" gets mechanical teeth without inventing anything. |

### Milestone 6 — scenarios and world

| Def type | Best vanilla example |
|---|---|
| `ScenarioDef` | `Core/Defs/Scenarios/Scenarios_Classic.xml` |
| `ScenarioDef` with xenotype start | `Biotech/Defs/Scenarios/Scenarios.xml` |
| `ScenPart` reference | `Core/Defs/Scenarios/ScenParts_Fixed.xml`, `ScenParts_Various.xml`, `Biotech/Defs/Scenarios/ScenParts_Various.xml` |
| `BiomeDef` | `Core/Defs/BiomeDefs/`, `Odyssey/Defs/BiomeDefs/` |
| World generation | `Core/Defs/WorldGeneration/`, `Biotech/Defs/WorldGeneration/`, `Odyssey/Defs/WorldGeneration/` |
| `WorldObjectDef` | `Core/Defs/WorldObjectDefs/` |
| `PlanetLayerDef` | `Core/Defs/PlanetLayerDefs/`, `Odyssey/Defs/PlanetLayerDefs/` |

### Milestone 7 — patching

No vanilla examples; patching is a mod-side concept. See section 3 for the mod-derived patterns.

---

## 3. Reference mods inspected

I inspected four installed mods. Two are strong structural models for this project.

Locations:

- Workshop root: `D:\SteamLibrary\steamapps\workshop\content\294100\` — 325 subscribed mods
- Local mods: `D:\SteamLibrary\steamapps\common\RimWorld\Mods\` — 134 mods

### Alpha Genes (`sarg.alphagenes`, workshop `2891845502`) — primary model

The closest analogue to Milestone 2: a large gene and xenotype content mod, current on 1.6.

```
2891845502/
  About/   Languages/   README.md   Sounds/   Textures/   loadFolders.xml
  1.5/   1.6/
    Assemblies/   Defs/   Mods/   Patches/
```

`Defs/` is split into roughly 30 subfolders named after def types (`GeneDefs/`, `FactionDefs/`,
`HediffDefs/`, `RecipeDefs/`, `Scenarios/`, `ThingDefs_Items/`, and so on) — that is, it **mirrors
vanilla's own `Data/Core/Defs/` layout.** That is the convention we will follow.

`loadFolders.xml` — note the lowercase `l`; the game accepts either spelling on Windows:

```xml
<loadFolders>
  <v1.6>
    <li>/</li>
    <li>1.6</li>
    <li IfModActive="sarg.alphabiomes">1.6/Mods/AlphaBiomes</li>
    <li IfModActive="Ludeon.RimWorld.Royalty">1.6/Mods/Royalty</li>
    <li IfModActive="Ludeon.RimWorld.Anomaly">1.6/Mods/Anomaly</li>
  </v1.6>
</loadFolders>
```

**Pattern to copy:** `<li>/</li>` first for the shared root (`Textures/`, `Sounds/`, `Languages/`),
then the version folder, then one conditional folder per optional integration. Compatibility
content for other mods lives at `1.6/Mods/<ModName>/`, gated by `IfModActive`. `IfModNotActive`
also exists — Big and Small uses it.

**Patch strategy:** `1.6/Patches/*.xml`, one file per integration target, named
`<Target>Patch.xml`. Cross-mod patches are wrapped defensively:

```xml
<Patch>
  <Operation Class="PatchOperationFindMod">
    <mods><li>Alpha Mythology</li></mods>
    <match Class="PatchOperationSequence">
      <operations>
        <li Class="PatchOperationAdd">
          <success>Always</success>
          <xpath>/Defs/GeneDef[defName = "AG_AcidResistance"]/damageFactors</xpath>
          <value><MM_AcidicBreath>0</MM_AcidicBreath></value>
        </li>
      </operations>
    </match>
  </Operation>
</Patch>
```

Three habits worth stealing: `PatchOperationFindMod` guards, `<success>Always</success>` on
individual operations so an upstream rename does not spam red errors, and a consistent `AG_`
defName prefix on every def the mod owns.

### Big and Small — Races (`RedMattis.BigSmall`, workshop `2894397737`)

Adds `IfModNotActive` to the vocabulary, and `<loadBefore>` in `About.xml`:

```xml
<v1.6>
  <li>/</li>
  <li>1.6</li>
  <li IfModActive="Ludeon.Rimworld.Royalty">1.6/Royalty</li>
  <li IfModActive="RedMattis.BSSlimes">1.6/BSSlimes</li>
</v1.6>
```

Note this mod writes `Ludeon.Rimworld.Royalty` with a lowercase `w`, and ships working — so
**packageId matching is case-insensitive.**

### Vanilla Expanded Framework (`OskarPotocki.VanillaFactionsExpanded.Core`, workshop `2023507013`)

Has **no `LoadFolders.xml` at all.** It relies on RimWorld's implicit behaviour of loading a folder
named after the version (`1.6/`). This confirms `LoadFolders.xml` is optional when you need version
folders and nothing conditional. We want the conditionals, so we will write one.

Its `About.xml` is the model for dependency declaration: `modDependencies` entries each carrying
`displayName` + `downloadUrl` + `steamWorkshopUrl`, an exhaustive `loadAfter` naming every DLC
explicitly, and an `incompatibleWith` list. Also note
`<modIconPath IgnoreIfNoMatchingField="True">UI/VELogo</modIconPath>` — the
`IgnoreIfNoMatchingField` attribute makes an About field safe against older game versions.

### Combat Extended Guns (`CETeam.CombatExtendedGuns`, workshop `1582570547`)

The minimal case — version folders only, no conditionals. Included because CE compatibility is a
stated goal for this project.

---

## 4. DLC and dependency mapping for the design

### Requires a DLC you own

| Design element | Requires | Confidence |
|---|---|---|
| Color castes as xenotypes plus genes | **Biotech** | Verified — `XenotypeDef` / `GeneDef` are Biotech-only. |
| Metabolic and complexity balancing | **Biotech** | Verified — `biostatMet` / `biostatCpx` / `biostatArc`. |
| Caste hierarchy as memes, precepts, roles | **Ideology** | Verified. |
| Xenotype-conditioned precepts (Color determines standing) | **Biotech + Ideology** | Verified — `Biotech/Defs/PreceptDefs/Precepts_Xenotype.xml` proves the crossover exists in vanilla. |
| Red labor base, slavery mechanics | **Ideology** | Verified — `Precepts_Slavery.xml`. |
| Energy melee at monosword tier | Royalty for the *template only* | Our defs live in our mod; Royalty is a reference, not a hard dependency. |
| Gravity-assisted equipment | Odyssey, probably | **Unverified** — see section 6. |

### Nothing in the design requires a DLC you do not own

You own all five. There is no gap here.

### Doable in pure vanilla XML — no DLC gate on the mechanism

Weapons, apparel, items, recipes, research projects, research tabs, factions, pawn kinds,
backstories, scenarios, damage types, stats, thoughts, hediffs. Plus vanilla suppression via
`Patches/` and xpath.

### Expected to require C# — flagging early, will ask before writing any

- **Hard caste-crossing consequences.** Vanilla precepts react to `HistoryEventDef`s the game
  raises. If we need an event vanilla never raises — "a Red gave an order to a Gold" — a Harmony
  patch has to raise it. XML alone cannot invent new triggers.
- **Color-gated equipment.** "Only a Gold may wield a razor" is not a vanilla equipment
  restriction. `PreceptDef` apparel requirements get partway; a true hard block needs C#.
- **Any stat calculation that reads a pawn's xenotype.**

Per your rules I will stop and ask before adding C# for any specific item.

### Third-party mod interactions

| Mod | packageId | Status | Relevance |
|---|---|---|---|
| Combat Extended | `ceteam.combatextended` | **Active** | Stated goal. CE needs per-weapon `CE_` stats; support belongs in `1.6/Mods/CombatExtended/` gated by `IfModActive`, no earlier than M4. |
| RimJobWorld | `rim.job.world` | **Installed but NOT active** | The design names it for Pinks. See section 6 — needs a decision from you. |
| Vanilla Expanded Framework | `oskarpotocki.vanillafactionsexpanded.core` | Active | Available for its faction and apparel-colour helpers. Adds a dependency; I would rather not take it unless we need it. |
| Alpha Genes | `sarg.alphagenes` | Active | Gene namespace collision risk. Uses `AG_`; our prefix must differ. |
| Big and Small | `redmattis.bigsmall`, `.core` | Active | Body-size genes; may conflict with Obsidian / Gold body genes. |
| Humanoid Alien Races | `erdelf.humanoidalienraces` | Active | Not needed — Colors are xenotypes, not races. |
| Harmony | `brrainz.harmony` | Active, loads first | Required if we ship C#. |

Your active mod list has **151 entries** including the five DLC, and a substantial share of it is
RJW-adjacent content. Load-order and patch conflicts are a real risk for a total conversion.

**Recommendation:** develop against a separate minimal profile — Core, the five DLC, Harmony, and
RimRising — and test against the full list only after a milestone is verified clean. Otherwise a
red error could originate in any of 150 other mods and we will burn time bisecting.

---

## 5. Naming and conventions proposed, not yet applied

For your sign-off:

- **packageId:** `cinergy92.redrising` from CONFIG. RimWorld lowercases packageIds internally, so
  case in `About.xml` is cosmetic.
- **defName prefix:** `RR_` on everything we own. Chosen to avoid `AG_` (Alpha Genes), `VFE`,
  `CE_` (Combat Extended), and `BS_` (Big and Small). No active mod appears to use `RR_`.
- **Def file layout:** mirror vanilla — `1.6/Defs/GeneDefs/`, `1.6/Defs/FactionDefs/`, and so on.
- **Implant files:** ThingDef + HediffDef + RecipeDef colocated per implant family, per vanilla.
- **Compat folders:** `1.6/Mods/<ModName>/`, gated `IfModActive` in `LoadFolders.xml`.
- **Patches:** `1.6/Patches/<Target>Patch.xml`, guarded with `PatchOperationFindMod` for cross-mod
  work, `<success>Always</success>` on speculative operations.

---

## 6. Toolchain — VERIFIED available

| Tool | Version | Note |
|---|---|---|
| .NET SDK | 9.0.317, plus 6.0.403 / 8.0.403 / 8.0.424 | Enough to build a `net472` assembly via SDK-style csproj plus `Microsoft.NETFramework.ReferenceAssemblies`. |
| git | 2.33.0.windows.2 | `A:\Projects\RimRising` is **not yet a git repo**. `git init` is a Phase 1 step. |
| PowerShell | 7+ (pwsh) | Build tooling target, per your instruction. |
| RimWorld assemblies | `RimWorldWin64_Data\Managed\Assembly-CSharp.dll` | Reference target for the C# project. |
| Decompiler | **Not installed** | No `ilspycmd` on PATH. Installable via `dotnet tool install -g ilspycmd` if we need to verify a field with no vanilla XML example. |

### The shipped C# source is a trap — recorded so I do not assume otherwise later

`RimWorld\Source\` exists and looks promising, but contains only **43 `.cs` files** — a curated
sample Ludeon ships as modding examples (`FactionDef.cs`, `Building_Door.cs`, `CompRottable.cs`,
and similar). There is no `XenotypeDef.cs` and no `GeneDef.cs`. **Field verification must come from
vanilla XML, or from decompiling `Assembly-CSharp.dll`.**

### Paths for the PowerShell tooling

- Player log: `%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log`
  (with `Player-prev.log` alongside). The current `Player.log` is dated 2026-04-25 — stale, from
  before the last game patch. The first Milestone 1 launch regenerates it and establishes our
  baseline.
- Mod config: `%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml`

---

## 7. What I cannot verify, and what I need from you

### Blocking — needed before Phase 1

1. **`MODS_FOLDER` was left unfilled** in the CONFIG block (`<...\RimWorld\Mods>`). I am assuming
   `D:\SteamLibrary\steamapps\common\RimWorld\Mods` — it exists and holds 134 local mods.
   `Publish-Mod.ps1` will target it unless you say otherwise. Please confirm.

2. **RimJobWorld is installed but not in your active mod list.** The design says Pinks use RJW.
   That makes RJW either a hard dependency or an optional integration, and the two produce very
   different mods. Options:
   - (a) Pinks are a normal Color in the base mod, and RJW content lives in an optional
     `1.6/Mods/RimJobWorld/` folder gated by `IfModActive="rim.job.world"`. **My recommendation** —
     keeps the mod usable without RJW and the dependency graph clean.
   - (b) RJW as a hard `modDependency`.
   - (c) Drop the RJW angle entirely.

   This is partly a lore and design call, which is yours, so I am not picking for you.

3. **Development mod profile.** Minimal profile (Core + 5 DLC + Harmony + RimRising), or your full
   151-mod list? I recommend minimal, per section 4. If you agree, I can generate a second
   `ModsConfig.xml` for you to swap in, or you can manage it in-game.

### Non-blocking, but needed before the relevant milestone

4. **Gravity-assisted equipment (M4).** Not yet verified.
   `Odyssey/Defs/ThingDefs_Buildings/Buildings_Gravship.xml` exists, but whether Odyssey exposes a
   reusable *personal* gravity mechanic, as opposed to ship-scale only, is unknown. If it does not,
   gravBoots become either cosmetic apparel with stat bonuses (XML, easy) or a C# comp (needs your
   sign-off). I will verify before M4 and come back to you.

5. **The Color roster is a lore judgment call, and it is yours.** Your draft lists Red, Gold,
   Obsidian, Gray, Pink, Orange, Yellow, Blue, Silver, White — ten Colors. Each is one
   `XenotypeDef` plus roughly 8 to 14 `GeneDef`s, which makes M2 the single largest chunk of work
   in the project. Before I build it I need:
   - Is ten the full roster for the vertical slice, or do you want a subset first?
   - Should Colors be `inheritable` — two Red parents produce a Red child — or not? Vanilla's
     Dirtmole is inheritable; Genie is not. This is a setting question with a real mechanical
     consequence for pawn generation and reproduction, and I would rather you decide than infer.
   - Hard castes (a Gold cannot become a Red) or soft?

   I will put these in `docs/DESIGN.md` as structured options in Phase 1 rather than choose.

6. **Tech tier.** You said "above vanilla industrial." I have confirmed `Industrial` and `Spacer`
   appear as `techLevel` values in `Factions_Misc.xml`, but I have **not** verified the full enum.
   I will confirm from a vanilla def before setting faction tech levels in M3.

### Known unknowns I am tracking

- I have not verified the complete field list for any def type beyond `XenotypeDef` and the
  `biostat*` trio. Per your "verify, never recall" rule, I will verify per-def as I write each one.
- I have not opened `Assembly-CSharp.dll`. No decompiler installed.
- No `Preview.png` or `ModIcon.png` art exists. Placeholders in Phase 1, per `ART_PLAN`.
- The game has not been launched since its last patch, so there is no current clean baseline log to
  diff against. The first Milestone 1 launch doubles as establishing that baseline.

---

## 8. Nothing has been written yet

No mod content, no `About.xml`, no defs, no git repo. `A:\Projects\RimRising` currently contains
only the original prompt file and this document. Awaiting answers to section 7 items 1 through 3
before starting Phase 1.
