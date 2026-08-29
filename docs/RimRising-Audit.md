# RimRising static audit

Target: RimWorld 1.6 (verified against 1.6.4871 rev590 `Assembly-CSharp.dll`).
Mod root audited: `A:\Projects\RimRising`.
Method: every XML file parsed and type-checked field by field against types decompiled from `Assembly-CSharp.dll`, `Vehicles.dll`, `SmashTools.dll`, `CombatExtended.dll` and `0Harmony.dll`; every def cross-reference resolved against the vanilla def index plus the installed dependency mods; every `<xpath>` evaluated against a merged vanilla+mod `<Defs>` document; every C# API member checked against the decompiled IL before being called correct.

No file was modified.

## Summary

| Severity | Count |
|---|---|
| BLOCKER | 0 |
| MAJOR | 6 |
| MINOR | 18 |
| NOTE | 12 |

Nothing in this mod prevents RimWorld from loading. All 42 XML files are well formed, all 230 defNames are unique within their def type, all 235 `Class=` / `workerClass` / `compClass` references resolve to types that exist (the only exceptions are the eight `Exosuit.*` classes, which belong to a framework not installed on this machine and are correctly folder-gated), no enum literal anywhere in the mod is invalid, all 73 asset paths resolve to files that exist, every `[DefOf]` field matches a def of the right type, every translation key used in C# is defined, and the compiled `1.6/Assemblies/RimRising.dll` is newer than every `.cs` file, so the source as it stands compiles.

The problems that remain are of two kinds. Two are unresolved cross-references that will print red at load and silently remove content (RR-001, RR-002). Four are semantic errors where the XML is valid but RimWorld's own resolution rules produce something other than what the def author intended: two lists merge with their parent's when the author expected a replacement (RR-003 and, at MINOR, RR-009, RR-010 and RR-011), one goodwill pairing is declared twice in a worker that is symmetric (RR-004), one faction merges two intentionally separate title ladders into one seniority chain (RR-005), and one faction advertises trade caravans it has no pawn group maker to produce (RR-006). RR-004 and RR-005 need a design decision rather than a mechanical edit.

Overall health is good. The codebase is unusually well documented, the C# is defensive and uses no invented API, the folder gating in `LoadFolders.xml` is correct, and the Combat Extended vehicle patch is verified correct down to the ammo set defNames. The recurring weakness is RimWorld's list-inheritance semantics: `XmlInheritance.RecursiveNodeCopyOverwriteElements` treats `<li>` children as merge-append, so a child def that redeclares a list without `Inherit="False"` gets the parent's entries plus its own. Four findings below are instances of that one rule.

## Findings

### [MAJOR] Drachenjaeger research depends on a def that only exists in the Exosuit folder

- File: `1.6/Mods/Vehicles/Defs/Drachenjager.xml`
- Location: line 49, `/Defs/ResearchProjectDef[defName="RR_DrachenjagerFrame"]/prerequisites`
- ID: RR-001
- Current:
  ```xml
  <prerequisites>
    <li>RR_StarShellFrame</li>
    <li>RR_NeuralInterface</li>
  </prerequisites>
  ```
- Problem: `RR_StarShellFrame` is declared only in `1.6/Mods/Exosuit/Defs/StarShell.xml` line 40. `LoadFolders.xml` gates `1.6/Mods/Exosuit` behind `IfModActive="Aoba.Exosuit.Framework"` and `1.6/Mods/Vehicles` behind `IfModActive="SmashPhil.VehicleFramework"`. The two gates are independent, so a player running Vehicle Framework without the Exosuit Framework loads this file while `RR_StarShellFrame` does not exist. `DirectXmlCrossRefLoader.WantedRefForList.TryResolve` logs `Could not resolve cross-reference: No Verse.ResearchProjectDef named RR_StarShellFrame found to give to Verse.ResearchProjectDef RR_DrachenjagerFrame` and drops the entry (verified in IL: on failure nothing is added to the list, so there is no null and no NRE). Net effect: a red error at every load, and the Drachenjaeger research loses one of its two gates.
- Fix: remove `<li>RR_StarShellFrame</li>` from the prerequisites and keep `RR_NeuralInterface`, OR keep it and add `MayRequire="Aoba.Exosuit.Framework"` to that `<li>`, which makes the reference conditional on the same mod the def's own folder is gated on. `MayRequire` on a list element is the supported mechanism and is already understood by the same code path. If the design intent is that the Drachenjaeger genuinely requires starShell tech, the prerequisite research must be moved out of `1.6/Mods/Exosuit/Defs/` into `1.6/Defs/ResearchProjectDefs/Research_RimRising.xml` so it exists unconditionally; that is a design decision.
- Depends on: none

### [MAJOR] `AccelerationRate` is not a VehicleStatDef

- File: `1.6/Mods/Vehicles/Defs/Drachenjager.xml`
- Location: line 229, `/Defs/Vehicles.VehicleDef[defName="RR_Drachenjager"]/vehicleStats/AccelerationRate`
- ID: RR-002
- Current:
  ```xml
  <vehicleStats>
    <Mass>1800</Mass>
    <MoveSpeed>4.2</MoveSpeed>
    <CargoCapacity>120</CargoCapacity>
    <RepairRate>0.3</RepairRate>
    <AccelerationRate>0.02</AccelerationRate>
  </vehicleStats>
  ```
- Problem: `VehicleDef.vehicleStats` is `List<VehicleStatModifier>`, and `VehicleStatModifier.LoadDataFromXmlCustom` calls `DirectXmlCrossRefLoader.RegisterObjectWantsCrossRef(this, "statDef", node.Name, ...)`, so each child tag name is resolved as a `Vehicles.VehicleStatDef` defName. Vehicle Framework 3014915404 defines exactly eight: `BodyIntegrity`, `CargoCapacity`, `FlightControl`, `FlightSpeed`, `Mass`, `MoveSpeed`, `RepairRate`, `WorkToSabotage`. There is no `AccelerationRate`. Result: `Could not resolve cross-reference: No Vehicles.VehicleStatDef named AccelerationRate found` at every load, plus a `VehicleStatModifier` with a null `statDef` left in the list, which Vehicle Framework's stat handler will dereference the first time the vehicle's stats are read.
- Fix: delete line 229 entirely. Acceleration is not a modelled stat in Vehicle Framework 1.6; there is no equivalent field to move the value to.
- Depends on: none

