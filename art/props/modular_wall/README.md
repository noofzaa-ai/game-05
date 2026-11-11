# Modular wooden fence kit

Source: `/Users/user/godot-project/assets/wall_modular.fbx`, SHA256 in asset.json. Original FBX untouched and excluded from web export.

Godot 4.7.2 native FBXDocument exports the original geometry/UVs/materials. The file contains eight separate pieces in one mesh: split by welded connected components (3,122 triangles total), preserving original UV/normals/tangents and texture. Rail pieces are aligned along X; all pivots centred on XZ at foot Y=0. Rail 448 triangles, Post 76 triangles. Post height 1.35m. The remaining gate/corner variants are prepared but not placed across open entrances.

Color 1024, normal 512, MR 512 (G roughness/B metallic). Native FBX import omitted MR and normal strength: original packed FBX maps restored, normal strength 1. GPU compressed S3TC/ETC2 with mipmaps. Original extracted MR maps are under art_source/props/modular_wall; no Blender model exports.

Rebuild from project root:
```
python3 tools/art/prepare_modular_wall.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
python3 tools/art/optimize_npc_textures.py art/props/modular_wall
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
```
The preparation wrapper calls split_modular_wall.py and align_modular_wall.py. `--use-existing-export` only budgets an unsplit native export; split derivatives are left intact.

`client/modular_fence.gd` shares layouts between visuals and simulation blockers. Rail/Post use two MultiMeshes per enclosure, shared mesh/material/texture resources; no texture copies per segment. Farm is visible from camp Lv2. West farm opening 2.4m, east training opening 2.2m. Both checked using real hub player movement in tools/shots/modular_fence_review.gd. Local screenshots: build/modular-fence-{training,farm}.png. No web build or deployment in this task.

## Game mood correction (2026-10-29)
`client/modular_fence.gd` shares a camp material across Rail/Post batches. It grades the original colour texture toward muted grey-brown (55% original chroma, restrained RGB gain), keeps original normal and packed MR data, raises roughness to at least0.8 and lowers metallic/specular response. Original FBX and texture pixels remain intact; all reconstruction parameters live in code. Native camp-light PC screenshots inspected in build/fence-muted-{training,farm}.png. No extra texture downloads or draw calls are introduced by the shared material.
