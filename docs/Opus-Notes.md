# Notes for the local session — the second content pass (2026-10-09)

Written by the cloud session that drafted the suggestions-doc items on `master`. Everything
below needs something the cloud box does not have: the .NET SDK, Blender, the game install,
or the game itself. Nothing here has loaded in a game. **Build first, then launch, then read
the log** — the unbuilt C# is referenced from XML and will error on load until the DLL
carries it.

Each item says what was done, what is unverified, and exactly what to do. The in-game
checks are in `docs/PROGRESS.md`, Milestone 12.


> **Status, 2026-10-10 (local session):** everything below is done - built, verified against
> the game, fixed where it was wrong, and checked in code by `rrtestmode=m12`. Design calls went
> to the user. See `docs/PROGRESS.md`, Milestone 12, for what changed and why.

---

## 1. Build the DLL (blocks everything else)

Four source files are new or changed and were never compiled:

| File | What it adds | API points to check if the build complains |
|---|---|---|
| `Source/RimRising/CasteLabor.cs` | `CasteWorkExtension`, `ThoughtWorker_CasteLabor`, `_Equality` | `ThoughtWorker_Precept` as the non-social base (the social one is already used in `ThoughtWorker_ColorRank.cs`); `Pawn.CurJob.workGiverDef.workType` |
| `Source/RimRising/Sigils.cs` | `RR_Sigils`, `Patch_PawnGenerator_Sigil`, `Recipe_ForgeSigil` | the `PawnGenerator.GeneratePawn(PawnGenerationRequest)` overload as the Harmony target; `health.AddHediff(def, part)`; `GetNotMissingParts()` |
| `Source/RimRising/IncidentWorkers.cs` | `IncidentWorker_Letter`, `IncidentWorker_Laurel` | `CanFireNowSub` / `TryExecuteWorker` signatures; `Find.Storyteller.incidentQueue.Add(def, tick, parms)`; `LetterDefOf.NeutralEvent` |
| `Source/RimRising/Recipe_CarveColor.cs` | two `CarvingAftermath.Add` calls, one on the failure branch | `pawn.Dead` after `CheckSurgeryFail` |

`pwsh -File Tools/Build-Mod.ps1`. The XML that names these classes:
`Precepts_CasteLabor.xml` (two `workerClass`), `Carving/Sigils.xml` (`workerClass`
`RimRising.Recipe_ForgeSigil`), `IncidentDefs/Incidents_RimRising.xml` (both workers),
`GeneDefs/XenotypeDefs_Colors.xml` (`RimRising.CasteWorkExtension` on all 21 xenotypes).

## 2. Verify the fields marked UNVERIFIED (each is a load error if wrong)

Run `.claude/skills/newdef/scripts/Find-VanillaDef.ps1` for each; the def's header
says what to compare.

| Def | Field | Check against |
|---|---|---|
| `RR_Caravan_Society_Census`, `RR_Caravan_Dominion_Census` | `tradeCurrency Favor`, `faction` | `Royalty/Defs/TraderKindDefs/TraderKinds_Caravan_Empire.xml` (tribute collector). If favour currency is Empire-only in code, drop both fields and the caravan pays silver; the ladder then needs another favour source - a design call for the user. |
| `RR_HeliumThree` | `deepCommonality`, `deepCountPerPortion`, `deepLumpSizeRange` | `Core/Defs/ThingDefs_Items/Items_Resource_Stuff.xml` (Uranium) |
| `RR_ClawDrill` | `<compClass>CompDeepDrill</compClass>`, thingClass | `Core/Defs/ThingDefs_Buildings/Buildings_Production.xml` (DeepDrill) |
| `RR_RazorTrialOutcome` | `workerClass RitualOutcomeEffectWorker_FromQuality` | `Ideology/Defs/RitualOutcomeEffectDefs/` - every reference mod uses its own subclass, so the base name is from memory |
| `RR_Tattoo_*` | `tattooType Face/Body` and the whole TattooDef field set | `Ideology/Defs/TattooDefs/` |
| `RR_Role_Engineer` | `ConstructSuccessChance` stat | `Core/Defs/StatDefs/` |
| `RR_Weapon_Razor_Heirloom` | that `BaseWeapon_Bladelink` supplies the bladelink and generated-name comps | `Royalty/Defs/ThingDefs_Misc/Weapons/MeleeBladelink.xml` |
| `CasteWorkExtension` lists | WorkTypeDef names (`Research`, `Doctor`, `Warden`, `PatientBedRest`, `Childcare`, …) | `Core/Defs/WorkTypeDefs/` - a wrong name is a cross-reference error naming the xenotype |