### [MAJOR] Carveling vats get two `CompProperties_Forbiddable`

- File: `1.6/Mods/AlphaAnimals/Defs/Carvelings.xml`
- Location: lines 65-67, `/Defs/ThingDef[@Name="RR_CarvelingVatBase"]/comps`
- ID: RR-003
- Current:
  ```xml
  <comps>
    <li Class="CompProperties_Forbiddable" />
  </comps>
  ```
- Problem: `RR_CarvelingVatBase` has `ParentName="ResourceBase"`, and vanilla's `ResourceBase` (Core/Defs/ThingDefs_Items/Items_Resource_Base.xml) already declares `<comps><li Class="CompProperties_Forbiddable"/></comps>`. `XmlInheritance.RecursiveNodeCopyOverwriteElements` treats `<li>` as a list element and appends the child's items to the parent's rather than replacing them (`IsListElement` returns true for `li`), so the resolved def carries the comp twice. Every carveling vat therefore spawns with two `CompForbiddable` instances: two forbid gizmos on the item, and two comps writing `Scribe_Values.Look(ref forbiddenInt, "forbidden")` into the same Thing node, which produces "Trying to write node with the same name twice" errors on save and an unpredictable value on load.
- Fix: delete lines 65-67 (the whole `<comps>` block on `RR_CarvelingVatBase`). The comp is already inherited. Do not add `Inherit="False"` instead, because the three concrete children (`RR_CarvelingVat_Sylph`, `_Lion`, `_Animalisk`) each declare their own `<comps>` with `CompProperties_Hatcher` and rely on the merge to keep the inherited Forbiddable.
- Depends on: none

### [MAJOR] The hierarchy/equality goodwill penalty is applied twice

- File: `1.6/Defs/Goodwill/GoodwillSituations_RimRising.xml`
- Location: lines 53-60 (`RR_ColorOrder_Disagreement`) and lines 67-91 (`RR_ColorHierarchy_VersusEgalitarian`)
- ID: RR-004
- Current:
  ```xml
  <GoodwillSituationDef>
    <defName>RR_ColorOrder_Disagreement</defName>
    <workerClass>GoodwillSituationWorker_MemeCompatibility</workerClass>
    <meme>RR_ColorHierarchy</meme>
    <otherMeme>RR_ColorEquality</otherMeme>
    <naturalGoodwillOffset>-40</naturalGoodwillOffset>
  </GoodwillSituationDef>
  ...
  <GoodwillSituationDef>
    <defName>RR_ColorHierarchy_VersusEgalitarian</defName>
    <workerClass>GoodwillSituationWorker_MemeCompatibility</workerClass>
    <meme>RR_ColorEquality</meme>
    <otherMeme>RR_ColorHierarchy</otherMeme>
    <naturalGoodwillOffset>-100</naturalGoodwillOffset>
  </GoodwillSituationDef>
  ```
- Problem: `GoodwillSituationWorker_MemeCompatibility.Applies(Faction other)` calls `Applies(other, Faction.OfPlayer)` and, if that is false, `Applies(Faction.OfPlayer, other)` (verified in IL). The worker is symmetric, so one def already covers both directions of the pairing. These two defs are the same pairing written both ways, and both return their offset for the same faction/player combination. `GoodwillSituationManager.GetNaturalGoodwill` sums every applicable situation with no clamp, so the actual offset is **-140**, not the -100 the second def's comment documents as the intended "price of the Rising". The file's own comment says -100 is deliberately just past the -75 permanent-hostility floor; -140 is 65 points past it.
- Fix: delete one of the two defs. Which one is a design decision. The straightforward fix is to delete `RR_ColorOrder_Disagreement` (lines 53-60) entirely and keep `RR_ColorHierarchy_VersusEgalitarian` at -100, since its comment is the one that reasons about the -75 floor. If both defNames must be kept for save compatibility, set one of the two `naturalGoodwillOffset` values to `0`. Note that the same double-counting does **not** affect `RR_GoldWorship_WithHierarchy` / `RR_GoldWorship_VersusEgalitarian`, which are distinct pairings.
- Depends on: none. Needs a developer decision on which def survives.

### [MAJOR] The Gold and Service title ladders merge into a single seniority chain

- File: `1.6/Defs/FactionDefs/Factions_RimRising.xml` (with `1.6/Defs/RoyalTitles/RoyalTitles_Gold.xml` and `1.6/Defs/RoyalTitles/RoyalTitles_Service.xml`)
- Location: `Factions_RimRising.xml` lines 50-55, `/Defs/FactionDef[defName="RR_Society"]/royalTitleTags`
- ID: RR-005
- Current:
  ```xml
  <royalTitleTags>
    <li>RR_GoldTitle</li>
    <li>RR_ServiceTitle</li>
  </royalTitleTags>
  ```
  with seniorities `RR_Title_Shamed` 0 and `RR_Title_Legionnaire` 0, `RR_Title_Graduate` 200, `RR_Title_Praetorian` 300, `RR_Title_PeerlessScarred` 500.
- Problem: `FactionDef.RoyalTitlesAwardableInSeniorityOrderForReading` walks `DefDatabase<RoyalTitleDef>.AllDefsListForReading()` and adds every title whose `tags` share **any** element with the faction's `royalTitleTags`, then sorts the whole collection by `seniority` (verified in IL). Listing both tags on one faction therefore produces one ladder, not two: `Shamed(0)`, `Legionnaire(0)`, `Graduate(200)`, `Praetorian(300)`, `PeerlessScarred(500)`. Two consequences. First, the two seniority-0 titles collide, and which one a favour award or an inheritance worker picks is decided by `DefDatabase` ordering rather than by design. Second, the C# gates in `Source/RimRising/GoldTitlePatches.cs` (blocks `RR_GoldTitle` for non-ruling-caste) and `Source/RimRising/CasteArmor.cs` line 260 (blocks `RR_ServiceTitle` for ruling caste) are mutually exclusive, so a Gold who has reached `Graduate` and earns enough favour for the next rung in the merged chain is offered `Praetorian`, which the prefix refuses. The title award silently does nothing and the pawn's advancement stalls at `Graduate`. The same happens in reverse for an Obsidian at `Legionnaire` whose next rung is `Graduate`.
- Fix: the two ladders must not share a faction's tag list. Preferred: remove `<li>RR_ServiceTitle</li>` from `RR_Society.royalTitleTags` and give the service ladder to a separate FactionDef, or fold the service ranks into the Gold chain with distinct non-colliding seniorities and drop the `CasteArmor.cs` `SetTitle` prefix. Whichever is chosen, no two `RoyalTitleDef`s reachable from one faction may share a `seniority` value.
- Depends on: none. This one needs a developer decision, not a mechanical edit; RR-023 and RR-025 describe the C# side of the same mechanism.

