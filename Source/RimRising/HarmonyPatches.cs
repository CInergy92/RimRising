using System.Reflection;
using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Harmony setup. Kept deliberately small - the only patch here is the razor
    /// caste restriction, which cannot be expressed in XML at all.
    /// </summary>
    [StaticConstructorOnStartup]
    public static class HarmonyPatches
    {
        static HarmonyPatches()
        {
            var harmony = new Harmony("cinergy92.rimrising");
            harmony.PatchAll(Assembly.GetExecutingAssembly());
            Log.Message("[RimRising] Harmony patches applied.");
        }
    }

    /// <summary>
    /// "It is forbidden for any other Color to wield the weapon, with merely
    /// touching it being punishable by death."
    ///
    /// WHY A PATCH
    ///
    /// Vanilla cannot express this. Precept_Weapon gates by weapon CLASS, not by
    /// who is holding it, and RimWorld raises no history event when a pawn equips
    /// a weapon - so there is nothing for a precept to react to. Both halves of
    /// the mechanic have to come from here.
    ///
    /// WHAT IT IS NOT
    ///
    /// Not a law of physics. The block only applies to a pawn whose ideoligion
    /// actually holds RR_RazorBearing_GoldOnly. A raider, a resistance fighter, or
    /// any colony that never adopted the hierarchy can pick up a razor freely -
    /// and the Society's fury about that is the point of the whole mechanic. The
    /// Rising began partly with lowColors being handed razors precisely because
    /// of what it meant.
    ///
    /// Postfix rather than prefix: vanilla's own reasons for refusing (bonded
    /// bladelink weapons, and so on) should win, and we only add a reason when the
    /// item would otherwise be equippable.
    /// </summary>
    [HarmonyPatch(typeof(EquipmentUtility), nameof(EquipmentUtility.CanEquip))]
    [HarmonyPatch(new[] { typeof(Thing), typeof(Pawn), typeof(string), typeof(bool) },
                  new[] { ArgumentType.Normal, ArgumentType.Normal, ArgumentType.Out, ArgumentType.Normal })]
    public static class Patch_EquipmentUtility_CanEquip
    {
        /// <summary>Weapon tag marking an item as reserved to the ruling caste.</summary>
        public const string CasteRestrictedTag = "RR_CasteRestricted";

        public static void Postfix(Thing thing, Pawn pawn, ref string cantReason, ref bool __result)
        {
            // Only narrow an allow; never overturn vanilla's refusal.
            if (!__result) { return; }

            if (thing?.def?.weaponTags == null) { return; }
            if (!thing.def.weaponTags.Contains(CasteRestrictedTag)) { return; }

            if (pawn == null || pawn.Ideo == null) { return; }

            PreceptDef restriction = RR_DefOf.RR_RazorBearing_GoldOnly;
            if (restriction == null || !pawn.Ideo.HasPrecept(restriction)) { return; }

            if (RR_XenotypeUtility.IsRulingCaste(pawn)) { return; }

            __result = false;
            cantReason = "RR_CannotBearRazor".Translate(pawn.Named("PAWN"));
        }
    }

    /// <summary>
    /// Raises the history event when the restriction is violated in spite of
    /// everything - a raider carrying one onto the map, or a colony that rejects
    /// the hierarchy arming a Red on purpose. Without this the precepts in
    /// Precepts_RazorBearing.xml would have nothing to react to.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_EquipmentTracker), nameof(Pawn_EquipmentTracker.AddEquipment))]
    public static class Patch_Pawn_EquipmentTracker_AddEquipment
    {
        public static void Postfix(Pawn_EquipmentTracker __instance, ThingWithComps newEq)
        {
            Pawn pawn = __instance?.pawn;
            if (pawn == null || newEq?.def?.weaponTags == null) { return; }
            if (!newEq.def.weaponTags.Contains(Patch_EquipmentUtility_CanEquip.CasteRestrictedTag)) { return; }
            if (RR_XenotypeUtility.IsRulingCaste(pawn)) { return; }

            HistoryEventDef ev = RR_DefOf.RR_LowColorBoreRazor;
            if (ev == null) { return; }

            Find.HistoryEventsManager.RecordEvent(new HistoryEvent(ev, pawn.Named(HistoryEventArgsNames.Doer)));
        }
    }

    /// <summary>Shared xenotype test, so both patches agree on who counts as Gold.</summary>
    public static class RR_XenotypeUtility
    {
        public static bool IsRulingCaste(Pawn pawn)
        {
            if (pawn?.genes == null) { return false; }
            XenotypeDef x = pawn.genes.Xenotype;
            if (x == null) { return false; }
            // Bronzies are Gold by birth and by law. The order and the Compact
            // both admit them, so the razor does too.
            return x == RR_DefOf.RR_Gold || x == RR_DefOf.RR_Bronzie;
        }
    }

    [DefOf]
    public static class RR_DefOf
    {
        public static PreceptDef RR_RazorBearing_GoldOnly;
        public static HistoryEventDef RR_LowColorBoreRazor;
        public static XenotypeDef RR_Gold;
        public static XenotypeDef RR_Bronzie;

        static RR_DefOf()
        {
            DefOfHelper.EnsureInitializedInCtor(typeof(RR_DefOf));
        }
    }
}
