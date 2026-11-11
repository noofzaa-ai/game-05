extends SceneTree
## Opens a real stage with the auto-battler on and saves frames over time: build/auto_battle/*.png
##   godot --path . --script res://tools/shots/auto_battle_shots.gd -- [map_id]
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := "goblin_base_gate"
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"): id = a
	var portrait := OS.get_environment("PORTRAIT") != ""
	var window_size := Vector2i(540, 960) if portrait else Vector2i(1280, 720)
	DisplayServer.window_set_size(window_size)
	root.size = window_size
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	DirAccess.make_dir_recursive_absolute("res://build/auto_battle")
	if OS.get_environment("JOURNEY") != "":
		game_state.start_journey()
	else:
		game_state.start_stage(game_state.Mode.PVE, id)
	var zoom_steps := int(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else 0
	var seconds := [0.45, 0.6, 0.75, 0.9, 1.1, 1.3] if zoom_steps > 0 else ([0.3, 0.8, 1.6, 2.6] if OS.get_environment("JOURNEY") != "" else [1, 3, 5, 7, 9, 12, 15, 20])
	for second in seconds:
		if zoom_steps > 0 and current_scene != null and current_scene.get("_rig") != null:
			for i in zoom_steps:
				current_scene._rig._orbit(Vector2.ZERO, 0.88)
		var frames := 0
		var target: int = int(second * 60.0)
		while frames < target:
			await process_frame
			frames += 1
			if frames > 3000: break
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/auto_battle/t%03d.png" % int(second * 100.0))
		var scene = current_scene
		var rig = scene.get("_rig") if scene != null else null
		print("t=", second, " scene=", scene.name if scene != null else "none", " rig=", rig.view() if rig != null else "-", " arena=", rig.arena if rig != null else "-", " chosen=", rig.chosen if rig != null else "-")
	quit()
