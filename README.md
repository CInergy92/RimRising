# RimRising

A total conversion for **RimWorld 1.6** built around an engineered caste hierarchy: fourteen Colors,
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

- RimWorld **1.6** with **Royalty, Ideology and Biotech**.
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
```

`Source/RimRising` holds the C# assembly. `CLAUDE.md` records every verified engine convention
the project relies on, `docs/DESIGN.md` the content design, and `docs/PROGRESS.md` milestone status.

## Credits

Built with Claude Code (Anthropic). Item, weapon and preview art generated locally with
Z-Image-Turbo and a ControlNet in ComfyUI, guided by procedural silhouettes from `Tools/`;
icons, worn apparel and terrain are drawn procedurally. Sound effects generated with fal (fal.ai)
using `fal-ai/elevenlabs/sound-effects/v2`; prompts and request ids are kept in
`Art/Sounds/candidates/fal_manifest.jsonl`.

Thanks to the authors of every required mod, and to Epicguru for Melee Animation.
