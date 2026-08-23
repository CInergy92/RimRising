# PROGRESS

Milestone status, open questions, known errors. Updated as work lands.

Game target: **RimWorld 1.6.4871 rev590**. packageId: `cinergy92.rimrising`.

---

## Milestone status

| # | Milestone | Status |
|---|---|---|
| 0 | Discovery | **Done.** `docs/DISCOVERY.md` |
| 1 | Skeleton | **Loaded in game. Texture bug fixed; awaiting re-verification** |
| 2 | The Color system | **Built, validated, published; awaiting in-game verification** |
| 3 | Factions and pawn kinds | Not started |
| 4 | Tech and equipment | Not started |
| 5 | Ideology and hierarchy | Not started |
| 6 | Scenarios and world | Not started |
| 7 | Vanilla suppression | Not started |

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
