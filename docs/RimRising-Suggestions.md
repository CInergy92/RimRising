# RimRising — suggestions for fun and lore fidelity

**Status:** proposals, not decisions. Written 2026-10-08 against commit `ea7105f` by a read-only review session, for the user and the Opus session to pick from. Companion to `docs/RimRising-Review-2026-10-08.md` (bugs) — nothing here is a bug.

Every item names the vanilla mechanism it rides on, an effort estimate, and what has to be verified before building (this session had no game install or decompiler; **verify, never recall** applies to every mechanism named below). Nothing here reproduces text from the books, and no character name from them is used — the project's standing rule.

Rulings already made in `docs/DESIGN.md` are respected: no age gate on carving (§8e), Pink framing stays as built (§8c), Gold has no physical weakness, the player may reject the hierarchy, prefixes stay as they are (§8b).

**Effort key:** `XML` — defs only. `XML+art` — defs plus textures the existing `Tools/` pipeline can draw. `C#‑small` — one comp/worker/patch under ~150 lines. `C#` — a real feature.

---

## 0. What makes this mod fun, and the rule for adding to it

RimWorld is fun where a system is *legible* and then *breaks*: you can read a pawn's place in the world off the screen, and then something crosses a line and everyone reacts. RimRising already has the legibility (hair, names, titles, plate colour, the ladder thought) and two line-crossings (carving, a lowColor with a razor). Most of what follows adds either **more ways to read the hierarchy at a glance** or **more lines that can be crossed and reacted to** — and leans on vanilla loops (trade, ideoligion, raids, surgery, titles) rather than inventing new ones. The guiding rule: a suggestion earns its place if a player who has never heard of the books would still enjoy it as a RimWorld mechanic.

A second rule, from the user's own direction in CLAUDE.md: nothing is done until it loads clean and the verification steps are written down. Each item below ends with "verify".

---

## 1. Quick wins — XML, highest lore per hour

### 1.1 Backstories per Color

**Lore.** A Red was a helldiver or a drill hand; a Gray stood a wall; a Copper filed; a Violet was raised in a Grove; a Gold went to the Institute. Right now every pawn's bio is a vanilla outlander or offworlder, and the bio is the single most-read text on a pawn.

**Mechanism.** `BackstoryDef` is plain XML since 1.4 (`Core/Backstories/*.xml`; `slot Childhood|Adulthood`, `title`, `titleShort`, `baseDesc`, `skillGains`, `workDisables`, `forcedTraits`, `spawnCategories`, `bodyTypeGlobal`). Factions select by `backstoryFilters/categories`, which the mod already sets. Define a category per tier (`RR_Society`, `RR_LowColor`, `RR_Rising`, `RR_Tribe`) and point each faction at it. Twenty childhoods and thirty adulthoods, all original writing, cover the roster; the Color is implied by the text, and the xenotype genes already carry the aptitudes, so `skillGains` can stay small.

**Fun.** Also the cheapest way to express **Iron Gold / Pixie** (DESIGN §2.6: behavioural tiers, never built): two Gold adulthoods with `forcedTraits` (`Tough`+`Brawler`-style for the martial exemplar; `Greedy`+`Lazy`-style for the decadent) rather than new precepts. And it is where the Rising's "abandoned the prefix" idea lives: a `RR_Rising` adulthood whose `titleShort` is "defector".

**Effort.** XML. **Verify:** BackstoryDef field names against `Core/Backstories/Shuffled_Adult_Offworld.xml`; that `spawnCategories` is matched case-sensitively; that xenotype `nameMaker` still applies when a backstory sets nothing about names.

### 1.2 The Society pays in standing — a census caravan

**Lore.** Standing with the Society is earned by service. In game, favour on the Gold ladder (`RR_Title_*`) currently has no source except what Royalty's Empire quests happen to hand out — and those are the Empire's.

**Mechanism.** Royalty's tribute collector is a `TraderKindDef` with `tradeCurrency Favor` and a `faction` field, delivered by the ordinary `TraderCaravanArrival` incident. Clone it: `RR_Caravan_Society_Census` buys ionsteel, resFlesh, carving kits, prisoners and slaves (Ideology slavery already models the Society buying people), and *pays in standing*. Add it to `RR_Society.caravanTraderKinds` and `RR_RimDominion`'s. A second one, `RR_Caravan_Society_Armory`, sells duroArmor, scorchers, nazopran and resFlesh for silver and buys helium if 1.6 is built — today the Society sells vanilla outlander stock, which is the one place the faction still reads as "an outlander town with Golds".

