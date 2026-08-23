# PROGRESS

Milestone status, open questions, known errors. Updated as work lands.

Game target: **RimWorld 1.6.4871 rev590**. packageId: `cinergy92.redrising`.

---

## Milestone status

| # | Milestone | Status |
|---|---|---|
| 0 | Discovery | **Done.** `docs/DISCOVERY.md` |
| 1 | Skeleton | **Loaded in game. One texture bug found and fixed; awaiting re-verification** |
| 2 | The Color system | Not started — blocked on M1 verification |
| 3 | Factions and pawn kinds | Not started |
| 4 | Tech and equipment | Not started |
| 5 | Ideology and hierarchy | Not started |
| 6 | Scenarios and world | Not started |
| 7 | Vanilla suppression | Not started |

---

## Milestone 1 — skeleton

### Built

- `About/About.xml` — packageId, `supportedVersions` 1.6, `modDependencies` on Biotech and
  Ideology, `loadAfter` naming all five DLC plus Harmony.
- `LoadFolders.xml` — root plus `1.6`. Conditional folders are listed as comments only; they get
  added when the folder actually exists, since referencing a missing path is unverified.
- `1.6/Defs/ThingDefs_Items/Items_Resource_RedRising.xml` — one trivial `ThingDef`, `RR_Ionsteel`,
  mirrored node-for-node from `ComponentIndustrial` with `ParentName="ResourceBase"`.
- `Tools/` — all four PowerShell scripts.
- Placeholder art — item texture, `Preview.png`, `ModIcon.png`, mod icon.
- `CLAUDE.md`, `docs/DESIGN.md`, this file, `.gitignore`.

### Validation

`Test-ModDefs.ps1` passes: 1 def, 0 errors, 0 warnings, exit 0.

The validator was negative-tested against a fixture containing all five fault classes — malformed
XML, duplicate defName, vanilla collision, missing texture, unresolvable ParentName — and produced
five errors with exit 1. It is not merely returning green.

### First in-game load — one real bug, found and fixed

The mod loaded. `About.xml` parsed, packageId resolved, no dependency complaints. RimSort's
"Missing Publish Field ID" notice is expected for a local mod and needs no action.

One genuine error in `Player.log`:

```
Collection cannot init: No textures found at path Things/Item/Resource/RR_Ionsteel
```

**Cause:** `Graphic_StackCount` derives from `Graphic_Collection` and resolves `texPath` as a
*folder* of images, not a single file. The placeholder generator had written one flat PNG at that
path, and the validator passed it because a file genuinely existed there — a false green.

**Fixed:** both tools are now graphic-class aware. `Test-ModDefs.ps1` requires at least one image
*under* `<texPath>/` for collection classes and reports `MissingTextureCollection`;
`New-PlaceholderTextures.ps1` emits `_a`/`_b`/`_c` variants in a folder. Confirmed the validator
now catches the exact condition the game reported, then regenerated and republished.

Mod renamed to **RimRising** in `About.xml`. packageId left as `cinergy92.redrising` per the
original CONFIG — see "Open questions".

### Still to verify

The fixed textures have not been loaded yet. Re-verify per the steps below.

### How to verify — what to click

1. Publish:

```bash
pwsh -File Tools/Publish-Mod.ps1
```

2. Launch RimWorld. In the mod list, confirm **Red Rising** appears with its placeholder preview
   image and no yellow warning triangle.
3. Enable it alongside Core and the DLC. Accept the restart prompt.
4. After restart, open the debug log (the `~` key opens the console; the message log is under the
   debug actions menu). Confirm **no red errors**.
5. Enable Development mode in Options if it is not already on.
6. Start any quick game. Use the debug actions menu, **Spawn thing**, search `ionsteel`, and place
   a stack.
7. Confirm the item appears with its placeholder texture (a labelled flat-colored square) and can
   be hauled and stockpiled.
8. Back at the desktop:

