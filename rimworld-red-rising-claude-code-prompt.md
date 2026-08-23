# Claude Code Prompt: Red Rising Total Conversion for RimWorld

Fill in the CONFIG block, then paste the whole thing as your first message in an empty repo.

---

## CONFIG (fill in before pasting)

```
GAME_INSTALL:     <D:\SteamLibrary\steamapps\common\RimWorld>
MODS_FOLDER:      <...\RimWorld\Mods>
DLC_OWNED:        Royalty / Ideology / Biotech / Anomaly / Odyssey
TARGET_VERSION:   detect from install, do not assume
MOD_PACKAGE_ID:   cinergy92.redrising
C_SHARP_ALLOWED:  yes
ART_PLAN:         placeholder art now, real art later
SCOPE_TARGET:     playable vertical slice first, full conversion after
```

---

## PROMPT

You are helping me build a Red Rising themed total conversion mod for RimWorld. I am an experienced systems engineer and PowerShell developer, new to RimWorld modding. Treat me as technically fluent but do not assume I know RimWorld's XML schema, and do not assume you know it either.

### Phase 0: Discovery, before you write any mod content

Do this first and report back. Do not skip to content.

1. Read `GAME_INSTALL/Version.txt` and confirm the exact game version. Every decision after this is version specific.
2. Inventory the def types actually present in `GAME_INSTALL/Data/Core/Defs/` and each DLC's `Defs/` folder. List the def types relevant to this project and the file path of the best vanilla example of each.
3. Inspect two or three existing total conversion or large content mods in `MODS_FOLDER` if any are installed. Report how they structure `LoadFolders.xml`, `About.xml`, and their patch strategy.
4. Report which parts of my design require a DLC I own, which require one I do not own, and which can be done in vanilla XML.
5. Tell me what you cannot verify and what you need from me.

Write findings to `docs/DISCOVERY.md` before proceeding.

### Hard rules for the whole project

- **Verify, never recall.** Before writing any def, open a vanilla def of the same type in the game's Data folder and mirror its structure. If you cannot find a real example of a field, do not use the field. State when you are guessing.
- **No invented XML.** RimWorld silently ignores unknown nodes and throws cryptic errors at load. Every node you write must trace to a vanilla example or to the decompiled `Assembly-CSharp.dll` class it maps to.
- **No copyrighted text or assets.** Do not copy passages, character dialogue, or artwork from the Red Rising books or any other source. All descriptions and flavor text must be original writing that evokes the setting. Names of concepts and factions are fine; verbatim prose is not.
- **Incremental and testable.** Nothing is done until the game loads it with zero red errors in the debug log. After every module, tell me exactly what to click in game to verify it.
- **Ask before scope changes.** If a design item turns out to require C# when I said XML only, or a DLC I do not own, stop and ask instead of substituting something.

### Repo layout

Set this up in Phase 1:

```
/Source/            C# project, if used
/1.x/               version specific folders driven by LoadFolders.xml
  Defs/
  Patches/
  Assemblies/
/About/             About.xml, Preview.png, ModIcon.png
/Textures/
/Sounds/
/Languages/
/Tools/             PowerShell build and validation scripts
/docs/              DISCOVERY.md, DESIGN.md, PROGRESS.md
CLAUDE.md
```

`About.xml` must declare `packageId`, `supportedVersions`, and explicit `modDependencies` plus `loadAfter` entries for every DLC the mod requires.

### Tooling, written in PowerShell

I write PowerShell, so build tooling goes in `/Tools` as `.ps1`, not Python or batch.

1. `Test-ModDefs.ps1`: parse every XML file under `Defs/` and `Patches/`, and fail on malformed XML, duplicate `defName` values, `defName` values that collide with vanilla defs, texture paths referenced in defs that have no matching file under `Textures/`, and `parentName` references to abstract defs that do not exist.
2. `New-PlaceholderTextures.ps1`: generate flat colored PNG placeholders at correct RimWorld dimensions for every texture path a def references but does not have, so the mod is playable before art exists.
3. `Publish-Mod.ps1`: copy the built mod into `MODS_FOLDER`, excluding `/Source`, `/docs`, and `.git`.
4. `Get-ModLoadErrors.ps1`: read the RimWorld player log and surface only the red errors attributable to this mod's packageId.

Run `Test-ModDefs.ps1` before telling me anything is finished.

### Build order

Do not build these in parallel. Finish and verify each before starting the next.

**Milestone 1, skeleton.** `About.xml`, `LoadFolders.xml`, folder structure, one trivial `ThingDef`. Success: mod appears in the mod list, game loads, item is spawnable in dev mode.

**Milestone 2, the Color system.** This is the spine of the mod. Map the Society's Colors to Biotech xenotypes plus supporting genes, one `XenotypeDef` per Color, with genes expressing each Color's engineered specialization and its costs. Include the metabolic and complexity budgeting so xenotypes are balanced against vanilla ones. Success: I can start a scenario and see the xenotypes, and pawn generation produces them correctly.

**Milestone 3, factions and pawn kinds.** `FactionDef` per major power, with `PawnGroupMaker` entries, `PawnKindDef` per Color and role, tech level, and relations. Success: factions generate on the world map, raids arrive with correct pawns, apparel and weapons resolve without missing texture errors.

**Milestone 4, tech and equipment.** Weapons, armor, and implants as `ThingDef` plus `RecipeDef` plus `HediffDef` where implants are involved, gated behind a custom research tree with its own `ResearchTabDef`. Start with a small vertical slice: one melee weapon, one ranged weapon, one armor set, one implant. Success: craftable, equippable, functional in combat.

**Milestone 5, ideology and hierarchy.** If Ideology is owned, express the caste hierarchy as memes, precepts, roles, and thoughts. This is where the setting's social structure lives, so give it real mechanical weight rather than cosmetic labels.

**Milestone 6, scenarios and world.** `ScenarioDef` entries for distinct starts on opposite ends of the hierarchy. World generation adjustments, biomes, and any faction placement rules.

**Milestone 7, vanilla suppression.** Only now decide what vanilla content to hide or remove, using `Patches/` with `PatchOperation` and xpath, never by editing game files. Prefer hiding over removing, since removal breaks saves and other mods.

### Working agreements

- Maintain `CLAUDE.md` with the verified XML conventions you discovered, the def types in use, the naming scheme for `defName` values, and anything you got wrong once so you do not repeat it.
- Maintain `docs/PROGRESS.md` with milestone status, open questions, and known errors.
- Commit per logical unit with a message naming the milestone.
- `docs/DESIGN.md` holds the content design. I am the authority on the setting. When a design decision is a lore judgment call rather than a technical one, put the options to me instead of picking.

### Content design starting point

I will refine this, treat it as a first draft to react to, not a spec.

- The Color hierarchy is the central mechanic: engineered castes with distinct capabilities, hard social stratification, and severe consequences for pawns who cross caste lines.
- Reds as the labor base, Golds as the ruling caste, Obsidians as engineered warriors, Grays as enforcers, pinks as pleasure slaves (using Rimjobworld), and the specialist Colors filling engineering (orange), medicine(yellow), piloting(blue), and finance roles(silver), and religious/diplomacy(white).
- Tech tier sits above vanilla industrial: energy melee weapons, powered armor, gravity assisted equipment, and implants that require a matching research and production chain.
- Factions should include the ruling order, the resistance, and independent or exiled powers, with relations that make the hierarchy legible in gameplay.
- Would like it to eventually work with Combat Evolved and thinking of other mods it can work with.

Start with Phase 0 now. Report findings before writing any mod content.
