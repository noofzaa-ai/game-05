# Blacksmith workshop

User source: `test01/assets/backsmith_fire.fbx` (kept unchanged outside game export).
Rebuild from game repo: Blender background `--python tools/blender/prepare_blacksmith_forge.py`; optional `--render` writes a review PNG to `/tmp`.

- 6,035 triangles, one source mesh.
- Source maps4096² reduced to albedo1024² / normal512² / combined metallic-roughness512², packed in derivative GLB. GPU imports use the same caps with mipmaps. See root `assets_spec.md`.
- Width5m, height2.6835m, depth4.6303m; floor at0, footprint centered.
- Runtime `client/hub_world.gd` places it at(8.6,0,-5.6), reuses existing warm flickering forge light.
- Contains its own furnace,anvil,rack,counter,roof and slab. `build_camp_hub.py` removes old station geometry, preserves RNG consumption for the rest of the camp, and supplies replacement colliders/NPC spot(8.4,0,-4.6).
- Blender5.2 export explicitly selects Color as active/render vertex color to preserve camp colors.
- Native landscape scene review completed; no automated tests run.

2026-10-20 Runtime effects:18 soft billboard flame particles at local(-0.29,0.77,-0.90),12 expanding/fading smoke particles at measured chimney rim(-0.306,2.66,-0.803). Procedural32² radial gradient, no added image assets, shadow casting off, reuse existing flickering forge light. Native landscape render checked.
