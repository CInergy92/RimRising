using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// The razor's whip form as a MELEE STROKE at reach, not a shot.
    ///
    /// WHY NOT A PROJECTILE. It used to be CompProperties_AbilityLaunchProjectile
    /// firing a Bullet, and a bullet resolves like a shot: blocked by whatever is
    /// between the pawns, indifferent to everything the wielder is good at (melee
    /// skill, MeleeDamageFactor, the razor's quality) and impossible to dodge. A
    /// Gold with Melee 19 and a Gold with Melee 3 lashed identically. Under CE its
    /// 0.75 also read as 0.75 mm, which a flak vest stops.
    ///
    /// So the lash rolls the way Verb_MeleeAttack.TryCastShot does - the wielder's
    /// MeleeHitChance, then the victim's MeleeDodgeChance - and scales damage by
    /// the wielder's MeleeDamageFactor and the razor's MeleeWeapon_DamageMultiplier
    /// (quality). The DamageInfo is CE-agnostic: CE reads ArmorPenetrationInt as
    /// millimetres, so the CE folder patches armorPenetration on this comp to CE
    /// units, as it does every other armour number.
    ///
    /// The four switches the review left to the user are plain fields, so each is
    /// a one-line XML change: sweepAll, ignoreDodge, staggerTicks and (on the
    /// AbilityDef) the cooldown.
    /// </summary>
    public class CompProperties_AbilityRazorLash : CompProperties_AbilityEffect
    {
        public float damage = 19f;
        public float armorPenetration = 0.75f;
        public DamageDef damageDef;
        // Hit every pawn on the line rather than stopping at the first.
        public bool sweepAll = false;
        // "It cannot simply be parried." Strong mechanically, so off by default.
        public bool ignoreDodge = false;
        public int staggerTicks = 45;
        public FleckDef lineFleck;
        public float lineWidth = 0.6f;

        public CompProperties_AbilityRazorLash()
        {
            compClass = typeof(CompAbilityEffect_RazorLash);
        }
    }

    public class CompAbilityEffect_RazorLash : CompAbilityEffect
    {
        // Vanilla melee grants 200 XP per second of a verb's cycle; the lash is a
        // single committed stroke of roughly the razor's own 1.4 s.
        private const float MeleeXp = 280f;

        public new CompProperties_AbilityRazorLash Props => (CompProperties_AbilityRazorLash)props;

        public override void Apply(LocalTargetInfo target, LocalTargetInfo dest)
        {
            base.Apply(target, dest);
            Pawn caster = parent.pawn;
            Map map = caster?.Map;
            if (map == null || !target.IsValid) { return; }

            ThingWithComps razor = caster.equipment?.Primary;
            Vector3 end = target.CenterVector3;

            foreach (IntVec3 cell in GenSight.PointsOnLineOfSight(caster.Position, target.Cell))
            {
                if (!cell.InBounds(map)) { break; }
                Pawn victim = cell.GetFirstPawn(map);
                if (victim == null || victim == caster) { continue; }
                Lash(caster, razor, victim, map);
                if (!Props.sweepAll)
                {
                    end = victim.DrawPos;
                    break;
                }
            }

            if (Props.lineFleck != null)
            {
                FleckMaker.ConnectingLine(caster.DrawPos, end, Props.lineFleck, map, Props.lineWidth);
            }
            if (caster.skills != null)
            {
                caster.skills.Learn(SkillDefOf.Melee, MeleeXp);
            }
        }

        private void Lash(Pawn caster, ThingWithComps razor, Pawn victim, Map map)
        {
            if (!Rand.Chance(caster.GetStatValue(StatDefOf.MeleeHitChance))) { return; }

            if (!Props.ignoreDodge && !victim.Downed &&
                Rand.Chance(victim.GetStatValue(StatDefOf.MeleeDodgeChance)))
            {
                MoteMaker.ThrowText(victim.DrawPos, map, "TextMote_Dodge".Translate(), 1.9f);
                return;
            }

            float amount = Props.damage * caster.GetStatValue(StatDefOf.MeleeDamageFactor);
            QualityCategory quality = QualityCategory.Normal;
            if (razor != null)
            {
                amount *= razor.GetStatValue(StatDefOf.MeleeWeapon_DamageMultiplier);
                razor.TryGetQuality(out quality);
            }

            var dinfo = new DamageInfo(
                Props.damageDef ?? DamageDefOf.Cut, amount, Props.armorPenetration,
                (victim.Position - caster.Position).AngleFlat, caster,
                weapon: razor?.def, intendedTarget: victim, weaponQuality: quality);
            victim.TakeDamage(dinfo);

            if (Props.staggerTicks > 0 && !victim.Dead)
            {
                victim.stances?.stagger?.StaggerFor(Props.staggerTicks);
            }
        }

        public override bool Valid(LocalTargetInfo target, bool throwMessages = false)
        {
            return target.Pawn != null && base.Valid(target, throwMessages);
        }
    }
}
