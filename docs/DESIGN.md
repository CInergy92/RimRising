# DESIGN — RimRising

Content design. **The user is the authority on the setting.** Where a decision is a lore judgment
call rather than a technical one, this document presents options rather than picking one.

Original writing only. Structural facts about the setting (which Colors exist, their occupations,
the grouping of the hierarchy, the naming prefixes) are treated as reference. No prose, dialogue,
or imagery from any published source is reproduced, and none should enter the mod's text.

---

## 1. Decisions locked

Ruled on by the user:

| Decision | Ruling |
|---|---|
| Mod name | **RimRising** |
| Color inheritance | **Colors are inheritable.** Two parents of a Color produce a child of that Color. |
| Crossing Colors | **Possible, but very difficult.** Carving is real and dangerous. |
| Roster scope | Full roster up front, so the whole system is visible as a baseline. **See §2.1 — the canonical roster is 14, not the 10 in the original brief.** |
| RimJobWorld | **Optional, never required.** Gated folder; base mod complete without it. |
| Dev environment | Build against what the mod needs, not the user's full mod list. |

---

## 2. The Color system

### 2.1 Roster — 14, not 10

The original brief listed ten Colors. The canonical hierarchy has **fourteen**. The four not in the
brief are marked below.

**The roster is a lore call and therefore yours.** I have designed for all fourteen because you
pointed me at the reference as the authority, and because "so we know what we are working with as a
baseline" argues for the complete set. Cutting back to your original ten is a small change — the
four additions are self-contained. Say the word either way.

The hierarchy groups into three tiers, which is itself mechanically useful — it gives us a natural
structure for precepts and faction composition rather than fourteen unrelated special cases.

#### highColors

| Color | Function | In original brief? |
|---|---|---|
| **Gold** | Rule | yes |
| **Silver** | Finance, commerce | yes |
| **White** | Clergy, judiciary | yes |
| **Copper** | Administration, law, bureaucracy | **no — new** |

#### midColors

| Color | Function | In original brief? |
|---|---|---|
| **Blue** | Ship pilots, bridge crew | yes |
| **Yellow** | Medicine, research | yes |
| **Green** | Programming, technicians | **no — new** |
| **Violet** | Artisans, creatives | **no — new** |
| **Orange** | Mechanics, engineering | yes |
| **Gray** | Soldiers, police | yes |

#### lowColors

| Color | Function | In original brief? |
|---|---|---|
| **Red** | Manual labor, mining | yes |
| **Pink** | Social functionaries | yes |
| **Obsidian** | Elite soldiers, bodyguards | yes |
| **Brown** | Servants, cooks, janitors | **no — new** |

Note that the tiering is **not** a simple power ranking: Obsidian is a lowColor despite being the
most physically dangerous caste in the setting. That tension — engineered lethality held at the
bottom of the social order — is one of the more interesting things to render mechanically, and it
argues for keeping social standing and combat capability as separate axes.

### 2.2 Physiology to build into genes

Reference points that translate directly into `GeneDef`s:

- **Hair and eye color track caste.** Every Color needs its spectrum genes. This is also the single
  cheapest way to make the hierarchy legible at a glance in game.
- **Red** — smaller, squat, built for tunnels.
- **Obsidian** — larger, more durable.
- **Pink** — deliberately delicate and fragile.
- **Gold** — engineered physically superior across the board; skeletal strength far above baseline.
- lowColors have engineered-short gestation; Gold and Obsidian do not. Biotech models pregnancy, so
  this is expressible, though it is low priority.

### 2.3 Balance anchors — computed from vanilla

Summed `biostatCpx` across each vanilla xenotype's genes, resolving template-generated genes back
to their `GeneTemplateDef`:

| Vanilla xenotype | Genes | Complexity |
|---|---|---|
| Sanguophage | 30 | 41 |
| Waster | 13 | 11 |
| Hussar | 19 | 10 |
| Genie | 12 | 8 |
| Highmate | 20 | 8 |
| Yttakin | 16 | 7 |
| Starjack | 13 | 7 |
| Dirtmole | 10 | 4 |
| Pigskin | 12 | 4 |
| Neanderthal | 17 | 3 |
| Impid | 18 | 2 |
| Baseliner | 0 | 0 |

