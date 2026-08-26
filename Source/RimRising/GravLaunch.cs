using System.Collections.Generic;
using RimWorld;
using RimWorld.Planet;
using UnityEngine;
using Verse;
using Verse.Sound;

namespace RimRising
{
    /// <summary>
    /// Lets a pawn wearing gravBoots launch themselves to another world tile, the
    /// way a transport pod does.
    ///
    /// WHY THIS IS HAND-ROLLED. In the books gravBoots are how a Gold gets from one
    /// place to another, so the boots needed an actual launch rather than only a
    /// caravan speed bonus - and there is no vanilla equivalent. CompLaunchable
    /// cannot be reused: TryLaunch is welded to CompTransporter groups, a fuel port
    /// and a spawned building, and even its public static ChoseWorldTarget still
    /// demands a CompLaunchable instance. So the targeting flow is reimplemented
    /// here, mirroring CompLaunchable.StartChoosingDestination argument for
    /// argument, and the flight itself is built from the same primitives vanilla
    /// uses: an ActiveTransporter holding the pawn, a FlyShipLeaving skyfaller, and
    /// the TravellingTransporters world object.
    ///
    /// DELIBERATELY NARROWER THAN A DROP POD. Arrival always forms a caravan on the
    /// destination tile. Landing directly onto a settlement or site is not offered,
    /// because those options come from CompLaunchable.GetOptionsForTile, which needs
    /// a list of IThingHolder pods to inspect - and the only holder that exists here
    /// is the one built at the moment of launch, which is too late to answer the
    /// question. Arriving beside a settlement and entering it normally is a small
    /// price for not inventing a second arrival path that nothing else in the game
    /// exercises.
    /// </summary>
    public class CompProperties_GravLaunch : CompProperties
    {
        /// <summary>Maximum world tiles per launch.</summary>
        public int maxLaunchDistance = 25;

        /// <summary>Ticks before the boots can launch again. 60000 is one day.</summary>
        public int cooldownTicks = 60000;

        public SoundDef soundLaunch;

        public CompProperties_GravLaunch()
        {
            compClass = typeof(CompGravLaunch);
        }
    }

    public class CompGravLaunch : ThingComp
    {
        private int lastLaunchTick = -99999;

        public CompProperties_GravLaunch Props => (CompProperties_GravLaunch)props;

        private Pawn Wearer => (parent as Apparel)?.Wearer;

        private int TicksRemaining =>
            Mathf.Max(0, (lastLaunchTick + Props.cooldownTicks) - Find.TickManager.TicksGame);

        public override void PostExposeData()
        {
            base.PostExposeData();
            Scribe_Values.Look(ref lastLaunchTick, "RR_lastLaunchTick", -99999);
        }

        public override IEnumerable<Gizmo> CompGetWornGizmosExtra()
        {
            foreach (Gizmo g in base.CompGetWornGizmosExtra()) { yield return g; }

            Pawn pawn = Wearer;
            if (pawn == null || !pawn.Spawned) { yield break; }
            // Only the player's own pawns get the button; a raider in gravBoots is
            // not something the player should be able to fly across the planet.
            if (pawn.Faction != Faction.OfPlayer || pawn.IsQuestLodger()) { yield break; }

            Command_Action cmd = new Command_Action
            {
                defaultLabel = "RR_GravLaunch".Translate(),
                defaultDesc = "RR_GravLaunchDesc".Translate(Props.maxLaunchDistance),
                icon = CompLaunchable.LaunchCommandTex,
                action = StartChoosingDestination
            };

            if (TicksRemaining > 0)
            {
                cmd.Disable("RR_GravLaunchCooldown".Translate(TicksRemaining.ToStringTicksToPeriod()));
            }
            else if (pawn.Downed)
            {
                cmd.Disable("RR_GravLaunchDowned".Translate());
            }

            yield return cmd;
        }

        /// <summary>
        /// Argument-for-argument the same targeting call CompLaunchable makes, so
        /// the world UI behaves exactly as it does for a transport pod.
        /// </summary>
        private void StartChoosingDestination()
        {
            Pawn pawn = Wearer;
            if (pawn?.Map == null) { return; }
            PlanetTile origin = pawn.Map.Tile;

            CameraJumper.TryJump(CameraJumper.GetWorldTarget(new GlobalTargetInfo(origin)));
            Find.WorldSelector.ClearSelection();

            Find.WorldTargeter.BeginTargeting(
                ChoseWorldTarget,
                canTargetTiles: true,
                CompLaunchable.TargeterMouseAttachment,
                closeWorldTabWhenFinished: true,
                delegate
                {
                    GenDraw.DrawWorldRadiusRing(origin, Props.maxLaunchDistance,
                        CompPilotConsole.GetThrusterRadiusMat(origin));
                },
                TargetingLabel,
                null,
                origin,
                showCancelButton: true);
        }

