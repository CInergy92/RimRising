using System.Collections.Generic;
using System.IO;
using System.Linq;
using RimWorld;
using RimWorld.Planet;
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
            // Ours, all five worn body armours...
            "RR_Apparel_PulseArmor",
            "RR_Apparel_RecoilArmor",
            "RR_Apparel_DuroArmor",
            "RR_Apparel_ScarabSkin",
            "RR_Apparel_GhostCloak",
            "RR_Apparel_HowlerPelt",            // the Howlers' shoulder mantle
            "RR_Apparel_DemonHelm",             // headgear, on its own
            // ...against vanilla references for scale and line weight. (Alpha
            // Genes, VAE, VFE Classical armour and Royalty's cataphract were
            // compared earlier; see CLAUDE.md for what that showed.)
            "Apparel_PowerArmor",               // vanilla marine armour
            "Apparel_PowerArmorHelmet",         // vanilla marine helmet
            // The starShell, only when the Exosuit Framework is active: the core,
            // with its head and cannon arm added in MakePawn (StarShellParts).
            "RR_Apparel_StarShellCore",
        };

        private static readonly string[] StarShellParts = { "RR_Apparel_StarShellHead", "RR_Apparel_StarShellCannonArm" };

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
        private float TargetOrtho = 2.7f;    // rrtestmode=items widens it
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
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m1) && m1 == "whip")
                    {
                        BuildWhip();
                        Find.TickManager.CurTimeSpeed = TimeSpeed.Normal;
                        stage = 10;
                        wait = 60;
                        return;
                    }
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m2) && m2 == "carve")
                    {
                        CarveTest();
                        Log.Message("[RimRising] TESTSCENE DONE (carve)");
                        stage = -1;
                        if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
                        return;
                    }
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m4) && m4 == "nature")
                    {
                        BuildNature();
                        Find.TickManager.CurTimeSpeed = TimeSpeed.Superfast;
                        stage = 20;
                        return;
                    }
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m6) && m6 == "raid")
                    {
                        try { BuildRaid(); }
                        catch (System.Exception e) { Log.Error("[RimRising] RAID build threw: " + e); }
                        Find.TickManager.CurTimeSpeed = TimeSpeed.Superfast;
                        stage = 30;
                        return;
                    }
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m5) && m5 == "m12")
                    {
                        // Each check is isolated: one that throws is logged as FAIL
                        // and the rest still run, and the mode always finishes.
                        stage = -1;
                        try { Milestone12(); }
                        catch (System.Exception e) { Log.Error("[RimRising] M12 harness threw: " + e); }
                        Log.Message("[RimRising] TESTSCENE DONE (m12)");
                        if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
                        return;
                    }
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m3) && m3 == "bios")
                    {
                        GenerateBios();
                        Log.Message("[RimRising] TESTSCENE DONE (bios)");
                        stage = -1;
                        if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
                        return;
                    }
                    if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string m0) && m0 == "kinds")
                    {
                        // No pictures: generation is judged from the log.
                        GenerateKinds();
                        Log.Message("[RimRising] TESTSCENE DONE (kinds)");
                        stage = -1;
                        if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
                        return;
                    }
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

                case 10:
                case 11:
                case 12:
                    WhipStep();
                    return;

                case 20:
                    NatureStep();
                    return;

                case 30:
                    RaidStep();
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

            if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string kmode) && kmode == "marks")
            {
                BuildMarks();
                return;
            }
            if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string vmode) && vmode == "vehicle")
            {
                BuildVehicle();
                return;
            }
            if (GenCommandLine.TryGetCommandLineArg("rrtestmode", out string imode) && imode == "items")
            {
                BuildItems();
                return;
            }
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

        /// <summary>
        /// rrtestmode=vehicle: the Drachenjager facing south, east and north, side by
        /// side. Spawned through Vehicle Framework's VehicleSpawner.GenerateVehicle by
        /// reflection, so this assembly takes no compile-time dependency on it.
        /// </summary>
        private void BuildVehicle()
        {
            TargetOrtho = 6.5f;
            System.Type vdef = GenTypes.GetTypeInAnyAssembly("Vehicles.VehicleDef");
            ThingDef def = vdef == null ? null : GenDefDatabase.GetDef(vdef, "RR_Drachenjager", false) as ThingDef;
            System.Type spawner = GenTypes.GetTypeInAnyAssembly("Vehicles.VehicleSpawner");
            var gen = spawner?.GetMethods().FirstOrDefault(m => m.Name == "GenerateVehicle" && m.GetParameters().Length == 2
                && m.GetParameters()[1].ParameterType == typeof(Faction));
            if (def == null || gen == null)
            {
                Log.Warning($"[RimRising] VEHICLE: def {(def != null)}, spawner {(gen != null)} - Vehicle Framework not active?");
                return;
            }
            IntVec3 c = map.Center;
            area = new CellRect(c.x - 14, c.z - 6, 29, 13).ClipInsideMap(map);
            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();
            Rot4[] rots = { Rot4.South, Rot4.East, Rot4.North };
            for (int i = 0; i < rots.Length; i++)
            {
                var v = (Pawn)gen.Invoke(null, new object[] { def, Faction.OfPlayer });
                GenSpawn.Spawn(v, new IntVec3(c.x - 10 + i * 10, 0, c.z), map, rots[i]);
                v.Rotation = rots[i];
            }
            shots.Add(("vehicle", new Vector3(c.x + 0.5f, 0f, c.z + 0.5f), 0f));
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            Log.Message("[RimRising] TESTSCENE built vehicle");
        }

        private static readonly string[] OurItems =
        {
            "RR_Zoladone", "RR_Nazopran", "RR_MjolnirSix", "RR_GodsBread", "RR_FeverCloud",
            "RR_ResFlesh", "RR_Ionsteel", "RR_CarvelingVat_Sylph", "RR_CarvingKit",
            "RR_CupidsKiss", "RR_SynapticLattice", "RR_Apparel_Aegis",
            "RR_Apparel_GravBoots", "RR_Apparel_SkipBoots",
        };

        private static readonly string[] VanillaItems =
        {
            "GoJuice", "Yayo", "Flake", "Luciferium", "Penoxycyline", "MedicineIndustrial",
            "MedicineUltratech", "Steel", "Plasteel", "Uranium", "ComponentSpacer",
            "Apparel_ShieldBelt", "Apparel_PackJump", "BionicArm",
        };

        /// <summary>
        /// rrtestmode=items: our items on the ground at one, a middling and a full
        /// stack (Graphic_StackCount shows _a, _b and _c), then a row of vanilla
        /// items for scale and line weight. Not forbidden, so no red X.
        /// </summary>
        private void BuildItems()
        {
            TargetOrtho = 4.2f;
            var ours = OurItems.Select(n => DefDatabase<ThingDef>.GetNamedSilentFail(n)).Where(d => d != null).ToList();
            var theirs = VanillaItems.Select(n => DefDatabase<ThingDef>.GetNamedSilentFail(n)).Where(d => d != null).ToList();
            int width = Mathf.Max(ours.Count, theirs.Count);
            int rowGap = 2;
            IntVec3 c = map.Center;
            area = new CellRect(c.x - width / 2, c.z - 4, width, 4 * rowGap).ClipInsideMap(map);
            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();

            float[] fractions = { 0f, 0.4f, 1f };     // count 1, mid, full
            for (int r = 0; r < fractions.Length; r++)
            {
                int z = area.maxZ - r * rowGap;
                for (int a = 0; a < ours.Count; a++)
                {
                    ThingDef d = ours[a];
                    Thing t = ThingMaker.MakeThing(d, d.MadeFromStuff ? GenStuff.DefaultStuffFor(d) : null);
                    t.stackCount = Mathf.Max(1, Mathf.RoundToInt(d.stackLimit * fractions[r]));
                    GenSpawn.Spawn(t, new IntVec3(area.minX + a, 0, z), map);
                }
            }
            int zv = area.maxZ - 3 * rowGap;
            for (int a = 0; a < theirs.Count; a++)
            {
                ThingDef d = theirs[a];
                Thing t = ThingMaker.MakeThing(d, d.MadeFromStuff ? GenStuff.DefaultStuffFor(d) : null);
                t.stackCount = Mathf.Max(1, Mathf.RoundToInt(d.stackLimit * 0.4f));
                GenSpawn.Spawn(t, new IntVec3(area.minX + a, 0, zv), map);
            }
            shots.Add(("items", new Vector3(area.minX + width / 2f, 0f, area.maxZ - 1.5f * rowGap + 0.5f), 0f));

            // Nature: our flower beside a vanilla one, fully grown, and our snake
            // beside vanilla's cobra, south and east. Factionless and paused.
            int zn = area.minZ - rowGap;
            int col = area.minX;
            foreach (string pn in new[] { "RR_Haemanthus", "RR_Haemanthus", "RR_Haemanthus", "Plant_Dandelion" })
            {
                ThingDef pd = DefDatabase<ThingDef>.GetNamedSilentFail(pn);
                if (pd == null) { col++; continue; }
                IntVec3 cell = new IntVec3(col++, 0, zn);
                foreach (Thing old in cell.GetThingList(map).ToList()) { if (old is Plant) { old.Destroy(); } }
                var plant = (Plant)ThingMaker.MakeThing(pd);
                plant.Growth = 1f;
                GenSpawn.Spawn(plant, cell, map);
            }
            foreach (string kn in new[] { "RR_Pitviper", "Cobra" })
            {
                PawnKindDef kd = DefDatabase<PawnKindDef>.GetNamedSilentFail(kn);
                if (kd == null) { col += 2; continue; }
                foreach (Rot4 rot in new[] { Rot4.South, Rot4.East })
                {
                    Pawn an = PawnGenerator.GeneratePawn(new PawnGenerationRequest(kd, null, forceGenerateNewPawn: true));
                    GenSpawn.Spawn(an, new IntVec3(col++, 0, zn), map, rot);
                    an.Rotation = rot;
                }
            }
            shots.Add(("nature", new Vector3(area.minX + 4f, 0f, zn + 0.5f), 0f));
            // Beasts and buildings, their own row and shot: the griffin against a
            // thrumbo (both ~2.6 cells adult), south and east, then the clawDrill
            // beside vanilla's deep drill.
            int zb = zn - 5;
            int cb = area.minX;
            Clear(new CellRect(cb - 1, zb - 3, 30, 7).ClipInsideMap(map));
            foreach (string kn in new[] { "RR_Griffin", "Thrumbo" })
            {
                PawnKindDef kd = DefDatabase<PawnKindDef>.GetNamedSilentFail(kn);
                if (kd == null) { cb += 6; continue; }
                foreach (Rot4 rot in new[] { Rot4.South, Rot4.East })
                {
                    Pawn an = PawnGenerator.GeneratePawn(new PawnGenerationRequest(kd, null, forceGenerateNewPawn: true));
                    an.ageTracker.AgeBiologicalTicks = (long)(an.RaceProps.lifeStageAges.Last().minAge * 3600000f) + 60000;
                    GenSpawn.Spawn(an, new IntVec3(cb + 1, 0, zb), map, rot);
                    an.Rotation = rot;
                    cb += 3;
                }
            }
            foreach (string bn in new[] { "RR_ClawDrill", "DeepDrill" })
            {
                ThingDef bd = DefDatabase<ThingDef>.GetNamedSilentFail(bn);
                if (bd == null) { continue; }
                cb += 1;
                GenSpawn.Spawn(ThingMaker.MakeThing(bd, bd.MadeFromStuff ? GenStuff.DefaultStuffFor(bd) : null),
                    new IntVec3(cb, 0, zb), map, Rot4.North);
                cb += bd.size.x + 1;
            }
            shots.Add(("beasts", new Vector3((area.minX + cb) / 2f, 0f, zb + 0.5f), 0f));
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            Log.Message("[RimRising] TESTSCENE built items: ours " + string.Join(", ", ours.Select(d => d.defName)) +
                        " | vanilla " + string.Join(", ", theirs.Select(d => d.defName)));
        }

        private static readonly string[] Weapons =
        {
            "RR_Weapon_Razor",
            "RR_Weapon_ReaperRazor",
            "RR_Weapon_Razor_Heirloom",
            "RR_Weapon_SlingBlade",
            "MeleeWeapon_LongSword",
            "MeleeWeapon_MonoSword",
            "MeleeWeapon_PlasmaSword",
            "MeleeWeapon_Gladius",
            "AG_ForsakenLongBlade",
            // ranged, against vanilla charge rifle and autopistol
            "RR_Weapon_PulseFist", "RR_Weapon_Scorcher", "Gun_ChargeRifle", "Gun_Autopistol",
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

        // rrtestmode=whip: one Gold per row lashes a target five cells away, each
        // target in different armour; null is bare skin.
        private static readonly string[] WhipTargetArmor =
        {
            null, "RR_Apparel_DuroArmor", "RR_Apparel_PulseArmor", "Apparel_PowerArmor",
        };
        private const int WhipReps = 8;
        private readonly List<(Pawn caster, Pawn target, Ability ability, string armor)> lashers =
            new List<(Pawn, Pawn, Ability, string)>();
        private readonly List<List<float>> lashDamage = new List<List<float>>();
        private int whipRep;
        private int whipWaited;

        /// <summary>
        /// rrtestmode=whip: drafted Golds with razors, each facing a pawn five cells
        /// away in a different armour, lash WhipReps times. Each lash's damage is
        /// read off the target's injuries (0 = missed, dodged or deflected) and the
        /// target is healed before the next. The first lash is paused on, so the
        /// line fleck is in the screenshot.
        /// </summary>
        private void BuildWhip()
        {
            if (!GenCommandLine.TryGetCommandLineArg("rrtestout", out outDir) || outDir.NullOrEmpty())
            {
                outDir = GenFilePaths.ScreenshotFolderPath;
            }
            Directory.CreateDirectory(outDir);

            ThingDef razorDef = DefDatabase<ThingDef>.GetNamed("RR_Weapon_Razor");
            int rows = WhipTargetArmor.Length;
            IntVec3 c = map.Center;
            area = new CellRect(c.x - 3, c.z - rows, 8, rows * 2).ClipInsideMap(map);
            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();

            for (int r = 0; r < rows; r++)
            {
                int z = area.maxZ - r * 2;
                var req = new PawnGenerationRequest(
                    PawnKindDefOf.Colonist, Faction.OfPlayer, forceGenerateNewPawn: true,
                    canGeneratePawnRelations: false, fixedGender: Gender.Male,
                    forcedXenotype: RR_DefOf.RR_Gold, forceNoIdeo: true,
                    developmentalStages: DevelopmentalStage.Adult,
                    fixedBiologicalAge: 30f, fixedChronologicalAge: 30f,
                    dontGiveWeapon: true, forceNoGear: true);
                Pawn caster = PawnGenerator.GeneratePawn(req);
                // A pacifist backstory makes the ability refuse ("incapable of
                // violence") and silently blanks a whole row - it did once.
                for (int tries = 0; tries < 20 && caster.WorkTagIsDisabled(WorkTags.Violent); tries++)
                {
                    caster = PawnGenerator.GeneratePawn(req);
                }
                caster.skills.GetSkill(SkillDefOf.Melee).Level = 12;
                caster.equipment.DestroyAllEquipment();
                var razor = (ThingWithComps)ThingMaker.MakeThing(razorDef);
                caster.equipment.AddEquipment(razor);
                caster.Name = new NameSingle("Lasher " + r);
                GenSpawn.Spawn(caster, new IntVec3(area.minX, 0, z), map, Rot4.East);
                caster.drafter.Drafted = true;

                string armor = WhipTargetArmor[r];
                ThingDef ad = armor == null ? null : DefDatabase<ThingDef>.GetNamedSilentFail(armor);
                Pawn target = MakePawn(BodyTypeDefOf.Male, ad, Color.white);
                target.Name = new NameSingle(armor ?? "unarmoured");
                GenSpawn.Spawn(target, new IntVec3(area.minX + 5, 0, z), map, Rot4.West);
                target.jobs.StartJob(JobMaker.MakeJob(JobDefOf.Wait, 60000), Verse.AI.JobCondition.InterruptForced);

                Ability ab = razor.TryGetComp<CompEquippableAbility>()?.AbilityForReading;
                lashers.Add((caster, target, ab, armor ?? "none"));
                lashDamage.Add(new List<float>());
            }
            shots.Add(("whip", new Vector3(area.minX + 3f, 0f, area.CenterVector3.z), 0f));
            Log.Message($"[RimRising] WHIP built {rows} rows; ability found: {lashers.All(l => l.ability != null)}");
        }

        private static float InjurySum(Pawn p) =>
            p.health.hediffSet.hediffs.OfType<Hediff_Injury>().Sum(h => h.Severity);

        private void WhipStep()
        {
            switch (stage)
            {
                case 10:   // order every lasher to cast
                    if (whipRep >= WhipReps)
                    {
                        for (int i = 0; i < lashers.Count; i++)
                        {
                            List<float> d = lashDamage[i];
                            Log.Message($"[RimRising] WHIP vs {lashers[i].armor}: {d.Count(x => x > 0)}/{d.Count} drew blood, damage [{string.Join(", ", d.Select(x => x.ToString("F1")))}]");
                        }
                        Log.Message("[RimRising] TESTSCENE DONE -> " + outDir);
                        stage = -1;
                        if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
                        return;
                    }
                    foreach (var l in lashers)
                    {
                        if (l.ability == null) { continue; }
                        // Hurt factionless targets FLEE, and a lash ordered at a pawn
                        // running out of reach ends without firing - which read as a
                        // stalled cast. Put each one back on its mark every round.
                        IntVec3 mark = new IntVec3(area.minX + 5, 0, l.caster.Position.z);
                        if (l.target.Spawned && l.target.Position != mark)
                        {
                            l.target.Position = mark;
                            l.target.Notify_Teleported();
                        }
                        if (l.target.Spawned && !l.target.Downed)
                        {
                            l.target.mindState?.mentalStateHandler?.Reset();
                            l.target.jobs.StartJob(JobMaker.MakeJob(JobDefOf.Wait, 60000), Verse.AI.JobCondition.InterruptForced);
                        }
                        l.ability.ResetCooldown();
                        bool ordered = l.caster.jobs.TryTakeOrderedJob(l.ability.GetJob(l.target, l.target));
                        if (!ordered || l.ability.GizmoDisabled(out string why))
                        {
                            l.ability.GizmoDisabled(out why);
                            Log.Warning($"[RimRising] WHIP rep {whipRep} vs {l.armor}: ordered={ordered} disabled={why ?? "-"} target downed={l.target.Downed} spawned={l.target.Spawned} pos={l.target.Position}");
                        }
                    }
                    stage = 11;
                    wait = 0;
                    whipWaited = 0;
                    return;

                case 11:   // wait for all casts to land, i.e. every cooldown started
                    if (lashers.Any(l => l.ability != null && !l.ability.OnCooldown))
                    {
                        if (++whipWaited < 900) { return; }
                        Log.Warning("[RimRising] WHIP: a cast never landed within 900 frames: " +
                            string.Join(", ", lashers.Where(l => l.ability != null && !l.ability.OnCooldown)
                                .Select(l => l.armor + " (" + (l.caster.CurJobDef?.defName ?? "no job") +
                                    $", dist {l.caster.Position.DistanceTo(l.target.Position):F1}" +
                                    $", los {GenSight.LineOfSight(l.caster.Position, l.target.Position, map)}" +
                                    $", target job {l.target.CurJobDef?.defName ?? "-"}" +
                                    $", stance {l.caster.stances?.curStance?.GetType().Name ?? "-"})")));
                    }
                    if (whipRep == 0)
                    {
                        Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
                        foreach (Window w in Find.WindowStack.Windows.ToList()) { Find.WindowStack.TryRemove(w, false); }
                        Find.CameraDriver.SetRootPosAndSize(shots[0].centre, 12f);   // Camera+ floor is 11
                        stage = 12;
                        wait = 10;
                        return;
                    }
                    RecordLashes();
                    return;

                case 12:
                    ScreenCapture.CaptureScreenshot(Path.Combine(outDir, "whip.png"), 2);
                    Find.TickManager.CurTimeSpeed = TimeSpeed.Normal;
                    RecordLashes();
                    return;
            }
        }

        private void RecordLashes()
        {
            for (int i = 0; i < lashers.Count; i++)
            {
                Pawn t = lashers[i].target;
                lashDamage[i].Add(InjurySum(t));
                foreach (Hediff h in t.health.hediffSet.hediffs.Where(h => h is Hediff_Injury || h.def == HediffDefOf.BloodLoss).ToList())
                {
                    t.health.RemoveHediff(h);
                }
                if (t.Downed || t.Dead) { Log.Message($"[RimRising] WHIP target {lashers[i].armor} downed/dead after lash {whipRep}"); }
            }
            whipRep++;
            stage = 10;
            wait = 30;
        }

        /// <summary>
        /// rrtestmode=carve: carve a Baseliner into every Color through the real
        /// recipe worker (billDoer null, as dev-mode surgery passes it) and log what
        /// the pawn reads as afterwards - Color, name, and which icon the UI shows.
        /// </summary>
        private void CarveTest()
        {
            var carves = DefDatabase<RecipeDef>.AllDefsListForReading
                .Where(r => r.workerClass == typeof(Recipe_CarveColor) &&
                            r.GetModExtension<CarveTargetExtension>()?.color != null).ToList();
            foreach (RecipeDef r in carves)
            {
                XenotypeDef target = r.GetModExtension<CarveTargetExtension>().color;
                Pawn p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(
                    PawnKindDefOf.Colonist, Faction.OfPlayer, forceGenerateNewPawn: true,
                    forcedXenotype: XenotypeDefOf.Baseliner, forceNoIdeo: true,
                    developmentalStages: DevelopmentalStage.Adult));
                r.Worker.ApplyOnPawn(p, null, null, new List<Thing>(), null);
                XenotypeIconDef want = DefDatabase<XenotypeIconDef>.GetNamedSilentFail("RR_Icon_" + target.defName.Substring(3));
                Texture2D shown = p.genes.XenotypeIcon;
                Log.Message($"[RimRising] CARVE {r.defName}: reads {RR_CasteIdentity.ColorOf(p)?.defName ?? "-"}, name '{p.genes.xenotypeName}', " +
                            $"icon {p.genes.iconDef?.defName ?? "-"}, shows own glyph {shown != null && want != null && shown == want.Icon}, " +
                            $"not Basic {shown != XenotypeIconDefOf.Basic.Icon}");
                Find.WorldPawns.PassToWorld(p, PawnDiscardDecideMode.Discard);
            }
            Log.Message($"[RimRising] CARVE {carves.Count} carve recipes tested");
        }

        private const int KindSamples = 30;

        private static readonly string[] Kinds =
        {
            "RR_Society_Obsidian_Knight",
            "RR_Society_Gold_Praetor",
            "RR_Society_Bronzie_Officer",
            "RR_Ascomanni_Warlord",
            "RR_Julii_Enforcer",
            "RR_Sun_Security",
        };

        /// <summary>
        /// rrtestmode=kinds: generate each kind ten times for a faction that fields
        /// it, the way a raid would, and log what each pawn came out holding and
        /// wearing. For questions like "can a Society Obsidian Knight actually spawn
        /// in the plate the kind lists" - which the caste restriction can refuse
        /// during generation, silently but for a "tried to wear" log line.
        /// </summary>
        private void GenerateKinds()
        {
            foreach (string name in Kinds)
            {
                PawnKindDef kind = DefDatabase<PawnKindDef>.GetNamedSilentFail(name);
                if (kind == null) { Log.Message("[RimRising] KINDS skipping " + name + " (not loaded)"); continue; }
                Faction fac = Find.FactionManager.AllFactionsListForReading.FirstOrDefault(f =>
                    f.def.pawnGroupMakers != null && f.def.pawnGroupMakers.Any(g =>
                        (g.options != null && g.options.Any(o => o.kind == kind)) ||
                        (g.traders != null && g.traders.Any(o => o.kind == kind)) ||
                        (g.guards != null && g.guards.Any(o => o.kind == kind))));
                if (fac == null) { Log.Message("[RimRising] KINDS " + name + ": no faction in this world fields it"); continue; }

                int plate = 0;
                for (int i = 0; i < KindSamples; i++)
                {
                    Pawn p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(kind, fac, forceGenerateNewPawn: true));
                    string apparel = string.Join(", ", p.apparel?.WornApparel.Select(a => a.def.defName) ?? Enumerable.Empty<string>());
                    string weapon = p.equipment?.Primary?.def.defName ?? "-";
                    CompShield shield = p.apparel?.WornApparel.Select(a => a.TryGetComp<CompShield>()).FirstOrDefault(s => s != null);
                    if (shield != null)
                    {
                        bool canFire = p.equipment?.Primary == null || p.equipment.Primary.def.IsMeleeWeapon ||
                                       p.apparel.WornApparel.All(a => a.AllowVerbCast(p.equipment.PrimaryEq.PrimaryVerb));
                        weapon += $" (shield {shield.parent.def.defName} max {shield.parent.GetStatValue(StatDefOf.EnergyShieldEnergyMax):F2}, may fire {canFire})";
                    }
                    string titles = p.royalty == null ? "-" :
                        string.Join(", ", p.royalty.AllTitlesForReading.Select(t => t.def.defName));
                    if (p.apparel != null && p.apparel.WornApparel.Any(a => a.def.apparel?.tags?.Contains(RR_CasteArmor.RestrictedTag) == true)) { plate++; }
                    Log.Message($"[RimRising] KINDS {name} #{i} ({fac.Name}) color={RR_CasteIdentity.ColorOf(p)?.defName ?? "-"} titles=[{titles}] weapon={weapon} apparel=[{apparel}]");
                    Find.WorldPawns.PassToWorld(p, PawnDiscardDecideMode.Discard);
                }
                Log.Message($"[RimRising] KINDS {name}: {plate} in restricted plate of {KindSamples}");
            }
        }

        // ---- rrtestmode=nature: the pitviper's bite and the haemanthus ----------

        private readonly List<(Pawn victim, Pawn viper, IntVec3 mark)> bites =
            new List<(Pawn, Pawn, IntVec3)>();
        private Plant darkFlower, litFlower;
        private float darkStart, litStart;
        private int natureFrames;
        private const int NatureMaxFrames = 9000;

        /// <summary>
        /// rrtestmode=nature. Manhunting pitvipers beside pinned victims, run until
        /// every victim shows toxic buildup (or time runs out), logging each
        /// victim's hediffs. Two haemanthus, one under a roof at glow 0 and one in
        /// noon light, whose growth is compared at the end. Then the sowing checks
        /// through vanilla's own PlantUtility.CanSowOnGrower, and a real helium
        /// barrens map generated to count the flower and the snake wild.
        /// </summary>
        private void BuildNature()
        {
            IntVec3 c = map.Center;
            area = new CellRect(c.x - 4, c.z - 4, 9, 9).ClipInsideMap(map);
            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();

            PawnKindDef viperKind = DefDatabase<PawnKindDef>.GetNamedSilentFail("RR_Pitviper");
            if (viperKind == null) { Log.Message("[RimRising] NATURE no RR_Pitviper kind"); }
            for (int i = 0; viperKind != null && i < 3; i++)
            {
                IntVec3 mark = new IntVec3(area.minX + 1 + i * 3, 0, area.maxZ - 1);
                Pawn victim = MakePawn(BodyTypeDefOf.Male, null, Color.white);
                victim.Name = new NameSingle("Victim " + i);
                GenSpawn.Spawn(victim, mark, map, Rot4.South);
                victim.jobs.StartJob(JobMaker.MakeJob(JobDefOf.Wait, 60000), Verse.AI.JobCondition.InterruptForced);
                Pawn viper = PawnGenerator.GeneratePawn(new PawnGenerationRequest(viperKind, null, forceGenerateNewPawn: true));
                GenSpawn.Spawn(viper, mark + IntVec3.South, map, Rot4.North);
                viper.mindState.mentalStateHandler.TryStartMentalState(MentalStateDefOf.Manhunter, forced: true, forceWake: true);
                bites.Add((victim, viper, mark));
            }

            ThingDef flower = DefDatabase<ThingDef>.GetNamedSilentFail("RR_Haemanthus");
            if (flower == null) { Log.Message("[RimRising] NATURE no RR_Haemanthus"); return; }
            IntVec3 dark = new IntVec3(area.minX + 1, 0, area.minZ + 1);
            IntVec3 lit = new IntVec3(area.maxX - 1, 0, area.minZ + 1);
            foreach (IntVec3 cell in new[] { dark, lit })
            {
                map.terrainGrid.SetTerrain(cell, TerrainDefOf.Soil);
            }
            map.roofGrid.SetRoof(dark, RoofDefOf.RoofConstructed);
            darkFlower = (Plant)GenSpawn.Spawn(flower, dark, map);
            litFlower = (Plant)GenSpawn.Spawn(flower, lit, map);
            darkFlower.Growth = litFlower.Growth = darkStart = litStart = 0.1f;

            // Sowing: the same call the growing-zone and plant-pot UIs make.
            var zone = new Zone_Growing(map.zoneManager);
            map.zoneManager.RegisterZone(zone);
            zone.AddCell(new IntVec3(area.minX + 4, 0, area.minZ + 1));
            Log.Message($"[RimRising] NATURE sow: growing zone {PlantUtility.CanSowOnGrower(flower, zone)}");
            ThingDef potDef = DefDatabase<ThingDef>.GetNamedSilentFail("PlantPot");
            if (potDef != null)
            {
                Thing pot = GenSpawn.Spawn(ThingMaker.MakeThing(potDef, GenStuff.DefaultStuffFor(potDef)),
                    new IntVec3(area.minX + 5, 0, area.minZ + 1), map);
                Log.Message($"[RimRising] NATURE sow: plant pot {PlantUtility.CanSowOnGrower(flower, pot)} (pot sowTag {potDef.building?.sowTag})");
            }
            Log.Message($"[RimRising] NATURE built {bites.Count} viper/victim pairs");
        }

        private void NatureStep()
        {
            natureFrames++;
            bool allBitten = bites.All(b => b.victim.health.hediffSet.HasHediff(HediffDefOf.ToxicBuildup) || b.victim.Dead);
            if (natureFrames % 30 == 0 && !allBitten)
            {
                foreach (var b in bites)
                {
                    if (b.victim.Dead || !b.victim.Spawned) { continue; }
                    // Hurt factionless victims flee - same as the whip targets.
                    if (b.victim.Position != b.mark) { b.victim.Position = b.mark; b.victim.Notify_Teleported(); }
                    if (!b.victim.Downed)
                    {
                        b.victim.mindState?.mentalStateHandler?.Reset();
                        b.victim.jobs.StartJob(JobMaker.MakeJob(JobDefOf.Wait, 60000), Verse.AI.JobCondition.InterruptForced);
                    }
                    if (!b.viper.Dead && b.viper.Spawned && !b.viper.InMentalState)
                    {
                        b.viper.mindState.mentalStateHandler.TryStartMentalState(MentalStateDefOf.Manhunter, forced: true, forceWake: true);
                    }
                }
            }
            if (allBitten)
            {
                // Freeze the bite result: the snakes go, the flowers keep growing.
                foreach (var b in bites) { if (b.viper.Spawned) { b.viper.Destroy(); } }
            }
            // The flowers need game time to show growth: half a day at least.
            if (natureStartTick < 0) { natureStartTick = Find.TickManager.TicksGame; }
            bool flowersDone = Find.TickManager.TicksGame - natureStartTick >= 30000;
            if ((!allBitten || !flowersDone) && natureFrames < NatureMaxFrames) { return; }

            // Finish exactly once. Anything below that throws must not leave the
            // stage live, or the update retries it every frame - which it did,
            // flooding the log until the process was killed.
            stage = -1;
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            try { NatureReport(); }
            catch (System.Exception e) { Log.Error("[RimRising] NATURE report threw: " + e); }
            Log.Message("[RimRising] TESTSCENE DONE (nature)");
            if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
        }

        private int natureStartTick = -1;

        private void NatureReport()
        {
            foreach (var b in bites)
            {
                Hediff tox = b.victim.health.hediffSet.GetFirstHediffOfDef(HediffDefOf.ToxicBuildup);
                string injuries = string.Join(", ", b.victim.health.hediffSet.hediffs.OfType<Hediff_Injury>()
                    .Select(h => $"{h.def.defName}@{h.Part?.def.defName}"));
                Log.Message($"[RimRising] NATURE bite {b.victim.Name}: toxic={(tox == null ? "NONE" : tox.Severity.ToString("F3"))} " +
                            $"toxRes={b.victim.GetStatValue(StatDefOf.ToxicResistance):F2} injuries=[{injuries}]");
            }
            Log.Message($"[RimRising] NATURE ran {natureFrames} frames, {Find.TickManager.TicksGame - natureStartTick} ticks");

            if (darkFlower != null)
            {
                Log.Message($"[RimRising] NATURE flower dark: glow {map.glowGrid.GroundGlowAt(darkFlower.Position):F2} " +
                            $"lightFactor {darkFlower.GrowthRateFactor_Light:F2} rate {darkFlower.GrowthRate:F2} " +
                            $"growth {darkStart:F3} -> {darkFlower.Growth:F3}");
                Log.Message($"[RimRising] NATURE flower lit: glow {map.glowGrid.GroundGlowAt(litFlower.Position):F2} " +
                            $"lightFactor {litFlower.GrowthRateFactor_Light:F2} rate {litFlower.GrowthRate:F2} " +
                            $"growth {litStart:F3} -> {litFlower.Growth:F3}");
                Log.Message($"[RimRising] NATURE flower light factor at glow 0 (engine formula): " +
                            $"{PlantUtility.GrowthRateFactorFor_Light(darkFlower.def, 0f):F2}");
            }
            NatureWorldgen();
        }

        /// <summary>Generate a real map on a barrens tile and count what grew wild.</summary>
        private void NatureWorldgen()
        {
            ThingDef flower = DefDatabase<ThingDef>.GetNamedSilentFail("RR_Haemanthus");
            BiomeDef barrens = DefDatabase<BiomeDef>.AllDefs.FirstOrDefault(b => flower != null && b.CommonalityOfPlant(flower) > 0f);
            if (barrens == null) { Log.Message("[RimRising] NATURE worldgen: no biome lists the flower"); return; }
            var surface = Find.WorldGrid.Surface;
            PlanetTile tile = PlanetTile.Invalid;
            for (int i = 0; i < Find.WorldGrid.TilesCount; i++)
            {
                PlanetTile t = surface.PlanetTileForID(i);
                if (Find.WorldGrid[t].PrimaryBiome == barrens && !Find.WorldObjects.AnyWorldObjectAt(t)) { tile = t; break; }
            }
            if (!tile.Valid) { Log.Message($"[RimRising] NATURE worldgen: no free {barrens.defName} tile in this world"); return; }
            Map gen = GetOrGenerateMapUtility.GetOrGenerateMap(tile, new IntVec3(150, 1, 150), WorldObjectDefOf.Debug_Arena);
            int flowers = gen.listerThings.ThingsOfDef(flower).Count;
            int vipers = gen.mapPawns.AllPawnsSpawned.Count(p => p.def.defName == "RR_Pitviper");
            int animals = gen.mapPawns.AllPawnsSpawned.Count(p => p.RaceProps.Animal);
            string kinds = string.Join(", ", gen.mapPawns.AllPawnsSpawned.Where(p => p.RaceProps.Animal).GroupBy(p => p.def.defName).Select(g => g.Key + " " + g.Count()));
            Log.Message($"[RimRising] NATURE worldgen generator {gen.Parent.MapGeneratorDef?.defName}, animals {animals}: {kinds}");
            Log.Message($"[RimRising] NATURE worldgen {barrens.defName} 150x150: haemanthus {flowers}, pitvipers {vipers} " +
                        $"(flower commonality {barrens.CommonalityOfPlant(flower):F2})");
            Current.Game.DeinitAndRemoveMap(gen, false);
        }

        // ---- rrtestmode=marks: the caste-mark tattoos on skin ----------------------

        /// <summary>
        /// rrtestmode=marks. One pawn of each marked kind per column (Helmsman,
        /// tribe warrior, Legionary), stripped so the body marks show, one row per
        /// facing; factionless and paused. CasteMarks.cs stamps the tattoos.
        /// </summary>
        private void BuildMarks()
        {
            TargetOrtho = 3.2f;
            string[] kinds = { "RR_Society_Blue_Helmsman", "RR_Tribe_Obsidian_Warrior", "RR_Society_Legionary" };
            IntVec3 c = map.Center;
            area = new CellRect(c.x - 3, c.z - 3, 7, 7).ClipInsideMap(map);
            Clear(area.ExpandedBy(3).ClipInsideMap(map));
            SetNoon();
            for (int k = 0; k < kinds.Length; k++)
            {
                for (int f = 0; f < Facings.Length; f++)
                {
                    Pawn p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(DefDatabase<PawnKindDef>.GetNamed(kinds[k]), null,
                        forceGenerateNewPawn: true, developmentalStages: DevelopmentalStage.Adult, fixedBiologicalAge: 30f, fixedChronologicalAge: 30f));
                    p.apparel?.DestroyAll();
                    p.equipment?.DestroyAllEquipment();
                    p.story.hairDef = HairDefOf.Bald;
                    GenSpawn.Spawn(p, new IntVec3(area.minX + 1 + k * 2, 0, area.maxZ - 1 - f * 2), map, Facings[f]);
                    p.Rotation = Facings[f];
                    p.Drawer.renderer.SetAllGraphicsDirty();
                    Log.Message($"[RimRising] MARKS {kinds[k]} {Facings[f]}: face {p.style?.FaceTattoo?.defName}, body {p.style?.BodyTattoo?.defName}");
                }
            }
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            shots.Add(("marks", new Vector3(area.minX + 3.5f, 0f, area.maxZ - 2.5f), 0f));
        }

        // ---- rrtestmode=raid: war griffins in an Obsidian tribe raid --------------

        private Faction raidFac;
        private readonly List<Pawn> raidGriffins = new List<Pawn>();
        private int raidFrames, raidErrorsAtStart;

        /// <summary>
        /// rrtestmode=raid. First, Obsidian tribe Combat groups generated straight
        /// from the faction's PawnGroupMaker, counting griffins - does the maker
        /// accept an animal option at all. Then a real RaidEnemy from the tribes,
        /// with two griffins of the tribe added to the raid's lord the way the
        /// group maker would deliver them, run at speed: do they take the lord's
        /// duty, close on the colony and fight, and does anything log an error.
        /// </summary>
        private void BuildRaid()
        {
            raidFac = FactionOf("RR_ObsidianTribes");
            if (raidFac == null)
            {
                FactionDef fd = DefDatabase<FactionDef>.GetNamed("RR_ObsidianTribes");
                raidFac = FactionGenerator.NewGeneratedFaction(new FactionGeneratorParms(fd));
                Find.FactionManager.Add(raidFac);
                Log.Message("[RimRising] RAID generated the tribes faction (not in this world)");
            }
            int griffinsInGroups = 0, pawnsInGroups = 0;
            for (int i = 0; i < 20; i++)
            {
                var parms = new PawnGroupMakerParms
                {
                    groupKind = PawnGroupKindDefOf.Combat, faction = raidFac, points = 3000f,
                    tile = map.Tile, inhabitants = false
                };
                foreach (Pawn p in PawnGroupMakerUtility.GeneratePawns(parms, false))
                {
                    pawnsInGroups++;
                    if (p.def.defName == "RR_Griffin") { griffinsInGroups++; }
                    Discard(p);
                }
            }
            Log.Message($"[RimRising] RAID groups: {griffinsInGroups} griffins among {pawnsInGroups} pawns in 20 tribe Combat groups at 3000 points");

            // The tribes use goodwill; SetRelationDirect is overridden by it, and the
            // first run's raid wandered with no targets because it was not hostile.
            raidFac.TryAffectGoodwillWith(Faction.OfPlayer, -200, false, false);
            Log.Message($"[RimRising] RAID tribes hostile to the colony: {raidFac.HostileTo(Faction.OfPlayer)} (goodwill {raidFac.PlayerGoodwill})");
            raidErrorsAtStart = RR_LogErrorCount();
            var rp = new IncidentParms
            {
                target = map, faction = raidFac, points = 1500f, forced = true,
                raidStrategy = RaidStrategyDefOf.ImmediateAttack, raidArrivalMode = PawnsArrivalModeDefOf.EdgeWalkIn
            };
            bool fired = IncidentDefOf.RaidEnemy.Worker.TryExecute(rp);
            Pawn anyRaider = map.mapPawns.SpawnedPawnsInFaction(raidFac).FirstOrDefault();
            Verse.AI.Group.Lord lord = anyRaider == null ? null : Verse.AI.Group.LordUtility.GetLord(anyRaider);
            PawnKindDef gk = DefDatabase<PawnKindDef>.GetNamed("RR_Griffin");
            for (int i = 0; i < 2 && anyRaider != null; i++)
            {
                Pawn g = PawnGenerator.GeneratePawn(new PawnGenerationRequest(gk, raidFac, forceGenerateNewPawn: true));
                IntVec3 at = CellFinder.RandomClosewalkCellNear(anyRaider.Position, map, 4);
                GenSpawn.Spawn(g, at, map);
                lord?.AddPawn(g);
                raidGriffins.Add(g);
            }
            Log.Message($"[RimRising] RAID fired {fired}: {map.mapPawns.SpawnedPawnsInFaction(raidFac).Count} raiders, lord {lord?.LordJob?.GetType().Name ?? "none"}, griffins added {raidGriffins.Count}");
        }

        private static int RR_LogErrorCount()
        {
            return Verse.Log.Messages.Count(m => m.type == LogMessageType.Error);
        }

        private void RaidStep()
        {
            raidFrames++;
            if (raidFrames % 300 == 0 || raidFrames >= 2400)
            {
                Pawn human = map.mapPawns.SpawnedPawnsInFaction(raidFac).FirstOrDefault(x => x.RaceProps.Humanlike && !x.Dead);
                foreach (Pawn g in raidGriffins.Concat(human == null ? Enumerable.Empty<Pawn>() : new[] { human }))
                {
                    var probe = new JobGiver_AIGotoNearestHostile();
                    Verse.AI.Job pj = null;
                    try { pj = probe.TryIssueJobPackage(g, default(Verse.AI.JobIssueParams)).Job; } catch { }
                    int targets = map.attackTargetsCache.GetPotentialTargetsFor(g).Count;
                    Log.Message($"[RimRising] RAID t{raidFrames} probe {g.LabelShort}: attack targets {targets}, goto-hostile gives {pj?.def?.defName ?? "null"}");
                    Pawn near = map.mapPawns.FreeColonistsSpawned.OrderBy(c => c.Position.DistanceTo(g.Position)).FirstOrDefault();
                    Log.Message($"[RimRising] RAID t{raidFrames} griffin {g.LabelShort}: {(g.Dead ? "dead" : g.Downed ? "downed" : "up")}, " +
                                $"job {g.CurJobDef?.defName ?? "-"}, duty {g.mindState?.duty?.def?.defName ?? "-"}, " +
                                $"lord {(Verse.AI.Group.LordUtility.GetLord(g) != null)}, nearest colonist {(near == null ? -1 : g.Position.DistanceTo(near.Position)):F0} cells");
                }
            }
            if (raidFrames < 2400) { return; }
            stage = -1;
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            int hurt = map.mapPawns.FreeColonists.Count(c => c.health.hediffSet.hediffs.OfType<Hediff_Injury>().Any());
            Log.Message($"[RimRising] RAID end: {hurt} colonists injured, {RR_LogErrorCount() - raidErrorsAtStart} new log errors");
            Log.Message("[RimRising] TESTSCENE DONE (raid)");
            if (GenCommandLine.CommandLineArgPassed("rrtestquit")) { Root.Shutdown(); }
        }

        // ---- rrtestmode=m12: the second content pass, checked in code ----------

        private int m12Ok, m12Fail;

        private void Check(string name, bool ok, string detail)
        {
            if (ok) { m12Ok++; } else { m12Fail++; }
            Log.Message($"[RimRising] M12 {(ok ? "OK  " : "FAIL")} {name}: {detail}");
        }

        private void Run(string name, System.Action body)
        {
            try { body(); }
            catch (System.Exception e) { Check(name, false, "threw " + e.GetType().Name + ": " + e.Message); }
        }

        private static Faction FactionOf(string defName) =>
            Find.FactionManager.AllFactionsListForReading.FirstOrDefault(f => f.def.defName == defName);

        private static Pawn Gen(string kind, Faction fac) =>
            PawnGenerator.GeneratePawn(new PawnGenerationRequest(DefDatabase<PawnKindDef>.GetNamed(kind), fac,
                forceGenerateNewPawn: true, developmentalStages: DevelopmentalStage.Adult));

        private Pawn Colonist(XenotypeDef x, Ideo ideo)
        {
            Pawn p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(PawnKindDefOf.Colonist, Faction.OfPlayer,
                forceGenerateNewPawn: true, forcedXenotype: x, forceNoIdeo: true,
                developmentalStages: DevelopmentalStage.Adult, fixedBiologicalAge: 30f, fixedChronologicalAge: 30f));
            if (ideo != null) { p.ideo?.SetIdeo(ideo); }
            return p;
        }

        private static void Discard(Pawn p)
        {
            if (p == null) { return; }
            if (p.Spawned) { p.DeSpawn(); }
            if (!p.Dead && !Find.WorldPawns.Contains(p)) { Find.WorldPawns.PassToWorld(p, PawnDiscardDecideMode.Discard); }
        }

        /// <summary>
        /// rrtestmode=m12: PROGRESS.md's Milestone 12 click-list, as far as each item
        /// can be decided from code in a live game. Logs one M12 line per check.
        /// </summary>
        private void Milestone12()
        {
            Faction society = FactionOf("RR_Society"), ares = FactionOf("RR_SonsOfAres"), tribes = FactionOf("RR_ObsidianTribes");
            Ideo hierarchy = society?.ideos?.PrimaryIdeo, equality = ares?.ideos?.PrimaryIdeo;
            Log.Message($"[RimRising] M12 factions: society {society != null} ares {ares != null} tribes {tribes != null}; " +
                        $"hierarchy ideo '{hierarchy?.name}', equality ideo '{equality?.name}'");
            XenotypeDef red = DefDatabase<XenotypeDef>.GetNamed("RR_Red"), gold = DefDatabase<XenotypeDef>.GetNamed("RR_Gold");

            // 1. Traders: every RR faction's caravans are ours; census caravans pay favour.
            Run("1 traders", () =>
            {
                foreach (FactionDef fd in DefDatabase<FactionDef>.AllDefs.Where(d => d.defName.StartsWith("RR_") && !d.isPlayer))
                {
                    // Other mods patch caravans onto every faction (RJW does); judge only
                    // what this mod and vanilla put there.
                    var kinds = (fd.caravanTraderKinds ?? new List<TraderKindDef>())
                        .Where(k => k.modContentPack == null || k.modContentPack.IsCoreMod || k.modContentPack.IsOfficialMod ||
                                    k.modContentPack.PackageId == "cinergy92.rimrising").ToList();
                    bool own = kinds.Count == 0 || kinds.All(k => k.defName.StartsWith("RR_")) || fd.defName == "RR_SonsOfAres";
                    Check("1 caravans " + fd.defName, own,
                          kinds.Count == 0 ? "none (no caravans)" : string.Join(", ", kinds.Select(k => k.defName)) +
                          (fd.defName == "RR_SonsOfAres" ? " (Ares trade as outlanders by design)" : ""));
                }
                ThingDef he3 = DefDatabase<ThingDef>.GetNamed("RR_HeliumThree"), ion = DefDatabase<ThingDef>.GetNamed("RR_Ionsteel");
                foreach (string c in new[] { "RR_Caravan_Society_Census", "RR_Caravan_Dominion_Census" })
                {
                    TraderKindDef tk = DefDatabase<TraderKindDef>.GetNamed(c);
                    Check("1 " + c, tk.tradeCurrency == TradeCurrency.Favor && tk.WillTrade(he3) && tk.WillTrade(ion) &&
                                    !tk.WillTrade(ThingDefOf.Steel) && !tk.WillTrade(ThingDefOf.Plasteel),
                          $"currency {tk.tradeCurrency}, buys helium {tk.WillTrade(he3)} ionsteel {tk.WillTrade(ion)} steel {tk.WillTrade(ThingDefOf.Steel)}; " +
                          $"favour per helium {he3.GetStatValueAbstract(StatDefOf.RoyalFavorValue):F3}, per ionsteel {ion.GetStatValueAbstract(StatDefOf.RoyalFavorValue):F3}");
                }
            });

            // 2. Heirloom razor: named, bladelinked, refused to a Red.
            Run("2 heirloom", () =>
            {
                Thing h = ThingMaker.MakeThing(DefDatabase<ThingDef>.GetNamed("RR_Weapon_Razor_Heirloom"));
                string name = h.TryGetComp<CompGeneratedNames>()?.Name;
                bool link = h.TryGetComp<CompBladelinkWeapon>() != null;
                Pawn r = Colonist(red, hierarchy), g = Colonist(gold, hierarchy);
                bool redCan = EquipmentUtility.CanEquip(h, r, out string why), goldCan = EquipmentUtility.CanEquip(h, g);
                bool whip = h.TryGetComp<CompEquippableAbility>() != null;
                Check("2 heirloom", !name.NullOrEmpty() && link && !redCan && goldCan && whip,
                      $"name '{name}', bladelink {link}, Red may equip {redCan} ({why}), Gold may equip {goldCan}, whip ability {whip}");
                Discard(r); Discard(g);
            });

            // 3. Trial by razor in the hierarchy ideoligion.
            Run("3 trial", () =>
            {
                bool has = hierarchy != null && hierarchy.PreceptsListForReading.Any(p => p.def.defName == "RR_Ritual_RazorTrial");
                Check("3 trial by razor", has, $"in '{hierarchy?.name}': {has}");
            });

            // 4. SlingBlade: craftable with no research; Ares kinds can carry it.
            Run("4 slingBlade", () =>
            {
                ThingDef sb = DefDatabase<ThingDef>.GetNamed("RR_Weapon_SlingBlade");
                RecipeDef make = DefDatabase<RecipeDef>.AllDefs.FirstOrDefault(r => r.ProducedThingDef == sb);
                int carried = 0, n = 0;
                foreach (PawnKindDef k in DefDatabase<PawnKindDef>.AllDefs.Where(k => k.defName.StartsWith("RR_Ares_")))
                {
                    for (int i = 0; i < 8; i++) { Pawn p = Gen(k.defName, ares); n++; if (p.equipment?.Primary?.def == sb) { carried++; } Discard(p); }
                }
                Check("4 slingBlade", make != null && make.researchPrerequisite == null && (make.researchPrerequisites == null || make.researchPrerequisites.Count == 0),
                      $"recipe {make?.defName ?? "NONE"} at {string.Join("/", make?.recipeUsers?.Select(u => u.defName) ?? Enumerable.Empty<string>())}, " +
                      $"research {make?.researchPrerequisite?.defName ?? "none"}; Ares pawns carrying it {carried}/{n}");
            });

            // 5. Caste marks.
            Run("5 marks", () =>
            {
                foreach (string k in new[] { "RR_Society_Blue_Helmsman", "RR_Tribe_Obsidian_Warrior", "RR_Society_Legionary" })
                {
                    Faction f = k.StartsWith("RR_Tribe") ? tribes : society;
                    var seen = new List<string>();
                    for (int i = 0; i < 10; i++)
                    {
                        Pawn p = Gen(k, f);
                        string t = (p.style?.FaceTattoo?.defName ?? "") + "|" + (p.style?.BodyTattoo?.defName ?? "");
                        seen.Add(t);
                        Discard(p);
                    }
                    int marked = seen.Count(s => s.Contains("RR_Tattoo_"));
                    Check("5 marks " + k, marked == 10, $"{marked}/10 marked: {string.Join(", ", seen.Distinct())}");
                }
            });

            // 6. Howlers.
            Run("6 howlers", () =>
            {
                var outfits = new List<string>();
                for (int i = 0; i < 6; i++)
                {
                    Pawn p = Gen("RR_Ares_Howler", ares);
                    outfits.Add(string.Join("+", p.apparel.WornApparel.Select(a => a.def.defName.Replace("RR_Apparel_", ""))));
                    Discard(p);
                }
                bool pelt = outfits.All(o => o.Contains("HowlerPelt") && o.Contains("ScarabSkin") && o.Contains("DemonHelm"));
                Check("6 howler", pelt, string.Join(" ; ", outfits));
                bool inRaids = ares.def.pawnGroupMakers.Any(g => g.options != null && g.options.Any(o => o.kind.defName == "RR_Ares_Howler"));
                Check("6 howler in Ares groups", inRaids, inRaids.ToString());
            });

            // 7. Carving aftermath and the carved pawn's own thought.
            Run("7 carving", () =>
            {
                RecipeDef carve = DefDatabase<RecipeDef>.GetNamed("RR_Carve_Gold");
                foreach (Ideo ideo in new[] { hierarchy, equality })
                {
                    Pawn p = Colonist(red, ideo);
                    carve.Worker.ApplyOnPawn(p, null, null, new List<Thing>(), null);
                    bool rec = p.health.hediffSet.hediffs.Any(h => h.def.defName == "RR_CarvingRecovery");
                    string mem = string.Join(", ", p.needs?.mood?.thoughts?.memories?.Memories?.Select(m => m.def.defName) ?? Enumerable.Empty<string>());
                    Check("7 carving under '" + ideo?.name + "'", rec && mem.Contains("RR_WasCarved"),
                          $"reads {RR_CasteIdentity.ColorOf(p)?.defName}, recovery {rec}, memories [{mem}]");
                    Discard(p);
                }
            });

            // 8. Sigils.
            Run("8 sigils", () =>
            {
                Pawn s = Gen("RR_Society_Legionary", society);
                HediffDef sig = RR_Sigils.SigilOf(s);
                Hediff sh = s.health.hediffSet.hediffs.FirstOrDefault(h => h.def == sig);
                Pawn t = Gen("RR_Tribe_Obsidian_Warrior", tribes);
                Check("8 sigil on Society pawn", sig != null && sig == RR_Sigils.SigilFor(RR_CasteIdentity.ColorOf(s)),
                      $"{RR_CasteIdentity.ColorOf(s)?.defName} has {sig?.defName ?? "none"} on {sh?.Part?.def.defName ?? "-"}");
                Check("8 no sigil on tribe pawn", RR_Sigils.SigilOf(t) == null, RR_Sigils.SigilOf(t)?.defName ?? "none");
                RecipeDef forge = DefDatabase<RecipeDef>.GetNamed("RR_ForgeSigil_Gold");
                XenotypeDef before = RR_CasteIdentity.ColorOf(s);
                forge.Worker.ApplyOnPawn(s, null, null, new List<Thing>(), null);
                Check("8 forge", RR_Sigils.SigilOf(s)?.defName == "RR_Sigil_Gold" && RR_CasteIdentity.ColorOf(s) == before && RR_Sigils.SigilMismatch(s),
                      $"now {RR_Sigils.SigilOf(s)?.defName}, still reads {RR_CasteIdentity.ColorOf(s)?.defName}, mismatch {RR_Sigils.SigilMismatch(s)}");
                Discard(s); Discard(t);
            });

            // 9. Caste labour thoughts.
            Run("9 labour", () =>
            {
                WorkGiverDef research = DefDatabase<WorkGiverDef>.AllDefs.First(w => w.workType == WorkTypeDefOf.Research);
                WorkGiverDef haul = DefDatabase<WorkGiverDef>.AllDefs.First(w => w.workType == WorkTypeDefOf.Hauling);
                foreach (Ideo ideo in new[] { hierarchy, equality })
                {
                    Pawn p = Colonist(red, ideo);
                    GenSpawn.Spawn(p, map.Center, map);
                    string Mood(WorkGiverDef wg)
                    {
                        Verse.AI.Job j = JobMaker.MakeJob(JobDefOf.Wait, 600);
                        j.workGiverDef = wg;
                        p.jobs.StartJob(j, Verse.AI.JobCondition.InterruptForced);
                        // Situational thoughts are cached and refreshed on an interval.
                        p.needs.mood.thoughts.situational.Notify_SituationalThoughtsDirty();
                        var list = new List<Thought>();
                        p.needs.mood.thoughts.situational.AppendMoodThoughts(list);
                        return string.Join(",", list.Where(x => x.def.defName.Contains("CasteLabor") || (x.def.Worker?.GetType().Name.Contains("CasteLabor") ?? false))
                                                    .Select(x => x.def.defName));
                    }
                    string atResearch = Mood(research), atHaul = Mood(haul);
                    Check("9 labour under '" + ideo?.name + "'", atResearch.Length > 0 && atHaul.Length == 0,
                          $"Red researching [{atResearch}], hauling [{atHaul}]");
                    Discard(p);
                }
            });

            // 10. Helium-3 under the map.
            Run("10 helium", () =>
            {
                ThingDef he3 = DefDatabase<ThingDef>.GetNamed("RR_HeliumThree");
                // 1.6 places deep lumps lazily, when a scanner finds one, picking by
                // deepCommonality (CompDeepScanner.ChooseLumpThingDef). A fresh map's
                // grid is empty, so judge helium's share of that weighted pick.
                var pool = DefDatabase<ThingDef>.AllDefs.Where(d => d.deepCommonality > 0f).ToList();
                float total = pool.Sum(d => d.deepCommonality);
                Check("10 helium in the deep-lump pool", he3.deepCommonality > 0f,
                      $"{he3.deepCommonality / total:P0} of finds; pool: {string.Join(", ", pool.Select(d => $"{d.defName} {d.deepCommonality}"))}; " +
                      $"{he3.deepCountPerPortion} per portion, lumps {he3.deepLumpSizeRange}");
            });

            // 11. The Institute.
            Run("11 institute", () =>
            {
                ScenarioDef sc = DefDatabase<ScenarioDef>.GetNamed("RR_Scenario_Institute");
                var errs = sc.scenario.ConfigErrors().ToList();
                Check("11 institute", errs.Count == 0, errs.Count == 0 ? "no config errors; " + sc.scenario.GetSummary().Replace("\n", " ") : string.Join("; ", errs));
            });

            // 12. Swill.
            Run("12 swill", () =>
            {
                ThingDef swill = DefDatabase<ThingDef>.GetNamed("RR_Swill");
                RecipeDef make = DefDatabase<RecipeDef>.AllDefs.FirstOrDefault(r => r.ProducedThingDef == swill);
                Pawn p = Colonist(red, null);
                Thing drink = ThingMaker.MakeThing(swill);
                drink.Ingested(p, 0f);
                string hed = string.Join(", ", p.health.hediffSet.hediffs.Select(h => h.def.defName));
                Check("12 swill", make != null && hed.Contains("RR_SwillHigh"),
                      $"recipe {make?.defName} x{make?.products?.FirstOrDefault()?.count} at {string.Join("/", make?.recipeUsers?.Select(u => u.defName) ?? Enumerable.Empty<string>())}; after drinking [{hed}]");
                Discard(p);
            });

            // 13. The Laurel and the census letter: only with a lowColor in the colony.
            Run("13 letters", () =>
            {
                IncidentDef laurel = DefDatabase<IncidentDef>.GetNamed("RR_Incident_LaurelQuota");
                IncidentDef census = DefDatabase<IncidentDef>.GetNamed("RR_Incident_CensusLetter");
                // CanFireNow also refuses before def.earliestDay, which a fresh map is
                // always under; the Color condition lives in CanFireNowSub.
                var sub = typeof(IncidentWorker).GetMethod("CanFireNowSub",
                    System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
                bool Can(IncidentDef d) => (bool)sub.Invoke(d.Worker, new object[] { StorytellerUtility.DefaultParmsNow(d.category, map) });
                var spawned = new List<Pawn>();
                foreach (Pawn c in map.mapPawns.FreeColonists.ToList()) { c.DeSpawn(); spawned.Add(c); }
                Pawn g = Colonist(gold, null); GenSpawn.Spawn(g, map.Center, map);
                bool goldOnlyL = Can(laurel), goldOnlyC = Can(census);
                Pawn r = Colonist(red, null); GenSpawn.Spawn(r, map.Center + IntVec3.East, map);
                bool withRedL = Can(laurel), withRedC = Can(census);
                int before = Find.Storyteller.incidentQueue.Count;
                bool fired = laurel.Worker.TryExecute(StorytellerUtility.DefaultParmsNow(laurel.category, map));
                bool queued = Find.Storyteller.incidentQueue.Count == before + 1;
                Check("13 laurel/census", !goldOnlyL && !goldOnlyC && withRedL && withRedC && fired && queued,
                      $"Gold-only: laurel {goldOnlyL} census {goldOnlyC}; with a Red: laurel {withRedL} census {withRedC}; " +
                      $"laurel fired {fired}, award queued {queued} (earliest days: laurel {laurel.earliestDay}, census {census.earliestDay})");
                Discard(g); Discard(r);
                foreach (Pawn c in spawned) { GenSpawn.Spawn(c, map.Center + IntVec3.North * 2, map); }
            });

            // 14. Griffins at the quartermaster.
            Run("14 griffin", () =>
            {
                TraderKindDef qm = DefDatabase<TraderKindDef>.GetNamed("RR_Caravan_Society_Armory");
                int griffins = 0;
                for (int i = 0; i < 20; i++)
                {
                    foreach (StockGenerator sg in qm.stockGenerators)
                    {
                        foreach (Thing t in sg.GenerateThings(map.Tile, society))
                        {
                            if (t.def.defName == "RR_Griffin") { griffins++; }
                            if (t is Pawn pp) { Discard(pp); } else { t.Destroy(); }
                        }
                    }
                }
                ThingDef gr = DefDatabase<ThingDef>.GetNamed("RR_Griffin");
                Check("14 griffin", griffins > 0, $"{griffins} griffins in 20 quartermaster stocks; trainability {gr.race.trainability?.defName}");
            });

            // 15. Colour roles: assignable only to the right Colour.
            Run("15 roles", () =>
            {
                var want = new (string role, string color)[] {
                    ("RR_Role_Physician", "RR_Yellow"), ("RR_Role_Engineer", "RR_Orange"), ("RR_Role_Pilot", "RR_Blue"),
                    ("RR_Role_Arbiter", "RR_White"), ("RR_Role_Shaman", "RR_Obsidian") };
                foreach (var (role, color) in want)
                {
                    PreceptDef def = DefDatabase<PreceptDef>.GetNamed(role);
                    Ideo host = hierarchy;
                    Precept_Role pr = (Precept_Role)PreceptMaker.MakePrecept(def);
                    pr.ideo = host;
                    Pawn right = Colonist(DefDatabase<XenotypeDef>.GetNamed(color), host), wrong = Colonist(red, host);
                    bool okRight = def.roleRequirements.Where(q => q is RoleRequirement_Xenotype).All(q => q.Met(right, pr));
                    bool okWrong = def.roleRequirements.Where(q => q is RoleRequirement_Xenotype).All(q => q.Met(wrong, pr));
                    Check("15 role " + role, okRight && !okWrong, $"{color} meets {okRight}, Red meets {okWrong}; name '{pr.GenerateNameRaw()}'");
                    Discard(right); Discard(wrong);
                }
            });

            // 16. ClawDrill: a colonist will take the job.
            Run("16 clawDrill", () =>
            {
                ThingDef cd = DefDatabase<ThingDef>.GetNamed("RR_ClawDrill");
                IntVec3 at = map.Center + new IntVec3(6, 0, 6);
                Clear(CellRect.CenteredOn(at, 3).ClipInsideMap(map));
                var b = (Building)GenSpawn.Spawn(ThingMaker.MakeThing(cd), at, map, Rot4.North);
                b.SetFaction(Faction.OfPlayer);
                b.TryGetComp<CompPowerTrader>().PowerOn = true;
                Pawn p = map.mapPawns.FreeColonists.First();
                var wg = new WorkGiver_ClawDrill { def = DefDatabase<WorkGiverDef>.GetNamed("RR_DrillClaw") };
                bool skip = wg.ShouldSkip(p), job = wg.HasJobOnThing(p, b);
                Check("16 clawDrill", !skip && job,
                      $"size {cd.size}, power {cd.GetCompProperties<CompProperties_Power>()?.PowerConsumption}, research {string.Join("/", cd.researchPrerequisites.Select(r => r.defName))}; " +
                      $"giver skips {skip}, colonist has job {job}, interaction cell {b.InteractionCell - b.Position}");
                b.Destroy();
            });

            // 17. Combat drugs.
            Run("17 drugs", () =>
            {
                foreach ((string k, Faction f) in new[] { ("RR_Society_Legionary", society), ("RR_Society_Lurcher", society), ("RR_Tribe_Obsidian_Warrior", tribes) })
                {
                    var drugs = new List<string>();
                    // 50, not 20: a Lurcher's drug chance is low enough that 20 drew none once.
                    for (int i = 0; i < 50; i++)
                    {
                        Pawn p = Gen(k, f);
                        drugs.AddRange(p.inventory.innerContainer.Where(t => t.def.IsDrug).Select(t => t.def.defName));
                        Discard(p);
                    }
                    Check("17 drugs " + k, drugs.Count > 0, $"{drugs.Count} drugs in 50: {string.Join(", ", drugs.Distinct())}");
                }
            });

            // 18. Dragons Descent, when active: its creatures read as Carver-made.
            // (Its orange dragon is commented out in that mod's own defs.)
            Run("18 dragons", () =>
            {
                if (!ModsConfig.IsActive("onyxae.dragonsdescent")) { Log.Message("[RimRising] M12 skip 18: Dragons Descent not active"); return; }
                var names = new[] { "Black_Dragon", "Blue_Dragon", "Green_Dragon", "Purple_Dragon", "Red_Dragon",
                                    "White_Dragon", "Yellow_Dragon", "Gold_Dragon", "Silver_Dragon", "Jade_Dragon", "True_Dragon", "DD_Drake" };
                var carved = names.Where(n => DefDatabase<ThingDef>.GetNamedSilentFail(n)?.description?.Contains("Carv") == true).ToList();
                Check("18 dragons carved", carved.Count == names.Length,
                      $"{carved.Count}/{names.Length} retold; missing: {string.Join(", ", names.Except(carved))}");
            });

            // ---- Fable's remaining notes (2026-10-10) ----

            // 19. Giddy-Up, when active: griffins rideable, Obsidian factions mount up.
            Run("19 giddyup", () =>
            {
                if (!ModsConfig.IsActive("MemeGoddess.GiddyUp")) { Log.Message("[RimRising] M12 skip 19: Giddy-Up not active"); return; }
                ThingDef gr = DefDatabase<ThingDef>.GetNamed("RR_Griffin");
                var cache = HarmonyLib.AccessTools.Field(HarmonyLib.AccessTools.TypeByName("GiddyUp.ModSettings_GiddyUp"), "MountableCache")?.GetValue(null) as HashSet<ushort>;
                bool mountable = cache != null && cache.Contains(gr.shortHash);
                bool tribes = DefDatabase<FactionDef>.GetNamed("RR_ObsidianTribes").modExtensions?.Any(e => e.GetType().Name == "FactionRestrictions") == true;
                Check("19 griffin rideable", mountable && tribes, $"in Giddy-Up's mountable cache {mountable}; tribes mount rules {tribes}");
            });

            // 20. Trial by razor duelists must be Gold.
            Run("20 duelists", () =>
            {
                RitualRole role = DefDatabase<RitualBehaviorDef>.GetNamed("RR_RazorTrialBehavior").roles.First(r => r.id == "duelist1");
                Pawn g = Colonist(gold, hierarchy), r = Colonist(red, hierarchy);
                bool okG = role.AppliesToPawn(g, out string _, TargetInfo.Invalid);
                bool okR = role.AppliesToPawn(r, out string why, TargetInfo.Invalid);
                Check("20 Gold-only duelists", okG && !okR, $"role {role.GetType().Name}; Gold {okG}, Red {okR} ({why})");
                Discard(g); Discard(r);
            });

            // 21. Helldiver gene, and the clawDrill's 1.5x portions.
            Run("21 drilling", () =>
            {
                Pawn r = Colonist(red, null), b = Colonist(XenotypeDefOf.Baseliner, null);
                float sr = r.GetStatValue(StatDefOf.DeepDrillingSpeed), sb = b.GetStatValue(StatDefOf.DeepDrillingSpeed);
                bool gene = r.genes.HasActiveGene(DefDatabase<GeneDef>.GetNamed("RR_Helldiver"));
                Check("21 helldiver", gene && sr > sb * 1.2f, $"Red has gene {gene}; deep drilling Red {sr:F2} vs baseliner {sb:F2}");
                Discard(r); Discard(b);
                var produce = HarmonyLib.AccessTools.Method(typeof(CompDeepDrill), "TryProducePortion");
                int Yield(string def, IntVec3 at)
                {
                    Clear(CellRect.CenteredOn(at, 3).ClipInsideMap(map));
                    ThingDef d = DefDatabase<ThingDef>.GetNamed(def);
                    var bld = (Building)GenSpawn.Spawn(ThingMaker.MakeThing(d, d.MadeFromStuff ? GenStuff.DefaultStuffFor(d) : null), at, map, Rot4.North);
                    bld.SetFaction(Faction.OfPlayer);
                    map.deepResourceGrid.SetAt(at, ThingDefOf.Steel, 5000);
                    int before = map.listerThings.ThingsOfDef(ThingDefOf.Steel).Sum(t => t.stackCount);
                    for (int i = 0; i < 20; i++) { produce.Invoke(bld.GetComp<CompDeepDrill>(), new object[] { 1f, null }); }
                    int total = map.listerThings.ThingsOfDef(ThingDefOf.Steel).Sum(t => t.stackCount) - before;
                    foreach (Thing t in map.listerThings.ThingsOfDef(ThingDefOf.Steel).ToList()) { t.Destroy(); }
                    bld.Destroy();
                    return total;
                }
                int claw = Yield("RR_ClawDrill", map.Center + new IntVec3(8, 0, 8));
                int deep = Yield("DeepDrill", map.Center + new IntVec3(-8, 0, 8));
                Check("21 clawDrill yield", claw > deep * 1.35f && claw < deep * 1.65f,
                      $"20 portions of steel: clawDrill {claw}, deep drill {deep} ({(deep > 0 ? (float)claw / deep : 0):F2}x)");
            });

            // 22. Starting sigils: true and forged.
            Run("22 start sigils", () =>
            {
                Pawn a = Colonist(red, null);
                GenSpawn.Spawn(a, map.Center + IntVec3.West * 4, map);
                var part = new ScenPart_Sigils { def = DefDatabase<ScenPartDef>.GetNamed("RR_StartingSigils") };
                part.PostGameStart();
                bool trueOk = RR_Sigils.SigilOf(a) == RR_Sigils.SigilFor(red);
                var forgedPart = new ScenPart_Sigils { def = DefDatabase<ScenPartDef>.GetNamed("RR_StartingSigils"), forged = true };
                forgedPart.PostGameStart();
                bool forgedOk = RR_Sigils.SigilMismatch(a);
                Check("22 starting sigils", trueOk && forgedOk, $"true part matches {trueOk}; forged part gives {RR_Sigils.SigilOf(a)?.defName} (mismatch {forgedOk})");
                Discard(a);
            });

            // 23. Census reads sigils; 24. Lurcher hunt.
            Run("23 census", () =>
            {
                Pawn a = Colonist(red, null);
                GenSpawn.Spawn(a, map.Center + IntVec3.West * 5, map);
                RR_Sigils.SetSigil(a, RR_Sigils.SigilFor(gold));
                if (society.HostileTo(Faction.OfPlayer)) { society.TryAffectGoodwillWith(Faction.OfPlayer, 200, false, false); }
                int gw = society.PlayerGoodwill;
                int letters = Find.LetterStack.LettersListForReading.Count;
                Patch_CensusReadsSigils.Postfix(new IncidentParms { target = map, faction = society }, DefDatabase<TraderKindDef>.GetNamed("RR_Caravan_Society_Census"));
                Check("23 census discrepancy", society.PlayerGoodwill < gw && Find.LetterStack.LettersListForReading.Count > letters,
                      $"goodwill {gw} -> {society.PlayerGoodwill}, letter sent {Find.LetterStack.LettersListForReading.Count > letters}");

                society.TryAffectGoodwillWith(Faction.OfPlayer, -200, false, false);
                IncidentDef hunt = DefDatabase<IncidentDef>.GetNamed("RR_Incident_LurcherHunt");
                IncidentParms hp = StorytellerUtility.DefaultParmsNow(hunt.category, map);
                hp.points = 1200f;
                hp.forced = true;
                // Drop pods land later; walking in puts the hunters on the map now.
                hp.raidArrivalMode = PawnsArrivalModeDefOf.EdgeWalkIn;
                bool can = hunt.Worker.CanFireNow(hp);
                var beforeSet = new HashSet<Pawn>(map.mapPawns.SpawnedPawnsInFaction(society));
                bool fired = hunt.Worker.TryExecute(hp);
                var came = map.mapPawns.SpawnedPawnsInFaction(society).Where(x => !beforeSet.Contains(x)).ToList();
                Check("24 Lurcher hunt", can && fired && came.Count > 0 && came.All(x => x.kindDef.defName == "RR_Society_Lurcher"),
                      $"quarry {IncidentWorker_LurcherHunt.Quarry(map)?.LabelShort}; can fire {can}, fired {fired}, {came.Count} pawns: {string.Join(", ", came.Select(x => x.kindDef.defName).Distinct())}");
                foreach (Pawn x in came) { x.Destroy(); }
                Discard(a);
            });

            // 25. Observer: a hierarchy believer thinks less of a Red researching.
            Run("25 observer", () =>
            {
                Pawn w = Colonist(red, hierarchy), o = Colonist(gold, hierarchy);
                GenSpawn.Spawn(w, map.Center + IntVec3.East * 4, map);
                GenSpawn.Spawn(o, map.Center + IntVec3.East * 5, map);
                Verse.AI.Job j = JobMaker.MakeJob(JobDefOf.Wait, 600);
                j.workGiverDef = DefDatabase<WorkGiverDef>.AllDefs.First(x => x.workType == WorkTypeDefOf.Research);
                w.jobs.StartJob(j, Verse.AI.JobCondition.InterruptForced);
                ThoughtDef td = DefDatabase<ThoughtDef>.GetNamed("RR_Thought_SawWorkOutsideCaste");
                bool active = td.Worker.CurrentSocialState(o, w).Active;
                Check("25 observer thought", active, $"Gold watching a Red research: {active}; opinion {o.relations.OpinionOf(w)}");
                Discard(w); Discard(o);
            });

            // 26. Iron Rain: the Society drops from orbit far more than a vanilla-weighted faction.
            Run("26 iron rain", () =>
            {
                var worker = (IncidentWorker_Raid)IncidentDefOf.RaidEnemy.Worker;
                float DropShare(Faction f)
                {
                    int drops = 0, n = 300;
                    for (int i = 0; i < n; i++)
                    {
                        var parms = new IncidentParms { target = map, faction = f, points = 1500f, raidStrategy = RaidStrategyDefOf.ImmediateAttack };
                        if (worker.TryResolveRaidArriveMode(parms) && parms.raidArrivalMode != null && !parms.raidArrivalMode.walkIn) { drops++; }
                    }
                    return (float)drops / n;
                }
                Faction other = Find.FactionManager.AllFactionsListForReading.FirstOrDefault(f =>
                    !f.IsPlayer && f.def.techLevel >= TechLevel.Industrial && !f.def.defName.StartsWith("RR_") && f.def.humanlikeFaction && !f.Hidden);
                float soc = DropShare(society), oth = other == null ? -1f : DropShare(other);
                Check("26 iron rain", soc > 0.75f && (other == null || soc > oth + 0.1f),
                      $"drop share at 1500 points: Society {soc:P0}, {other?.def.defName ?? "no comparison faction"} {oth:P0}");
            });

            // 27. Blues and gravships: helm sense raises piloting.
            Run("27 helm sense", () =>
            {
                StatDef pilot = DefDatabase<StatDef>.GetNamedSilentFail("PilotingAbility");
                if (pilot == null) { Log.Message("[RimRising] M12 skip 27: Odyssey not active"); return; }
                Pawn b = Colonist(DefDatabase<XenotypeDef>.GetNamed("RR_Blue"), null), o = Colonist(DefDatabase<XenotypeDef>.GetNamed("RR_Orange"), null);
                float pb = b.GetStatValue(pilot), po = o.GetStatValue(pilot);
                Check("27 helm sense", b.genes.HasActiveGene(DefDatabase<GeneDef>.GetNamed("RR_HelmSense")) && pb > po,
                      $"piloting Blue {pb:F2} vs Orange {po:F2}");
                Discard(b); Discard(o);
            });

            // 28. The Rim Dominion's own ladder: separate titles, and its knight holds its own rung.
            Run("28 rim ladder", () =>
            {
                Faction dom = FactionOf("RR_RimDominion");
                if (dom == null)
                {
                    dom = FactionGenerator.NewGeneratedFaction(new FactionGeneratorParms(DefDatabase<FactionDef>.GetNamed("RR_RimDominion")));
                    Find.FactionManager.Add(dom);
                }
                var socTitles = DefDatabase<FactionDef>.GetNamed("RR_Society").RoyalTitlesAwardableInSeniorityOrderForReading.Select(t => t.defName).ToList();
                var domTitles = DefDatabase<FactionDef>.GetNamed("RR_RimDominion").RoyalTitlesAwardableInSeniorityOrderForReading.Select(t => t.defName).ToList();
                bool apart = socTitles.Count > 0 && domTitles.Count > 0 && !socTitles.Intersect(domTitles).Any();
                string knight = "no Dominion in world";
                bool kOk = true;
                if (dom != null)
                {
                    int plate = 0, titled = 0;
                    for (int i = 0; i < 10; i++)
                    {
                        Pawn k = Gen("RR_Dominion_Obsidian_Knight", dom);
                        if (k.royalty?.GetCurrentTitle(dom)?.defName == "RR_Title_RimPraetorian") { titled++; }
                        if (k.apparel.WornApparel.Any(x => x.def.apparel?.tags?.Contains(RR_CasteArmor.RestrictedTag) == true)) { plate++; }
                        Discard(k);
                    }
                    knight = $"{titled}/10 Rim Praetorians, {plate}/10 in plate";
                    kOk = titled >= 8;
                }
                Check("28 rim ladder", apart && kOk, $"Society [{string.Join(", ", socTitles)}] / Dominion [{string.Join(", ", domTitles)}]; knights {knight}");
            });

            Log.Message($"[RimRising] M12 SUMMARY {m12Ok} ok, {m12Fail} fail");
        }

        private const int BioSamples = 6;

        /// <summary>
        /// rrtestmode=bios: every RR_ humanlike kind that pins backstories through
        /// backstoryFiltersOverride, generated a few times. Each pawn's childhood and
        /// adulthood must carry one of the kind's categories (a vanilla bio means the
        /// override did not take), and its name is logged for reading. A kind that
        /// throws is caught and logged, since that is the failure a category with no
        /// backstory for a slot produces.
        /// </summary>
        private void GenerateBios()
        {
            int bad = 0, total = 0;
            foreach (PawnKindDef kind in DefDatabase<PawnKindDef>.AllDefs
                         .Where(k => k.defName.StartsWith("RR_") && k.RaceProps?.Humanlike == true &&
                                     k.backstoryFiltersOverride != null)
                         .OrderBy(k => k.defName))
            {
                HashSet<string> cats = new HashSet<string>(kind.backstoryFiltersOverride
                    .Where(f => f.categories != null).SelectMany(f => f.categories));
                Faction fac = Find.FactionManager.AllFactionsListForReading.FirstOrDefault(f =>
                    f.def.pawnGroupMakers != null && f.def.pawnGroupMakers.Any(g =>
                        (g.options != null && g.options.Any(o => o.kind == kind)) ||
                        (g.traders != null && g.traders.Any(o => o.kind == kind)) ||
                        (g.guards != null && g.guards.Any(o => o.kind == kind))));
                int kindBad = 0;
                List<string> names = new List<string>();
                for (int i = 0; i < BioSamples; i++)
                {
                    Pawn p;
                    try
                    {
                        p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(kind, fac, forceGenerateNewPawn: true));
                    }
                    catch (System.Exception e)
                    {
                        Log.Message($"[RimRising] BIOS {kind.defName} THREW: {e.GetType().Name}: {e.Message}");
                        kindBad++;
                        continue;
                    }
                    BackstoryDef child = p.story?.Childhood, adult = p.story?.Adulthood;
                    bool childOk = child != null && child.spawnCategories.Any(cats.Contains);
                    bool adultOk = adult == null || adult.spawnCategories.Any(cats.Contains);
                    string full = p.Name?.ToStringFull ?? "-";
                    bool nameOk = p.Name is NameTriple && !full.Contains("'") && !full.Contains("\"");
                    if (!childOk || !adultOk || !nameOk) { kindBad++; }
                    names.Add(full);
                    Log.Message($"[RimRising] BIOS {kind.defName} #{i} {(childOk && adultOk && nameOk ? "ok" : "BAD")} " +
                                $"color={RR_CasteIdentity.ColorOf(p)?.defName ?? "-"} age={p.ageTracker.AgeBiologicalYears} " +
                                $"name=\"{full}\" child={child?.defName ?? "-"}{(childOk ? "" : "(!)")} " +
                                $"adult={adult?.defName ?? "-"}{(adultOk ? "" : "(!)")}");
                    Find.WorldPawns.PassToWorld(p, PawnDiscardDecideMode.Discard);
                }
                total++;
                if (kindBad > 0) { bad++; }
                Log.Message($"[RimRising] BIOS {kind.defName}: {(kindBad == 0 ? "OK" : kindBad + " BAD")} of {BioSamples} " +
                            $"(faction {fac?.Name ?? "none"}, categories {string.Join("/", cats)})");
            }
            Log.Message($"[RimRising] BIOS SUMMARY {total - bad}/{total} kinds clean");
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
                // Fixed adult age: Biotech draws 13-18 year olds smaller, and one
                // teenage Hulk made pulse armour look undersized beside recoil.
                fixedBiologicalAge: 30f,
                fixedChronologicalAge: 30f,
                dontGiveWeapon: true,
                forceNoGear: true);
            Pawn p = PawnGenerator.GeneratePawn(req);
            // forceNoIdeo is NOT enough: a player-faction pawn can still come out
            // holding the colony's random ideoligion, and when that one carries
            // the caste precept every pulse and recoil row is refused and drawn
            // naked ("tried to wear ... but is not allowed to"). Cleared outright.
            p.ideo?.SetIdeo(null);
            p.story.bodyType = body;
            p.apparel?.DestroyAll();
            p.equipment?.DestroyAllEquipment();

            if (armor == null) { p.SetFaction(null); return p; }   // rrtestmode=whip's bare target

            ThingDef stuff = armor.MadeFromStuff ? GenStuff.DefaultStuffFor(armor) : null;
            var ap = (Apparel)ThingMaker.MakeThing(armor, stuff);
            // Ours is shown in a caste colour, since being dyed is half of what it
            // is for; the others keep whatever their defs give them.
            // ONLY caste-coloured plate, the same rule CasteArmor.cs applies in
            // play. Every apparel has a CompColorable (it is how the styling station
            // dyes clothes), so dyeing anything RR_ tinted duroArmor, scarabSkin and
            // the ghost cloak gold - a look nobody would ever see in a game.
            if (armor.apparel?.tags != null && armor.apparel.tags.Contains(RR_CasteArmor.CasteColoredTag))
            {
                ap.TryGetComp<CompColorable>()?.SetColor(gold);
            }
            p.apparel.Wear(ap, dropReplacedApparel: false, locked: true);
            if (armor.defName == "RR_Apparel_StarShellCore")
            {
                // Mirrors Exosuit's Building_MaintenanceBay.GearUp: every module
                // worn locked, then the core notified and its module cache rebuilt.
                // Reflection, so this assembly takes no compile-time Exosuit reference.
                foreach (string part in StarShellParts)
                {
                    ThingDef pd = DefDatabase<ThingDef>.GetNamedSilentFail(part);
                    if (pd != null) { p.apparel.Wear((Apparel)ThingMaker.MakeThing(pd), dropReplacedApparel: false, locked: true); }
                }
                ap.Notify_Equipped(p);
                HarmonyLib.AccessTools.Method(ap.GetType(), "ModuleRecache")?.Invoke(ap, null);
            }
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
