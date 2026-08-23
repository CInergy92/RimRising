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

## 8. Open questions for the user

None block Milestone 1.

1. **Roster: 14 or your original 10?** §2.1. My recommendation is 14.
2. **Prefixes for the five Colors with none established** — invent, or leave prefix-less? §2.4.
3. **Pink's framing.** Mechanically: a social-functionary caste with no adult content in the base
   mod and RJW-specific content confined to the gated folder, or something more pointed. Option one
   is what I would build absent direction, since it keeps the base mod shippable.
4. **May the player reject the hierarchy?** §4.
5. **Should Gold carry a real engineered flaw**, or pay only in complexity? The reference gives Gold
   no meaningful physical weakness, which argues for complexity-only — but that makes Gold strictly
   better in play, which may not be what you want from a game.