**Caveat:** the template resolution is my own inference from `GeneTemplateDefs.xml`, not something
the game exposes. Ordering is reliable; exact figures are provisional until checked against the
in-game gene assembler.

Proposed complexity bands, which map onto the canonical tiers:

- **lowColors** — 2 to 6. Specialized, cheap, and visibly limited.
- **midColors** — 6 to 10. Comparable to Genie or Hussar: genuinely good at one thing, weak
  elsewhere.
- **highColors** — 10 to 16, except Gold.
- **Gold** — 20+, deliberately in Sanguophage territory. This is not just flavor; see §3.1.

A Color that is purely an upgrade is a design failure. Every caste is built for a purpose and
crippled outside it — that is what makes the hierarchy legible in play rather than cosmetic.

### 2.4 Naming

The setting uses two-letter caste prefixes between given name and surname, drawn from element
symbols: Gold `au`, Silver `ag`, Copper `cu`, Blue `xe`, Green `si`, Gray `ti`. White, Yellow,
Violet, Orange and Brown have no established prefix.

Crucially, **Red, Pink and Obsidian have no prefix at all**, because the Society treats them as
property rather than people. Reds identify by origin instead.

This is a gift, mechanically. `XenotypeDef` supports `nameMaker`, `nameMakerFemale` and
`chanceToUseNameMaker` (verified on Dirtmole). We can express the entire legal status of a caste
through its name generation, at essentially zero cost, and a player will read a pawn's standing off
the name before opening any tab.

**Open question:** for the five Colors with no established prefix, do you want me to invent
plausible element-symbol prefixes for consistency, or leave them prefix-less? Inventing is a lore
call, so it is yours.

---

## 2.6 Gold in detail

From the reference, and now built:

| Trait | Implementation |
|---|---|
| Golden irises | `Eyes_Golden` (EyeGenes2) |
| Golden or blonde hair | `Hair_Blonde` |
| **Skin varies by ancestry** | **No skin gene at all** — Gold is the only Color without one, so skin rolls naturally. This is deliberate and canonical. |
| Bone density ~5x, superhuman strength | `Robust`, `MeleeDamage_Strong` |
| Taller than other Colors, most over 2m | `AG_LargerBodySize` |
| Lives past 150, fit into old age | `AG_ExtraordinaryLifespan` |
| Enhanced cognition | `AptitudeStrong_Intellectual`, `Learning_Fast` |
| ~0.22% of population (40M of 18B) | `factionlessGenerationWeight` **0.1** against Red's **30** |

Not implemented, no vanilla or dependency mechanism found: five-minute breath-holding.

### Appetite and expectations

Per direction, `RR_HighbornAppetite`:

- `biostatMet -3` — markedly higher food consumption.
- `forcedTraits: Greedy` — mood loss without an impressive bedroom. This is the only way vanilla
  exposes "higher expectations" in pure XML. `ExpectationDef`s exist (`ExtremelyLow` → `Royal`) but
  are driven by wealth and royal title, not genes; raising them per-pawn needs C#.

Neither is a capability weakness. A hungry, fussy Gold is still the most dangerous person in the
room — both are economic costs, which is the shape the constraint was asked to take.

### Gold tiers — M5, not M2

The reference gives Gold a rank structure. Only one of these is genetic:

| Tier | Nature | Where it belongs |
|---|---|---|
| **Peerless Scarred** | Achieved — top Institute performance | Ideology role (M5) |
| **Graduate** | Achieved — attended, no distinction | Ideology role (M5) |
| **Shamed** | Achieved — performed poorly | Ideology role (M5) |
| **Iron Gold** | Behavioural — martial exemplar | Precept / thought (M5) |
| **Pixie** | Behavioural — decadent, self-indulgent | Precept / thought (M5) |
| **Bronzie** | **Genetic** — inferior stock, smaller and weaker, khaki hair and eyes | Could be a 15th xenotype |

**Open question:** the roster is fourteen Colors, but Bronzie is a genetic sub-grade of Gold rather
than a rank, so it is the one tier that would naturally be its own `XenotypeDef` — a cheaper Gold
with lower complexity, khaki colouring, and none of the size or lifespan genes. Worth adding as a
fifteenth xenotype? It would also give carving a *cheaper* target than true Gold, which is
mechanically interesting. Lore call, so it is yours.

---

