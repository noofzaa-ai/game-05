# Mummy — rig v2

Prepared for scene 2, asset only. Stable ID `monster_mummy_01`.

- Source: `../assets/mummy.glb` relative to game repo (the supplied 2026-10-21 file, not the older `../../assets/monster/mummy.glb`). Source remains unchanged; SHA-256 in mummy.json.
- Runtime derivative: `art/monsters/mummy/mummy.glb`.
- Editable source: `art_source/monsters/mummy/mummy_rigged.blend` (packed bounded textures).
- 3,242 triangles; 2,103 original mesh vertices, no decimation or silhouette edits.
- 28 bones,25 deforming; maximum4 normalized influences. Includes root/hips/spine/chest/neck/head,clavicles,upper arms,forearms,hands,thighs,shins,feet,toes,two weapon attachment bones and four loose-bandage bones.
- Hands deform as a whole; individual finger articulation is not included. Weapon sockets are preparation only, not fitted weapon grips.
- Height uniformly fitted to1.80m to match SimBody.HEIGHT (source1.110859m, factor recorded in mummy.json). Mesh and bone rest positions scaled together; proportions/weights unchanged, feet at0; Blender forward-Y becomes glTF/Godot+Z. Do not directly retarget Goblin animations: naming overlaps but rest axes/proportions differ.
- Original UV/material appearance retained. Albedo1024,Normal512,Metallic/Roughness512,embedded PNGs; GodotS3TC/ETC2 VRAM compression+mipmaps. GLB approximately1.8MiB versus source29.8MiB; this is asset file size, not game download size.
- Region weights keep torso/head/limbs separate; coincident seam vertices share weights. Loose back wraps have their own bones attached to upper arms/forearms.
- Native Blender front/side/back and articulated front/back pose captures reviewed under `art_source/monsters/mummy/review/`. Godot4.7.2 import completed without errors. No automated suite or gameplay animation acceptance performed.
- No clips yet. Enemy type `mummy` is registered in combat data; map/spawn placement remains pending. No deployment for this preparation asset.

Rebuild from game repo:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/rig_mummy.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
python3 tools/art/optimize_npc_textures.py art/monsters/mummy
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/preview_mummy_rig.py
```

Optional source override: append `-- /absolute/path/to/mummy.glb` to the rigger. Landmark coordinates fit the supplied file only; do not reuse on a differently posed/scaled replacement without fitting them again.

## Combat type (provisional)

`data/combat/combat.json` → `enemies.mummy`: regular melee enemy,model/body height1.80m,HP450/ATK150/DEF45,MOVESPD32,ATKSPD50,CRIRATE0,poise0. Uses existing `fists` style (normal light attack),range1.3m,cooldown40–73 ticks,wait range3.2m,no random special,no retreat/flee. These are starter tuning values,not balanced encounter results. No new status effects or custom moves.

`data/loot/loot.json` → `by_enemy.mummy=grunt`: existing basic drop table as a provisional choice (level-1 gold6–15,independent material/equipment rolls). No items granted by registration. Default regular enemy health-bar tier applies; no existing map/Journey roster contains Mummy. Dedicated idle/walk/attack/hit/death clips are pending; the current client uses static-model fallback until clips exist.

Boss tuning2026-10-21: core stats use1.5x normal Goblin at equal level. Actual movement multiplier0.88×1.5=1.32,so MOVESPD32 (not -18). ATKSPD50 gives1.5x move-frame speed;AI waits shortened from Goblin60–110 ticks to40–73. Zero crit/poise remain zero. This is a stat/speed ratio,not a measured damage/DPS or difficulty guarantee: fists and Goblin moves have different power/timing. Source Goblin unchanged;loot and map membership unchanged.
