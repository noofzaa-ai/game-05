# Orc camp kit — scene asset standard

Source: `art_source/props/orc_camp/orc_source.glb` (unchanged). Builder: `tools/blender/build_orc_kit.py`.
Standard: root `assets_spec.md`; updated 2026-10-20.

- Shared external color1024 / normal512. Metallic0 / roughness1; no unnecessary ORM map.
- 12 stable named pieces;85% source triangles on static non-fire pieces. Gate,watchtower,forge,bonfire retain full geometry for small fire faces and light anchors.
- Whole kit49,495 ->44,861tri; transforms, grounded height, UVs and source shading normals retained through the builder.
- Regenerated Goblin arenas A/B/C,rest camp,Brush Ring with the shared kit. Four material groups per map retained; no new per-object draw calls.
- Explicit active/render Col export fixes Blender5.2 vertex-color selection, including restoring the painted warm flame colors rather than white kit fire faces.
- Historical `_lo` placement names alias these spec-budget meshes; no separate automatic runtime LOD switch.
- Gameplay data,collision,spawn andportal layout unchanged. Use `build_goblin_stages.py -- --art-only` for future art-only rebuilds.
- GPU compressed textures with mipmaps, S3TC/ETC2 per-device packs. Original high-resolution textures remain in source GLB outside game export.

| Piece | Triangles |
| --- | ---: |
| bone_fence | 2,014 |
| bonfire | 3,052 |
| cage | 2,362 |
| forge | 5,741 |
| gate | 5,238 |
| hut | 5,789 |
| palisade | 3,032 |
| picket_fence | 3,388 |
| throne | 6,860 |
| totem | 1,761 |
| war_banner | 995 |
| watchtower | 4,629 |
