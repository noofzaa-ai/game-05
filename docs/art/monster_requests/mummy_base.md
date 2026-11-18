# Request sheet: Mummy Base (normal monster, unarmed or short blade, melee)

From: monster-rigger (2026-11-17). For: the model team, through the PO. Mirrors the goblin (the basic melee grunt of the goblin family).
Status: REPLACES the stand-in `art/monsters/mummy/mummy.glb` (1.8 MB, 3 PBR maps, own 28-bone rig, 3,242 triangles). It has the right size, A-pose and proportions, but its texture set and rig do not fit the shared rig. The same look rebuilt to the budgets below is acceptable.

## 1. Role
- Normal monster, melee, the most common mummy. A bandaged undead that walks up and strikes with fists or a short rusty blade (one hand, optional; if armed it is one separate object `Monster_MummyBase_Blade`).
- Size: 1.8 m tall in game (`model_height` 1.8; the player is at most 1.35 m). Chibi-ish proportions like the goblin family: hips at 0.40-0.44 of the height, head at most 1.3x the player's head/body ratio, normal arms and legs (hips_scale 1.0).

## 2. Clips (all copied from player clips, nothing keyframed by hand)
Stance library: `sword_shield` (one-hand melee), from `art/characters/studio05/split/body_sword_shield.glb`. STATUS: PLACEHOLDER choices in the table of `tools/monsters/build_clip_library.gd`; built and measured (107 KB) but NOT shipped. THE ANIMATOR MUST CONFIRM the picks before shipping.
| Game clip | Copied from (sword_shield clip) | Notes |
|---|---|---|
| `idle` | `idle_4` | loops |
| `run` | `run_2` | loops, root drift stripped, `travel_per_second` goes to `run_clip_speed` |
| `attack_1` | `attack_2` (first 1.6 s) | wind-up / strike marks in the json must fit the move timing in combat.json |
| `attack_2` | `slash` (first 1.6 s) | optional second move |
| `hit` | `impact` (0.62 s) | |
| `death` | `death` (3.0 s) | |
No finger tracks, no player hair tracks. New clips: none.
Library convention: `art/animations/monster_clips_<stance>.glb` + `.json` (see `mummy_archer.md` section 10); the game plays the fixed names idle, run, hit, death plus the attack clips named in the monster data `clips` map. Leg length differing from the player rig is the monster data field `hips_scale` (default 1.0).

## 3. Skeleton (what you must deliver)
- Build on the SHARED 102-joint studio05 rig (donor `art/characters/studio05/split/body_longbow.glb`, joint list in `mummy_archer.md`, appendix). Deliver the MESH (skinned or not) in the neutral A-pose of section 5; the rigger binds it,
  keeps every donor joint name, parent and orientation, and moves joints to your mesh. An armature, if delivered, uses the donor names (`mixamorig_*`).
