# Request sheet: Mummy Boss (DESIGN PENDING THE BOSS)

From: monster-rigger (2026-11-17). For: the model team, through the PO.
**DESIGN PENDING THE BOSS: the Boss has not designed the pyramid boss. Do NOT model from this sheet yet. It fixes only the technical frame (rig, budgets, clip pipeline) so that whatever the Boss decides can be rigged fast. The level-designer's `mummy_boss_placeholder` is a gold-tinted, scaled-up mummy: a stand-in, not a design.**

## 1. Role (to be filled when the Boss decides)
- Boss of the Mummy Pyramid (wave 9 of `data/journeys/mummy_waves.json`). Unknown: name, silhouette, weapon, special moves.
- Size class: large humanoid, 2.4-3.0 m in game (`model_height`; the placeholder is 2.43). Humanoid on the shared 102-joint rig only. A serpent, quadruped or multi-armed pharaoh does NOT fit the shared rig: the rigger will stop and report 2-3 options with a recommendation for the Boss.
- The same 5,000-triangle hard limit applies to bosses (Boss 2026-11-17).

## 2. Clips
Base clips from the stance library the Boss's weapon implies (`sword_shield`, `greatsword` or `magic`; all are PLACEHOLDER tables in `tools/monsters/build_clip_library.gd`, THE ANIMATOR MUST CONFIRM): idle, run, hit, death plus one or two attacks copied from player clips. Bosses add their own special moves as NEW keyframed clips (a stomp, a summon, a sandstorm cast...): do not stretch a player clip into something it is not. Each new clip is listed here, with its move timing, once the Boss has designed it.
Library convention: `art/animations/monster_clips_<stance>.glb` + `.json` (see `mummy_archer.md` section 10); the game plays the fixed names idle, run, hit, death plus the attack clips named in the monster data `clips` map. Leg length differing from the player rig is the monster data field `hips_scale` (default 1.0).

## 3. Skeleton (what you must deliver)
- Build on the SHARED 102-joint studio05 rig (donor `art/characters/studio05/split/body_longbow.glb`, joint list in `mummy_archer.md`, appendix). Deliver the MESH (skinned or not) in the neutral A-pose of section 5; the rigger binds it,
  keeps every donor joint name, parent and orientation, and moves joints to your mesh. An armature, if delivered, uses the donor names (`mixamorig_*`).
- Extra joints (names exact, parent = donor joint): `bandage_upper_L/R` (parent `mixamorig_LeftArm/RightArm`) and `bandage_lower_L/R` (parent `mixamorig_LeftForeArm/RightForeArm`): loose bandage ends. The shared libraries sway them; a model without them ignores the tracks. Keep them FEW and LARGE (see art rules).
- Weights: max 4 influences per vertex, normalised, clean falloff (about 2 cm blend) at shoulder, elbow, hip, knee, ankle, neck; head 100% to `mixamorig_Head`; hands one piece to the hand joints (no finger bones); loose cloth 100% to its bandage joint at the free end, blended into the arm; no floating geometry without a joint.
- Weapon and props: separate objects named `Monster_<Name>_<Part>`, weighted 100% to the holding hand joint (`mixamorig_LeftHand` / `mixamorig_RightHand`), modelled in the donor pose so they sit in the fist at idle (grip about 0.03 rig units along the hand's +Y).
- Boss extras (only if the Boss's design asks): crown, cape, extra bandage chains, a tail: parented to donor joints, names agreed with the rigger BEFORE modelling.

## 4. Proportion changes the rigger can absorb
Whole-body scale, bigger head or hands, longer or shorter arms: free. Shorter or longer legs: free with `hips_scale` (0.6-1.4). Quadruped, serpent, wings, extra arms: does not fit the shared rig (stop and ask the Boss).
Very large scale makes copied arm and leg swings look slow and floaty: the rigger renders each clip and may speed it up or rewrite it.

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
`model`, `animations`, `clips` per move id, `model_height`, `run_clip_speed`, `hips_scale`, `body_height`. Boss moves, poise and timings are the PO's / combat-designer's after the Boss decides.

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

## 9. Status 2026-11-17: BUILT as the PO's DEFAULT Pharaoh (placeholder; the Boss has not accepted the design)
Built by `tools/monsters/build_mummy_family.gd` (no new mesh delivery yet): the stand-in mummy mesh (now `tools/monsters/standin/`, not shipped) re-bound to the shared rig, 102 donor joints + `bandage_upper_L/R`, `bandage_lower_L/R` (106), simplified body 1,620 triangles, one 512 px tinted albedo shipped as lossy JPEG/WebP import, no tangents/LODs/shadow meshes. Gear is procedural, posed on the player's own weapon of the stance and weighted 100% to its holding joint. Checked by `tests/test_monster_rig.gd` (family section) and windowed shots `tools/monsters/mummy_family_shots.gd` -> `build/mummy_shots/`. A real model per sections 3-5 still replaces it later through the same builder.
- Look (PO default): tall bandaged king, teal-grey bandages, gold-and-teal striped nemes with lappets and a gold uraeus, gold death mask with false beard and teal glowing eyes (`eyes_glow`), striped usekh collar (mixamorig_Spine2), gold khopesh held on the player's greatsword grip; shoulders x1.24, head x1.18.
- Files: `art/monsters/mummy_boss/mummy_boss.glb` + `.json` + albedo + 2 tiny stripe textures. 2,580 triangles (body 1,620, khopesh 120, nemes 516, mask 120, eyes 24, collar 180), 230 KB.
- Library `art/animations/monster_clips_greatsword.glb` (mirrors goblin_chief: quick chop + telegraphed leaping lunge, plus one extra): attack_1 `gs_slash` (0.6 / 0.86), attack_2 `gs_jump_attack` leap and slam (0.97 / 1.17; 15% of the donor's 0.97 rig-unit lunge kept, `pin_travel`), attack_3 `gs_high_spin_attack` whirl in place (0.84 / 1.26), hit, death, idle, run `gs_run_2` (forward; `gs_run` runs BACKWARD), run_clip_speed 1.275. These are copied player clips; no new keyframed boss clip exists yet.
- Data for the combat-designer: model_height 2.6, clips {<chop>: attack_1, <lunge/slam>: attack_2, <whirl>: attack_3}.
