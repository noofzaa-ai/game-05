extends SceneTree
## Pose distance (cm, worst body joint) from the class idle for every 1/60 s of each skill clip, the joint
## positions (joints_<clip>.txt, for clip-to-clip gaps) and the Root bone's tracks. build/skill_motion_preview/data/gaps_<clip>.txt (helper for the skill motion preview)
const ItemAssets := preload("res://client/item_assets.gd")
const CLIPS := {"sword_shield": ["idle", "attack_3", "attack_4", "block", "block_2", "block_idle", "jump", "jump_2", "slash_4", "slash_2", "kick"], "greatsword": ["gs_idle", "gs_slash_3", "gs_jump_attack", "gs_slash_4", "gs_power_up"], "longbow": ["lb_idle_01", "lb_aim_recoil", "lb_draw_arrow", "lb_aim_overdraw", "lb_dodge_backward"], "magic": ["mg_loco_idle", "mg_spell_1h_cast_spell_01", "mg_spell_2h_magic_area_attack_01", "mg_spell_2h_magic_attack_05", "mg_spell_2h_cast_spell_01"]}
func _initialize():
	call_deferred("run")

func joints(model, clip: String, t: float) -> Array:
	model._skill_clip = {"set": model._library, "clip": clip, "time": t}
	model.apply_pose(10.0)
	var sk: Skeleton3D = model._skeleton
	var pts := []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.begins_with("mixamorig_") and not n.ends_with("_end") and not ("Hand" in n and n.length() > 20):
			pts.append(sk.global_transform * sk.get_bone_global_pose(i).origin)
	return pts

func run():
	var scene := Node3D.new()
	root.add_child(scene)
	for cls in CLIPS:
		var model = load("res://client/characters/studio05_character_model.gd").new()
		scene.add_child(model)
		model.load_model()
		model.dress({"class": cls, "appearance": ItemAssets.card_appearance({"class": cls}, ItemAssets.appearance({})), "weapon": {"path": "", "family": cls, "style": cls}})
		model.set_pose("idle", 0.0, 0.0, true, Vector2(0, 1), false)
		var idle := str(model.class_data(cls).get("states", {}).get("idle", "idle"))
		var ref := joints(model, idle, 0.0)
		var wanted: Array = CLIPS[cls]
		if OS.get_environment("ALL_CLIPS") == "1":
			wanted = model._library.clip_names()
		for clip in wanted:
			var anim: Animation = model._library._clips[clip]["animation"]
			for tr in anim.get_track_count():
				var p := String(anim.track_get_path(tr).get_concatenated_subnames())
				if p == "Root":
					print("ROOTTRACK ", clip, " type ", anim.track_get_type(tr), " keys ", anim.track_get_key_count(tr))
			var f := FileAccess.open("res://build/skill_motion_preview/data/gaps_%s.txt" % clip, FileAccess.WRITE)
			var jf := FileAccess.open("res://build/skill_motion_preview/data/joints_%s.txt" % clip, FileAccess.WRITE)
			var length: float = model._library.length(clip)
			var i := 0
			while i / 60.0 <= length:
				var pts := joints(model, clip, i / 60.0)
				var worst := 0.0
				for k in pts.size():
					worst = maxf(worst, (pts[k] - ref[k]).length())
				f.store_line("%.4f %.1f" % [i / 60.0, worst * 100.0])
				var row := PackedStringArray([str(i / 60.0)])
				for pt in pts:
					row.append("%.4f %.4f %.4f" % [pt.x, pt.y, pt.z])
				jf.store_line(" ".join(row))
				i += 1
			f.close()
			jf.close()
		model.tint(Color(0, 0, 0, 0))
	quit()