- Extra joints (names exact, parent = donor joint): `bandage_upper_L/R` (parent `mixamorig_LeftArm/RightArm`) and `bandage_lower_L/R` (parent `mixamorig_LeftForeArm/RightForeArm`): loose bandage ends. The shared libraries sway them; a model without them ignores the tracks. Keep them FEW and LARGE (see art rules).
- Weights: max 4 influences per vertex, normalised, clean falloff (about 2 cm blend) at shoulder, elbow, hip, knee, ankle, neck; head 100% to `mixamorig_Head`; hands one piece to the hand joints (no finger bones); loose cloth 100% to its bandage joint at the free end, blended into the arm; no floating geometry without a joint.
- Weapon and props: separate objects named `Monster_<Name>_<Part>`, weighted 100% to the holding hand joint (`mixamorig_LeftHand` / `mixamorig_RightHand`), modelled in the donor pose so they sit in the fist at idle (grip about 0.03 rig units along the hand's +Y).

## 4. Proportion changes the rigger can absorb
Whole-body scale, bigger head or hands, longer or shorter arms: free. Shorter or longer legs: free with `hips_scale` (0.6-1.4). Quadruped, serpent, wings, extra arms: does not fit the shared rig (stop and ask the Boss).

## 5. Mesh, texture and orientation
- File: one GLB (or FBX), ONE mesh object for the body plus separate weapon/prop objects, named `Monster_<Name>_*` (body `Monster_<Name>_Body`).
- Pose: neutral A-pose like the donor: facing +Z (glTF/Godot forward), arms hanging 16-30 degrees from vertical with palms toward the legs, legs straight and parallel (at most 5 degrees splay), feet flat and pointing forward, head level. NOT a T-pose or a combat pose.
- Pivot at the feet centre, soles at y = 0, symmetrical about X = 0. Real-world scale as stated in section 1 (the rigger rescales to the rig).
- HARD LIMIT (Boss 2026-11-17): at most 5,000 triangles for the whole file (body + weapon + props); aim for 4,500. One material, one albedo atlas of at most 1024x1024 (512 is plenty), joints at most 110.
- Flat painted colour texture ONLY (Boss/PO 2026-11-17): one albedo, no PBR, no normal, roughness or metallic maps, and NO baked ink, dark outlines or baked shadows in the texture. The game draws the ink outline itself at render time
  (`client/fighter_view.gd` builds an outline shell per monster, skinned to the same bones, width capped 1-2 px by `draw_style.gd`; the goblin textures contain no painted outlines either).
- Big simple shapes: the outline shell doubles every small piece and turns clutter into black smudges. Model bandages as a FEW LARGE readable wraps, not many tiny strips or loose bits; no thin spikes, no details under about 5 px at phone size;
  closed meshes with no internal faces.
- Parts the game might hide or tint (hood, quiver, mask) are welcome as separate skinned objects. Do not put props, kits or scenes in the character file.

## 6. Game data the monster needs
`model` (art/monsters/mummy_base/mummy_base.glb), `animations` (art/animations/monster_clips_sword_shield.glb), `clips` {<move id>: "attack_1" ...}, `model_height` 1.8, `run_clip_speed` (from the library json), `hips_scale` (omit for 1.0), `body_height` (the rules' hurt box, the level-designer's call). Move timings belong to the PO / combat-designer; the rigger sets the clip marks to match.

## 7. Acceptance checklist (the rigger tests these)
1. Joints: all 102 donor joints with donor names, only the declared extras added (tests/test_monster_rig.gd).
2. Library: the clips of section 2 exist in the stance library, every bone a clip animates exists in the monster, valid marks.
3. Budgets, checked by the test that walks `art/monsters/**`: triangles <= 5,000, joints <= 110, one body material, textures <= 1024 px and lossy, model and each texture <= 450 KB; import settings without tangents/LODs/shadow meshes.
4. Windowed Godot strips of every clip from three-quarter, side and back: no limb through the body, no shoulder or hip collapse, no stretched triangles, nothing detached, feet near the floor, weapon in the fist through all clips.
5. Outline check: each monster rendered with the real ink outline (windowed, `tools/monsters/goblin_shots.gd` pattern) at fight-camera size and phone size (844x390); the rigger looks for smudging and reports it.
6. In the game camera: attacks land at the right moment (the marks in the library json agree with the move timings in `data/combat/combat.json`).

## 8. Ask for every delivery
- A character in the A-pose of section 5: one body mesh + weapon objects separately; textures at most 1024; flat colour only. Name files by content (`mummy_knight.glb`), never `modular_assets`.
- Tell the rigger which parts hang loose (cloth, bandage) so extra joints can be named before modelling.
- Deliver a turntable or front/side/back render with the file so a missing part is seen before rigging.

## 9. Status 2026-11-17: BUILT (placeholder look, character-artist)
Built by `tools/monsters/build_mummy_family.gd` (no new mesh delivery yet): the stand-in mummy mesh (now `tools/monsters/standin/`, not shipped) re-bound to the shared rig, 102 donor joints + `bandage_upper_L/R`, `bandage_lower_L/R` (106), simplified body 1,620 triangles, one 512 px tinted albedo shipped as lossy JPEG/WebP import, no tangents/LODs/shadow meshes. Gear is procedural, posed on the player's own weapon of the stance and weighted 100% to its holding joint. Checked by `tests/test_monster_rig.gd` (family section) and windowed shots `tools/monsters/mummy_family_shots.gd` -> `build/mummy_shots/`. A real model per sections 3-5 still replaces it later through the same builder.
- Files: `art/monsters/mummy/mummy.glb` (REPLACES the stand-in in place; combat.json path unchanged) + `mummy.json` + `mummy_bandage_albedo.jpg`. 1,668 triangles (body 1,620 + `Monster_Mummy_Blade` 48, right hand), 171 KB.
- Library `art/animations/monster_clips_sword_shield.glb` (shared with mummy_knight): idle `idle_4`, run `run` (forward; `run_2` runs BACKWARD), attack_1 `slash` 0.35-2.3 s (windup_end 1.05, strike_end 1.35), attack_2 `attack_4` 0.15-2.4 s overhead (1.37 / 1.61), hit `impact` 0.62 s, death `death` 0.4-4.6 s at 1.4x (lands on the floor). `run_clip_speed` 0.51. The table in section 2 is superseded; the animator may still re-pick.
- Data for the combat-designer: model_height 1.8, animations above, clips {<jab>: attack_1, <heavy>: attack_2}, run_clip_speed 0.51.
