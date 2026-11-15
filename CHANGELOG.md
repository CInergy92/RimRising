# Changelog

## Unreleased

- New scenario, **The Quota (campaign)**: a story told in acts. Four Reds on a helium claim are set
  a quota; meeting it or not, the Laurel goes elsewhere, and what follows is a reprisal, an offer
  from the Sons of Ares, a Red carved Gold with a sigil that no longer matches, the Lurchers that
  come for it, recruits, the garrison, and an Iron Rain. After the Rain comes a short epilogue -
  Reds from other claims, a merchant house's offer, a price on the stranger - and a last choice
  of what the claim becomes: a free clan, an ally of the Sons of Ares, or under the Rim Dominion's
  protection. Each act waits for its own condition, never a calendar. The turning points are accept-or-refuse letters: refusing the stranger ends
  the story quietly and the colony plays on as a sandbox. The other four scenarios are unchanged,
  and the campaign does nothing in them or in existing saves.
- Fixed: a pawn BORN a Color and carved into another with the Carver's surgery still read as its
  birth Color - to the razor lock, the title ladders, the armour lock and the sigil check alike.
  A Red carved Gold now reads as Gold. (Carving a Baseliner already worked.)

## 1.0.1 - 2026-10-24

- Fixed: drafting several pawns at once could stop pawns from drawing and flood the log with
  "Operations that change non-concurrent collections must have exclusive access". The pulse-helm
  check kept a cache that RimWorld's parallel pawn drawing wrote from several threads at once.
- The Obsidian face mark is now a chevron on the brow. The old band across the eyes looked like a
  blindfold and spilled past the edge of the head.
- duroArmor fits Fat and Hulk bodies: the cuirass and belt now follow the body down to the belt,
  where before a narrow plate sat on the belly with the body bulging past it. On Female it gains
  riveted steel tassets over the hips, which flared out below the bare cuirass.

## 1.0.0 - first public release

The first Steam Workshop release, after a several-week playtest.

- Fourteen Colors as inheritable xenotypes, plus Bronzies and six sub-strains (21 in all), with a
  caste ladder the game enforces: caste labour, deference and caste marks.
- Carving by Violet Carvers: regrowing limbs, removing scars, restoring fertility, and remaking a
  person into another Color.
- Razors with a whip form; pulse armour with a sealed helm that closes when drafted; recoil
  armour, scarabSkin, the demonHelm, ghost cloak, Howler pelt, gravBoots, skipBoots and the aegis.
- Seven factions, three memes, the Society's two title ladders and the Rim Dominion's own, four
  scenarios, two biomes, the Board of Quality Control storyteller and the Lurcher hunt.
- Griffins, pitvipers and the haemanthus; the clawDrill; helium-3 as a deep resource.
- Optional support for Combat Extended, Vehicle Framework (Drachenjaeger, ripWing), Exosuit
  Framework (starShell), Alpha Animals, Melee Animation, Realistic Body, Giddy-Up 2, Dragons
  Descent and Odyssey.
- Supports RimWorld 1.6; loads and passes its tests on 1.7 (1.7.4985).
- AI usage is disclosed in the description and asset by asset in `About/AI_DISCLOSURE.txt`.
