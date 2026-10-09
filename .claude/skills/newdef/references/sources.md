# Where to find a working example, by def type

Two columns matter. **Ours** is a file in this repo that has loaded clean and whose header
says what it was mirrored from; read it first. **Vanilla** is the path the project has cited
for that type, relative to `<install>\Data\`. A vanilla path marked *expected* has not been
cited in this repo yet; confirm it exists before trusting it, or use
`scripts/Find-VanillaDef.ps1`.

Cloud sessions have no vanilla on disk. The **GitHub** column names a public 1.6 mod whose
use of the type was mirrored; clone it per CLAUDE.md.

| Def type | Ours | Vanilla | GitHub stand-in |
|---|---|---|---|
| `XenotypeDef` | `GeneDefs/XenotypeDefs_Colors.xml` | `Biotech/Defs/GeneDefs/XenotypeDefs.xml` | `juanosarg/AlphaGenes` |
| `GeneDef` | `GeneDefs/GeneDefs_RimRising.xml` | `Biotech/Defs/GeneDefs/GeneDefs_Health.xml`, `GeneDefs_Misc.xml` | `juanosarg/AlphaGenes` |
| `PawnKindDef` (humanlike) | `PawnKindDefs/PawnKinds_RimRising.xml` | `Royalty/Defs/PawnKinds/PawnKinds_Empire.xml` | `Vanilla-Expanded/VanillaFactionsExpanded-Medieval2` |
| `PawnKindDef` (animal) | `ThingDefs_Races/Races_Animal_Pitviper.xml` | `Core/Defs/ThingDefs_Races/Races_Animal_*.xml` *(expected)* | `juanosarg/AlphaAnimals` |
| `ThingDef` animal race | same file | same *(expected)* | `juanosarg/AlphaAnimals` |
| `ThingDef` plant | `ThingDefs_Plants/Plants_RimRising.xml` | `Core/Defs/ThingDefs_Plants/Plants_Wild_Base.xml` *(expected)* | `Vanilla-Expanded/VanillaPlantsExpanded-MorePlants`, `juanosarg/AlphaBiomes` |
| `ThingDef` apparel | `ThingDefs_Misc/Apparel_RimRising.xml` | `Core/Defs/ThingDefs_Misc/Apparel_Various.xml` | - |
| `ThingDef` melee weapon | `ThingDefs_Misc/Weapons_RimRising.xml` | `Royalty/Defs/ThingDefs_Misc/Weapons/MeleeUltratech.xml` | - |
| `ThingDef` drug + chemical + hediffs | `ThingDefs_Items/Drugs_RimRising.xml` | `Core/Defs/ThingDefs_Items/Items_Drug.xml` *(expected)* | - |
| `ThingDef` resource item | `ThingDefs_Items/Items_Resource_RimRising.xml` | `Core/Defs/ThingDefs_Items/Items_Resource_Stuff.xml` *(expected)* | - |
| Implant (ThingDef + HediffDef + RecipeDef) | `HediffDefs/Implants_RimRising.xml` | `Core/Defs/HediffDefs/BodyParts/Hediffs_BodyParts_Bionic.xml` | - |
| `HediffDef` (non-implant) | `HediffDefs/Hediffs_ArmorMedical.xml` | `Core/Defs/HediffDefs/Hediffs_Global_Misc.xml` *(expected)* | `juanosarg/AlphaAnimals` |
| `RecipeDef` surgery | `Carving/Carving.xml`, `Carving/Restoration.xml` | `Biotech/Defs/RecipeDefs/Recipes_Surgery_Misc.xml` | - |
| `FactionDef` | `FactionDefs/Factions_RimRising.xml` | `Royalty/Defs/FactionDefs/Faction_Empire.xml`, `Core/Defs/FactionDefs/Factions_Misc.xml` | - |
| `MemeDef` | `PreceptDefs/Memes_RimRising.xml` | `Ideology/Defs/MemeDefs/Memes_GenderSupremacy.xml`, `Memes_GroupRelation.xml` | - |
| `PreceptDef` | `PreceptDefs/Precepts_*.xml` | `Ideology/Defs/PreceptDefs/Precepts_Weapons.xml`, `Precepts_Scarification.xml`, `Precepts_Role.xml` | - |
| Role precept + `RulePackDef` | `PreceptDefs/Roles_OlympicKnights.xml`, `RulePackDefs/RulePacks_Knights.xml` | `Ideology/Defs/RulePackDefs/RulePacks_Ideo_Role.xml` | - |
| `GoodwillSituationDef` | `Goodwill/GoodwillSituations_RimRising.xml` | `Ideology/Defs/Goodwill/GoodwillSituations_MemeCompatibility.xml` | - |
| `RoyalTitleDef` | `RoyalTitles/RoyalTitles_Gold.xml` | `Royalty/Defs/RoyalTitles/RoyalTitles_Empire.xml` | - |
| `RulePackDef` namer | `RulePackDefs/Namers_ColorPrefixes.xml`, `Namers_Unprefixed.xml` | `Biotech/Defs/RulePackDefs/RulePacks_Namers_Xenohumans.xml` | - |
| `BackstoryDef` | `BackstoryDefs/Backstories_Colors.xml` | `Core/Backstories/*.xml` *(expected)* | `Vanilla-Expanded/VanillaBackstoriesExpanded` |
| `BiomeDef` | `BiomeDefs/Biomes_RimRising.xml` | `Core/Defs/BiomeDefs/Biomes_WarmArid.xml` | `juanosarg/AlphaBiomes` |
| `ScenarioDef` | `Scenarios/Scenarios_RimRising.xml` | `Biotech/Defs/Scenarios/Scenarios.xml` | - |
| `StorytellerDef` | `Storyteller/Storyteller_BQC.xml` | `Core/Defs/Storyteller/Storytellers.xml` | - |
| `ResearchProjectDef`, `ResearchTabDef` | `ResearchProjectDefs/Research_RimRising.xml` | `Core/Defs/ResearchProjectDefs/ResearchTabs.xml` | - |
| `DamageDef`, `ToolCapacityDef`, `ManeuverDef` | `DamageDefs/`, `ToolCapacityDefs/`, `ManeuverDefs/` | `Core/Defs/DamageDefs/Damages_Misc.xml` *(expected)* | `juanosarg/AlphaAnimals` |
| `TraderKindDef` | none yet | `Royalty/Defs/TraderKindDefs/TraderKinds_Caravan_Empire.xml` *(expected)* | - |
| `QuestScriptDef` | none yet | `Core/Defs/QuestScriptDefs/` *(expected)* | - |
| Vehicle triad | `1.6/Mods/Vehicles/Defs/Drachenjager.xml` | Vehicle Framework's own `BaseVehiclePawn` | - |
| CE patch | `1.6/Mods/CombatExtended/Patches/*.xml` | CE `Patches/Core/ThingDefs_Misc/Weapons_Guns.xml` | - |
| Harmony / cross-mod patch | - | Alpha Genes `1.6/Patches/AlphaMythologyPatch.xml` | `juanosarg/AlphaGenes` |

Paths under **Ours** are relative to `1.6/Defs/` unless they start with `1.6/`.
