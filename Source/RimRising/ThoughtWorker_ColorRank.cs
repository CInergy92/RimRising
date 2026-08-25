using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// The graded hierarchy: how a pawn feels about another pawn purely because of
    /// where their two Colors sit on the ladder.
    ///
    /// WHY THIS NEEDS C#
    ///
    /// Vanilla's PreferredXenotype precept is a flat three-way switch - liked,
    /// disliked, neutral - and caps at three preferred xenotypes. The setting's whole
    /// point is that the ladder is GRADED: a Silver looks down on a Red and up at a
    /// Gold, and the size of both feelings depends on the distance. No vanilla
    /// precept expresses a relation whose sign and magnitude come from a pair of
    /// ranks, so the thought stage has to be chosen in code.
    ///
    /// ThoughtWorker_Precept_Social is a plain abstract with one method to
    /// implement, so no Harmony is involved - same as RoleRequirement and
    /// BiomeWorker elsewhere in this mod.
    ///
    /// WHERE THE RANK COMES FROM
    ///
    /// XenotypeDef.displayPriority, which already encodes the canonical order in
    /// Defs/GeneDefs/XenotypeDefs_Colors.xml: Gold 10, Silver 20, White 30 and so on
    /// down to Red 140, with sub-strains sitting beside their parent (Lurcher 105
    /// next to Gray 100, Bronzie 15 next to Gold 10).
    ///
    /// Reading the ladder off that field rather than hardcoding a list here means
    /// the two can never drift apart. Reorder the Colors in XML and this follows.
    /// Ten points of displayPriority is one rung.
    /// </summary>
    public class ThoughtWorker_ColorRank : ThoughtWorker_Precept_Social
    {
        // displayPriority points per rung of the ladder.
        private const float PointsPerRung = 10f;

        // How far apart two Colors have to be, in rungs, to move up a magnitude
        // band. Distance only - the direction is applied separately below.
        private const float NearBand = 0.75f;   // below this, the same Color
        private const float FarBand  = 3.5f;
        private const float VeryFar  = 7.5f;

        // Stage indices in Precepts_ColorDeference.xml, which the worker indexes:
        //
        //   0 far beneath   1 well beneath   2 beneath
        //   3 of my own Color
        //   4 above         5 well above     6 far above
        //
        private const int SameColorStage = 3;

        /// <summary>
        /// Chooses the thought stage from the distance between two Colors.
        ///
        /// SYMMETRY IS STRUCTURAL HERE, and that is the point. The obvious
        /// implementation - a list of signed edges walked with >= - was written
        /// first and was wrong twice: adjacent Colors sit exactly one rung apart
        /// and sub-strains exactly half a rung, so real pairs kept landing ON an
        /// edge. Because every comparison was >=, one direction fell into a
        /// different band from the other, and Gray-looks-down-on-Red did not match
        /// Red-looks-up-at-Gray.
        ///
        /// Nudging the edges off the integers fixed the base Colors and moved the
        /// same fault onto the sub-strains. So the magnitude is bucketed from the
        /// ABSOLUTE distance and the sign applied afterwards, which makes
        /// stage(a,b) + stage(b,a) == 6 an identity rather than something that has
        /// to be re-checked whenever a Color is added or the ladder reordered.
        /// </summary>
        protected override ThoughtState ShouldHaveThought(Pawn p, Pawn otherPawn)
        {
            // Not about oneself, and not about anything that cannot hold a Color.
            if (p == otherPawn) { return ThoughtState.Inactive; }

            float? mine  = RankOf(p);
            float? theirs = RankOf(otherPawn);
            if (!mine.HasValue || !theirs.HasValue) { return ThoughtState.Inactive; }

            // Positive gap means the other pawn sits BELOW the observer, because
            // displayPriority counts downward from Gold.
            float gap = theirs.Value - mine.Value;
            float distance = gap < 0f ? -gap : gap;

            int band;
            if (distance < NearBand)     { band = 0; }
            else if (distance < FarBand) { band = 1; }
            else if (distance < VeryFar) { band = 2; }
            else                         { band = 3; }

            int stage = band == 0
                ? SameColorStage
                : (gap > 0f
                    ? SameColorStage - band    // they are beneath: 2, 1, 0
                    : SameColorStage + band);  // they are above:   4, 5, 6

            // The stage index is only meaningful against the def that declares
            // them. If the XML is ever edited to have fewer stages than this
            // returns, RimWorld throws on every social tick rather than telling
            // anyone which def is short - so clamp instead, and degrade to the
            // nearest real stage.
            int last = def?.stages?.Count - 1 ?? SameColorStage;
            if (stage > last) { stage = last; }
            if (stage < 0)    { stage = 0; }

            return ThoughtState.ActiveAtStage(stage);
        }

        /// <summary>
        /// A pawn's rung, or null if they are not one of our Colors at all.
        ///
        /// Baseliners, vanilla xenotypes and anything from another mod deliberately
        /// return null rather than being slotted in somewhere: the hierarchy has an
        /// opinion about Colors, and a person outside it has no rung to compare
        /// against. Giving them a default position would quietly rank every pawn in
        /// the game on a Society ladder they have never heard of.
        /// </summary>
        private static float? RankOf(Pawn pawn)
        {
            // Reads as, not born as. A carved Gold has a Gold's rung, which is the
            // whole reason anyone submits to the surgery - see RR_CasteIdentity.
            XenotypeDef xeno = RR_CasteIdentity.ColorOf(pawn);
            if (xeno == null) { return null; }

            return xeno.displayPriority / PointsPerRung;
        }
    }

    /// <summary>
    /// The same ladder, read by an egalitarian ideoligion instead.
    ///
    /// Rather than being the absence of the hierarchy thought, this is its mirror:
    /// believers are actively pleased by company from far across the ladder and
    /// unmoved by rank. It gives RR_ColorEquality something to DO in daily play
    /// rather than only a goodwill modifier at the faction level.
    /// </summary>
    public class ThoughtWorker_ColorRank_Equality : ThoughtWorker_Precept_Social
    {
        protected override ThoughtState ShouldHaveThought(Pawn p, Pawn otherPawn)
        {
            if (p == otherPawn) { return ThoughtState.Inactive; }

            float? mine   = RankOfPublic(p);
            float? theirs = RankOfPublic(otherPawn);
            if (!mine.HasValue || !theirs.HasValue) { return ThoughtState.Inactive; }

            float gap = theirs.Value - mine.Value;
            if (gap < 0f) { gap = -gap; }

            // Only the crossing itself is remarkable. Two Reds sharing a bunkroom
            // are not making a point about anything.
            if (gap < 1f)  { return ThoughtState.Inactive; }
            if (gap < 5f)  { return ThoughtState.ActiveAtStage(0); }
            return ThoughtState.ActiveAtStage(1);
        }

        private static float? RankOfPublic(Pawn pawn)
        {
            XenotypeDef xeno = RR_CasteIdentity.ColorOf(pawn);
            if (xeno == null) { return null; }
            return xeno.displayPriority / 10f;
        }
    }
}
