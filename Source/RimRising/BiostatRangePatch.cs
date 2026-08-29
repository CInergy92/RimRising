using System;
using System.Reflection;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Widens the minimum metabolic efficiency a xenogerm may have.
    ///
    /// WHY THIS EXISTS
    ///
    /// Vanilla defines:
    ///
    ///     GeneTuning.BiostatRange = new IntRange(-5, 5);
    ///
    /// and <c>GeneCreationDialogBase</c> refuses to assemble a xenogerm whose total
    /// metabolism falls below <c>BiostatRange.TrueMin</c>, reporting
    /// "MetabolismTooLowToCreateXenogerm".
    ///
    /// That floor is a hard cap on how expensive a xenotype may be, and it silently
    /// makes any richer xenotype impossible to carve into - the xenogerm simply
    /// cannot be built. For a mod whose central mechanic is carving someone into a
    /// higher caste, a -5 ceiling on ambition is too tight: several Colors exceed it
    /// on genes drawn from the reference material alone.
    ///
    /// HOW
    ///
    /// The field is <c>public static readonly</c>, so there is no setter, but it is
    /// a plain static field and reflection can assign it. This runs once, before the
    /// gene assembler UI is ever opened, so nothing has cached the old value.
    ///
    /// No Harmony patch is needed - we are not altering any method body, only the
    /// tuning constant those methods read.
    ///
    /// BLAST RADIUS - read before changing
    ///
    /// This is a global change. Anything reading BiostatRange.TrueMin sees the new
    /// floor, including other mods and vanilla's own xenotype editor. That is
    /// deliberate for a total conversion, but it is not a local tweak.
    ///
    /// TrueMax is left alone. Only the minimum moves.
    ///
    /// WHAT IT DOES NOT CHANGE
    ///
    /// GeneTuning.MetabolismToFoodConsumptionFactorCurve runs
    ///     (-5, 2.25) -> (0, 1.0) -> (5, 0.5)
    /// and a SimpleCurve clamps at its endpoints. So metabolism below -5 still costs
    /// 2.25x food and no more. Lowering the floor buys design room without an
    /// unbounded food penalty. If that ever needs to bite harder, extend the curve
    /// here too - but that is a separate, deliberate decision.
    /// </summary>
    [StaticConstructorOnStartup]
    public static class BiostatRangePatch
    {
        /// <summary>New minimum metabolic efficiency for xenogerm assembly.</summary>
        public const int MinMetabolism = -10;

        // The value the game shipped with, captured before the first overwrite so
        // the setting below can put it back without a restart.
        private static IntRange? original;

        static BiostatRangePatch()
        {
            Apply();
        }

        /// <summary>
        /// Brings the tuning constant in line with the current setting. Safe to
        /// call repeatedly - WriteSettings does, so a player can opt out of the
        /// widened floor without restarting. The original range is captured
        /// exactly once, before anything is overwritten.
        /// </summary>
        public static void Apply()
        {
            try
            {
                FieldInfo field = typeof(GeneTuning).GetField(
                    nameof(GeneTuning.BiostatRange),
                    BindingFlags.Public | BindingFlags.Static);

                if (field == null)
                {
                    Log.Error("[RimRising] GeneTuning.BiostatRange not found. "
                            + "The game version has changed this field; the xenogerm metabolism floor is unpatched.");
                    return;
                }

                if (original == null)
                {
                    original = (IntRange)field.GetValue(null);
                }

                // Settings may be null if the Mod constructor threw; default to
                // widened, which is what the mod's own Colors need.
                bool widen = RimRisingMod.Settings == null || RimRisingMod.Settings.widenMetabolismFloor;

                IntRange target = widen
                    ? new IntRange(MinMetabolism, original.Value.TrueMax)
                    : original.Value;

                field.SetValue(null, target);

                IntRange applied = (IntRange)field.GetValue(null);
                if (applied.TrueMin != target.TrueMin)
                {
                    Log.Error("[RimRising] Failed to set GeneTuning.BiostatRange. "
                            + "It still reads min " + applied.TrueMin + ".");
                    return;
                }

                if (Prefs.DevMode)
                {
                    Log.Message("[RimRising] Xenogerm metabolism floor now "
                              + applied.TrueMin + " (shipped " + original.Value.TrueMin
                              + "). Max unchanged at " + applied.TrueMax + ".");
                }
            }
            catch (Exception ex)
            {
                Log.Error("[RimRising] Could not set GeneTuning.BiostatRange: " + ex);
            }
        }
    }
}