## 2.7 Per-Color corrections from the reference pages

The summary table on the main Color page is not enough — the individual pages contradict it in
places. Corrections applied:

| Color | Finding | Change |
|---|---|---|
| **Obsidian** | Hair **white**, eyes **black** — not black hair | `Hair_SnowWhite` |
| **Blue** | Hair listed as **Bald**: DigiTats are tattooed on a shaved scalp. Brains are neurodevelopmentally sculpted for machine interfacing, which *impairs communication outside their sect*. | `Hair_BaldOnly`, added `AptitudeTerrible_Social` |
| **Violet** | Raised in Groves on forced psychedelics to boost artistic output. Many leave **very unstable**. | `Mood_Optimist` → `Instability_Mild` |
| **Red** | lowReds **rarely live past thirty**; forties is elderly. | `ShortLifespan` (also refunds metabolism) |
| **Gray** | Explicitly **not** superhuman — "easily dispatched in large numbers by Gold and Obsidian". Their edge is numbers and discipline. | Dropped `Immunity_Strong` |
| **Silver** | Hair and eyes silver. | `Hair_SnowWhite` → `Hair_Gray`, freeing SnowWhite for White and Obsidian |
| **Gold** | Skin varies by ancestry; 150+ year lifespans | No skin gene; `ExtremeLifespanExtension` |

Confirmed already correct: Copper (copper hair/eyes), Yellow (blonde hair, yellow eyes), Brown
(brown/brown), Orange (orange/orange), Pink (pink hair, pink eyes, beautiful and fragile), White
(white/white), Green (green eyes; hair shaved or short → `Hair_ShortOnly`).

### Population ratios

The pages give hard numbers, and they do not form a simple pyramid: Grays outnumber Golds
**a thousand to one**, Coppers outnumber Silvers **ten to one**, and Violets are as rare as Whites.
Notably **Gold outnumbers both Copper and Silver** — the top of the hierarchy is not its smallest
tier. Weights now reflect this, with Red at 30 as the overwhelming bulk and Silver at 0.4 as the
rarest.

### Sub-tiers not yet built

Several Colors have genetic sub-tiers that could each be a xenotype. Only Bronzie is built. Flagged
for a decision, not assumed:

- **Ultraheavy** (Red) — bred for the Rim, 2.4g and heavy radiation; larger and denser than other
  Reds, shorter-lived.
- **Lurcher** (Gray) — genetically altered for superior smell and sight, trained to kill highColors.
- **Fulgur Bellator** (Green) — bred hardy, thicker-bodied, paired with Gray squads.
- **Rose** (Pink) and **Stained** (Obsidian) — described as comparably rare and valuable.
- Some Pinks carry **Pheromonal Defense Mechanisms**.

### Two strong hooks for later milestones

- **Carvers are Violets.** Master Carver and Carver are Violet tiers — the artist caste performs
  bio-modification. So the caste that makes carving possible is a midColor, not a Gold. That is a
  gift for Milestone 5: the surgery at the heart of the mod belongs to a specific Color.
- **Bladeweavers are Oranges.** A sub-tier of Artificer specifically builds razors. Milestone 4
  should gate razor production behind an Orange.

---

## 3. Carving — crossing Colors

Your ruling: possible, but very difficult. This is also canonical — Carvers exist in the setting
specifically to carve Reds into Golds.

### 3.1 Vanilla already does most of the work

Verified in `Biotech/Defs/RecipeDefs/`:

- `ImplantXenogerm` is a real surgery (`workerClass` `Recipe_ImplantXenogerm`).
- Its `SurgeryOutcomeEffectDef` includes `SurgeryOutcomeComp_XenogermComplexity`, whose curve runs
  `(0, 1)` to `(20, 0.6)` — **success chance falls as complexity rises.**
- Failure applies `XenogerminationComa`, up to 3 days.

Putting Gold above 20 complexity therefore makes carving into Gold the most dangerous surgery in
the game *as a consequence of the gene budget*, with no special-casing. The difficulty is a
property of the design rather than a number tacked on.

### 3.2 Inheritance behaves correctly by accident

- `inheritable` xenotypes pass on **endogenes**.
- Xenogerm implantation grants **xenogenes**, which are **not** inherited.