## 3. Art that needs Blender or the test scene

- **slingBlade sprite.** `Tools/Draw-Weapons.py` has a `sling_blade()` design and an
  `OUTPUTS` entry. Run it through Blender as the file header says; it will also redraw the
  razors, which the generated-art pass may have replaced - check `git status` after and keep
  only `RR_SlingBlade.png` if the others changed. Then the tweak data:
  ```
  blender -b --factory-startup --python Tools/Derive-MeleeTweak.py -- Textures/Things/Item/Equipment/WeaponMelee/RR_SlingBlade.png RR_Weapon_SlingBlade 0.273 0.754 0.52 0.52 2
  ```
  (grip at 35 % along the haft, blade starting at the haft's end, type 2 Long_Sharp - a
  curved cutting tool, unlike the razors; CLAUDE.md explains why they are 6.) Until then the
  slingBlade is a placeholder and Melee Animation falls back to the static sprite.
- **Howler pelt worn art.** A `Draw-PanelArmor.py` design: a shoulder mantle only, no
  falling panels (the cloak design minus its lower half). Register it undyed, with no
  Realistic Body variant - it stops at the shoulders. Then the test scene beside the cloak.
- **Griffin and clawDrill sprites.** Through whatever drew the pitviper
  (`Tools/Draw-Nature.py`, by its name). Griffin: four-legged, a raptor's head, folded wings;
  the Society's beast, so gold trim.
- **Tattoo overlays.** Four 128² overlays under `Things/Pawn/Humanlike/Tattoos/`. These are
  glyphs on skin, so `New-XenotypeIcons.ps1` is the right generator (it owns glyph art), not
  the placeholder script. Check Ideology's facing convention for tattoos first - the
  placeholders were written both as a bare file and as `_south/_north/_east`.
- **Role, ritual and issue icons.** `UI/Roles/RR_Role_*` (five), `UI/Rituals/RR_RazorTrial`,
  `UI/Issues/RR_CasteLabor`. Glyphs, same generator.
- **Heirloom razor.** `RR_RazorHeirloom` is a placeholder; the intended sprite is the razor
  with a darker, worn hilt - `razor()` with a second grip colour.

## 4. Things left out on purpose, with the one-line test for each

- **Griffins in Society raids.** Add `<RR_Griffin>0.4</RR_Griffin>` to `RR_Society`'s Combat
  `options` and generate a raid (`rrtestmode=kinds` or dev mode). If the lord assigns the
  animal a duty without complaint, keep it; if it logs, the animal needs a `PawnGroupMaker`
  of its own kind. Not done because the cloud session could not verify animal kinds in a
  humanlike group.
- **Gold-only duelists.** A `RitualRoleColonist` subclass whose `AppliesToPawn` also
  requires `RR_CasteIdentity.IsRulingCaste(pawn)`; swap it in for both duelist roles in
  `Rituals_RazorTrial.xml`. Not written because the override's signature was not available
  to check.
