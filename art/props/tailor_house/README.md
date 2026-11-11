# Tailor house

Source: `test01/assets/tailor.glb`, kept unchanged outside game export.
Prepare from game repo: `python3 tools/art/prepare_tailor_house.py` (Python + Pillow).

- Static building, separate from `art/npcs/tailor.glb` (the NPC).
- 3,498 triangles; original geometry, UVs and materials retained.
- Uniform normalization preserves source root rotation: width4.8m / height1.8677m / depth2.9883m; centered footprint, floorY=0.
- Actual embedded PNGs Color1024 / Normal512 / Metallic-Roughness512 per root `assets_spec.md`.
- GPU compressed imports, mipmaps, S3TC/ETC2 in existing stages packs.
- `client/hub_world.gd` places the house at the `tailor_house` marker (-8.6,0,-4.6).
- `build_camp_hub.py` removes the previous merged tent + clothes rack while preserving RNG consumption for all other scenery; replaces the solid bounds with the new footprint. NPC spot and interactions remain the same.
