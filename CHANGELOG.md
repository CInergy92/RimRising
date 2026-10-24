# Changelog

## Unreleased

- Fixed: drafting several pawns at once could stop pawns from drawing and flood the log with
  "Operations that change non-concurrent collections must have exclusive access". The pulse-helm
  check kept a cache that RimWorld's parallel pawn drawing wrote from several threads at once.
- The Obsidian face mark is now a chevron on the brow. The old band across the eyes looked like a
  blindfold and spilled past the edge of the head.
- duroArmor fits Fat and Hulk bodies: the cuirass and belt now follow the body down to the belt,
  where before a narrow plate sat on the belly with the body bulging past it.

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
