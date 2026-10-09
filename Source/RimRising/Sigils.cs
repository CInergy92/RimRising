using System.Collections.Generic;
using System.Linq;
using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Suggestion 2.1: sigils, and the lie a carved pawn carries.
    ///
    /// A sigil is a hediff on a hand that records what Color the Society's registries
    /// have a person down as (Defs/Carving/Sigils.xml). RR_CasteIdentity.ColorOf reads
    /// genes; this reads the paper. The two disagree exactly when someone has been
    /// carved and nobody has forged a new sigil yet, which is the mechanic.
    ///
    /// Three pieces:
    ///   - SigilFor / SigilOf: map a Color to its sigil hediff and read a pawn's.
    ///   - a PawnGenerator postfix stamping Society-side pawns at generation.
    ///   - Recipe_ForgeSigil, the Violet-only surgery that rewrites one.
    ///
    /// UNBUILT - written in a cloud session without the .NET SDK. The two API points
    /// to check at build: PawnGenerator.GeneratePawn(PawnGenerationRequest) as the
    /// patch target (there are overloads; the request-taking one is the public entry
    /// every caller uses), and HediffMaker.MakeHediff(HediffDef, Pawn, BodyPartRecord).
    /// docs/Opus-Notes.md.
    /// </summary>
    public static class RR_Sigils
    {
        // Factions whose pawns are on the Society's books. The tribes and the
        // Ascomanni were never filed; the Rising keeps whatever it was born with.
        private static readonly HashSet<string> FiledFactions = new HashSet<string>
        {
            "RR_Society", "RR_RimDominion", "RR_JuliiIndustries", "RR_SunIndustries"
        };

        private static BodyPartDef handDef;
        private static BodyPartDef Hand
        {
            get
            {
                if (handDef == null) { handDef = DefDatabase<BodyPartDef>.GetNamedSilentFail("Hand"); }
                return handDef;
            }
        }

        /// <summary>
        /// The sigil hediff for a Color. Sub-strains are filed under their parent:
        /// RR_Gray_Lurcher is Gray, RR_Obsidian_Stained is Obsidian, and Bronzie,
        /// being a Gold strain in the design, is filed as Gold.
        /// </summary>
        public static HediffDef SigilFor(XenotypeDef color)
        {
            if (color == null) { return null; }
            string name = color.defName;
            if (name == "RR_Bronzie") { name = "RR_Gold"; }
            // RR_<Color>_<Strain> -> RR_<Color>
            string[] parts = name.Split('_');
            if (parts.Length > 2) { name = parts[0] + "_" + parts[1]; }
            if (!name.StartsWith("RR_")) { return null; }
            return DefDatabase<HediffDef>.GetNamedSilentFail("RR_Sigil_" + name.Substring(3));
        }

        /// <summary>What the paper says, or null for a pawn with no sigil.</summary>
        public static HediffDef SigilOf(Pawn pawn)
        {
            if (pawn?.health?.hediffSet == null) { return null; }
            foreach (Hediff h in pawn.health.hediffSet.hediffs)
            {
                if (h.def.defName.StartsWith("RR_Sigil_")) { return h.def; }
            }
            return null;
        }

        /// <summary>The Color a sigil names, by reversing SigilFor.</summary>
        public static XenotypeDef ColorOfSigil(HediffDef sigil)
        {
            if (sigil == null || !sigil.defName.StartsWith("RR_Sigil_")) { return null; }
            return DefDatabase<XenotypeDef>.GetNamedSilentFail("RR_" + sigil.defName.Substring("RR_Sigil_".Length));
        }

        /// <summary>True when the paper and the body disagree.</summary>
        public static bool SigilMismatch(Pawn pawn)
        {
            HediffDef sigil = SigilOf(pawn);
            if (sigil == null) { return false; }
            XenotypeDef body = RR_CasteIdentity.ColorOf(pawn);
            if (body == null) { return false; }
            return SigilFor(body) != sigil;
        }

        /// <summary>Remove any sigil and stamp the given one on the first hand.</summary>
        public static void SetSigil(Pawn pawn, HediffDef sigil)
        {
            if (pawn?.health?.hediffSet == null) { return; }
            List<Hediff> old = pawn.health.hediffSet.hediffs
                .Where(h => h.def.defName.StartsWith("RR_Sigil_")).ToList();
            foreach (Hediff h in old) { pawn.health.RemoveHediff(h); }
            if (sigil == null) { return; }

            BodyPartRecord hand = null;
            if (Hand != null)
            {
                hand = pawn.health.hediffSet.GetNotMissingParts().FirstOrDefault(p => p.def == Hand);
            }
            // No hands, no paper. The Society would say the same.
            if (hand == null) { return; }
            pawn.health.AddHediff(sigil, hand);
        }

        public static bool IsFiledFaction(Faction f)
        {
            return f?.def != null && FiledFactions.Contains(f.def.defName);
        }
    }

    /// <summary>
    /// Stamp every pawn generated for a filed faction with its birth Color's sigil.
    /// A postfix, so the pawn is complete (genes, faction) when it runs. Player
    /// starting pawns come through here too, but with the player faction, so they
    /// are not stamped - the Breakout and Household scenarios can add a sigil via
    /// ScenPart_ForcedHediff if that is wanted; it is a design call.
    /// </summary>
    [HarmonyPatch(typeof(PawnGenerator), nameof(PawnGenerator.GeneratePawn), new[] { typeof(PawnGenerationRequest) })]
    public static class Patch_PawnGenerator_Sigil
    {
        public static void Postfix(Pawn __result, PawnGenerationRequest request)
        {
            if (__result == null || !__result.RaceProps.Humanlike) { return; }
            if (!RR_Sigils.IsFiledFaction(request.Faction)) { return; }
            if (RR_Sigils.SigilOf(__result) != null) { return; }
            XenotypeDef color = RR_CasteIdentity.ColorOf(__result);
            HediffDef sigil = RR_Sigils.SigilFor(color);
            if (sigil != null) { RR_Sigils.SetSigil(__result, sigil); }
        }
    }

    /// <summary>
    /// The forgery. Same extension as the carving recipes (CarveTargetExtension names
    /// the Color); same Violet-only gate (RR_CarverWork, enforced in
    /// CarverRestoration.cs). Only the hediff changes - the body is untouched.
    /// </summary>
    public class Recipe_ForgeSigil : Recipe_Surgery
    {
        private XenotypeDef TargetColor
        {
            get
            {
                CarveTargetExtension ext = recipe?.GetModExtension<CarveTargetExtension>();
                return ext?.color;
            }
        }

        public override bool AvailableOnNow(Thing thing, BodyPartRecord part = null)
        {
            if (!base.AvailableOnNow(thing, part)) { return false; }
            if (RimRisingMod.Settings == null || !RimRisingMod.Settings.allowCarverSurgery) { return false; }
            XenotypeDef target = TargetColor;
            if (target == null) { return false; }
            Pawn pawn = thing as Pawn;
            if (pawn == null) { return false; }
            // Pointless to forge what the paper already says.
            return RR_Sigils.SigilOf(pawn) != RR_Sigils.SigilFor(target);
        }

        public override void ApplyOnPawn(Pawn pawn, BodyPartRecord part, Pawn billDoer,
                                         List<Thing> ingredients, Bill bill)
        {
            if (billDoer != null && CheckSurgeryFail(billDoer, pawn, ingredients, part, bill)) { return; }
            XenotypeDef target = TargetColor;
            if (target == null) { return; }
            RR_Sigils.SetSigil(pawn, RR_Sigils.SigilFor(target));
            Messages.Message(
                string.Format("{0}'s sigil now reads {1}.", pawn.LabelShort, target.LabelCap),
                pawn, MessageTypeDefOf.NeutralEvent, historical: false);
        }
    }
}
