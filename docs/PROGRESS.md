# PROGRESS

Milestone status, open questions, known errors. Updated as work lands.

Game target: **RimWorld 1.6.4871 rev590**. packageId: `cinergy92.rimrising`.

---

## Milestone status

| # | Milestone | Status |
|---|---|---|
| 0 | Discovery | **Done.** `docs/DISCOVERY.md` |
| 1 | Skeleton | **Done** |
| 2 | The Color system | **Built and published; U1 parked as flavour** |
| 3 | Factions and pawn kinds | **Verified: planet generates, log clean** |
| 4 | Tech and equipment | **Verified in game.** Razor, pulse fist, pulse armor, scarabSkin, demonHelm |
| 5 | Ideology and hierarchy | **Verified in game.** Memes, 13 knighthoods, razor lock, caste romance, Gold ladder |
| 6 | Scenarios and world | **Verified in game.** Two starts, two biomes, faction placement |
| 7 | Vanilla suppression | **Verified in game.** Settings toggle, xenotypes + generic factions, two merchant houses |

---

## Milestone 1 — skeleton

### Built

- `About/About.xml` — packageId, `supportedVersions` 1.6, `modDependencies` on Biotech and
  Ideology, `loadAfter` naming all five DLC plus Harmony.
- `LoadFolders.xml` — root plus `1.6`. Conditional folders are listed as comments only; they get
  added when the folder actually exists, since referencing a missing path is unverified.
- `1.6/Defs/ThingDefs_Items/Items_Resource_RimRising.xml` — one trivial `ThingDef`, `RR_Ionsteel`,
  mirrored node-for-node from `ComponentIndustrial` with `ParentName="ResourceBase"`.
- `Tools/` — all four PowerShell scripts.
- Placeholder art — item texture, `Preview.png`, `ModIcon.png`, mod icon.
- `CLAUDE.md`, `docs/DESIGN.md`, this file, `.gitignore`.

### Validation

`Test-ModDefs.ps1` passes: 1 def, 0 errors, 0 warnings, exit 0.

The validator was negative-tested against a fixture containing all five fault classes — malformed
XML, duplicate defName, vanilla collision, missing texture, unresolvable ParentName — and produced
five errors with exit 1. It is not merely returning green.

### First in-game load — one real bug, found and fixed

The mod loaded. `About.xml` parsed, packageId resolved, no dependency complaints. RimSort's
"Missing Publish Field ID" notice is expected for a local mod and needs no action.

One genuine error in `Player.log`:

```
Collection cannot init: No textures found at path Things/Item/Resource/RR_Ionsteel
```

**Cause:** `Graphic_StackCount` derives from `Graphic_Collection` and resolves `texPath` as a
*folder* of images, not a single file. The placeholder generator had written one flat PNG at that
path, and the validator passed it because a file genuinely existed there — a false green.

**Fixed:** both tools are now graphic-class aware. `Test-ModDefs.ps1` requires at least one image
*under* `<texPath>/` for collection classes and reports `MissingTextureCollection`;
`New-PlaceholderTextures.ps1` emits `_a`/`_b`/`_c` variants in a folder. Confirmed the validator
now catches the exact condition the game reported, then regenerated and republished.

Mod renamed to **RimRising**, and packageId changed from `cinergy92.redrising` to
`cinergy92.rimrising` at the user's direction. Done now while it is free — packageId is what save
files and other mods key on, so changing it later would be expensive. The mod icon texture and its
`modIconPath` were renamed to match.

### Still to verify

The fixed textures have not been loaded yet. Re-verify per the steps below.

### How to verify — what to click

1. Publish:

```bash
pwsh -File Tools/Publish-Mod.ps1
```

2. Launch RimWorld. In the mod list, confirm **RimRising** appears with its placeholder preview
   image and no yellow warning triangle.
3. Enable it alongside Core and the DLC. Accept the restart prompt.
4. After restart, open the debug log (the `~` key opens the console; the message log is under the
   debug actions menu). Confirm **no red errors**.
5. Enable Development mode in Options if it is not already on.
6. Start any quick game. Use the debug actions menu, **Spawn thing**, search `ionsteel`, and place
   a stack.
7. Confirm the item appears with its placeholder texture (a labelled flat-colored square) and can
   be hauled and stockpiled.
8. Back at the desktop:

```bash
pwsh -File Tools/Get-ModLoadErrors.ps1
```

   Expect "No errors attributable to this mod."

Report back what happens, including anything red, and Milestone 1 closes.

---

## Milestone 2 — the Color system

### Built

- `1.6/Defs/GeneDefs/XenotypeDefs_Colors.xml` — all **14 Colors** as inheritable `XenotypeDef`s.
- `1.6/Defs/GeneDefs/GeneDefs_RimRising.xml` — one custom gene, `RR_Fertility_Reduced`. Vanilla
  ships only Sterile (Fertility 0) and Fertile (Fertility 2); Gold needs a partial reduction, which
  does not exist. `Inbred` proves a fractional `<Fertility>` statFactor is valid.
- Placeholder icons for 14 xenotypes (64x64) and 1 gene (128x128).
- `Tools/Get-XenotypeBudget.ps1` — new. Sums member-gene biostats per xenotype, resolving mod genes,
  vanilla genes, and template-generated genes.

**Everything else is composed from verified vanilla genes.** Only one custom gene exists, which
keeps the dependency surface at Core + Biotech + Ideology and the texture workload near zero.

### Computed budgets

| Tier | Colors | Cpx | Met |
|---|---|---|---|
| Gold | Gold | **24** (arc 2) | −13 |
| highColors | White 13, Copper 12, Silver 10 | 10–13 | −4 to −5 |
| midColors | Blue 10, Yellow 9, Green 9, Violet 9, Orange 9, Gray 8 | 8–10 | −1 to −5 |
| lowColors | Obsidian 6, Pink 6, Brown 6, Red 6 | 6 | +3 to −5 |

For scale, vanilla runs Impid 2 → Waster 11, with Sanguophage the outlier at 41. Our non-Gold
Colors sit inside vanilla's ordinary band; Gold is deliberately outside it.

### Gold: the metabolism trade-off — needs a ruling

