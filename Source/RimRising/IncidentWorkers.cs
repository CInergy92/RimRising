using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Letter-only incidents. Suggestion 6.4 (the Laurel) and the Board's census
    /// letter from the suggestions' section 3. Defs/IncidentDefs/Incidents_RimRising.xml.
    ///
    /// Both fire only on a colony the Society would bother with: at least one
    /// colonist who reads as a lowColor. The Laurel is a Red's prize and a census is
    /// something done TO people; a colony of Golds gets neither.
    ///
    /// UNBUILT - written in a cloud session without the .NET SDK. API points to check
    /// at build: IncidentWorker.CanFireNowSub / TryExecuteWorker signatures,
    /// Find.LetterStack.ReceiveLetter(string, string, LetterDef), and
    /// Find.Storyteller.incidentQueue.Add(IncidentDef, int, IncidentParms).
    /// docs/Opus-Notes.md.
    /// </summary>
    public class IncidentWorker_Letter : IncidentWorker
    {
        // The ladder's lower half: Gray and below in displayPriority terms
        // (XenotypeDefs_Colors.xml, Gray 100). Read off the def so the two cannot drift.
        private const int LowColorPriority = 100;

        protected static bool ColonyHasLowColor(Map map)
        {
            if (map == null) { return false; }
            foreach (Pawn p in map.mapPawns.FreeColonists)
            {
                XenotypeDef c = RR_CasteIdentity.ColorOf(p);
                if (c != null && c.displayPriority >= LowColorPriority) { return true; }
            }
            return false;
        }

        protected override bool CanFireNowSub(IncidentParms parms)
        {
            if (!base.CanFireNowSub(parms)) { return false; }
            return ColonyHasLowColor(parms.target as Map);
        }

        protected override bool TryExecuteWorker(IncidentParms parms)
        {
            Find.LetterStack.ReceiveLetter(def.letterLabel, def.letterText, def.letterDef ?? LetterDefOf.NeutralEvent);
            return true;
        }
    }

    /// <summary>
    /// The Laurel: the quota letter now, and the "awarded elsewhere" letter fifteen
    /// days later, queued through the storyteller so it survives a save.
    /// </summary>
    public class IncidentWorker_Laurel : IncidentWorker_Letter
    {
        private const int FollowUpTicks = 15 * 60000;

        protected override bool TryExecuteWorker(IncidentParms parms)
        {
            if (!base.TryExecuteWorker(parms)) { return false; }
            IncidentDef awarded = DefDatabase<IncidentDef>.GetNamedSilentFail("RR_Incident_LaurelAwarded");
            if (awarded != null)
            {
                IncidentParms follow = new IncidentParms { target = parms.target };
                Find.Storyteller.incidentQueue.Add(awarded, Find.TickManager.TicksGame + FollowUpTicks, follow);
            }
            return true;
        }
    }
}
