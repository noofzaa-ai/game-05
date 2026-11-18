extends SceneTree
## Review pictures of the Mummy Pyramid maps as the game shows them (the real stage scene, the battle camera, the
## drawn style the player has), at the phone size 844x390 and at 1280x720. Needs a window (no --headless):
##   godot --path . --script res://tools/maps/mummy_map_shots.gd -- [--out DIR] [--sizes 844x390,1280x720] [map_id ...]
## Per map and size: <id>_<WxH>_1_open.png (the board as the stage opens: the camera's full overview),
## <id>_<WxH>_2_fight.png (4 s in, the auto-framed fight), <id>_<WxH>_3_overview.png (the arena overview camera
## held still, the rules frozen). Prints the frame's draw calls and primitives for each picture.

const MAPS := ["mummy_pyramid_gate", "mummy_pyramid_hall", "mummy_pyramid_sanctum"]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ProjectSettings.globalize_path("res://build/mummy_map_shots")
	var sizes: Array = [Vector2i(844, 390), Vector2i(1280, 720)]
	var ids: Array = []
	var k := 0
	while k < args.size():
		match args[k]:
			"--out":
				out = args[k + 1]
				k += 1
			"--sizes":
				sizes = Array(args[k + 1].split(",")).map(func(s): return Vector2i(int(s.split("x")[0]), int(s.split("x")[1])))
				k += 1
			_:
				ids.append(args[k])
		k += 1
	if ids.is_empty():
		ids = MAPS
	DirAccess.make_dir_recursive_absolute(out)
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	for size in sizes:
		DisplayServer.window_set_size(size)
		root.size = size
		await _frames(3)
		for id in ids:
			game_state.start_stage(game_state.Mode.PVE, id)
			await _frames(20)
			await _save(out, "%s_%dx%d_1_open" % [id, size.x, size.y])
			await _frames(220)
			await _save(out, "%s_%dx%d_2_fight" % [id, size.x, size.y])
			var stage: Node = current_scene
			if stage == null or not stage is Node3D:
				printerr("MUMMY_SHOT no stage for ", id)
				continue
			stage.set_physics_process(false)
			var camera := Camera3D.new()
			stage.add_child(camera)
			camera.fov = 40.0
			camera.look_at_from_position(Vector3(0.0, 16.5, 14.0), Vector3(0.0, -0.5, 0.0))
			camera.current = true
			await _frames(4)
			await _save(out, "%s_%dx%d_3_overview" % [id, size.x, size.y])
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("MUMMY_SHOT %s draw_calls=%d primitives=%d" % [name, calls, primitives])