Per direction, Gold has **no capability weakness**. Its costs are scarcity
(`factionlessGenerationWeight` 0.3 against Red's 8) and slow reproduction
(`RR_Fertility_Reduced`, Fertility ×0.4).

Biotech's economy will not let that be entirely free. Complexity and metabolism are coupled: every
advantage costs metabolism, and **every met-positive gene in vanilla is a drawback** — hemogen
dependency, deathrest, instability, depression, UV sensitivity. There is no clean way to buy
capability back.

Gold currently sits at **met −13**, i.e. Golds eat substantially more than baseline. Mitigations
already applied:

- `ArchiteMetabolism` (cpx +6, met **+6**, arc +2) — the one gene that raises complexity while
  *refunding* metabolism. It also contributes `biostatArc`, which means a Gold xenogerm cannot be
  assembled without archite capsules. **Carving into Gold is therefore gated behind the rarest
  material in the game**, which is exactly the difficulty asked for.
- Preferring `AptitudeStrong` (cpx 2, met −1) over `AptitudeRemarkable` (cpx 2, met −3) wherever the
  caste is not *defined* by that skill. Same complexity, a third of the hunger.

**My read:** high food consumption is not a capability flaw — it is an economic one, and "Golds are
enormously expensive to keep" is squarely on-theme for the ruling given. Recommend keeping it. Say
the word if you would rather trim Gold's advantages to bring met toward zero, at the cost of making
carving easier.

### Validation

`Test-ModDefs.ps1`: 16 defs, 0 errors, 0 warnings.

A sixth check was added first — **`MissingGene`**, cross-referencing every `<genes><li>` in a
XenotypeDef against mod GeneDefs, vanilla GeneDefs, and gene-template expansions. With 14 xenotypes
naming ~160 genes between them, catching a typo here rather than in the game log is worth a lot.
Negative-tested: `Skin_Chartreuse` and `AptitudeAmazing_Melee` both caught, valid names passed.

### How to verify — what to click

1. Launch RimWorld with RimRising enabled.
2. Start a new colony. At the **scenario / starting pawn** screen, open the xenotype selector — all
   14 Colors should be listed, each with a labelled placeholder icon.
3. Confirm the descriptions read correctly and each Color shows plausible genes.
4. **Check the budgets against the game's own numbers.** Open a Color in the gene assembler or the
   xenotype editor and compare its complexity and metabolism against the table above. This closes
   U2 — my figures are inferred, the game's are authoritative.
5. **Test carving (U1).** Assemble a xenogerm from a Color's exact gene set and implant it. Does the
   pawn read as that Color, or as "Hybrid"? This is the one unknown the whole carving design rests
   on.
6. Dev-mode spawn a few pawns of different Colors and confirm hair and skin colors are visibly
   distinct.
7. `pwsh -File Tools/Get-ModLoadErrors.ps1`

### Dependencies added — earlier limitations now resolved

The user made EyeGenes2 and Facial Animation hard requirements, and pointed at EBSG and Alpha Genes.
All four are now declared dependencies, and all four are installed and indexed.

| Was a limitation | Now |
|---|---|
| Only two vanilla eye genes, so only Red and Gray had caste eyes | **All 14 Colors have caste-matched eyes.** `Eyes_Golden` exists in EyeGenes2, which is exactly canonical for Gold. |
| No body-size gene | `AG_LargerBodySize` on Gold and Obsidian, `AG_SmallerBodySize` on Red and Pink |
| No lifespan gene | `AG_ExtraordinaryLifespan` on Gold — canon has Golds past 150 |
| No way to model lowColor early reproduction | `EBSG_FertilityShortening` on Red |

`Test-ModDefs.ps1` and `Get-XenotypeBudget.ps1` both now read `modDependencies` from About.xml and
index those mods' GeneDefs. Without that, the budget tool silently omitted third-party genes and
produced plausible-but-wrong totals — it reported 13 unresolved references before the fix.

### Gold is now playable — U8 resolved

`Capacity_Boost_Tier_3` from Biotech Capacitor Genes trades **+15 metabolism for +15 complexity**,
a straight 1:1 swap with no side effects (verified: the def carries biostats and nothing else).

That resolves the whole tension. Gold pays for its advantages in **complexity** rather than in
hunger or weakness — and complexity is the carving gate, so paying there is a feature:

| | Before | Now |
|---|---|---|
| Metabolism | −20 | **−4** |
| Complexity | 26 | **49** |
| Archite | 2 | **4** |

Golds now eat moderately above baseline instead of ruinously, are bad at nothing, and a Gold
xenogerm needs a large gene-assembly setup plus four archite capsules to build.

`EBSG_ArchiteWoundHealing` (cpx 6, arc 2, **met 0**) adds the canonical rapid healing for free on
the metabolism axis.

### Bronzie — the fifteenth xenotype

Built. The only Gold tier that is *genetic* rather than achieved, so the only one that belongs as a
xenotype; Peerless Scarred, Graduate, Shamed, Iron Gold and Pixie are earned or behavioural and
belong in M5 as Ideology roles.

**Complexity 9, archite 0, metabolism −4** against true Gold's 49 / 4 / −4. That makes Bronzie the
cheap Gold: assemblable and carvable early, and viable as a starting pawn without a Gold's food
economy. Not a weak pawn — Remarkable melee, strong shooting and social, Robust, MeleeDamage_Strong.
It fights like a Gold; what it lacks is the polish its own caste measures itself by, hence
`Mood_Pessimist`.

### Sub-tiers — six added, roster now 21

Only sub-tiers with a **stated genetic basis** became xenotypes. The reference is explicit about
which those are, and the rest are achieved, occupational or chemical.

| Xenotype | Parent | Basis |
|---|---|---|
| **Ultraheavy** | Red | "bred on The Rim… bodies are larger and denser", 2.4g and heavy radiation, short-lived |
| **Lurcher** | Gray | "genetically-altered to have superior senses, such as smell and sight" |
| **Fulgur Bellator** | Green | "bred for hardiness… bodies tend to be thicker" |
| **Stained** | Obsidian | elite class, "among the strongest warriors of their caste" |
| **Ascomanni** | Obsidian | "further modifying themselves over several centuries", genetically distinct |
| **Rose** | Pink | "rare and highly valued class", bred and trained in the Gardens |

Deliberately **not** xenotypes — these are M5 Ideology roles, M4 implants, or job titles:
Peerless Scarred / Graduate / Shamed / Iron Gold / Pixie (Gold); Skuggi, Berserkers (drug-induced
via Fever Cloud), Shamans, Eaters (outcasts) (Obsidian); Hetaera (Pink); Psychotech (Green,
implant-based); Medici (Yellow); Artificer / Bladeweaver / Master Maker (Orange); Master Carver /
Carver (Violet); Growers (Brown); highRed / lowRed; MineMagistrate / Actarius (Copper); Logos /
Justice / Chance / Arbiter (White); helmBlue / comBlue / ripWing (Blue).

### First C# — the xenogerm metabolism floor

Decompiling `RimWorld.GeneTuning` settled a question that was quietly shaping the whole design:

```csharp
public static readonly IntRange BiostatRange = new IntRange(-5, 5);
```

`GeneCreationDialogBase` refuses to assemble a xenogerm below `BiostatRange.TrueMin`. **A Color
below −5 metabolism can never be carved into** — the xenogerm cannot be built, and nothing warns
you. Silver and Obsidian were both at −6.

`Source/RimRising/BiostatRangePatch.cs` widens the floor to **−10** via reflection at startup. No
Harmony required: the field is `public static readonly`, but it is a plain static field and
reflection assigns it. It is a global change, which suits a total conversion.

Also decompiled, and it closes **U8**:

```
MetabolismToFoodConsumptionFactorCurve:  (-5, 2.25)  (0, 1.0)  (5, 0.5)
```

**Metabolism −5 means 2.25x food, and the curve ends there** — `SimpleCurve` clamps at endpoints,
so below −5 costs 2.25x and no more. Gold at −4 lands near 2x food: "much more food", exactly as
asked, and bounded. U8 needed no in-game measurement after all.

`Get-XenotypeBudget.ps1` now checks the floor, reads the patched value out of the C# source, and
distinguishes "below vanilla's floor but legal under our patch" from "broken".

### Icon pass — done

`Tools/New-XenotypeIcons.ps1` replaces the labelled placeholder squares with an original geometric
glyph set: 21 xenotypes plus the mod's 2 gene icons.

- **Original designs.** The published sigils are copyrighted artwork and are not reproduced. Only
  the idiom is shared — terse geometric marks in the manner of alchemical symbols. Red was
  deliberately redesigned as a shaft-and-rungs ladder rather than a ringed downward arrow, since
  that form sat too close to the real Red sigil.
- **Lineage is visible.** Sub-tiers inherit the parent glyph plus a modifier, so a Lurcher reads as
  a Gray and an Ascomanni as an Obsidian. Useful in a 21-entry list.
- **Caste-colored.** `XenotypeDef.IconColor` is a uniform 0.75 grey multiply, which preserves hue,
  so colored glyphs read correctly. Each is drawn with a dark underlay so it holds its edges on any
  background.

`New-PlaceholderTextures.ps1` now refuses to touch icon paths even under `-Force`, so it cannot
silently undo the set.

### U1 — parked, not blocking

The user's read is that a carved pawn will show as **Hybrid**, and that this is flavour rather than
a blocker. That matches the mechanics: the wiki confirms germline genes are *suppressed*, not
removed, so a carved Red keeps its Red endogenes underneath. Thematically that is the right answer
anyway — a carved Red is always a Red wearing Gold. To be confirmed in game whenever convenient;
work continues either way.

### Build tooling

`Tools/Build-Mod.ps1` wraps `dotnet build`. The project targets `net472` and pulls reference
assemblies from NuGet; `Source/NuGet.config` pins nuget.org for that folder only, because this
machine's global NuGet feed is offline-only and lacks
`Microsoft.NETFramework.ReferenceAssemblies`. `Publish-Mod.ps1` ships `1.6/Assemblies/RimRising.dll`
and still excludes `Source/`.

### Revised budgets

| Color | Cpx | Met |
|---|---|---|
| Gold | 26 | **−20** (arc 2) |
| White 13, Copper 12, Silver 10, Blue 10 | 10–13 | −1 to −6 |
| Yellow, Green, Violet, Orange 9, Gray 8 | 8–9 | −1 to −5 |
| Obsidian, Pink, Red 7, Brown 6 | 6–7 | +2 to −6 |

### U8 — Gold's metabolism needs an in-game check

Gold is at **met −20**, which is what "much more food" means mechanically, and is now deliberate
rather than incidental. But it is far outside vanilla's range — every vanilla xenotype sits between
−1 and +2 — and **I cannot verify the hunger-rate curve from disk**; it is C# in the gene tracker.

If Golds turn out to starve constantly rather than merely eat lavishly, the dial is easy: reduce
`RR_HighbornAppetite`'s `biostatMet` from −3, or drop `Beauty_Pretty` and `Robust`.
`ArchiteMetabolism` already refunds +6; without it Gold would be −26.

**Please check the hunger rate on a Gold pawn and report back.**

---

## Milestone 3 — factions and pawn kinds

Five factions, 20 pawn kinds, 49 defs total, validating clean.

| Faction | Tech | Shape |
|---|---|---|
| the Society | Spacer | 34% Red, 0.8% Gold. Grays in bulk, Obsidian shock, rare Gold praetor. |
| Rim Dominion | Spacer | Rival Golds. Heavy on Ultraheavy Reds bred for Rim gravity. |
| Sons of Ares | Industrial | 44% Red. Saboteurs, freed Obsidians, turned Grays. |
| obsidian tribes | Neolithic | Obsidian and Stained only. Stripped of technology. |
| Ascomanni | Industrial | Ascomanni only. Hostile to everyone. |

**Olympic Knights** exist as `RR_Society_OlympicKnight`, appearing for both the Society and the
Dominion, since the order split into Core and Rim branches. combatPower 340 — one is worth more
than a full Society squad. The thirteen named knighthoods are titles, not a pawn type; see
DESIGN §4.1 for the Royalty-versus-Ideology decision, which is open.

### Correction — faction relations are player-relative

I previously said inter-faction relations "need Goodwill def work". That was wrong, and decompiling
settled it: `GoodwillSituationWorker` resolves the second party as `Faction.OfPlayer`, and
`FactionDef` has no `startingGoodwill`. **RimWorld does not let a mod set how two NPC factions feel
about each other.**

The one real NPC-to-NPC lever is `permanentEnemyToEveryoneExcept`, now used to make the Ascomanni
hostile to every faction rather than only to the player.

"The Society hates the resistance" therefore has to be expressed player-relatively, via a
`GoodwillSituationDef` keyed on the Color-hierarchy memes — which lands in Milestone 5 and is pure
XML once those memes exist. That is also the version that matters, since the player is the only
party whose relations the game simulates with any weight.

### First load of M3 — 56 errors, all fixed

The first in-game load of Milestone 3 produced 56 errors in four classes. All are fixed.

| Error | Cause | Fix |
|---|---|---|
| `has pawnGroupMakers but missing maxPawnCostPerTotalPointsCurve` (x5) | Required on any humanlike faction with group makers | Curve added to all five, shape from `Faction_Empire.xml` |
| `is humanlikeFaction but has no backstory categories` (x5) | `backstoryFilters` is required, not optional | Added per faction; categories verified present in `Core/Defs/BackstoryDefs` |
| `initial resistance range is undefined` / `initial will range is undefined` (x40) | Required on every humanlike pawn kind | Added to the shared base so all inherit; Praetor and Olympic Knight override upward |
| `Could not resolve cross-reference to GeneDef EBSG_ArchiteWoundHealing` / `EBSG_FertilityShortening` | **Validator false green — see below** | One gated, one dependency added |

The C# worked on the first try:
`[RimRising] Xenogerm metabolism floor widened from -5 to -10. Max unchanged at 5.`

### The fourth false green — two gating mechanisms the validator ignored

Both failing genes exist on disk. Neither loads, for different reasons, and the validator indexed
both because it read the filesystem rather than the load rules.

1. **`EBSG_FertilityShortening`** lives in `1.6/Mods/EBSGFull/`, which EBSG's own `LoadFolders.xml`
   gates behind `IfModActive="EBSG.Framework"`. The framework was installed but not active, so the
   folder never loaded.
   **Fix:** `EBSG.Framework` added as a dependency. **It must be enabled in the mod list.**
2. **`EBSG_ArchiteWoundHealing`** carries
   `MayRequireAnyOf="MoreBiotechStyleGenes.Mod,MoreWoundHealingGenes.Mod"` on the def itself.
   Neither mod is installed, so the def never exists.
   **Fix:** the same gate is now mirrored on our `<li>`, so the reference drops out cleanly instead
   of erroring. Gold loses 6 complexity and 2 archite when those mods are absent — cpx 43, arc 2,
   metabolism unchanged. Installing either mod restores it.

`Test-ModDefs.ps1` now honours both mechanisms when indexing dependencies: it parses each
dependency's `LoadFolders.xml` and skips folders whose `IfModActive` we do not satisfy, and skips
defs whose `MayRequire` / `MayRequireAnyOf` is unsatisfied. On the current profile that removes
**100 gated files and 160 gated genes** from the index. A reference of ours that is itself
`MayRequire`-gated now reports as a warning rather than an error, since the game drops it cleanly.

### Second load — the planet would not generate

Not a worldgen failure. The world generated and then threw while being **drawn**:

```
Could not execute post-long-event action. ArgumentNullException: Parameter name: key
  at Verse.ContentFinder`1[T].Get (System.String itemPath, ...)
  at RimWorld.Planet.Settlement.get_Material ()
  at RimWorld.Planet.WorldDrawLayer_WorldObjects+<Regenerate>d__7.MoveNext ()
```

`Settlement.Material` reads the faction's `settlementTexturePath`. None of our factions set one, so
a null path went to `ContentFinder` and threw — **once per settlement on the map**, roughly ten
thousand times, taking the whole draw layer down with it. All five factions now set it;
`DefaultSettlement` and `TribalSettlement` are the only two values vanilla uses.

Also fixed: `weaponMoney` with no `weaponTags` on the three civilian kinds.

New validator checks, both negative-tested:

- **`FactionMissingField`** — requires `settlementTexturePath`, `maxPawnCostPerTotalPointsCurve` and
  `backstoryFilters` on every concrete non-hidden faction.
- **`PawnKindWeaponMoney`** — catches `weaponMoney` declared without `weaponTags`.

These close a category the validator was blind to. Every earlier check asked "is this name real?";
none asked "is this required field present?" An absent field is invisible to a reference check.

### Get-ModLoadErrors was crying wolf, and hiding the real thing

Two opposite faults, both now fixed:

1. **False positive.** Attribution matched against the whole context window, so any unrelated line
   sitting near our own startup message read as ours. Attribution is now on the matching line only,
   walking into following lines solely while they look like a stack trace. A benign-noise ignore
   list also drops Unity's constant `Fallback handler could not load library` chatter.
2. **False negative, and this is the one that mattered.** The settlement crash was *entirely our
   fault* and named only vanilla settlements — 10,002 error blocks, 3 attributed to us. The tool
   reported a comfortable "3 errors" while the world map was black. It now warns loudly whenever a
   large number of errors go unattributed, pointing at `-All`.

### M3 verified

Planet generates. `Get-ModLoadErrors`: **0 error blocks in the log, 0 attributable to this mod.**

Still unconfirmed by eye: that RimRising factions actually appear on the world map, and that a raid
arrives with the right Colors.

---

## Milestone 4 — tech and equipment

The vertical slice from the build order: one melee weapon, one ranged, one armor set, one implant,
behind a custom research tab. 61 defs total, validating clean.

### The Artificer tab

Named for the Orange sub-tier that actually builds the Society's weapons and armor — Bladeweavers,
the Artificers who make razors, are a specialisation within it. Four projects:

| Project | Cost | Prerequisites | Unlocks |
|---|---|---|---|
| polyenne weaving | 3000 | Fabrication | razor |
| pulse physics | 3500 | Fabrication, ChargedShot | pulseFist |
| pulse armor | 5000 | pulse physics, PoweredArmor | pulse armor |
| neural interface | 4000 | Bionics | synaptic lattice |

### The slice

- **Razor** — polyenne, Ultra tech, armor penetration **0.95** against the monosword's 0.90, because
  canonically it opens pulseArmor. Four tools including a `lash` for the whip state: longer reach,
  wider arc, less concentrated force.
- **pulseFist** — gauntlet-mounted energy weapon, canonically "the most widely used ranged weapon in
  combat between Golds". Range **19.9** against the charge rifle's 27.9: brutal close, useless far.
  Uses `Flame` damage.
- **Pulse armor** — recoil plating plus servo harness plus shield generator. Unlike vanilla power
  armor it gives **positive** MoveSpeed and MeleeDamageFactor, because the suit is described as
  enhancing strength and speed rather than merely protecting. That is its signature.
- **Synaptic lattice** — brain implant. The best-attested implant in the setting: Blues fly by it
  via the Synaptic Drift and their scalp digiTats, and Greens wear the same lattice for the networks.
  It is why Blue carries `Hair_BaldOnly` and Green `Hair_ShortOnly`.

Implant triad kept in one file per the vanilla convention already recorded in CLAUDE.md.

### No new DLC dependency

Everything parents to **Core** abstracts — `BaseMeleeWeapon`, `BaseHumanMakeableGun`, `BaseBullet`,
`ArmorMachineableBase`, `BodyPartProstheticBase`, `SurgeryInstallImplantBase` — not to Royalty's
`MeleeWeaponUltratech`. Royalty arrives at M5 for the Gold rank ladder, and the razor becomes a
persona weapon then, which is what its fiction wants: ancestral razors are named and inherited.

### Caste restriction is deliberately absent

A razor is forbidden to every Color but Gold, on pain of death. That is a **social rule, not a
property of the object**, so nothing in the ThingDef enforces it. It belongs in M5 as a precept
reacting to a HistoryEvent. Right now a Red can pick one up — the Society's objection is the whole
point, and the Society does not exist yet.

### U6 closed

Texture dimensions measured across ~140 textures in installed mods rather than assumed:
**weapons 128x128** (117 samples; a few mods ship 256, but 128 is the convention) and
**apparel 256x256** (24 samples). The placeholder generator's size table was wrong — it had weapons
at 256 — and is now corrected with per-path rules.

### Validator bug — duplicate check was type-blind

`Test-ModDefs` rejected the synaptic lattice, reporting `RR_SynapticLattice` as a duplicate defName.
It was wrong. **defNames are unique per def type, not globally** — vanilla relies on this, and
`Joywire` is simultaneously a HediffDef and a ThingDef in the same file. Every implant triad is
written this way, so a type-blind check rejects correct XML.

The check now keys on type plus defName. Verified both ways: a HediffDef and ThingDef sharing a name
passes, two ThingDefs sharing a name still fails.

The vanilla-collision check remains type-blind, which is over-strict rather than wrong, and harmless
while every def we own carries the `RR_` prefix.

---

## Milestone 6 — scenarios and world

### The two starts

`RR_Scenario_Household` and `RR_Scenario_Breakout`, mirrored from Biotech's Sanguophage scenario
(the vanilla example of forcing xenotypes into a starting party via
`ScenPart_ConfigPage_ConfigureStartingPawns_Xenotypes`). Neither presumes an ideoligion; picking
`RR_ColorEquality` as a Gold, or `RR_ColorHierarchy` as a Red, is coherent and produces better games.

### Two biomes, and why they needed C#

A `BiomeDef` cannot say where it belongs. Placement lives entirely in a `BiomeWorker`, whose
`GetScore(BiomeDef, Tile, PlanetTile)` runs for every biome on every tile, highest score taking it.
Reusing a vanilla worker would make our biome compete with the vanilla one on identical criteria and
one of the two would simply never appear — so `Source/RimRising/BiomeWorkers.cs`.

Scoring idiom taken from the decompiled `BiomeWorker_AridShrubland`
(`22.5 + (temperature - 20) * 2.2 + (rainfall - 600) / 100`, behind an `Allowed(tile)` gate). Both of
ours are pitched slightly **below** the vanilla biome they overlap, so they surface on tiles vanilla is
lukewarm about rather than carpeting the planet.

- `RR_TerraformedSteppe` — engineered farmland. Fertile, flat, and near-empty of anything not put
  there on purpose. Its `wildAnimals` are livestock, not fauna.
- `RR_HeliumBarrens` — mining country whose entire value is underneath it. Hot, dry, and required to
  be broken ground; flat desert is just desert.

**Deliberately not polar.** Vanilla's IceSheet and Tundra already do that job well; a duplicate would
add a name and nothing else.

World textures are 512×512 flat tints with a light grain — measured from a shipped mod biome texture,
not assumed. That means a tinted square is the *finished* form for this asset type, not a placeholder.
Generated by `Tools/New-BiomeTextures.ps1` from a fixed seed so re-runs are byte-identical.

### Faction placement

`minSettlementTemperatureChanceCurve`, verified against Ideology's `NudistTribe`, which uses it to keep
nudist settlements out of the cold. `FactionDef` has **no** `allowedBiomes`/`disallowedBiomes`, and
`BiomeDef` carries no faction weights — this curve is the whole lever.

Obsidian tribes and Ascomanni are weighted onto cold tiles, the Rim Dominion onto cool-but-not-polar,
the Society onto temperate. **Sons of Ares get no curve on purpose**: an insurgency that only hid in one
climate would be a poor insurgency.

Every curve's tail is small but non-zero. A hard zero risks worldgen finding no legal tile on an unusual
planet; a small weight makes these strong preferences that can bend rather than rules that can fail.

### The sixth false green — a caste with no face

The user reported a Gray rendering with green eyes. `RR_Gray` carried `Hair_Gray` and **no eye gene at
all**, so Facial Animation fell back to a randomly generated eyeball colour. An audit found three more of
the same class: `Hair_ShortOnly` and `Hair_BaldOnly` are *style* genes carrying no `hairColorOverride`, so
`RR_Blue`, `RR_Green` and `RR_Green_FulgurBellator` were rolling random hair colour.

All four load with zero errors and are visible only by looking at a pawn's face — which is exactly the
failure mode this project keeps hitting. Closed with `XenotypeMissingAppearanceGene`, which indexes
vanilla genes carrying `hairColorOverride` (rather than trusting a hardcoded list) and requires every
xenotype to declare one hair *colour* gene and one `Eyes_*` gene. Negative-tested by reintroducing both
original faults; both fire.

Also checked and cleared while investigating: Eye Genes 2 ships `Patch_FacialRemoveEyes.xml`, which strips
its vanilla eye render nodes when Facial Animation is active. **All fifteen** eye genes RimRising uses are
on that strip list, so none of them can double-draw over an FA head.

---

## Milestone 7 — vanilla suppression

User's scope decision: suppress vanilla xenotypes **and** the generic factions, leave the Empire and
the hidden factions alone, and put it behind a mod setting that defaults to on.

### Nothing is deleted

Every vanilla def still loads and still resolves. Only generation weights change, so a saved game,
another mod, or a player who ticks a faction back on at world creation all still work. Removal breaks
saves and is hostile to the rest of the load order; suppression costs nothing and reverses in place.

### Why this could not be a patch file

The obvious implementation is a `PatchOperation` writing zeroes. That cannot be toggled — XML patches
run once at load, have no access to mod settings, and cannot be undone. Doing it in C# lets the
checkbox mean something, because the shipped values are captured before anything is overwritten.

`LoadedModManager.LoadAllActiveMods` (decompiled) runs `CreateModClasses()` **before** `LoadModXML()`,
so the `Mod` constructor can read settings but no def exists yet. Def mutation therefore lives in a
`[StaticConstructorOnStartup]`, and `WriteSettings` re-applies when the settings window closes.

### factionlessGenerationWeight alone is a half-measure

`PawnGenerator` reads `factionlessGenerationWeight` in exactly one place —
`AdjustXenotypeForFactionlessPawn` — so it governs wanderers and refugees and **nothing else**. Pawns
belonging to a faction get their xenotype from `XenotypesAvailableFor`, which reads the faction's or
the kind's `xenotypeSet`.

So suppression walks every `FactionDef` and `PawnKindDef` and zeroes the `chance` on any
`XenotypeChance` naming a suppressed xenotype. `XenotypeChance` is a class with public mutable fields
and `XenotypeSet` exposes an indexer, so no reflection is needed. Zeroing needs no compensating
Baseliner entry either: `XenotypeSet.BaselinerChance` is derived as `1 - sum(rest)`, so the freed
probability falls back on its own.

### Prerequisite found and fixed first — the planet had no traders

Our five factions descend from `FactionBase`, which declares **no** trader kinds. Vanilla puts
`caravanTraderKinds` / `visitorTraderKinds` / `baseTraderKinds` on the concrete outlander and tribal
factions, not on the base. Suppressing those factions would therefore have left a planet with no
ground trade at all — no caravans, no visiting traders, nothing to trade with at a settlement — and
nothing would have logged an error about it.

Fixed before touching suppression: industrial trade for the Society and the Rim, combat and black
market for the Sons of Ares, the neolithic set for the obsidian tribes, and pirate-merchant caravans
only for the Ascomanni.

### What is deliberately left alone

| Kept | Why |
|---|---|
| `Mechanoid`, `Insect`, `Entities`, `HoraxCult`, `Sanguophages`, `Beggars`, `Pilgrims`, `Salvagers`, `OutlanderRefugee` | Hidden factions. No settlements; they drive events and quests. Suppressing them deletes content and gains nothing. |
| `Ancients`, `AncientsHostile` | Ruins and cryptosleep caskets. Setting-neutral and load-bearing for ancient dangers. |
| `Empire` | User's explicit call. Also owns Royalty's entire quest and title chain. |
| `TradersGuild` | Odyssey's trade faction. Cutting it while the player is already short of trade partners is a worse game. |
| `Baseliner` | The "no xenotype" default. Zeroing it leaves pawn generation with nothing to fall back on. |
| `Sanguophage` | Already ships at weight 0 and is granted by mechanics rather than rolled. |

---

## The two merchant powers — and the validator bug they uncovered

### Julii Industries and Sun Industries

Added because M7 created a mechanical hole: with vanilla's outlander towns suppressed, a colony that
has angered the Society could be left with no viable trade partner at all. The Ascomanni raid rather
than trade, and the obsidian tribes sell only neolithic goods.

Two merchants rather than one, because they are opposites and between them they cover every colony a
player can run:

| | Julii Industries | Sun Industries |
|---|---|---|
| Run by | Gold house, inherited | Silver, self-made |
| Disposition | no `requiredMemes` at all | `RR_ColorEquality` |
| Trade | full industrial suite **plus** the pirate merchant | industrial plus exotics, **no** pirate merchant |
| Golds employed | a few | none, by construction |

Julii sells to anyone and cares only about the price — the source's own account of the house is that
it backs whoever is currently paying and drops an alliance the moment it stops being profitable,
which is exactly the disposition a guaranteed trade partner needs. It is deliberately given **no**
required meme: binding it to the hierarchy would hand it the hierarchy goodwill situations and make
it loathe an egalitarian colony, undoing the entire reason it exists.

Sun leans egalitarian, so an equality colony always has a friendly merchant even when Julii's prices
are bad. Between them, no ideoligion leaves the player without trade.

### `$node.Name` in PowerShell is not the element name

**The most consequential bug found in this project so far, and it had been live since Milestone 1.**

PowerShell's XML adapter exposes attributes as properties, and an attribute called `Name` **shadows**
`XmlElement.Name`. So for `<ThingDef Name="Gun_Revolver">`, `$node.Name` returns `Gun_Revolver`, not
`ThingDef`:

```
node.Name       = Gun_Revolver
node.LocalName  = ThingDef
node.get_Name() = ThingDef
```

Every type test in `Test-ModDefs.ps1` was written as `$node.Name -eq 'ThingDef'`, so **every def
carrying a `Name=` attribute was silently skipped by every check** — 838 of them in vanilla alone.
The checks did not fail; they inspected less than they claimed to and reported PASSED.

Fixed by switching all type tests to `.LocalName`, with a comment at the top of the file so it does
not come back. This is the same lesson as the collection-graphics false green: *a check that looks
like it ran is not a check that ran.*

### Seventh false green — pawn kind gear tags

A `PawnKindDef` requests gear by TAG. `PawnApparelGenerator` (decompiled) matches
`kindDef.apparelTags` against `ThingDef.apparel.tags` and rejects anything that matches none. If no
thing carries the tag at all, the pawn simply spawns **without a weapon or without clothes, and
nothing is logged** — an empty filter is not an error.

Six invented tags were in use across 18 pawn kinds, most of them shipped milestones ago:

| Invented | Actually is | Replaced with |
|---|---|---|
| `Clothing` | a `tradeTag` | `IndustrialBasic` |
| `Grenades` | a `thingCategory` | `GrenadeDestructive` |
| `Spacefarer` | nothing | `SpacerMilitary` |
| `BasicClothing`, `Worker` | nothing | `IndustrialBasic` |
| `Armor` | nothing | `IndustrialMilitaryBasic` |

Closed with `UnknownPawnKindTag`. The vocabulary is indexed from the things that **carry** the tags,
never from the kinds that request them, so a typo cannot validate itself. Negative-tested.

Note this check only became possible *after* the `.LocalName` fix — with `$node.Name`, the
`ThingDef` branch that builds the vocabulary never ran for any weapon defined with `Name=`, and the
check produced confident false positives instead.

---

## The stealth and siege kit

### ghostCloak — no new dependency

Apparel granting a self-targeted invisibility ability on a cooldown.
`ApparelProperties.abilities` is a **Core** field (decompiled to confirm); Odyssey's
mechlord suit is the only vanilla def that uses it, but the field is unconditional.
Cloak shape from Core's `Apparel_Cape`, hediff from Core's `PsychicInvisibility`.

Deliberately not psychic — vanilla `Invisibility` is a level 5 psycast scaling on
`PsychicSensitivity`, and a Howler is not a psycaster. Cooldown rather than charges,
because `CompProperties_ApparelReloadable` would need an ammo item whose only purpose
is feeding one cloak.

Occupies `Shell`, so it stacks with scarabSkin and demonHelm but **conflicts with
pulse armor**. The stealth kit and the power armour are alternatives, by design.

### Ninth false green — a gizmo that did nothing

Reported in game: Refract appeared but clicking it did nothing. Two faults, neither
logged, because an ability with no reachable target is not an error — it is inert.

1. No `targetRequired false` / `targetable false` / `nonInterruptingSelfCast`, so
   clicking dropped the pawn into target-selection mode.
2. `canTargetSelf true` alongside `canTargetPawns false`. **Self is a pawn**, so that
   excluded the only legal target.

I had copied the shape from vanilla `Invisibility`, which is a psycast aimed at
*other* pawns. The right template was Anomaly's `MetalbloodInjection` — a self-only
buff granted by worn equipment. Closed with `AbilityUntargetable`, which flags both
faults independently. Negative-tested.

### starShell — on the Exosuit Framework, gated

I first assumed a starShell was over-armour worn on pulse armor and had worked out
that a custom `ApparelLayerDef` would let it stack with no dependency at all. **That
was wrong.** In the source it is a four-metre, three-tonne powered suit with modular
weapon mounts, thrusters and heavy fuel use — exactly what the framework models. The
user's original read was correct.

Built as Core, sensor hood and cannon-arm module pairs plus a suit-scale pulse cannon,
behind `IfModActive="Aoba.Exosuit.Framework"`. Each module is a pair by framework
requirement: `ModuleItem<Slot>` carrying `EquipedThingDef`, `ModuleApparel<Slot>`
carrying `ItemDef`. **The duplicated entries in the debug spawner are that pair, not a
double load** — the worn half is `destroyOnDrop` and untradeable so it surfaces
nowhere else.

### Drachenjäger does not belong here

Forty metres, filed under Vehicles on the wiki, with a cockpit instead of a head and
pilots who bolt into it. That is a piloted vehicle, not worn apparel, so the Exosuit
Framework is the wrong tool no matter how hard it is bent. **Vehicle Framework
(`SmashPhil.VehicleFramework`) is the right tool and is already installed.** Left
unbuilt rather than built badly.

### Placeholders have to be diagnostic, not decorative

Reported: "it's impossible to tell the draw with the placeholder." Correct, and the
reason matters — a flat opaque labelled square is orientation-blind **and** it hides
the pawn underneath, so `drawData` offsets and scale cannot be assessed from it at all.

Worn directional textures are now translucent, with a red crosshair on the exact
centre (a wrong offset shows as the crosshair sitting off the pawn), a white arrow in
the facing direction, and the label moved clear of the crosshair.

That immediately paid for itself: the first screenshot with it showed the label and
the facing letter **mirrored** with the arrow reversed, confirming RimWorld
horizontally mirrors the `_east` texture for west — which is why only three facings
are generated, and now that is observed rather than assumed.

---

## The Drachenjaeger — verified, and the four faults it took to get there

Built on Vehicle Framework, gated on it, and confirmed in game: it spawns, renders,
the health tab lists its twelve components, and both turrets fire cleanly under
Combat Extended.

It took four rounds, and every fault shared one property: **the defs were valid and
the load log was clean.** None of them could have been caught by reading XML.

| # | Fault | How it presented | Found by |
|---|---|---|---|
| 1 | Body texture was one file; `Vehicles.Graphic_Vehicle` wants `_north`/`_east`/`_south` | — | listing a shipped VVE vehicle's textures |
| 2 | `VehicleBuildDef` had no `thingToSpawn` | empty architect slot, 100 NREs/sec | the OnGUI stack trace |
| 3 | No `<components>`, so total health was 0 | health tab threw on open | the error names it directly |
| 4 | Turret projectiles were vanilla `BaseBullet` | InvalidCastException on every shot | the full CE stack in `Player.log` |

Fault 2 is the sharpest lesson. `VehicleDef.buildDef` and `VehicleBuildDef.thingToSpawn`
are a **mutual pair**, and I had written only the forward half — because I read VVE's
blueprint file as far as line 35 when the field sits at line 40. Truncating a
reference file and treating the fragment as the whole pattern is its own failure mode.

Fault 4 corrects an assumption from the round before. The `CETurretDataDefModExtension`
was necessary but **not sufficient**: `CE_Utility.LaunchProjectileCE` casts the
projectile to its own CE type, so a vanilla-descended bullet throws no matter what
ammo set the extension names. The turrets now point at CE's own projectiles, which
also puts the ballistics entirely in CE's hands — the right answer regardless, since
a vanilla armour number reinterpreted in CE units is meaningless.

### Persisted state does not retroactively update

Worth stating once, because it came up twice in one session and looked like a failed
fix both times:

- The seven `Faction leader is null` lines came from **loading an old save**. Factions
  are generated at worldgen and persisted; `fixedLeaderKinds` applies when a leader is
  generated. New worlds are clean, that world never will be.
- `Total health is 0` came from a Drachenjaeger **spawned before components existed**.
  A `VehiclePawn` serializes its own component list.

In both cases the def was already correct. When a fix appears not to have taken, check
whether the thing being looked at was created before it.

### Combat Extended ammo sets are not all equally real

`AmmoSet_40mmRocket` is the obvious fit for a warhead rack and works on this machine.
It is defined in CE's `ModPatches/Rimsenal Enhanced Vanilla/` folder, so it exists only
for players who also run Rimsenal. Only ammo sets from CE's own `Defs/` tree are safe
to name. `AmmoSetFromModPatch` now warns about this.

### Checks added this session

All negative-tested. `MissingTextureDirectional`, `FactionNoLeader`, `VehiclePairBroken`,
`UnknownAmmoSet`, `AmmoSetFromModPatch`, `UnknownPawnKindTag`, `AbilityUntargetable`,
`XenotypeMissingAppearanceGene`, plus gated-mod texture and defName indexing.

**Two of them passed while inspecting nothing before being fixed** — one because
`LocalName` on `<Vehicles.VehicleDef>` is the whole dotted string, one because the
collector sat inside a branch that patch files never enter. A negative test that
produces no output is a failing check, not a passing one.

---

## The graded hierarchy ladder

Vanilla's `PreferredXenotype` precept is a flat three-way switch - liked, disliked,
neutral - and caps at three preferred xenotypes. With fifteen Colors it cannot say
the thing the setting is actually about: the feeling is **graded and signed**. A
Silver looks down on a Red and up at a Gold, and the size of both depends on the
distance. So the stage is chosen in `Source/RimRising/ThoughtWorker_ColorRank.cs`.

`ThoughtWorker_Precept_Social` is a plain abstract with one method, so no Harmony -
the same as `RoleRequirement` and `BiomeWorker`. Def structure mirrored from
Biotech's `Precepts_Bloodfeeders.xml`, the vanilla example of a precept installing a
situational *social* thought.

### The rank is not written down twice

The worker reads `XenotypeDef.displayPriority` straight out of
`XenotypeDefs_Colors.xml`, where the canonical order already lives - Gold 10 down to
Red 140, sub-strains beside their parents. Ten points is one rung. Reorder the
Colors there and the ladder follows; there is no second list to drift.

### The asymmetry is the design

| Relation | Opinion |
|---|---|
| far beneath | −20 |
| well beneath | −12 |
| beneath | −5 |
| of my own Color | +8 |
| above | +6 |
| well above | +14 |
| far above | +22 |

Looking **down** is only mildly sour - a Gold barely notices a Red, and contempt is
cheap. Looking **up** is strongly positive, because the hierarchy survives on the
belief of the people at the bottom. The net effect in a mixed colony is that
lowColors are content and highColors are faintly irritated: the Society working as
intended, and the thing an egalitarian colony feels different from.

`RR_ColorEquality` gets its own mirror precept rather than merely the absence of
this one - believers are actively pleased by company from across the ladder, so the
meme does something in daily play rather than only moving a faction goodwill number.

### Symmetry had to be made structural, not tuned

The first implementation was a list of signed edges walked with `>=`. It was wrong
twice, and neither fault was visible by reading it:

1. Adjacent Colors sit **exactly one rung apart**, so a 1.0 edge put
   Silver-looking-at-Gold in the "of my own Color" bucket while
   Gold-looking-at-Silver correctly read "beneath me".
2. Nudging the edges off the integers fixed the base Colors and moved the identical
   fault onto the **sub-strains**, which sit at half and fifth rungs - 18 pairs out
   of 21 xenotypes still mismatched.

The fix was to stop dodging boundary values: bucket the **absolute** distance, then
apply the sign. `stage(a,b) + stage(b,a) == 6` is now an identity rather than
something to re-check whenever a Color is added.

Both faults were found by **simulating the table against the real
displayPriority values** rather than by reading the code - a scripted check over all
21 xenotypes, 420 ordered pairs. Worth repeating for anything where the correctness
condition is a relation between data rather than a property of one def.

### Pawns outside the hierarchy have no rung

Baseliners, vanilla xenotypes and anything from another mod return no rank at all
rather than being slotted in somewhere. The hierarchy has opinions about Colors; a
person outside it has nothing to compare against, and giving them a default position
would quietly rank every pawn in the game on a ladder they have never heard of.

---

## A third start — the Rising

The two existing scenarios sat at opposite ends of the hierarchy but both accepted
it. With the user's ruling that a player may reject the castes, there was an obvious
gap: no way to *begin* as the thing that rejects them.

**Deliberately not a harder Breakout.** Breakout is anonymity — the shaft flooded,
the census never had your name, nobody is looking for you. The Rising is the
opposite: a cell is something the Society already knows exists and is already
hunting.

| | Household | Breakout | Rising |
|---|---|---|---|
| Party | Gold + 4 castes | 3 Reds | cross-Color cell of 5 |
| Arrival | drop pods | standing | drop pods |
| Gear | Society issue | nothing | stolen |
| First raid | storyteller's call | storyteller's call | **scheduled, day 4–7** |

Three things worth recording:

**It starts with kinds, not xenotypes.** `ScenPart_ConfigPage_ConfigureStartingPawns_KindDefs`
lets the party be actual Sons of Ares pawn kinds, so the Gray defector arrives with a
Gray's marksmanship and the Orange saboteur with an Orange's hands. Picking xenotypes
alone would have produced the right Colors with the wrong lives behind them.

**No ideoligion is forced, because RimWorld ships no ScenPart that can.** Checked
against every ScenPart vanilla actually uses — there is no ideo lever. Color equality
has to be chosen on the ideoligion page, so the description says so outright rather
than letting the player discover afterwards that the premise never took.

**The party composition is the argument.** A Gold, a Gray, an Orange and two Reds in
one room is the thing the Society says is impossible, stated as a starting roster
instead of as flavour text.

---

## A storyteller — the Board of Quality Control

The BQC is a real branch of the Society's government in the reference: it keeps the
census, sets reproductive bans, regulates the Carvers, monitors the Institute, and
sterilises the Pinks. It also, explicitly, **manages mortality rates** — cultivating
conditions that produce a desirable death rate for each Color, on the stated belief
that civilisation weakens natural selection.

That is already a storyteller's philosophy, which is why it earns a def rather than
being flavour text.

### The hook is one field, not a difficulty multiplier

RimWorld's adaptive system eases off after a death — Cassandra grants about **30 days**
of reduced pressure per colonist lost, so a disaster buys recovery time. The Board
grants **10**, and does not scale it up for larger colonies.

That is the lore expressed as a number. To the Board a death is not a setback; it is
the figure moving in the correct direction, and relenting is the one thing the
institution would never do.

Secondary tuning: threat cycles run 6 days on against 3 off (Cassandra runs 4.6
against 6.0), the start grace period is 10 days rather than 30, and friendly raids
drop from 15 a year to 9.

**Trade is deliberately untouched.** Strangling the economy would make this
unplayable rather than hard, and the merchant houses deal with everyone regardless of
what the Board thinks — which is the entire point of Julii Industries.

### Another tooling blind spot, same shape as the rest

`StorytellerDef.portraitLarge` and `portraitTiny` were invisible to **both** tools.
The suffix list recognised `texPath`, `iconPath` and `graphicPath` and nothing else,
so no placeholder was generated and no error was raised — a storyteller with no
portrait simply shows as a blank slot on the selection page.

Both tools now recognise `portrait`. Negative-tested by deleting the file, which now
errors instead of passing silently.

This is the same lesson the collection graphics and the directional textures both
taught: **a texture check only covers the node names it happens to know about.**

---

## Open questions

Carried in `docs/DESIGN.md` §8.

### Resolved

- **Roster: all 14 Colors.** Ruled by the user.
- **Gold's flaw: scarcity, not weakness.** Golds are rare and reproduce slowly. No stat penalty —
  Gold is genuinely superior, and the constraint is how few of them there are. See DESIGN §2.5.
- **packageId: `cinergy92.rimrising`.** Changed at the user's direction.
- **Mod name: RimRising.**

### Still open

1. **Prefixes for the five Colors with no established one** — invent, or leave prefix-less?
   *Lore call, user's.*
2. **Pink's framing** — social functionary with no adult content in the base mod and RJW content
   gated, or something more pointed. *Lore call, user's.*
3. **May the player reject the hierarchy?** *Lore call, user's.*

---

## Known unknowns — must be resolved before the milestone that depends on them

| # | Unknown | Blocks | Plan |
|---|---|---|---|
| U1 | Does implanting a xenogerm built from an exact Color gene set make the pawn read as that Color, or as "Hybrid"? C# behaviour in `Building_GeneAssembler`, invisible from XML. | M2 — the whole carving design | Test in game during M2. If "Hybrid", bring the user options rather than improvise. |
| U2 | Exact vanilla xenotype complexity totals. My template-gene resolution is inference, not something the game exposes. Ordering is reliable; figures are provisional. | M2 balance | Check against the in-game gene assembler. |
| U3 | Does vanilla raise a `HistoryEventDef` on xenogerm implantation? | M5 — ideoligious reaction to carving | Check before M5. If not, raising one needs Harmony. Ask before writing C#. |
| U4 | Does Odyssey expose a *personal* gravity mechanic, or only ship-scale? | M4 — gravity equipment | Read `Buildings_Gravship.xml` before M4. If ship-only, choose between stat-bonus apparel and a C# comp, and ask. |
| U5 | Full `techLevel` enum. `Industrial` and `Spacer` confirmed in use; rest unconfirmed. | M3 faction tech levels | Verify from vanilla before setting. |
| U6 | Apparel and pawn-worn texture dimensions. Gene, xenotype, item and weapon sizes are measured; these are not. | M4 placeholder art | Measure from a reference mod before M4. |
| U7 | Is it safe for `LoadFolders.xml` to name a folder that does not exist on disk? | Adding compat folders | Currently sidestepped by only listing folders that exist. Test when the first compat folder lands. |

---

## Known errors

None outstanding. One found and fixed on first load — see "First in-game load" above.

## Prior art

Two Workshop mods cover adjacent ground; details in `docs/DESIGN.md` §7. Both independently use the
full fourteen-Color roster, and both depend on Expanded Biotech Style Genes plus EyeGenes2 and
Facial Animation for caste appearance. **RimRising stays on vanilla Biotech spectrum genes for now**
so it runs on Core + Biotech + Ideology alone. Revisit once the system works.

Neither appears to implement carving as a playable mechanic, which makes it the most distinctive
thing this mod can do.

---

## Environment notes

- Developing against a minimal profile per the user's direction: Core, the five DLC, Harmony, and
  this mod. Integrations get added deliberately, not inherited from the user's 151-mod list.
- The user's `Player.log` was last written 2026-04-25 and predates the current game build. The
  first Milestone 1 launch establishes a usable baseline.
- `Tools/.cache/vanilla-defs.json` is gitignored and rebuilds on demand. It is keyed on
  `Version.txt`, so a game update invalidates it automatically.
