# Request sheet: Orc family (grunt, archer, mage), built from ONE supplied body

From: monster-rigger (2026-11-21). For: the model team, through the PO.
**Boss rule 2026-11-21:** a zone's monster family may come from ONE supplied body. Rig it once, then make every type from it (tint, proportions, its own weapon, its own animations). Do not wait for one model per type.

## 1. Source and roles
- Source: the Boss's orc FBX (188 MB, 19 loose parts, 2.6 M triangles, no rig, one 4096 PBR set). It contains ONE chibi orc grunt (green skin, black mohawk, leather vest, stone shoulder pads, bracers, belt with stone buckle, loincloth, fur boots), empty hands, A/T pose. It has no weapons and no archer or mage variant.
- Normal monsters of the Orc Camp zone (family `orc`; the Orc Warlock boss comes later):

| type | role | attack | model_height | stance library |
|---|---|---|---|---|
| `orc_grunt` | melee brute | cleaver chop + lunging cleave (wound) | 1.7 m, shoulders x1.12 | `monster_clips_orc_grunt` |
| `orc_archer` | ranged | shot + 3-arrow volley | 1.6 m, shoulders x0.94, green-tinted | `monster_clips_orc_bow` |
| `orc_mage` | caster | homing bolt + ground hex (slow) + blink | 1.6 m, shoulders x0.94, head x1.06, blue-tinted | `monster_clips_orc_magic` |

## 2. Clips (each type has its OWN library and its own walk)
| type | idle | run (own walk) | attacks | hit | death |
|---|---|---|---|---|---|
| grunt | `gs_idle`, hunched, arms out | sword_shield `run` at 2.7x: brute stomp, pelvis straightened 16 deg (trunk ~17 deg), rolling 7 deg, wide stance, both arms swinging against the legs, cleaver carried | attack_1 = `attack_4` 0.6-2.0 s; attack_2 = `slash_3` 1.3-3.6 s + keyed trunk lunge | `impact_3` 1.3x | `death` 1.4x |
| archer | `lb_idle_02_looking` | `lb_run_forward` 1.55x: light upright run, pelvis straightened 22 deg (trunk ~14 deg, was 44), knee lift x1.2, arms counter-swinging, bow at the side | shoot / volley = `lb_draw_arrow` + `lb_aim_recoil` (the player's shot) | `lb_react_small_from_headshot` | `lb_death_backward_01` |
| mage | `mg_spell_idle` | `mg_loco_run_forward` 1.25x: shaman waddle, upright-ish (trunk ~12 deg), 8 deg side roll, head bob, free arm swinging | cast = `mg_spell_1h_magic_attack_02`; cast_aoe = `mg_spell_2h_magic_area_attack_01`; blink = `mg_spell_2h_cast_spell_01` 2x | `mg_lite_react_small_from_front` 1.2x | `mg_lite_react_death_backward` |

Every run keeps one foot on the floor (no flight phase). `run_clip_speed` = the measured planted-foot speed (grunt 1.546, archer 1.726, mage 1.42), so each type plays inside the 0.6-1.4x clamp at its MOVESPD. Table and marks: `tools/monsters/build_clip_library.gd`.
Animator pass 2026-11-21 (Boss: "the run must not look like crawling"): new layers in the builder: `upright` (tips the pelvis back while the thighs keep their direction, so a folded donor run straightens without changing the stride), `swing` (stride-synced arm counter-swing), `shrug` (hands part of the clavicle's rotation to the upper arm: the arm points the same way, the clavicle and the pad/vest top skinned to it lift about half as much). Posture numbers: `tools/monsters/posture_probe.gd`.

## 3. Rig
- The shared 102-joint studio05 rig (no donor joint removed or merged). The shared monster rig's four `bandage_*` extra joints are present but unweighted.
- Landmark rig `tools/monsters/rig_orc_fbx.py`: smooth distance weights on the skin parts (torso/arms/head, legs, boots, shoulder pads), each restricted to its own bones; the accessories are rigid on one bone. Max 4 influences, normalised.
- Gear is built in `tools/monsters/build_mummy_family.gd`, in the pose of the player's own weapon of that stance, 100% on the holding joint: cleaver (the player's sword frame), the player's longbow + string + nocked `arrow` (moved to the orc rest pose), totem staff with a horned skull and green stone (the player's staff frame). The red headband and the bone skull mask with glowing eyes are on `mixamorig_Head`.

## 4. Art rules (for any future orc model)
- At most 5,000 triangles; one flat painted colour albedo (no PBR, normal, roughness or metallic maps, no baked ink or dark outlines: the game draws the outline); big simple shapes, closed meshes.
- Model (without textures) and each texture <= 450 KB; textures <= 1024 px, imported lossy (compress/mode=1, detect_3d off); model imported with no tangents, LODs or shadow meshes.
- Naming `Monster_<Name>_<Part>`, +Z forward, feet at the origin, A-pose.

## 5. Delivered (2026-11-21)
| model | triangles | model bytes (no texture) | texture |
|---|---|---|---|
| `art/monsters/orc_grunt/orc_grunt.glb` | 3,458 (body 3,414 + cleaver 44) | 387 KB | 1024 jpg 190 KB |
| `art/monsters/orc_archer/orc_archer.glb` | 4,062 (body + bow 450, string, arrow, headband 136) | 439 KB | 1024 jpg 181 KB |
| `art/monsters/orc_mage/orc_mage.glb` | 3,822 (body + staff 184, mask 224) | 415 KB | 1024 jpg 177 KB |

To keep the size budget the body was decimated to 3,414 triangles and smooth shaded, and the TANGENT streams were dropped (`prune_glb.py --strip-tangents`).
Rebuild: `squeeze_fbx.py <fbx> build/orc_base 3400` -> `rig_orc_fbx.py build/orc_base/squeezed.glb build/orc_base/rigged.glb` -> `build_mummy_family.gd -- orc_grunt orc_archer orc_mage` -> `build_clip_library.gd -- orc_grunt orc_bow orc_magic --tol=1.0` -> `--import`.

## 6. Acceptance (checked)
- `tests/test_monster_rig.gd`: budgets, the 102 donor joints, clip names and marks, run_clip_speed = foot speed, run inside the clamp, the lower foot never leaves the floor, one shared body, an own library per type, goblin stats with 2x ATK, no journey or map spawns an orc yet.
- Wiring probe `tools/monsters/mummy_wiring_probe.gd -- orc_grunt orc_archer orc_mage`: each type loads its own model, library and clips, with 0% foot slide.
- Windowed shots: `tools/monsters/mummy_anim_shots.gd` (1280x720 and 844x390).

## 7. Known weaknesses
- All three share one silhouette. They are told apart mainly by weapon, headgear, tint and gait; at phone size the tint difference is subtle.
- The shoulder pads and the vest deform as a stiff shell when the arms are raised high (cast_aoe, the overhead cleave). Reduced 2026-11-21 by `shrug` in the clips (clavicle lift about halved); the pads are still weighted only to clavicle + upper arm, so a fully raised arm still lifts them. A real fix is a re-weight in `rig_orc_fbx.py` (pads partly on the chest), not done here.
- The archer's bow is the player's longbow, recoloured, not an orc-made bow.
