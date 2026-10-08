using System.Collections.Generic;
using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Marks a recipe as Carver's work. Two things follow from it: only a Violet
    /// may perform it, and the recipe is described as carving in its report.
    ///
    /// A DefModExtension rather than a defName prefix or a hard-coded list,
    /// because the check runs on every bill a pawn considers taking and wants to
    /// be a field read rather than a string compare.
    /// </summary>
    public class RR_CarverWork : DefModExtension
    {
    }

    /// <summary>
    /// "Carvers are Violet artists who specialize in the creation and alteration
    /// of organic tissue." Every carving surgery in this mod - restoration and
    /// Color alike - is therefore Violet work.
    ///
    /// WHY THIS HOOK. RecipeDef gates the SURGEON only by skillRequirements;
    /// there is no field for who may perform a recipe. Bill.PawnAllowedToStartAnew
    /// is the one place vanilla asks "may this specific pawn start this specific
    /// bill" - it is what pawnRestriction, slavesOnly and mechsOnly all run
    /// through - so it is the correct place to add a fourth restriction rather
    /// than inventing one somewhere further down the job chain.
    ///
    /// The bill simply goes untaken if no Violet is available, exactly as it does
    /// when nobody meets a skill requirement. That is a real gameplay wall by
    /// design: a colony with no Carver cannot carve.
    /// </summary>
    [HarmonyPatch(typeof(Bill), nameof(Bill.PawnAllowedToStartAnew))]
    public static class Bill_PawnAllowedToStartAnew_CarverOnly
    {
        public static void Postfix(Bill __instance, Pawn p, ref bool __result)
        {
            if (!__result) { return; }
            if (__instance?.recipe == null || p == null) { return; }
            if (!__instance.recipe.HasModExtension<RR_CarverWork>()) { return; }

            XenotypeDef color = RR_CasteIdentity.ColorOf(p);
            if (color != RR_CarverDefOf.RR_Violet) { __result = false; return; }

            // PreceptComp_UnwillingToDo is only a UI line until code asks: without
            // this a Violet whose ideoligion says "won't carve someone into another
            // Color" took the bill anyway. Colour carves only - restoration is not
            // the act the precept names.
            if (__instance.recipe.HasModExtension<CarveTargetExtension>() &&
                RR_CarveDefOf.RR_ColorCarved != null &&
                !IdeoUtility.DoerWillingToDo(RR_CarveDefOf.RR_ColorCarved, p))
            {
                __result = false;
            }
        }
    }

    /// <summary>
    /// Regrow a limb the patient has lost.
    ///
    /// "Carvers most commonly provide body modifications such as regrowing or
    /// reattaching lost body parts." This is the Carver's ordinary trade and the
    /// thing the setting actually turns on after a battle: the armour keeps a
    /// casualty alive, and then somebody rebuilds them.
    ///
    /// Modelled as ONE recipe that offers every missing part rather than as a
    /// dozen vat-grown limb items. Vanilla only ever made organs into items -
    /// there is no arm or leg ThingDef to install - so the item route would have
    /// meant inventing a parallel set of things for no mechanical gain.
    ///
    /// GetMissingPartsCommonAncestors is vanilla's own answer to "what has this
    /// pawn lost", used by the health tab and by prosthetic surgery, so the parts
    /// offered here are exactly the parts the game already considers missing.
    /// </summary>
    public class Recipe_RegrowPart : Recipe_Surgery
    {
        public override IEnumerable<BodyPartRecord> GetPartsToApplyOn(Pawn pawn, RecipeDef recipe)
        {
            if (pawn?.health?.hediffSet == null) { yield break; }

            foreach (Hediff_MissingPart missing in pawn.health.hediffSet.GetMissingPartsCommonAncestors())
            {
                // A part whose parent is also gone cannot be regrown on its own -
                // GetMissingPartsCommonAncestors already returns only the topmost
                // missing part of each branch, which is what makes that true.
                yield return missing.Part;
            }
        }

        public override void ApplyOnPawn(Pawn pawn, BodyPartRecord part, Pawn billDoer, List<Thing> ingredients, Bill bill)
        {
            if (billDoer != null && CheckSurgeryFail(billDoer, pawn, ingredients, part, bill)) { return; }
            if (part == null) { return; }

            pawn.health.RestorePart(part);

            if (PawnUtility.ShouldSendNotificationAbout(pawn))
            {
                Messages.Message(
                    "RR_CarverRegrewPart".Translate(pawn.LabelShort.Named("PAWN"),
                                                    part.Label.Named("PART")),
                    pawn, MessageTypeDefOf.PositiveEvent, historical: false);
            }
        }
    }

    /// <summary>
    /// Repair a permanent injury - a scar, a bad back, a ruined eye.
    ///
    /// The cosmetic half of the Carver's trade, and the half that matters to a
    /// Gold: a Peerless does not walk around wearing the record of a fight they
    /// won. Mechanically it is the one thing vanilla medicine cannot do at all
    /// outside a healer mech serum.
    ///
    /// Targets the WORST permanent injury the patient has, one surgery at a time,
    /// so a heavily scarred pawn is a repeated expense rather than a single bill.
    /// </summary>
    public class Recipe_RepairScar : Recipe_Surgery
    {
        /// <summary>The worst permanent injury, or null if there is none.</summary>
        public static Hediff WorstPermanentInjury(Pawn pawn)
        {
            if (pawn?.health?.hediffSet == null) { return null; }

            Hediff worst = null;
            float worstSeverity = 0f;
            foreach (Hediff h in pawn.health.hediffSet.hediffs)
            {
                if (!h.IsPermanent()) { continue; }
                if (worst != null)
                {
                    if (h.Severity < worstSeverity) { continue; }
                    // Equal severities tie-break on loadID - the oldest injury -
                    // so which scar the Carver removes is stable across loads
                    // rather than falling to hediff list ordering.
                    if (h.Severity == worstSeverity && h.loadID >= worst.loadID) { continue; }
                }
                worst = h;
                worstSeverity = h.Severity;
            }
            return worst;
        }

        public override bool AvailableOnNow(Thing thing, BodyPartRecord part = null)
        {
            if (!base.AvailableOnNow(thing, part)) { return false; }
            return WorstPermanentInjury(thing as Pawn) != null;
        }

        public override void ApplyOnPawn(Pawn pawn, BodyPartRecord part, Pawn billDoer, List<Thing> ingredients, Bill bill)
        {
            if (billDoer != null && CheckSurgeryFail(billDoer, pawn, ingredients, part, bill)) { return; }

            Hediff worst = WorstPermanentInjury(pawn);
            if (worst == null) { return; }

            string label = worst.Label;
            pawn.health.RemoveHediff(worst);

            if (PawnUtility.ShouldSendNotificationAbout(pawn))
            {
                Messages.Message(
                    "RR_CarverRepairedScar".Translate(pawn.LabelShort.Named("PAWN"),
                                                      label.Named("INJURY")),
                    pawn, MessageTypeDefOf.PositiveEvent, historical: false);
            }
        }
    }

    /// <summary>
    /// CompHatcher for a CRAFTED thing rather than a laid one.
    ///
    /// Vanilla CompHatcher gets its hatcheeFaction from the hen that laid the egg
    /// or from the trade that delivered it; a vat built at a fabrication bench has
    /// neither, so hatcheeFaction stays null and the creature hatches WILD - an
    /// animalisk the colony paid fourteen resFlesh for would emerge as a hostile
    /// stranger in the middle of the workshop. A crafted vat belongs to the
    /// player, so the field is claimed on first tick if nothing else set it
    /// (trade paths still overwrite it, exactly as vanilla intends).
    /// </summary>
    public class CompCarvelingHatcher : CompHatcher
    {
        public override void CompTick()
        {
            if (hatcheeFaction == null)
            {
                hatcheeFaction = Faction.OfPlayerSilentFail;
            }
            base.CompTick();
        }
    }

    [DefOf]
    public static class RR_CarverDefOf
    {
        public static XenotypeDef RR_Violet;

        static RR_CarverDefOf()
        {
            DefOfHelper.EnsureInitializedInCtor(typeof(RR_CarverDefOf));
        }
    }
}
