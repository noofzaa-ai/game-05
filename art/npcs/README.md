# Camp NPCs

Imported from the user-provided `assets/Qboard.fbx`, `assets/storage.fbx` and
`assets/backsmith.fbx`, plus `assets/merchance.fbx` and `assets/capcut.fbx` using
`tools/blender/prepare_hub_npcs.py` from this game repository (sources in `../assets/`).

All derivatives are grounded, centered, and uniformly scaled to 1.6 m tall.
Original FBX files are preserved. Derivative color textures are capped at 1024 px; Normal and combined Metallic/Roughness at 512 px. See `assets_spec.md` in the repository root.

| Game role | Asset | Triangles | Rig |
| --- | --- | ---: | --- |
| quest | quest_board.glb | 5367 | none in supplied source |
| storage | storage.glb | 7563 | none in supplied source |
| blacksmith | blacksmith.glb | 7129 | original 28-bone armature |
| merchant | merchant.glb | 6128 | none in supplied source |
| tailor | tailor.glb | 5185 | original 28-bone armature |

`client/hub_npc.gd` retains the existing hub spawn points and interactions.
The blacksmith and tailor receive small looping chest/head/arm/forearm rotations on its
original rigs. Feet and root are unchanged. The three unrigged meshes stay static.
Tailor uses capcut.fbx at the same runtime scale as Merchant (0.825; 1.32 m tall).

Conversion completed; in-game visual review remains pending. No game build or
deployment was performed as part of this NPC change.

2026-10-20: Applied 1024 color / 512 normal + metallic-roughness to all five embedded GLBs. Geometry, rigs, runtime scaling and interactions preserved. GPU texture imports use the same caps with mipmaps.
