using System.Collections.Generic;
using System.Linq;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// The Lurcher hunt (suggestion 2.2, docs/Opus-Notes.md): the Society sends its
    /// hunters after someone it has reason to want.
    ///
    /// Fires only when the Society is hostile to the colony AND it has a reason: a
    /// colonist whose sigil does not match their Color (RR_Sigils.SigilMismatch), or a
    /// lowColor having borne a razor in the last sixty days (RR_LowColorBoreRazor). The
    /// raid is the Society's, and only Lurchers: the faction carries a pawn group of
    /// kind RR_LurcherHunt holding nothing else (Factions_RimRising.xml), and this
    /// worker asks for that kind. The letter names who they came for.
    ///
    /// Built on IncidentWorker_RaidEnemy; decompiled, TryGenerateRaidInfo honours a
    /// preset parms.faction when it is hostile and generates from parms.pawnGroupKind.
    /// </summary>
    public class IncidentWorker_LurcherHunt : IncidentWorker_RaidEnemy
    {
        private const int RazorMemoryTicks = 60 * 60000;

        private static Faction Society =>
            Find.FactionManager.AllFactionsListForReading.FirstOrDefault(f => f.def.defName == "RR_Society" && !f.defeated);

        /// <summary>Who the Society is after on this map, or null.</summary>
        public static Pawn Quarry(Map map)
        {
            if (map == null) { return null; }
            List<Pawn> colonists = map.mapPawns.FreeColonists.ToList();
            Pawn forged = colonists.FirstOrDefault(RR_Sigils.SigilMismatch);
            if (forged != null) { return forged; }
            HistoryEventDef bore = DefDatabase<HistoryEventDef>.GetNamedSilentFail("RR_LowColorBoreRazor");
            if (bore != null && Find.HistoryEventsManager.GetRecentCountWithinTicks(bore, RazorMemoryTicks) > 0)
            {
                // The one holding a razor now if there is one; otherwise any lowColor.
                return colonists.FirstOrDefault(p => !RR_CasteIdentity.IsRulingCaste(p) && RR_CasteIdentity.ColorOf(p) != null &&
                                                     p.equipment?.Primary?.def.weaponTags?.Contains("RR_RazorBearer") == true)
                    ?? colonists.FirstOrDefault(p => !RR_CasteIdentity.IsRulingCaste(p) && RR_CasteIdentity.ColorOf(p) != null);
            }
            return null;
        }

        protected override bool CanFireNowSub(IncidentParms parms)
        {
            Faction s = Society;
            if (s == null || !s.HostileTo(Faction.OfPlayer)) { return false; }
            if (Quarry(parms.target as Map) == null) { return false; }
            return base.CanFireNowSub(parms);
        }

        protected override bool TryExecuteWorker(IncidentParms parms)
        {
            parms.faction = Society;
            parms.pawnGroupKind = RR_LurcherDefOf.RR_LurcherHunt;
            parms.raidStrategy = RaidStrategyDefOf.ImmediateAttack;
            return base.TryExecuteWorker(parms);
        }

        protected override string GetLetterLabel(IncidentParms parms) => def.letterLabel;

        protected override string GetLetterText(IncidentParms parms, List<Pawn> pawns)
        {
            Pawn q = Quarry(parms.target as Map);
            string text = q == null
                ? "RR_LurcherHuntText".Translate()
                : "RR_LurcherHuntTextNamed".Translate(q.Named("PAWN"));
            return text + "\n\n" + base.GetLetterText(parms, pawns);
        }
    }

    [DefOf]
    public static class RR_LurcherDefOf
    {
        public static PawnGroupKindDef RR_LurcherHunt;

        static RR_LurcherDefOf() { DefOfHelper.EnsureInitializedInCtor(typeof(RR_LurcherDefOf)); }
    }
}
