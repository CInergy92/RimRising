using System.Collections.Generic;
using RimWorld;
using UnityEngine;
using Verse;

namespace RimRising
{
    /// <summary>
    /// What makes one campaign raid different from the next, set on its IncidentDef
    /// (Defs/IncidentDefs/Incidents_Campaign.xml) so the numbers are tuned in XML.
    /// </summary>
    public class CampaignRaidExtension : DefModExtension
    {
        /// <summary>Times the storyteller's own threat points for the colony right now.</summary>
        public float pointsFactor = 1f;
        /// <summary>Forced arrival mode; null leaves it to the usual weighted pick.</summary>
        public PawnsArrivalModeDef arrivalMode;
        /// <summary>A pawn group only the Society carries; null means its Combat group.</summary>
        public PawnGroupKindDef groupKind;
        /// <summary>Keyed letter text; a second key is used when the quota was missed.</summary>
        public string textKey, textKeyQuotaMissed;
    }

    /// <summary>
    /// A raid the campaign sends (GameComponent_Campaign): always the Society, at a
    /// strength the act calls for, arriving the way the act calls for.
    ///
    /// Built on IncidentWorker_RaidEnemy the same way IncidentWorker_LurcherHunt is.
    /// Decompiled on 1.7.5005: TryResolveRaidFaction keeps a preset parms.faction when
    /// it is HOSTILE, ResolveRaidPoints only fills points that are not set, and
    /// TryResolveRaidArriveMode returns at once when raidArrivalMode is preset.
    ///
    /// Only the director fires these. baseChance is 0 and CanFireNowSub refuses
    /// anything that is not forced, so the storyteller and other mods' incident
    /// pickers cannot send an Iron Rain into somebody's sandbox.
    /// </summary>
    public class IncidentWorker_CampaignRaid : IncidentWorker_RaidEnemy
    {
        private CampaignRaidExtension Ext => def.GetModExtension<CampaignRaidExtension>();

        protected override bool CanFireNowSub(IncidentParms parms)
        {
            return parms.forced && base.CanFireNowSub(parms);
        }

        protected override bool TryExecuteWorker(IncidentParms parms)
        {
            CampaignRaidExtension ext = Ext;
            Faction society = GameComponent_Campaign.Society;
            if (society != null)
            {
                // The reprisal is where the Society stops being a neighbour. Goodwill
                // first, because a faction that tracks goodwill ignores a bare
                // SetRelationDirect (CLAUDE.md, rrtestmode=raid).
                if (!society.HostileTo(Faction.OfPlayer))
                {
                    society.TryAffectGoodwillWith(Faction.OfPlayer, -200, canSendMessage: false, canSendHostilityLetter: false);
                }
                if (!society.HostileTo(Faction.OfPlayer))
                {
                    society.SetRelationDirect(Faction.OfPlayer, FactionRelationKind.Hostile, canSendHostilityLetter: false);
                }
                parms.faction = society;
                if (ext?.groupKind != null) { parms.pawnGroupKind = ext.groupKind; }
            }
            // No Society in this world (the player removed it): an ordinary raid from
            // whoever is hostile stands in, rather than the story stopping dead.

            parms.raidStrategy = RaidStrategyDefOf.ImmediateAttack;
            if (ext?.arrivalMode != null) { parms.raidArrivalMode = ext.arrivalMode; }

            float points = StorytellerUtility.DefaultThreatPointsNow(parms.target) * (ext?.pointsFactor ?? 1f);
            if (parms.faction != null)
            {
                // Never below what the group needs to field anyone at all, or the raid
                // fails to generate and the act never starts.
                points = Mathf.Max(points, parms.faction.def.MinPointsToGeneratePawnGroup(parms.pawnGroupKind ?? PawnGroupKindDefOf.Combat) * 1.05f);
            }
            parms.points = points;
            return base.TryExecuteWorker(parms);
        }

        protected override string GetLetterLabel(IncidentParms parms) => def.letterLabel;

        protected override string GetLetterText(IncidentParms parms, List<Pawn> pawns)
        {
            CampaignRaidExtension ext = Ext;
            GameComponent_Campaign director = RR_Campaign.Director;
            string key = ext?.textKey;
            if (ext?.textKeyQuotaMissed != null && director != null && !director.quotaMet) { key = ext.textKeyQuotaMissed; }
            string own = key != null ? (string)key.Translate() : def.letterText;
            return own + "\n\n" + base.GetLetterText(parms, pawns);
        }
    }
}
