using System.Collections.Generic;
using System.Linq;
using HarmonyLib;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// The census reads sigils (docs/Opus-Notes.md, "Sigil reads"). When a census
    /// caravan arrives (RR_Caravan_*_Census) and a colonist's sigil does not match their
    /// Color, the census-takers notice: a letter naming who, and goodwill lost with the
    /// power that sent them. A census is a count, not a hunt - the hunt is the
    /// Lurchers' job (LurcherHunt.cs), and needs the Society hostile.
    ///
    /// Postfix on IncidentWorker_TraderCaravanArrival.SendLetter, which vanilla calls
    /// once per arrival with the resolved trader kind (decompiled).
    /// </summary>
    [HarmonyPatch(typeof(IncidentWorker_TraderCaravanArrival), "SendLetter")]
    public static class Patch_CensusReadsSigils
    {
        public const int GoodwillPerDiscrepancy = -8;

        public static void Postfix(IncidentParms parms, TraderKindDef traderKind)
        {
            if (traderKind == null || !traderKind.defName.EndsWith("_Census")) { return; }
            if (!(parms?.target is Map map) || parms.faction == null) { return; }
            List<Pawn> wrong = map.mapPawns.FreeColonists.Where(RR_Sigils.SigilMismatch).ToList();
            if (wrong.Count == 0) { return; }
            parms.faction.TryAffectGoodwillWith(Faction.OfPlayer, GoodwillPerDiscrepancy * wrong.Count,
                canSendMessage: true, canSendHostilityLetter: true);
            string names = wrong.Select(p => p.LabelShort).ToCommaList(useAnd: true);
            Find.LetterStack.ReceiveLetter("RR_CensusDiscrepancyLabel".Translate(),
                "RR_CensusDiscrepancyText".Translate(parms.faction.NameColored, names, -GoodwillPerDiscrepancy * wrong.Count),
                LetterDefOf.NegativeEvent, new LookTargets(wrong));
        }
    }
}
