using System.Linq;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// A one-shot report on why the Color ladder is or is not producing thoughts.
    ///
    /// The chain from def to visible opinion has four links, and every one of them
    /// fails SILENTLY when broken:
    ///
    ///   1. the ThoughtDef resolves its workerClass          -> ThoughtDef.IsSituational
    ///   2. its thoughtClass implements ISocialThought       -> ThoughtDef.IsSocial
    ///   3. (1 and 2) put it in ThoughtUtility.situationalSocialThoughtDefs,
    ///      which is the only list SituationalThoughtHandler ever walks
    ///   4. the pawn's ideoligion holds a precept naming it, checked by
    ///      ThoughtWorker_Precept_Social against ideo.cachedPossibleSituationalThoughts
    ///
    /// Static analysis confirmed all four are correct in principle, which is exactly
    /// when it stops being worth reasoning and starts being worth measuring. This
    /// prints the actual state of 1-3 at startup, and the worker below reports 4 and
    /// the rank lookup the first few times it is asked.
    ///
    /// Harmless to leave in: it is a handful of log lines at startup and at most
    /// three afterwards.
    /// </summary>
    [StaticConstructorOnStartup]
    public static class LadderDiagnostic
    {
        static LadderDiagnostic()
        {
            ReportThought("RR_Thought_ColorRank");
            ReportThought("RR_Thought_ColorCrossing");
        }

        private static void ReportThought(string defName)
        {
            ThoughtDef t = DefDatabase<ThoughtDef>.GetNamedSilentFail(defName);
            if (t == null)
            {
                Log.Warning("[RimRising] ladder: ThoughtDef " + defName + " DOES NOT EXIST.");
                return;
            }

            bool inList = ThoughtUtility.situationalSocialThoughtDefs != null &&
                          ThoughtUtility.situationalSocialThoughtDefs.Contains(t);

            Log.Message(string.Format(
                "[RimRising] ladder: {0} worker={1} situational={2} social={3} inCandidateList={4} stages={5}",
                defName,
                t.Worker == null ? "NULL" : t.Worker.GetType().Name,
                t.IsSituational,
                t.IsSocial,
                inList,
                t.stages == null ? 0 : t.stages.Count));

            if (!inList)
            {
                Log.Warning("[RimRising] ladder: " + defName + " is NOT in situationalSocialThoughtDefs, " +
                            "so RimWorld will never evaluate it. That list is built once at startup from " +
                            "IsSituational && IsSocial.");
            }
        }

        // Reports on the base-class gate, which is where the chain actually stops.
        public static int RemainingGateReports = 3;

        /// <summary>
        /// Prints whether the pawn's ideoligion holds a precept naming this thought,
        /// and if not, what precepts it does hold - which distinguishes "wrong
        /// ideoligion" from "precept present but cache not rebuilt".
        /// </summary>
        public static void ReportGate(Pawn p, Ideo ideo, ThoughtDef def)
        {
            if (ideo == null)
            {
                Log.Warning("[RimRising] ladder gate: " + (p?.LabelShort ?? "?") + " has NO IDEO.");
                return;
            }

            bool held = ideo.cachedPossibleSituationalThoughts != null &&
                        ideo.cachedPossibleSituationalThoughts.Contains(def);

            string precepts = string.Join(", ", ideo.PreceptsListForReading
                .Select(pr => pr.def.defName)
                .Where(n => n.StartsWith("RR_"))
                .DefaultIfEmpty("<none of ours>"));

            string memes = string.Join(", ", ideo.memes
                .Select(m => m.defName)
                .Where(n => n.StartsWith("RR_"))
                .DefaultIfEmpty("<none of ours>"));

            Log.Message(string.Format(
                "[RimRising] ladder gate: pawn={0} ideo='{1}' holdsThought={2} | our memes: {3} | our precepts: {4}",
                p?.LabelShort, ideo.name, held, memes, precepts));
        }

        // Counts down the number of per-evaluation reports still to print.
        public static int RemainingCallReports = 3;

        /// <summary>
        /// Called from the worker the first few times it actually runs, so the log
        /// shows whether it is reached at all and what it saw.
        /// </summary>
        public static void ReportCall(Pawn p, Pawn other, string outcome)
        {
            if (RemainingCallReports <= 0) { return; }
            RemainingCallReports--;

            string mine  = p?.genes?.Xenotype?.defName ?? "<none>";
            string yours = other?.genes?.Xenotype?.defName ?? "<none>";
            string ideo  = p?.Ideo?.name ?? "<no ideo>";

            Log.Message(string.Format(
                "[RimRising] ladder call: {0} ({1}) vs {2} ({3}) ideo='{4}' -> {5}",
                p?.LabelShort, mine, other?.LabelShort, yours, ideo, outcome));
        }
    }
}
