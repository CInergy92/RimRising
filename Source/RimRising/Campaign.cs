using System.Collections.Generic;
using System.Linq;
using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// The campaign: a story spine for one scenario (RR_Scenario_Quota), told in acts.
    ///
    /// The user's calls (2026-11-14): an ORIGINAL carved Red with a generated name, the
    /// books' arc as STRUCTURE only (quota, injustice, carving, hunt, rising, Rain - no
    /// scene recreated, every word original), every key beat an OFFER the player may
    /// refuse, and a scenario of its own so the other four starts stay sandboxes.
    ///
    /// HOW IT RUNS. ScenPart_Campaign switches it on at game start; this component
    /// then holds one act at a time and moves on when that act's CONDITION is met -
    /// a deadline passed, a raid beaten, an offer answered - never on a fixed
    /// calendar, so the story waits for the colony. The storyteller carries on as
    /// usual between beats. In any other scenario, and in every save made before the
    /// campaign existed, the act is None and nothing here does anything.
    ///
    /// THE ACTS
    ///   Opening      two days of quiet, then the quota letter.
    ///   Quota        mine helium-3 from the seam under the clan's rig by the deadline.
    ///                Met or not, the Laurel goes elsewhere; which it was is remembered.
    ///   Reprisal     the Society sends a detachment (CampaignRaid.cs) and is hostile
    ///                from here on.
    ///   Contact      the Sons of Ares offer a wounded stranger. REFUSING ENDS THE STORY,
    ///                quietly; the colony plays on as a sandbox.
    ///   Hero         a Red carved Gold, razor in hand, a Red sigil that no longer
    ///                matches the body. Six days later the mismatch draws Lurchers
    ///                (the existing RR_Incident_LurcherHunt).
    ///   Rising       freed Obsidians offer to join; the garrison answers; Gray and
    ///                Orange defectors offer to join. Refusing recruits costs only them.
    ///   Rain         a warning, then an Iron Rain: a forced centre drop.
    ///   Epilogue     what the win leaves behind (the user's go-ahead, 2026-11-14):
    ///                Reds from other claims offer to join and bring supplies; a
    ///                merchant house offers trade; the Society puts a price on the
    ///                stranger, which is only a letter - the Lurcher hunt already
    ///                keeps coming for a mismatched sigil, and forging one ends it.
    ///   Ending       one last choice of what the claim becomes: a free clan, an ally
    ///                of the Sons of Ares, or under the Rim Dominion's protection.
    ///   Won          the closing letter for that choice. Play continues.
    ///
    /// Engine facts this leans on, each decompiled on 1.7.5005: Game.FillComponents
    /// instantiates every GameComponent subclass through a (Game) constructor, on new
    /// games and old saves alike; IncidentWorker_RaidEnemy keeps a preset hostile
    /// parms.faction and Raid keeps a preset raidArrivalMode; DeepResourceGrid.SetAt
    /// plants a seam and CompDeepDrill reads the grid with no scanner involved.
    /// </summary>
    public class GameComponent_Campaign : GameComponent
    {
        public enum Act
        {
            None, Opening, Quota, Reprisal, ReprisalFight, ContactPending, Hero, HuntFight,
            Wave1Pending, Garrison, GarrisonFight, Wave2Pending, RainWarned, RainFight, Won, Ended,
            // The epilogue and the ending. Added after Won and Ended on purpose: the act
            // is saved by name, so order does not matter to a save, and a game that had
            // already reached Won stays finished.
            Aftermath, ClansPending, HouseWait, HousePending, PriceWait, ChoiceWait, ChoicePending
        }

        private const int Day = 60000;
        private const int OpeningDays = 2, ReprisalDays = 2, HuntDays = 6, GarrisonDays = 5, RainDays = 3;
        private const int AftermathDays = 4, HouseDays = 5, PriceDays = 3, ChoiceDays = 4;

        // The quota's two numbers live on the scenario part, so they are tuned in
        // Scenarios_Campaign.xml. Measured in rrtestmode=campaignstart: four Reds left
        // to themselves bring up about 90 canisters a day with one of them on the rig.
        private static ScenPart_Campaign Part => Find.Scenario?.AllParts.OfType<ScenPart_Campaign>().FirstOrDefault();
        public static int QuotaAmount => Part?.quota ?? ScenPart_Campaign.DefaultQuota;
        public static int QuotaDays => Part?.quotaDays ?? ScenPart_Campaign.DefaultQuotaDays;
        // A raid is over when no Society fighter is left standing, but not before
        // half a day (drop pods are still in the air) and never later than five.
        private const int RaidMinTicks = Day / 2, RaidMaxTicks = 5 * Day;
        private const int CheckInterval = 250;

        public Act act = Act.None;
        public bool quotaMet;
        public Pawn hero;
        /// <summary>What the claim became: "free", "ares" or "dominion". Null until chosen.</summary>
        public string ending;
        private int nextTick, raidTick;

        public GameComponent_Campaign(Game game) { }

        public bool Running => act != Act.None && act != Act.Won && act != Act.Ended;

        public override void ExposeData()
        {
            Scribe_Values.Look(ref act, "rrCampaignAct", Act.None);
            Scribe_Values.Look(ref quotaMet, "rrCampaignQuotaMet", false);
            Scribe_Values.Look(ref nextTick, "rrCampaignNextTick", 0);
            Scribe_Values.Look(ref raidTick, "rrCampaignRaidTick", 0);
            Scribe_References.Look(ref hero, "rrCampaignHero");
            Scribe_Values.Look(ref ending, "rrCampaignEnding");
        }

        public override void GameComponentTick()
        {
            if (!Running || Find.TickManager.TicksGame % CheckInterval != 0) { return; }
            Step();
        }

        private static int Now => Find.TickManager.TicksGame;

        private static Faction FactionOf(string defName) =>
            Find.FactionManager.AllFactionsListForReading.FirstOrDefault(f => f.def.defName == defName && !f.defeated);

        public static Faction Society => FactionOf("RR_Society");
        public static Faction Ares => FactionOf("RR_SonsOfAres");
        public static Faction Dominion => FactionOf("RR_RimDominion");

        /// <summary>The merchant house that makes the offer: one that is not at war with the colony.</summary>
        public static Faction House
        {
            get
            {
                foreach (string name in new[] { "RR_SunIndustries", "RR_JuliiIndustries" })
                {
                    Faction f = FactionOf(name);
                    if (f != null && !f.HostileTo(Faction.OfPlayer)) { return f; }
                }
                return null;
            }
        }

        // ------------------------------------------------------------------ start

        /// <summary>Called once by ScenPart_Campaign when the game starts.</summary>
        public void Begin(Map map)
        {
            if (act != Act.None) { return; }
            act = Act.Opening;
            nextTick = Now + OpeningDays * Day;
            PlaceRig(map);
        }

        /// <summary>
        /// The clan's rig: a clawDrill over a seeded helium-3 seam, with a wood-fired
        /// generator beside it. Without this the quota is a letter about work nobody
        /// can do - helium is a deep resource, and three Reds with slingBlades are a
        /// long way from a scanner and a drill of their own.
        /// </summary>
        public static bool PlaceRig(Map map)
        {
            ThingDef drill = DefDatabase<ThingDef>.GetNamedSilentFail("RR_ClawDrill");
            ThingDef he3 = DefDatabase<ThingDef>.GetNamedSilentFail("RR_HeliumThree");
            ThingDef gen = DefDatabase<ThingDef>.GetNamedSilentFail("WoodFiredGenerator");
            if (map == null || drill == null || he3 == null) { return false; }

            IntVec3 start = MapGenerator.PlayerStartSpot.IsValid ? MapGenerator.PlayerStartSpot : map.Center;
            IntVec3 spot = IntVec3.Invalid;
            for (int radius = 8; radius <= 40 && !spot.IsValid; radius += 8)
            {
                CellFinder.TryFindRandomCellNear(start, map, radius, c => RigFits(c, map, drill, gen), out spot);
            }
            if (!spot.IsValid)
            {
                Log.Warning("[RimRising] Campaign: no room for the clan's rig near the start; the quota cannot be mined.");
                return false;
            }

            // The seam: under the rig and a little around it. 300 a cell is vanilla's
            // default deepCountPerCell; nine or so cells is far more than the quota.
            foreach (IntVec3 c in GenRadial.RadialCellsAround(spot, 2.9f, true))
            {
                if (c.InBounds(map)) { map.deepResourceGrid.SetAt(c, he3, 300); }
            }

            Thing rig = GenSpawn.Spawn(ThingMaker.MakeThing(drill), spot, map, Rot4.South, WipeMode.Vanish);
            rig.SetFaction(Faction.OfPlayer);
            if (gen != null)
            {
                Thing g = GenSpawn.Spawn(ThingMaker.MakeThing(gen), spot + new IntVec3(3, 0, 0), map, Rot4.North, WipeMode.Vanish);
                g.SetFaction(Faction.OfPlayer);
                CompRefuelable fuel = g.TryGetComp<CompRefuelable>();
                if (fuel != null) { fuel.Refuel(fuel.Props.fuelCapacity * 0.6f); }
            }
            return true;
        }

        private static bool RigFits(IntVec3 c, Map map, ThingDef drill, ThingDef gen)
        {
            // The drill's 2x2, its interaction cell to the south, and the generator's
            // 2x2 three cells east: one clear, buildable block, kept off the very start.
            CellRect block = new CellRect(c.x - 1, c.z - 2, 7, 5);
            if (!block.InBounds(map) || block.Contains(MapGenerator.PlayerStartSpot)) { return false; }
            foreach (IntVec3 b in block)
            {
                if (b.Fogged(map) || !b.Standable(map) || b.GetEdifice(map) != null) { return false; }
                if (!b.GetTerrain(map).affordances.Contains(TerrainAffordanceDefOf.Heavy)) { return false; }
            }
            return true;
        }

        // ------------------------------------------------------------------- acts

        /// <summary>One look at the current act; moves on if its condition is met.</summary>
        public void Step()
        {
            Map map = Find.AnyPlayerHomeMap;
            if (map == null) { return; }
            switch (act)
            {
                case Act.Opening:
                    if (Now < nextTick) { return; }
                    nextTick = Now + QuotaDays * Day;
                    act = Act.Quota;
                    Send("RR_Campaign_QuotaLabel", "RR_Campaign_QuotaText".Translate(QuotaAmount, QuotaDays), LetterDefOf.NeutralEvent);
                    return;

                case Act.Quota:
                    if (Now < nextTick) { return; }
                    ResolveQuota(map);
                    act = Act.Reprisal;
                    nextTick = Now + ReprisalDays * Day;
                    return;

                case Act.Reprisal:
                    if (Now >= nextTick) { StartRaid(map, "RR_Incident_CampaignReprisal", Act.ReprisalFight); }
                    return;

                case Act.ReprisalFight:
                    if (!RaidOver(map)) { return; }
                    act = Act.ContactPending;
                    SendOffer("contact", "RR_Campaign_ContactLabel", "RR_Campaign_ContactText".Translate(), Ares);
                    return;

                case Act.Hero:
                    if (Now < nextTick) { return; }
                    // The hunt needs a quarry. If the stranger is dead or gone, the
                    // hunters have nobody to come for and the story moves on without it.
                    if (IncidentWorker_LurcherHunt.Quarry(map) != null && Fire(map, "RR_Incident_LurcherHunt"))
                    {
                        act = Act.HuntFight;
                        raidTick = Now;
                        return;
                    }
                    OfferWave1();
                    return;

                case Act.HuntFight:
                    if (RaidOver(map)) { OfferWave1(); }
                    return;

                case Act.Garrison:
                    if (Now >= nextTick) { StartRaid(map, "RR_Incident_CampaignGarrison", Act.GarrisonFight); }
                    return;

                case Act.GarrisonFight:
                    if (!RaidOver(map)) { return; }
                    act = Act.Wave2Pending;
                    SendOffer("wave2", "RR_Campaign_Wave2Label", "RR_Campaign_Wave2Text".Translate(), Ares);
                    return;

                case Act.RainWarned:
                    if (Now >= nextTick) { StartRaid(map, "RR_Incident_CampaignRain", Act.RainFight); }
                    return;

                case Act.RainFight:
                    if (!RaidOver(map)) { return; }
                    act = Act.Aftermath;
                    nextTick = Now + AftermathDays * Day;
                    Send("RR_Campaign_WonLabel",
                         hero != null && !hero.Dead ? "RR_Campaign_WonText".Translate(hero.Named("PAWN")) : "RR_Campaign_WonTextNoHero".Translate(),
                         LetterDefOf.PositiveEvent);
                    return;

                case Act.Aftermath:
                    if (Now < nextTick) { return; }
                    act = Act.ClansPending;
                    SendOffer("clans", "RR_Campaign_ClansLabel", "RR_Campaign_ClansText".Translate(), Ares);
                    return;

                case Act.HouseWait:
                    if (Now < nextTick) { return; }
                    Faction house = House;
                    // No house on speaking terms (or none in this world): the beat is skipped.
                    if (house == null) { ToPrice(); return; }
                    act = Act.HousePending;
                    SendOffer("house", "RR_Campaign_HouseLabel", "RR_Campaign_HouseText".Translate(house.Name), house);
                    return;

                case Act.PriceWait:
                    if (Now < nextTick) { return; }
                    // Only a letter. The hunt itself is RR_Incident_LurcherHunt, which already
                    // fires for as long as a colonist's sigil does not match; this tells the
                    // player so, and that a forged sigil is the way out.
                    if (hero != null && !hero.Dead && RR_Sigils.SigilMismatch(hero))
                    {
                        Find.LetterStack.ReceiveLetter("RR_Campaign_PriceLabel".Translate(),
                            "RR_Campaign_PriceText".Translate(hero.Named("PAWN")), LetterDefOf.NegativeEvent, hero);
                    }
                    act = Act.ChoiceWait;
                    nextTick = Now + ChoiceDays * Day;
                    return;

                case Act.ChoiceWait:
                    if (Now < nextTick) { return; }
                    act = Act.ChoicePending;
                    List<string> answers = new List<string> { "free" };
                    if (Ares != null) { answers.Add("ares"); }
                    if (Dominion != null) { answers.Add("dominion"); }
                    SendOffer("ending", "RR_Campaign_EndingLabel", "RR_Campaign_EndingText".Translate(), null, answers);
                    return;
            }
        }

        private void ToPrice()
        {
            act = Act.PriceWait;
            nextTick = Now + PriceDays * Day;
        }

        private void OfferWave1()
        {
            act = Act.Wave1Pending;
            SendOffer("wave1", "RR_Campaign_Wave1Label", "RR_Campaign_Wave1Text".Translate(), Ares);
        }

        /// <summary>
        /// The tithe. Whatever helium-3 is lying on the map is counted; the Society
        /// takes the quota if it is there and everything if it is not. The Laurel
        /// goes elsewhere either way - that is the point of the Laurel.
        /// </summary>
        public void ResolveQuota(Map map)
        {
            ThingDef he3 = DefDatabase<ThingDef>.GetNamedSilentFail("RR_HeliumThree");
            List<Thing> stacks = he3 == null ? new List<Thing>()
                : map.listerThings.ThingsOfDef(he3).Where(t => t.Spawned && !t.Position.Fogged(map)).ToList();
            int have = stacks.Sum(t => t.stackCount);
            quotaMet = have >= QuotaAmount;

            int take = quotaMet ? QuotaAmount : have;
            foreach (Thing t in stacks)
            {
                if (take <= 0) { break; }
                int n = Mathf.Min(take, t.stackCount);
                take -= n;
                if (n >= t.stackCount) { t.Destroy(); } else { t.SplitOff(n).Destroy(); }
            }

            Send(quotaMet ? "RR_Campaign_QuotaMetLabel" : "RR_Campaign_QuotaShortLabel",
                 quotaMet ? "RR_Campaign_QuotaMetText".Translate(QuotaAmount)
                          : "RR_Campaign_QuotaShortText".Translate(have, QuotaAmount),
                 LetterDefOf.NegativeEvent);
        }

        // ---------------------------------------------------------------- answers

        public const string Accept = "accept", Refuse = "refuse";

        public void Resolve(string beat, bool accepted) => Resolve(beat, accepted ? Accept : Refuse);

        /// <summary>
        /// The player's answer to an offer letter (ChoiceLetter_CampaignOffer): "accept"
        /// or "refuse" for most, and one of "free", "ares", "dominion" for the ending.
        /// </summary>
        public void Resolve(string beat, string answer)
        {
            Map map = Find.AnyPlayerHomeMap;
            if (map == null) { return; }
            bool accepted = answer == Accept;
            switch (beat)
            {
                case "clans":
                    if (act != Act.ClansPending) { return; }
                    if (accepted)
                    {
                        SpawnRecruits(map, "RR_Ares_Red_Fighter", 2);
                        DropSupplies(map);
                    }
                    act = Act.HouseWait;
                    nextTick = Now + HouseDays * Day;
                    return;

                case "house":
                    if (act != Act.HousePending) { return; }
                    Faction house = House;
                    if (accepted && house != null)
                    {
                        house.TryAffectGoodwillWith(Faction.OfPlayer, 50, canSendMessage: false, canSendHostilityLetter: false);
                        Ares?.TryAffectGoodwillWith(Faction.OfPlayer, -10, canSendMessage: false, canSendHostilityLetter: false);
                        // Their first caravan, now. If it cannot come (a hostile lord on
                        // the map, no entry cell) the goodwill still stands.
                        IncidentParms trade = StorytellerUtility.DefaultParmsNow(IncidentDefOf.TraderCaravanArrival.category, map);
                        trade.faction = house;
                        trade.forced = true;
                        IncidentDefOf.TraderCaravanArrival.Worker.TryExecute(trade);
                    }
                    ToPrice();
                    return;

                case "ending":
                    if (act != Act.ChoicePending) { return; }
                    // An answer naming a faction this world does not have is the free clan:
                    // nobody to ally with, and nobody else to pay for it.
                    if (answer == "ares" && Ares == null) { answer = "free"; }
                    if (answer == "dominion" && Dominion == null) { answer = "free"; }
                    if (answer != "ares" && answer != "dominion") { answer = "free"; }
                    ending = answer;
                    if (answer == "ares")
                    {
                        Ares?.TryAffectGoodwillWith(Faction.OfPlayer, 200, canSendMessage: false, canSendHostilityLetter: false);
                    }
                    else if (answer == "dominion")
                    {
                        Dominion?.TryAffectGoodwillWith(Faction.OfPlayer, 200, canSendMessage: false, canSendHostilityLetter: false);
                        Ares?.TryAffectGoodwillWith(Faction.OfPlayer, -60, canSendMessage: false, canSendHostilityLetter: false);
                    }
                    act = Act.Won;
                    Send("RR_Campaign_EndLabel", ("RR_Campaign_End_" + answer).Translate(), LetterDefOf.PositiveEvent);
                    return;

                case "contact":
                    if (act != Act.ContactPending) { return; }
                    if (!accepted)
                    {
                        act = Act.Ended;
                        Send("RR_Campaign_DeclinedLabel", "RR_Campaign_DeclinedText".Translate(), LetterDefOf.NeutralEvent);
                        return;
                    }
                    Ares?.TryAffectGoodwillWith(Faction.OfPlayer, 40, canSendMessage: false, canSendHostilityLetter: false);
                    hero = SpawnHero(map);
                    act = Act.Hero;
                    nextTick = Now + HuntDays * Day;
                    if (hero != null)
                    {
                        Find.LetterStack.ReceiveLetter("RR_Campaign_HeroLabel".Translate(),
                            "RR_Campaign_HeroText".Translate(hero.Named("PAWN")), LetterDefOf.PositiveEvent, hero);
                    }
                    return;

                case "wave1":
                    if (act != Act.Wave1Pending) { return; }
                    if (accepted) { SpawnRecruits(map, "RR_Ares_Obsidian_Freed", 2); }
                    act = Act.Garrison;
                    nextTick = Now + GarrisonDays * Day;
                    return;

                case "wave2":
                    if (act != Act.Wave2Pending) { return; }
                    if (accepted)
                    {
                        SpawnRecruits(map, "RR_Ares_Gray_Defector", 2);
                        SpawnRecruits(map, "RR_Ares_Orange_Saboteur", 1);
                    }
                    act = Act.RainWarned;
                    nextTick = Now + RainDays * Day;
                    Send("RR_Campaign_RainWarningLabel", "RR_Campaign_RainWarningText".Translate(RainDays), LetterDefOf.ThreatSmall);
                    return;
            }
        }

        // ------------------------------------------------------------------ pawns

        /// <summary>
        /// The stranger: born Red, carved Gold, a razor in hand and the Red sigil
        /// still on the hand - so the paper no longer matches the body, which is what
        /// the Lurchers come for. Arrives by drop pod, wounded and down, the way
        /// vanilla's refugees do, so sheltering them is something the colony does.
        /// </summary>
        public static Pawn SpawnHero(Map map)
        {
            XenotypeDef red = DefDatabase<XenotypeDef>.GetNamedSilentFail("RR_Red");
            XenotypeDef gold = RR_DefOf.RR_Gold;
            PawnKindDef kind = DefDatabase<PawnKindDef>.GetNamedSilentFail("RR_Ares_Red_Fighter") ?? PawnKindDefOf.Colonist;
            if (red == null || gold == null) { return null; }

            float age = Rand.Range(20f, 27f);
            Pawn p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(kind, Faction.OfPlayer,
                forceGenerateNewPawn: true, forcedXenotype: red, developmentalStages: DevelopmentalStage.Adult,
                fixedBiologicalAge: age, fixedChronologicalAge: age));

            // The carving, laid down exactly as Recipe_CarveColor does it: the whole
            // Color as xenogenes over the birth xenotype, the name and the glyph.
            p.genes.ClearXenogenes();
            foreach (GeneDef g in gold.genes) { p.genes.AddGene(g, xenogene: true); }
            p.genes.xenotypeName = gold.LabelCap;
            XenotypeIconDef icon = DefDatabase<XenotypeIconDef>.GetNamedSilentFail("RR_Icon_" + gold.defName.Substring(3));
            if (icon != null) { p.genes.iconDef = icon; }

            RR_Sigils.SetSigil(p, RR_Sigils.SigilFor(red));

            ThingDef razor = DefDatabase<ThingDef>.GetNamedSilentFail("RR_Weapon_Razor");
            if (razor != null && p.equipment != null)
            {
                p.equipment.DestroyAllEquipment();
                p.equipment.AddEquipment((ThingWithComps)ThingMaker.MakeThing(razor, razor.MadeFromStuff ? GenStuff.DefaultStuffFor(razor) : null));
            }

            HealthUtility.DamageUntilDowned(p, allowBleedingWounds: false);
            IntVec3 near = DropCellFinder.TradeDropSpot(map);
            DropPodUtility.DropThingsNear(near, map, new List<Thing> { p }, leaveSlag: true, forbid: false);
            return p;
        }

        public static List<Pawn> SpawnRecruits(Map map, string kindDefName, int count)
        {
            List<Pawn> made = new List<Pawn>();
            PawnKindDef kind = DefDatabase<PawnKindDef>.GetNamedSilentFail(kindDefName);
            if (kind == null) { return made; }
            if (!CellFinder.TryFindRandomEdgeCellWith(c => map.reachability.CanReachColony(c) && !c.Fogged(map),
                    map, CellFinder.EdgeRoadChance_Neutral, out IntVec3 edge))
            {
                edge = DropCellFinder.TradeDropSpot(map);
            }
            for (int i = 0; i < count; i++)
            {
                Pawn p = PawnGenerator.GeneratePawn(new PawnGenerationRequest(kind, Faction.OfPlayer,
                    forceGenerateNewPawn: true, developmentalStages: DevelopmentalStage.Adult));
                GenSpawn.Spawn(p, CellFinder.RandomClosewalkCellNear(edge, map, 4), map);
                made.Add(p);
            }
            if (made.Count > 0)
            {
                Find.LetterStack.ReceiveLetter("RR_Campaign_RecruitsLabel".Translate(),
                    "RR_Campaign_RecruitsText".Translate(made.Count, kind.label), LetterDefOf.PositiveEvent, new LookTargets(made));
            }
            return made;
        }

        /// <summary>What another clan can spare, dropped beside the colony.</summary>
        public static void DropSupplies(Map map)
        {
            List<Thing> things = new List<Thing>();
            void Add(ThingDef def, int count)
            {
                Thing t = ThingMaker.MakeThing(def);
                t.stackCount = count;
                things.Add(t);
            }
            Add(ThingDefOf.MealSurvivalPack, 20);
            Add(ThingDefOf.MedicineIndustrial, 6);
            Add(ThingDefOf.ComponentIndustrial, 8);
            Add(ThingDefOf.Steel, 150);
            DropPodUtility.DropThingsNear(DropCellFinder.TradeDropSpot(map), map, things, forbid: false);
        }

        // ------------------------------------------------------------------ raids

        private void StartRaid(Map map, string incidentDefName, Act fightAct)
        {
            // A raid that cannot be put together (no Society left in this world, no
            // entry cell) is tried again in half a day rather than skipping the act.
            if (Fire(map, incidentDefName))
            {
                act = fightAct;
                raidTick = Now;
            }
            else
            {
                nextTick = Now + Day / 2;
            }
        }

        private static bool Fire(Map map, string incidentDefName)
        {
            IncidentDef def = DefDatabase<IncidentDef>.GetNamedSilentFail(incidentDefName);
            if (def == null) { return false; }
            IncidentParms parms = StorytellerUtility.DefaultParmsNow(def.category, map);
            parms.forced = true;
            return def.Worker.TryExecute(parms);
        }

        public bool RaidOver(Map map)
        {
            int since = Now - raidTick;
            if (since < RaidMinTicks) { return false; }
            if (since > RaidMaxTicks) { return true; }
            Faction society = Society;
            return society == null || !map.mapPawns.AllPawnsSpawned.Any(p =>
                p.Faction == society && !p.Downed && p.HostileTo(Faction.OfPlayer));
        }

        // ---------------------------------------------------------------- letters

        private static void Send(string labelKey, TaggedString text, LetterDef def)
        {
            Find.LetterStack.ReceiveLetter(labelKey.Translate(), text, def);
        }

        private static void SendOffer(string beat, string labelKey, TaggedString text, Faction from, List<string> answers = null)
        {
            LetterDef def = DefDatabase<LetterDef>.GetNamedSilentFail("RR_CampaignOffer");
            TaggedString label = labelKey.Translate();
            ChoiceLetter_CampaignOffer letter = def == null ? null
                : LetterMaker.MakeLetter(label, text, def, from) as ChoiceLetter_CampaignOffer;
            if (letter == null)
            {
                // The def is missing or has the wrong class: say so, and do not strand the story.
                Log.Error("[RimRising] Campaign: RR_CampaignOffer letter def missing; accepting '" + beat + "' by default.");
                Find.LetterStack.ReceiveLetter(label, text, LetterDefOf.NeutralEvent);
                RR_Campaign.Director?.Resolve(beat, answers != null ? answers[0] : Accept);
                return;
            }
            letter.title = label;
            letter.beat = beat;
            letter.answers = answers;
            Find.LetterStack.ReceiveLetter(letter);
        }

        // ------------------------------------------------------------------ tests

        /// <summary>rrtestmode=campaign: every wait is treated as already over.</summary>
        public void DebugSkipWaits()
        {
            nextTick = 0;
            raidTick = Now - RaidMinTicks - 1;
        }

        /// <summary>rrtestmode=campaign: back to the start, for the refusal path.</summary>
        public void DebugReset(Act to)
        {
            act = to;
            hero = null;
            ending = null;
            quotaMet = false;
            nextTick = 0;
            raidTick = 0;
        }
    }

    public static class RR_Campaign
    {
        public static GameComponent_Campaign Director => Current.Game?.GetComponent<GameComponent_Campaign>();
    }

    /// <summary>
    /// Switches the campaign on for a scenario. Nothing but the switch: the story
    /// itself lives in GameComponent_Campaign, which is saved with the game.
    /// Def in Defs/Scenarios/Scenarios_Campaign.xml.
    /// </summary>
    public class ScenPart_Campaign : ScenPart
    {
        public const int DefaultQuota = 900, DefaultQuotaDays = 12;

        /// <summary>Canisters of helium-3 the clan owes, and the days it has to mine them.</summary>
        public int quota = DefaultQuota, quotaDays = DefaultQuotaDays;

        public override void ExposeData()
        {
            base.ExposeData();
            Scribe_Values.Look(ref quota, "quota", DefaultQuota);
            Scribe_Values.Look(ref quotaDays, "quotaDays", DefaultQuotaDays);
        }

        public override string Summary(Scenario scen) => "RR_ScenPartCampaign".Translate();

        public override void PostGameStart()
        {
            Map map = Find.AnyPlayerHomeMap ?? Find.Maps.FirstOrDefault();
            if (map != null) { RR_Campaign.Director?.Begin(map); }
        }
    }

    /// <summary>
    /// An offer the player may take or refuse - the campaign's "spine, not railroad".
    /// Shaped like vanilla's ChoiceLetter_AcceptJoiner (decompiled), which answers
    /// through quest signals; this one answers the director directly. It cannot be
    /// dismissed unanswered and never times out: the story waits.
    /// </summary>
    public class ChoiceLetter_CampaignOffer : ChoiceLetter
    {
        public string beat;
        /// <summary>
        /// The answers on offer, each passed back to the director as written. Null means
        /// accept and refuse. Anything else is labelled from RR_Campaign_Option_&lt;answer&gt;.
        /// </summary>
        public List<string> answers;

        public override bool CanDismissWithRightClick => false;

        public override IEnumerable<DiaOption> Choices
        {
            get
            {
                if (ArchivedOnly)
                {
                    yield return Option_Close;
                    yield break;
                }
                foreach (string answer in answers ?? new List<string> { GameComponent_Campaign.Accept, GameComponent_Campaign.Refuse })
                {
                    yield return Answer(answer);
                }
                yield return Option_Postpone;
            }
        }

        private DiaOption Answer(string answer)
        {
            string key = answer == GameComponent_Campaign.Accept ? "AcceptButton"
                       : answer == GameComponent_Campaign.Refuse ? "RejectLetter"
                       : "RR_Campaign_Option_" + answer;
            return new DiaOption(key.Translate())
            {
                action = delegate
                {
                    Find.LetterStack.RemoveLetter(this);
                    RR_Campaign.Director?.Resolve(beat, answer);
                },
                resolveTree = true
            };
        }

        public override void ExposeData()
        {
            base.ExposeData();
            Scribe_Values.Look(ref beat, "beat");
            Scribe_Collections.Look(ref answers, "answers", LookMode.Value);
        }
    }
}
