---
name: newdef
description: Draft a new RimWorld def for RimRising the project's way - open a real vanilla or working-mod def of the same type first, mirror its field set, cite the source in the file header, and run the validator. Use this whenever the user wants anything new in the mod that is XML - a gene, xenotype, pawn kind, faction, precept, meme, recipe, hediff, implant, apparel, weapon, animal, plant, drug, backstory, name pool, biome, scenario, title, trader, quest or patch - and whenever an existing def needs a field it does not have yet. Trigger on phrases like "add a", "make a", "create a", "new def", "give the Society a", "I want a flower/animal/armour/gene that", even when the word "def" never appears. If the request is C# rather than XML, still start here to settle the def side, then stop and ask before writing source.
---

# /newdef

The rule that matters most in this project, from CLAUDE.md: **verify, never recall.** Before
writing any def, open a vanilla def of the same type and mirror its structure. If you cannot
find a real example of a field, do not use the field. Every false green in `docs/PROGRESS.md`
came from a field or a value that looked right and had never been seen in a working file.

This skill is that rule as a procedure.

## 1. Name the type and its nearest working example

Decide the def type (`ThingDef` with `<plant>`, `GeneDef`, `PreceptDef`, and so on) and the
vanilla thing it is closest to in play, not in fiction. A pitviper is a cobra; a Carver's kit
is medicine; a razor is a monosword. That analogue's def is the template.

Then find it, in this order:

1. **A def this mod already has of the same type.** It was mirrored once and has loaded, and
   its header says what it was mirrored from. `references/sources.md` lists our file per type.
2. **The vanilla file.** `<install>\Data\{Core,Royalty,Ideology,Biotech,Anomaly,Odyssey}\Defs\`.
   `references/sources.md` gives the path per type where the project has already cited one.
   For anything else, run `scripts/Find-VanillaDef.ps1 -DefName Cobra` or
   `-DefType ThingDef -Contains "<plant>"`; it greps the install and prints file and line.
3. **In the cloud, where the game is not on disk:** shallow-clone a public mod that works on
   1.6 and mirror its use of the field. CLAUDE.md "In a cloud session, working mods on GitHub
   stand in for vanilla defs" lists the ones used so far and the clone command.

Read the whole template def, not the first twenty lines. The field that bites is usually near
the bottom.

## 2. Mirror, do not compose

Copy the template's field set and change values. Resist adding a field from memory because it
"should" exist; grep the template's file for it first, and if it is not there, grep the rest of
that DLC's Defs folder. A field seen nowhere is a field that does not load, or loads and does
nothing, and both are silent.

Where a value is a reference to another def (a `ThingDef`, a `HediffDef`, a sound, a body part
group, a tool capacity), confirm that def exists by name in vanilla or in a declared dependency.
`Test-ModDefs.ps1` checks `RR_` references and vanilla defNames, so a typo will be caught, but
only if you run it.

## 3. Follow the project's own conventions

These are the ones that have cost a round each. Full detail is in CLAUDE.md under the quoted
headings.

- **`RR_` prefix on every defName we own**, and every texture leaf we own starts `RR_`. The
  tooling keys off this.
- **Files mirror vanilla's layout**: `1.6/Defs/<VanillaFolderName>/`. Vanilla splits animals,
  plants, items, buildings and races into their own folders; so do we. The only deliberate
  exception is implants, which stay a triad in one file ("Implants are a triad in one file").
- **Collection graphics take a folder**, `Graphic_Random` and `Graphic_StackCount` especially
  ("Collection graphics resolve texPath as a FOLDER"). Pawn body graphics are directional;
  declare `graphicClass Graphic_Multi` inside `bodyGraphicData` so the tooling can see it.
- **Optional content is gated**, with `MayRequire` / `MayRequireAnyOf` on the node or by living
  in a folder `LoadFolders.xml` gates. A def that names a gated def ungated is an error.
- **Under Combat Extended, every `<tools>` entry must become a `ToolCE`** via a
  `PatchOperationReplace` in `1.6/Mods/CombatExtended/Patches/`. Guns included. The validator
  fails on this (`CEToolsUnpatched`).
- **Precepts need `requireOne` on the meme** to be guaranteed, and a `requireOne` group can be
  unsatisfiable. The validator has both checks.
- **Pawn kinds redeclare `apparelTags` with `Inherit="False"`**, because list fields merge
  on inheritance. Pin the Color with `xenotypeSet` and the bio with `backstoryFiltersOverride`.
- **Xenotype budgets live on genes.** After touching a gene list, run
  `pwsh -File Tools/Get-XenotypeBudget.ps1` and check metabolism is within -10..5 and the
  complexity change is intended.
- **Vehicles and implants are triads** whose halves point at each other.
- **No book names, no book prose.** Setting terms are fine; descriptions are original.
- **Lore calls go to the user.** If a value is a setting judgement rather than a technical
  one, put options in the report and do not pick.

## 4. Write the header

Every def file in this mod opens with a comment that says what it is, what it was mirrored
from (file path), what was verified and what was not, and why any number is what it is. Mirror
the header style of a neighbouring file. A future session reads that header before it reads
the def; it is where "this field is unverified" has to live so it does not become a false
green later.

## 5. Validate and hand over

Run `/validate`. Then add to `docs/PROGRESS.md` the exact steps to verify the def in game:
what to spawn or build, what should appear, and what in the log would mean it failed. The
project's agreement is that a def is not done until it has loaded with zero red errors, and
that the person launching the game is told what to click.

## Example

Request: "add a sea-cave moss the Obsidian tribes eat."

1. Type: `ThingDef` with `<plant>`, harvested for food. Nearest vanilla analogue: a wild
   berry bush or, closer, Biotech's cave fungus. Our own nearest file:
   `1.6/Defs/ThingDefs_Plants/Plants_RimRising.xml` (haemanthus), header cites VPE More
   Plants and Alpha Biomes' cave plants.
2. Open the haemanthus def and, if on the game machine, the vanilla fungus def. Copy the
   plant block; change `harvestedThingDef`, `harvestYield`, `growDays`, `growMinGlow`,
   `fertilityMin`. Do not add `sowResearchPrerequisites` unless the template has it.
3. `Graphic_Random`, so `Things/Plant/RR_SeaMoss/` is a folder of `_a/_b/_c`.
4. Wild only on the biome the tribes live on: edit that `BiomeDef`'s `wildPlants`, which we
   own, rather than putting `wildBiomes` on the plant.
5. Header: mirrored from X; `growMinGlow 0` seen in Alpha Biomes; yield numbers set
   relative to vanilla berries. Then `/validate` and the PROGRESS steps.
