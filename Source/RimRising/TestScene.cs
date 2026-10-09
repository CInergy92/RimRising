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
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            Log.Message("[RimRising] TESTSCENE built items: ours " + string.Join(", ", ours.Select(d => d.defName)) +
                        " | vanilla " + string.Join(", ", theirs.Select(d => d.defName)));
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
