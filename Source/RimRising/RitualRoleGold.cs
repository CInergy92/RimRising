using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// A trial by razor is fought between Golds (docs/Opus-Notes.md, "Gold-only
    /// duelists"). RitualRoleColonist with one more condition: the pawn must read as
    /// the ruling caste - Gold or Bronzie, born or carved (RR_CasteIdentity). Used for
    /// both duelist roles in Rituals_RazorTrial.xml; the speaker is unrestricted.
    /// </summary>
    public class RitualRoleGold : RitualRoleColonist
    {
        public override bool AppliesToPawn(Pawn p, out string reason, TargetInfo selectedTarget,
            LordJob_Ritual ritual = null, RitualRoleAssignments assignments = null,
            Precept_Ritual precept = null, bool skipReason = false)
        {
            if (!base.AppliesToPawn(p, out reason, selectedTarget, ritual, assignments, precept, skipReason))
            {
                return false;
            }
            if (RR_CasteIdentity.IsRulingCaste(p)) { return true; }
            if (!skipReason) { reason = "RR_RazorTrialGoldOnly".Translate(p.Named("PAWN")); }
            return false;
        }
    }
}
