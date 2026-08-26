using System.Collections.Generic;
using HarmonyLib;
using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Two rules about who wears the good armour, and what colour it is when they do.
    ///
    /// COLOUR CAST. RecoilArmor is dyed to its wearer's Color - Darrow's is red
    /// because he was born a Red, and that is the single most legible thing about
    /// him. A suit therefore takes the colour of whoever puts it on, which turns a
    /// battlefield into a readable diagram of the hierarchy: gold at the back,
    /// grey in the middle, red where the fighting is.
    ///
    /// ACCESS. Inside the Society only Golds wear recoilArmor and pulseArmor, plus
    /// the handful of Obsidians and Grays who have been given a title for proven
    /// loyalty. Everyone else fights in duroArmor.
    ///
    /// GATED ON A PRECEPT, exactly as the razor restriction is. The rule is a
    /// social fact rather than a property of the plate, so it binds a colony that
    /// holds the Society's hierarchy precept and does not bind the Rising. A
    /// Rising colony can armour whoever it likes - which is the whole argument the
    /// Rising is making, and it would be perverse for the mod to enforce the
    /// Society's law on the people rejecting it.
    /// </summary>
    public static class RR_CasteArmor
    {
        /// <summary>Apparel tag marking a suit as reserved to the ruling caste and its trusted.</summary>
        public const string RestrictedTag = "RR_ArmorRestricted";

        /// <summary>Apparel tag marking a suit that takes its wearer's Color.</summary>
        public const string CasteColoredTag = "RR_CasteColored";

        public static bool IsRestricted(ThingDef def)
        {
            return def?.apparel?.tags != null && def.apparel.tags.Contains(RestrictedTag);
        }

        public static bool IsCasteColored(ThingDef def)
        {
            return def?.apparel?.tags != null && def.apparel.tags.Contains(CasteColoredTag);
        }

        /// <summary>
        /// Does this pawn's ideoligion actually believe in the Color hierarchy?
        ///
        /// Both rules here hang off this. The armour restriction is a Society law,
        /// and dyeing a suit to its wearer's caste is a Society habit - neither is
        /// a property of the plate, and neither should be imposed on the people
        /// who reject the whole idea.
        /// </summary>
        public static bool BelievesInColor(Pawn pawn)
        {
            if (pawn?.Ideo == null) { return false; }
            PreceptDef restriction = RR_ArmorDefOf.RR_ArmorBearing_Restricted;
            return restriction != null && pawn.Ideo.HasPrecept(restriction);
        }

        /// <summary>
        /// May this pawn wear caste-restricted plate?
        ///
        /// PERMISSIVE BY DEFAULT. Anything unusual - no pawn, no ideoligion, a
        /// colony that never took the precept - returns true, because a rule that
        /// fires when it cannot tell is worse than one that does not fire. The
        /// restriction binds only those who believe in the hierarchy; the Rising
        /// arms whoever it likes, which is its entire argument.
        /// </summary>
        public static bool MayWearRestricted(Pawn pawn)
        {
            if (pawn == null) { return true; }
            if (!BelievesInColor(pawn)) { return true; }

            // Golds, always.
            if (RR_XenotypeUtility.IsRulingCaste(pawn)) { return true; }

            // Obsidians and Grays who hold a title: the Society arms the ones it
            // has decided it can trust, and a title is how it says so.
            XenotypeDef color = RR_CasteIdentity.ColorOf(pawn);
            if (color != null &&
                (color == RR_ArmorDefOf.RR_Obsidian || color == RR_ArmorDefOf.RR_Gray) &&
                HasSocietyTitle(pawn))
            {
                return true;
            }

            return false;
        }

        private static bool HasSocietyTitle(Pawn pawn)
        {
            // royalty is null on a game without the DLC active, and on most pawns
            // even with it, so this has to be defensive rather than assume.
            return pawn?.royalty != null && pawn.royalty.AllTitlesInEffectForReading.Count > 0;
        }

        /// <summary>
        /// Paint a suit to its wearer's Color, and mark the pawn for redraw.
        /// Silent no-op for anything not caste-coloured or not colourable.
        /// </summary>
        public static void ApplyCasteColor(Apparel apparel, Pawn wearer)
        {
            if (apparel == null || wearer == null) { return; }
            if (!IsCasteColored(apparel.def)) { return; }

            // TINT APPLIES TO BOTH SIDES, and is deliberately NOT gated on the
            // hierarchy precept the way the wear restriction is. The Rising does
            // not stop caring what Color someone is - it cares enormously, which
            // is the point of it. Darrow's plate is red because he was born a Red
            // and wants that seen; a Society Gold's is gold for the opposite
            // reason. Same mechanic, opposite meaning, and the mod should not take
            // a side by only colouring one of them.
            CompColorable colorable = apparel.TryGetComp<CompColorable>();
            if (colorable == null) { return; }

            XenotypeDef color = RR_CasteIdentity.ColorOf(wearer);
            if (color == null) { return; }

            Color? dye = RR_CasteColors.For(color);
            if (!dye.HasValue) { return; }

            colorable.SetColor(dye.Value);
            // Without this the suit keeps whatever it was drawn as until something
            // else dirties the pawn - the colour is set but invisible, which reads
            // as the feature not working at all.
            wearer.Drawer?.renderer?.SetAllGraphicsDirty();
        }
    }

    /// <summary>
    /// The dye each Color uses. Kept in C# rather than on the XenotypeDef because
    /// XenotypeDef has no colour field to hang it on - see the field list in
    /// CLAUDE.md - and inventing one would mean a DefModExtension on fifteen defs
    /// to express fifteen constants.
    ///
    /// These are the CASTE colours, deliberately muted to sit in RimWorld's
    /// palette rather than the saturated primaries the names suggest.
    /// </summary>
    public static class RR_CasteColors
    {
        private static readonly Dictionary<string, Color> ByDefName =
            new Dictionary<string, Color>
            {
                { "RR_Gold",     new Color(0.72f, 0.58f, 0.26f) },
                { "RR_Bronzie",  new Color(0.60f, 0.42f, 0.22f) },
                { "RR_Silver",   new Color(0.66f, 0.68f, 0.70f) },
                { "RR_Copper",   new Color(0.63f, 0.36f, 0.22f) },
                { "RR_Blue",     new Color(0.28f, 0.40f, 0.60f) },
                { "RR_Yellow",   new Color(0.74f, 0.68f, 0.32f) },
                { "RR_Green",    new Color(0.34f, 0.50f, 0.34f) },
                { "RR_Violet",   new Color(0.45f, 0.34f, 0.56f) },
                { "RR_Orange",   new Color(0.72f, 0.44f, 0.20f) },
                { "RR_Gray",     new Color(0.45f, 0.46f, 0.48f) },
                { "RR_Brown",    new Color(0.42f, 0.32f, 0.24f) },
                { "RR_Obsidian", new Color(0.20f, 0.20f, 0.23f) },
                { "RR_Pink",     new Color(0.72f, 0.48f, 0.54f) },
                { "RR_Red",      new Color(0.57f, 0.16f, 0.16f) },
                { "RR_White",    new Color(0.80f, 0.80f, 0.78f) },
            };

        public static Color? For(XenotypeDef color)
        {
            if (color == null) { return null; }
            Color found;
            if (ByDefName.TryGetValue(color.defName, out found)) { return found; }
            return null;
        }
    }

    /// <summary>
    /// The AI and outfit paths both run apparel past PawnCanWear, so narrowing it
    /// here keeps colonists from optimising into plate they are not entitled to.
    /// Postfix only, and only ever turns an allow into a refusal - vanilla's own
    /// reasons for saying no must win.
    /// </summary>
    [HarmonyPatch(typeof(ApparelProperties), nameof(ApparelProperties.PawnCanWear),
                  new[] { typeof(Pawn), typeof(bool) })]
    public static class Patch_ApparelProperties_PawnCanWear
    {
        public static void Postfix(ApparelProperties __instance, Pawn pawn, ref bool __result)
        {
            if (!__result) { return; }
            if (__instance?.tags == null) { return; }
            if (!__instance.tags.Contains(RR_CasteArmor.RestrictedTag)) { return; }
            if (RR_CasteArmor.MayWearRestricted(pawn)) { return; }
            __result = false;
        }
    }

    /// <summary>
    /// The same rule on the equip path, which is what a player's manual "wear
    /// this" order goes through. Both hooks are patched deliberately: PawnCanWear
    /// covers the automatic paths and this covers the deliberate one, and missing
    /// either would leave the restriction half-enforced in a way that looks like a
    /// bug rather than a rule.
    /// </summary>
    [HarmonyPatch(typeof(EquipmentUtility), nameof(EquipmentUtility.CanEquip))]
    [HarmonyPatch(new[] { typeof(Thing), typeof(Pawn), typeof(string), typeof(bool) },
                  new[] { ArgumentType.Normal, ArgumentType.Normal, ArgumentType.Out, ArgumentType.Normal })]
    public static class Patch_CanEquip_RestrictedArmor
    {
        public static void Postfix(Thing thing, Pawn pawn, ref string cantReason, ref bool __result)
        {
            if (!__result) { return; }
            if (!RR_CasteArmor.IsRestricted(thing?.def)) { return; }
            if (RR_CasteArmor.MayWearRestricted(pawn)) { return; }

            __result = false;
            cantReason = "RR_CannotWearCasteArmor".Translate(pawn.Named("PAWN"));
        }
    }

    /// <summary>
    /// Dye the suit when it goes on. Wear is the only moment the wearer is known,
    /// so it is the only place the colour can be decided.
    /// </summary>
    [HarmonyPatch(typeof(Pawn_ApparelTracker), nameof(Pawn_ApparelTracker.Wear))]
    public static class Patch_Pawn_ApparelTracker_Wear
    {
        public static void Postfix(Pawn_ApparelTracker __instance, Apparel newApparel)
        {
            RR_CasteArmor.ApplyCasteColor(newApparel, __instance?.pawn);
        }
    }

    [DefOf]
    public static class RR_ArmorDefOf
    {
        public static PreceptDef RR_ArmorBearing_Restricted;
        public static XenotypeDef RR_Obsidian;
        public static XenotypeDef RR_Gray;

        static RR_ArmorDefOf()
        {
            DefOfHelper.EnsureInitializedInCtor(typeof(RR_ArmorDefOf));
        }
    }
}