```bash
pwsh -File Tools/Get-ModLoadErrors.ps1
```

   Expect "No errors attributable to this mod."

Report back what happens, including anything red, and Milestone 1 closes.

---

## Open questions

Carried in `docs/DESIGN.md` §7. None block Milestone 1.

1. **Roster: canonical 14 Colors, or the original 10?** The reference the user supplied gives
   fourteen; the original brief listed ten, omitting Copper, Green, Violet and Brown. Design now
   covers all fourteen. *Lore call, user's.* Recommendation: 14.
2. **Prefixes for the five Colors with no established one** — invent, or leave prefix-less?
   *Lore call, user's.*
3. **Pink's framing** — social functionary with no adult content in the base mod and RJW content
   gated, or something more pointed. *Lore call, user's.*
4. **May the player reject the hierarchy?** *Lore call, user's.*
5. **Should Gold carry a real engineered flaw**, or pay only in complexity? *Lore call, user's.*
6. **packageId.** Still `cinergy92.redrising` per the original CONFIG, while the mod is now named
   RimRising. Changing it is free today and expensive later, since packageId is what other mods and
   save files key on. *Technical, but the user's call — say the word and it changes.*

---

## Known unknowns — must be resolved before the milestone that depends on them

| # | Unknown | Blocks | Plan |
|---|---|---|---|
| U1 | Does implanting a xenogerm built from an exact Color gene set make the pawn read as that Color, or as "Hybrid"? C# behaviour in `Building_GeneAssembler`, invisible from XML. | M2 — the whole carving design | Test in game during M2. If "Hybrid", bring the user options rather than improvise. |
| U2 | Exact vanilla xenotype complexity totals. My template-gene resolution is inference, not something the game exposes. Ordering is reliable; figures are provisional. | M2 balance | Check against the in-game gene assembler. |
| U3 | Does vanilla raise a `HistoryEventDef` on xenogerm implantation? | M5 — ideoligious reaction to carving | Check before M5. If not, raising one needs Harmony. Ask before writing C#. |
| U4 | Does Odyssey expose a *personal* gravity mechanic, or only ship-scale? | M4 — gravity equipment | Read `Buildings_Gravship.xml` before M4. If ship-only, choose between stat-bonus apparel and a C# comp, and ask. |
| U5 | Full `techLevel` enum. `Industrial` and `Spacer` confirmed in use; rest unconfirmed. | M3 faction tech levels | Verify from vanilla before setting. |
| U6 | Apparel and pawn-worn texture dimensions. Gene, xenotype, item and weapon sizes are measured; these are not. | M4 placeholder art | Measure from a reference mod before M4. |
| U7 | Is it safe for `LoadFolders.xml` to name a folder that does not exist on disk? | Adding compat folders | Currently sidestepped by only listing folders that exist. Test when the first compat folder lands. |

---

## Known errors

None outstanding. One found and fixed on first load — see "First in-game load" above.

## Prior art

Two Workshop mods cover adjacent ground; details in `docs/DESIGN.md` §7. Both independently use the
full fourteen-Color roster, and both depend on Expanded Biotech Style Genes plus EyeGenes2 and
Facial Animation for caste appearance. **RimRising stays on vanilla Biotech spectrum genes for now**
so it runs on Core + Biotech + Ideology alone. Revisit once the system works.

Neither appears to implement carving as a playable mechanic, which makes it the most distinctive
thing this mod can do.

---

## Environment notes

- Developing against a minimal profile per the user's direction: Core, the five DLC, Harmony, and
  this mod. Integrations get added deliberately, not inherited from the user's 151-mod list.
- The user's `Player.log` was last written 2026-04-25 and predates the current game build. The
  first Milestone 1 launch establishes a usable baseline.
- `Tools/.cache/vanilla-defs.json` is gitignored and rebuilds on demand. It is keyed on
  `Version.txt`, so a game update invalidates it automatically.
