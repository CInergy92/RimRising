# RimRising

A total conversion for **RimWorld 1.6 and 1.7** built around an engineered caste hierarchy: fourteen Colors,
each an inheritable xenotype with its own capabilities and costs, held together by a social order
the game actually enforces.

An unofficial fan work inspired by Pierce Brown's *Red Rising* novels. Not affiliated with or
endorsed by the author or his publishers. No text or artwork from the books is reproduced.

## What it adds

- **The Colors** — fourteen xenotypes plus Bronzies and six sub-strains, ranked on an enforced ladder.
- **Carving** — a Violet Carver can regrow lost limbs, repair scarring, rebuild fertility for
  cross-Color reproduction, or rebuild a person into another Color. Only a Violet may do any of it.
- **Equipment** — razors (with a whip form), pulse and recoil armour with an automated trauma suite,
  gravBoots that launch across the world map, the aegis, pulseFist and scorcher.
- **Society** — seven factions, three ideoligion memes with their precepts, two caste-locked title ladders, a storyteller.
- **Drugs** — zoladone, mjolnir-6, nazopran, god's bread and fever cloud.
- **World** — three scenarios and two biomes.

## Requirements

- RimWorld **1.6 or 1.7** with **Royalty, Ideology and Biotech**.
- Required mods (RimWorld lists any that are missing): Harmony, Vanilla Expanded Framework,
  [NL] Facial Animation, [BT] EyeGenes2, Expanded Biotech Style Genes AiO, EBSG Framework,
  Alpha Genes, Expanded Archite Genes, Biotech Capacitor Genes, Lifespan Expectancy Genes.

### Optional

Each is loaded only if you already run it; nothing else changes without it.

| Mod | Adds |
|---|---|
| Combat Extended | CE stats for the weapons, the vehicle turrets, and pulse armour, demonHelm and scarabSkin (the remaining armour pieces are not yet CE-patched) |
| Exosuit Framework | the starShell |
| Vehicle Framework | the Drachenjäger |
| Alpha Animals | Carvelings, grown in Carver vats |
| Melee Animation | idle, attack and execution animations for both razors |

### Extras: Cinergy's CE Patches (local)

`Extras/CinergyCEPatches` is a **separate mod**, kept in this repo but not part of RimRising and
not published with it. It patches third-party mods for Combat Extended where CE does not, or
where CE's own patch leaves a crash:

| Mod | What is patched |
|---|---|
| MUGB Goblin | melee tools as CE tools; armour, helmets and shields in CE units; Bulk; the crossbow, repeating crossbow, warbow and staff sling made CE weapons (they crashed on every shot) |
| Mutagen and Mutation | melee tools; its five gas clouds recategorised so CE's gas check stops crashing every pawn inside one |
| Petification | its seven impact weapons; collar and mask armour in CE units |
| RimJobWorld - Gasses | the four launchers' stock and barrel attacks |
| Big and Small - Genes & More | the giant sword only (the rest is already CE-patched) |
| VFE Classical | the handheld scorpion fires CE's scorpion bolts (CE's own patch left it crashing) |
| Unlimited Cumworks | the three guns' grip and barrel attacks |
| High Heels of Rim | all 13 heels' armour in CE units |
| RJW Menstruation Cycle | the two absorber pads' armour |
| Big and Small - Framework, RJW Genes | natural armour granted by a hediff, at CE's own race scale |

Each patch applies only when its target mod is active; CE is required. Supports 1.6 and 1.7
(checked on 1.7.4980). To install, link or copy the folder into `RimWorld/Mods` and enable
"Cinergy's CE Patches (local)". After a target mod updates, regenerate the generated files with
`python Extras/CinergyCEPatches/Tools/gen_patches.py`; the `*_Ranged`, `*_Gas`, `*_Scorpion` and
`CE_PawnArmourHediffs.xml` files are hand-written.

`rrtestmode=cetools` audits a whole load order: it lists every weapon without CE tools, then makes
every pawn-equippable weapon fight or fire and names any that throws. `Tools/audit_report.py`
turns the log into a per-mod report; the latest is `Extras/CinergyCEPatches/AUDIT.md`.

## Install

Subscribe on the Steam Workshop, or copy this folder's shipped content into
`RimWorld/Mods/RimRising`. Load it after everything in the requirements list.

## Troubleshooting

The log is at
`%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log`.
`Tools/Get-ModLoadErrors.ps1` extracts only the errors that concern this mod; most red text in a
large mod list belongs to someone else.

## Development

Tooling lives in `Tools/` and runs from the repo root. Most of it is PowerShell 7; the worn-armour,
weapon and tweak-data drawing scripts are Python (`Draw-PanelArmor.py`, `Draw-Weapons.py`,
`Derive-MeleeTweak.py`, the two run inside Blender for its bundled numpy).

```powershell
pwsh -File Tools/Test-ModDefs.ps1     # validate every def; exit 1 on any error
pwsh -File Tools/Publish-Mod.ps1      # validate, then mirror the shipped content into Mods/
python3 Tools/Check-ModDefs.py        # cloud fallback: no game install needed, cannot see vanilla
```

Two Claude Code project skills live in `.claude/skills/`: `/validate` runs the tooling above and
turns the report into a fix list, and `/newdef` is the "open a vanilla def of the same type first"
rule as a procedure, with a per-type table of what to open.

`Source/RimRising` holds the C# assembly. `CLAUDE.md` records every verified engine convention
the project relies on, `docs/DESIGN.md` the content design, and `docs/PROGRESS.md` milestone status.

## Credits

Built with Claude Code (Anthropic). Items, weapons, worn apparel, animals, plants, icons and
terrain are drawn procedurally by scripts in `Tools/` (`Draw-Items.py`, `Draw-Weapons.py`,
`Draw-Ranged.py`, `Draw-PanelArmor.py`, `Draw-Nature.py` and others). The starShell exosuit was
generated with fal (fal.ai) using `openai/gpt-image-2` and `fal-ai/nano-banana-2/edit`, then cut
out, greyscaled and outlined by `Tools/Clean-GenStarShell.py`; prompts and request ids are in
`Art/Gen/StarShell/fal_manifest.jsonl`. Preview and storyteller art was generated locally with
Z-Image-Turbo and a ControlNet in ComfyUI. Sound effects generated with fal using
`fal-ai/elevenlabs/sound-effects/v2`; prompts and request ids are kept in
`Art/Sounds/candidates/fal_manifest.jsonl`.

Thanks to the authors of every required mod, and to Epicguru for Melee Animation.