### [MAJOR] RR_ObsidianTribes advertises trade caravans it cannot produce

- File: `1.6/Defs/FactionDefs/Factions_RimRising.xml`
- Location: `pawnGroupMakers` lines 639-661; `caravanTraderKinds` lines 663-667
- ID: RR-006
- Current: `pawnGroupMakers` contains only `<kindDef>Combat</kindDef>`, `<kindDef>Peaceful</kindDef>` and `<kindDef>Settlement</kindDef>`, while the def also declares
  ```xml
  <caravanTraderKinds>
    <li>Caravan_Neolithic_BulkGoods</li>
    <li>Caravan_Neolithic_WarMerchant</li>
    <li>Caravan_Neolithic_ShamanMerchant</li>
  </caravanTraderKinds>
  ```
- Problem: `IncidentWorker_TraderCaravanArrival` inherits `IncidentWorker_NeutralGroup`, whose `FactionCanBeGroupSource` returns false unless `f.def.pawnGroupMakers.Any(x => x.kindDef == PawnGroupKindDefOf.Trader)` (verified in IL). With no `Trader` group maker the trade-caravan incident can never select this faction, so the three caravan trader kinds are dead configuration and the Obsidian tribes never send a trade caravan. `visitorTraderKinds` (lines 668-670) still works because the `Peaceful` group maker exists, and `baseTraderKinds` (671-673) still works for settlement trading, which is why this is easy to miss in play.
- Fix: add a fourth entry to `RR_ObsidianTribes.pawnGroupMakers`, modelled on the `Trader` group maker already present on `RR_Society` / `RR_RimDominion` / `RR_SonsOfAres` in the same file. It needs `<kindDef>Trader</kindDef>`, a `<traders>` option list, a `<carriers>` option list and a `<guards>` option list; copy the shape from `RR_SonsOfAres` and substitute `RR_Tribe_Obsidian_Warrior` for the guard and a neolithic pack animal for the carrier. If the tribes are meant not to send caravans, delete `caravanTraderKinds` lines 663-667 instead.
- Depends on: none

### [MINOR] RR_Ascomanni trader kinds are unreachable

- File: `1.6/Defs/FactionDefs/Factions_RimRising.xml`
- Location: `RR_Ascomanni` defName line 692; `pawnGroupMakers` lines 767-783; `caravanTraderKinds` lines 785-787; `baseTraderKinds` lines 788-790
- ID: RR-007
- Current: `permanentEnemy` is `true`; `pawnGroupMakers` contains only `Combat` and `Settlement`; `caravanTraderKinds` and `baseTraderKinds` are both declared.
- Problem: `FactionCanBeGroupSource` returns false for any faction hostile to the player, and there is no `Trader` group maker in any case, so `caravanTraderKinds` can never fire. `baseTraderKinds` requires the player to trade at the settlement, which a permanent enemy will not permit. Both lists are dead.
- Fix: delete `caravanTraderKinds` (785-787) and `baseTraderKinds` (788-790) from `RR_Ascomanni`, or drop `permanentEnemy` and add a `Trader` group maker if the raiders are meant to be tradeable with.
- Depends on: none

### [MINOR] Two research projects have no tree position

- File: `1.6/Defs/ResearchProjectDefs/Research_RimRising.xml`
- Location: `RR_RecoilPlating` lines 73-85; `RR_GravManipulation` lines 153-165
- ID: RR-008
- Current: both defs end at `</prerequisites>` with no `<researchViewX>` / `<researchViewY>`.
- Problem: `ResearchProjectDef.researchViewX` and `researchViewY` both default to `1.0` (verified against the field initialisers in IL). Every other project in this file sets an explicit position. These two land on top of each other at (1, 1) in the `RR_Artificer` tab, on top of anything else that also defaults there, and the research tree draws them overlapping.
- Fix: add `<researchViewX>` and `<researchViewY>` to both, using positions consistent with the rest of the tab. `RR_RecoilPlating` is a prerequisite of `RR_PulseArmor` so it belongs to the left of it; `RR_GravManipulation` unlocks gravBoots and has only `Fabrication` as a prerequisite, so it belongs in the first column.
- Depends on: none

### [MINOR] ghostCloak becomes craftable at tailoring benches

- File: `1.6/Defs/ThingDefs_Misc/Apparel_GhostCloak.xml`
- Location: line 135, `/Defs/ThingDef[defName="RR_Apparel_GhostCloak"]/recipeMaker/recipeUsers`
- ID: RR-009
- Current:
  ```xml
  <recipeUsers>
    <li>FabricationBench</li>
  </recipeUsers>
  ```
- Problem: the def has `ParentName="ApparelMakeableBase"`, whose `recipeMaker` already declares `<recipeUsers><li>ElectricTailoringBench</li><li>HandTailoringBench</li></recipeUsers>`. Lists merge, so the resolved recipe users are all three benches and a spacer-tech stealth cloak with a refractive lattice can be sewn at a hand tailoring bench. Every other craftable in this mod uses `Inherit="False"` here: `Apparel_RimRising.xml` lines 33, 226, 312, 713, 851 and `Weapons_RimRising.xml` lines 44, 163, 439, 510. Vanilla itself uses `<recipeUsers Inherit="False">` on `ApparelArmorCataphractBase` for the same reason.
- Fix: change line 135 to `<recipeUsers Inherit="False">`.
- Depends on: none

### [MINOR] duroArmor and recoilArmor inherit their recipe users silently

