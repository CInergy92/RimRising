using System.Collections.Generic;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// What Color a pawn READS AS, which is not always the Color they were born.
    ///
    /// WHY THIS EXISTS - the answer to open question U1
    ///
    /// U1 asked whether implanting a xenogerm built from an exact Color gene set
    /// makes the pawn read as that Color, or as some kind of hybrid. Decompiling
    /// GeneUtility.ImplantXenogermItem settles it, and the answer is neither:
    ///
    ///     pawn.genes.SetXenotype(XenotypeDefOf.Baseliner);
    ///     pawn.genes.xenotypeName = xenogerm.xenotypeName;
    ///     pawn.genes.iconDef = xenogerm.iconDef;
    ///     foreach (GeneDef item in xenogerm.GeneSet.GenesListForReading)
    ///         pawn.genes.AddGene(item, xenogene: true);
    ///
    /// The xenotype is set to BASELINER unconditionally. Nothing is matched against
    /// any XenotypeDef; all that survives is a free-text name the player typed and
    /// an icon. A carved pawn therefore has every gene of a Gold and, as far as
    /// Pawn.genes.Xenotype is concerned, is nobody at all.
    ///
    /// WHAT THAT BROKE
    ///
    /// Every caste check in this mod read genes.Xenotype directly, so a carved Gold
    /// had no rung on the ladder, could not bear a razor, and could not hold a
    /// Society title. The one thing the setting is actually about - a lowColor
    /// carved into a Gold and passing - was the one case the mod handled worst.
    ///
    /// HOW IT IS RESOLVED NOW
    ///
    /// Birth first, then genes. If the pawn's XenotypeDef is one of ours they are
    /// that Color and nothing else matters. Otherwise we ask which Color's gene set
    /// the pawn actually carries, which is exactly the question a Society official
    /// with a gene scanner would ask - and exactly the question the Carvers exist to
    /// produce a particular answer to.
    /// </summary>
    public static class RR_CasteIdentity
    {
        // Built once: every Color we own, paired with the genes that define it,
        // ordered most-specific first so a sub-strain wins over its parent.
        private static List<KeyValuePair<XenotypeDef, HashSet<GeneDef>>> colorGenes;

        private static void EnsureBuilt()
        {
            if (colorGenes != null) { return; }

            colorGenes = new List<KeyValuePair<XenotypeDef, HashSet<GeneDef>>>();
            foreach (XenotypeDef x in DefDatabase<XenotypeDef>.AllDefs)
            {
                if (!IsColor(x) || x.genes == null || x.genes.Count == 0) { continue; }
                colorGenes.Add(new KeyValuePair<XenotypeDef, HashSet<GeneDef>>(
                    x, new HashSet<GeneDef>(x.genes)));
            }

            // Most genes first. A carved Lurcher carries everything a Gray does plus
            // more, so without this ordering the broader parent Color would match
            // first and the sub-strain would never be seen.
            colorGenes.Sort((a, b) => b.Value.Count.CompareTo(a.Value.Count));
        }

        /// <summary>A Color is one of ours, keyed on the defName prefix.</summary>
        public static bool IsColor(XenotypeDef x)
        {
            return x != null && x.defName != null && x.defName.StartsWith("RR_");
        }

        /// <summary>
        /// The Color this pawn reads as, or null if they are outside the hierarchy
        /// entirely - a baseliner, a vanilla xenotype, or somebody else's mod.
        /// </summary>
        public static XenotypeDef ColorOf(Pawn pawn)
        {
            if (pawn?.genes == null) { return null; }

            // Born to it. The overwhelmingly common case, and cheap.
            XenotypeDef born = pawn.genes.Xenotype;
            if (IsColor(born)) { return born; }

            // Carved, or otherwise assembled. Only baseliners can be - anyone with a
            // real xenotype that is not ours belongs to another mod and is left
            // alone rather than being sorted onto a ladder they never heard of.
            if (born != null && born != XenotypeDefOf.Baseliner) { return null; }

            return ColorFromGenes(pawn);
        }

        /// <summary>
        /// Which Color's gene set this pawn fully carries. Containment rather than
        /// equality, because a carved pawn may also keep endogenes from the Color
        /// they were born - a carved Red still has a Red's history in them, which is
        /// the entire tragedy of the thing and is not a reason to fail the match.
        /// </summary>
        private static XenotypeDef ColorFromGenes(Pawn pawn)
        {
            EnsureBuilt();

            List<Gene> held = pawn.genes.GenesListForReading;
            if (held == null || held.Count == 0) { return null; }

            HashSet<GeneDef> have = new HashSet<GeneDef>();
            for (int i = 0; i < held.Count; i++)
            {
                if (held[i]?.def != null) { have.Add(held[i].def); }
            }

            for (int i = 0; i < colorGenes.Count; i++)
            {
                if (have.IsSupersetOf(colorGenes[i].Value)) { return colorGenes[i].Key; }
            }
            return null;
        }

        /// <summary>
        /// Whether this pawn passes as Gold - by birth or by carving.
        ///
        /// Bronzies count. They are Gold by birth and by law, and the Compact admits
        /// them. A carved Gold counts too, which is the point: the razor lock and
        /// the Society's titles are enforced by people looking at somebody, and a
        /// good Carver's work is meant to survive being looked at.
        /// </summary>
        public static bool IsRulingCaste(Pawn pawn)
        {
            XenotypeDef c = ColorOf(pawn);
            if (c == null) { return false; }
            return c == RR_DefOf.RR_Gold || c == RR_DefOf.RR_Bronzie;
        }

        /// <summary>True only when both pawns read as Colors, and as different ones.</summary>
        public static bool AreDifferentColors(Pawn a, Pawn b)
        {
            XenotypeDef ca = ColorOf(a);
            XenotypeDef cb = ColorOf(b);
            if (ca == null || cb == null) { return false; }
            return ca != cb;
        }
    }
}
