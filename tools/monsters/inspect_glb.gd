extends SceneTree
## Prints skeleton, mesh and animation facts of a GLB. godot --headless --path . --script res://tools/monsters/inspect_glb.gd -- res://path.glb [clips]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := load(args[0]) as PackedScene
	var root := scene.instantiate()
	for sk in root.find_children("*", "Skeleton3D", true, false):
		print("SKELETON ", sk.get_path(), " bones=", sk.get_bone_count())
		if args.size() > 2:
			for i in sk.get_bone_count():
				print("  ", i, " ", sk.get_bone_name(i), " parent=", sk.get_bone_parent(i), " restpos=", sk.get_bone_rest(i).origin)
	var tris := 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris += t
		print("MESH ", mi.name, " tris=", t, " skin=", mi.skin != null, " aabb=", mi.get_aabb())
	print("TRIS ", tris)
	for p in root.find_children("*", "AnimationPlayer", true, false):
		for ln in p.get_animation_library_list():
			var lib: AnimationLibrary = p.get_animation_library(ln)
			for c in lib.get_animation_list():
				var a: Animation = lib.get_animation(c)
				if args.size() > 1 and args[1] == "clips" or c in ["lb_idle_01","lb_draw_arrow","lb_aim_recoil","lb_run_forward"]:
					print("CLIP ", c, " len=", a.length, " tracks=", a.get_track_count())
	quit()
