using System.Collections.Generic;
using System.IO;
using System.Linq;
using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// A scripted test scene for judging worn apparel against other mods' armour,
    /// without anyone clicking through dev menus. DORMANT unless the game is
    /// launched with -rrtestscene, so normal play never reaches any of it.
    ///
    ///     RimWorldWin64.exe -quicktest -rrtestscene rrtestout=&lt;dir&gt; [-rrtestquit]
    ///
    /// -quicktest is RimWorld's own flag (Verse.QuickStarter): straight into a
    /// fresh map with the player's current mod list. This component then:
    ///
    ///   1. clears and unfogs a patch of ground and sets the clock to noon;
    ///   2. spawns one Baseliner pawn per body type per armour, wearing only that
    ///      armour, in three blocks facing south, east and north;
    ///   3. pauses, frames the camera on each block in turn and writes a
    ///      screenshot of each with ScreenCapture, which grabs the rendered frame
    ///      itself, so nothing about window capture can spoil it;
    ///   4. logs "[RimRising] TESTSCENE DONE" and, with -rrtestquit, exits.
    ///
    /// Armours whose defs are not loaded are skipped and named in the log, so the
    /// scene works with whatever comparison mods happen to be active.
    /// </summary>
    public class MapComponent_RR_TestScene : MapComponent
    {
        private static readonly string[] Armors =
        {
            "RR_Apparel_PulseArmor",            // ours
            "Apparel_PowerArmor",               // vanilla marine armour
            "Apparel_ArmorCataphract",          // Royalty cataphract
            "AG_ForsakenMarineArmor",           // Alpha Genes
            "VAE_Apparel_HeavyMarineArmor",     // Vanilla Armour Expanded
            "VFEC_Apparel_LegionnaireArmor",    // VFE Classical
            "VFEC_Apparel_CenturionArmor",      // VFE Classical
        };

        private static readonly Rot4[] Facings = { Rot4.South, Rot4.East, Rot4.North };

        private static bool? enabled;
        private int frame;
        private int stage;
        private int shotIndex;
        private int wait;
        private CellRect area;
        // size here is the number of CELLS the shot must show top to bottom. It is
        // NOT handed to the camera as-is: see Frame().
        private readonly List<(string name, Vector3 centre, float size)> shots =
            new List<(string, Vector3, float)>();
        // Half the visible height, in cells. 2.7 shows ~5.4 cells tall and ~9.6
        // wide at 16:9: one row of seven armours with room for the HUD at the
        // edges. Close, because the user judged the first run's close-up zoom the
        // right one to read sprites at.
        private const float TargetOrtho = 2.7f;
        private const int RowGap = 5;            // cells between rows; one row per shot
        private int calibration;
        private bool letTimeRun;
        private bool cameraPlus;
        private float zoomLo, zoomHi, zoomMid, bestRoot, bestOrtho;
        private string outDir;

        public MapComponent_RR_TestScene(Map map) : base(map) { }

        private static bool Enabled
        {
            get
            {
                if (!enabled.HasValue) { enabled = GenCommandLine.CommandLineArgPassed("rrtestscene"); }
                return enabled.Value;
            }
        }

        public override void MapComponentUpdate()
        {
            if (!Enabled || stage < 0) { return; }
            if (Current.ProgramState != ProgramState.Playing || Find.CurrentMap != map) { return; }
            frame++;
            if (wait > 0) { wait--; return; }

            switch (stage)
            {
                case 0:
                    // Let the quicktest map settle - colonists spawned, UI up.
                    if (frame < 180) { return; }
                    Build();
                    if (letTimeRun)
                    {
                        // Melee Animation draws a drafted pawn's weapon through its
                        // own idle animation, which only starts once game time runs;
                        // paused at once, every held weapon - vanilla's too - was
                        // simply absent. Run ~2.5 s at normal speed, then pause.
                        Find.TickManager.CurTimeSpeed = TimeSpeed.Normal;
                        stage = 5;
                        wait = 150;
                        return;
                    }
                    StartZoomSearch();
                    stage = 4;
                    wait = 30;
                    return;

                case 5:
                    Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
                    StartZoomSearch();
                    stage = 4;
                    wait = 30;
                    return;

                case 4:
                    // ZOOM, FOUND ONCE BY BISECTION on the camera's REAL size.
                    // Camera+ (brrainz.cameraplus) maps rootSize from an input range
                    // of 11-60 onto its own curve, so rootSize is not cells. Worse,
                    // below 11 that curve raises a negative to a fractional power
                    // and the camera goes NaN - which is what blanked the second
                    // run. So: search only inside the valid range, read
                    // Camera.orthographicSize (half the visible height in cells,
                    // which Camera+ itself writes), and keep the best rootSize.
                    float ortho = Find.Camera.orthographicSize;
                    if (ortho > TargetOrtho) { zoomHi = zoomMid; } else { zoomLo = zoomMid; }
                    if (Mathf.Abs(ortho - TargetOrtho) < Mathf.Abs(bestOrtho - TargetOrtho))
                    {
                        bestOrtho = ortho;
                        bestRoot = zoomMid;
                    }
                    if (++calibration < 14 && Mathf.Abs(ortho - TargetOrtho) > 0.05f)
                    {
                        zoomMid = (zoomLo + zoomHi) / 2f;
                        Find.CameraDriver.SetRootPosAndSize(shots[0].centre, zoomMid);
                        wait = 4;
                        return;
                    }
                    Log.Message($"[RimRising] TESTSCENE zoom: rootSize {bestRoot:F2} -> {bestOrtho:F2} cells half-height (wanted {TargetOrtho}), camera+ {cameraPlus}");
                    stage = 1;
                    wait = 30;           // let graphics resolve before the first shot
                    return;

                case 1:
                    if (shotIndex >= shots.Count)
                    {
                        Log.Message("[RimRising] TESTSCENE DONE -> " + outDir);
                        stage = -1;
                        if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
                        return;
                    }
                    Find.CameraDriver.SetRootPosAndSize(shots[shotIndex].centre, bestRoot);
                    stage = 2;
                    wait = 15;
                    return;

                case 2:
                    // The debug log auto-opens on any red error - other mods log
                    // plenty at startup - and sits in the middle of the shot.
                    foreach (Window w in Find.WindowStack.Windows.ToList()) { Find.WindowStack.TryRemove(w, false); }
                    var shot = shots[shotIndex];
                    string path = Path.Combine(outDir, shot.name + ".png");
                    ScreenCapture.CaptureScreenshot(path, 2);
                    Log.Message("[RimRising] TESTSCENE shot " + path);
                    shotIndex++;
                    stage = 1;
                    wait = 20;
                    return;
            }
        }

        private void StartZoomSearch()
        {
            cameraPlus = GenTypes.GetTypeInAnyAssembly("CameraPlus.Tools") != null;
            zoomLo = cameraPlus ? 11f : 1f;      // Camera+'s minRootInput; below it is NaN
            zoomHi = 60f;                        // Camera+'s maxRootInput; far enough for vanilla
            zoomMid = (zoomLo + zoomHi) / 2f;
            bestRoot = zoomLo;
            bestOrtho = float.MaxValue;
            calibration = 0;
            Find.CameraDriver.SetRootPosAndSize(shots[0].centre, zoomMid);
        }

        private void Build()
        {
            if (!GenCommandLine.TryGetCommandLineArg("rrtestout", out outDir) || outDir.NullOrEmpty())
            {
                outDir = GenFilePaths.ScreenshotFolderPath;
            }
            Directory.CreateDirectory(outDir);

            if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string mode) && mode == "weapons")
            {
                BuildWeapons();
                return;
            }

            var defs = new List<ThingDef>();
            foreach (string name in Armors)
            {
                ThingDef d = DefDatabase<ThingDef>.GetNamedSilentFail(name);
                if (d == null) { Log.Message("[RimRising] TESTSCENE skipping " + name + " (not loaded)"); }
                else { defs.Add(d); }
            }

            BodyTypeDef[] bodies =
            {
                BodyTypeDefOf.Male, BodyTypeDefOf.Female, BodyTypeDefOf.Thin,
                BodyTypeDefOf.Fat, BodyTypeDefOf.Hulk,
            };

            // ONE SHOT = ONE BODY TYPE IN ONE FACING, every armour side by side,
            // so each picture is a direct comparison at a zoom close enough to read.
            int rows = Facings.Length * bodies.Length;
            int width = defs.Count;
            int height = (rows - 1) * RowGap + 1;
            IntVec3 c = map.Center;
            area = new CellRect(c.x - width / 2, c.z - height / 2, width, height).ClipInsideMap(map);

            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();

            Color gold = RR_CasteColors.For(RR_DefOf.RR_Gold) ?? new Color(0.86f, 0.68f, 0.30f);

            int row = 0;
            foreach (Rot4 facing in Facings)
            {
                foreach (BodyTypeDef body in bodies)
                {
                    int z = area.maxZ - row * RowGap;
                    for (int a = 0; a < defs.Count; a++)
                    {
                        var cell = new IntVec3(area.minX + a, 0, z);
                        Pawn p = MakePawn(body, defs[a], gold);
                        if (p == null) { continue; }
                        GenSpawn.Spawn(p, cell, map, facing);
                        p.Rotation = facing;
                        p.Drawer?.renderer?.SetAllGraphicsDirty();
                    }
                    var centre = new Vector3(area.minX + (defs.Count - 1) / 2f + 0.5f, 0f, z + 0.5f);
                    shots.Add(($"{facing.ToStringHuman().ToLowerInvariant()}_{body.defName}", centre, 0f));
                    row++;
                }
            }

            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            Log.Message($"[RimRising] TESTSCENE built: {defs.Count} armours x {bodies.Length} bodies x {Facings.Length} facings at {area}; left to right: " + string.Join(", ", defs.Select(d => d.defName)));
        }

        private static readonly string[] Weapons =
        {
            "RR_Weapon_Razor",
            "RR_Weapon_ReaperRazor",
            "MeleeWeapon_LongSword",
            "MeleeWeapon_MonoSword",
            "MeleeWeapon_PlasmaSword",
            "MeleeWeapon_Gladius",
            "AG_ForsakenLongBlade",
        };

        /// <summary>
        /// rrtestmode=weapons: each melee weapon LYING ON THE GROUND (its item
        /// graphic, the same texture a player sees in a stockpile), then HELD by a
        /// drafted pawn facing south and facing east. Drafted, because
        /// PawnRenderUtility.CarryWeaponOpenly only shows a weapon for a drafted
        /// pawn or a few job/duty cases - so these pawns must be the player's,
        /// since only they have a drafter.
        /// </summary>
        private void BuildWeapons()
        {
            var defs = new List<ThingDef>();
            foreach (string name in Weapons)
            {
                ThingDef d = DefDatabase<ThingDef>.GetNamedSilentFail(name);
                if (d == null) { Log.Message("[RimRising] TESTSCENE skipping " + name + " (not loaded)"); }
                else { defs.Add(d); }
            }

            int width = defs.Count;
            int height = 2 * RowGap + 1;
            IntVec3 c = map.Center;
            area = new CellRect(c.x - width / 2, c.z - height / 2, width, height).ClipInsideMap(map);
            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();

            // Row 0: on the ground.
            int z0 = area.maxZ;
            for (int a = 0; a < defs.Count; a++)
            {
                ThingDef stuff = defs[a].MadeFromStuff ? GenStuff.DefaultStuffFor(defs[a]) : null;
                Thing w = ThingMaker.MakeThing(defs[a], stuff);
                // Not forbidden: the forbidden marker drew a red X over each one.
                // The game runs only ~2.5 s before the shots, too short for anyone
                // to walk over and haul them.
                GenSpawn.Spawn(w, new IntVec3(area.minX + a, 0, z0), map);
            }
            shots.Add(("ground", new Vector3(area.minX + (defs.Count - 1) / 2f + 0.5f, 0f, z0 + 0.5f), 0f));

            // Rows 1-2: held, drafted, facing south then east.
            Rot4[] held = { Rot4.South, Rot4.East };
            for (int r = 0; r < held.Length; r++)
            {
                int z = area.maxZ - (r + 1) * RowGap;
                for (int a = 0; a < defs.Count; a++)
                {
                    var req = new PawnGenerationRequest(
                        PawnKindDefOf.Colonist, Faction.OfPlayer,
                        forceGenerateNewPawn: true, canGeneratePawnRelations: false,
                        fixedGender: Gender.Male, forcedXenotype: XenotypeDefOf.Baseliner,
                        forceNoIdeo: true, developmentalStages: DevelopmentalStage.Adult,
                        dontGiveWeapon: true, forceNoGear: true);
                    Pawn p = PawnGenerator.GeneratePawn(req);
                    p.story.bodyType = BodyTypeDefOf.Male;
                    ThingDef stuff = defs[a].MadeFromStuff ? GenStuff.DefaultStuffFor(defs[a]) : null;
                    var eq = (ThingWithComps)ThingMaker.MakeThing(defs[a], stuff);
                    p.equipment.DestroyAllEquipment();
                    p.equipment.AddEquipment(eq);
                    p.Name = new NameSingle(defs[a].label.CapitalizeFirst());
                    GenSpawn.Spawn(p, new IntVec3(area.minX + a, 0, z), map, held[r]);
                    p.drafter.Drafted = true;
                    p.Rotation = held[r];
                    p.Drawer?.renderer?.SetAllGraphicsDirty();
                }
                shots.Add(($"held_{held[r].ToStringHuman().ToLowerInvariant()}",
                           new Vector3(area.minX + (defs.Count - 1) / 2f + 0.5f, 0f, z + 0.5f), 0f));
            }

            letTimeRun = true;
            Log.Message($"[RimRising] TESTSCENE built weapons at {area}; left to right: " + string.Join(", ", defs.Select(d => d.defName)));
        }

        private Pawn MakePawn(BodyTypeDef body, ThingDef armor, Color gold)
        {
            var req = new PawnGenerationRequest(
                PawnKindDefOf.Colonist, Faction.OfPlayer,
                forceGenerateNewPawn: true,
                canGeneratePawnRelations: false,
                fixedGender: body == BodyTypeDefOf.Female ? Gender.Female : Gender.Male,
                forcedXenotype: XenotypeDefOf.Baseliner,
                // No ideoligion. Our own caste restriction refused pulse armour to
                // these Baselines whenever quicktest's random ideoligion carried the
                // hierarchy precept - the log said "tried to wear ... but is not
                // allowed to" and the row came out naked. MayWearRestricted is
                // permissive for a pawn with no belief, by design, so this passes
                // the restriction without adding any test hook to the rule itself.
                forceNoIdeo: true,
                developmentalStages: DevelopmentalStage.Adult,
                dontGiveWeapon: true,
                forceNoGear: true);
            Pawn p = PawnGenerator.GeneratePawn(req);
            p.story.bodyType = body;
            p.apparel?.DestroyAll();
            p.equipment?.DestroyAllEquipment();

            ThingDef stuff = armor.MadeFromStuff ? GenStuff.DefaultStuffFor(armor) : null;
            var ap = (Apparel)ThingMaker.MakeThing(armor, stuff);
            // Ours is shown in a caste colour, since being dyed is half of what it
            // is for; the others keep whatever their defs give them.
            if (armor.defName.StartsWith("RR_"))
            {
                ap.TryGetComp<CompColorable>()?.SetColor(gold);
            }
            p.apparel.Wear(ap, dropReplacedApparel: false, locked: true);
            p.Name = new NameSingle(armor.label.CapitalizeFirst());
            // Not the player's: 105 test colonists filled the colonist bar across
            // the top of every shot. Factionless pawns stay out of it, and the game
            // is paused, so they never act.
            p.SetFaction(null);
            return p;
        }

        private void Clear(CellRect rect)
        {
            foreach (IntVec3 cell in rect)
            {
                foreach (Thing t in cell.GetThingList(map).ToList())
                {
                    if (t is Pawn) { continue; }
                    t.Destroy(DestroyMode.Vanish);
                }
                map.roofGrid.SetRoof(cell, null);
                map.fogGrid.Unfog(cell);
                map.snowGrid?.SetDepth(cell, 0f);
            }
        }

        private void SetNoon()
        {
            // Advance the clock to local noon, so the light is the same every run.
            float pct = GenLocalDate.DayPercent(map);
            float ahead = (0.5f - pct + 1f) % 1f;
            Find.TickManager.DebugSetTicksGame(Find.TickManager.TicksGame + (int)(ahead * GenDate.TicksPerDay));
        }
    }
}
