using System.Linq;
using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Keeps the Society's standing ladder to the caste that is allowed to climb it.
    ///
    /// WHY HARMONY, WHEN A WORKER EXISTS
    ///
    /// RoyalTitleDef.awardWorkerClass looked like the clean answer and is not.
    /// RoyalTitleAwardWorker exposes only OnPreAward and DoAward, both returning
    /// void, so it is a notification hook rather than a gate - it can react to an
    /// award but cannot refuse one. Pawn_RoyaltyTracker.SetTitle is the only place
    /// the decision is actually made.
    ///
    /// WHAT THIS DOES NOT DO
    ///
    /// It does not touch vanilla Empire titles, or any title from another mod. Only
    /// titles tagged RR_GoldTitle - ours, from Defs/RoyalTitles - are gated, so an
    /// Empire knighthood still works exactly as it always did for anyone.
    ///
    /// Removing a title is always allowed. Only granting one is checked.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RoyaltyTracker), nameof(Pawn_RoyaltyTracker.SetTitle))]
    public static class Patch_Pawn_RoyaltyTracker_SetTitle
    {
        public const string GoldTitleTag = "RR_GoldTitle";

        public static bool Prefix(Pawn_RoyaltyTracker __instance, Faction faction, RoyalTitleDef title)
        {
            // Null means the title is being STRIPPED. Never block that - a Gold can
            // always be shamed out of a rank, and blocking removal would strand a
            // title on a pawn who has just lost it.
            if (title == null) { return true; }
            if (title.tags == null || !title.tags.Contains(GoldTitleTag)) { return true; }

            Pawn pawn = __instance?.pawn;
            if (pawn == null) { return true; }
            if (RR_XenotypeUtility.IsRulingCaste(pawn)) { return true; }

            // Refuse, and say so. A silent skip here would look like the game had
            // eaten a quest reward.
            Messages.Message(
                "RR_CannotHoldGoldTitle".Translate(pawn.Named("PAWN"), title.GetLabelCapFor(pawn).Named("TITLE")),
                pawn, MessageTypeDefOf.RejectInput, historical: false);

            return false;
        }
    }
}
