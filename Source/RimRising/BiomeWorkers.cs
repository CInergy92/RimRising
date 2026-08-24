using RimWorld;
using RimWorld.Planet;

namespace RimRising
{
    /// <summary>
    /// Biome placement for RimRising's two engineered landscapes.
    ///
    /// WHY C#
    ///
    /// A BiomeDef cannot say where it belongs. Placement lives entirely in a
    /// BiomeWorker, whose GetScore is run for every biome on every tile with the
    /// highest score taking it. Reusing a vanilla worker would make our biome
    /// compete with the vanilla one on identical criteria, and one of the two
    /// would simply never appear.
    ///
    /// SCORING, AND WHY THESE NUMBERS
    ///
    /// Vanilla's arid shrubland scores 22.5 at 20 degrees and 600mm rainfall, then
    /// adjusts by 2.2 per degree and 0.01 per mm. Both workers here are pitched to
    /// sit slightly BELOW the vanilla biome they overlap with, so they surface on
    /// tiles vanilla is lukewarm about rather than carpeting the planet. A total
    /// conversion should colour the world, not repaint it.
    /// </summary>
    public class BiomeWorker_RR_TerraformedSteppe : BiomeWorker
    {
        public override float GetScore(BiomeDef biome, Tile tile, PlanetTile planetTile)
        {
            if (tile.WaterCovered) { return -100f; }

            // Terraforming is expensive and nobody bothers with the extremes. The
            // Society's engineered farmland sits in the band that pays back.
            if (tile.temperature < 2f || tile.temperature > 24f) { return 0f; }
            if (tile.rainfall < 700f || tile.rainfall >= 1800f) { return 0f; }

            // Flat ground only - this is farmland cut to a plan, not terrain that
            // happened. Mountainous tiles belong to the mines instead.
            if (tile.hilliness == Hilliness.Mountainous || tile.hilliness == Hilliness.Impassable)
            {
                return 0f;
            }

            // Peaks around 13 degrees and 1200mm, and stays just under vanilla
            // temperate forest so it fills gaps rather than replacing it.
            float score = 19.5f
                        - System.Math.Abs(tile.temperature - 13f) * 0.9f
                        - System.Math.Abs(tile.rainfall - 1200f) / 220f;

            if (tile.hilliness == Hilliness.Flat) { score += 1.5f; }

            return score;
        }
    }

    /// <summary>
    /// The helium-3 barrens: the mining country the lowColors were bred for.
    /// Hot, dry, broken ground, and worth nothing on the surface.
    /// </summary>
    public class BiomeWorker_RR_HeliumBarrens : BiomeWorker
    {
        public override float GetScore(BiomeDef biome, Tile tile, PlanetTile planetTile)
        {
            if (tile.WaterCovered) { return -100f; }

            if (tile.temperature < 4f) { return 0f; }
            if (tile.rainfall >= 700f) { return 0f; }

            // The whole point is what is underneath, so broken ground is required.
            // Flat desert is just desert.
            if (tile.hilliness == Hilliness.Flat) { return 0f; }

            float score = 20.5f
                        + (tile.temperature - 22f) * 1.4f
                        - tile.rainfall / 130f;

            // Mountainous ground scores best: that is where the shafts go.
            if (tile.hilliness == Hilliness.Mountainous) { score += 3f; }
            else if (tile.hilliness == Hilliness.LargeHills) { score += 1.5f; }

            return score;
        }
    }
}
