using System.Collections.Generic;
using System.Linq;
using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Caste marks (StyleDefs/Styles_RimRising.xml) are imposed, not chosen - the
    /// user's call, 2026-10-09.
    ///
    /// The first draft left them to vanilla's style roll, which can never pick them:
    /// a pawn with an ideoligion only gets a tattoo the ideoligion's culture or memes
    /// tag (IdeoStyleTracker.RecalculateAvailableStyleItems), and the kind's
    /// styleItemTags only weight within that set. rrtestmode=m12 measured 0 of 30.
    ///
    /// So after generation, a pawn whose kind names an RR_...Marks style tag is given
    /// the matching tattoo for each slot one exists for (face, body), with the tag's
    /// weight as the chance, capped at 1. The kinds carry weight 1: every Legionary
    /// has a legion mark. The ideoligion is not asked - the Society does not ask.
    /// </summary>
    [HarmonyPatch(typeof(PawnGenerator), nameof(PawnGenerator.GeneratePawn), new[] { typeof(PawnGenerationRequest) })]
    public static class Patch_PawnGenerator_CasteMarks
    {
        public static void Postfix(Pawn __result)
        {
            if (__result?.style == null || !ModsConfig.IdeologyActive) { return; }
            List<StyleItemTagWeighted> tags = __result.kindDef?.styleItemTags;
            if (tags == null) { return; }
            foreach (StyleItemTagWeighted t in tags)
            {
                if (t.Tag == null || !t.Tag.StartsWith("RR_") || !t.Tag.EndsWith("Marks")) { continue; }
                if (!Rand.Chance(System.Math.Min(1f, t.TotalWeight))) { continue; }
                List<TattooDef> marks = DefDatabase<TattooDef>.AllDefsListForReading
                    .Where(d => d.styleTags != null && d.styleTags.Contains(t.Tag)).ToList();
                if (marks.Where(d => d.tattooType == TattooType.Face).TryRandomElement(out TattooDef face))
                {
                    __result.style.FaceTattoo = face;
                }
                if (marks.Where(d => d.tattooType == TattooType.Body).TryRandomElement(out TattooDef body))
                {
                    __result.style.BodyTattoo = body;
                }
            }
        }
    }
}
