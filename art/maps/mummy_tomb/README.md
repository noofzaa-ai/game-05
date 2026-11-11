# Mummy pyramid — three scene2 drafts

Builder `tools/blender/build_mummy_stage.py` creates art, matching collision/spawn JSON and ordered presentation plan `route.json`:

| Order | Map ID | Scene | Triangles | GLB bytes |
|---|---|---|---:|---:|
|1|mummy_arena_a|Desert courtyard outside the Great Pyramid|27142|1315436|
|2|mummy_arena_b|Interior burial hall with aisles and coffins|26296|1250280|
|3|mummy_arena_c|Solar ritual chamber beneath the cutaway pyramid apex|22356|1123148|

All three have28x22m walkable bounds (Goblin A/C28x21m),four level1 `mummy` draft spawns,two northern exit landings,southern player entry. Source layout owns both art/gameplay positions. Scene elevations are local: floorY0 for each separate map,not continuous vertical travel inside one world. Ground +10/28/27 prop/dais collision boxes respectively;large grounded props inside the bounds are solid. Peripheral art beyond the bounds is scenery. Runtime collision/combat playthrough remains pending.

## Art and camera

- A: actual square pyramid22m high behind the north gateway,desert dunes,paved approach and cover. Pyramid stays outside walk bounds.
- B: roof/south wall cut away to expose the fight to the top-down camera. Four support columns,side burial alcoves,fire bowls and ascending doorway. Cooler night mood distinguishes the interior.
- C: brighter gold/blue solar inlay,royal sarcophagus dais,clerestory windows,obelisk cover,and rear triangular roof cross-section representing the apex;roof over combat omitted for camera visibility. Raised dais has explicit solid box.
- One merged render object per scene,9/8/8 exported material surfaces. Shared kit albedo1024/normal512/MR512 via `../../props/mummy_tomb/`. No per-scene texture duplicates.
-3arena GLBs total3688864bytes + shared kit/PNG1994991bytes =5683855bytes of preparation assets. Not a compressed web-download or GPU-memory measurement.
- Editable packed blends live under `art_source/maps/mummy_tomb/` (excluded from game export);original modular kit unchanged.
- Decorative kit chests are scenery,not reward chests. No new rewards,treasure rules or boss variant.

## Current integration status

Ordered scene preparation only. `route.json` records exterior→interior→summit but is **not consumed by Journey runtime**. These maps are not added to existing map index,Journey roster or world-map destinations. No automatic portal transition chain,new boss definition,web build or deployment. Mummy's dedicated animation clips remain pending.

Native Godot Compatibility captures `art_source/preview/mummy_tomb/<map_id>_{overview,gameplay,sanctuary}.png` use actual map/props/moods and static1.80m figures at full resolution without changing saved graphics preferences. Legacy overview/gameplay/sanctuary filenames remain aliases for mapA. Native MapLoader/import/preview loaded without errors;no automated tests,combat acceptance or mobile UI acceptance performed.

## Rebuild

From game repo after kit preparation:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_mummy_stage.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
python3 tools/art/optimize_npc_textures.py art/props/mummy_tomb art/maps/mummy_tomb
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/shots/mummy_stage_preview.gd
```

Append `-- mummy_arena_b` to either builder or preview command to process one scene. Builder updates route plan for all three even when selecting one.

### Private activation2026-10-21

The3-map sequence is now connected by the room worker for the owner-only `mummy_ascent` Solo route. `route.json` remains an art presentation plan,not runtime input;normal Journey/index unchanged. See docs/tech/mummy_private_preview.md for UUID admission,entry button and rollout.
