using System.Collections.Generic;
using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// The automated medical package in pulse and recoil armour: a passive wound
    /// seal that runs the whole time the suit is worn, and a small number of
    /// combat stims the suit injects on its own when the wearer is in trouble.
    ///
    /// WHY C#. Nothing in vanilla grants a hediff from worn apparel.
    /// ApparelProperties has no such field - the full field list was checked, not
    /// remembered - and the only hediff-granting comps in the game are ability
    /// comps, which need somebody to press a button. The behaviour wanted here is
    /// specifically the one the player does NOT press.
    ///
    /// tickerType Normal IS REQUIRED on any def using this comp. Worn apparel is
    /// not ticked by Pawn_ApparelTracker; it is reached by Thing.DoTick recursing
    /// into child holders, and that recursion only calls Tick() when the def's
    /// tickerType is Normal. Without it this comp compiles, loads, attaches, and
    /// silently never runs - which is why the two defs that use it say so in a
    /// comment as well.
    /// </summary>
    public class CompProperties_TraumaSuite : CompProperties
    {
        /// <summary>Applied for as long as the suit is worn. Carries totalBleedFactor.</summary>
        public HediffDef sealHediff;

        /// <summary>Injected when the wearer is in trouble. One per dose.</summary>
        public HediffDef stimHediff;

        /// <summary>How many stims the suit carries at once.</summary>
        public int stimDoses = 2;

        /// <summary>Ticks to synthesise one replacement dose. 60000 is a day.</summary>
        public int doseRechargeTicks = 60000;

        /// <summary>
        /// Bleed rate, in the same units as HediffSet.BleedRateTotal, above which
        /// the suit decides this is a casualty rather than a scratch. Vanilla
        /// treats 0.1 as the point where a pawn is visibly losing blood.
        /// </summary>
        public float bleedTrigger = 0.35f;

        /// <summary>Pain fraction above which the suit stims regardless of bleeding.</summary>
        public float painTrigger = 0.45f;

        public CompProperties_TraumaSuite()
        {
            compClass = typeof(CompTraumaSuite);
        }
    }

    public class CompTraumaSuite : ThingComp
    {
        private const int CheckIntervalTicks = 60;

        private int dosesRemaining = -1;      // -1 means "not initialised yet"
        private int rechargeProgress;
        private int ticksToCheck;

        public CompProperties_TraumaSuite Props => (CompProperties_TraumaSuite)props;

        private Pawn Wearer => (parent as Apparel)?.Wearer;

        public override void PostPostMake()
        {
            base.PostPostMake();
            dosesRemaining = Props.stimDoses;
        }

        public override void PostExposeData()
        {
            base.PostExposeData();
            Scribe_Values.Look(ref dosesRemaining, "RR_traumaDoses", -1);
            Scribe_Values.Look(ref rechargeProgress, "RR_traumaRecharge", 0);
            // ticksToCheck is deliberately NOT scribed - but left at zero after a
            // load, every suit in the colony evaluated on the same tick and then
            // stayed in phase forever. A random phase spreads a squad's checks
            // across the interval.
            if (Scribe.mode == LoadSaveMode.PostLoadInit)
            {
                ticksToCheck = Rand.Range(1, CheckIntervalTicks);
            }
        }

        public override void Notify_Equipped(Pawn pawn)
        {
            base.Notify_Equipped(pawn);
            ApplySeal(pawn);
        }

        public override void Notify_Unequipped(Pawn pawn)
        {
            base.Notify_Unequipped(pawn);
            RemoveSeal(pawn);
        }

        public override void CompTick()
        {
            base.CompTick();

            // Apparel sitting in a stockpile has no wearer and nothing to do. The
            // recharge deliberately does not run either: a suit refills its stims
            // from the wearer's own supplies, and a crate of armour quietly
            // topping itself up would make doses free.
            Pawn pawn = Wearer;
            if (pawn == null) { return; }

            if (--ticksToCheck > 0) { return; }
            ticksToCheck = CheckIntervalTicks;

            if (dosesRemaining < 0) { dosesRemaining = Props.stimDoses; }

            // Reconcile rather than assume. Notify_Equipped covers wearing the
            // suit, but a pawn who was already wearing it when the save loaded
            // never fires that, and neither does a resurrection.
            if (Props.sealHediff != null && !pawn.Dead &&
                pawn.health?.hediffSet?.GetFirstHediffOfDef(Props.sealHediff) == null)
            {
                ApplySeal(pawn);
            }

            if (dosesRemaining < Props.stimDoses && Props.doseRechargeTicks > 0)
            {
                rechargeProgress += CheckIntervalTicks;
                if (rechargeProgress >= Props.doseRechargeTicks)
                {
                    rechargeProgress = 0;
                    dosesRemaining++;
                }
            }

            TryStim(pawn);
        }

        private void ApplySeal(Pawn pawn)
        {
            if (Props.sealHediff == null || pawn?.health == null || pawn.Dead) { return; }
            if (pawn.health.hediffSet.GetFirstHediffOfDef(Props.sealHediff) != null) { return; }
            pawn.health.AddHediff(Props.sealHediff);
        }

        private void RemoveSeal(Pawn pawn)
        {
            if (Props.sealHediff == null || pawn?.health == null) { return; }
            Hediff seal = pawn.health.hediffSet.GetFirstHediffOfDef(Props.sealHediff);
            if (seal != null) { pawn.health.RemoveHediff(seal); }
        }

        /// <summary>
        /// The suit's own decision to inject. Fires on blood loss or on pain, so a
        /// crushed limb that is not bleeding still counts as trouble.
        /// </summary>
        private void TryStim(Pawn pawn)
        {
            if (Props.stimHediff == null || dosesRemaining <= 0) { return; }
            if (pawn.Dead || pawn.health == null) { return; }

            // Never double-dose. Waiting for the previous stim to burn off is also
            // what stops a long fight draining the whole magazine in a minute.
            if (pawn.health.hediffSet.GetFirstHediffOfDef(Props.stimHediff) != null) { return; }

            bool hurt = pawn.health.hediffSet.BleedRateTotal >= Props.bleedTrigger
                     || pawn.health.hediffSet.PainTotal >= Props.painTrigger;
            if (!hurt) { return; }

            pawn.health.AddHediff(Props.stimHediff);
            dosesRemaining--;
            rechargeProgress = 0;

            // Told to the player only for their own pawns, and only for pawns on a
            // map. A raid full of stimming Golds would otherwise bury the message
            // log in events the player can do nothing about.
            if (pawn.Faction == Faction.OfPlayer && pawn.Spawned)
            {
                Messages.Message(
                    "RR_TraumaSuiteStim".Translate(pawn.LabelShort.Named("PAWN"),
                                                   parent.LabelShort.Named("ARMOR")),
                    pawn, MessageTypeDefOf.NeutralEvent, historical: false);
            }
        }

        public override string CompInspectStringExtra()
        {
            if (Props.stimHediff == null) { return null; }
            int doses = Mathf.Max(0, dosesRemaining < 0 ? Props.stimDoses : dosesRemaining);
            string line = "RR_TraumaSuiteDoses".Translate(doses, Props.stimDoses);

            if (doses < Props.stimDoses && Props.doseRechargeTicks > 0)
            {
                int left = Mathf.Max(0, Props.doseRechargeTicks - rechargeProgress);
                line += " (" + "RR_TraumaSuiteRecharging".Translate(left.ToStringTicksToPeriod()) + ")";
            }
            return line;
        }

        public override IEnumerable<StatDrawEntry> SpecialDisplayStats()
        {
            foreach (StatDrawEntry e in base.SpecialDisplayStats()) { yield return e; }

            if (Props.stimHediff != null)
            {
                yield return new StatDrawEntry(
                    StatCategoryDefOf.Apparel,
                    "RR_StatTraumaSuite".Translate(),
                    Props.stimDoses.ToString(),
                    "RR_StatTraumaSuiteDesc".Translate(
                        Props.doseRechargeTicks.ToStringTicksToPeriod()),
                    2500);
            }
        }
    }
}