**Fun.** Gives the title ladder a loop (serve the Society → standing → Graduate → Peerless) that a hierarchy colony can actually play, and a thing an egalitarian colony is pointedly denied. Selling a Red to the census caravan for standing is the kind of decision this game is good at.

**Effort.** XML. **Verify:** `TraderKindDef.tradeCurrency` and `faction` on `Royalty/Defs/TraderKindDefs/TraderKinds_Caravan_Empire.xml`; `StockGenerator_SingleDef` / `StockGenerator_Tag` / `StockGenerator_Slaves` names; that a favour-currency caravan works for a non-Empire faction (the Empire's uses `royalFavorLabel`, which `RR_Society` already sets).

### 1.3 Trader kinds for every faction

Same mechanism as 1.2, no favour: Sun sells recoilArmor, pulseFists and the implants (the one merchant that arms the Rising — `RR_Scenario_Rising`'s description promises this); Julii sells everything plus `StockGenerator_Slaves` (the pirate merchant already hints at it); the obsidian tribes sell god's bread, fever cloud and Stained-grade melee weapons and buy steel they are not supposed to have. Replace the vanilla `Caravan_Outlander_*` entries rather than adding beside them, so the faction's stock *is* its character.

**Effort.** XML. **Verify:** as 1.2.

### 1.4 Names for the Colors that have none

**Lore.** DESIGN §8b: Red, Pink and Obsidian carry no prefix because the Society files them as property; White, Yellow, Violet, Orange and Brown have none in the reference. Today those eight Colors draw vanilla names, so a Red is "Jenkins" and an Obsidian is "Rebecca". The *absence of a prefix* is the point, but the names themselves should still sound like the caste.

**Mechanism.** `XenotypeDef.nameMaker` + `RulePackDef`, exactly as the six prefixed Colors already do. Three new pools, all original: an Obsidian register (hard consonants, patronymic-style surnames, "-sdottir/-sson" shapes are public domain), a Red register (short given names, surname is a *place* — "of <shaft>" built from mining-syllable pools, per DESIGN §8b "Reds identify by origin"), and a Pink register (given name only — `r_name->[given]` — which says "property" more quietly than any description). Brown and Orange can share the servant pool already written; White and Yellow the highborn one; Violet its own softer pool.

**Fun.** Reads at a glance in the colonist bar, costs nothing at runtime.

**Effort.** XML. **Verify:** that a single-token `r_name` (no surname) is accepted by `NameTriple` parsing — Impid-style namers produce triples; a `NameSingle` may need `nameMakerFemale`/`NameSingle` handling. Check `Biotech/Defs/RulePackDefs/RulePacks_Namers_Xenohumans.xml`.

### 1.5 The razor as a persona weapon

**Lore.** Razors are named, kept for generations, and handed down inside a house. The project's own original plan (`Weapons_RimRising.xml:9-12`) was "the razor becomes a persona weapon" and it was dropped when Royalty was not yet a dependency. Royalty is a dependency now.

**Mechanism.** A second def, `RR_Weapon_Razor_Heirloom`, mirrored from `MeleeWeapon_MonoSword` with `CompProperties_Bladelink` and `CompProperties_GeneratedName` (the mono/plasma/zeus swords in `Royalty/Defs/ThingDefs_Misc/Weapons/MeleeBladelink.xml`): bonds to one wielder, carries one to three weapon traits, has a generated name. Give it `RR_RazorBearer`-style tags so Olympic Knights and Praetors generate with it, `tradeability` None, `generateCommonality` low. Keep the plain razor craftable; the heirloom is found on a dead knight or granted by a Society quest reward, never built.

**Fun.** Bladelink traits (the kill-thirst / psychic ones) already produce stories; a razor that *will not let a Red hold it* is a bonded weapon refusing its wielder, which is the fiction's own line about razors for free. Watch the `comps Inherit="False"` restating rule and the `CompProperties_Art` gap noted in the review.

**Effort.** XML (+ one sprite variant if wanted — the existing razor with a different hilt colour via `Draw-Weapons.py`). **Verify:** bladelink comps and `weaponTags` on the mono sword; `CompBladelinkWeapon` traits list; whether `CompEquippableAbility` and `CompBladelinkWeapon` coexist (both are equipment comps; nothing suggests a conflict).

### 1.6 Trial by razor — a duel ritual for hierarchy ideoligions

**Lore.** Golds settle standing by the blade; the Institute is a year-long duel. **Mechanism.** Ideology ships a duel ritual (the `Duel` precept, `RitualBehaviorWorker_Duel`, with `RitualOutcomeEffectDef` moods). Clone it as `RR_Ritual_RazorTrial`, put it in `RR_ColorHierarchy`'s `requireOne` so every hierarchy ideoligion has it, and give the outcome effect a `RR_` thought ("watched a trial by razor") and, if the loser dies, the vanilla execution events. Restrict participants with `RoleRequirement_Xenotype` to Gold/Bronzie if the ritual framework exposes participant requirements (the duel takes two fighters chosen in the dialog).

**Fun.** Duels are one of Ideology's best set pieces and almost nobody runs them. A hierarchy colony *has* to, and the loser is a Gold.

**Effort.** XML. **Verify:** `Ideology/Defs/PreceptDefs/Precepts_Ritual.xml` for the duel precept's `ritualPatternBase`, and whether participant roles accept requirements.

### 1.7 A slingBlade for the Reds

**Lore.** The reaper's razor is shaped like a mining tool. The tool itself is missing from the mod: the thing every Red holds all day. **Mechanism.** `RR_Weapon_SlingBlade`, parented to `BaseMeleeWeapon`, Industrial, cheap (steel at a smithy, no research), a curved cut weapon between a gladius and an ikwa in numbers, tagged `RR_RisingWeapon` so Ares fighters and laborers carry it, and added to `RR_Scenario_Breakout`'s starting things (its text already says "you have a drill"). Under CE it needs a `ToolCE` block — the validator will insist. Sprite via `Draw-Weapons.py` (the reaper's curve at a smaller scale, wooden haft).

**Fun.** The Breakout start is three unarmed Reds; a mining blade is the right amount of weapon, and a resistance raid that arrives with slingBlades and assault rifles reads correctly before anyone opens a tab.

**Effort.** XML+art, plus a `WeaponTweakData` JSON (`Derive-MeleeTweak.py`) so Melee Animation animates it.

### 1.8 Caste marks — tattoos and styles tied to the memes

**Lore.** Blues shave and tattoo; Obsidians are stained; Peerless Golds are scarred (done). **Mechanism.** Ideology's `TattooDef` / `HairDef` carry `styleTags`; memes list `styleTags` they favour, and pawns generated for an ideoligion draw from them. Two or three tattoo sets (`RR_DigiTat_Face`, `RR_ObsidianStain_Body`) with 128² textures from the icon pipeline, tagged to `RR_ColorHierarchy` and `RR_GoldWorship`. Xenotype-specific assignment (only Blues get digiTats) is not expressible by meme alone; `GeneDef` has `tattooDef`?-style hooks only for hair/skin colour, so either accept that any hierarchy pawn may carry a digiTat or do the per-Color assignment in a small `PawnGenerator` postfix.

**Effort.** XML+art, `C#‑small` for per-Color accuracy. **Verify:** `StyleItemDef.styleTags`, `MemeDef.styleTags`, and whether `XenotypeDef` or `GeneDef` has any style hook in 1.6.

### 1.9 Howlers as a pawn kind

The stealth kit exists (scarabSkin, demonHelm, ghostCloak) but nobody spawns in it. Add `RR_Ares_Howler` (Red/Gray mix, `apparelTags Inherit="False"` → a new `RR_StealthKit` tag carried by the three pieces, `weaponTags` SpacerGun, combatPower ~110) to the Sons of Ares combat group at low weight, and `RR_Society_Lurcher` could carry the demonHelm the same way. Whether AI pawns *use* the cloak ability is a separate question (see the review's note on `aiCanUse`); even unused, a raider in a ghostCloak is lootable, which is how the player gets one early.

**Effort.** XML.

### 1.10 Carving aftermath

**Lore.** A carving takes months and is not bearable; the person who walks out is not the person who walked in. In game it is one surgery and a message. **Mechanism.** Two hediffs added by `Recipe_CarveColor.ApplyOnPawn` (one line each): `RR_CarvingRecovery` — weeks of pain, Moving and Manipulation down, `HediffCompProperties_SeverityPerDay` to burn off, `HediffCompProperties_Disappears`; and, on a failed-but-survived surgery roll, `RR_CarvingRejection` — permanent, mild, a scar in the record. Plus a `Thought_Memory` for the carved pawn via `PreceptComp_SelfTookMemoryThought` on `RR_ColorCarved` under both memes (the hierarchy's reads as shame, the equality's as liberation — the knows-thoughts exist; the *self* thoughts do not).

**Fun.** Makes the carving a *period* in a colony's life rather than a click, which is what the central mechanic deserves, and gives the carved pawn a mood story.

**Effort.** XML + `C#‑small` (two `AddHediff` calls).

---

## 2. Medium — one real piece of work each

### 2.1 Sigils, and the lie a carved pawn carries

**Lore.** DESIGN §4 lists "sigils implanted in the wrists — a HediffDef that marks caste, and whose absence or falsification is itself detectable". Not built. **Mechanism.** `RR_Sigil_<Color>` hediffs on a hand, added at generation by a small `PawnGenerator` postfix for Society-faction pawns and by the Breakout/Household scenarios; invisible in effect, visible in the health tab. A Carver surgery `RR_ForgeSigil` (Violet-only, kit + resFlesh) swaps it. Then the interesting part: `RR_CasteIdentity` keeps reading *genes* (a carved Gold passes socially), but a new `RR_CasteIdentity.SigilOf(pawn)` reads the *paper*, and the two places the Society checks paper — the census caravan (1.2) and the Lurcher hunt (2.2) — use the sigil. A carved Red with a Red sigil is a Gold until somebody looks at their wrist.

**Fun.** Turns "passing" into a mechanic with a tell, a fix (forge it), and a risk, instead of a flag that is set and forgotten.

**Effort.** `C#‑small` for generation, XML for the rest. **Verify:** `Hediff` on `BodyPartDefOf.Hand` survives amputation sensibly (it will be lost with the hand — which is correct and funny).

### 2.2 The Lurcher hunt

**Lore.** Lurchers are bred to kill highColors and are pointed at the ones who should not be. **Mechanism.** An `IncidentDef` (`IncidentWorker_RaidEnemy` subclass, or a `QuestScriptDef` if a letter and a timer are wanted) that fires only when the player colony holds a carved pawn whose sigil (2.1) does not match, or a lowColor who bore a razor (the `RR_LowColorBoreRazor` event already exists as a trigger): a small Society group of `RR_Society_Lurcher` arrives with a `LordJob_AssaultColony`-style job targeting that pawn. Storyteller comp: `StorytellerCompProperties_Triggered`-style, or a `QuestNode_Root` with a `HistoryEvent` trigger.

**Fun.** The Society *noticing* is the consequence the carving system is missing. It is also the best use of the Lurcher xenotype, which today is a slightly better Gray.

**Effort.** `C#`. Needs `IncidentWorker` and `Lord` code; the Board of Quality Control storyteller is the natural owner, and the incident could be weighted higher under it.

### 2.3 Caste-restricted work, the soft way

**Lore.** Colors are confined to their caste's trade by law. DESIGN §4 planned precepts for it. **Do not** use `GeneDef.disabledWorkTags` or hard incapables: a Red who *cannot* research is a worse RimWorld pawn and it is wrong anyway — Reds are *denied* education, not unable. **Mechanism.** A `ThoughtWorker` (sibling of `ThoughtWorker_ColorRank`) giving hierarchy-believing pawns a situational thought when a pawn is doing work "above" or "below" their Color — reading `Pawn.CurJob.workGiverDef.workType` against a per-Color table on a `DefModExtension` on each `XenotypeDef` (`allowedWorkTypes`). Observers: "a Red at the research bench" (−); the pawn themself: "work above my station" (−, hierarchy) or "doing what I was never allowed" (+, equality). Expose it as a precept pair on a new `RR_CasteLabor` issue, `requireOne` under both memes.

**Fun.** A hierarchy colony has to staff the research bench with Yellows and Greens and feels it when it cannot; an equality colony gets a small, constant reward for mixing. It is the daily-life version of the ladder thought, which today only fires on *who* you stand next to, not *what* you do.

**Effort.** `C#‑small` (one worker, one extension) + XML. **Verify:** `Pawn.CurJob.workGiverDef` is set for most work jobs but not all (e.g. hauling via `JobGiver_Work`); fall back to `JobDef` category.

### 2.4 Helium-3 and the Barrens

**Lore.** The Barrens exist for what is under them, and pulse armour "drinks helium-3". Neither is a thing in game. **Mechanism.** `RR_Helium3` as a resource (`Graphic_StackCount`, canister sprites from `New-ItemIcons.ps1`), obtained by deep drilling (`ThingDef.deepCommonality`, `deepCountPerPortion`, `deepLumpSizeRange` — vanilla's deep resources) with a `MarketValue` that makes it the Barrens' export, bought by the Society census caravan (1.2) and Julii. Making the Barrens *better* for it than other biomes needs a check: deep resources are global, so either accept it (fine; the biome's scanner just finds more rock) or add a mineable `RR_HeliumSeam` placed by the biome's terrain if a 1.6 biome field for scatterable mineables exists.

Then pulse armour can cost something to run: a `CompProperties_ApparelReloadable`-shaped charge on the suit's servo bonuses is awkward (that comp wants a verb); the honest version is a `C#‑small` comp that burns one canister per N days worn or the `MoveSpeed`/`MeleeDamageFactor` offsets drop, with a gizmo showing charge. Lore-exact, but **decide whether the upkeep is fun** — RimWorld players tolerate fuel on turrets and dislike it on clothes. A middle path: no upkeep, but the suit's *trauma suite* restocks stims from helium instead of from nothing (TraumaSuite already has a recharge timer; swap "free" for "consumes one `RR_Helium3` from the wearer's inventory or a nearby stockpile").

**Effort.** XML for the resource; `C#‑small` for any upkeep. **Verify:** deep-resource fields on `Core/Defs/ThingDefs_Items/Items_Resource_Stuff.xml` (Uranium/Plasteel entries).

### 2.5 The Institute as a start and as a place

**Lore.** The year-long trial every Gold child is put through. **Mechanism, cheap form:** a fourth scenario, "The Institute" — eight Gold adolescents (`allowedDevelopmentalStages Child`? no: Biotech children cannot fight; use young adults at `pawnChoiceCount`), no faction help, a `ScenPart_CreateIncident` raid from the Society every few days (the "Proctors"), a `ScenPart_StatFactor`-style harsh start, and the Household scenario's standing offered at the end via a timed quest. **Expensive form:** a `WorldObjectDef` site with a `SitePartDef` and a quest chain. The cheap form is a weekend; the expensive form is a milestone.

**Effort.** XML (cheap) / `C#` (site).

### 2.6 Iron Rain

**Lore.** The Society's assaults come down from orbit. **Mechanism.** Vanilla picks raid arrival modes per faction through `PawnsArrivalModeDef.selectionWeightCurvesPerFaction`? — not a field this session can confirm. If the arrival-mode weighting is reachable from XML (check `Core/Defs/PawnsArrivalModeDefs` and `RaidStrategyDef`), give the Society and Dominion a heavy weight on `CenterDrop`/`EdgeDrop` and the tribes none. If it is not, a `C#‑small` Harmony postfix on the arrival-mode selection for `RR_Society` is enough. Pair with a `RR_IronRain` skyfaller skin (the gravAscent sprite pipeline already exists) and the starShell's `RR_StarShellFrame` description, which already names the term.

**Effort.** XML or `C#‑small` depending on the field. **Verify** first.

### 2.7 RipWings and a gravBike

Vehicle Framework supports aerial vehicles. A Blue-piloted `ripWing` (two seats, light cannon, fast, fragile) on the same VF folder as the Drachenjaeger gives Blues a reason to exist in a colony and the Society a second vehicle. Art is the expensive part — the vehicle pipeline (`New-VehicleArt.ps1`, silhouettes, 128 px per cell) is already built. Same for a one-seat gravBike for Golds. Both are optional-folder content with no new dependency.

**Effort.** XML+art (large art).

---

## 3. Smaller touches

- **The razor hum.** A `soundInteract`/`soundDrop` for both razors (there is a `SoundDef` pipeline via fal already); vanilla melee weapons use `Interact_...` sounds. XML.
- **A `RR_Society_Praetor` persona name rule.** Golds who reach Peerless get an epithet: `RoyalTitleDef` has `labelFemale`/`labelCap`; a `nameMaker`-style epithet is not vanilla, but the title's label itself can read "Peerless Scarred" + the house, which is what the fiction does. XML.
- **Dominion vs Society goodwill.** NPC-to-NPC relations are not authorable (CLAUDE.md), but *which Society you serve* is: give the Rim Dominion its own `royalFavorLabel` ("the Rim's regard") and a slightly different ladder (`RR_Title_Shamed` → `RR_Title_RimKnight` …) via a second `royalTitleTags` set, so standing with one is not standing with the other. XML; interacts with `TitleLadders.cs` (it keys on tags, so a third tag needs adding to `EligibleFor`).
- **Obsidian shamans as a role.** `RR_GoldWorship` already names the moralist "shaman"; a `Precept_RoleSingle` "Shaman" requiring `RR_Obsidian` with the vanilla moralist abilities, so a tribe ideoligion has a face. XML.
- **White arbiters as a role** in hierarchy ideoligions: `RoleRequirement_Xenotype` → `RR_White`, with `RoleEffect_PawnStatOffset NegotiationAbility` and the vanilla leader's "conversion" abilities swapped for a "pronounce" (the vanilla `Trial` ritual exists in Ideology; the arbiter presides). XML.
- **Copper officials raise trade prices for the Society.** A `RoleEffect`-free version: give the Society's census caravan better prices when the colony has a Copper (needs C#) — or skip it and give Coppers `AptitudeStrong_Social` already present. Note only.
- **Zoladone for Gray squads.** Society combat kinds could carry it as `combatEnhancingDrugsChance` (a `PawnKindDef` field used by vanilla pirates for go-juice) with `combatEnhancingDrugsCount`. Grays on zoladone are harder to break, which is the drug's canon use. XML, verify the field names.
- **Fever cloud for tribe raids.** Same field on `RR_Tribe_Obsidian_Warrior` → berserk Obsidians, which is what "making men into savages" looks like arriving at the wall. XML.
- **The Board's census letter.** Each new year under the BQC storyteller, a letter stating the colony's "target population" for the year (a `StorytellerCompProperties_Triggered`-style comp or an `IncidentDef` with `IncidentWorker_LetterOnly`-style worker: check whether vanilla has a letter-only worker, else `C#‑small`). Flavour that explains the storyteller's premise in play.
- **Reds and the dark.** `CaveDweller` + `DarkVision` are on; a `MineableSpeed`-style stat bonus underground is not a vanilla stat, but `MiningSpeed`/`MiningYield` offsets via a gene are. Already `AptitudeRemarkable_Mining`; consider `MiningYield` +20% on Red and Ultraheavy as the one thing Reds are *the best in the game* at. XML.
- **Carver reputation.** A Violet who has carved N pawns gets a title-like `Hediff` or trait ("Master Carver", DESIGN §2.7) that improves `surgerySuccessChanceFactor` via `MedicalSurgerySuccessChance` offset. `C#‑small` (counting) or XML if simply granted by a ritual.

---

## 4. Things to leave alone

- **No age gate on carving** (DESIGN §8e). Do not add one in 1.10 either; the recovery hediff applies to anyone.
- **Pink content** stays as built; nothing here touches it beyond the name register in 1.4, which is about legal status, not the Gardens.
- **No hard work incapables by Color** (2.3 explains why).
- **No eighth required mod.** Everything above is vanilla+DLC XML, this mod's own C#, or an existing optional folder. 1.5 uses Royalty (already required).
- **No book names.** Every defName, label and rule pack above is original; "ripWing", "slingBlade", "Iron Rain", "Institute", "Lurcher", "sigil" are setting *terms* of the kind the project already uses (razor, pulseFist), not prose or character names.

---

## 5. Suggested order

1. **1.1 backstories** and **1.4 names** — the two biggest legibility gains, pure XML, no risk.
2. **1.2 / 1.3 trader kinds** — gives the title ladder and the merchant houses their loops.
3. **1.10 carving aftermath** and **1.7 slingBlade** — small, finish two existing features.
4. **1.5 heirloom razor** and **1.6 razor trial** — both ride on Royalty/Ideology content that already exists.
5. **2.1 sigils → 2.2 Lurcher hunt** — the one new *system*; do 2.1 first and let 2.2 wait for a test of whether the carving loop needs an antagonist.
6. **2.3 caste work thoughts** — after the ladder thought has been judged in play, since it is the same idea applied to jobs.
7. Everything else as the art budget allows.
