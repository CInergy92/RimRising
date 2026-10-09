# RimRising review — 2026-10-08

**For:** the Opus session working in the live checkout. **From:** a read-only cloud session on commit `ea7105f` (`Pulse armour with greaves for [NL] Realistic Body`). **Nothing was modified.**

## Scope and method

- Every XML file under `1.6/` parsed and cross-referenced with a script: defName uniqueness, `ParentName` resolution, every `RR_*` reference resolved to a def, folder-gate crossings, `DefOf` fields vs defs, `Class=`/`workerClass`/`compClass` vs C# classes, every `RR_` texture/sound path on disk incl. worn body-type sets and Graphic_StackCount folders, Keyed strings vs `.Translate()` calls, `LoadFolders.xml` vs folders on disk.
- All 16 C# files and all def files read in full. Shipped `1.6/Assemblies/RimRising.dll` checked against source (every class name, method name and `RR_` string literal in source is present in the DLL — it is not stale).
- Melee Animation tweak data re-derived from the current sprites: razor axis 45.3° vs shipped 45.0, reaper 43.7° vs 43.5; far-end `t` matches `BladeEnd - OffX + 0.02` to three decimals on both. Tweak data is current.
- The prior `docs/RimRising-Audit.md` was checked item by item: **RR-001 through RR-024 are all fixed in the tree** (RR-005 by the C# favour-walk in `TitleLadders.cs` rather than by splitting the tags). Nothing below repeats it.

**What this session could not do:** no game install, no vanilla defs, no decompiler, no PowerShell, no dependency mods. Anything marked **PLAUSIBLE** is reasoned from the mod's own files plus memory of the 1.5/1.6 engine and must be confirmed against the decompiled dll or in play before editing. **CONFIRMED** means it follows from the files alone.

IDs here are `RV-nn` so they do not collide with the earlier audit's `RR-nn`.

## Summary

| Severity | Count | Needs a decision |
|---|---|---|
| MAJOR | 3 | RV-03 |
| MINOR | 12 | RV-06, RV-10 |
| NOTE | 9 | — |
| Clean checks recorded | 12 | — |

Plus a design section for the razor whip rework, which is the thing the user asked about and which touches RV-02.

### Status after the cloud session's own fixes (branch `review/2026-10-08`)

Fixed from the cloud, no game needed, all XML/text — **RV-01** (six CE armour blocks added; numbers are a first placement, judge them under CE), **RV-02** CE half only (whip projectile penetration patched to 9.5 mm; the rework itself is still open), **RV-04**, **RV-05** (kept the first weight, 3, in both lists), **RV-15**, **RV-17** (49/43 wording in CLAUDE.md, Carving.xml, XenotypeDefs; the C# comment in `Recipe_CarveColor.cs:343-345` is left for whoever next rebuilds the DLL), **RV-20** (all stale and garbled comments), plus the validator's own `.DESCRIPTION` header.

Still open, needing a build or the game: RV-03, RV-06, RV-07, RV-08, RV-09, RV-10, RV-11, RV-12, RV-13, RV-14, RV-16, RV-18, RV-19 and the whip rework. No `.cs` file was touched, so `1.6/Assemblies/RimRising.dll` still matches `Source/`.

### Status after the live session (master, 2026-10-08)

Merged the branch. Verified against vanilla defs, the decompiled game and in game:

| ID | Outcome |
|---|---|
| RV-01 | Fable's six blocks kept (every xpath resolves). Added validator check `CEArmorUnpatched`, negative-tested. CE's flak vest is stuff-scaled, not a flat 10/20. |
| RV-03 | **Confirmed in game** (`rrtestmode=kinds`): 0/10 knights in plate. Fixed with option (a), `titleRequired RR_Title_Praetorian`. That exposed a worse bug: neither royal faction had `royalTitleInheritanceRelations`, so **every Society title grant threw** in `RoyalTitleInheritanceWorker.FindHeir`. Fixed; validator check `RoyalFactionNoInheritance`. Also the plate rule now accepts sub-strains (Stained, Lurcher). After: 9/10 knights in plate, all titled. |
| RV-07 | Fixed with the Sterilized mechanism (hediff `tags` + recipe `incompatibleWithHediffTags`). |
| RV-08 | Kit moved to `Manufactured`. |
| RV-09 | Confirmed (`BaseMeleeWeapon_Sharp_Quality` carries the art comp). Restated on both razors. |
| RV-12, RV-14, RV-19, RV-17 (C#) | Fixed. RV-14 uses `IdeoUtility.DoerWillingToDo`, Colour carves only. RV-19 uses vanilla `ToCommaListOr`. |
| RV-13 | **No change needed.** Decompiled: destroying worn apparel → `ThingOwner.Remove` → `Notify_ApparelRemoved` → comps' `Notify_Unequipped`. |
| Whip rework | Done with the conservative defaults (one target, dodgeable, 45-tick stagger, 15 s cooldown, line of sight kept). `RazorLash.cs`, `RR_Fleck_RazorLash`, `RR_RazorLash` DamageDef (gives CE a blunt AP for deflected lashes instead of its 50 fallback), lash tools removed, bullet deleted. Tested with `rrtestmode=whip` under CE. |

**New finding:** the Reaper's razor also carries `UltratechMelee`, so Society Golds and Bronzies generate holding it (seen in the kinds run). This belongs with RV-10.

User's decisions, applied and checked in game (`rrtestmode=kinds`, 30 per kind):

- **Reaper's razor is Rising-only:** `UltratechMelee` removed, leaving `RR_RisingWeapon`. Society pawns holding it: 0.
- **RV-06, zoladone builds tolerance:** wired the way vanilla alcohol is (second GiveHediff doer at 0.032 plus `toleranceHediff` on the ChemicalDef).
- **RV-11, pulse armour has a real pulseShield that blocks no guns:** `CompProperties_Shield` with `blocksRangedWeapons false`, energy 1.0 / 0.13. In game, a charge-rifle Praetor and a pulseFist Bronzie in pulse armour may both fire.
- **Whip defaults kept.**

Plate rate at 30 samples: knights 18/30, Praetors 14/30, Bronzies 23/30. The earlier 10-sample swings were noise.

Still open: RV-10 for the ordinary razor (Society Obsidian Knights can generate holding one, which triggers the "lesser Color bore a razor" thought). Not done: RV-16 (starShell in game), RV-18 (cosmetic).

---

## MAJOR

### RV-01 Combat Extended apparel patch covers three of nine armour pieces — CONFIRMED

- File: `1.6/Mods/CombatExtended/Patches/Apparel_RimRising.xml`
- Patched: `RR_Apparel_PulseArmor`, `RR_Apparel_DemonHelm`, `RR_Apparel_ScarabSkin`.
- **Not patched:** `RR_Apparel_RecoilArmor` (vanilla Sharp 0.92), `RR_Apparel_DuroArmor` (0.42), `RR_Apparel_Aegis`, `RR_Apparel_GhostCloak` (0.10), `RR_Apparel_GravBoots` (0.35), `RR_Apparel_SkipBoots` (0.22), and the three StarShell modules (gated on Exosuit, so only when both are active).
- Problem: CE reads `ArmorRating_Sharp` as millimetres. RecoilArmor — the Society's elite suit, "just under the razor's penetration" in the vanilla numbers — stops **0.92 mm** under CE, i.e. nothing; duroArmor stops 0.42 mm. None of the six has `Bulk`/`WornBulk`, so they weigh nothing to carry. This is the same class of fault as the Reaper's-razor crash recorded in CLAUDE.md: these defs were added after the CE file was written and nobody came back to it. README claims "CE stats for every weapon, armour piece and turret".
- Fix: add `PatchOperationReplace` blocks for Sharp/Blunt/Mass and `PatchOperationAdd` for `Bulk`/`WornBulk` on the six, scaled against the existing ones (pulse 24/52, scarab 8/14, marine armour 20/45). Suggested anchors: recoil ~18–20 sharp (one step under pulse, "a razor still wins"), duro ~10, ghostCloak ~2, boots ~4. Then extend `Tools/Test-ModDefs.ps1` with a `CEArmorUnpatched` check mirroring `CEToolsUnpatched`: any def with `ArmorRating_Sharp` in `statBases` and no `PatchOperationReplace` on that stat in the CE folder fails.
- Depends on: none.

### RV-02 Whip projectile is unpatched for CE and misses the point of the weapon — CONFIRMED (CE part), design (rest)

- Files: `1.6/Defs/ThingDefs_Misc/Weapons_RimRising.xml:231-282`; nothing in `1.6/Mods/CombatExtended/` names `RR_RazorWhip` or `RR_Bullet_RazorLash`.
- Problem: `RR_Bullet_RazorLash` has `armorPenetrationBase 0.75`. Under CE that is 0.75 mm, so the lash cannot get through a flak vest, while the `lash` `ToolCE` on the same weapon has `armorPenetrationSharp 9.50`. Separately, the whip is represented **twice**: as a 1-cell random melee tool (`lash`, lines 124-133 / 583-591, power 20, AP 0.6) that dilutes the razor's blade swings ~20% of the time, and as a ranged projectile ability. The description promises "reach around cover" and "cannot simply be parried"; the ability has `requireLineOfSight true` and a `Bullet`.
- Fix: see **Whip rework** below. The minimum CE fix if the rework is deferred is a `PatchOperationReplace` on `RR_Bullet_RazorLash/projectile/armorPenetrationBase` to ~9.5 in the CE folder.

### RV-03 Society Obsidian Knights probably cannot generate in heavy plate — PLAUSIBLE, needs an in-game check

- Files: `Source/RimRising/CasteArmor.cs:519-531` (`Patch_ApparelProperties_PawnCanWear`), `1.6/Defs/PawnKindDefs/PawnKinds_RimRising.xml:126-153` (`RR_Society_Obsidian_Knight`, `apparelTags RR_HeavyPlate`, comment "this kind IS the Praetorian case"), `1.6/Defs/PreceptDefs/Memes_RimRising.xml:117-119` (`RR_ArmorBearing_Restricted` is `requireOne` for every hierarchy ideoligion).
- Reasoning: `PawnGenerator` assigns the faction's ideoligion before `GenerateGearFor` (apparel generation reads `Ideo` for required apparel), so a generated Society Obsidian already holds `RR_ArmorBearing_Restricted` when plate is chosen. `MayWearRestricted` returns false for an Obsidian with no `RR_PlateBearer` title, and generated pawns have no titles. Either `PawnApparelGenerator.CanUsePair` filters the suit out, or `Pawn_ApparelTracker.Wear` refuses it and logs `tried to wear … but is not allowed to` — `TestScene.cs:318-322` records exactly that message from this patch. Either way the knight spawns in `IndustrialBasic` clothing. PROGRESS §"Generation is separate from wearing" says the restriction "governs equipping", but `Wear()` is the equipping path generation ends on. The same applies to `RR_Julii_Enforcer` / `RR_Sun_Security` if their faction's ideoligion happens to hold the precept (Julii's does not require the meme; Sun's cannot).
- Verify: dev mode → Spawn pawn → `RR_Society_Obsidian_Knight` for the Society faction, ten times. Check apparel and `Player.log` for "tried to wear". Also spawn a Society raid and look at the knights.
- Fix options (decision): (a) make the kind actually hold the title it is described as holding — `PawnKindDef` has Royalty fields for this (`titleRequired` / `royalTitleChance`; verify field names against `Royalty/Defs/PawnKindDefs/PawnKinds_Empire.xml`) → `RR_Title_Praetorian`, which is lore-correct and also makes `HasSocietyTitle` true; or (b) exempt generation in the postfix: `if (PawnGenerator.IsBeingGenerated(pawn)) return;`. (a) is better: it makes the "trusted Obsidian" visible as a title in the UI. Note the PawnKinds header still says Royalty fields are "deliberately not used - Royalty is not a dependency", which is stale (RV-20).

---

## MINOR

### RV-04 Carver's kit description says Carvers are Yellows; everything else says Violets — CONFIRMED

- File: `1.6/Defs/Carving/Carving.xml:62` — "Carvers are Yellows. The caste that makes the hierarchy transgressable is a midColor…"
- Contradicts `Restoration.xml:492-496` ("CARVERS ARE VIOLETS, NOT YELLOWS"), `CarverRestoration.cs:162-172` (the bill gate rejects everyone but `RR_Violet`), `docs/DESIGN.md:235`. Player-facing text.
- Fix: rewrite the sentence for Violet ("The caste that makes the hierarchy transgressable is the one engineered for art, which the Society has never found as funny as it is.").

### RV-05 `RR_Society_Copper_Official` listed twice in two Peaceful group makers — CONFIRMED

- Files: `1.6/Defs/FactionDefs/Factions_RimRising.xml:173-174` (weights 3 and 6) and `:371-372` (3 and 5).
- `pawnGroupMaker/options` is a list, so both entries load and the official's effective weight is 9 / 8 — more than the servant or the labourer, which the comment two lines up says should dominate. Copy-paste residue.
- Fix: delete one line in each; keep whichever weight was intended (probably the smaller one, matching Julii's 5).

### RV-06 Zoladone's tolerance hediff is never applied — PLAUSIBLE

- File: `1.6/Defs/ThingDefs_Items/Drugs_RimRising.xml:155-161` (ChemicalDef), `:68-74` (outcome doers), `:238-265` (`RR_ZoladoneTolerance`).
- Vanilla builds tolerance through a **second** `IngestionOutcomeDoer_GiveHediff` on the drug (`GoJuiceTolerance`, severity ~0.032, `divideByBodySize`), and the ChemicalDef names it in `<toleranceHediff>`. Zoladone has neither, so `RR_ZoladoneTolerance` (with its `HediffCompProperties_DrugEffectFactor` and the brain-damage giver) is a dead def and the high never weakens with use.
- Verify against `Core/Defs/ThingDefs_Items/Items_Drug_GoJuice.xml` and `Core/Defs/ChemicalDefs`.
- Fix: add the tolerance outcome doer and `<toleranceHediff>RR_ZoladoneTolerance</toleranceHediff>` (plus `onGeneratedAddictedToleranceHediff` if GoJuice has it). Decision: whether zoladone *should* build tolerance; the file's own comment ("highly addictive… severe withdrawal") suggests yes.

### RV-07 `RR_CarveReproduction` can be performed repeatedly on the same pawn — PLAUSIBLE

- File: `1.6/Defs/Carving/Restoration.xml:685-737`; hediff `:672-683`.
- `Recipe_AddHediff` has no "already has it" guard. `incompatibleWithHediffTags` lists only `Sterilized`, and `RR_CrossColorFertility` carries no tags, so the surgery stays on the list after it is done. Each repeat burns a Carver's kit (1400 silver) and stacks another identical hediff.
- Fix: give the hediff `<tags><li>RR_CarvedFertility</li></tags>` and add `<li>RR_CarvedFertility</li>` to the recipe's `incompatibleWithHediffTags` — the same mechanism vanilla's `Sterilize` uses (verify the HediffDef field name `tags` against `Sterilized` in `Core/Defs/HediffDefs/Hediffs_Global_Misc.xml`).

### RV-08 Carver's kit sits in the `Medicine` category and matches the surgeries' medicine ingredient — PLAUSIBLE

- File: `1.6/Defs/Carving/Carving.xml:74-76` (kit `thingCategories Medicine`), `:168-193` (`RR_CarveBase` ingredients: 1 kit + 6 of category `Medicine`; `fixedIngredientFilter` allows both).
- The kit has no `MedicalPotency`, so it is not `IsMedicine`, but the second ingredient's filter is the *category*, which the kit is in. When kits are closer to the table than medicine, the bill's ingredient search can fill "6 medicine" with six more kits. The bill UI also shows the kit as a toggle under medicine.
- Fix: either move the kit to a category of its own / `Manufactured`, or add `<disallowedThingDefs><li>RR_CarvingKit</li></disallowedThingDefs>` to the medicine ingredient's `<filter>` in `RR_CarveBase` (and the equivalent in `RR_RestoreBase` recipes, which use resFlesh explicitly and are fine). Verify by placing seven kits and no medicine next to a hospital bed and queuing a carve.

### RV-09 Razors lose `CompProperties_Art` through `comps Inherit="False"` — PLAUSIBLE

- File: `1.6/Defs/ThingDefs_Misc/Weapons_RimRising.xml:69-79` and `:532-542`.
- The comment restates what `BaseWeapon` supplies (Forbiddable, Equippable, Styleable) and re-adds `CompQuality` from `BaseMeleeWeapon`, but vanilla's `BaseMeleeWeapon` also carries `CompProperties_Art` (`NamerArtWeaponMelee` / `ArtDescription_WeaponMelee`, `minQualityForArtistic Excellent`). Without it a masterwork razor never gets a name or an art description, unlike every other melee weapon.
- Verify by grepping the vanilla Defs for `Name="BaseMeleeWeapon"`. If confirmed, copy the art comp into both razors' comps blocks.

### RV-10 The razor carries vanilla `UltratechMelee`, so non-Gold kinds generate holding it — CONFIRMED (tags), decision on fix

- File: `Weapons_RimRising.xml:82-86`. Kinds with `UltratechMelee` and enough `weaponMoney` (razor MarketValue 2600): `RR_Society_Obsidian_Knight` (1200–2600), `RR_Ascomanni_Warlord` (1600–3200), `RR_Ares_Obsidian_Freed` (800–2000, no), every vanilla Empire kind with the tag, and other mods' kinds.
- `PawnWeaponGenerator` does not consult `EquipmentUtility.CanEquip`, so a Society Obsidian Knight can arrive carrying the one object the Society kills lowColors for touching, and `Patch_Pawn_EquipmentTracker_AddEquipment` fires `RR_LowColorBoreRazor` for it during the raid (the worldgen guard does not apply to raids), handing every hierarchy-believing colonist "a lesser Color bore a razor" −8 ×5 stacks.
- Fix: replace `UltratechMelee` on `RR_Weapon_Razor` with a mod-owned tag (e.g. `RR_RazorBearer`) and add that tag to `RR_Society_Gold_Praetor`, `RR_Society_Bronzie_Officer`, `RR_Society_OlympicKnight`, `RR_Ares_Gold_Turncoat`. Decide whether Ascomanni warlords with looted razors are wanted (lore says maybe; then give the warlord the tag too). The reaper already uses `RR_RisingWeapon` this way. Weapon *classes* (`Ultratech`, used by the meme's `preferredWeaponClasses`) are unaffected.

### RV-11 Pulse armour promises a shield it does not have — CONFIRMED

- File: `1.6/Defs/ThingDefs_Misc/Apparel_RimRising.xml:24` (description: "will overheat if the shield takes sustained punishment"), `:9` (file comment: "recoilArmor plus a shield generator plus servo assistance"), research description `Research_RimRising.xml:94` ("a shield generator carried on the back").
- The def's comps are `CompColorable` and the trauma suite only. There is no `CompProperties_Shield`. The aegis note in `Weapons_RimRising.xml:388-405` explains why a shield comp is awkward (it blocks ranged weapon use — which would forbid the pulseFist the description says it is synched to).
- Fix (decision): either drop the shield from the three texts, or add a small `CompProperties_Shield` and accept the no-ranged rule. The texts are the cheaper fix and keep the pulseFist synergy.

### RV-12 `Recipe_CarveColor.ApplyOnPawn` calls `CheckSurgeryFail` without a null `billDoer` guard — CONFIRMED

- File: `Source/RimRising/Recipe_CarveColor.cs:407` vs `CarverRestoration.cs:209` and `:269`, which both write `if (billDoer != null && CheckSurgeryFail(...))`.
- Vanilla's own recipes guard it because dev-mode "apply surgery" and some quest paths pass null. Match the other two.

### RV-13 Trauma-suite seal can outlive a suit destroyed while worn — PLAUSIBLE

- File: `Source/RimRising/TraumaSuite.cs:333-337`, `:377-389`.
- The seal is removed in `Notify_Unequipped`. If a worn suit is destroyed by damage, `Pawn_ApparelTracker` removes it through its own destroy path; whether that calls `Notify_Unequipped` on comps needs checking. If not, the pawn keeps `totalBleedFactor 0.15` forever with no suit, and nothing ticks to reconcile because the comp is gone.
- Fix: override `PostDestroy(DestroyMode, Map)` in `CompTraumaSuite` and call `RemoveSeal(Wearer)` (capture the wearer before `base`). Cheap, and correct whichever way the engine behaves.

### RV-14 `PreceptComp_UnwillingToDo` on carving/razor precepts is never consulted — PLAUSIBLE

- Files: `Carving.xml:250-253` (`RR_Carving_Abomination`: "Carve someone into another Color"), `Precepts_RazorBearing.xml:350-353`, `Precepts_InterColorUnion.xml:701-704`.
- `UnwillingToDo` only does something where code asks `IdeoUtility.DoerWillingToDo` / `HistoryEvent.DoerWillingToDo()` before the act. Nothing in this mod asks. So a Society Violet whose ideoligion lists "Won't: carve someone into another Color" carves without complaint, while the UI says they refuse. The razor case is covered by the `CanEquip` patch, and the union case is unblockable, so those two comps are harmless UI text; the carving one is an actual contradiction.
- Fix: in `Bill_PawnAllowedToStartAnew_CarverOnly` (`CarverRestoration.cs:164-172`), after the Violet check, for recipes carrying `CarveTargetExtension`: `if (!new HistoryEvent(RR_CarveDefOf.RR_ColorCarved, p.Named(HistoryEventArgsNames.Doer)).DoerWillingToDo()) __result = false;` (verify the extension method exists on `HistoryEvent` in 1.6; it is in `IdeoUtility`).

### RV-15 About.xml / README counts are wrong — CONFIRMED

- `About/About.xml:11`: "Six factions, two ideoligion memes" — there are **seven** `FactionDef`s (five in `Factions_RimRising.xml` + Julii + Sun; the faction file's own comment says "all seven of ours") and **three** memes (`RR_ColorHierarchy`, `RR_GoldWorship`, `RR_ColorEquality`).
- `README.md`: "six factions", "two scenarios" (there are three — `RR_Scenario_Rising`), "CE stats for every weapon, armour piece and turret" (see RV-01), "All tooling is PowerShell 7" (three Python/Blender tools).
- About.xml is the Workshop page. Fix the numbers.

---

## NOTE

### RV-16 StarShell worn sprites are not body-typed — checker flag, framework convention unverified

- `Textures/Things/Pawn/Humanlike/Apparel/RR_StarShell/` holds `_north/_east/_south` only; the checker expected `_Male_north` etc. The Exosuit framework's `ModuleApparel*` abstracts probably draw modules without body types (the file's header mentions the framework's "no-gender extension"). CLAUDE.md already lists starShell alignment as the one unverified sprite. Confirm in game with the framework active; if the framework does want body-typed names, this is a missing-texture error at wear time, not at load.

### RV-17 Gold's complexity is quoted as 49, 47 and 43 in different places

- CLAUDE.md ("Gold at complexity 49", "22 gene processors"), `Carving.xml:9`, `Recipe_CarveColor.cs:343-345`, `XenotypeDefs_Colors.xml:42-44` ("four archite capsules") all assume `EBSG_ArchiteWoundHealing` is present; `XenotypeDefs_Colors.xml:118` says "true Gold's 47 and 4"; PROGRESS §"fourth false green" records that on the current profile the gene does not exist and Gold is **cpx 43, arc 2**. The `MayRequireAnyOf` on line 98 is deliberate and correct. Pick one number and say it depends on the two optional mods.

### RV-18 Carved pawns keep the Baseliner icon

- `Recipe_CarveColor.cs:426` sets `xenotypeName` but not `pawn.genes.iconDef`, so the colonist bar shows a generic icon under the name "Gold". Vanilla's xenogerm sets `iconDef`. There is no `XenotypeIconDef` per Color to point at; adding fifteen (one per `UI/Icons/Xenotypes/RR_*` glyph) would close the gap. Cosmetic.

### RV-19 `string.Join(" or ", …)` in `RoleRequirement_Xenotype.GetLabel` is untranslated

- `Source/RimRising/RoleRequirement_Xenotype.cs:549`. The rest of the string went through Keyed in the last pass; the conjunction did not. Trivial.

### RV-20 Stale comments that now say the opposite of the code

- `Factions_RimRising.xml:6-7` and `PawnKinds_RimRising.xml:5-7`, `:20-21`: "Royalty is not a dependency", "Milestone 4 adds equipment; these will be revisited" — Royalty is required and the kinds use its tags.
- `RoyalTitles_Gold.xml:195-198`: "NOT GATED TO GOLD YET" — gated in `GoldTitlePatches.cs` and `TitleLadders.cs`.
- `Apparel_RimRising.xml:496-503`: "stopping bleeding literally would need C#" — `TraumaSuite.cs` does exactly that now.
- `Implants_RimRising.xml:803-804`, `Weapons_RimRising.xml:9-18`: "no Royalty dependency at Milestone 4", "razor becomes a persona weapon then", "caste restriction… belongs in Milestone 5" — all superseded.
- Garbled comment fragments from a scripted edit: `PawnKinds_RimRising.xml:593`, `:619`, `:656`, `:683` are four pieces of one sentence; `Apparel_RimRising.xml:195-196` and `:650-651` likewise.
- `RR_TribeBase` is referenced by the PawnKinds header as not using Royalty fields; harmless.

### RV-21 `TestScene` is a live `MapComponent` on every map

- `MapComponent_RR_TestScene` is instantiated for every map in normal play (that is how MapComponents work) and returns on the first line of `MapComponentUpdate`. Cost is one bool check per frame per map, and it scribes nothing. Fine; recorded so nobody wonders why it is in saves' component lists.

### RV-22 Projectile/weapon texture path convention differs for the pulse cannon

- `StarShell.xml:71` uses `Things/Weapons/RR_PulseCannon`; every other weapon is under `Things/Item/Equipment/Weapon{Melee,Ranged}/`. Works; inconsistent.

### RV-23 `RR_Ascomanni.permanentEnemyToEveryoneExcept` lists itself

- `Factions_RimRising.xml:734-736`. A faction is never hostile to itself, so the entry is a no-op; presumably there to keep the list non-empty. Harmless.

### RV-24 Society-prefixed kinds inside the resistance's group makers

- `RR_SonsOfAres` uses `RR_Society_Silver_Factor` as its trader and `RR_Society_Brown_Servant` in its peaceful group (`Factions_RimRising.xml:503`, `:519`). Mechanically fine (faction comes from the group). Lore: the Rising's merchant is a Silver factor "of the Society". If that bothers anyone, clone the kind under an `RR_Ares_` name.

---

## Clean — checked, no action, recorded so it is not re-derived

1. 249 defs, 13 abstracts, 0 duplicate defNames within a type, every `RR_` reference resolves (the only unresolved strings are `categoryTag` free text).
2. No cross-gate references: nothing in `1.6/Defs` reaches into `1.6/Mods/*`; the one inter-gate reference (`RR_DrachenjagerFrame` → `RR_StarShellFrame`) carries the right `MayRequire`.
3. All five `[DefOf]` classes resolve, none points at a gated def.
4. All 13 C# classes named from XML exist; no XML names a class that is missing.
5. All 33 Keyed strings are used from C#; every `.Translate()` key exists. The one `labelKey` not in Keyed (`RoleRequirementLabelSameIdeo`) is vanilla's.
6. Every `RR_` texture resolves: 15 worn sprites per body-typed garment, 3 per helmet, `_m` masks present for all 15 pulse and recoil sprites plus the item icons, `Graphic_StackCount` folders hold `_a/_b/_c`, vehicle body 768×1024 / 1024×768 and turrets 512×512 (128 px per drawSize unit), biome textures, storyteller portraits 580×620 / 116×124, `Preview.png` 640×360 under 1 MB.
7. `Sounds/Weapon/RR_RazorLash.mp3` exists for the one SoundDef.
8. `LoadFolders.xml` lists exactly the folders that exist, RealisticBody last.
9. `RimRising.dll` contains every type, method and `RR_` literal in `Source/` — not stale.
10. WeaponTweakData matches the current razor sprites (see Method).
11. The two Harmony postfixes on `EquipmentUtility.CanEquip` and the single prefix on `SetTitle` are consistent; the favour-walk patches degrade to vanilla on a missing member and `Prepare()` guards the private target.
12. Earlier audit items RR-001..RR-024 are all resolved in the tree; RR-025..RR-036 were notes.

---

## Whip rework — making the razor's whip form behave like a whip

The user wants the whip to stop being a projectile. This section is the plan for that. It replaces RV-02.

### What exists today

| Piece | Where |
|---|---|
| `AbilityDef RR_RazorWhip` — `Verb_CastAbility`, range 7.9, warmup 0.6, LOS required, `aiCanUse`, cooldown 900, `CompProperties_AbilityLaunchProjectile` | `Weapons_RimRising.xml:231-263` |
| `ThingDef RR_Bullet_RazorLash` — Cut 19, AP 0.75, speed 55 | `Weapons_RimRising.xml:265-282` |
| `CompProperties_EquippableAbility` on both razors | `:69-72`, `:532-535` |
| `lash` melee tool on both razors (Cut 20, AP 0.6, 1.4 s) | `:124-133`, `:583-591` |
| `lash` `ToolCE` on both razors under CE (28 / 9.5 mm; 26 / 9.0 mm) | `1.6/Mods/CombatExtended/Patches/Weapons_RimRising.xml:59-73`, `:217-227` |
| `SoundDef RR_RazorLash` + mp3 | `Sounds_RimRising.xml`, `Sounds/Weapon/` |
| Ability icon 128² and lash sprite 64² | `Textures/UI/Abilities/RR_RazorWhip.png`, `Textures/Things/Projectile/RR_RazorLash.png`, drawn by `Tools/Draw-Weapons.py` (`whip_icon`, `lash_projectile`) |
| No CE patch for the ability or the projectile | — |

### Why the projectile reads wrong

- `CompAbilityEffect_LaunchProjectile` spawns a `Bullet` that travels at `speed` and resolves like a shot: it can be blocked by whatever is between the pawns, it is affected by nothing the wielder is good at (melee skill, weapon quality, `MeleeDamageFactor`, `MeleeHitChance`), and it cannot be dodged with `MeleeDodgeChance`. A Gold with Melee 19 and a Gold with Melee 3 lash identically.
- The description promises reach around cover; `requireLineOfSight true` plus a bullet gives the opposite.
- Under CE it does 0.75 mm of penetration (RV-02).
- A second, unrelated "lash" lives in `<tools>` at 1 cell, so the weapon has two whips.

### Proposed shape (option 2 from the chat, refined)

Keep `RR_RazorWhip` as the equipment ability — the gizmo, the icon, the cooldown and the sound already work — and swap the projectile comp for a custom melee-sweep effect:

**New C#** (`Source/RimRising/RazorLash.cs`):

```csharp
public class CompProperties_AbilityRazorLash : CompProperties_AbilityEffect
{
    public float damage = 19f;
    public float armorPenetration = 0.75f;   // vanilla units; CE folder patches this to ~9.5
    public DamageDef damageDef;             // Cut
    public bool sweepAll = false;           // true: hit every pawn on the line, not just the first
    public bool ignoreDodge = false;        // "cannot simply be parried"
    public int staggerTicks = 45;
    public FleckDef lineFleck;              // RR_Fleck_RazorLash, reusing the 64px lash sprite
    public CompProperties_AbilityRazorLash() { compClass = typeof(CompAbilityEffect_RazorLash); }
}

public class CompAbilityEffect_RazorLash : CompAbilityEffect
{
    public new CompProperties_AbilityRazorLash Props => (CompProperties_AbilityRazorLash)props;

    public override void Apply(LocalTargetInfo target, LocalTargetInfo dest)
    {
        Pawn caster = parent.pawn;
        Map map = caster.Map;
        ThingWithComps razor = caster.equipment?.Primary;   // the thing carrying CompEquippableAbility
        foreach (IntVec3 cell in GenSight.PointsOnLineOfSight(caster.Position, target.Cell))
        {
            Pawn victim = cell.GetFirstPawn(map);
            if (victim == null || victim == caster) continue;
            Lash(caster, razor, victim);
            if (!Props.sweepAll) break;
        }
        if (Props.lineFleck != null)
            FleckMaker.ConnectingLine(caster.DrawPos, target.CenterVector3, Props.lineFleck, map); // verify signature
    }

    private void Lash(Pawn caster, ThingWithComps razor, Pawn victim)
    {
        float hit = caster.GetStatValue(StatDefOf.MeleeHitChance);
        float dodge = Props.ignoreDodge ? 0f : victim.GetStatValue(StatDefOf.MeleeDodgeChance);
        if (!Rand.Chance(hit) || Rand.Chance(dodge)) { /* miss/dodge motes, battle log */ return; }
        float dmg = Props.damage
                  * caster.GetStatValue(StatDefOf.MeleeDamageFactor)
                  * (razor?.GetStatValue(StatDefOf.MeleeWeapon_DamageMultiplier) ?? 1f);  // quality
        var dinfo = new DamageInfo(Props.damageDef ?? DamageDefOf.Cut, dmg, Props.armorPenetration,
                                   (victim.Position - caster.Position).AngleFlat, caster, null, razor?.def);
        victim.TakeDamage(dinfo);
        if (Props.staggerTicks > 0) victim.stances?.stagger.StaggerFor(Props.staggerTicks);
        // Battle log: Find.BattleLog.Add(new BattleLogEntry_MeleeCombat(...)) is optional; the TakeDamage
        // call already produces a damage log line.
    }

    public override bool Valid(LocalTargetInfo target, bool throwMessages = false)
        => target.HasThing && target.Thing is Pawn;
}
```

Names to verify by decompile before trusting: `FleckMaker.ConnectingLine` (exists in 1.3+ for the psycast lines; check the parameter list), `StaggerHandler.StaggerFor(int)`, `StatDefOf.MeleeWeapon_DamageMultiplier`, `Pawn_StanceTracker.stagger`. Everything else is `Verb_MeleeAttackDamage` vocabulary.

**XML changes:**

1. `Weapons_RimRising.xml`: in `RR_RazorWhip` replace the `CompProperties_AbilityLaunchProjectile` comp with `<li Class="RimRising.CompProperties_AbilityRazorLash"><damage>19</damage><armorPenetration>0.75</armorPenetration><damageDef>Cut</damageDef><lineFleck>RR_Fleck_RazorLash</lineFleck></li>`. Set `requireLineOfSight` to **false** if "reach around cover" is wanted (the line walk still stops at the first pawn); keep `canTargetPawns true`, `aiCanUse true`. Consider `cooldownTicksRange 600` — the description says the whip "opens a fight", so a shorter cooldown than 15 s may read better; decision.
2. Delete `RR_Bullet_RazorLash`. Keep the texture: add a `FleckDef RR_Fleck_RazorLash` (`graphicData texPath Things/Projectile/RR_RazorLash`, `solidTime 0.08`, `fadeOutTime 0.15`, `shaderType MoteGlow`, mirrored from a vanilla line fleck such as the psycast skip line) in a new `1.6/Defs/FleckDefs/Flecks_RimRising.xml`.
3. Remove the `lash` tool from both razors (vanilla) **and** both `ToolCE` lists in the CE patch, so the blade swings are the blade and the whip is the ability. Melee Animation tweak data is unaffected (it describes the sprite, not the tools); `Test-ModDefs.ps1`'s `CEToolsUnpatched` is unaffected.
4. CE folder: `PatchOperationReplace` on `Defs/AbilityDef[defName="RR_RazorWhip"]/comps/li[@Class="RimRising.CompProperties_AbilityRazorLash"]/armorPenetration` → `9.5` (the value the removed `ToolCE` used). This keeps the C# CE-agnostic; CE's armour patch reads `DamageInfo.ArmorPenetrationInt` in millimetres, so the number simply has to be in CE units when CE is active.
5. `Tools/Draw-Weapons.py`: the docstring and the output map still say "lash projectile"; rename to the fleck in comments only, the file is reused.
6. `docs/PROGRESS.md`: a short entry; `About.xml` text is already generic ("razors").

**Decisions for the user:** `sweepAll` (one target or everyone on the line), `ignoreDodge` (canon says it cannot be parried; mechanically this is strong), cooldown length, and whether to add a disarm/yank. Yank is `victim.Position = cellTowardCaster; victim.Notify_Teleported()` and is the one canon beat ("the blade wraps and pulls") that justifies a longer cooldown.

**AI:** `aiCanUse` is set, but whether humanlike raiders use equipment-granted abilities in 1.6 is not something this session can confirm. Check with a Society raid under dev mode; if praetors never lash, the fallback is to leave the ability player-only and give NPC Golds their reach through nothing (they are already lethal at 1 cell).

**Verification in game:** draft a Gold with a razor, target a pawn 5 cells away behind sandbags; expect the line fleck from hand to target, the crack, a Cut injury scaled by the wielder's melee factor, a stagger, and a clean log. Repeat with CE active against a pawn in duroArmor once RV-01 is in; the lash should get through duro and not through pulse.

---

## Fix order

**Batch 1 — mechanical, no decisions** (mod stays loadable after each): RV-04, RV-05, RV-12, RV-15, RV-19, RV-20 (comments), RV-17 (pick 43/49 wording).

**Batch 2 — CE** : RV-01 (six apparel blocks + validator check), then the CE half of RV-02 or the whole whip rework.

**Batch 3 — needs the game running**: RV-03 (spawn test, then (a) or (b)), RV-07, RV-08, RV-09, RV-13, RV-14 (each has a one-line verification above).

**Batch 4 — decisions**: RV-06 (tolerance or not), RV-10 (who may generate with razors), RV-11 (shield text vs comp), whip options.

RV-16, RV-18, RV-21..24 need no action unless the user wants the cosmetics.
