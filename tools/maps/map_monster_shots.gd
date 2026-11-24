extends SceneTree
## Review pictures of a map with a chosen monster mix (no journey needed): copies the map file to a temporary
## map id with its enemy_spawns retyped in order, plays it as a free PvE stage (the real stage scene, the battle
## camera, the starter squad), and deletes the temporary file at the end. Needs a window (no --headless):
##   godot --path . --script res://tools/maps/map_monster_shots.gd -- --map orc_camp_night \
##       --enemies orc_grunt:4,orc_archer:2,orc_mage:2 [--out DIR] [--sizes 1280x720,844x390] [--fight-frames 240]
## Per size: <map>_<WxH>_1_open.png (as the stage opens), <map>_<WxH>_2_fight.png (fight-frames in),
## <map>_<WxH>_3_close.png (a close camera on the middle of the fighters, the rules frozen).

const TMP_SUFFIX := "__shots_tmp"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ProjectSettings.globalize_path("res://build/map_monster_shots")
	var sizes: Array = [Vector2i(1280, 720), Vector2i(844, 390)]
	var map_id := "orc_camp_night"
	var enemy_spec := "orc_grunt:4,orc_archer:2,orc_mage:2"
	var fight_frames := 240
	var k := 0
	while k < args.size():
		match args[k]:
			"--out": out = args[k + 1]; k += 1
			"--map": map_id = args[k + 1]; k += 1
			"--enemies": enemy_spec = args[k + 1]; k += 1
			"--fight-frames": fight_frames = int(args[k + 1]); k += 1
			"--sizes":
				sizes = Array(args[k + 1].split(",")).map(func(s): return Vector2i(int(s.split("x")[0]), int(s.split("x")[1])))
				k += 1
		k += 1
	var types: Array = []
	for part in enemy_spec.split(","):
		var bits := part.split(":")
		for i in (int(bits[1]) if bits.size() > 1 else 1):
			types.append(bits[0])
	var tmp_id := map_id + TMP_SUFFIX
	var tmp_path := "res://data/maps/%s.json" % tmp_id
	var json = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % map_id))
	if typeof(json) != TYPE_DICTIONARY:
		printerr("MONSTER_SHOT cannot read map ", map_id)
		quit(1)
		return
	json["id"] = tmp_id
	var spawns: Array = json.get("enemy_spawns", [])
	for i in mini(spawns.size(), types.size()):
		spawns[i]["type"] = types[i]
	json["enemy_spawns"] = spawns.slice(0, mini(spawns.size(), types.size()))
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(json, "\t"))
	f.close()
	DirAccess.make_dir_recursive_absolute(out)
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var deck: Dictionary = game_state.profile.card_deck
	var saved_squad: Array = deck.get("squad", []).duplicate()
	if saved_squad.is_empty():  # a fresh profile has no squad yet: show the starter one (in memory only)
		deck["squad"] = Array(preload("res://logic/card_deck.gd").STARTER_SQUAD)
	for size in sizes:
		DisplayServer.window_set_size(size)
		root.size = size
		await _frames(3)
		game_state.start_stage(game_state.Mode.PVE, tmp_id)
		await _frames(20)
		await _save(out, "%s_%dx%d_1_open" % [map_id, size.x, size.y])
		await _frames(fight_frames)
		await _save(out, "%s_%dx%d_2_fight" % [map_id, size.x, size.y])
		var stage: Node = current_scene
		if stage == null or not stage is Node3D:
			printerr("MONSTER_SHOT no stage")
			continue
		stage.set_physics_process(false)
		var centre := Vector3.ZERO
		var n := 0
		var views = stage.get("_views")
		if views is Dictionary:
			for id in views:
				var v = views[id]
				if v is Node3D and v.visible:
					centre += v.global_position
					n += 1
		if n > 0:
			centre /= n
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.fov = 40.0
		camera.look_at_from_position(centre + Vector3(0.0, 6.5, 5.5), centre + Vector3(0.0, 0.6, 0.0))
		camera.current = true
		await _frames(4)
		await _save(out, "%s_%dx%d_3_close" % [map_id, size.x, size.y])
	deck["squad"] = saved_squad
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("MONSTER_SHOT ", name)