- **The heirloom razor's whip.** Add `<li Class="CompProperties_EquippableAbility">
  <abilityDef>RR_RazorWhip</abilityDef></li>` to the heirloom's `comps` WITHOUT
  `Inherit="False"`, equip one, and check the health tab and the equipment gizmos: if the
  whip gizmo appears and nothing logs about duplicate `CompEquippable`, keep it. If it
  logs, the heirloom stays rigid-only (the header explains why that is defensible).
- **Red deep-drilling bonus.** A `GeneDef` with `statFactors DeepDrillingSpeed` on the two
  Red xenotypes. Needs a glyph recipe in `New-XenotypeIcons.ps1` first (icon ownership).
- **ClawDrill yield.** Vanilla exposes no per-building yield; a `Building` subclass
  overriding the deep-drill portion is the lever, if wanted.
- **Pulse armour helium upkeep.** The suggestions doc (2.4) argues against fuel on
  clothing; the honest middle path is `TraumaSuite.cs` restocking stims from a
  `RR_HeliumThree` in inventory. **Ask the user before building either.**
- **Sigil reads.** `RR_Sigils.SigilMismatch(pawn)` exists; nothing calls it yet. The two
  intended readers: the census caravan (a trader-arrival check that refuses to deal, or
  reports a mismatched pawn, when a colonist's paper and body disagree) and the Lurcher
  hunt below.
- **Player starting pawns have no sigil.** The postfix stamps only filed factions. If the
  Household and Breakout starts should begin with paper, `ScenPart_ForcedHediff` with the
  matching `RR_Sigil_*` is the XML way - a design call.

## 5. Not drafted - C# against the game, or art the cloud cannot make

- **2.2 The Lurcher hunt.** An `IncidentDef` with an `IncidentWorker_RaidEnemy` subclass
  that fires only when `RR_Sigils.SigilMismatch` is true for some colonist or when the
  `RR_LowColorBoreRazor` history event has been recorded, forces `RR_Society` as the
  faction, and generates its group from `RR_Society_Lurcher` only. Weight it higher under
  `RR_Storyteller_BQC`. The letter should name the pawn the Society is after.
- **2.6 Iron Rain.** No reference mod sets arrival modes per faction in XML, and vanilla's
  `FactionDef` has no such field that any of them use. The lever is a Harmony postfix on
  `PawnsArrivalModeWorker`/`RaidStrategyWorker` selection that weights `CenterDrop` and
  `EdgeDrop` for `RR_Society` and `RR_RimDominion` and removes them for the tribes.
  Decompile the selection first; the method names above are from memory.
- **2.7 RipWing.** A second Vehicle Framework triad in `1.6/Mods/Vehicles/`, aerial.
  Mirror the Drachenjäger's three defs and VF's own aerial example (the framework ships
  one); art through `New-VehicleArt.ps1`. Blues as pilots needs the gravship answer below.
- **6.7 Blues and gravships.** Read `Odyssey/Defs/` for the gravship console `ThingDef`
  and any `StatDef` it names. If there is a piloting stat, give `RR_Blue` a `statFactors`
  entry and swap the Pilot role's stand-in stats (`Roles_Colors.xml`) for it. If piloting
  is a plain job, the lever is a `PreceptComp_UnwillingToDo`-style precept, never a hard
  gate - a Red colony with no Blue must still be able to leave.
- **The Dominion's own ladder** (suggestions, section 3). A second `royalTitleTags` set
  and `TitleLadders.cs` learning a third tag in `EligibleFor`. The Dominion census caravan
  already pays its favour; today that favour climbs the Society's rungs.
- **Observer thought for caste labour** (2.3). "A Red at the research bench" as a
  `ThoughtWorker_Precept_Social` reading the OTHER pawn's current job through
  `CasteLabor.WorkingOutsideCaste(otherPawn)`. The helper is written; the worker and a
  second `PreceptComp_SituationalThought` are not.

## 6. CE numbers are first placements

Heirloom razor (CE's bladelink x1.21 convention), slingBlade (CE gladius band, re-checked 2026-10-25), Howler pelt (bulk
only; armour is the leather's). Judge in play, as with the armour pass.
