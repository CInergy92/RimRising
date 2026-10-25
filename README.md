# RimRising

**[Get it on the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3826500705)** - or download the mod folder from the [latest release](https://github.com/CInergy92/RimRising/releases/latest).

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
| Combat Extended | CE stats for every weapon, armour piece and vehicle turret |
| Exosuit Framework | the starShell |
| Vehicle Framework | the Drachenjäger walker and the ripWing aerial fighter |
| Alpha Animals | Carvelings, grown in Carver vats |
| Melee Animation | idle, attack and execution animations for the razors |
| [NL] Realistic Body | armour sprites with greaves for its body shapes |
| Giddy-Up 2 - Continued | rideable griffins; Obsidian raiders ride them |
| Dragons Descent | its dragons retold as Carver-made (descriptions only) |
| Odyssey | gravships burn helium-3 |

## Install

Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3826500705), or copy this folder's shipped content into
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

## Credits and AI disclosure

A love letter to Pierce Brown's Red Rising saga, from a massive fan. Thank you, Pierce Brown, for the Society, the Institute, the Rising and every Color in between - for books that took a Red from the mines of Mars to the stars and never let go. This mod exists because those books would not leave me alone. If you have not read them, start with Red Rising.

An unofficial fan work inspired by Pierce Brown's Red Rising novels; not affiliated with or endorsed
by the author or his publishers. No text or artwork from the books is reproduced.

This mod was made with heavy use of generative AI. The exact, asset-by-asset account ships with the
mod in [`About/AI_DISCLOSURE.txt`](About/AI_DISCLOSURE.txt), and this repository is public so the
generation logs can be checked. In short:

- **Code and text:** written by Claude (Anthropic) through Claude Code, under the author's direction:
  the C# assembly, every XML def and patch, every in-game string, and the tooling in `Tools/`.
  Models: Claude Opus 5, Opus 5.5, Fable 5 and Fable 5.1 (see the co-author lines in the history).
  The author directed the design, made the lore and balance calls, chose which generated art to keep,
  and play-tested the mod over several weeks.
- **229 of 363 images:** generated on fal with OpenAI `openai/gpt-image-2` (and its edit endpoint),
  then cut out, fitted, tint-masked and outlined by `Tools/Clean-GenWorn.py` and siblings: all worn
  armour and helms, the weapons, both vehicles, the griffin and the clawDrill. The starShell also
  used `fal-ai/nano-banana-2/edit`. Prompts, models and request ids: `Art/Gen/**/fal_manifest.jsonl`.
- **3 images:** generated locally with Z-Image-Turbo and a ControlNet in ComfyUI (the preview image
  and the storyteller portrait).
- **131 images:** drawn by scripts with no image model (`Draw-Items.py`, `Draw-PanelArmor.py`,
  `Draw-Nature.py`, `New-XenotypeIcons.ps1`, `New-CasteMarks.ps1` and others): item icons,
  xenotype and UI icons, tattoos, the pitviper and haemanthus, the mod icon, biomes and effects.
- **1 sound:** generated on fal with `fal-ai/elevenlabs/sound-effects/v2`
  (`Art/Sounds/candidates/fal_manifest.jsonl`).

Thanks to the authors of every required mod, and to Epicguru for Melee Animation.
