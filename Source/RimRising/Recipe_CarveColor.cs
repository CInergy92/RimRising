using System.Collections.Generic;
using RimWorld;
using Verse;

namespace RimRising
{
    /// <summary>
    /// Which Color a carving recipe produces. One recipe per Color, each carrying
    /// this, so the worker is written once.
    /// </summary>
    public class CarveTargetExtension : DefModExtension
    {
        public XenotypeDef color;
    }

    /// <summary>
    /// The Carver's work: rebuilding somebody into another Color on an operating
    /// table, rather than assembling a xenogerm for them first.
    ///
    /// WHY THIS EXISTS ALONGSIDE THE VANILLA ROUTE
    ///
    /// Vanilla xenogerm assembly already permits carving and is left completely
    /// intact. But measured against the actual defs it is a megaproject: Gold is
    /// complexity 49, gene processors give +2 each on a base of 6, so twenty-two of
    /// them - and the archite genes cannot be extracted from a captured Gold at all,
    /// because Building_GeneExtractor scores biostatArc > 0 at weight zero. They
    /// have to be bought.
    ///
    /// That is a fine end-game goal and a poor story beat. In the reference a
    /// carving is a thing that happens to a person in a room, over months, at
    /// enormous expense - not a thing a colony industrialises. This recipe is that
    /// version, and the setting lets a player switch it off and keep only the
    /// megaproject.
    ///
    /// THE PAWN IS LEFT AS BASELINER, DELIBERATELY
    ///
    /// Genes are added as XENOGENES and Pawn.genes.Xenotype is not changed, exactly
    /// as GeneUtility.ImplantXenogermItem does it. Two reasons, and the second is
    /// the important one:
    ///
    ///   - it keeps this path behaviourally identical to the vanilla one, so
    ///     RR_CasteIdentity resolves both the same way
    ///   - xenogenes are NOT INHERITED. A carved pawn's children are born the Color
    ///     their parent was born, not the Color their parent was made. That is the
    ///     cruellest fact in the setting and it falls straight out of the mechanic.
    ///
    /// Only xenotypeName is set, so the UI reads the new Color while the pawn's
    /// biology quietly remembers otherwise.
    /// </summary>
    public class Recipe_CarveColor : Recipe_Surgery
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
            if (!ModsConfig.BiotechActive) { return false; }

            // The opt-out. A player who wants carving to remain the gene assembler
            // megaproject turns this off and the surgeries disappear from the list.
            if (RimRisingMod.Settings == null || !RimRisingMod.Settings.allowCarverSurgery)
            {
                return false;
            }

            XenotypeDef target = TargetColor;
            if (target == null) { return false; }

            Pawn pawn = thing as Pawn;
            if (pawn?.genes == null) { return false; }

            // No point carving somebody into what they already read as.
            return RR_CasteIdentity.ColorOf(pawn) != target;
        }

        public override void ApplyOnPawn(Pawn pawn, BodyPartRecord part, Pawn billDoer,
                                         List<Thing> ingredients, Bill bill)
        {
            if (!ModLister.CheckBiotech("Color carving")) { return; }
            if (CheckSurgeryFail(billDoer, pawn, ingredients, part, bill)) { return; }

            XenotypeDef target = TargetColor;
            if (target == null || pawn.genes == null) { return; }

            XenotypeDef wasBorn = RR_CasteIdentity.ColorOf(pawn);

            // Clear any previous carving before laying down the new one, or a pawn
            // carved twice would carry both gene sets and resolve to whichever was
            // more specific rather than to the most recent work.
            pawn.genes.ClearXenogenes();

            foreach (GeneDef g in target.genes)
            {
                pawn.genes.AddGene(g, xenogene: true);
            }

            // What the paperwork says. The xenotype itself stays Baseliner - see
            // the class comment on why that matters for inheritance.
            pawn.genes.xenotypeName = target.LabelCap;

            Messages.Message(
                "RR_CarvingComplete".Translate(
                    pawn.Named("PAWN"),
                    target.LabelCap.Named("COLOR")),
                pawn, MessageTypeDefOf.PositiveEvent, historical: false);

            // Let ideoligions have an opinion. Guarded the same way every other
            // event in this mod is, because surgeries can complete during states
            // where there is no player faction to notify.
            if (RR_CasteUtility.CanRaiseHistoryEvent())
            {
                HistoryEventDef ev = RR_CarveDefOf.RR_ColorCarved;
                if (ev != null)
                {
                    Find.HistoryEventsManager.RecordEvent(
                        new HistoryEvent(ev, pawn.Named(HistoryEventArgsNames.Doer)));
                }
            }

            if (wasBorn != null && wasBorn != target)
            {
                Log.Message(string.Format(
                    "[RimRising] {0} carved from {1} to {2}.",
                    pawn.LabelShort, wasBorn.defName, target.defName));
            }
        }
    }

    [DefOf]
    public static class RR_CarveDefOf
    {
        public static HistoryEventDef RR_ColorCarved;

        static RR_CarveDefOf()
        {
            DefOfHelper.EnsureInitializedInCtor(typeof(RR_CarveDefOf));
        }
    }
}