So a carved pawn's children inherit their **birth** Color. A Red carved into a Gold does not found
a line of Golds. That matches the setting exactly, and costs nothing to implement.

### 3.3 Escalating the difficulty, in the order I would add it

1. **Complexity cost** — free, above.
2. **Research gate** — a late project on our own `ResearchTabDef`.
3. **Ingredient cost** — materials gated behind the tech chain, not 4 medicine.
4. **Ideoligious consequence** — a `HistoryEventDef` on carving, with precepts that make Society
   members react badly.

Layer 4 holds **the one known C# risk**: I have not verified that vanilla raises a history event on
xenogerm implantation. If it does not, raising one needs Harmony. I will check before Milestone 5
and ask before writing any C#.

### 3.4 Unverified, must be tested at Milestone 2

**Does implanting a xenogerm assembled from an exact Color gene set make the pawn read as that
Color, or as "Hybrid"?** This is `Building_GeneAssembler` behaviour in C#, invisible from XML. The
carving fantasy depends on it. If the answer is "Hybrid", I will bring options rather than
improvise.

---

## 4. Hierarchy — Milestone 5 sketch

The closest working vanilla model is `Ideology/Defs/MemeDefs/Memes_GenderSupremacy.xml`, and
`Biotech/Defs/PreceptDefs/Precepts_Xenotype.xml` proves xenotype-conditioned precepts are a
supported combination.

Enforcement mechanisms from the reference that translate into Ideology:

- **Caste-restricted work.** Colors are legally confined to their caste's profession. Precepts
  keyed on xenotype, with thoughts for violation.
- **Prohibited inter-Color reproduction**, enforced by execution. This is the sharpest available
  hook and maps onto `HistoryEventDef` plus precept reaction.
- **Sigils** implanted in the wrists — a `HediffDef` that marks caste, and whose absence or
  falsification is itself detectable.
- **Conditioned belief.** Obsidians were conditioned to regard Golds as divine. This is a
  per-Color precept or thought package, not a global one, which argues for Color-specific
  ideoligion fragments.

**Open question:** should the player's colony be able to *reject* the hierarchy — an egalitarian
ideoligion treating all Colors as equal, taking penalties from Society factions but none
internally? The setting's own arc ends in exactly that, so there is canonical warrant. Still a lore
call, so it is yours.

---

## 4.1 Titles — the Olympic Knights, and how titles should work

The Olympic Knights are an order of thirteen Golds who answer to the Compact rather than to the
Sovereign, held to be the best warriors alive. **After the Second Moon Lord Rebellion the order
split into a Core branch and a Rim branch**, so the Society *and* the Rim Dominion each appoint
their own — which is why the knight pawn kind appears in both factions.

Named knighthoods, each held by one person at a time: **Morning, Rage, Protean, Storm, Wind,
Hearth, Truth, Joy, Death, Cloud, Fear, Love**, plus the **Shadow Knight** standing apart.

### DECIDED — the split

Ruled by the user:

- **Knighthoods → Ideology roles.** There can be only one holder of each knight title, and Ideology
  roles are singular by construction — a role is held by one pawn at a time. That is the mechanic
  the fiction is asking for, and it comes free with a dependency we already have.
- **Gold rank ladder → Royalty titles.** Peerless Scarred, Graduate and Shamed are ranks with
  progression, and `RoyalTitleDef` is built for exactly that. **Royalty therefore becomes a
  dependency** when Milestone 5 begins.

The split is the right shape: Ideology enforces *uniqueness* (one Rage Knight), Royalty enforces
*progression* (Shamed → Graduate → Peerless Scarred).

**Consequence to watch:** Ideology caps roles per ideoligion, and thirteen knighthoods will not fit
alongside the caste roles in a single ideoligion. Likely resolution is that knighthoods belong to
the Society's and the Dominion's own ideoligions rather than to the player's — which is also
canonical, since the order serves the Compact. To be confirmed against the role cap at M5.

Nothing is built either way yet. The knight exists for now as an elite pawn kind
(`RR_Society_OlympicKnight`, combatPower 340 — one is worth more than a whole Society squad).

---

## 4.2 Loadouts — two kits, deliberately incompatible

The equipment splits into a siege kit and a stealth kit, and the apparel layers enforce it.

