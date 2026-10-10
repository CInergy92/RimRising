using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Keeps both of the Society's ladders to the castes allowed to climb them:
    /// titles tagged RR_GoldTitle are refused to anyone who is not of the ruling
    /// caste, and titles tagged RR_ServiceTitle are refused to anyone who IS. A
    /// Gold is not made a Praetorian - the rank exists precisely as what the
    /// Society offers the people it will never make Gold.
    ///
    /// ONE PREFIX FOR BOTH GATES, deliberately. These used to be two Harmony
    /// prefix classes on the same method, each able to return false, with
    /// nothing but reflection ordering deciding which ran first. The conditions
    /// were mutually exclusive so it happened to work, but an ordering hazard
    /// that happens to work is still an ordering hazard - merged, there is no
    /// ordering to depend on.
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
    /// It does not touch vanilla Empire titles, or any title from another mod.
    /// Only titles carrying our two tags are gated, so an Empire knighthood still
    /// works exactly as it always did for anyone.
    ///
    /// Removing a title is always allowed. Only granting one is checked.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RoyaltyTracker), nameof(Pawn_RoyaltyTracker.SetTitle))]
    public static class Patch_Pawn_RoyaltyTracker_SetTitle
    {
        public const string GoldTitleTag = "RR_GoldTitle";
        public const string ServiceTitleTag = "RR_ServiceTitle";
        // The Rim Dominion's own ladder (RoyalTitles_Rim.xml): same rules, own tags,
        // so neither power awards the other's titles.
        public const string RimGoldTitleTag = "RR_RimGoldTitle";
        public const string RimServiceTitleTag = "RR_RimServiceTitle";

        public static bool IsGoldRung(RoyalTitleDef t) =>
            t?.tags != null && (t.tags.Contains(GoldTitleTag) || t.tags.Contains(RimGoldTitleTag));

        public static bool IsServiceRung(RoyalTitleDef t) =>
            t?.tags != null && (t.tags.Contains(ServiceTitleTag) || t.tags.Contains(RimServiceTitleTag));

        public static bool Prefix(Pawn_RoyaltyTracker __instance, Faction faction, RoyalTitleDef title)
        {
            // Null means the title is being STRIPPED. Never block that - a Gold can
            // always be shamed out of a rank, and blocking removal would strand a
            // title on a pawn who has just lost it.
            if (title == null || title.tags == null) { return true; }

            Pawn pawn = __instance?.pawn;
            if (pawn == null) { return true; }

            bool refuse;
            string messageKey;
            if (IsGoldRung(title))
            {
                refuse = !RR_XenotypeUtility.IsRulingCaste(pawn);
                messageKey = "RR_CannotHoldGoldTitle";
            }
            else if (IsServiceRung(title))
            {
                refuse = RR_XenotypeUtility.IsRulingCaste(pawn);
                messageKey = "RR_CannotHoldServiceTitle";
            }
            else
            {
                return true;
            }

            if (!refuse) { return true; }

            // Refuse, and say so - a silent skip would look like the game had
            // eaten a quest reward. NegativeEvent rather than RejectInput so the
            // refusal survives in the message log, the faction is named so the
            // player can tell WHICH reward was refused, and nothing is shown at
            // all outside play: royal titles are also assigned during pawn
            // generation, long before there is a screen to message.
            if (Current.ProgramState == ProgramState.Playing)
            {
                Messages.Message(
                    messageKey.Translate(pawn.Named("PAWN"), title.GetLabelCapFor(pawn).Named("TITLE"))
                        + " (" + (faction?.Name ?? "?") + ")",
                    pawn, MessageTypeDefOf.NegativeEvent, historical: false);
            }

            return false;
        }
    }
}
