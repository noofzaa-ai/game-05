# Campfire modular kit

Prepared 2026-10-21 from `assets/campfire_assets_split.fbx` supplied by Boss. The source FBX remains untouched.

## Contents

- `campfire_components.glb`: 11 separately named components, each at a bottom-centred origin (use as a component library, not a preassembled scene).
- Individual component GLBs: stones (large/small), long/short/round logs, stump, crossed firewood, flame, upper/lower stacked firewood and grass.
- `campfire_level_1.glb` through `campfire_level_3.glb`: ready prop assemblies using those parts; placement manifests in matching JSON.
- Three shared external PNGs: albedo1024, normal512, packed metallic/roughness512. Keep them beside the GLBs.
- `asset.json`: source hash, scale, per-piece dimensions, triangle counts and level summaries.

The FBX contained one mesh with **11 genuinely disconnected components**. They are separated along existing topology without spatial cuts or deleting source faces; original UVs/materials retained. Uniform source conversion factor4 is baked into component vertices. Godot +Y is up after glTF conversion; source placement manifests explicitly use Blender Z-up.

| Asset | Triangles |
| --- | ---: |
| All original components | 1,459 |
| Level1: small stone ring, crossed firewood/flame, one log seat and stump | 1,642 |
| Level2: wider stone ring, extra seat and stacked firewood | 2,730 |
| Level3: larger reinforced stone ring, more seating, stumps and firewood | 3,654 |

All GLBs plus the shared PNGs total **1,681,699bytes** before game packaging; this is not a measured web download delta. Editable `.blend` files and preview images are excluded under `art_source/props/campfire_workshop/`.

## Build

Run Blender with `--background --factory-startup --threads 4 --python tools/blender/prepare_campfire_workshop.py` from the repository root. Builder reads the original FBX, checks for one mesh/11loose components, prepares textures, publishes components/assemblies, and renders all three levels at the same camera scale. Native previews depict actual exported assembly geometry, not generated concept artwork.

Godot texture imports: GPU compression, mipmaps, correct normal role and actual size limits. Imports prepared in an isolated temporary Godot project to avoid interfering with concurrent work on the main game.

## Scope

This is a prepared art kit and visual progression proposal. No live Hub replacement, camp upgrade rules/costs/area unlocks, collision, server state or deployment was changed. The flame is the original static mesh with restrained emissive color; runtime flicker/smoke is not included. Review ground planes, cameras and lamps are excluded from exported GLBs.
