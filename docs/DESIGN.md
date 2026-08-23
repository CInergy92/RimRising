# DESIGN — Red Rising

Content design. **The user is the authority on the setting.** Where a decision is a lore judgment
call rather than a technical one, this document presents options rather than picking one.

Original writing only. Concept and faction names are used as terminology; no prose, dialogue, or
imagery is taken from any published source.

---

## 1. Decisions locked

Ruled on by the user, 2026-08-23:

| Decision | Ruling |
|---|---|
| Color inheritance | **Colors are inheritable.** Two parents of a Color produce a child of that Color. |
| Crossing Colors | **Possible, but very difficult.** A pawn can be carved into a higher Color. This must be a real undertaking, not a menu click. |
| Roster scope | **All ten Colors up front**, so the full shape of the system is visible as a baseline before tuning. |
| RimJobWorld | **Optional, never required.** RJW content lives in a gated folder. The base mod is complete and coherent without it. |
| Dev environment | Build against what the mod needs, not the user's full 151-mod list. Integrations are added deliberately. |

---

## 2. The Color system

### 2.1 How it maps onto Biotech

Each Color is one `XenotypeDef` with `<inheritable>true</inheritable>`, carrying 8 to 14 `GeneDef`s
that express its engineered specialization *and its engineered costs*. A Color that is purely an
upgrade is a design failure — the hierarchy is only legible if every caste is visibly built for a
purpose and crippled outside it.

### 2.2 Balance anchors — computed from vanilla

Summed `biostatCpx` across each vanilla xenotype's genes, resolving template-generated genes
(`AptitudeRemarkable_Mining` and similar) back to their `GeneTemplateDef`:

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

**Caveat, stated plainly:** the template resolution is my own inference from
`GeneTemplateDefs.xml`, not something the game exposes. Treat the *ordering* as reliable and the
*exact figures* as provisional until checked against the in-game gene assembler at Milestone 2.

What this gives us regardless of the exact numbers:

- Ordinary vanilla xenotypes cluster in a **2 to 11 complexity band**. Most Colors belong there.
- **Sanguophage at 41 is the outlier ceiling**, and it is deliberately not something you casually
  become.
- That outlier is the design space for Gold. See §3.

### 2.3 The ten Colors — first draft

This is a draft to react to, not a spec. Specializations follow the user's starting brief.

| Color | Role | Built for | Built to fail at | Target cpx |
|---|---|---|---|---|
| **Red** | Labor base | Mining, physical endurance, tolerance of heat and confinement | Social standing, education-gated work | low, 2–4 |
| **Gold** | Ruling caste | Leadership, melee, physical and cognitive ceiling | Nothing much — the cost is paid in complexity, not weakness | high, 20+ |
| **Obsidian** | Engineered warriors | Melee damage, pain tolerance, body size | Intellectual work, social work | mid-high, 10–14 |
| **Gray** | Enforcers | Shooting, discipline, steady aggression | Creative and intellectual work | mid, 6–9 |
| **Pink** | Coerced service caste | Social, beauty, empathy read | Violence, hard labor | mid, 6–9 |
| **Orange** | Engineering | Crafting, construction, machine intuition | Social, animals | mid, 6–9 |
| **Yellow** | Medicine | Medical, intellectual, steady hands | Combat of any kind | mid, 6–9 |
| **Blue** | Piloting | Reflex, spatial reasoning, low-gravity tolerance | Physical labor, melee | mid, 6–9 |
| **Silver** | Finance and logistics | Trade, negotiation, intellectual | Physical work | mid, 5–8 |
| **White** | Ritual and arbitration | Social, artistic, ideological authority | Physical work, violence | mid, 5–8 |

**Open question for the user (lore, not technical):** Pink is the one entry where the source
material's framing is explicitly coercive. Mechanically it can be built as (a) a service caste with
social and beauty genes and no sexual content at all in the base mod, with RJW-specific content
confined to the gated folder, or (b) something more pointed. Option (a) is what I would build
absent direction, since it keeps the base mod shippable and puts the adult content behind the RJW
gate you already asked for. Confirm or redirect.

---

## 3. Carving — crossing Colors

The user's ruling: possible, but very difficult.

### 3.1 Vanilla already does most of this

Verified in `Biotech/Defs/RecipeDefs/`:

- `ImplantXenogerm` is a real surgery (`workerClass` `Recipe_ImplantXenogerm`).
- Its `SurgeryOutcomeEffectDef` includes `SurgeryOutcomeComp_XenogermComplexity`, whose curve runs
  from `(0, 1)` to `(20, 0.6)` — **success chance falls as xenogerm complexity rises.**