| | Siege | Stealth |
|---|---|---|
| Body | **pulse armor** — sealed, helmet built in, Middle + Shell + Overhead | **scarabSkin** — tightly fitted, OnSkin + Middle |
| Head | integrated | **demonHelm** — Overhead |
| Over | **starShell** for orbital descent | **ghostCloak** — Shell |
| Worn by | Golds in open battle | the Howlers and other elite units |

Because pulse armor claims Middle, Shell *and* Overhead by itself, it cannot be combined with a
demonHelm or a ghostCloak. That is correct rather than a limitation — it is a sealed suit, and the
choice between the two kits should be a real one.

scarabSkin deliberately sits on OnSkin + Middle so Shell stays free for a cloak and Overhead for the
helm. All three stealth pieces must coexist.

### Built

pulse armor, demonHelm, scarabSkin.

### Not built, and why

- **ghostCloak** — a portable invisibility field, good for short bursts, with a tailbone battery
  that overheats. Vanilla has the mechanism: `HediffCompProperties_Invisibility`, used by
  `PsychicInvisibility` in **Core**, not Anomaly. Doing it properly means apparel granting a
  reloadable ability that applies a timed hediff, following the jump-pack pattern in
  `Odyssey/Defs/ThingDefs_Misc/Apparel_Packs.xml`. That is a real piece of work and faking it with
  unrelated stats would be worse than not shipping it.
- **starShell** — four metres, three tons, flies on built-in gravBoots, launched from SpitTubes,
  modular armament, and immobile without power. That is not apparel; it is a mech. The right base is
  the **Exosuit Framework** (`Aoba.Exosuit.Framework`, workshop 3352894993), which is installed.
  Same framework would carry the **Drachenjäger**.

Both are scoped as their own pass rather than bolted onto Milestone 4.

---

## 5. Factions — Milestone 3 sketch

`Royalty/Defs/FactionDefs/Faction_Empire.xml` is the reference for a stratified faction whose
`pawnGroupMakers` produce visibly different pawns by rank.

Candidate powers, from the reference: the ruling Society; a resistance movement; independent or
exiled powers, of which the setting offers a strong one in the Obsidian offshoot that fled after a
failed revolt and modified itself further in isolation. That gives a natural third pole that is
neither ruler nor rebel.

Detail deferred until Milestone 2 is verified.

---

## 6. Tech tier — Milestone 4 sketch

Above vanilla industrial: energy melee, powered armor, gravity-assisted equipment, implants with a
matching research and production chain. Vertical slice: one melee weapon, one ranged weapon, one
armor set, one implant, behind a custom `ResearchTabDef`.

**Unverified:** whether Odyssey exposes a reusable *personal* gravity mechanic as opposed to
ship-scale only. Checked before Milestone 4.

**Unverified:** the full `techLevel` enum. `Industrial` and `Spacer` confirmed in use; rest
unconfirmed.

---

## 7. Prior art

Two existing Workshop mods cover adjacent ground. Neither blocks this project, but both are worth
knowing about — and both independently chose the full fourteen-Color roster.

| Mod | Approach | Notable |
|---|---|---|
| **Red Rising Conversion** (`3764942376`) | Total conversion. 14 Colors as xenotypes, multiple factions, custom ideoligions, rituals. | Depends on Royalty + Biotech + Ideology, Harmony, Big and Small Framework, Expanded Biotech Style Genes, EyeGenes2 + Facial Animation. Has a Gold "Peerless Scarred" spawn chance and a Gold rivalry system. |
| **Red Rising Xenotypes Conversion** (`3640892677`) | Xenotypes only. Replaces all vanilla xenotypes with the 14 castes, redistributes them across factions, renames the Empire. | Biotech only, plus the same two style-gene dependencies. Save-incompatible by design. |

Points worth taking from them, or deliberately not:

- Both lean on **Expanded Biotech Style Genes** and **EyeGenes2 / Facial Animation** for caste
  appearance. That is the fast route to distinct-looking castes. It is also a hard dependency
  chain. **Recommendation: stay on vanilla Biotech spectrum genes for now**, so the mod runs on
  Core + Biotech + Ideology alone, and revisit once the system works.
- Replacing vanilla xenotypes outright, as the second mod does, is a Milestone 7 decision. Your
  brief already says prefer hiding over removing, since removal breaks saves.
- Neither appears to implement carving as a playable mechanic. Given §3, that is the most
  distinctive thing RimRising can do.

