using System.Collections.Generic;
using System.Linq;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Starting colonists' sigils (the user's call, 2026-10-10): the Household and the
    /// Institute begin with each pawn's true Color on the hand; the Rising's breakout
    /// begins with forged ones - the mismatch the Society's census and its Lurchers
    /// look for (RR_Sigils.SigilMismatch).
    ///
    /// Vanilla's ScenPart_ForcedHediff gives every starting pawn the SAME hediff, and a
    /// sigil has to follow each pawn's Color, so this part does it per pawn at
    /// PostGameStart, to the free colonists then on the map.
    /// </summary>
    public class ScenPart_Sigils : ScenPart
    {
        public bool forged;

        // Paper that passes without a second look: service and trade Colors. Nobody
        // forges a Gold sigil and expects to live.
        private static readonly string[] ForgeAs = { "RR_Brown", "RR_Orange", "RR_Gray" };

        public override void ExposeData()
        {
            base.ExposeData();
            Scribe_Values.Look(ref forged, "forged", false);
        }

        public override string Summary(Scenario scen)
        {
            return (forged ? "RR_ScenPartSigilsForged" : "RR_ScenPartSigilsTrue").Translate();
        }

        public override void PostGameStart()
        {
            foreach (Map map in Find.Maps)
            {
                foreach (Pawn p in map.mapPawns.FreeColonists)
                {
                    XenotypeDef color = RR_CasteIdentity.ColorOf(p);
                    if (color == null) { continue; }
                    HediffDef sigil;
                    if (forged)
                    {
                        List<XenotypeDef> options = ForgeAs
                            .Select(n => DefDatabase<XenotypeDef>.GetNamedSilentFail(n))
                            .Where(x => x != null && x != color).ToList();
                        if (!options.TryRandomElement(out XenotypeDef fake)) { continue; }
                        sigil = RR_Sigils.SigilFor(fake);
                    }
                    else
                    {
                        sigil = RR_Sigils.SigilFor(color);
                    }
                    if (sigil != null) { RR_Sigils.SetSigil(p, sigil); }
                }
            }
        }
    }
}
