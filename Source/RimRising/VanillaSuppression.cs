using System.Collections.Generic;
using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Milestone 7. Pushes vanilla's own xenotypes and generic factions off a
    /// generated planet so the world reads as the Society's, not as a RimWorld
    /// with extra castes bolted on.
    ///
    /// NOTHING HERE DELETES A DEF. Every vanilla def still loads, still resolves,
    /// and still works if something references it - a saved game, another mod, or
    /// a player who ticks the faction back on at world creation. Only the
    /// GENERATION WEIGHTS change. Removing defs outright breaks saves and is
    /// hostile to every other mod in the load order; suppression costs nothing and
    /// is reversible in place.
    ///
    /// WHY C# AND NOT A PATCH FILE
    ///
    /// The obvious implementation is a PatchOperation setting these fields to zero.
    /// That cannot be toggled: XML patches run once, at load, with no access to mod
    /// settings, and there is no way to undo one. Doing it in code lets the settings
    /// checkbox actually mean something, because the original values are captured
    /// before anything is overwritten and can be put back.
    /// </summary>
    [StaticConstructorOnStartup]
    public static class VanillaSuppression
    {
        // Vanilla's generic humanlike factions - the outlander towns, tribes and
        // pirate bands that make a default RimWorld planet look like a default
        // RimWorld planet.
        //
        // Enumerated by reading every FactionDef in Core, Biotech, Ideology,
        // Royalty, Anomaly and Odyssey and keeping the ones that are visible,
        // non-player and generic. Deliberately absent, with reasons:
        //
        //   Mechanoid, Insect, Entities, HoraxCult,
        //   Sanguophages, Beggars, Pilgrims, Salvagers,
        //   OutlanderRefugee                     - hidden factions. They have no
        //                                          settlements and drive events and
        //                                          quests. Suppressing them removes
        //                                          content and gains nothing.
        //   Ancients, AncientsHostile            - ruins and cryptosleep caskets.
        //                                          Setting-neutral, and load-bearing
        //                                          for ancient dangers.
        //   Empire                               - left alone by the user's explicit
        //                                          decision. It also owns Royalty's
        //                                          entire quest and title chain.
        //   TradersGuild                         - Odyssey's trade faction. Removing
        //                                          it while leaving the player short
        //                                          of trade partners is a worse game.
        //
        // A name that does not resolve is skipped in silence: these span six DLC and
        // a player may own none of them.
        private static readonly string[] GenericFactions =
        {
            // Core
            "OutlanderCivil", "OutlanderRough",
            "TribeCivil", "TribeRough", "TribeSavage",
            "Pirate",
            // Biotech - the xenotype-flavoured variants of the same three archetypes
            "TribeRoughNeanderthal", "PirateYttakin", "TribeSavageImpid",
            "OutlanderRoughPig", "PirateWaster",
            // Ideology
            "TribeCannibal", "NudistTribe", "CannibalPirate",
        };

        // Vanilla's playable-looking xenotypes. Baseliner is NOT here: it is the
        // "no xenotype" default and zeroing it would leave pawn generation with
        // nothing to fall back on. Sanguophage is not here either - it already
        // ships at weight 0 and is granted by mechanics rather than rolled.
        private static readonly string[] VanillaXenotypes =
        {
            "Dirtmole", "Genie", "Hussar", "Neanderthal", "Pigskin",
            "Impid", "Waster", "Yttakin", "Highmate",
        };

        private struct FactionOriginal
        {
            public int RequiredCountAtGameStart;
            public int StartingCountAtWorldCreation;
            public float SettlementGenerationWeight;
        }

        private static readonly Dictionary<FactionDef, FactionOriginal> factionOriginals =
            new Dictionary<FactionDef, FactionOriginal>();
        private static readonly Dictionary<XenotypeDef, float> xenotypeOriginals =
            new Dictionary<XenotypeDef, float>();

        // Every XenotypeChance anywhere in the game that points at a vanilla xenotype,
        // paired with the chance it shipped with.
        //
        // factionlessGenerationWeight ALONE IS NOT ENOUGH. Decompiling PawnGenerator
        // shows it is read in exactly one place - AdjustXenotypeForFactionlessPawn -
        // so it governs wanderers and refugees and nothing else. Pawns belonging to a
        // faction get their xenotype from XenotypesAvailableFor, which reads the
        // faction's (or the kind's) xenotypeSet instead. Suppressing one and not the
        // other would make the setting a half-truth the moment a player kept vanilla
        // factions switched on.
        private static readonly List<KeyValuePair<XenotypeChance, float>> xenotypeChanceOriginals =
            new List<KeyValuePair<XenotypeChance, float>>();

        private static bool captured;

        static VanillaSuppression()
        {
            Apply();
        }

        /// <summary>
        /// Brings the def database in line with the current settings. Safe to call
        /// repeatedly: originals are captured exactly once, on the first call, before
        /// anything has been overwritten.
        /// </summary>
        public static void Apply()
        {
            Capture();

            RimRisingSettings s = RimRisingMod.Settings;

            foreach (KeyValuePair<XenotypeDef, float> kv in xenotypeOriginals)
            {
                kv.Key.factionlessGenerationWeight = s.suppressVanillaXenotypes ? 0f : kv.Value;
            }

            // Zeroing a chance does not need a matching Baseliner entry: XenotypeSet
            // derives BaselinerChance as 1 minus the sum of the rest, so the freed
            // probability falls back to baseliner on its own.
            foreach (KeyValuePair<XenotypeChance, float> kv in xenotypeChanceOriginals)
            {
                kv.Key.chance = s.suppressVanillaXenotypes ? 0f : kv.Value;
            }

            foreach (KeyValuePair<FactionDef, FactionOriginal> kv in factionOriginals)
            {
                FactionDef def = kv.Key;
                FactionOriginal orig = kv.Value;

                if (s.suppressVanillaFactions)
                {
                    // startingCountAtWorldCreation is the field that actually matters.
                    // It sets the DEFAULT count on the world creation page, and vanilla
                    // itself uses 0 for its optional Ideology factions - so zero here
                    // means "still offered, just not on by default", not "gone". A
                    // player who wants outlander towns can still dial them back up.
                    def.startingCountAtWorldCreation = 0;
                    def.requiredCountAtGameStart = 0;
                    def.settlementGenerationWeight = 0f;
                }
                else
                {
                    def.startingCountAtWorldCreation = orig.StartingCountAtWorldCreation;
                    def.requiredCountAtGameStart = orig.RequiredCountAtGameStart;
                    def.settlementGenerationWeight = orig.SettlementGenerationWeight;
                }
            }
        }

        private static void Capture()
        {
            if (captured) { return; }
            captured = true;

            foreach (string name in VanillaXenotypes)
            {
                XenotypeDef def = DefDatabase<XenotypeDef>.GetNamedSilentFail(name);
                if (def == null) { continue; }   // DLC not owned
                xenotypeOriginals[def] = def.factionlessGenerationWeight;
            }

            foreach (string name in GenericFactions)
            {
                FactionDef def = DefDatabase<FactionDef>.GetNamedSilentFail(name);
                if (def == null) { continue; }   // DLC not owned
                factionOriginals[def] = new FactionOriginal
                {
                    RequiredCountAtGameStart    = def.requiredCountAtGameStart,
                    StartingCountAtWorldCreation = def.startingCountAtWorldCreation,
                    SettlementGenerationWeight  = def.settlementGenerationWeight,
                };
            }

            // Walk every faction and every pawn kind for xenotypeSet entries pointing
            // at one of the suppressed xenotypes. Our own defs are skipped: they never
            // reference a vanilla xenotype, and skipping them keeps this incapable of
            // touching RimRising's own castes even if that ever changed.
            foreach (FactionDef def in DefDatabase<FactionDef>.AllDefs)
            {
                if (def.defName.StartsWith("RR_")) { continue; }
                CaptureSet(def.xenotypeSet);
            }
            foreach (PawnKindDef def in DefDatabase<PawnKindDef>.AllDefs)
            {
                if (def.defName.StartsWith("RR_")) { continue; }
                CaptureSet(def.xenotypeSet);
            }

            Log.Message(string.Format(
                "[RimRising] vanilla suppression: {0} xenotype(s), {1} faction(s) and {2} xenotypeSet entr(ies) resolved and captured.",
                xenotypeOriginals.Count, factionOriginals.Count, xenotypeChanceOriginals.Count));
        }

        private static void CaptureSet(XenotypeSet set)
        {
            if (set == null) { return; }
            for (int i = 0; i < set.Count; i++)
            {
                XenotypeChance chance = set[i];
                if (chance?.xenotype == null) { continue; }
                if (!xenotypeOriginals.ContainsKey(chance.xenotype)) { continue; }
                xenotypeChanceOriginals.Add(new KeyValuePair<XenotypeChance, float>(chance, chance.chance));
            }
        }
    }

    public class RimRisingSettings : ModSettings
    {
        public bool suppressVanillaXenotypes = true;
        public bool suppressVanillaFactions  = true;

        public override void ExposeData()
        {
            base.ExposeData();
            Scribe_Values.Look(ref suppressVanillaXenotypes, "suppressVanillaXenotypes", true);
            Scribe_Values.Look(ref suppressVanillaFactions,  "suppressVanillaFactions",  true);
        }
    }

    public class RimRisingMod : Mod
    {
        public static RimRisingSettings Settings { get; private set; }

        public RimRisingMod(ModContentPack content) : base(content)
        {
            // Mod class construction happens in CreateModClasses(), which runs BEFORE
            // LoadModXML(). Verified by decompiling LoadedModManager.LoadAllActiveMods.
            // So settings can be read here, but no def exists yet to be touched - that
            // is why the actual work lives in a StaticConstructorOnStartup instead.
            Settings = GetSettings<RimRisingSettings>();
        }

        public override string SettingsCategory() => "RimRising";

        public override void DoSettingsWindowContents(Rect inRect)
        {
            Listing_Standard list = new Listing_Standard();
            list.Begin(inRect);

            list.CheckboxLabeled(
                "RR_Setting_SuppressXenotypes".Translate(),
                ref Settings.suppressVanillaXenotypes,
                "RR_Setting_SuppressXenotypesTip".Translate());

            list.Gap();

            list.CheckboxLabeled(
                "RR_Setting_SuppressFactions".Translate(),
                ref Settings.suppressVanillaFactions,
                "RR_Setting_SuppressFactionsTip".Translate());

            list.Gap(24f);
            list.Label("RR_Setting_SuppressNote".Translate());

            list.End();
        }

        public override void WriteSettings()
        {
            base.WriteSettings();
            // Re-apply immediately rather than demanding a restart. Worldgen reads
            // these fields when a world is created, so a change taken now is picked
            // up by the next new world - which is the only place it can matter.
            VanillaSuppression.Apply();
        }
    }
}
