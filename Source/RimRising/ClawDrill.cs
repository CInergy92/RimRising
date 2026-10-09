using System.Collections.Generic;
using RimWorld;
using Verse;
using Verse.AI;

namespace RimRising
{
    /// <summary>
    /// Vanilla's deep-drill work giver, pointed at the clawDrill.
    ///
    /// Decompiled, WorkGiver_DeepDrill hard-codes ThingDefOf.DeepDrill twice: as its
    /// PotentialWorkThingRequest and in ShouldSkip. Any other drill def - with the same
    /// CompDeepDrill and the same OperateDeepDrill job - is therefore never offered as
    /// work, and sits built and idle. HasJobOnThing and JobOnThing key only on the
    /// comp and the job, so they are inherited unchanged.
    /// </summary>
    public class WorkGiver_ClawDrill : WorkGiver_DeepDrill
    {
        public override ThingRequest PotentialWorkThingRequest =>
            ThingRequest.ForDef(RR_ClawDrillDefOf.RR_ClawDrill);

        public override bool ShouldSkip(Pawn pawn, bool forced = false)
        {
            List<Building> buildings = pawn.Map.listerBuildings.allBuildingsColonist;
            for (int i = 0; i < buildings.Count; i++)
            {
                Building b = buildings[i];
                if (b.def != RR_ClawDrillDefOf.RR_ClawDrill) { continue; }
                CompPowerTrader power = b.GetComp<CompPowerTrader>();
                if ((power == null || power.PowerOn) &&
                    b.Map.designationManager.DesignationOn(b, DesignationDefOf.Uninstall) == null)
                {
                    return false;
                }
            }
            return true;
        }
    }

    [DefOf]
    public static class RR_ClawDrillDefOf
    {
        public static ThingDef RR_ClawDrill;

        static RR_ClawDrillDefOf() { DefOfHelper.EnsureInitializedInCtor(typeof(RR_ClawDrillDefOf)); }
    }
}
