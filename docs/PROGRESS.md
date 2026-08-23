# PROGRESS

Milestone status, open questions, known errors. Updated as work lands.

Game target: **RimWorld 1.6.4871 rev590**. packageId: `cinergy92.redrising`.

---

## Milestone status

| # | Milestone | Status |
|---|---|---|
| 0 | Discovery | **Done.** `docs/DISCOVERY.md` |
| 1 | Skeleton | **Built, awaiting in-game verification** |
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

### Not yet verified — this is the gate on Milestone 2

**Nothing here has been loaded by RimWorld.** The mod has not been published or launched. Until the
game loads it with zero red errors, Milestone 1 is not done.

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

1. **Pink's framing** — service caste with no adult content in the base mod, RJW content gated, or
   something more pointed. *Lore call, user's.*
2. **May the player reject the hierarchy?** *Lore call, user's.*
3. **Is the ten-way specialization split right?** *Lore call, user's.*
4. **Should Gold carry a real engineered flaw**, or pay only in complexity? *Lore call, user's.*

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

None. Nothing has been run in game yet, which is itself the point above.

---

## Environment notes

- Developing against a minimal profile per the user's direction: Core, the five DLC, Harmony, and
  this mod. Integrations get added deliberately, not inherited from the user's 151-mod list.
- The user's `Player.log` was last written 2026-04-25 and predates the current game build. The
  first Milestone 1 launch establishes a usable baseline.
- `Tools/.cache/vanilla-defs.json` is gitignored and rebuilds on demand. It is keyed on
  `Version.txt`, so a game update invalidates it automatically.