        private TaggedString TargetingLabel(GlobalTargetInfo target)
        {
            if (!target.IsValid) { return null; }
            Pawn pawn = Wearer;
            if (pawn?.Map == null) { return null; }

            int dist = Find.WorldGrid.TraversalDistanceBetween(
                pawn.Map.Tile, target.Tile, passImpassable: true, Props.maxLaunchDistance, canTraverseLayers: true);
            if (dist > Props.maxLaunchDistance)
            {
                // No GUI.color here: GUI lives in UnityEngine.IMGUIModule, which
                // this assembly does not reference, and colouring one label red is
                // not worth taking a second Unity dependency for.
                return "TransportPodDestinationBeyondMaximumRange".Translate();
            }
            return null;
        }

        private bool ChoseWorldTarget(GlobalTargetInfo target)
        {
            Pawn pawn = Wearer;
            if (pawn?.Map == null) { return true; }

            if (!target.IsValid)
            {
                Messages.Message("MessageTransportPodsDestinationIsInvalid".Translate(),
                    MessageTypeDefOf.RejectInput, historical: false);
                return false;
            }

            int dist = Find.WorldGrid.TraversalDistanceBetween(
                pawn.Map.Tile, target.Tile, passImpassable: true, int.MaxValue, canTraverseLayers: true);
            if (dist > Props.maxLaunchDistance)
            {
                Messages.Message("TransportPodDestinationBeyondMaximumRange".Translate(),
                    MessageTypeDefOf.RejectInput, historical: false);
                return false;
            }

            if (Find.World.Impassable(target.Tile))
            {
                Messages.Message("MessageTransportPodsDestinationIsInvalid".Translate(),
                    MessageTypeDefOf.RejectInput, historical: false);
                return false;
            }

            TryLaunch(target.Tile);
            return true;
        }

        private void TryLaunch(PlanetTile destinationTile)
        {
            Pawn pawn = Wearer;
            if (pawn == null || !pawn.Spawned) { return; }

            Map map = pawn.Map;
            IntVec3 pos = pawn.Position;

            // ORDER MATTERS HERE. ThingOwner.TryAdd does NOT despawn what it is
            // given - decompiling it shows it only refuses things that already have
            // a holdingOwner - so a still-spawned pawn dropped into the container
            // would end up half on the map and half in a pod. Stop the job, drop
            // the selection, despawn, and only then hand the pawn over.
            pawn.jobs?.StopAll();
            Find.Selector?.Deselect(pawn);
            pawn.DeSpawn(DestroyMode.Vanish);

            ActiveTransporterInfo contents = new ActiveTransporterInfo();
            if (!contents.innerContainer.TryAdd(pawn, canMergeWithExistingStacks: false))
            {
                // Put them back rather than lose them. This should not happen, but
                // the failure mode if it does is a pawn deleted from the game.
                GenSpawn.Spawn(pawn, pos, map);
                Log.Error("[RimRising] gravBoot launch could not containerise " + pawn.LabelShort + "; aborted and respawned.");
                return;
            }

            ActiveTransporter transporter = (ActiveTransporter)ThingMaker.MakeThing(ThingDefOf.ActiveDropPod);
            transporter.Contents = contents;

            FlyShipLeaving leaving = (FlyShipLeaving)SkyfallerMaker.MakeSkyfaller(
                ThingDefOf.DropPodLeaving, transporter);
            leaving.groupID = Find.UniqueIDsManager.GetNextTransporterGroupID();
            leaving.destinationTile = destinationTile;
            leaving.arrivalAction = new TransportersArrivalAction_FormCaravan("MessageTransportPodsArrived");
            leaving.worldObjectDef = WorldObjectDefOf.TravellingTransporters;

            GenSpawn.Spawn(leaving, pos, map);

            Props.soundLaunch?.PlayOneShot(new TargetInfo(pos, map));
            lastLaunchTick = Find.TickManager.TicksGame;
            CameraJumper.TryHideWorld();
        }
    }
}
