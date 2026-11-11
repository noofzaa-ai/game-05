# Camp modular bases — assembly review draft

Prepared from Boss's four `*_assets_split.fbx` sources on 2026-10-21. Original files are untouched. This is a local art review; no Hub placement, menu routing, server facility split, collision, or deployment has been changed.

| Kit | Original triangles | Draft sections |
| --- | ---: | ---: |
| Blacksmith | 9,085 | 11 |
| Merchant | 5,795 | 4 |
| Storage | 4,614 | 4 |
| Tailor | 2,959 | 4 |

Despite their filenames, the supplied FBXs each contain one joined mesh. Blacksmith has only two disconnected islands. Components here are spatial face selections, retaining source UVs and faces; they are **not clean authored modular pieces**. Cut boundaries can expose missing surfaces or include neighbouring geometry. Merchant/storage/tailor currently have foundation/left/central/right sections only, not fully independent named props. Review/retopology/capping is required before arbitrary rearrangement or camp-level variants.

## Blacksmith comparison

- `blacksmith/refine_station.glb`: full original workshop reassembled from its 11 sections, plus a continuous support slab. Keeps the forge, chimney, anvil, tool rack, roof and supplies together so fused boundaries are hidden.
- `blacksmith/upgrade_station.glb`: reuses the front workbench, anvil, rack and crates. Clean new low-poly foundation, timber posts, slate canopy, working table and brass work plate replace the problematic fused forge/roof sections. New pieces use solid materials, no extra textures.
- Both are **prop-only** assets. The actual existing game Blacksmith is instanced twice in the Blender review to show staffing/scale; NPCs are not baked into the GLBs. This does not yet create two interactable NPCs in the game.
- Review image and editable composition: `art_source/props/camp_modular/review/`.

## Files and budget

Each kit has bottom-centred component GLBs, original-layout `*_assembled.glb`, and `kit.json` with placement offsets, dimensions, source hash and triangle counts. All components share three external PNGs per kit. Copy those PNGs with the GLBs. Assembly width is 4.2m; Z-up Blender offsets in metadata are converted by glTF export for Godot.

Actual textures are resized to albedo1024, normal512, packed metallic/roughness512. GPU compression/mipmaps enabled for Godot. Editable Blender files and resized source images stay in excluded `art_source/`.

Builders: `tools/blender/prepare_camp_split_kits.py`, `tools/blender/preview_blacksmith_stations.py`.

Preview is a native Blender render of actual geometry, not generated concept art. Godot import is the only runtime preparation check performed; no combat/UI acceptance is claimed.

## Proposed workshop levels (local visual study)

`art_source/props/camp_modular/review/levels/` contains three native Blender scenes/renders and `proposal.json`:

1. Compact Refine workshop: small new clean forge + reused anvil/rack/front bench; only Refine unlocked.
2. Original larger forge workshop plus separate Upgrade workshop/NPC.
3. Both workshops gain wider back platforms, extra canopy, supply wings and additional work surfaces. Function/cap/cost changes for level3 are intentionally undefined.

These are proposed levels, not approved balance or runtime facility configuration. Props and NPC dimensions are fixed between shots; camera orthographic scale16.5 is also fixed. Growth comes from extra components and footprint. Original fused source still limits freely interchangeable original parts as described above.

### Revised direction — forge first (Boss correction)

Boss rejected level3 growth via extra canopies (2026-10-21). The new visual proposal is `review/levels_forge_v2/`, built with `preview_blacksmith_forge_levels.py`. Level1 stays compact, level2 uses the original full workshop, and level3 replaces the forge core with a deep monumental hearth, segmented stone arch, thick buttresses, twin tall reinforced open flues and restrained molten inlays. Upgrade becomes a heavy stone runic work altar instead of a canopy. This revision supersedes the canopy-growth proposal; original comparison files remain as history. Review geometry is not a production kit or runtime unlock/cost configuration.

### Current approved art direction — original Lv1 continuity (v3)

Boss rejected v2's different era/palette. `review/levels_matching_v3/` now uses the **actual original supplied workshop** as Lv1 (not the earlier primitive small-hearth stand-in). Lv2/Lv3 expand the same forge core with a shared transform across original fused parts to preserve seams, original UVs and materials. Lv3 extends its chimney using copies of the original textured upper masonry. Loose props/NPC stay at their existing size. Upgrade is absent at Lv1 and assembled from the source workbench, rack, anvil, barrel, crates and paving from Lv2 onward. It has no new gold/rune architecture or sun canopy. This supersedes both earlier visual studies. Still a native editable art proposal only; no runtime facility menus/costs/levels or deployment changes.
