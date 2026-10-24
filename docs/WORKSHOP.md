# Publishing RimRising to the Steam Workshop

Publishing is the author's call and is done by hand from inside RimWorld. This page is the checklist.

## Before uploading

1. `pwsh -File Tools/Test-ModDefs.ps1` - must say PASSED.
2. `pwsh -File Tools/Publish-Mod.ps1` - mirrors the shipped content into `RimWorld/Mods/RimRising`.
   RimWorld uploads from that folder, not from the repo. Source, docs, tools, the source art under
   `Art/` (with its generation logs) and `Extras/` (the separate CE patch mod) never ship.
3. Lint the shipped folder against vanilla only:
   `um publish check "<RimWorld>/Mods/RimRising" --game "<RimWorld>/Data"`.
   Last result (2026-10-24): 554 files, 0 failures. The single warning, "no README", is expected:
   `*.md` files are not shipped, and the Workshop description plus `About/AI_DISCLOSURE.txt`
   cover what a README would.
4. Launch once with your normal mod list and check the log for red errors from RimRising.
5. Scan the shipped folder for personal data - it must print nothing:
   `grep -r -l -a -i -E "<your email>|<your name>" "<RimWorld>/Mods/RimRising"`.
   The lint above does not look for this. On 2026-10-24 it caught `.git-rewrite/`, left by an
   abandoned history rewrite and holding the personal email, mirrored into the Mods copy;
   `Publish-Mod.ps1` now excludes it and `.claude/`.

## Uploading (first time)

1. Start RimWorld, open **Mods**, select **RimRising**, and click **Upload to Steam Workshop**.
2. Accept the Workshop agreement if Steam asks.
3. RimWorld writes `About/PublishedFileId.txt` into `Mods/RimRising`. **Keep it.** Every later
   upload needs it to update the same item instead of creating a new one. `Publish-Mod.ps1`
   excludes it from the mirror, so it survives future publishes. Copying it into the repo's
   `About/` as well is a good backup.
4. On the new Workshop page, set the visibility (it starts private or hidden, depending on Steam)
   and check the description.

## The 1.7 upload options

- **Build asset pack: on.** Tested 2026-10-24 with `-BakeModAssetPacks` and the loose files hidden:
  everything renders from the packs, Realistic Body greaves included.
- **Don't upload source textures: OFF.** 1.6 players need the loose image and sound files.
- **Tag as translation: off.**

## What RimWorld sends (decompiled, `Workshop.SetWorkshopItemDataFrom`)

- **Title** and **preview image** (`About/Preview.png`, 640x360, 405 KB) on every upload.
- **Description** from `About/About.xml` **only when the item is first created**. Later uploads
  never touch it, so after the first upload any description change (including the AI disclosure)
  must be made on the Workshop page itself.
- **Tags**, including one per `supportedVersions` entry (1.6 and 1.7).

## AI disclosure

- The description's AI DISCLOSURE section states, by category and with counts, what was
  generated and with which models.
- `About/AI_DISCLOSURE.txt` ships inside the mod with the asset-by-asset list.
- The README's Credits section and the generation logs under `Art/` hold the same information for
  anyone reading the source.

If assets are regenerated or added later, update all three places, and on the Workshop page
update the description by hand.

## Updating later

Run steps 1-5, then **Update on Steam Workshop** from the same in-game Mods menu, and write the
change notes in the dialog Steam shows. Bump `modVersion` in `About/About.xml` first.
