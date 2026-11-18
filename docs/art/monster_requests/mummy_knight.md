# Request sheet: Mummy Knight (normal monster, shield and blade, melee tank)

From: monster-rigger (2026-11-17). For: the model team, through the PO. Mirrors the goblin knight (heavy armoured melee).
Status: new model, nothing exists yet.

## 1. Role
- Normal monster, melee, armoured: a tomb guard in bandages with a bronze helmet, a round shield on the LEFT arm and a heavy khopesh-style blade in the right hand. Slower and tankier than the base mummy, with a telegraphed overhead blow.
- Size: 2.0 m tall in game (`model_height` 2.0; the goblin knight is 1.61 against the goblin's 0.98). A-pose, hips at 0.40-0.44 of the height, head at most 1.3x the player's head/body ratio, slightly broad shoulders, normal legs (hips_scale 1.0).

## 2. Clips
Two options for the stance library; the animator picks (STATUS: both are PLACEHOLDER, built and measured but NOT shipped, THE ANIMATOR MUST CONFIRM):
- A (recommended): `sword_shield` library (107 KB), shield stance: `idle` from `block_idle` or `idle_4`, `run` from `run_2`, `attack_1` from `attack` (cleave), `attack_2` from `attack_3` (heavy overhead, telegraphed), `hit` from `impact`, `death` from `death`.
- B: `greatsword` library (93 KB): one heavy two-hand swing only; the shield would then be a static prop.
Clip names the game plays: idle, run, attack_1, attack_2, hit, death. Heavy walk: the data sets a low `run_clip_speed` (the goblin knight uses 1.55). No finger or hair tracks. New clips: none.
Library convention: `art/animations/monster_clips_<stance>.glb` + `.json` (see `mummy_archer.md` section 10); the game plays the fixed names idle, run, hit, death plus the attack clips named in the monster data `clips` map. Leg length differing from the player rig is the monster data field `hips_scale` (default 1.0).

## 3. Skeleton (what you must deliver)
- Build on the SHARED 102-joint studio05 rig (donor `art/characters/studio05/split/body_longbow.glb`, joint list in `mummy_archer.md`, appendix). Deliver the MESH (skinned or not) in the neutral A-pose of section 5; the rigger binds it,
  keeps every donor joint name, parent and orientation, and moves joints to your mesh. An armature, if delivered, uses the donor names (`mixamorig_*`).
- Extra joints (names exact, parent = donor joint): `bandage_upper_L/R` (parent `mixamorig_LeftArm/RightArm`) and `bandage_lower_L/R` (parent `mixamorig_LeftForeArm/RightForeArm`): loose bandage ends. The shared libraries sway them; a model without them ignores the tracks. Keep them FEW and LARGE (see art rules).
- Weights: max 4 influences per vertex, normalised, clean falloff (about 2 cm blend) at shoulder, elbow, hip, knee, ankle, neck; head 100% to `mixamorig_Head`; hands one piece to the hand joints (no finger bones); loose cloth 100% to its bandage joint at the free end, blended into the arm; no floating geometry without a joint.
- Weapon and props: separate objects named `Monster_<Name>_<Part>`, weighted 100% to the holding hand joint (`mixamorig_LeftHand` / `mixamorig_RightHand`), modelled in the donor pose so they sit in the fist at idle (grip about 0.03 rig units along the hand's +Y).
- Shield: separate object `Monster_MummyKnight_Shield`, weighted 100% to `mixamorig_LeftForeArm` (not the hand, so it does not spin with the wrist); blade `Monster_MummyKnight_Blade` to `mixamorig_RightHand`. Keep at least 4 cm between shield and torso in the A-pose so the arm swing does not clip.

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
`model`, `animations` (art/animations/monster_clips_sword_shield.glb), `clips` {<cleave id>: "attack_1", <overhead id>: "attack_2"}, `model_height` 2.0, `run_clip_speed` (low), `hips_scale`, `body_height`. Timings: PO / combat-designer.

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
- Files: `art/monsters/mummy_knight/mummy_knight.glb` + `.json` + albedo. 2,268 triangles (body 1,620, `_Shield` 132 on mixamorig_LeftForeArm, `_Khopesh` 120 on mixamorig_RightHand, `_Helmet` 396 on mixamorig_Head), 219 KB; shoulders x1.16, head x1.22, darker bandages; bronze + teal.
- Library `monster_clips_sword_shield` (shared with mummy): attack_1 = side cut (slash), attack_2 = telegraphed overhead (attack_4, raised 1.0 s, chop 1.37-1.61). run_clip_speed 0.51.
- Data for the combat-designer: model_height 2.0, clips {<cleave>: attack_1, <overhead>: attack_2}.