- File: `1.6/Defs/ThingDefs_Misc/Apparel_RimRising.xml`
- Location: `RR_Apparel_DuroArmor` def at line 390; `RR_Apparel_RecoilArmor` def at line 479
- ID: RR-010
- Current: neither def declares `recipeMaker/recipeUsers` at all.
- Problem: both inherit `ArmorMachineableBase`'s recipe users. That may be intended, but it is the only place in the mod where the bench list is left implicit, and it is not stated in the surrounding comments the way every other decision in this file is. Worth confirming rather than fixing blind: if `ArmorMachineableBase` resolves to the machining table alone, duroArmor is correct and recoilArmor is probably too permissive for a suit the mod otherwise restricts to the ruling caste.
- Fix: add an explicit `<recipeUsers Inherit="False">` to `RR_Apparel_RecoilArmor` naming `FabricationBench`, matching `RR_Apparel_PulseArmor` at line 33. Leave `RR_Apparel_DuroArmor` inheriting if the machining table is intended, and add a one-line comment saying so.
- Depends on: RR-009 (same rule, apply together)

### [MINOR] Pawn kind apparelTags merge with the base kind's

- File: `1.6/Defs/PawnKindDefs/PawnKinds_RimRising.xml`
- Location: `RR_SocietyFighterBase` apparelTags line 47; children that redeclare `apparelTags` without `Inherit="False"` at lines 68, 96, 124, 155, 190, 242. Same pattern on `RR_AresFighterBase` (line 397) children at 411, 441, 471, 502, 535, and on `RR_AscomanniBase` (line 634) children at 647 and 674.
- ID: RR-011
- Current:
  ```xml
  <PawnKindDef Name="RR_SocietyFighterBase" ParentName="RR_ColorPawnBase" Abstract="True">
    <apparelTags>
      <li>IndustrialMilitaryBasic</li>
      <li>IndustrialMilitaryAdvanced</li>
      <li>SpacerMilitary</li>
    </apparelTags>
  ```
  and, in `RR_Society_Legionary`:
  ```xml
  <apparelTags>
    <li>RR_BasicPlate</li>
    <li>IndustrialBasic</li>
  </apparelTags>
  ```
- Problem: lists merge, so `RR_Society_Legionary` actually generates against `IndustrialMilitaryBasic`, `IndustrialMilitaryAdvanced`, `SpacerMilitary`, `RR_BasicPlate`, `IndustrialBasic`. The comment on that def says it was given tags specifically to stop it "generating any apparel in the game". The `RR_HeavyPlate` tag does keep it out of pulseArmor and recoilArmor (neither carries `SpacerMilitary`), so the worst case is contained, but a rank-and-file Gray can still spawn in vanilla marine or cataphract armour, in `RR_Apparel_ScarabSkin`, in `RR_Apparel_DemonHelm` and in `RR_Apparel_GhostCloak`, all of which are tagged `SpacerMilitary`. `RR_Ascomanni_Raider` and `RR_Ascomanni_Warlord` likewise inherit `Neolithic` despite their comments describing them as industrial salvage raiders.
- Fix: add `Inherit="False"` to the `<apparelTags>` element on each of the twelve concrete kinds listed above, and re-add whichever parent tags each kind actually wants. Do not remove the tags from the abstract bases; other kinds rely on them.
- Depends on: none

### [MINOR] Five Drachenjaeger fields use deprecated Vehicle Framework aliases

- File: `1.6/Mods/Vehicles/Defs/Drachenjager.xml`
- Location: `spreadRadius` lines 119, 126, 171; `vehicleType` line 215; `winterSpeedMultiplier` line 242; `maxHealth` lines 326, 393; `turretDef` lines 428, 465
- ID: RR-012
- Current: e.g. `<spreadRadius>1.2</spreadRadius>`, `<vehicleType>Land</vehicleType>`, `<turretDef>RR_Drachenjager_ParticleCannon</turretDef>`
- Problem: none of these names is a real field. They load only because Vehicle Framework carries `[LoadAlias]` attributes on the renamed fields: `spreadRadius` → `FireMode.forcedMissRadius`, `vehicleType` → `VehicleDef.type`, `winterSpeedMultiplier` → `VehicleProperties.winterCost`, `maxHealth` → `Reactor_Explosive.healthPercent`, `turretDef` → `VehicleTurret.def` (all confirmed by decoding the attribute blobs in `Vehicles.dll`). Aliases are courtesy shims that framework authors drop; when they do, these become unknown-field errors. `winterSpeedMultiplier` is additionally a semantic trap: the real field is a **cost**, so `1` means neutral by coincidence and any other value will read backwards from what the name suggests.
- Fix: rename to the real field names: `forcedMissRadius`, `type`, `winterCost`, `healthPercent`, `def`. Keep the values as they are except `winterCost`, where `1` should be confirmed as the intended cost multiplier rather than a speed multiplier.
- Depends on: none

### [MINOR] `<success>Always</success>` hides patch failures on the mod's core wiring

- File: `1.6/Patches/Carving_Human.xml` and `1.6/Mods/Vehicles/Patches/CombatExtended.xml`
- Location: `Carving_Human.xml` line 20; `CombatExtended.xml` on all four operations
- ID: RR-013
- Current:
  ```xml
  <Operation Class="PatchOperationAdd">
    <success>Always</success>
    <xpath>/Defs/ThingDef[defName="Human"]/recipes</xpath>
  ```
- Problem: this single operation is what attaches all eighteen carving and restoration surgeries to humans. With `success Always` a failure to match produces no error at all, and the entire carving system, which is the mod's central mechanic, disappears with nothing in the log to say why. The file's own comment acknowledges this is a project convention; the convention is wrong for a load-bearing patch. Both xpaths currently match (verified against a merged vanilla+mod document: 1 match each).
- Fix: remove `<success>Always</success>` from `Carving_Human.xml` line 20 so a future failure reports itself. Keep it on the four Combat Extended operations in `CombatExtended.xml`, which are genuinely optional compatibility.
- Depends on: none

### [MINOR] Six sub-strain Colors have no caste dye

