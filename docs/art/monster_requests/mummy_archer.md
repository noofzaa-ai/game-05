# Request sheet: Mummy Archer (normal monster, bow)

From: monster-rigger (pilot, 2026-11-17). For: the model team, through the PO.
Status (v2, 2026-11-17): PILOT PROVEN with a stand-in (the existing `art/monsters/mummy/mummy.glb` mesh re-bound to the shared rig). This sheet is what a
real model must follow so it can be rigged in minutes, not days. Sections 8 and 9 say what the 2026-11-17 deliveries did right and wrong.

## 1. Role
- Normal monster (not a boss), ranged. Undead archer: bandaged mummy that keeps its distance and shoots arrows. It draws before each arrow;
  a rarer slow draw fires a 3-arrow volley (same pair of moves as the goblin archer: one shot, one telegraphed volley).
- Size class: medium humanoid, 1.8 m tall in game (`model_height` 1.8, a normal adult; the player is at most 1.35 m, so it towers over the squad).
  Proportions: the main characters are chibi (head about 1/4 of the height, hips at 0.42 of the height). Keep the mummy's hips at 0.40-0.44 of its
  height and its head at most 1.3 times the player's head/body ratio; legs and arms of normal length. Legs may be shorter or longer
  (the monster sets `hips_scale`, see 4); stay within 0.6-1.4 of the player's leg length.

## 2. Clips (all copied from the player's LONGBOW class, nothing is keyframed by hand)
Source: `art/characters/studio05/split/body_longbow.glb` (read only). Library: `art/animations/monster_clips_bow.glb` + `.json`, shared by every bow monster (convention in section 10).

| Game clip | Copied from (longbow clip) | Notes |
|---|---|---|
| `idle` | `lb_idle_01` (0 - 5.1 s, loops) | |
| `run` | `lb_run_forward` (0.883 s, loops) | The player's clip drifts 0.947 rig units forward through the Hips: the library strips the drift; `travel_per_second` 1.069 (rig units) goes to `run_clip_speed` |
| `shoot` | `lb_draw_arrow` (0-1.017 s at 1.35x) then `lb_aim_recoil` (0.17-0.70 s) | The player's own heartseeker shot (class_skills.json); arrow leaves at clip 0.763 s (`windup_end`), `strike_end` 0.833 s, length 1.283 s |
| `volley` | `lb_draw_arrow` (0-1.017 s at 1.0x, slow draw) then `lb_aim_recoil` (0.17-0.70 s) | release at 1.027 s, `strike_end` 1.097 s, length 1.547 s. Same body motion, longer draw = the telegraph |
| `hit` | `lb_react_small_from_front` first 0.62 s | |
| `death` | `lb_death_forward_01` (3.18 s) | falls forward and ends lying about 0.4 rig units (~1 m in game) in front of its spot |

Not copied: aim-walk, dodge, melee, equip, turn, the 40 finger tracks and the 21 player hair tracks of every clip (monster hands deform as one piece).
New clips this monster needs: none. (A later "reload from the quiver" or "collapse into bandages" would be new keyframed clips, not stretched player clips.)

## 3. Skeleton (what you must deliver)
- Build on the SHARED 102-joint studio05 rig. Rig source and the donor mesh: `art/characters/studio05/split/body_longbow.glb` (joint list at the end of this sheet).
  Keep every joint name, parent and the A-pose orientation of the donor. The rigger moves the joints to your mesh; you do not need to
  pose-match by hand, but your mesh must be close to the donor's pose (section 5).
- Do not ship hair joints, finger joints etc. in your own armature: deliver the MESH (skinned or not) in the pose below; the rigger binds it.
  If you do deliver an armature, use the donor names (e.g. `mixamorig_LeftArm`) so the weights transfer by name.
