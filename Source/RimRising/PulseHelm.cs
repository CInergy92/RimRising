using System.Collections.Generic;
using System.Linq;
using RimWorld;
using UnityEngine;
using Verse;
using HarmonyLib;

namespace RimRising
{
    // Pulse armour's built-in helm, drawn only while the wearer is sealed for a fight.
    //
    // The suit covers FullHead all the time; out of combat the helm is folded into the
    // collar and the face shows. Drafted - or, for NPCs, on a job or duty that shows
    // the weapon, the same test CE's PawnRenderNodeWorker_Drafted uses - the helm is
    // drawn and the hair, beard and eyes under it are hidden.
    //
    // Why a node of our own: vanilla PawnRenderNode_Apparel draws the apparel's worn
    // graphic, not props.texPath, and plain PawnRenderNode cannot take the apparel's
    // dye. CE's PawnRenderNode_Apparel takes its graphic class from the ITEM's
    // graphicData, which for pulse armour is Graphic_Single, so a three-facing helm
    // cannot load through it. Wired in Apparel_RimRising.xml (renderNodeProperties).
    public static class PulseHelm
    {
        public static bool Sealed(Pawn p)
        {
            if (p == null || !p.Spawned) { return false; }
            if (p.Drafted) { return true; }
            return (p.CurJob != null && p.CurJob.def.alwaysShowWeapon)
                || (p.mindState?.duty?.def?.alwaysShowWeapon ?? false);
        }

        private static readonly Dictionary<ThingDef, bool> hasHelm = new Dictionary<ThingDef, bool>();

        public static bool WearsHelm(Pawn p)
        {
            List<Apparel> worn = p.apparel?.WornApparel;
            if (worn == null) { return false; }
            for (int i = 0; i < worn.Count; i++)
            {
                ThingDef d = worn[i].def;
                if (!hasHelm.TryGetValue(d, out bool yes))
                {
                    yes = d.apparel?.RenderNodeProperties?.Any(n => n.nodeClass == typeof(PawnRenderNode_PulseHelm)) == true;
                    hasHelm[d] = yes;
                }
                if (yes) { return true; }
            }
            return false;
        }
    }

    public class PawnRenderNode_PulseHelm : PawnRenderNode_Apparel
    {
        public PawnRenderNode_PulseHelm(Pawn pawn, PawnRenderNodeProperties props, PawnRenderTree tree)
            : base(pawn, props, tree)
        {
            useHeadMesh = true;
        }

        // The base constructor computes the mesh before the apparel is attached, so
        // ask for the head mesh outright rather than through useHeadMesh.
        public override GraphicMeshSet MeshSetFor(Pawn pawn) =>
            HumanlikeMeshPoolUtility.GetHumanlikeHeadSetForPawn(pawn);

        // One texture per facing (<texPath>_south/_east/_north) with a dye mask beside
        // each, tinted with the suit's own colour so the helm matches the wearer's Color.
        protected override IEnumerable<Graphic> GraphicsFor(Pawn pawn)
        {
            if (apparel == null || props.texPath.NullOrEmpty()) { yield break; }
            yield return GraphicDatabase.Get<Graphic_Multi>(props.texPath, ShaderDatabase.CutoutComplex,
                Vector2.one, apparel.DrawColor, apparel.DrawColorTwo);
        }
    }

    public class PawnRenderNodeWorker_PulseHelm : PawnRenderNodeWorker_Apparel_Head
    {
        public override bool CanDrawNow(PawnRenderNode node, PawnDrawParms parms) =>
            PulseHelm.Sealed(node.tree.pawn) && base.CanDrawNow(node, parms);
    }

    // The suit's renderSkipFlags are None so an unsealed wearer keeps their hair; while
    // the helm is up, hide what it covers. AdjustParms runs every draw.
    [HarmonyPatch(typeof(PawnRenderTree), "AdjustParms")]
    public static class Patch_PawnRenderTree_PulseHelmSkips
    {
        public static void Postfix(PawnRenderTree __instance, ref PawnDrawParms parms)
        {
            Pawn p = __instance.pawn;
            if (p?.apparel == null || !PawnRenderNodeWorker_Apparel_Head.HeadgearVisible(parms)) { return; }
            if (!PulseHelm.Sealed(p) || !PulseHelm.WearsHelm(p)) { return; }
            parms.skipFlags |= RenderSkipFlagDefOf.Hair;
            parms.skipFlags |= RenderSkipFlagDefOf.Beard;
            parms.skipFlags |= RenderSkipFlagDefOf.Eyes;
        }
    }
}