- File: `Source/RimRising/CasteArmor.cs`
- Location: `RR_CasteColors.ByDefName`, lines 164-182
- ID: RR-014
- Current: the dictionary has fifteen entries, keyed `RR_Gold` through `RR_White`.
- Problem: `XenotypeDefs_Colors.xml` also defines `RR_Green_FulgurBellator` (562), `RR_Gray_Lurcher` (593), `RR_Obsidian_Stained` (627), `RR_Obsidian_Ascomanni` (657), `RR_Pink_Rose` (685) and `RR_Red_Ultraheavy` (711). `RR_CasteColors.For` returns null for all six, so `ApplyCasteColor` returns early and a Lurcher in recoilArmor wears it in the default texture colour while the Gray beside him is dyed. `RR_CasteIdentity` sorts sub-strains ahead of their parent precisely so they resolve as themselves, which makes this reachable in normal play.
- Fix: add six entries to the dictionary mapping each sub-strain to its parent Color's value, or add a fallback in `For` that strips the suffix after the first underscore following the parent name and retries. The dictionary is simpler and keeps the sub-strain shades tunable.
- Depends on: none

### [MINOR] Field ref built in a static initialiser cannot fail gracefully

- File: `Source/RimRising/CasteRelationsPatches.cs`
- Location: lines 166-175, `RR_CasteUtility.PawnField` / `GetTrackerPawn`
- ID: RR-015
- Current:
  ```csharp
  private static readonly AccessTools.FieldRef<Pawn_RelationsTracker, Pawn> PawnField =
      AccessTools.FieldRefAccess<Pawn_RelationsTracker, Pawn>("pawn");

  public static Pawn GetTrackerPawn(Pawn_RelationsTracker tracker)
  {
      if (tracker == null) { return null; }
      try { return PawnField(tracker); }
      catch { return null; }
  }
  ```
- Problem: the field currently exists (`Verse.Pawn_RelationsTracker.pawn`, confirmed in IL), so this works today. But `FieldRefAccess` throws when the field is missing, and it runs in the static initialiser, before the `try`. A rename upstream would produce a `TypeInitializationException` on the first call to any member of `RR_CasteUtility`, which includes `CanRaiseHistoryEvent` used by three separate patches, and the `catch` would never see it.
- Fix: make `PawnField` lazily initialised inside `GetTrackerPawn` behind its own try/catch, caching both the delegate and a "failed" flag, so a missing field degrades to `null` instead of poisoning the type.
- Depends on: none

### [MINOR] Color gene cache is never invalidated

- File: `Source/RimRising/CasteIdentity.cs`
- Location: lines 46-64, `colorGenes` / `EnsureBuilt`
- ID: RR-016
- Current: `private static List<KeyValuePair<XenotypeDef, HashSet<GeneDef>>> colorGenes;` built once on first use and never cleared.
- Problem: the list holds `XenotypeDef` and `GeneDef` instances from `DefDatabase`. Any path that regenerates the def database in the same process (dev-mode def reload, the mod-settings-driven restart-free reload some frameworks perform) leaves this cache holding defs that are no longer the live instances, and every reference comparison in `ColorFromGenes` silently fails. The pawn then reads as no Color at all, which disables the razor lock, the armour lock, the title gates and the thought worker at once, with no error.
- Fix: add `public static void ResetCache() { colorGenes = null; }` and call it from a `[StaticConstructorOnStartup]` type or from `RimRisingMod.WriteSettings`, alongside the existing `VanillaSuppression.Apply()` call.
- Depends on: none

### [MINOR] `VanillaSuppression.Apply` dereferences settings without a null check

- File: `Source/RimRising/VanillaSuppression.cs`
- Location: line 121
- ID: RR-017
- Current:
  ```csharp
  RimRisingSettings s = RimRisingMod.Settings;
  ```
  followed immediately by `s.suppressVanillaXenotypes` on line 125.
- Problem: `RimRisingMod.Settings` is assigned in the `Mod` constructor, which `LoadedModManager.CreateModClasses` runs before static constructors on startup, so in practice it is non-null. If that constructor throws, for instance on a corrupt `RimRising.xml` settings file, `Settings` stays null and this static constructor throws an NRE that RimWorld reports without naming the real cause. `Recipe_CarveColor.AvailableOnNow` line 233 already guards the same property, so the codebase is inconsistent with itself.
- Fix: `if (s == null) { return; }` after line 121, matching the guard in `Recipe_CarveColor`.
- Depends on: none

### [MINOR] `IsColor` claims every def named `RR_*`

- File: `Source/RimRising/CasteIdentity.cs` line 68, duplicated in `Source/RimRising/CasteRelationsPatches.cs` line 189
- Location: `RR_CasteIdentity.IsColor` and `RR_CasteUtility.IsColor`
- ID: RR-018
- Current:
  ```csharp
  return x != null && x.defName != null && x.defName.StartsWith("RR_");
  ```