- Extra joints wanted (parent = donor joint, all with the donor's orientation, names exact):
  - `bandage_upper_L` / `bandage_upper_R`: loose bandage ends hanging behind the upper arms (parent `mixamorig_LeftArm` / `mixamorig_RightArm`)
  - `bandage_lower_L` / `bandage_lower_R`: loose bandage ends behind the forearms (parent `mixamorig_LeftForeArm` / `mixamorig_RightForeArm`)
  - The shared library already sways these four (idle and run); a monster without them ignores the tracks. More bandage chains (back, waist): ask the rigger for names.
- Weights: max 4 influences per vertex, normalised, clean falloff at the shoulder, elbow, hip, knee, ankle and neck (about 2 cm of blend over a joint,
  no single-vertex jumps); head 100% to `mixamorig_Head`; hands one piece to the hand joints (no finger bones needed); loose bandage cloth 100% to its bandage joint
  at the free end, blended up into the arm; no floating geometry without a joint.
- Bow: weighted 100% to `mixamorig_LeftHand`, string to the hands/bow (the player's bow `L 01 | Bow` + `L 17 | Bow string` of `armor_longbow.glb` fit and are
  what the pilot uses). A new bow must be skinned in the same donor pose so it sits in the left fist at idle: grip about 0.03 units along the hand's +Y.
- Nocked arrow: a small separate mesh called exactly `arrow` (about 0.3 rig units long, 8-30 triangles) weighted 100% to `mixamorig_RightHand`; the game shows it only while the draw
  winds up (`nock_mesh`). The pilot builds it from the full-draw pose.

## 4. Proportion changes the rigger can absorb (and the price)
| Change | Cost |
|---|---|
| Whole-body scale (`model_height`) | free |
| Bigger head (tested x1.3) / bigger hands / feet | free: baked into mesh and joints, shared library unchanged |
| Longer or shorter arms | free: clip rotations only, no arm translation in the clips |
| Shorter / longer LEGS | free since v2: monster data field `hips_scale` (default 1.0) rescales the Hips translation of the shared library at runtime (`client/animation_set.gd`), so no second clip file. Tested at 0.75 (feet stay on the floor); below about 0.6 expect clipping/foot slide. Bake the shorter legs into the mesh and joints as for the big head |
| Quadruped, serpent, wings, extra arms | does NOT fit the shared rig: stop and ask the Boss |

## 5. Mesh, texture and orientation
- File: one GLB (or FBX) with ONE mesh object for the body (plus separate `bow`, `arrow` objects), named `Monster_MummyArcher_*` (body: `Monster_MummyArcher_Body`).
- Pose: neutral A-pose like the donor: facing +Z (glTF/Godot forward), arms hanging about 16-30 degrees from vertical with the palms toward the legs, legs straight and parallel
  (no more than 5 degrees splay), feet flat on the floor and pointing forward, head level. NOT a T-pose, not a combat pose.
- Pivot at the feet centre, feet soles at y = 0, symmetrical about X = 0. Real-world scale 1.8 m (the rigger rescales to the rig anyway, but give a sane number).
- Budget: body at most 3,500 triangles, whole file (body + bow + arrow) at most 4,500 triangles (v2 ships 2,132 after the rigger's simplification: body 1,620, bow 450; the source mummy was 3,242 + the player's 900-triangle bow). One material, one
  albedo atlas of at most 1024x1024 (the pilot shrinks to 512 and ships it as lossy WebP, 40 KB instead of 298 KB lossless: the delivered file will be re-compressed, but do not send 4096 maps), no normal or
  metallic map needed, no extra textures, no vertex colours, no blendshapes. Ink outline and toon shading come from the game: keep the albedo flat-lit, no baked shadows.
- Separate parts for anything the game might hide or tint (hood, quiver, mask) are welcome but must be skinned too.
- Do not deliver props, kits or scenes in the same file as the character (section 8).

## 6. Game data the monster needs (the PO decides the numbers; pilot values in brackets)
`model` (art/monsters/mummy_archer/mummy_archer.glb), `animations` (art/animations/monster_clips_bow.glb, marks in the `.json` next to it), `clips` {<shot move id>: "shoot", <volley move id>: "volley"},
`nock_mesh` "arrow", `model_height` 1.8, `run_clip_speed` 1.069 (rig units per second, from the library json), `hips_scale` 1.0 (omit for 1.0; 0.75 would be legs 25% shorter), `body_height` (the rules' hurt box; goblin archer 1.04 of 1.24).
The level-designer's `mummy_archer` entry in combat.json already follows this (model, animations, clips, nock_mesh, model_height 1.8, run_clip_speed 1.069).
Moves (pilot, 60 ticks per second, natural clip speed 1.0): shot startup 46 / active 4 / recovery 28; volley startup 62 / active 4 / recovery 34. The arrow spawns at move_frame
= startup, which the pilot measured at clip time 0.7633 s = the clip's `windup_end` (proof in tools/monsters/mummy_archer_fire_shot.gd). Arrow spawn offset
[forward, up, side] = [0.70, 1.15, 0.14] m for a 1.8 m monster (the arrow tip at the release pose).

## 7. Acceptance checklist (the rigger tests these)
1. Joints: all 102 donor joints present with donor names, only the declared extras added. (tests/test_monster_rig.gd)
2. Library: exactly `idle run shoot volley hit death`, every bone a clip animates exists in the monster, valid marks, run does not drift. (tests)
3. Budgets: triangles <= 4,500 (hard 6,000), file <= 450 KB (v2: 224 KB), library <= 200 KB (v2: 172 KB), body one material, atlas <= 1024, joints <= 110; import settings: lossy texture, no tangents/LODs/shadow meshes. (tests)
4. Windowed Godot strips of idle, run, shoot, volley, hit, death, viewed from front-3/4, side and back: no limb through the body, no shoulder or hip collapse,
   no stretched triangles, no bandage or arrow detached, feet near the floor (a gap of more than about 5% of the height or a sunk foot is a failure), the bow stays in the left fist
   through all clips, the arrow shows only while drawing.
5. In the game camera (practice field): the arrow leaves at the right moment and hits where the aim is. (tools/monsters/mummy_archer_fire_shot.gd)

## 8. What the 2026-11-17 deliveries tell us
`C:\Users\wanwi\Downloads\mummy_modular_assets.fbx` (27.7 MB): done right: one clean mesh with UVs and one PBR material, no stray objects.
Wrong for a character: it is the TOMB PROP KIT (coffin, pillar, torch, Anubis urn, brazier, altar, stairs, chest, obelisk, wall panel, urn; already extracted to `art/props/mummy_tomb`),
a single fused mesh with 16 loose islands, 5,283 triangles, no armature, no vertex groups, 4 embedded 4096x4096 textures (~27.4 MB), 45 non-manifold edges, and NO body, head, bandage or bow.
The name ("modular assets") reads like a character kit; please name files by content (`mummy_tomb_props`) and send characters as characters.
`art/monsters/mummy/mummy.glb` (2026-10-21): done right: a real character at 1.8 m, A-pose, feet at 0, facing +Z, 3,242 triangles, clean weights with 4 influences max, bone names
that map 1:1 to the donor, loose bandage bones, sockets, 1024 textures. Weak: its own 28-bone rig does not match the donor's axes (so its clips cannot be shared), thighs splayed
about 11 degrees and arms 29 degrees (the pilot swings them to the donor pose, a small deformation cost), no fingers, 1.8 MB with 4 maps.

## 9. Ask next time
- A character, in the A-pose of section 5, one mesh + the bow + `arrow` separately, textures at most 1024.
- Tell the rigger which parts hang loose (cloth, bandage, tail) so extra joints can be named before modelling.
- Deliver a turntable or front/side/back render with the file so a missing part is seen before rigging.

## Appendix: donor joint names (102)
Root, mixamorig_Hips, mixamorig_{Left,Right}{UpLeg,Leg,Foot,ToeBase,Toe_End,Toe_End_end}, mixamorig_Spine, Spine1, Spine2, mixamorig_{Left,Right}{Shoulder,Arm,ForeArm,Hand},
the 40 finger joints (Hand{Index,Middle,Pinky,Ring,Thumb}1-4 and _end), mixamorig_Neck, mixamorig_Head, 21 hair_* joints, headfront, headfront_end,
mixamorig_HeadTop_End, mixamorig_HeadTop_End_end. Full list with parents: run
`godot --headless --path . --script res://tools/monsters/inspect_glb.gd -- res://art/characters/studio05/split/body_longbow.glb clips bones`.

## 10. Clip library convention (v2) and measured sizes
- Naming: `art/animations/monster_clips_<stance>.glb` + `.json`, stance = bow, sword_shield, greatsword, magic. A monster's data points `animations` at the library of its stance;
  the game plays the fixed names `idle`, `run`, `hit`, `death` and the move clips named in the monster's `clips` map (`shoot`, `volley`, `attack_1`, `attack_2`, `cast`, `cast_aoe`...).
  Marks (`length`, `loop`, `windup_end`, `strike_end`, run `travel_per_second`) sit in the `.json` next to it. Build: `tools/monsters/build_clip_library.gd -- <stance> [--tol=1.0]` (the library table in that file holds the clip choices of all four stances; only `bow` is shipped).
- One library PER STANCE, not one library with everything: every stance has its own idle, run, hit and death (the weapon is in the hand), and the game looks these up by fixed name, so one file cannot hold two stances without code changes; and a map would download clips it never plays.
- Shipped sizes are the imported (pack) files. Measured at the pilot key tolerance 0.35 degree (a built but unshipped library per stance, 6 clips each): bow 118 KB, sword_shield 107 KB, greatsword 93 KB, magic 124 KB (sum 443 KB). One merged library holding all unique clips would be about 238 KB (estimated from key counts) and cannot work by name; per stance, a map loads only its stances (the mummy map: bow, 98 KB).
- v2 uses key tolerance 1.0 degree: bow library 118 KB -> 98 KB shipped (0.8 degree gave 102 KB, 1.2 degrees 92 KB); the strips show no difference at game distance.
- Goblins (report only, not migrated): their per-monster sets ship 95-119 KB each (goblin 114, archer 95, chief 97, knight 109, mage 119 = 534 KB for five). A stance library costs about the same as ONE of them, so sharing saves bytes only when two or more monsters use one stance (about 100 KB per extra monster); the goblin clips are hand-keyframed by the animator, not player clips, so they would also change look.
- Pack impact of the mummy archer (imported files, bytes): model 132,781 -> 75,244 (simplified mesh, no tangents/LODs/shadow meshes); texture 297,820 -> 39,566 (lossy WebP instead of lossless); library 118,445 -> 97,633; total 549,046 -> 212,443 (-61%). The short-legs variant (another 548,506) is gone: `hips_scale` replaces it.
