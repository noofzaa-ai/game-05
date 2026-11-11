# Relic Master — 2026-10-30

Source: `/Users/user/godot-project/assets/relic_master.fbx`, unchanged SHA256 `a2c4d8401e478cd6aac872d230522af51d955419ec3fbc9070e4c3bf0ebdec6d`.

Rebuild from the game repository: `python3 tools/art/prepare_relic_master.py`, then Godot import, `python3 tools/art/optimize_npc_textures.py art/npcs/relic_master`, then import again. Native Godot FBXDocument preserves source geometry; Python extracts embedded FBX roughness/metallic maps omitted by the native importer. No Blender dependency. Source maps are archived outside runtime under `art_source/npcs/relic_master/`.

- 6,232 triangles, one source mesh; 1.8m height, foot Y=0.
- Source FBX 26,737,356 bytes; derivative GLB 1,911,816 bytes.
- Color1024 / normal512 / metallic-roughness512, VRAM compression+mipmaps.
- GPU textures: 1,223,548 bytes per selected format(S3TC OR ETC2).
- Original roughness in G, metallic in B; material metallic factor0.35; normal strength1.
- Actual Web download size remains OPEN: no Relic build/deployment yet. File/GPU sizes above are not download totals.

Native rendered review: `build/relic-master-camp.png`, `build/relic-ui-1280.png`, `build/relic-ui-844.png`. NPC clear of Tailor tent; actual PC/mobile landscape bounds checked. No Web gameplay acceptance claimed.

## Standing correction (local, 2026-10-31)

Donor neutral Head pose pitches down and rolls sideways. client/relic_master_pose.gd applies one local pose delta to align the Head-to-Head_end axis with visual up before HubNpc caches idle rotations. Imported rig/rest/skin/material/meshes and FBX/GLB remain untouched. Only relic_master role uses it; label/bubble lifted0.12m to clear raised hair. Native beforeafter front/threequarter/side and idle/feet/rest invariants PASS (tools/shots/relic_master_pose_review.gd). No deploy; next scoped release must include helper and corrected hub_npc wrapper.

## Deployed 2026-10-31

Approved original-spec Relic UI and posture fix now live build **f8082c6b7f9a**. Exact shipped native/public byte checks passed; see docs/releases/relic-ui-20261031.md for release evidence and limitations. Historical LOCAL-only statements above superseded for this approved scope.
