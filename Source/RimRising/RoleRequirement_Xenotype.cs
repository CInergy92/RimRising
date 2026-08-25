using System.Collections.Generic;
using System.Linq;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// A role requirement satisfied only by pawns of specific xenotypes.
    ///
    /// WHY THIS EXISTS
    ///
    /// Vanilla ships exactly three RoleRequirement subclasses - MinSkillAny,
    /// SameIdeo and SupremeGender - and none of them can see a pawn's Color. That
    /// makes "only a Gold may hold a knighthood" inexpressible in XML, and the
    /// knighthoods are meaningless without it: an order of thirteen Golds that any
    /// Red can join is not the Olympic Knights.
    ///
    /// HOW
    ///
    /// RoleRequirement is a plain abstract class with one abstract member,
    /// <c>Met(Pawn, Precept_Role)</c>. Subclassing it needs no Harmony - the def
    /// names the class and the game instantiates it, exactly like a
    /// GoodwillSituationWorker. Nothing is patched.
    ///
    /// USAGE
    ///
    ///   &lt;li Class="RimRising.RoleRequirement_Xenotype"&gt;
    ///     &lt;xenotypes&gt;
    ///       &lt;li&gt;RR_Gold&lt;/li&gt;
    ///       &lt;li&gt;RR_Bronzie&lt;/li&gt;
    ///     &lt;/xenotypes&gt;
    ///   &lt;/li&gt;
    ///
    /// NOTE ON CARVED PAWNS
    ///
    /// This reads <c>Pawn.genes.Xenotype</c>, which is what the game displays. A
    /// pawn carved by xenogerm implantation may read as a hybrid rather than as
    /// the target Color, in which case they would NOT satisfy a Gold-only
    /// knighthood. That is arguably the correct outcome for the setting - a carved
    /// Red passing as a Gold is exactly the fiction, and the Society's own
    /// machinery not recognising them is the tension, not a bug. Revisit if
    /// testing shows otherwise.
    /// </summary>
    public class RoleRequirement_Xenotype : RoleRequirement
    {
        /// <summary>Xenotypes that satisfy this requirement. Empty means nothing does.</summary>
        public List<XenotypeDef> xenotypes = new List<XenotypeDef>();

        public override bool Met(Pawn p, Precept_Role role)
        {
            if (p == null || p.genes == null) { return false; }
            if (xenotypes == null || xenotypes.Count == 0) { return false; }

            // A carved Gold can hold a knighthood. That is not a loophole - it is
            // the plot, and the Institute has no gene scanner at the door.
            XenotypeDef current = RR_CasteIdentity.ColorOf(p);
            if (current == null) { return false; }

            for (int i = 0; i < xenotypes.Count; i++)
            {
                if (xenotypes[i] == current) { return true; }
            }
            return false;
        }

        public override string GetLabel(Precept_Role role)
        {
            // Fall back to an explicit labelKey when one is given, so a def can
            // override the wording; otherwise build a readable list from the defs.
            if (!labelKey.NullOrEmpty())
            {
                return base.GetLabel(role);
            }

            if (xenotypes == null || xenotypes.Count == 0)
            {
                return "Must be of a specific Color";
            }

            string names = string.Join(" or ", xenotypes.Where(x => x != null).Select(x => x.LabelCap.ToString()));
            return "Must be " + names;
        }
    }
}