---

## 8b. Resolved by the user — caste name prefixes

Six Colors carry a prefix between given name and family name, each the chemical
symbol of the element the caste is named for:

| Color | Prefix | Element |
|---|---|---|
| Gold | `au` | gold |
| Silver | `ag` | silver |
| Copper | `cu` | copper |
| Blue | `xe` | xenon |
| Green | `si` | silicon |
| Gray | `ti` | titanium |

**The omissions carry the meaning.** Red, Pink and Obsidian have no prefix because
the Society files them as property rather than as people — leaving them plain says
the same thing the prefix says, in reverse.

White, Yellow, Violet, Orange and Brown have none in the reference either, and are
left plain rather than given invented symbols. A fabricated caste marker would read
as canon to anyone who did not know better, which is worse than an absence. This
closes the "invent, or leave prefix-less?" question with: leave them.

Implemented as `RulePackDef` name makers in `Defs/RulePackDefs/`, attached to the
nine xenotypes that carry a prefix (the six Colors plus Bronzie, Lurcher and Fulgur
Bellator, which follow their parent Color). `chanceToUseNameMaker` is 1: the prefix
is not decoration.

**No character name from the books is used.** Given names are ordinary historical
Latin and Greek forms; family names are assembled from syllables. Only the
convention is borrowed, and a convention is a rule rather than an asset.

Noted for later: characters who join the Rising abandon the prefix, and Reds take
birthplace surnames instead. That is a per-faction naming rule rather than a
per-Color one, so it belongs with the Sons of Ares rather than here.

---

## 8c. Resolved by the user — Pink

Pinks are a lowColor and the **second-lowest caste**, above Red only. The ladder was
corrected for this: Brown 120, Pink 130, Red 140. Rose follows its parent at 132.

The Society files them as **property, bought rather than employed**. RimWorld already
models that through Ideology's slavery, so nothing needed inventing and nothing
needed depicting.

What the Gardens actually train is emotional read — body language, empathy,
detecting a lie — which is why the Solar Republic later used Pinks as field lie
detectors when equipment was unavailable. That is the part of the caste that is
expressible in this game, and it is what the pawn kind reflects: Social 13–20,
Artistic, and Melee floored at 0–2.

Physiology from the reference, already carried by the xenotype: bred for beauty and
correspondingly fragile — `Beauty_Beautiful`, `Delicate`, `Pain_Extra`,
`MeleeDamage_Weak`. Added on this pass: **`Sterile`**, because Pinks under the
Society are chemically sterilised and new generations come out of breeding tubes.

**Roses** are the rare, ruinously expensive tier, which the reference puts on a par
with a Stained Obsidian. Weighted at 0.4 against the ordinary companion's 3.

Not modelled, deliberately: **Cupid's Kiss**, the conditioning implant that inflicts
constant pain until a Pink obeys. It is expressible — it is just a hediff — but it is
a torture device fitted to children, and putting a working version of it in a colony
sim is a different thing from describing it in a wiki. Left out unless the user asks.

Adult content stays out of the base mod entirely; the RimJobWorld integration remains
optional and unbuilt.

---

## 8. Open questions for the user

### Resolved in play

1. **Roster: 14 or the original 10?** — **14**, and it grew: Bronzie plus six sub-strains, 21
   xenotypes in all.
2. **May the player reject the hierarchy?** — **Yes.** `RR_ColorEquality` is a first-class meme, and
   both scenarios state that playing against your birth Color's expected ideoligion is the more
   interesting game rather than a mistake.
3. **Should Gold carry a real engineered flaw?** — **No physical weakness.** The direction given was
   that Gold is flawed only in being few and slow to reproduce. Implemented as `RR_Fertility_Reduced`
   plus a complexity cost of 49, with no capability penalty.

### Still open

4. **Prefixes for the five Colors with none established.** Invent them, or leave those Colors
   prefix-less? Purely a setting call. Leaving them absent is self-consistent — not every caste needs
   a naming particle — but it does read as incomplete beside the ones that have one.
5. **Pink's framing.** What is currently built is option one: a social-functionary caste, no adult
   content in the base mod, anything explicit confined to a gated compat folder that does not yet
   exist. That keeps the base mod shippable to anyone. Confirm, or make it more pointed.