- Failure applies `XenogerminationComa`, up to 3 days.

So if Gold sits above 20 complexity, carving into Gold is *already* the most dangerous surgery in
the game, using nothing but vanilla machinery and our own gene budget. The difficulty the user
asked for falls out of the design rather than being bolted on.

### 3.2 Inheritance behaves correctly by accident

This is the part worth pausing on.

- `inheritable` xenotypes pass on **endogenes** — the genes a pawn is born with.
- Xenogerm implantation grants **xenogenes**, which are **not** inherited.

Therefore a carved pawn's children inherit their **birth** Color, not the carved one. A Red carved
into a Gold does not found a line of Golds. That is exactly right for the setting, and it costs us
nothing to implement — it is simply what Biotech already does.

### 3.3 Gating the difficulty further

Layers available in pure XML, in the order I would add them:

1. **Complexity cost** — free, described above.
2. **Research gate** — carving requires a late project on our own `ResearchTabDef`.
3. **Ingredient cost** — the recipe demands materials that are themselves gated behind the tech
   chain, not just 4 medicine.
4. **Ideoligious consequence** — a `HistoryEventDef` raised on carving, with precepts that make the
   Society's members react badly to it.

Layer 4 is where **the one known C# risk** sits: I have not verified that vanilla raises a history
event on xenogerm implantation. If it does not, raising one needs a Harmony patch. I will check
before Milestone 5 and ask before writing any C#.

### 3.4 Unverified, must be tested at Milestone 2

**Does implanting a xenogerm assembled from an exact Color gene set make the pawn read as that
Color, or as "Hybrid"?** This is `Building_GeneAssembler` behaviour in C#, invisible from XML. The
whole carving fantasy depends on the answer. If the game says "Hybrid", we need a different
approach and I will bring options rather than improvise.

---

## 4. Hierarchy — Milestone 5 sketch

The closest working vanilla model is `Ideology/Defs/MemeDefs/Memes_GenderSupremacy.xml`: one group
is innately superior, with precepts, thoughts, and role restrictions that give it mechanical
weight. `Biotech/Defs/PreceptDefs/Precepts_Xenotype.xml` proves xenotype-conditioned precepts are
a supported vanilla combination.

Planned shape, to be detailed when Milestone 5 starts:

- A **Color Supremacy** meme establishing that the hierarchy is natural and correct.
- Precepts keying off xenotype for standing, permitted work, permitted apparel, and permitted
  weapons.
- Roles restricted by Color, using the `Precepts_Role.xml` pattern.
- Thoughts for being commanded by a lower Color, for a Color working outside its caste, and for
  witnessing a carving.

**Open question for the user:** should the player's own colony be *able* to reject the hierarchy —
an egalitarian ideoligion that treats all Colors as equal, taking mood penalties from Society
factions but none internally? That is a significant statement about what the mod is for, and it is
a lore call, so it is yours.

---

## 5. Factions — Milestone 3 sketch

Per the brief: the ruling order, the resistance, and independent or exiled powers.

`Royalty/Defs/FactionDefs/Faction_Empire.xml` is the reference for a stratified faction whose
`pawnGroupMakers` produce visibly different pawns by rank. Relations should make the hierarchy
legible on the world map before the player reads a single description.

Detail deferred until Milestone 2 is verified.

---

## 6. Tech tier — Milestone 4 sketch

Above vanilla industrial: energy melee, powered armor, gravity-assisted equipment, implants with a
matching research and production chain.

Vertical slice, per the build order: one melee weapon, one ranged weapon, one armor set, one
implant, behind a custom `ResearchTabDef`.

**Unverified:** whether Odyssey exposes a reusable *personal* gravity mechanic, as opposed to
ship-scale only. `Odyssey/Defs/ThingDefs_Buildings/Buildings_Gravship.xml` exists but has not been
read. If there is no personal mechanic, gravity equipment becomes either stat-bonus apparel (XML,
straightforward) or a C# comp (needs sign-off). I will check before Milestone 4.

**Unverified:** the full `techLevel` enum. `Industrial` and `Spacer` are confirmed in use in
`Core/Defs/FactionDefs/Factions_Misc.xml`; the rest is unconfirmed and will be checked before
faction tech levels are set.

---

## 7. Open questions for the user

Carried forward, none blocking Milestone 1:

1. **Pink's framing** — §2.3.
2. **Whether the player may reject the hierarchy** — §4.
3. **Color roster** — is the ten-way split in §2.3 right in its specializations, or are any of the
   role assignments wrong for the setting?
4. **Gold's cost** — Gold as drafted pays for its ceiling in complexity rather than in weakness.
   Is that right, or should Golds carry a real engineered flaw?
