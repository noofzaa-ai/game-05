extends SceneTree
## Builds a monster clip library (skeleton-only .glb + .json of marks) out of the player's longbow clips.
## Only the clips a bow monster needs are copied, each baked at 30 fps and key-reduced; the player's files are only read.
##   godot --headless --path . --script res://tools/monsters/build_clip_library.gd
##   godot --headless --path . --script res://tools/monsters/build_clip_library.gd -- bow [sword_shield greatsword magic] [--out=res://dir/] [--tol=0.35]
## Output: art/animations/monster_clips_<stance>.glb + .json (the player's proportions). Leg proportions of a monster are NOT baked in:
## the monster's data field hips_scale rescales the Hips translation at runtime (client/animation_set.gd).
## Then re-import (godot --headless --path . --import).

const Rig := preload("res://tools/monsters/rig_common.gd")

## Libraries, one per weapon stance (a monster loads ONE: its own idle/run/hit/death + the attacks of its stance).
## Each is a skeleton-only glb named monster_clips_<stance>.glb with a .json of marks next to it.
## Clip entries: clip name -> {"segs": [[donor clip, from, to, speed]...] played one after the other (speed 2 = twice as fast)}.
## Shipped: bow (mummy_archer), mummy, sword_shield (mummy_knight), greatsword (mummy_boss), magic (mummy_mage), wizard_boss,
## orc_grunt, orc_bow (orc_archer), orc_magic (orc_mage).
## Clip choices checked by the animator 2026-11-19 (windowed shots: tools/monsters/mummy_anim_shots.gd).
## bow shoot  = the player's own two-part shot (class_skills.json heartseeker: lb_draw_arrow then lb_aim_recoil, released at 0.18 s of the recoil).
## bow volley = the same with a slow draw, so it reads as the telegraphed move.
const LIBRARIES := {
	"bow": {"donor": "res://art/characters/studio05/split/body_longbow.glb", "clips": {
		"idle": {"segs": [["lb_idle_01", 0.0, 5.1, 1.0]], "loop": true},
		## the donor's run drifts 0.947 rig units forward through the Hips: stripped, the speed goes to the marks. Baked at 1.15x
		## (2026-11-19) so the archer's 3.8 m/s walk plays inside the view's 0.6-1.4x clamp (at 1.0x it hit the clamp: 6% foot slide).
		## "floor": no flight phase (a mummy never leaves the ground); the trunk hunched 6 deg, the stride widened 20%.
		"run": {"segs": [["lb_run_forward", 0.0, 0.8833333, 1.15]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"amp": {"mixamorig_LeftUpLeg": 1.2, "mixamorig_RightUpLeg": 1.2},
			"lean": {"mixamorig_Spine": [[0.0, 6, 0, 0]], "mixamorig_LeftUpLeg": [[0.0, 0, 0, 3]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -3]]}},
		"shoot": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.35], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
		"volley": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.0], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
		"hit": {"segs": [["lb_react_small_from_front", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["lb_death_forward_01", 0.0, 3.1833, 1.0]], "loop": false},
	}},
	## ---- The mummy family (animator pass 2026-11-19, Boss: "the mummies float and walk with their legs together"). ----
	## Layer keys (see _compose): "amp" scales a bone's swing away from rest (stride width), "calm" damps a donor swing toward rest
	## (a stiff mummy arm), "lean" adds MODEL-space degrees [t, x, y, z] (x+ tips the spine forward / swings an arm back; y+ turns the
	## left shoulder back; z+ tips the spine to the right / swings a limb to the left), "frac" = lean/hover key times are fractions of
	## the clip (seamless loops), "ground" re-plants the feet after the layers ("floor" = one foot ALWAYS on the floor: no flight phase,
	## a heavy grounded gait), a clip "donor" borrows from another player body (same 102-joint rig). The run's travel_per_second is
	## then measured from the planted foot (foot_speed): combat.json run_clip_speed = that value, so the feet do not slide.
	## Picked from contact sheets (tools/monsters/donor_clip_sheet.gd) and hand speed / foot height probes (clip_probe.gd,
	## foot_contact_probe.gd, locomotion_probe.gd); every attack's windup_end / strike_end sits on the donor's hand-speed peak.
	##
	## mummy (the basic undead, MOVESPD +32 = 5.0 m/s, ATKSPD +50): the dead-man LURCH, own library (no longer shared with the knight).
	## run = gs_run_2 (hunched forward run, arms already in front) + a wider stride (thighs x1.25), arm swing damped 70% and both arms
	## raised to reach forward, the trunk hunched 12 deg and rolling 6 deg over the planted foot, the head lolled; floor-planted.
	## attack_1 (mummy_strike 10/4/16) = gs_slash from 0.2 s: both hands raised 0.29-0.57 s, raked down 0.6-0.86 s.
	## attack_2 (mummy_grasp 30/10/34) = gs_attack: arms drawn in, both hands thrust out 0.40-0.60 s (the grab), with a keyed lean back
	## (anticipation) then a lunge forward and the arms lifted into the clutch.
	## hit = gs_impact_2 at 1.5x (doubles over, staggers). death = gs_death_2 (knees buckle, collapses face down), travel kept 40%.
	"mummy": {"donor": "res://art/characters/studio05/split/body_greatsword.glb", "clips": {
		"idle": {"segs": [["gs_idle", 0.0, 2.0166, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 10, 0, 0]], "mixamorig_Head": [[0.0, 8, 0, 10]],
				"mixamorig_LeftArm": [[0.0, -50, 0, 0]], "mixamorig_RightArm": [[0.0, -45, 0, 0]],
				"mixamorig_LeftForeArm": [[0.0, -12, 0, 0]], "mixamorig_RightForeArm": [[0.0, -12, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 4]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -4]]}},
		"run": {"segs": [["gs_run_2", 0.0, 0.6166, 1.2]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"amp": {"mixamorig_LeftUpLeg": 1.45, "mixamorig_RightUpLeg": 1.45, "mixamorig_LeftLeg": 1.15, "mixamorig_RightLeg": 1.15},
			"calm": {"mixamorig_LeftArm": 0.7, "mixamorig_RightArm": 0.7, "mixamorig_LeftForeArm": 0.6, "mixamorig_RightForeArm": 0.6},
			"lean": {"mixamorig_Spine": [[0.0, 12, 0, 4], [0.43, 12, 0, -6], [0.9, 12, 0, 6], [1.0, 12, 0, 4]],
				"mixamorig_Head": [[0.0, 6, 0, 10], [0.5, 10, 0, 5], [1.0, 6, 0, 10]],
				"mixamorig_LeftArm": [[0.0, -60, 0, 0]], "mixamorig_RightArm": [[0.0, -52, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 4]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -4]]}},
		"attack_1": {"segs": [["gs_slash", 0.2, 1.28, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 0.6, "strike_src": 0.86,
			"lean": {"mixamorig_Spine": [[0.0, 8, 0, 0]], "mixamorig_Head": [[0.0, 6, 0, 8]]}},
		"attack_2": {"segs": [["gs_attack", 0.0, 1.2, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 0.4, "strike_src": 0.6,
			"lean": {"mixamorig_Spine": [[0.0, 8, 0, 0], [0.32, -8, 0, 0], [0.45, 22, 0, 0], [0.65, 22, 0, 0], [1.2, 8, 0, 0]],
				"mixamorig_Head": [[0.0, 6, 0, 8], [0.32, -6, 0, 4], [0.45, 8, 0, 0], [1.2, 6, 0, 8]],
				"mixamorig_LeftArm": [[0.0, 0, 0, 0], [0.32, 20, 0, 0], [0.45, -35, 0, 0], [0.7, -35, 0, 0], [1.2, 0, 0, 0]],
				"mixamorig_RightArm": [[0.0, 0, 0, 0], [0.32, 20, 0, 0], [0.45, -35, 0, 0], [0.7, -35, 0, 0], [1.2, 0, 0, 0]]}},
		"hit": {"segs": [["gs_impact_2", 0.0, 1.0, 1.5]], "loop": false, "ground": true, "lean": {"mixamorig_Head": [[0.0, 6, 0, 8]]}},
		"death": {"segs": [["gs_death_2", 0.0, 2.6, 1.0]], "loop": false, "pin_travel": 0.4},
	}},
	## sword_shield = mummy_knight only since 2026-11-19 (MOVESPD -36 = 2.4 m/s, no ATKSPD): the HEAVY STOMP.
	## run = the sword_shield "run" (a slow high-knee march, 1.79 s) at 1.6x: knees lift high and every foot comes down planted
	## (floor), wide stance (thighs out 6 deg), shield arm held still in front, trunk forward 8 deg rolling 5 deg over each stomp.
	## attack_1 (mummy_knight_cleave 26/6/32) = slash from 0.8 s (the idle lead-in cut): blade drawn back over the shoulder
	## 0.8-1.4 s, cut 1.4-1.7 s. attack_2 (mummy_knight_bash 34/6/40) = NEW keyed clip on idle_4: the trunk twists the shield
	## back (0-0.55 s, held to 0.68 s), then drives it forward (0.68-0.8 s) with the arm thrust out, held, settles by 1.6 s.
	"sword_shield": {"donor": "res://art/characters/studio05/split/body_sword_shield.glb", "clips": {
		"idle": {"segs": [["idle_4", 0.0, 6.375, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 4, 0, 0]], "mixamorig_LeftArm": [[0.0, -25, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 5]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -5]]}},
		"run": {"segs": [["run", 0.0, 1.7916, 1.6]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"amp": {"mixamorig_LeftUpLeg": 1.15, "mixamorig_RightUpLeg": 1.15, "mixamorig_LeftLeg": 1.1, "mixamorig_RightLeg": 1.1},
			"calm": {"mixamorig_LeftArm": 0.8, "mixamorig_LeftForeArm": 0.8, "mixamorig_RightArm": 0.4},
			"lean": {"mixamorig_Spine": [[0.0, 8, 0, 5], [0.42, 8, 0, -5], [0.92, 8, 0, 5], [1.0, 8, 0, 5]],
				"mixamorig_LeftArm": [[0.0, -30, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 6]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -6]]}},
		"attack_1": {"segs": [["slash", 0.8, 2.6, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 1.4, "strike_src": 1.7,
			"lean": {"mixamorig_Spine": [[0.0, 4, 0, 0]], "mixamorig_LeftArm": [[0.0, -20, 0, 0]]}},
		"attack_2": {"segs": [["idle_4", 0.0, 1.6, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 0.68, "strike_src": 0.8,
			"lean": {"mixamorig_Spine": [[0.0, 4, 0, 0], [0.55, -10, 32, 0], [0.68, -10, 32, 0], [0.78, 18, -22, 0], [0.95, 18, -22, 0], [1.6, 4, 0, 0]],
				"mixamorig_LeftArm": [[0.0, -25, 0, 0], [0.55, -5, 0, 12], [0.68, -5, 0, 12], [0.78, -82, 0, -8], [0.95, -82, 0, -8], [1.6, -25, 0, 0]],
				"mixamorig_LeftForeArm": [[0.0, 0, 0, 0], [0.55, -45, 0, 0], [0.68, -45, 0, 0], [0.78, -5, 0, 0], [1.6, 0, 0, 0]],
				"mixamorig_RightArm": [[0.0, 0, 0, 0], [0.55, 10, 0, 0], [0.78, 20, 0, 0], [1.6, 0, 0, 0]],
				"mixamorig_Head": [[0.0, 0, 0, 0], [0.55, 6, -12, 0], [0.78, 8, 12, 0], [1.6, 0, 0, 0]]}},
		"hit": {"donor": "res://art/characters/studio05/split/body_greatsword.glb", "segs": [["gs_impact_2", 0.0, 1.0, 1.5]], "loop": false, "ground": true,
			"lean": {"mixamorig_LeftArm": [[0.0, -20, 0, 0]]}},
		"death": {"segs": [["death", 0.4, 4.6, 1.6]], "loop": false},
	}},
	## greatsword = mummy_boss, the Pharaoh (MOVESPD -3 = 3.7 m/s on a 2.6 m body): the REGAL STRIDE.
	## run = gs_run_2 with the trunk pulled UPRIGHT (-10 deg against the donor's forward run), chin up, the khopesh arm held at the
	## side (swing damped), a longer stride (thighs x1.15), always one foot planted, a slow 3 deg roll over each step.
	## attack_1 (mummy_boss_combo 14/5/28, crescent at frame 26) = gs_slash_3 from 0.15 s: raised 0.2-0.5 s, first cut DOWN
	## 0.73-0.87 s (the melee hit), second cut UP 1.0-1.1 s, which the move's recovery reaches at frame 26: the crescent leaves on it.
	## attack_2 (mummy_boss_nova 40/5/40) = gs_jump_attack, travel pinned to 0 (the nova is a box around itself): crouch, leap,
	## slam at 1.07 s (the burst). hit = gs_impact_2 at 1.5x. death = gs_death (falls back, lands by 1.6 s).
	"greatsword": {"donor": "res://art/characters/studio05/split/body_greatsword.glb", "clips": {
		"idle": {"segs": [["gs_idle", 0.0, 2.0166, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, -5, 0, 0]], "mixamorig_Head": [[0.0, -6, 0, 0]]}},
		"run": {"segs": [["gs_run_2", 0.0, 0.6166, 0.8]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"amp": {"mixamorig_LeftUpLeg": 1.4, "mixamorig_RightUpLeg": 1.4, "mixamorig_LeftLeg": 1.1, "mixamorig_RightLeg": 1.1},
			"calm": {"mixamorig_LeftArm": 0.6, "mixamorig_LeftForeArm": 0.5, "mixamorig_RightArm": 0.5, "mixamorig_RightForeArm": 0.4},
			"lean": {"mixamorig_Spine": [[0.0, -10, 0, 2], [0.45, -10, 0, -3], [0.88, -10, 0, 3], [1.0, -10, 0, 2]],
				"mixamorig_Head": [[0.0, -8, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 3]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -3]]}},
		"attack_1": {"segs": [["gs_slash_3", 0.15, 1.8333, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 0.73, "strike_src": 0.87},
		"attack_2": {"segs": [["gs_jump_attack", 0.0, 2.18, 1.0]], "loop": false, "pin_travel": 0.0, "release_in_seg": 0, "release_src": 0.97, "strike_src": 1.17},
		"hit": {"segs": [["gs_impact_2", 0.0, 1.0, 1.5]], "loop": false, "ground": true},
		"death": {"segs": [["gs_death", 0.0, 2.4166, 1.0]], "loop": false},
	}},
	## magic = mummy_mage (MOVESPD -6 = 3.6 m/s): the PRIEST'S SCURRY: mg_lite_run_forward floor-planted (no flight), hunched,
	## head bowed, the free arm stiff and half raised; the staff arm untouched. cast / blink as before (marks on the hand peaks);
	## cast_aoe trimmed to start at 0.5 s so the wind-up is not three times the strike + recovery. hit = the big recoil
	## (mg_lite_react_large_from_front at 1.6x, travel kept 30%). death = mg_lite_react_death_backward.
	"magic": {"donor": "res://art/characters/studio05/split/body_magic.glb", "clips": {
		"idle": {"segs": [["mg_lite_idle", 0.0, 1.8833, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 8, 0, 0]], "mixamorig_Head": [[0.0, 8, 0, -8]]}},
		"run": {"segs": [["mg_lite_run_forward", 0.0, 0.75, 1.3]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"amp": {"mixamorig_LeftUpLeg": 1.25, "mixamorig_RightUpLeg": 1.25},
			"calm": {"mixamorig_LeftArm": 0.6, "mixamorig_LeftForeArm": 0.5},
			"lean": {"mixamorig_Spine": [[0.0, 10, 0, 0]], "mixamorig_Head": [[0.0, 8, 0, -8]], "mixamorig_LeftArm": [[0.0, -35, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 3]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -3]]}},
		"cast": {"segs": [["mg_lite_1h_magic_attack_01", 0.0, 2.1, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.95, "strike_src": 1.15},
		"cast_aoe": {"segs": [["mg_lite_2h_magic_area_attack_02", 0.5, 3.2667, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.75, "strike_src": 2.1},
		"blink": {"segs": [["mg_spell_1h_cast_spell_01", 0.2, 1.4, 2.0]], "loop": false, "release_in_seg": 0, "release_src": 0.76, "strike_src": 0.9},
		"hit": {"segs": [["mg_lite_react_large_from_front", 0.0, 1.3833, 1.6]], "loop": false, "pin_travel": 0.3},
		"death": {"segs": [["mg_lite_react_death_backward", 0.0, 3.6333, 1.0]], "loop": false},
	}},
	## wizard_boss (2026-11-18: mummy_high_wizard, the Boss's own model). Base = the magic donor; the first five clips are copied, the
	## last three are NEW keyframed clips: a donor cast with an ADDITIVE keyed layer ("add": bone -> [[time s, rx, ry, rz degrees]...], eased,
	## multiplied onto the donor rotation in the parent's space; "hover": Hips height keys, rig units) so the boss rises, flings its arms and spins.
	## cast = mg_lite_1h_magic_attack_01 (the bolt). cast_aoe = mg_lite_2h_magic_area_attack_02 (the big ground cast).
	"wizard_boss": {"donor": "res://art/characters/studio05/split/body_magic.glb", "clips": {
		"idle": {"segs": [["mg_lite_idle", 0.0, 1.8833, 1.0]], "loop": true},
		"run": {"segs": [["mg_lite_run_forward", 0.0, 0.75, 1.0]], "loop": true, "strip_travel": true},
		"cast": {"segs": [["mg_lite_1h_magic_attack_01", 0.0, 2.1, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.95, "strike_src": 1.15},
		"cast_aoe": {"segs": [["mg_lite_2h_magic_area_attack_02", 0.0, 3.0, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.75, "strike_src": 2.1},
		"summon": {"segs": [["mg_spell_2h_cast_spell_01", 0.0, 2.18, 0.8]], "loop": false, "release_in_seg": 0, "release_src": 1.0, "strike_src": 1.4,
			"add": {"mixamorig_Spine": [[0.0, 0, 0, 0], [0.9, -14, 0, 0], [1.6, -14, 0, 0], [2.7, 0, 0, 0]],
				"mixamorig_Spine2": [[0.0, 0, 0, 0], [0.9, -12, 0, 0], [1.6, -12, 0, 0], [2.7, 0, 0, 0]],
				"mixamorig_Head": [[0.0, 0, 0, 0], [0.9, -16, 0, 0], [1.6, -16, 0, 0], [2.7, 0, 0, 0]]},
			"hover": [[0.0, 0.0], [1.0, 0.0], [1.5, 0.09], [2.2, 0.09], [2.7, 0.0]]},
		"starfall": {"segs": [["mg_spell_2h_magic_attack_03", 0.0, 4.32, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 2.3, "strike_src": 3.0,
			"add": {"mixamorig_Spine": [[0.0, 0, 0, 0], [1.5, -12, 0, 0], [2.6, -12, 0, 0], [3.4, 6, 0, 0], [4.32, 0, 0, 0]],
				"mixamorig_Head": [[0.0, 0, 0, 0], [1.5, -22, 0, 0], [2.6, -22, 0, 0], [3.4, 8, 0, 0], [4.32, 0, 0, 0]]},
			"hover": [[0.0, 0.0], [1.2, 0.0], [1.9, 0.16], [3.0, 0.16], [3.7, 0.0], [4.32, 0.0]]},
		"sandstorm": {"segs": [["mg_spell_2h_magic_attack_02", 0.0, 2.65, 0.8]], "loop": false, "release_in_seg": 0, "release_src": 1.5, "strike_src": 2.2,
			"add": {"mixamorig_Hips": [[0.0, 0, 0, 0], [0.9, 0, 0, 0], [1.4, 0, 120, 0], [2.4, 0, 560, 0], [3.0, 0, 720, 0], [3.3, 0, 720, 0]]},
			"hover": [[0.0, 0.0], [1.0, 0.0], [1.5, 0.06], [2.6, 0.06], [3.3, 0.0]]},
		"hit": {"segs": [["mg_lite_react_small_from_front", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["mg_lite_react_death_backward", 0.0, 3.6333, 1.0]], "loop": false},
	}},
	## ---- The orc family (2026-11-21, Boss: ONE supplied orc body, every type made from it, each with its OWN animation set). ----
	## Every orc keeps a foot on the floor through its run ("floor"); speeds baked so the type's MOVESPD plays inside the 0.6-1.4x clamp.
	## orc_grunt (cleaver, MOVESPD -12 = 3.3 m/s): the BRUTE SWAGGER. run = the sword_shield march "run" at 2.7x (the knight plays it at 1.6x upright with a
	## still shield arm; run_2 / walk_2 / gs_run drift backward, gs_run_2 is the mummy's), trunk hunched 14 deg and rolling
	## 7 deg over each planted foot, a wide stance (thighs out 6 deg, stride x1.3), both arms held out from the body (gorilla).
	## attack_1 (orc_grunt_chop) = attack_4 from 0.6 s: blade drawn back 0.6-1.0 s, chopped 1.0-1.2 s (hand-speed peak 1.13 s).
	## attack_2 (orc_grunt_cleave) = slash_3 from 1.3 s: the big two-step wind-up, the cut 1.93-2.2 s (peak 2.07 s), with a keyed
	## lunge of the trunk. hit = impact_3 at 1.3x. death = death (falls) at 1.4x. idle = gs_idle hunched, arms out.
	"orc_grunt": {"donor": "res://art/characters/studio05/split/body_sword_shield.glb", "clips": {
		"idle": {"donor": "res://art/characters/studio05/split/body_greatsword.glb", "segs": [["gs_idle", 0.0, 2.0166, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 12, 0, 0]], "mixamorig_Head": [[0.0, -8, 0, 0]],
				"mixamorig_LeftArm": [[0.0, 0, 0, 14]], "mixamorig_RightArm": [[0.0, 0, 0, -14]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 6]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -6]]}},
		"run": {"segs": [["run", 0.0, 1.7916, 2.7]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"upright": [[0.0, 16]],
			"amp": {"mixamorig_LeftUpLeg": 1.35, "mixamorig_RightUpLeg": 1.35, "mixamorig_LeftLeg": 1.1, "mixamorig_RightLeg": 1.1},
			"calm": {"mixamorig_LeftArm": 0.6, "mixamorig_RightArm": 0.6, "mixamorig_LeftForeArm": 0.3, "mixamorig_RightForeArm": 0.3},
			"lean": {"mixamorig_Spine": [[0.0, 2, 0, 7], [0.5, 2, 0, -7], [1.0, 2, 0, 7]],
				"mixamorig_Head": [[0.0, -6, 0, -4], [0.5, -6, 0, 4], [1.0, -6, 0, -4]],
				"mixamorig_LeftArm": [[0.0, 0, 0, 14]], "mixamorig_RightArm": [[0.0, 0, 0, -14]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 6]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -6]]},
			"swing": {"mixamorig_LeftArm": [-30, 0.74, 0], "mixamorig_RightArm": [-24, 0.24, 0]},
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5}},
		"attack_1": {"segs": [["attack_4", 0.6, 2.0, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 1.0, "strike_src": 1.2,
			"shrug": {"mixamorig_LeftShoulder": 0.6, "mixamorig_RightShoulder": 0.6},
			"lean": {"mixamorig_Spine": [[0.0, 10, 0, 0]], "mixamorig_LeftArm": [[0.0, 0, 0, 12]]}},
		"attack_2": {"segs": [["slash_3", 1.3, 3.6, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 1.93, "strike_src": 2.2,
			"shrug": {"mixamorig_LeftShoulder": 0.6, "mixamorig_RightShoulder": 0.6},
			"lean": {"mixamorig_Spine": [[0.0, 8, 0, 0], [0.55, -6, 0, 0], [0.8, 24, 0, 0], [1.3, 24, 0, 0], [2.3, 8, 0, 0]],
				"mixamorig_Head": [[0.0, -6, 0, 0], [0.8, -14, 0, 0], [2.3, -6, 0, 0]]}},
		"hit": {"segs": [["impact_3", 0.0, 1.7916, 1.3]], "loop": false, "ground": true},
		"death": {"segs": [["death", 0.4, 4.6, 1.4]], "loop": false},
	}},
	## orc_bow = orc_archer (MOVESPD -12 = 3.3 m/s): the HUNTER'S PROWL. run = lb_run_forward at 1.55x, the head kept low and level (trunk 6 deg
	## forward on top of the donor's own run lean: 18 deg folded the short orc double), stride x1.2, the bow arm held low in front. shoot / volley = the
	## player's own two-part shot as the bow library (released at 0.18 s of the recoil). hit = lb_react_small_from_headshot.
	## death = lb_death_backward_01 (the mummy archer falls forward). idle = lb_idle_02_looking (scans around).
	"orc_bow": {"donor": "res://art/characters/studio05/split/body_longbow.glb", "clips": {
		"idle": {"segs": [["lb_idle_02_looking", 0.0, 3.2, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 8, 0, 0]], "mixamorig_Head": [[0.0, -6, 0, 0]]}},
		"run": {"segs": [["lb_run_forward", 0.0, 0.8833333, 1.55]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"upright": [[0.0, 22]],
			"amp": {"mixamorig_LeftUpLeg": 1.25, "mixamorig_RightUpLeg": 1.25, "mixamorig_LeftLeg": 1.2, "mixamorig_RightLeg": 1.2},
			"calm": {"mixamorig_LeftArm": 0.5, "mixamorig_LeftForeArm": 0.3, "mixamorig_RightArm": 0.5, "mixamorig_RightForeArm": 0.3},
			"lean": {"mixamorig_Spine": [[0.0, -8, 0, 0]], "mixamorig_Head": [[0.0, -4, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 3]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -3]]},
			"swing": {"mixamorig_LeftArm": [14, 0.25, 0], "mixamorig_RightArm": [-28, 0.25, 0]},
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5}},
		"shoot": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.35], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
		"volley": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.0], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
		"hit": {"segs": [["lb_react_small_from_headshot", 0.0, 0.9833, 1.0]], "loop": false},
		"death": {"segs": [["lb_death_backward_01", 0.0, 3.1166, 1.0]], "loop": false},
	}},
	## orc_magic = orc_mage (MOVESPD -18 = 3.1 m/s): the SHAMAN'S WADDLE. run = mg_loco_run_forward at 1.25x with a wide stance and a
	## big side-to-side roll over each foot (8 deg), the head bobbing, the free arm swinging out; floor-planted.
	## cast = mg_spell_1h_magic_attack_02 (a quick one-hand throw, peak 0.53 s). cast_aoe = mg_spell_2h_magic_area_attack_01 (both
	## arms raised, slammed down at 1.27 s). blink = mg_spell_2h_cast_spell_01 at 2x. hit = mg_lite_react_small_from_front at 1.2x.
	## death = mg_lite_react_death_backward.
	"orc_magic": {"donor": "res://art/characters/studio05/split/body_magic.glb", "clips": {
		"idle": {"segs": [["mg_spell_idle", 0.0, 1.8833, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 10, 0, 0]], "mixamorig_Head": [[0.0, -6, 0, 0]]}},
		"run": {"segs": [["mg_loco_run_forward", 0.0, 0.75, 1.25]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"upright": [[0.0, 8]],
			"amp": {"mixamorig_LeftUpLeg": 1.3, "mixamorig_RightUpLeg": 1.3, "mixamorig_LeftLeg": 1.15, "mixamorig_RightLeg": 1.15},
			"calm": {"mixamorig_RightArm": 0.5, "mixamorig_RightForeArm": 0.5},
			"lean": {"mixamorig_Spine": [[0.0, 6, 0, 8], [0.5, 6, 0, -8], [1.0, 6, 0, 8]],
				"mixamorig_Head": [[0.0, -6, 0, -6], [0.25, -9, 0, 0], [0.5, -6, 0, 6], [0.75, -9, 0, 0], [1.0, -6, 0, -6]],
				"mixamorig_LeftArm": [[0.0, -6, 0, 16]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 7]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -7]]},
			"swing": {"mixamorig_LeftArm": [-22, 0.8, 0]},
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5}},
		"cast": {"segs": [["mg_spell_1h_magic_attack_02", 0.0, 1.6, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.4, "strike_src": 0.53,
			"shrug": {"mixamorig_LeftShoulder": 0.6, "mixamorig_RightShoulder": 0.6}},
		"cast_aoe": {"segs": [["mg_spell_2h_magic_area_attack_01", 0.0, 2.9666, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.13, "strike_src": 1.27,
			"shrug": {"mixamorig_LeftShoulder": 0.6, "mixamorig_RightShoulder": 0.6}},
		"blink": {"segs": [["mg_spell_2h_cast_spell_01", 0.2, 1.4, 2.0]], "loop": false, "release_in_seg": 0, "release_src": 0.55, "strike_src": 0.67,
			"shrug": {"mixamorig_LeftShoulder": 0.6, "mixamorig_RightShoulder": 0.6}},
		"hit": {"segs": [["mg_lite_react_small_from_front", 0.0, 1.2, 1.2]], "loop": false},
		"death": {"segs": [["mg_lite_react_death_backward", 0.0, 3.6333, 1.0]], "loop": false},
	}},
	## orc_warlock = the Orc Camp BOSS (Boss 2026-11-21: its own FBX, sword and shield; "reuse OUR sword & shield player set, only SOME
	## clips, the flashiest: grand skills and a brutal, over-the-top BLOCK"). Every clip comes from the player's Sword & Shield body.
	## run = the REGAL BRUTE WALK: the sword_shield march "run" at 1.8x, pelvis straightened 18 deg, chest out, chin up, a long stride
	## (thighs x1.3) with the knees lifted (shins x1.15: no dragging feet), every step planted ("floor"), a slow 3 deg roll, the shield
	## held across the body, the sword arm swinging low and heavy.
	## idle = idle_4 (shield up, steady) upright, chin up, wide stance.
	## attack_1 (orc_warlock_cleave) = slash from 0.4 s: blade drawn back over the shoulder, cut 1.4-1.7 s, a keyed trunk lunge.
	## skyfall (orc_warlock_skyfall) = attack_2, the player's own ULTIMATE: the run-up, the LEAP (keyed hover: the hips rise 0.15 rig units
	## over 0.7-1.15 s) and the overhead smash landing at 1.33 s (hand-speed peak); the ground travel goes to the sim's dash.
	## cataclysm (orc_warlock_cataclysm) = slash_4, the player's Breaker Slam, at 1.25x: the rising spin into the air (+ a keyed 0.08 hover
	## at the apex), then the sword driven into the ground (peak 3.33 s source), held low, rises.
	## block (orc_warlock_bulwark) = block (the shield slammed up, 1.4x) then block_idle held, with a keyed over-the-top layer: a hop and a
	## STOMP into a wide, low stance (thighs out 12 deg), the trunk thrown 14 deg into the shield, the shield arm driven forward, the head
	## tucked behind the rim. hit = impact at 1.4x. death = death_2 at 2.6x (sword lowered, drops to the knees, topples face down).
	"orc_warlock": {"donor": "res://art/characters/studio05/split/body_sword_shield.glb", "clips": {
		"idle": {"segs": [["idle_4", 0.0, 6.375, 1.0]], "loop": true, "ground": true,
			"lean": {"mixamorig_Spine": [[0.0, -4, 0, 0]], "mixamorig_Head": [[0.0, -8, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 6]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -6]]}},
		"run": {"segs": [["run", 0.0, 1.7916, 1.8]], "loop": true, "strip_travel": true, "frac": true, "ground": "floor",
			"upright": [[0.0, 18]],
			"amp": {"mixamorig_LeftUpLeg": 1.3, "mixamorig_RightUpLeg": 1.3, "mixamorig_LeftLeg": 1.15, "mixamorig_RightLeg": 1.15},
			"calm": {"mixamorig_LeftArm": 0.8, "mixamorig_LeftForeArm": 0.8, "mixamorig_RightArm": 0.5, "mixamorig_RightForeArm": 0.4},
			"lean": {"mixamorig_Spine": [[0.0, -4, 0, 3], [0.5, -4, 0, -3], [1.0, -4, 0, 3]],
				"mixamorig_Head": [[0.0, -8, 0, 0]],
				"mixamorig_LeftArm": [[0.0, -25, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 5]], "mixamorig_RightUpLeg": [[0.0, 0, 0, -5]]},
			"swing": {"mixamorig_RightArm": [-16, 0.74, 0]},
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5}},
		"attack_1": {"segs": [["slash", 0.4, 2.6, 1.0]], "loop": false, "ground": true, "release_in_seg": 0, "release_src": 1.4, "strike_src": 1.7,
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5},
			"lean": {"mixamorig_Spine": [[0.0, 0, 0, 0], [0.9, -8, 0, 0], [1.3, 16, 0, 0], [1.8, 6, 0, 0], [2.2, 0, 0, 0]]}},
		"skyfall": {"segs": [["attack_2", 0.0, 3.29, 1.0]], "loop": false, "pin_travel": 0.0, "release_in_seg": 0, "release_src": 1.15, "strike_src": 1.4,
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5},
			"hover": [[0.0, 0.0], [0.7, 0.0], [0.95, 0.15], [1.15, 0.13], [1.35, 0.0], [3.29, 0.0]]},
		"cataclysm": {"segs": [["slash_4", 0.43, 5.6, 1.25]], "loop": false, "pin_travel": 0.0, "release_in_seg": 0, "release_src": 3.13, "strike_src": 3.53,
			"shrug": {"mixamorig_LeftShoulder": 0.5, "mixamorig_RightShoulder": 0.5},
			"hover": [[0.0, 0.0], [1.0, 0.0], [1.6, 0.08], [2.1, 0.08], [2.4, 0.0], [4.14, 0.0]]},
		"block": {"segs": [["block", 0.0, 1.4583, 1.4], ["block_idle", 0.0, 2.4, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.45, "strike_src": 0.75,
			"ground": true,
			"lean": {"mixamorig_Spine": [[0.0, 0, 0, 0], [0.25, -8, 0, 0], [0.5, 14, -10, 0], [3.44, 14, -10, 0]],
				"mixamorig_Head": [[0.0, 0, 0, 0], [0.5, 10, 0, 0], [3.44, 10, 0, 0]],
				"mixamorig_LeftArm": [[0.0, 0, 0, 0], [0.25, 10, 0, 0], [0.5, -22, 0, 0], [3.44, -22, 0, 0]],
				"mixamorig_LeftUpLeg": [[0.0, 0, 0, 0], [0.5, 0, 0, 12], [3.44, 0, 0, 12]], "mixamorig_RightUpLeg": [[0.0, 0, 0, 0], [0.5, 0, 0, -12], [3.44, 0, 0, -12]]},
			"hover": [[0.0, 0.0], [0.25, 0.05], [0.5, 0.0], [3.44, 0.0]]},
		"hit": {"segs": [["impact", 0.0, 1.9583, 1.4]], "loop": false, "ground": true},
		"death": {"segs": [["death_2", 0.0, 8.3, 2.6]], "loop": false},
	}},
}
## Optional sway tracks for the loose-bandage bones of a mummy (name -> parent donor bone). A monster without them ignores the tracks.
const EXTRA_BONES := {"bandage_upper_L": "mixamorig_LeftArm", "bandage_upper_R": "mixamorig_RightArm", "bandage_lower_L": "mixamorig_LeftForeArm", "bandage_lower_R": "mixamorig_RightForeArm"}


func _init() -> void:
	var args := OS.get_cmdline_user_args()  ## [stance...] [--out=res://dir/] [--tol=<degrees>]
	var out_dir := "res://art/animations/"
	var stances := []
	for arg in args:
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--tol="):
			Rig.rot_tol = deg_to_rad(float(arg.substr(6)))
		else:
			stances.append(arg)
	if stances.is_empty():
		stances = ["bow"]
	var donor := Rig.load_donor()
	var src_skeleton := Rig.donor_skeleton(donor)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for stance in stances:
		var spec: Dictionary = LIBRARIES[stance]
		var stance_donor := (load(spec["donor"]) as PackedScene).instantiate()
		_build("monster_clips_" + stance, out_dir, spec["clips"], src_skeleton, Rig.donor_player(stance_donor))
		stance_donor.free()
	for d in _donors.values():
		d.free()
	donor.free()
	quit()


## Other donor bodies a clip borrows from ("donor" on a clip), loaded once.
var _donors := {}
var _rest_skeleton: Skeleton3D


func _player_for(spec: Dictionary, fallback: AnimationPlayer) -> AnimationPlayer:
	if not spec.has("donor"):
		return fallback
	var path: String = spec["donor"]
	if not _donors.has(path):
		_donors[path] = (load(path) as PackedScene).instantiate()
	return Rig.donor_player(_donors[path])


func _build(file_name: String, out_dir: String, clips: Dictionary, src_skeleton: Skeleton3D, player: AnimationPlayer) -> void:
	var root := Node3D.new()
	root.name = "monster_clips"
	var rig := Node3D.new()
	rig.name = "rig"
	root.add_child(rig)
	var skeleton := Rig.copy_skeleton(src_skeleton)
	_rest_skeleton = Rig.copy_skeleton(src_skeleton)
	# The optional loose-bandage bones (a mummy's extra bones) hang from the arms.
	for extra in EXTRA_BONES:
		var index := skeleton.get_bone_count()
		skeleton.add_bone(extra)
		skeleton.set_bone_parent(index, skeleton.find_bone(EXTRA_BONES[extra]))
		skeleton.set_bone_rest(index, Transform3D(Basis(), Vector3(0, -0.02, -0.03)))
	skeleton.reset_bone_poses()
	rig.add_child(skeleton)
	# A skeleton with no skin is imported as plain nodes (tracks without bone names): one tiny skinned triangle, weighted to the
	# Root joint and binding every joint, makes the importer build a real Skeleton3D (as the goblin libraries have).
	var skin := Skin.new()
	for i in skeleton.get_bone_count():
		skin.add_named_bind(skeleton.get_bone_name(i), skeleton.get_bone_global_rest(i).affine_inverse())
	var tri_arrays := []
	tri_arrays.resize(Mesh.ARRAY_MAX)
	tri_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(0.001, 0, 0), Vector3(0, 0.001, 0)])
	tri_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	tri_arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	tri_arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	tri_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var tri_mesh := ArrayMesh.new()
	tri_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tri_arrays)
	var anchor := MeshInstance3D.new()
	anchor.name = "skin_anchor"
	anchor.mesh = tri_mesh
	anchor.skin = skin
	skeleton.add_child(anchor)
	anchor.skeleton = NodePath("..")
	anchor.owner = root
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	var library := AnimationLibrary.new()
	var marks := {}
	var bones_used := {}
	for clip in clips:
		var built := _compose(clip, clips[clip], _player_for(clips[clip], player))
		var animation: Animation = built["animation"]
		library.add_animation(clip, animation)
		marks[clip] = built["marks"]
		for t in animation.get_track_count():
			bones_used[String(animation.track_get_path(t).get_concatenated_subnames())] = true
	anim_player.add_animation_library("", library)
	for node in [rig, skeleton, anim_player]:
		node.owner = root
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var err := document.append_from_scene(root, state)
	if err == OK:
		err = document.write_to_filesystem(state, out_dir + file_name + ".glb")
	if err == OK:
		Rig.minify_glb(out_dir + file_name + ".glb")
	print(file_name, ": export err=", err, " bones animated=", bones_used.size())
	var json_text := JSON.stringify(marks, "  ")
	var file := FileAccess.open(out_dir + file_name + ".json", FileAccess.WRITE)
	file.store_string(json_text + "\n")
	file.close()
	root.free()
	_rest_skeleton.free()


## A monster gets the body, not the player's hair (secondary motion baked into the clips) or finger tracks
## (monster hands deform as one piece, so 40 finger tracks per clip would only cost file size).
static func _wanted(bone: String) -> bool:
	return not bone.begins_with("hair_") and not (bone.contains("Hand") and bone.length() > 17 and bone[-1].is_valid_int())


## One clip: the segments baked at 30 fps in order; Hips travel scaled; the optional tail sway added to idle/run.
func _compose(clip: String, spec: Dictionary, player: AnimationPlayer) -> Dictionary:
	var segs: Array = spec["segs"]
	var starts := []
	var total := 0.0
	for seg in segs:
		starts.append(total)
		total += (float(seg[2]) - float(seg[1])) / float(seg[3])
	var frames := int(round(total * Rig.FPS))
	var times := []
	for f in frames + 1:
		times.append(minf(f / Rig.FPS, total))
	if absf(float(times[-1]) - total) > 0.0001:
		times.append(total)
	var out := Animation.new()
	out.length = total
	out.loop_mode = Animation.LOOP_LINEAR if spec["loop"] else Animation.LOOP_NONE
	# The tracks of the first segment's clip are the same bones for every donor clip.
	var first: Animation = player.get_animation(segs[0][0])
	var path_of := {}
	for t in first.get_track_count():
		path_of[String(first.track_get_path(t).get_concatenated_subnames()) + "|" + str(first.track_get_type(t))] = first.track_get_path(t)
	var tracks_per_seg := []
	for seg in segs:
		tracks_per_seg.append(Rig.clip_tracks(player.get_animation(seg[0])))
	var bones: Array = tracks_per_seg[0].keys()
	var travel := 0.0
	var rot_of := {}  ## bone -> baked rotations (one per time)
	var pos_of := {}  ## bone -> baked positions (bones with a position track)
	var rot_t := times
	for bone in bones:
		if not _wanted(bone):
			continue
		var has_pos: bool = tracks_per_seg[0][bone]["pos"] >= 0
		var rot_v := []
		var pos_v := []
		rot_of[bone] = rot_v
		if has_pos:
			pos_of[bone] = pos_v
		for time in times:
			var s := segs.size() - 1
			for k in segs.size():
				if time < float(starts[k]) + (float(segs[k][2]) - float(segs[k][1])) / float(segs[k][3]) - 0.00001:
					s = k
					break
			var src_time: float = float(segs[s][1]) + (time - float(starts[s])) * float(segs[s][3])
			src_time = clampf(src_time, 0.0, player.get_animation(segs[s][0]).length)
			var anim: Animation = player.get_animation(segs[s][0])
			var tr: Dictionary = tracks_per_seg[s][bone]
			var q: Quaternion = anim.rotation_track_interpolate(tr["rot"], src_time)
			if spec.has("amp") and (spec["amp"] as Dictionary).has(bone):
				# the swing away from the rest pose scaled (1.3 = a 30% wider stride, 0.5 = half the arm swing)
				var rest := _rest_rotation(bone)
				var delta := rest.inverse() * q
				if delta.w < 0.0:
					delta = -delta
				var angle := delta.get_angle()
				if angle > 0.0001:
					q = rest * Quaternion(delta.get_axis().normalized(), angle * float(spec["amp"][bone]))
			if spec.has("add") and (spec["add"] as Dictionary).has(bone):
				q = _layer(spec["add"][bone], time) * q
			if spec.has("calm") and (spec["calm"] as Dictionary).has(bone):
				# swing damped toward the rest pose (1 = frozen at rest, 0 = the donor's own swing)
				q = _rest_rotation(bone).slerp(q, 1.0 - float(spec["calm"][bone]))
			if spec.has("lean") and (spec["lean"] as Dictionary).has(bone):
				# MODEL-space layer: degrees about the model's own x (right), y (up), z (forward) axes at the bone's pivot,
				# as if the parent stood in its rest pose: +x tips an upward bone forward and -x swings a hanging arm forward;
				# +z tips an upward bone toward -x and swings a hanging limb toward +x (the LEFT side). "frac": key times are
				# fractions of the clip (a loop whose keys repeat at 0 and 1 stays seamless at any baked speed).
				var parent_rest := _parent_global_rest(bone)
				var key_time: float = time / total if spec.get("frac", false) else time
				q = parent_rest.inverse() * _layer(spec["lean"][bone], key_time) * parent_rest * q
			if spec.has("swing") and (spec["swing"] as Dictionary).has(bone):
				# a smooth MODEL-space x swing (same axes as "lean"): [amplitude deg, clip fraction of the peak, offset deg];
				# angle = offset + amplitude * cos(2 pi (fraction - peak)). Arms swung against the legs (a real run's counter-swing).
				var sw: Array = spec["swing"][bone]
				var frac_t: float = time / total
				var deg: float = float(sw[2]) + float(sw[0]) * cos(TAU * (frac_t - float(sw[1])))
				var pr := _parent_global_rest(bone)
				q = pr.inverse() * Quaternion(Vector3.RIGHT, deg_to_rad(deg)) * pr * q
			rot_v.append(q)
			if has_pos:
				pos_v.append(anim.position_track_interpolate(tr["pos"], src_time))
	# "upright": [[t, degrees]...] tips the PELVIS back (model x axis) by that many degrees while both thighs keep their model-space
	# direction exactly (the legs do not swing forward with it): straightens a donor run that is folded forward at the hips
	# without changing the stride (Boss 2026-11-21: "the orc run looks like crawling").
	if spec.has("upright") and rot_of.has("mixamorig_Hips"):
		var pr := _parent_global_rest("mixamorig_Hips")
		for i in times.size():
			var key_time: float = float(times[i]) / total if spec.get("frac", false) else float(times[i])
			var deg := _ease_keys(spec["upright"], key_time)
			var lh := pr.inverse() * Quaternion(Vector3.RIGHT, deg_to_rad(-deg)) * pr
			var qh: Quaternion = rot_of["mixamorig_Hips"][i]
			var qh2 := (lh * qh).normalized()
			rot_of["mixamorig_Hips"][i] = qh2
			for leg in ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]:
				if rot_of.has(leg):
					rot_of[leg][i] = (qh2.inverse() * qh * (rot_of[leg][i] as Quaternion)).normalized()
	# "shrug": {shoulder bone: fraction} hands that fraction of the clavicle's swing away from rest over to the upper arm, so the
	# arm still points exactly where the donor's does while the clavicle (and the shoulder pad / vest top skinned to it) stays
	# lower: an arm raised overhead no longer lifts the whole shoulder shell with it (Boss 2026-11-21, the orc pads).
	if spec.has("shrug"):
		for shoulder: String in spec["shrug"]:
			var arm := shoulder.replace("Shoulder", "Arm")
			if not rot_of.has(shoulder) or not rot_of.has(arm):
				continue
			var rest := _rest_rotation(shoulder)
			var keep := 1.0 - float(spec["shrug"][shoulder])
			for i in times.size():
				var qs: Quaternion = rot_of[shoulder][i]
				var qs2 := rest.slerp(qs, keep)
				rot_of[arm][i] = (qs2.inverse() * qs * (rot_of[arm][i] as Quaternion)).normalized()
				rot_of[shoulder][i] = qs2
	# "ground": the layers above lengthen or bend the legs; the Hips height is moved so the lower foot stays exactly as high
	# as the donor's own lower foot at that moment (planted feet stay planted, nothing sinks into or floats over the floor).
	# "ground": "floor" keeps the lower foot ON the floor every frame (the donor's lowest foot height): a run loses its flight
	# phase and becomes a heavy, always-grounded gait (nothing hangs in the air: the cure for a floating walk).
	if typeof(spec.get("ground", false)) != TYPE_BOOL or spec.get("ground", false):
		var donor_feet := _feet_low(player, segs, starts, times, tracks_per_seg)
		var floor_y: float = donor_feet.min()
		for i in times.size():
			var low := _low_foot(rot_of, pos_of, i)
			var v: Vector3 = pos_of["mixamorig_Hips"][i]
			v.y += (floor_y if str(spec["ground"]) == "floor" else float(donor_feet[i])) - low
			pos_of["mixamorig_Hips"][i] = v
	if spec.has("hover") and pos_of.has("mixamorig_Hips"):
		for i in times.size():
			var v: Vector3 = pos_of["mixamorig_Hips"][i]
			v.y += _ease_keys(spec["hover"], float(times[i]) / total if spec.get("frac", false) else float(times[i]))
			pos_of["mixamorig_Hips"][i] = v
	var foot_speed := 0.0
	if spec.get("strip_travel", false):
		foot_speed = _planted_foot_speed(rot_of, pos_of, times)
	for bone in bones:
		if not rot_of.has(bone):
			continue
		var has_pos: bool = pos_of.has(bone)
		var rot_v: Array = rot_of[bone]
		var pos_v: Array = pos_of.get(bone, [])
		if has_pos and spec.get("strip_travel", false):
			var drift: float = (pos_v[-1] as Vector3).z - (pos_v[0] as Vector3).z
			travel = drift
			for i in pos_v.size():
				var v: Vector3 = pos_v[i]
				v.z -= drift * float(rot_t[i]) / total
				pos_v[i] = v
		if has_pos and spec.has("pin_travel"):
			# an attack that lunges far: the Hips' ground travel (x, z) is cut to the kept fraction, height untouched
			var keep := float(spec["pin_travel"])
			var start: Vector3 = pos_v[0]
			for i in pos_v.size():
				var v: Vector3 = pos_v[i]
				pos_v[i] = Vector3(start.x + (v.x - start.x) * keep, v.y, start.z + (v.z - start.z) * keep)
		var rot_reduced := Rig.reduce_keys(rot_t, rot_v, true)
		var path := NodePath("rig/Skeleton3D:" + bone)
		var rt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, path)
		for i in rot_reduced[0].size():
			out.rotation_track_insert_key(rt, rot_reduced[0][i], rot_reduced[1][i])
		if has_pos:
			var pos_reduced := Rig.reduce_keys(rot_t, pos_v, false)
			var pt := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(pt, path)
			for i in pos_reduced[0].size():
				out.position_track_insert_key(pt, pos_reduced[0][i], pos_reduced[1][i])
	if clip == "idle" or clip == "run":
		_add_tail_sway(out, total, 0.07 if clip == "idle" else 0.16, 3.0 if clip == "idle" else 1.0)
	var meta := {"length": snappedf(total, 0.0001), "loop": bool(spec["loop"])}
	if travel != 0.0:
		meta["travel_per_second"] = snappedf(travel / total, 0.001)  ## rig units per second at the donor's size
	if foot_speed > 0.0:
		## how fast the PLANTED foot slides back under the Hips (rig units/s at the donor's size): the ground speed at which the
		## feet do not slide. Equals travel_per_second for an untouched donor; differs once a stride layer changes the legs.
		meta["foot_speed"] = snappedf(foot_speed, 0.001)
		if spec.has("amp") or spec.has("lean") or spec.has("ground"):
			meta["travel_per_second"] = meta["foot_speed"]
	var key_count := 0
	for t in out.get_track_count():
		key_count += out.track_get_key_count(t)
	print("  clip ", clip, " length=", snappedf(total, 0.001), " tracks=", out.get_track_count(), " keys=", key_count)
	if spec.has("release_in_seg"):
		var k: int = spec["release_in_seg"]
		var seg_start: float = float(starts[k])
		var from: float = float(segs[k][1])
		var speed: float = float(segs[k][3])
		meta["windup_end"] = snappedf(seg_start + (float(spec["release_src"]) - from) / speed, 0.0001)
		meta["strike_end"] = snappedf(seg_start + (float(spec["strike_src"]) - from) / speed, 0.0001)
	return {"animation": out, "marks": meta}


## Model-space position of `bone` at frame i of baked tracks (bones without a track keep their rest).
func _fk(bone: String, rot_of: Dictionary, pos_of: Dictionary, i: int, hips_shift: Vector3 = Vector3.ZERO) -> Vector3:
	var index := _rest_skeleton.find_bone(bone)
	var chain := []
	while index >= 0:
		chain.push_front(index)
		index = _rest_skeleton.get_bone_parent(index)
	var t := Transform3D.IDENTITY
	for b in chain:
		var name := _rest_skeleton.get_bone_name(b)
		var rest := _rest_skeleton.get_bone_rest(b)
		var q: Quaternion = rot_of[name][i] if rot_of.has(name) else rest.basis.get_rotation_quaternion()
		var p: Vector3 = pos_of[name][i] if pos_of.has(name) else rest.origin
		if name == "mixamorig_Hips":
			p += hips_shift
		t = t * Transform3D(Basis(q), p)
	return t.origin


func _low_foot(rot_of: Dictionary, pos_of: Dictionary, i: int) -> float:
	return minf(_fk("mixamorig_LeftFoot", rot_of, pos_of, i).y, _fk("mixamorig_RightFoot", rot_of, pos_of, i).y)


## The donor's own lower-foot height per frame (the clip without any layer).
func _feet_low(player: AnimationPlayer, segs: Array, starts: Array, times: Array, tracks_per_seg: Array) -> Array:
	var raw_rot := {}
	var raw_pos := {}
	for bone in ["mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"]:
		raw_rot[bone] = []
		for time in times:
			var s := segs.size() - 1
			for k in segs.size():
				if time < float(starts[k]) + (float(segs[k][2]) - float(segs[k][1])) / float(segs[k][3]) - 0.00001:
					s = k
					break
			var anim: Animation = player.get_animation(segs[s][0])
			var src_time := clampf(float(segs[s][1]) + (time - float(starts[s])) * float(segs[s][3]), 0.0, anim.length)
			var tr: Dictionary = tracks_per_seg[s][bone]
			raw_rot[bone].append(anim.rotation_track_interpolate(tr["rot"], src_time))
			if tr["pos"] >= 0:
				if not raw_pos.has(bone):
					raw_pos[bone] = []
				raw_pos[bone].append(anim.position_track_interpolate(tr["pos"], src_time))
	var out := []
	for i in times.size():
		out.append(_low_foot(raw_rot, raw_pos, i))
	return out


## Speed (rig units/s) at which the planted foot slides backward once the Hips' forward drift is stripped: the ground speed the
## clip shows without foot sliding. A foot counts as planted while it is the lower foot and within 1.5 cm (rig) of its lowest.
func _planted_foot_speed(rot_of: Dictionary, pos_of: Dictionary, times: Array) -> float:
	var n := times.size()
	var total: float = times[-1]
	var drift: float = (pos_of["mixamorig_Hips"][n - 1] as Vector3).z - (pos_of["mixamorig_Hips"][0] as Vector3).z
	var feet := {"mixamorig_LeftFoot": [], "mixamorig_RightFoot": []}
	for i in n:
		var shift := Vector3(0, 0, -drift * float(times[i]) / total)
		for foot in feet:
			feet[foot].append(_fk(foot, rot_of, pos_of, i, shift))
	var lowest := INF
	for foot in feet:
		for p in feet[foot]:
			lowest = minf(lowest, (p as Vector3).y)
	# the median backward speed of the lower foot (frames where it is on the ground): robust to the short moments of a
	# floor-planted gait where the lower foot is still swinging (those slide whatever the speed; the shots show them)
	var speeds := []
	for i in range(1, n):
		for foot in feet:
			var a: Vector3 = feet[foot][i - 1]
			var b: Vector3 = feet[foot][i]
			var other: Vector3 = feet["mixamorig_RightFoot" if foot == "mixamorig_LeftFoot" else "mixamorig_LeftFoot"][i]
			if b.y <= other.y and b.y < lowest + 0.015 and a.y < lowest + 0.015:
				speeds.append(-(b.z - a.z) / (float(times[i]) - float(times[i - 1])))
	if speeds.is_empty():
		return 0.0
	speeds.sort()
	return float(speeds[speeds.size() / 2])


func _rest_rotation(bone: String) -> Quaternion:
	return _rest_skeleton.get_bone_rest(_rest_skeleton.find_bone(bone)).basis.get_rotation_quaternion()


## The rest rotation of the bone's parent in model space (the chain of rest rotations from the root).
func _parent_global_rest(bone: String) -> Quaternion:
	var q := Quaternion.IDENTITY
	var p := _rest_skeleton.get_bone_parent(_rest_skeleton.find_bone(bone))
	while p >= 0:
		q = _rest_skeleton.get_bone_rest(p).basis.get_rotation_quaternion() * q
		p = _rest_skeleton.get_bone_parent(p)
	return q


## Eased value of keys [[t, v]...] at time t (smoothstep between keys, held outside).
static func _ease_keys(keys: Array, t: float) -> float:
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var a: float = keys[i - 1][0]
			var b: float = keys[i][0]
			var w := smoothstep(0.0, 1.0, (t - a) / maxf(b - a, 0.0001))
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), w)
	return float(keys[-1][1])


## The additive rotation of a layer at time t: keys [[t, rx, ry, rz degrees]...], each component eased.
static func _layer(keys: Array, t: float) -> Quaternion:
	var c := []
	for k in 3:
		c.append(_ease_keys(keys.map(func(key): return [key[0], key[k + 1]]), t))
	return Quaternion.from_euler(Vector3(deg_to_rad(c[0]), deg_to_rad(c[1]), deg_to_rad(c[2])))


## The tail sways with a wave running down its three bones (a new, monster-only track set).
func _add_tail_sway(out: Animation, total: float, amplitude: float, cycles_per_clip: float) -> void:
	var steps := 24
	var names := EXTRA_BONES.keys()
	for i in names.size():
		var track := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(track, NodePath("rig/Skeleton3D:" + names[i]))
		for s in steps + 1:
			var phase := float(s) / steps * TAU * cycles_per_clip - i * 0.9
			out.rotation_track_insert_key(track, total * s / steps, Quaternion(Vector3.RIGHT, amplitude * sin(phase)) * Quaternion(Vector3.FORWARD, amplitude * 0.5 * sin(phase * 0.5)))


