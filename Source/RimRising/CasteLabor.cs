using System.Collections.Generic;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Suggestion 2.3: caste-restricted work, the soft way.
    ///
    /// Colors are confined to their caste's trade by law. The hard version - work
    /// incapables on the gene - was rejected in DESIGN.md: a Red who CANNOT research
    /// is a worse RimWorld pawn and it is wrong anyway. Reds are denied education,
    /// not unable. So this is a thought, not a lock: a pawn whose ideoligion holds
    /// the hierarchy precept feels it when they work outside their Color's trades,
    /// and a pawn under the equality precept feels the opposite.
    ///
    /// The table of "which Color may do what" is a DefModExtension on each
    /// XenotypeDef (CasteWorkExtension, XenotypeDefs_Colors.xml), so it is data and
    /// the Colors can be re-balanced without touching this file. A Color with no
    /// extension is unrestricted, which is what the sub-strains fall back to via
    /// RR_CasteIdentity.ColorOf, which already resolves a Lurcher to its own def.
    ///
    /// WHAT IS READ. Pawn.CurJob.workGiverDef.workType. It is set for every job that
    /// came from a work giver, which is most of them; jobs taken directly (a drafted
    /// pawn, a forced job from the right-click menu, hauling via JobGiver_Work's
    /// opportunistic path) may carry no work giver and are treated as no work at
    /// all - the thought simply does not fire. That is the honest fallback the
    /// suggestions doc asked for, and it errs towards silence.
    ///
    /// UNBUILT. Written in a cloud session without the .NET SDK. ThoughtWorker_Precept
    /// is the non-social sibling of ThoughtWorker_Precept_Social, which this mod
    /// already uses (ThoughtWorker_ColorRank.cs); if the base class name differs the
    /// build names the line. docs/Opus-Notes.md.
    /// </summary>
    public class CasteWorkExtension : DefModExtension
    {
        // Work types this Color is permitted by the Society. Everything else is
        // "above" or "below" its station; the thought does not distinguish, since
        // the setting punishes both.
        public List<WorkTypeDef> allowedWorkTypes = new List<WorkTypeDef>();
    }

    public static class CasteLabor
    {
        /// <summary>
        /// True when the pawn is currently doing work its Color is not permitted,
        /// false when it is permitted, has no Color, has no table, or is not working.
        /// </summary>
        public static bool WorkingOutsideCaste(Pawn p)
        {
            if (p == null || p.jobs == null || p.CurJob == null) { return false; }
            WorkGiverDef giver = p.CurJob.workGiverDef;
            if (giver == null || giver.workType == null) { return false; }

            XenotypeDef color = RR_CasteIdentity.ColorOf(p);
            if (color == null) { return false; }
            CasteWorkExtension ext = color.GetModExtension<CasteWorkExtension>();
            if (ext == null || ext.allowedWorkTypes == null || ext.allowedWorkTypes.Count == 0)
            {
                return false;
            }
            return !ext.allowedWorkTypes.Contains(giver.workType);
        }
    }

    /// <summary>"Work above my station" - the hierarchy's reading. Stage 0.</summary>
    public class ThoughtWorker_CasteLabor : ThoughtWorker_Precept
    {
        protected override ThoughtState ShouldHaveThought(Pawn p)
        {
            return CasteLabor.WorkingOutsideCaste(p)
                ? ThoughtState.ActiveAtStage(0)
                : ThoughtState.Inactive;
        }
    }

    /// <summary>"Doing what I was never allowed" - the equality reading. Stage 0.</summary>
    public class ThoughtWorker_CasteLabor_Equality : ThoughtWorker_Precept
    {
        protected override ThoughtState ShouldHaveThought(Pawn p)
        {
            return CasteLabor.WorkingOutsideCaste(p)
                ? ThoughtState.ActiveAtStage(0)
                : ThoughtState.Inactive;
        }
    }
}
