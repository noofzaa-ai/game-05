# Modular Mummy tomb kit v1

Source `../assets/modular_mummy_assets.glb` (relative to game repo),29,987,188bytes,one mesh/three4096px maps. Original remains unchanged. SHA-256 and part dimensions in mummy_kit.json.

11 bottom-centred semantic props: coffin,torch,pillar,anubis_urn,brazier,altar,stairs,chest,obelisk,wall_panel,urn. Separate flames/handles retained with their parent prop. Total5283tri unchanged; UVs and painted stone/bronze/blue appearance preserved. Each part is fitted uniformly to an intentional game-scale height; no rig or collision embedded.

- `mummy_kit.glb` has reusable named meshes at origin. It is a library,not an assembled scene.
- Shared `mummy_kit_albedo.png`1024;normal512;metallic/roughness512. Color sRGB,data Non-Color. Actual image sizes reduced,not just import limits.
- GLB175744bytes + shared PNGs:1994991bytes total. Source29.99MB -> derivative kit1.995MB (~93% less). Not a game download measurement.
- External image references are intentional: copy the GLB together with its three PNGs. Scenes use these exact images without embedding duplicates.
- Godot S3TC/ETC2 VRAM compression+mipmaps. Torch/brazier flame geometry has a separate emissive material; no particle emitter or animated flames added.
- Editable packed source `art_source/props/mummy_tomb/mummy_kit.blend` lays the parts out for editing. Generation script resets library-export transforms to origin.

Rebuild:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/prepare_mummy_kit.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
python3 tools/art/optimize_npc_textures.py art/props/mummy_tomb
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
```
