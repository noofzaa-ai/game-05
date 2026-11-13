extends SceneTree
## Structure of each class skill VFX: MeshInstance3D count, surfaces, unique materials, unique meshes, animation tracks.
##   godot --headless --path . --script res://tools/perf/class_skill_vfx_inspect.gd -- [ids...]
const ROOT := "res://art/vfx/class_skills/"

func _initialize() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = DirAccess.get_directories_at(ROOT)
	for sid in ids:
		var inst: Node = load(ROOT + sid + "/effect.tscn").instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		var surfaces := 0
		var mats := {}
		var meshes := {}
		var kinds := {}
		for mi in mis:
			var m: Mesh = mi.mesh
			meshes[m] = true
			surfaces += m.get_surface_count()
			for s in m.get_surface_count():
				var mat = mi.get_active_material(s)
				mats[mat] = true
			var key: String = mi.get_parent().name if mi.get_parent() else "?"
		var ap := inst.find_children("*", "AnimationPlayer", true, false)
		var tracks := 0
		var ttypes := {}
		if not ap.is_empty():
			for c in ap[0].get_animation_list():
				if c != &"RESET":
					var a: Animation = ap[0].get_animation(c)
					tracks = a.get_track_count()
					for t in tracks:
						var p := str(a.track_get_path(t))
						var tt := "%d:%s" % [a.track_get_type(t), p.get_slice(":", 1)]
						ttypes[tt] = int(ttypes.get(tt, 0)) + 1
		print("INSPECT %s mi=%d surfaces=%d meshes=%d mats=%d tracks=%d types=%s" % [sid, mis.size(), surfaces, meshes.size(), mats.size(), tracks, ttypes])
		inst.free()
	quit()
