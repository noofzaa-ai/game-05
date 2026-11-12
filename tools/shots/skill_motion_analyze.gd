extends SceneTree
## Numeric pass for the class-skill motion preview: per clip, at 60 Hz, the world positions of the feet,
## hips, hands and head on the in-game studio05 model (hips held in place as in the game), written to
## build/skill_motion_preview/data/<clip>.csv. Also the pose gap (cm) between the class idle and each
## skill window's first / last frame. Run (headless is fine for numbers):
## godot --headless --path . --script res://tools/shots/skill_motion_analyze.gd
const ItemAssets := preload("res://client/item_assets.gd")
const OUT := "res://build/skill_motion_preview/data/"
const BONES := ["mixamorig_Hips", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_LeftHand", "mixamorig_RightHand", "mixamorig_Head", "mixamorig_Spine2"]
const CLASS_CLIPS := {
	"sword_shield": ["attack_3", "block", "block_idle", "attack_4", "block_2", "jump", "jump_2", "crouching_2", "crouching_3", "slash_4", "slash_2", "power_up", "kick", "idle"],
	"greatsword": ["gs_slash_3", "gs_jump_attack", "gs_jump", "gs_jump_2", "gs_slash_4", "gs_power_up", "gs_slide_attack", "gs_high_spin_attack", "gs_attack", "gs_spell_cast", "gs_casting", "gs_idle"],
	"longbow": ["lb_draw_arrow", "lb_aim_recoil", "lb_aim_overdraw", "lb_dodge_backward", "lb_dodge_left", "lb_dodge_right", "lb_idle_01"],
	"magic": ["mg_lite_2h_magic_area_attack_02", "mg_spell_1h_cast_spell_01", "mg_spell_2h_magic_area_attack_01", "mg_spell_2h_magic_area_attack_02", "mg_spell_2h_magic_attack_05", "mg_spell_2h_cast_spell_01", "mg_loco_idle"],
}
## skill id -> [class, clip, start, end] for the pop check against the class idle
const WINDOWS := [
	["S1", "sword_shield", "attack_3", 1.417, 2.40], ["S2a", "sword_shield", "block", 0.0, 0.60], ["S2c", "sword_shield", "attack_4", 0.25, 1.10],
	["S2x", "sword_shield", "block_2", 0.0, 0.80], ["S3", "sword_shield", "jump", 0.10, 1.60], ["S3b", "sword_shield", "block", 0.0, 0.45], ["S4", "sword_shield", "slash_4", 3.00, 4.22],
	["G1", "greatsword", "gs_slash_3", 0.233, 1.453], ["G2", "greatsword", "gs_jump_attack", 0.0, 1.60], ["G3", "greatsword", "gs_slash_4", 0.0, 0.987], ["G4", "greatsword", "gs_power_up", 0.017, 1.237],
	["L1a", "longbow", "lb_draw_arrow", 0.0, 1.033], ["L1b", "longbow", "lb_aim_recoil", 0.0, 0.70], ["L3", "longbow", "lb_aim_recoil", 0.0, 0.32], ["L4a", "longbow", "lb_dodge_backward", 0.0, 1.20],
	["M1", "magic", "mg_spell_1h_cast_spell_01", 0.033, 1.253], ["M2", "magic", "mg_spell_2h_magic_area_attack_01", 0.767, 1.987], ["M3", "magic", "mg_spell_2h_magic_attack_05", 1.533, 2.753], ["M4", "magic", "mg_spell_2h_cast_spell_01", 0.70, 1.92],
]

func _initialize():
	call_deferred("run")

func make_model(scene: Node3D, cls: String):
	var model = load("res://client/characters/studio05_character_model.gd").new()
	scene.add_child(model)
	model.load_model()
	model.dress({"class": cls, "appearance": ItemAssets.card_appearance({"class": cls}, ItemAssets.appearance({})), "weapon": {"path": "", "family": cls, "style": cls}})
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0, 1), false)
	return model

func pose_at(model, clip: String, t: float) -> Dictionary:
	model._skill_clip = {"set": model._library, "clip": clip, "time": t}
	model.apply_pose(10.0)  # follow = 1: the exact authored pose
	var out := {}
	var sk: Skeleton3D = model._skeleton
	for b in BONES:
		out[b] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
	return out

func all_joints(model, clip: String, t: float) -> Array:
	model._skill_clip = {"set": model._library, "clip": clip, "time": t}
	model.apply_pose(10.0)
	var sk: Skeleton3D = model._skeleton
	var pts := []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.begins_with("mixamorig_") and not ("Hand" in n and n.length() > 20) and not n.ends_with("_end"):
			pts.append(sk.global_transform * sk.get_bone_global_pose(i).origin)
	return pts

func gap(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, (a[i] - b[i]).length())
	return worst * 100.0

func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	var scene := Node3D.new()
	root.add_child(scene)
	var models := {}
	var summary := {}
	for cls in CLASS_CLIPS:
		var model = make_model(scene, cls)
		models[cls] = model
		summary[cls] = {}
		for clip in CLASS_CLIPS[cls]:
			if not model._library.has_clip(clip):
				print("MISSING ", cls, " ", clip)
				continue
			var length: float = model._library.length(clip)
			var f := FileAccess.open(OUT + clip + ".csv", FileAccess.WRITE)
			var header := "t,raw_hips_x,raw_hips_y,raw_hips_z"
			for b in BONES:
				var s := str(b).replace("mixamorig_", "")
				header += ",%s_x,%s_y,%s_z" % [s, s, s]
			f.store_line(header)
			var frames := int(ceil(length * 60.0))
			for i in frames + 1:
				var t := minf(i / 60.0, length)
				var raw: Dictionary = model._library.sample(clip, t)
				var hp: Vector3 = raw.get("mixamorig_Hips", {}).get("position", Vector3.ZERO)
				var p := pose_at(model, clip, t)
				var row := "%.4f,%.4f,%.4f,%.4f" % [t, hp.x, hp.y, hp.z]
				for b in BONES:
					row += ",%.4f,%.4f,%.4f" % [p[b].x, p[b].y, p[b].z]
				f.store_line(row)
			f.close()
			summary[cls][clip] = length
	# pop check: class idle (t=0 and its mean) vs the window's first and last frame
	var pops := []
	for w in WINDOWS:
		var model = models[w[1]]
		var idle := str(model.class_data(w[1]).get("states", {}).get("idle", "idle"))
		var idle_pts := all_joints(model, idle, 0.0)
		var s := all_joints(model, w[2], w[3])
		var e := all_joints(model, w[2], w[4])
		var row := "%s %s %s start_gap_cm=%.1f end_gap_cm=%.1f" % [w[0], w[1], w[2], gap(idle_pts, s), gap(idle_pts, e)]
		print("POP ", row)
		pops.append(row)
	var pf := FileAccess.open(OUT + "pops.txt", FileAccess.WRITE)
	pf.store_string("\n".join(pops))
	pf.close()
	print("SCALE ", models["greatsword"].model_scale())
	for cls in models:
		models[cls].tint(Color(0, 0, 0, 0))
	quit()