- Problem: `RR_` is a two-letter prefix with no namespace guarantee. Any other mod shipping an `XenotypeDef` whose defName starts `RR_` is silently enrolled in the Society's caste ladder, gets a `displayPriority`-derived rank in `ThoughtWorker_ColorRank`, and can satisfy or fail the razor and armour gates. `RR_CasteUtility.IsColor` is additionally dead code: nothing calls it, and `RR_CasteIdentity.IsColor` is the one actually used.
- Fix: replace the prefix test with membership in the mod's own xenotype set, built once from `DefDatabase<XenotypeDef>.AllDefs.Where(x => x.modContentPack?.PackageId == <this mod's packageId>)`, or with an explicit `DefModExtension` marker on the fifteen Color defs. Delete the unused copy in `CasteRelationsPatches.cs`.
- Depends on: RR-016 (both touch the same cache-building code)

### [MINOR] Role requirement label is hardcoded English

- File: `Source/RimRising/RoleRequirement_Xenotype.cs`
- Location: lines 164-180, `GetLabel`
- ID: RR-019
- Current:
  ```csharp
  return "Must be of a specific Color";
  ...
  return "Must be " + names;
  ```
- Problem: these strings bypass `Languages/English/Keyed/RimRising.xml` entirely, so they cannot be translated and will show in English in every locale. Every other user-facing string in the mod goes through `.Translate()`.
- Fix: add `RR_RoleRequirement_Color` and `RR_RoleRequirement_AnyColor` keys to `Languages/English/Keyed/RimRising.xml` and use `"RR_RoleRequirement_Color".Translate(names.Named("COLORS"))`.
- Depends on: none

### [MINOR] Two Harmony prefixes on `Pawn_RoyaltyTracker.SetTitle` with an order dependency

- File: `Source/RimRising/GoldTitlePatches.cs` line 27 and `Source/RimRising/CasteArmor.cs` line 260
- Location: `Patch_Pawn_RoyaltyTracker_SetTitle.Prefix` and `Patch_Pawn_RoyaltyTracker_SetServiceTitle.Prefix`
- ID: RR-020
- Current: both classes carry `[HarmonyPatch(typeof(Pawn_RoyaltyTracker), nameof(Pawn_RoyaltyTracker.SetTitle))]` and both declare a `bool Prefix` that can return `false`.
- Problem: Harmony skips the remaining prefixes once one returns `false`, and neither patch declares `[HarmonyPriority]` or `bool __runOriginal`, so which one gets to refuse first is decided by reflection ordering. The two conditions happen to be mutually exclusive today (one fires only for ruling caste, the other only for non-ruling caste), so behaviour is currently correct, but the arrangement is fragile and there is nothing in either file recording the dependency. Separately, the class in `CasteArmor.cs` is named `Patch_Pawn_RoyaltyTracker_SetServiceTitle` while the method it patches is `SetTitle`, which reads as a patch on a method that does not exist.
- Fix: merge both gates into a single prefix on `SetTitle` that inspects the title's tags once and decides, or add explicit `[HarmonyPriority]` to both. Rename the `CasteArmor.cs` class to `Patch_Pawn_RoyaltyTracker_SetTitle_ServiceLadder`.
- Depends on: RR-005 (same mechanism; do RR-005's design decision first)

### [MINOR] Blocking `SetTitle` silently swallows quest rewards

- File: `Source/RimRising/GoldTitlePatches.cs`
- Location: line 50, `return false;`
- ID: RR-021
- Current: the prefix shows a `Messages.Message` and returns `false`, skipping the original.
- Problem: `Pawn_RoyaltyTracker.SetTitle(Faction, RoyalTitleDef, bool grantRewards, bool rewardsOnlyForNewestTitle, bool sendLetter)` is called from quest reward chains and from `RoyalTitleUtility`. Callers do not check whether the title was actually applied. Refusing here leaves the quest believing it paid out, so the player loses the reward with only a `RejectInput` message to explain it. The message is at least shown, which is why this is MINOR rather than MAJOR.
- Fix: leave the refusal in place but make it visible in the right place: change the message type from `MessageTypeDefOf.RejectInput` to `MessageTypeDefOf.NegativeEvent` so it survives in the log, and add the faction name to the message so the player can see which reward was refused. A fuller fix is to gate the reward earlier, in the quest's `RoyalTitleDef` selection, which is a design change.
- Depends on: RR-005, RR-020

### [MINOR] `BiostatRangePatch` mutates a global tuning constant for the whole process

- File: `Source/RimRising/BiostatRangePatch.cs`
- Location: lines 59-95, static constructor
- ID: RR-022
- Current: reflection assignment of `GeneTuning.BiostatRange` to `new IntRange(-10, current.TrueMax)`.
- Problem: the mechanism is sound (`BiostatRange` is `public static initonly`, not `const`, so reads go through `ldsfld` and the reflection write is observed), and the file documents the blast radius honestly. The residual issue is that the change is unconditional and irreversible within the session: it is not tied to a mod setting the way `VanillaSuppression` is, and every other mod's xenogerm validation sees the new floor for as long as the game runs. There is no way for a player to opt out.
- Fix: add a `widenMetabolismFloor` bool to `RimRisingSettings`, default true, and read it here; move the assignment into a method that `RimRisingMod.WriteSettings` can call to restore the captured original, exactly as `VanillaSuppression.Apply` does.
- Depends on: none

### [MINOR] `RR_TribeBase` lists `Neolithic` twice

- File: `1.6/Defs/PawnKindDefs/PawnKinds_RimRising.xml`
- Location: lines 566-569
- ID: RR-023
- Current:
  ```xml
  <apparelTags>
    <li>Neolithic</li>
    <li>Neolithic</li>
  </apparelTags>
  ```
- Problem: harmless at runtime, since `PawnApparelGenerator` tests the tag list with `Contains`, but it is a copy-paste artifact and it will double once more if a child adds `Neolithic` again under RR-011.
- Fix: delete one of the two `<li>Neolithic</li>` lines.
- Depends on: RR-011 (same element)

### [MINOR] Build file hardcodes one machine's paths

- File: `Source/RimRising/RimRising.csproj`
- Location: lines 26-32
- ID: RR-024
- Current:
  ```xml
  <SteamLibrary>D:\SteamLibrary\steamapps</SteamLibrary>
  <HarmonyManaged>$(SteamLibrary)\workshop\content\294100\2009463077\Current\Assemblies</HarmonyManaged>
  ```
- Problem: the project only builds on a machine where the Steam library is `D:\SteamLibrary` and where Harmony is workshop item 2009463077. Anyone else, including a CI runner, gets missing-reference errors. The workshop id is also one of several Harmony redistributions; the mod list on this machine shows Harmony vendored under multiple ids.
- Fix: make `SteamLibrary` overridable, e.g. `<SteamLibrary Condition="'$(SteamLibrary)'==''">D:\SteamLibrary\steamapps</SteamLibrary>`, and add a `Directory.Build.props` or an environment-variable fallback so the path can be set without editing the csproj.
- Depends on: none

### [NOTE] packageId does not match the project brief

- File: `About/About.xml`
- Location: line 5
- ID: RR-025
- Current: `<packageId>cinergy92.rimrising</packageId>`
- Problem: the audit brief states the packageId is an earlier personal-name packageId. The Harmony instance id in `Source/RimRising/HarmonyPatches.cs` line 16 also uses `cinergy92.rimrising`. Only one of these can be right, and changing a published packageId breaks every existing save and every other mod's `loadAfter` entry.
- Fix: developer decision. If `cinergy92.rimrising` is the published id, correct the brief and leave both files alone. If the id must change, change `About.xml` line 5 and `HarmonyPatches.cs` line 16 together, and be aware that existing saves referencing the old id will warn.
- Depends on: none

### [NOTE] Three startup log lines plus one per carving

- File: `Source/RimRising/HarmonyPatches.cs` line 18, `Source/RimRising/VanillaSuppression.cs` lines 200-202, `Source/RimRising/BiostatRangePatch.cs` lines 87-89, `Source/RimRising/Recipe_CarveColor.cs` lines 294-297
- Location: as listed
- ID: RR-026
- Current: unconditional `Log.Message` calls.
- Problem: three lines at every startup and one per completed carving. Not harmful, but RimWorld's log is a shared resource and mods that write to it unconditionally make other mods' problems harder to find.
- Fix: guard them with `if (Prefs.DevMode)`, or drop the Harmony one entirely, which conveys nothing a player can act on.
- Depends on: none

### [NOTE] `modIconPath` is redundant

- File: `About/About.xml`
- Location: line 6
- ID: RR-027
- Current: `<modIconPath IgnoreIfNoMatchingField="True">UI/RimRisingModIcon</modIconPath>`
- Problem: `About/ModIcon.png` already exists on disk and is what RimWorld loads by convention. `ModMetaDataInternal.modIconPath` does exist in 1.6, so `IgnoreIfNoMatchingField` never triggers and simply adds noise.
- Fix: either drop the attribute or drop the element. Keeping both files is fine.
- Depends on: none

### [NOTE] Malformed whitespace in About.xml

- File: `About/About.xml`
- Location: line 33 area, and line 43 area
- ID: RR-028
- Current: `</li>    <li>` on a single line inside `modDependencies`, and `</royalTitleInheritanceWorkerClass>    <techLevel>` in `Factions_RimRising.xml` line 56.
- Problem: cosmetic only; both parse correctly.
- Fix: reflow.
- Depends on: none

### [NOTE] `Source/`, `Tools/` and `docs/` ship inside the mod folder

- File: mod root
- Location: `Source/`, `Tools/` (including `Tools/.cache/vanilla-defs.json`), `docs/`
- ID: RR-029
- Problem: RimWorld ignores them, but a Steam Workshop upload of this folder publishes them to every subscriber, including the cached vanilla def index. That is several megabytes of build artifacts in a content mod.
- Fix: add them to the Workshop upload exclusion, or move `Tools/` and `docs/` out of the mod root and keep only `Source/` if you want the source shipped deliberately.
- Depends on: none

### [NOTE] `Recipe_RepairScar` ties are resolved arbitrarily

- File: `Source/RimRising/CarverRestoration.cs`
- Location: lines 117-126, `WorstPermanentInjury`
- ID: RR-030
- Current:
  ```csharp
  if (h.Severity <= worstSeverity && worst != null) { continue; }
  ```
- Problem: with several permanent injuries at equal severity the first one enumerated wins, so which scar the surgery removes depends on hediff ordering rather than on anything the player can see or choose.
- Fix: break ties on `h.def.defName` or on the affected part's coverage, so the choice is at least stable across loads. Alternatively let the recipe target a body part and let the player pick.
- Depends on: none

### [NOTE] Trauma suite check phase is not saved

- File: `Source/RimRising/TraumaSuite.cs`
- Location: line 62, `ticksToCheck`; `PostExposeData` lines 74-79
- ID: RR-031
- Current: `ticksToCheck` is not scribed.
- Problem: after a load every worn trauma suit in the colony has `ticksToCheck == 0` and therefore evaluates on the same tick, then stays in phase. With one suit this is invisible; with a squad it puts all the stim checks on one tick every 60.
- Fix: initialise `ticksToCheck` to `Rand.Range(0, CheckIntervalTicks)` in `PostPostMake` and in `CompTick` when it is zero after a load, or scribe it.
- Depends on: none

### [NOTE] Xpath prefix style is inconsistent

- File: `1.6/Mods/CombatExtended/Patches/*.xml` and `1.6/Mods/Vehicles/Patches/CombatExtended.xml` versus `1.6/Patches/Carving_Human.xml`
- Location: all `<xpath>` elements
- ID: RR-032
- Current: the CE patch files use `Defs/ThingDef[...]`; `Carving_Human.xml` uses `/Defs/ThingDef[...]`.
- Problem: both forms work, since RimWorld evaluates against the document whose root is `<Defs>`. Purely a consistency issue.
- Fix: pick one form. `/Defs/...` is the more common convention and is harder to misread.
- Depends on: none

### [NOTE] `RR_XenotypeUtility` is a pass-through

- File: `Source/RimRising/HarmonyPatches.cs`
- Location: lines 103-112
- ID: RR-033
- Current: `RR_XenotypeUtility.IsRulingCaste` forwards straight to `RR_CasteIdentity.IsRulingCaste` with no added behaviour.
- Problem: an extra indirection that call sites in three files now go through. Harmless, but it means there are two names for one concept.
- Fix: optional. If kept, the doc comment should say it exists only as a compatibility shim for existing call sites.
- Depends on: none

### [NOTE] Unused sub-strain entries in the equality thought worker

- File: `Source/RimRising/ThoughtWorker_ColorRank.cs`
- Location: line 160, `xeno.displayPriority / 10f`
- ID: RR-034
- Current: the divisor `10f` is a bare literal here while the sibling class uses the named constant `PointsPerRung`.
- Problem: the two classes encode the same ladder scale in two places. A change to `PointsPerRung` silently desynchronises them.
- Fix: make `PointsPerRung` `internal const` on a shared type and use it in both.
- Depends on: none

### [NOTE] Storyteller portraits and biome textures are referenced through fields the validator does not cover

- File: `1.6/Defs/Storyteller/Storyteller_BQC.xml` lines 37-38, `1.6/Defs/BiomeDefs/Biomes_RimRising.xml` lines 28 and 101
- Location: `portraitLarge`, `portraitTiny`, `texture`
- ID: RR-035
- Problem: none found. All four files exist on disk (`UI/HeroArt/Storytellers/RR_BoardOfQualityControl.png`, `...Tiny.png`, `World/Biomes/RR_TerraformedSteppe.png`, `RR_HeliumBarrens.png`). Recorded here so a later reviewer does not re-derive it.
- Fix: none needed.
- Depends on: none

### [NOTE] Every translation key is used and every used key is defined

- File: `Languages/English/Keyed/RimRising.xml`
- Location: whole file
- ID: RR-036
- Problem: none. All 25 defined keys are referenced from C#; the two additional keys referenced (`MessageTransportPodsDestinationIsInvalid`, `TransportPodDestinationBeyondMaximumRange`) are vanilla. `RR_GravFlightArrived` is passed as a string literal to `TransportersArrivalAction_FormCaravan` in `GravLaunch.cs` line 215 rather than through `.Translate()`, which is correct for that constructor.
- Fix: none needed.
- Depends on: none

## Fix Order

Each batch leaves the mod loadable on its own.

**Batch 1: unresolved cross-references and merge bugs. Mechanical, no decisions.**
1. RR-002 (delete `AccelerationRate`)
2. RR-003 (delete the duplicate `comps` block on `RR_CarvelingVatBase`)
3. RR-001 (add `MayRequire="Aoba.Exosuit.Framework"` to the `RR_StarShellFrame` prerequisite, unless the decision below moves the def)
4. RR-006 (add the `Trader` pawn group maker to `RR_ObsidianTribes`)

**Batch 2: design decisions. Do not start these until someone has decided.**
5. RR-004 (which of the two goodwill defs survives): **needs a developer decision**
6. RR-005 (how the Gold and Service ladders are separated): **needs a developer decision**; changing `royalTitleTags` on a faction with existing saves will strip titles from saved pawns
7. RR-020, then RR-021 (both follow from whatever RR-005 decides)
8. RR-001 revisited if RR-005's answer is that starShell research should be unconditional: **needs a developer decision**

**Batch 3: XML inheritance and configuration.**
9. RR-009, RR-010 (recipeUsers `Inherit="False"`)
10. RR-011, then RR-023 (apparelTags `Inherit="False"`, then the duplicate `Neolithic` line)
11. RR-012 (real Vehicle Framework field names)
12. RR-007 (dead Ascomanni trader kinds)
13. RR-008 (research view coordinates)
14. RR-013 (drop `success Always` from the Human recipes patch)

**Batch 4: C# robustness. No def changes, so the mod stays loadable throughout.**
15. RR-017 (settings null guard)
16. RR-014 (sub-strain caste dyes)
17. RR-016, then RR-018 (cache reset, then the Color membership test)
18. RR-015 (lazy field ref)
19. RR-019 (translated role requirement label)
20. RR-022 (make the biostat floor a setting): **needs a developer decision** on whether the floor should be opt-out

**Batch 5: metadata and hygiene.**
21. RR-025 (packageId): **needs a developer decision**; do this before any Workshop publish or not at all
22. RR-024, RR-026, RR-027, RR-028, RR-029, RR-030, RR-031, RR-032, RR-033, RR-034

RR-035 and RR-036 require no action. They record checks that came back clean so a later reviewer does not repeat them.

## Cannot Verify

These could not be confirmed statically and are listed rather than guessed.

1. **Everything under `1.6/Mods/Exosuit/`.** The Aoba Exosuit Framework is not installed on this machine, so its assembly could not be decompiled. Specifically unverified: `Exosuit.CompProperties_ExosuitModule` (StarShell.xml lines 200, 248, 279, 316, 355, 405), `Exosuit.CompProperties_ModuleWeapon` (line 411) and `Exosuit.CompApparelForcedWeapon` (line 141) as type names; every field inside those comps; and whether `RR_StarShellFrame`'s own prerequisite `WG_HeavyExoskeleton` (StarShell.xml line 48) exists in that framework or in some other mod. If it does not, that is a second unresolved cross-reference of the same class as RR-001, inside a folder that is already correctly gated.
2. **Vehicle Framework's gizmo textures.** `UI/Gizmos/FireRate_Burst` and `UI/Gizmos/FireRate_Single` (Drachenjager.xml lines 121, 128, 173) are not in this mod's `Textures/` tree and Vehicle Framework's `Textures/` folder was not enumerated. They are conventional VF paths but their existence was not confirmed.
3. **Vanilla packed textures.** `Things/Projectile/Charge_Small` (Weapons_RimRising.xml lines 210, 368) is a vanilla asset shipped inside Unity asset bundles rather than as a loose file, so it could not be confirmed by a filesystem check.
4. **Whether `EquipmentUtility.CanEquip` is on the apparel wear path in 1.6.** `Patch_CanEquip_RestrictedArmor` (`CasteArmor.cs` line 223) reads `thing.def.apparel.tags` from inside a `CanEquip` postfix. The overload it targets exists and the patch is safe either way, but whether apparel actually reaches this method in 1.6, and therefore whether that half of the armour restriction fires at all, requires running the game.
5. **Runtime behaviour of the Drachenjaeger turret render offsets.** The `renderProperties` values in Drachenjager.xml lines 440-447 and 470-480 are derived from a stated convention. Only a screenshot can confirm the turrets sit where intended.
6. **Whether `CombatExtended.PatchOperationMakeGunCECompatible` succeeds.** Two of these appear in `1.6/Mods/CombatExtended/Patches/Weapons_RimRising.xml`. It is CE's own operation class with its own internal matching, which cannot be evaluated as an xpath. Its inputs look well formed; its outcome was not verified.
7. **Balance figures.** Every `naturalGoodwillOffset`, `commonality`, `baseCost`, stat base and score curve in this mod is a design choice. RR-004 is reported because two defs sum to a value that contradicts the file's own stated intent, not because -100 or -140 is wrong in itself. Nothing else in that class is assessed.
8. **Dependency mod def coverage.** Alpha Genes, EyeGenes2 and the EBSG family were only partly staged for inspection. All 1559 def references in this mod resolved against the vanilla index, the vanilla gene templates (`AptitudeStrong_*`, `AptitudePoor_*` and similar are generated at runtime by `GeneDefGenerator.ImpliedGeneDefs`, which is why they are not in any file), the staged dependency defs, and this mod's own defs, with the two exceptions reported as RR-001 and RR-002. It remains possible that a def which resolved against a partially staged mod would fail if that mod's LoadFolders gating excludes the file it lives in.
9. **Save compatibility of the fixes.** RR-005 in particular changes which `RoyalTitleDef`s a faction can award. Whether existing saves survive that was not modelled.
