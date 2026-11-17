# Request sheet: Mummy Mage (normal monster, magic caster)

From: monster-rigger (2026-11-17). For: the model team, through the PO. Mirrors the goblin mage (keeps away, throws a bolt and marks the ground).
Status: new model, nothing exists yet.

## 1. Role
- Normal monster, magic. A bandaged priest with a staff topped by a glowing scarab or crystal; hangs back, throws slow homing bolts and marks the floor with a curse circle.
- Size: 1.9 m tall in game (`model_height` 1.9, lighter build than the knight). A-pose, hips at 0.40-0.44 of the height, head at most 1.3x the player's ratio. A hood or headdress is fine as a SEPARATE skinned object (flat shapes, a few large folds, no cloth simulation). Normal legs.

## 2. Clips
Stance library: `magic`, from `art/characters/studio05/split/body_magic.glb`. STATUS: PLACEHOLDER picks, built and measured (124 KB) but NOT shipped. THE ANIMATOR MUST CONFIRM.
| Game clip | Copied from (magic clip) | Notes |
|---|---|---|
| `idle` | `mg_lite_idle` | loops |
| `run` | `mg_lite_run_forward` | loops, drift stripped |
| `cast` | `mg_lite_1h_magic_attack_01` | the bolt; release mark in the json |
| `cast_aoe` | `mg_lite_2h_magic_area_attack_02` | the telegraphed ground curse |
| `hit` | `mg_lite_react_small_from_front` | |
| `death` | `mg_lite_react_death_backward` | falls backwards, ends about 1 m behind its spot |
The goblin mage also has a `blink` clip. A mummy mage that teleports needs a NEW keyframed clip (`blink`), not a stretched player clip: ask the Boss/PO before requesting it.
Library convention: `art/animations/monster_clips_<stance>.glb` + `.json` (see `mummy_archer.md` section 10); the game plays the fixed names idle, run, hit, death plus the attack clips named in the monster data `clips` map. Leg length differing from the player rig is the monster data field `hips_scale` (default 1.0).

## 3. Skeleton (what you must deliver)
- Build on the SHARED 102-joint studio05 rig (donor `art/characters/studio05/split/body_longbow.glb`, joint list in `mummy_archer.md`, appendix). Deliver the MESH (skinned or not) in the neutral A-pose of section 5; the rigger binds it,
  keeps every donor joint name, parent and orientation, and moves joints to your mesh. An armature, if delivered, uses the donor names (`mixamorig_*`).
- Extra joints (names exact, parent = donor joint): `bandage_upper_L/R` (parent `mixamorig_LeftArm/RightArm`) and `bandage_lower_L/R` (parent `mixamorig_LeftForeArm/RightForeArm`): loose bandage ends. The shared libraries sway them; a model without them ignores the tracks. Keep them FEW and LARGE (see art rules).
- Weights: max 4 influences per vertex, normalised, clean falloff (about 2 cm blend) at shoulder, elbow, hip, knee, ankle, neck; head 100% to `mixamorig_Head`; hands one piece to the hand joints (no finger bones); loose cloth 100% to its bandage joint at the free end, blended into the arm; no floating geometry without a joint.
- Weapon and props: separate objects named `Monster_<Name>_<Part>`, weighted 100% to the holding hand joint (`mixamorig_LeftHand` / `mixamorig_RightHand`), modelled in the donor pose so they sit in the fist at idle (grip about 0.03 rig units along the hand's +Y).
- Staff: separate object `Monster_MummyMage_Staff`, weighted 100% to `mixamorig_RightHand`; the glowing head is a flat bright colour in the albedo (no extra material).

## 4. Proportion changes the rigger can absorb
Whole-body scale, bigger head or hands, longer or shorter arms: free. Shorter or longer legs: free with `hips_scale` (0.6-1.4). Quadruped, serpent, wings, extra arms: does not fit the shared rig (stop and ask the Boss).
A long robe hem must stay a few large panels that follow the legs (the shared rig has no skirt chain: ask the rigger if one is needed).

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
`model`, `animations` (art/animations/monster_clips_magic.glb), `clips` {<bolt id>: "cast", <curse id>: "cast_aoe"}, `model_height` 1.9, `run_clip_speed`, `hips_scale`, `body_height`. Timings: PO / combat-designer.

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
