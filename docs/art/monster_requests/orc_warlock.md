# Request sheet: Orc Warlock (Orc Camp BOSS)

From: monster-rigger (2026-11-21). For: the model team, through the PO.

## 1. Source and role
- Source: the Boss's FBX `20261121101433_6c4e401e.fbx` (198 MB, 20 loose parts, 2.85 M triangles, no rig, no animation, one 4096 PBR set). It holds ONE chibi orc warlord: a deep purple hooded war-robe (long coat to the knees), two big bone horns on the hood, a crest spike, spiked bone-and-purple pauldrons, a green face in the hood's shadow, leather cuffs, a belt with a skull buckle, brown trousers, boots with straps. Empty hands, A-pose. Nothing unexpected inside.
- Role: the zone BOSS (family `orc`, enemy id `orc_warlock`, in `data/races/rules.json` boss_types and elite_types). Melee, **sword and shield** (Boss). Size: `model_height` 3.2 m (the grunt is 1.7 m, the Mummy High Wizard 3.4 m).
- **The sword and shield are MOCKUPS** (Boss: no weapon models yet): `Monster_OrcWarlock_MOCKUP_Sword` (plain grey broadsword) and `Monster_OrcWarlock_MOCKUP_Shield` (plain brown kite board with a steel boss), built by `_gear_mock_sword` / `_gear_mock_shield` in `tools/monsters/build_mummy_family.gd` in the exact pose of the player's own sword (right hand) and shield (left forearm). Replace them with real models later; they only exist so the animations can be judged.

## 2. Clips (all from the player's Sword & Shield set, `body_sword_shield.glb`; only 8 of its 47 clips)
| game clip | move | source clip | what it shows |
|---|---|---|---|
| `idle` | - | `idle_4` | shield up, steady; chest out, chin up, wide stance |
| `run` | walk | `run` at 1.8x | REGAL BRUTE WALK: pelvis straightened 18 deg, chin up, long stride (thighs x1.3), knees lifted (no dragging), every step planted, slow roll, shield across the body, sword arm swinging low |
| `attack_1` | `orc_warlock_cleave` (light) | `slash` from 0.4 s | blade drawn over the shoulder, a big sweeping cut + keyed trunk lunge; bleed 30% |
| `skyfall` | `orc_warlock_skyfall` (skill) | `attack_2` (the player's ULTIMATE) | run-up, a keyed LEAP (hips +0.15), overhead smash; dashes 3 m; sunder 60%, stun 25% (the only control, telegraphed) |
| `cataclysm` | `orc_warlock_cataclysm` (skill) | `slash_4` (the player's Breaker Slam) at 1.25x | spinning rise into the air, sword driven into the ground, a 6.5 m ring; weaken, wound, bleed |
| `block` | `orc_warlock_bulwark` (skill) | `block` 1.4x then `block_idle` | the over-the-top guard: a hop and STOMP into a wide, low stance, trunk thrown into the shield, shield arm driven forward, head tucked behind the rim, held 3 s; invulnerable for ~0.5 s, Fortify (DEF +50%) on itself, the slam exhausts/weakens whoever stands in front |
| `hit` | - | `impact` 1.4x | recoils behind the shield |
| `death` | - | `death_2` at 2.6x | sword lowered, drops to the knees, topples face down |
Library: `art/animations/monster_clips_orc_warlock.glb/.json` (229 KB), built by `tools/monsters/build_clip_library.gd -- orc_warlock --tol=1.0`.
`run_clip_speed` 0.919 = the measured planted-foot speed; at MOVESPD -20 (3.04 m/s) the run plays at 0.88x (0% foot slide).

## 3. Rig
- The shared 102-joint studio05 rig (no donor joint removed or merged) + the shared monster rig's 4 `bandage_*` joints (unweighted) = 106 joints.
- Landmark rig `tools/monsters/rig_warlock_fbx.py`: smooth distance weights on the coat (torso and sleeves), trousers, boots, pauldrons and hood; the coat skirt below the belt blends from the hips into the thigh on its side (up to 60%), so it follows the stride; face, horns, crest, buckle, belt, cuffs, hands and boot straps are rigid on one bone. Max 4 influences, normalised.

## 4. Art rules (for the real weapons and any future version)
- At most 5,000 triangles for the whole model (now 3,600: body 3,508 + mockups 92); one flat painted colour albedo (no PBR, normal, roughness or metallic maps, no baked ink or outlines: the game draws the outline); big simple shapes, closed meshes.
- Model (without textures) and each texture <= 450 KB; textures <= 1024 px, lossy (compress/mode=1, detect_3d off); no tangents, LODs or shadow meshes.
- Naming `Monster_OrcWarlock_<Part>`, +Z forward, feet at the origin, A-pose.
- Real sword: built along the player's sword grip (right hand, `mixamorig_RightHand`), blade length about the player's sword x1.05 (scaled with the body). Real shield: on the left forearm (`mixamorig_LeftForeArm`), about the player's shield x1.15.

## 5. Delivered (2026-11-21)
| file | triangles | size |
|---|---|---|
| `art/monsters/orc_warlock/orc_warlock.glb` | 3,600 | 425 KB without the texture |
| embedded albedo | 1024 jpg | 207 KB |
| `art/animations/monster_clips_orc_warlock.glb` | - | 229 KB |
Rebuild: `squeeze_fbx.py <fbx> build/orc_warlock 3350` -> `rig_warlock_fbx.py build/orc_warlock/squeezed.glb build/orc_warlock/rigged.glb` -> `build_clip_library.gd -- orc_warlock --tol=1.0` -> `build_mummy_family.gd -- orc_warlock` -> `--import` (then the model .import must keep no tangents/LODs/shadow meshes and the jpg lossy).

## 6. Acceptance (checked)
- `tests/test_monster_rig.gd` (budgets, 102 donor joints, clips and marks, run_clip_speed = foot speed, run inside the clamp, the lower foot never leaves the floor, boss-class rules: boss_types, CTRL_RES 100, 3 ai.skills with cooldowns, statuses, ATK >= 2x the grunt, 3.0-3.4 m, the leap/spin rise, the block holds).
- Wiring probe `tools/monsters/mummy_wiring_probe.gd -- orc_warlock`: own model, own library, 0% foot slide.
- Windowed shots `tools/monsters/warlock_shots.gd` (1280x720 and 844x390, with --strips).

## 6b. Boss feedback 2026-11-21 (robe read PINK)
- Root cause: the source albedo itself (the robe and hood are painted purple-magenta, hue 280-350), not the tint/squeeze or the ink shader; under the toon light it read pink. `rig_warlock_fbx.py` now repaints every purple pixel of the albedo warm earth brown (hue 24-36, darker shadows, the light rune trim turns bronze), except the spiked pauldrons' islands, and brightens the face in the hood (gamma 0.7, x1.2). Output `build/orc_warlock/albedo_brown.png`, used by `build_mummy_family.gd`.
- Coat stretch in the wide block stance: the skirt's thigh share cut from 60% to 35%.

## 7. Known weaknesses
- MOCKUP weapons: plain shapes on purpose.
- The coat is one shell: on the widest stride and the block's low stance the skirt stretches between the legs; at the cataclysm's spin the hood and coat move as a stiff block.
- The face reads dark inside the hood at phone size (the source texture is dark there).
- VFX: no own bundles yet (Boss). Strikes use the violence presets (boss / skill / aura) in purple; the Bulwark plays the player's Iron Guard aura at 1.8x.
- Numbers are placeholders until `orc_waves.json` exists and the combat-designer runs `class_sim`.
