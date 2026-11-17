extends SceneTree
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := (load(args[0]) as PackedScene).instantiate()
	var p: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	print("LIBS ", p.get_animation_library_list(), " players=", root.find_children("*", "AnimationPlayer", true, false).size())
	for c in args.slice(1):
		var a: Animation = p.get_animation(c)
		var types := {}
		var keys := 0
		for t in a.get_track_count():
			types[a.track_get_type(t)] = types.get(a.track_get_type(t), 0) + 1
			keys += a.track_get_key_count(t)
		print(c, " len=", a.length, " tracks=", a.get_track_count(), " types=", types, " keys=", keys)
		for t in a.get_track_count():
			var n := str(a.track_get_path(t))
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D or "Hips" in n or "Root" in n:
				print("   ", a.track_get_type(t), " ", n, " keys=", a.track_get_key_count(t))
	quit()
