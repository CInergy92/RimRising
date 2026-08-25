using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Cross-Color reproduction is impossible.
    ///
    /// "Inter-color marriages and reproduction are strictly prohibited, with
    /// violators subject to execution" - but the prohibition is the SOCIAL layer.
    /// Underneath it the castes were engineered apart far enough that two
    /// different Colors simply cannot conceive. Getting a child out of a mixed
    /// pairing takes a Carver, not permission.
    ///
    /// This is therefore a GLOBAL rule, not an ideoligious one. It applies
    /// regardless of what anybody believes, because it is biology rather than law
    /// - the opposite of the razor restriction, which is law rather than biology.
    ///
    /// Scoped deliberately: it only fires when BOTH pawns are RimRising Colors and
    /// those Colors differ. A Color paired with a baseliner or with some other
    /// mod's xenotype is left alone, since the setting says nothing about those and
    /// silently sterilising them would be an unpleasant surprise.
    /// </summary>
    [HarmonyPatch(typeof(PregnancyUtility), nameof(PregnancyUtility.CanEverProduceChild))]
    public static class Patch_PregnancyUtility_CanEverProduceChild
    {
        public static void Postfix(Pawn first, Pawn second, ref AcceptanceReport __result)
        {
            // Never overturn an existing refusal; only add ours.
            if (!__result.Accepted) { return; }

            if (!RR_CasteUtility.AreDifferentColors(first, second)) { return; }

            __result = "RR_CannotConceiveAcrossColors".Translate(
                first.Named("PAWN1"),
                second.Named("PAWN2"));
        }
    }

    /// <summary>
    /// Cross-Color attraction is suppressed.
    ///
    /// Two layers, matching the fiction:
    ///
    ///   Engineering - the castes were shaped apart and conditioned from birth, so
    ///     baseline attraction across Colors is low for everyone, everywhere.
    ///
    ///   Law - where an ideoligion actually holds the hierarchy, it is not merely
    ///     unlikely but unthinkable, and drops to nothing.
    ///
    /// Suppressed rather than forbidden outright at the engineering layer, because
    /// people crossing that line anyway is the engine of the entire setting. If it
    /// were impossible there would be no story.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RelationsTracker), nameof(Pawn_RelationsTracker.SecondaryRomanceChanceFactor))]
    public static class Patch_Pawn_RelationsTracker_SecondaryRomanceChanceFactor
    {
        private const float CrossColorFactor = 0.15f;

        public static void Postfix(Pawn_RelationsTracker __instance, Pawn otherPawn, ref float __result)
        {
            if (__result <= 0f) { return; }

            Pawn pawn = RR_CasteUtility.GetTrackerPawn(__instance);
            if (pawn == null || otherPawn == null) { return; }
            if (!RR_CasteUtility.AreDifferentColors(pawn, otherPawn)) { return; }

            if (RR_CasteUtility.HoldsHierarchy(pawn) || RR_CasteUtility.HoldsHierarchy(otherPawn))
            {
                __result = 0f;
                return;
            }

            __result *= CrossColorFactor;
        }
    }

    /// <summary>
    /// Raises an event when a cross-Color bond forms in spite of everything, so
    /// the precepts in Precepts_InterColorUnion.xml have something to react to.
    /// RimWorld ships no history event for romance, marriage or death, so if we
    /// want an ideoligion to have an opinion about this, we have to raise it.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RelationsTracker), nameof(Pawn_RelationsTracker.AddDirectRelation))]
    public static class Patch_Pawn_RelationsTracker_AddDirectRelation
    {
        public static void Postfix(Pawn_RelationsTracker __instance, PawnRelationDef def, Pawn otherPawn)
        {
            if (def == null) { return; }
            if (def != PawnRelationDefOf.Lover && def != PawnRelationDefOf.Fiance && def != PawnRelationDefOf.Spouse)
            {
                return;
            }

            Pawn pawn = RR_CasteUtility.GetTrackerPawn(__instance);
            if (pawn == null || otherPawn == null) { return; }
            if (!RR_CasteUtility.AreDifferentColors(pawn, otherPawn)) { return; }

            HistoryEventDef ev = RR_RelationDefOf.RR_InterColorUnion;
            if (ev == null || !RR_CasteUtility.CanRaiseHistoryEvent()) { return; }

            Find.HistoryEventsManager.RecordEvent(
                new HistoryEvent(ev, pawn.Named(HistoryEventArgsNames.Doer)));
        }
    }

    public static class RR_CasteUtility
    {
        /// <summary>
        /// Whether it is safe to raise a HistoryEvent right now.
        ///
        /// RimWorld fabricates relationships and hands out weapons while GENERATING
        /// pawns - during worldgen, faction creation and the scenario page - long
        /// before there is a game to notify. Raising an event then reaches
        /// IdeoUtility.Notify_HistoryEvent, which walks caravans, maps and the
        /// player faction, and throws:
        ///
        ///     Could not find player faction.
        ///     Error while notifying ideos of a HistoryEvent: NullReferenceException
        ///
        /// HistoryEventsManager catches and logs it, so nothing breaks - it just
        /// fills the log at every world creation, and the trace stops at the catch
        /// site so nothing in it points back to us.
        ///
        /// Nothing is lost by skipping these. A backstory marriage invented during
        /// pawn generation is not a lowColor defying the hierarchy; it is set
        /// dressing that predates the colony. These events exist for things that
        /// happen in play.
        /// </summary>
        public static bool CanRaiseHistoryEvent()
        {
            if (Current.ProgramState != ProgramState.Playing) { return false; }
            if (Find.HistoryEventsManager == null) { return false; }
            if (Find.FactionManager == null) { return false; }
            if (Faction.OfPlayerSilentFail == null) { return false; }
            return true;
        }

        private static readonly AccessTools.FieldRef<Pawn_RelationsTracker, Pawn> PawnField =
            AccessTools.FieldRefAccess<Pawn_RelationsTracker, Pawn>("pawn");

        /// <summary>The tracker's owning pawn; the field is private, hence the ref.</summary>
        public static Pawn GetTrackerPawn(Pawn_RelationsTracker tracker)
        {
            if (tracker == null) { return null; }
            try { return PawnField(tracker); }
            catch { return null; }
        }

        /// <summary>True only when both pawns are RimRising Colors and the Colors differ.</summary>
        public static bool AreDifferentColors(Pawn a, Pawn b)
        {
            if (a?.genes == null || b?.genes == null) { return false; }

            XenotypeDef xa = a.genes.Xenotype;
            XenotypeDef xb = b.genes.Xenotype;
            if (xa == null || xb == null) { return false; }
            if (xa == xb) { return false; }

            return IsColor(xa) && IsColor(xb);
        }

        /// <summary>
        /// A Color is one of ours. Keyed on the defName prefix rather than a hard
        /// list so sub-tiers and any future Colors are covered automatically.
        /// </summary>
        public static bool IsColor(XenotypeDef x)
        {
            return x != null && x.defName != null && x.defName.StartsWith("RR_");
        }

        public static bool HoldsHierarchy(Pawn pawn)
        {
            if (pawn?.Ideo == null) { return false; }
            MemeDef meme = RR_RelationDefOf.RR_ColorHierarchy;
            return meme != null && pawn.Ideo.HasMeme(meme);
        }
    }

    [DefOf]
    public static class RR_RelationDefOf
    {
        public static HistoryEventDef RR_InterColorUnion;
        public static MemeDef RR_ColorHierarchy;

        static RR_RelationDefOf()
        {
            DefOfHelper.EnsureInitializedInCtor(typeof(RR_RelationDefOf));
        }
    }
}
