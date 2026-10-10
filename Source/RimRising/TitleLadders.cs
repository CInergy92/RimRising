using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Two title ladders on one faction: the Gold ranks and the service ranks,
    /// each walkable only by the caste it belongs to.
    ///
    /// WHY THE FAVOR PATH NEEDS ITS OWN PATCHES. The SetTitle gate in
    /// GoldTitlePatches.cs looked sufficient and is not: decompiling
    /// Pawn_RoyaltyTracker.UpdateRoyalTitle shows the standing/favor path never
    /// calls SetTitle at all - it writes <c>titles[index].def = nextTitle</c>
    /// directly. So a Gold earning standing was walking the MERGED seniority
    /// chain and being made a Legionnaire by the game itself, with our gate
    /// none the wiser. SetTitle only covers quest rewards and other external
    /// callers.
    ///
    /// The three favor-path methods are all instance methods with the pawn in
    /// reach, so each is replaced with an eligibility-aware version that walks
    /// the same chain but SKIPS rungs belonging to the other caste - without
    /// charging their favorCost. A Gold pays Shamed, Graduate, Peerless; a Gray
    /// pays Legionnaire, Praetorian; neither ever sees the other's rungs.
    ///
    /// SCOPE. Every prefix first checks whether the faction's ladder contains
    /// any title carrying our tags, and steps aside entirely when it does not -
    /// the Empire and any other mod's royalty run pure vanilla.
    ///
    /// DEGRADATION. UpdateRoyalTitle is private and its body is mirrored here
    /// from the decompile, using AccessTools for its private members. If any of
    /// those ever vanishes in a game update, the accessors fail ONCE, loudly,
    /// and every prefix then returns true - vanilla behaviour, ungated, rather
    /// than a broken royalty tracker.
    ///
    /// KNOWN EDGE, left alone deliberately: ReduceTitle and title inheritance
    /// use GetPreviousTitle un-patched, so a demotion could step onto the other
    /// caste's rung. Nothing in this mod's factions issues demotions today, and
    /// the SetTitle gate does not cover the direct-write path they use either -
    /// if demotions ever matter, patch ReduceTitle the same way as here.
    /// </summary>
    public static class RR_TitleEligibility
    {
        /// <summary>May this pawn ever hold this title? The one rule both the
        /// SetTitle gate and the favor walk share, so they cannot drift.</summary>
        public static bool EligibleFor(Pawn pawn, RoyalTitleDef title)
        {
            if (pawn == null || title?.tags == null) { return true; }
            if (Patch_Pawn_RoyaltyTracker_SetTitle.IsGoldRung(title))
            {
                return RR_XenotypeUtility.IsRulingCaste(pawn);
            }
            if (Patch_Pawn_RoyaltyTracker_SetTitle.IsServiceRung(title))
            {
                return !RR_XenotypeUtility.IsRulingCaste(pawn);
            }
            return true;
        }

        /// <summary>Does this faction carry either of our ladders at all?</summary>
        public static bool FactionHasCasteLadder(Faction faction)
        {
            var list = faction?.def?.RoyalTitlesAwardableInSeniorityOrderForReading;
            if (list == null) { return false; }
            for (int i = 0; i < list.Count; i++)
            {
                if (Patch_Pawn_RoyaltyTracker_SetTitle.IsGoldRung(list[i]) || Patch_Pawn_RoyaltyTracker_SetTitle.IsServiceRung(list[i]))
                {
                    return true;
                }
            }
            return false;
        }

        /// <summary>
        /// The next rung on THIS PAWN'S ladder after <paramref name="current"/>,
        /// skipping the other caste's rungs as if they were not in the chain.
        /// </summary>
        public static RoyalTitleDef NextEligible(Pawn pawn, Faction faction, RoyalTitleDef current)
        {
            var list = faction.def.RoyalTitlesAwardableInSeniorityOrderForReading;
            int start = 0;
            if (current != null)
            {
                int idx = list.IndexOf(current);
                if (idx < 0) { return null; }   // mirror GetNextTitle: unknown title advances nowhere
                start = idx + 1;
            }
            for (int i = start; i < list.Count; i++)
            {
                if (EligibleFor(pawn, list[i])) { return list[i]; }
            }
            return null;
        }
    }

    /// <summary>
    /// "Is a title update available" - drives the banner alert. Replaced so the
    /// alert fires for the pawn's own next rung, not the merged chain's.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RoyaltyTracker), nameof(Pawn_RoyaltyTracker.CanUpdateTitle))]
    public static class Patch_Pawn_RoyaltyTracker_CanUpdateTitle
    {
        public static bool Prefix(Pawn_RoyaltyTracker __instance, Faction faction, ref bool __result)
        {
            if (faction == null || !RR_TitleEligibility.FactionHasCasteLadder(faction)) { return true; }

            Pawn pawn = __instance.pawn;
            RoyalTitleDef next = RR_TitleEligibility.NextEligible(pawn, faction, __instance.GetCurrentTitle(faction));
            __result = next != null && __instance.GetFavor(faction) >= next.favorCost;
            return false;
        }
    }

    /// <summary>
    /// The UI preview of what the update will award. Same walk as the award
    /// itself, or the dialog promises a title the pawn cannot hold.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RoyaltyTracker), nameof(Pawn_RoyaltyTracker.GetTitleAwardedWhenUpdating))]
    public static class Patch_Pawn_RoyaltyTracker_GetTitleAwardedWhenUpdating
    {
        public static bool Prefix(Pawn_RoyaltyTracker __instance, Faction faction, int favor,
                                  ref RoyalTitleDef __result)
        {
            if (faction == null || !RR_TitleEligibility.FactionHasCasteLadder(faction)) { return true; }

            Pawn pawn = __instance.pawn;
            RoyalTitleDef at = __instance.GetCurrentTitle(faction);
            RoyalTitleDef result = null;
            // Mirrors vanilla's loop shape (favor > 0 to keep walking, favor >= 0
            // to accept), with ineligible rungs invisible and free.
            while (favor > 0)
            {
                RoyalTitleDef next = RR_TitleEligibility.NextEligible(pawn, faction, at);
                if (next == null) { break; }
                favor -= next.favorCost;
                if (favor >= 0) { result = next; }
                at = next;
            }
            __result = result;
            return false;
        }
    }

    /// <summary>
    /// The award itself. Mirrored from the decompiled body - which is the part
    /// that writes the title WITHOUT going through SetTitle - with the single
    /// change that the rung walked to is the pawn's next eligible one. The
    /// recursion is a loop here; behaviour is otherwise line for line.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_RoyaltyTracker), "UpdateRoyalTitle")]
    public static class Patch_Pawn_RoyaltyTracker_UpdateRoyalTitle
    {
        // Private members of Pawn_RoyaltyTracker, resolved lazily so a missing
        // one degrades to vanilla instead of poisoning the type (the same
        // failure mode RR-015 removed from the relations patch).
        private static System.Reflection.MethodInfo onPreTitleChanged;
        private static System.Reflection.MethodInfo findFactionTitleIndex;
        private static System.Reflection.MethodInfo cleanupThoughts;
        private static AccessTools.FieldRef<Pawn_RoyaltyTracker, System.Collections.Generic.List<RoyalTitle>> titlesField;
        private static bool resolved;
        private static bool failed;

        private static bool Resolve()
        {
            if (failed) { return false; }
            if (resolved) { return true; }
            try
            {
                onPreTitleChanged = AccessTools.Method(typeof(Pawn_RoyaltyTracker), "OnPreTitleChanged");
                findFactionTitleIndex = AccessTools.Method(typeof(Pawn_RoyaltyTracker), "FindFactionTitleIndex");
                cleanupThoughts = AccessTools.Method(typeof(Pawn_RoyaltyTracker), "CleanupThoughts");
                titlesField = AccessTools.FieldRefAccess<Pawn_RoyaltyTracker, System.Collections.Generic.List<RoyalTitle>>("titles");
                failed = onPreTitleChanged == null || findFactionTitleIndex == null || cleanupThoughts == null;
                resolved = !failed;
            }
            catch
            {
                failed = true;
            }
            if (failed)
            {
                Log.Error("[RimRising] Pawn_RoyaltyTracker private members not found; "
                        + "the caste-aware title ladder is disabled and favor advancement runs vanilla.");
            }
            return resolved;
        }

        /// <summary>
        /// Harmony runs Prepare BEFORE it resolves the target method - verified in
        /// PatchClassProcessor.Patch, where RunMethod&lt;HarmonyPrepare&gt; is the
        /// first statement and GetBulkMethods comes after. That ordering is the
        /// whole reason this exists: UpdateRoyalTitle is PRIVATE and named by
        /// string, so if Ludeon ever renames it, attribute target resolution would
        /// throw during PatchAll and take startup down with it. Returning false
        /// here skips the class instead, leaving favor advancement on vanilla.
        /// </summary>
        public static bool Prepare()
        {
            if (AccessTools.Method(typeof(Pawn_RoyaltyTracker), "UpdateRoyalTitle") != null)
            {
                return true;
            }
            Log.Error("[RimRising] Pawn_RoyaltyTracker.UpdateRoyalTitle not found; the "
                    + "caste-aware title ladder is disabled and favor advancement runs vanilla. "
                    + "A Gold and a Gray will share one seniority chain.");
            return false;
        }

        public static bool Prefix(Pawn_RoyaltyTracker __instance, Faction faction,
                                  bool sendLetter, RoyalTitleDef updateTo)
        {
            if (faction == null || !RR_TitleEligibility.FactionHasCasteLadder(faction)) { return true; }
            if (!Resolve()) { return true; }

            Pawn pawn = __instance.pawn;
            while (true)
            {
                RoyalTitleDef current = __instance.GetCurrentTitle(faction);
                if (current != null && !current.Awardable) { return false; }

                RoyalTitleDef next = RR_TitleEligibility.NextEligible(pawn, faction, current);
                if (next == null) { return false; }

                int favor = __instance.GetFavor(faction);
                if (favor < next.favorCost) { return false; }

                onPreTitleChanged.Invoke(__instance, new object[] { faction, current, next, sendLetter });
                __instance.SetFavor(faction, favor - next.favorCost, notifyOnFavorChanged: false);
                int index = (int)findFactionTitleIndex.Invoke(__instance, new object[] { faction, true });
                titlesField(__instance)[index].def = next;
                cleanupThoughts.Invoke(__instance, new object[] { current });
                cleanupThoughts.Invoke(__instance, new object[] { next });
                if (next.awardThought != null && pawn.needs?.mood != null)
                {
                    Thought_MemoryRoyalTitle memory =
                        (Thought_MemoryRoyalTitle)ThoughtMaker.MakeThought(next.awardThought);
                    memory.titleDef = next;
                    pawn.needs.mood.thoughts.memories.TryGainMemory(memory);
                }

                if (next == updateTo) { return false; }
                // Vanilla recurses here; the loop is the same walk without the
                // re-entry, and the eligibility skip applies on every pass.
            }
        }
    }
}
