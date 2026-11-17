extends SceneTree
## DEV / REVIEW ONLY: runs the Mummy Pyramid journey (data/journeys/mummy_waves.json, 9 waves, placeholder boss) on the
## local session (no server, a fresh local profile with the starter squad), because the pyramid zone is still
## "coming soon" on the world map (data/world/zones.json: journey is empty on purpose) and the online rooms always
## play goblin_waves. Needs a window (no --headless).
##   godot --path . --script res://tools/maps/mummy_dev_run.gd [-- --size 1280x720]            play it by hand
##   godot --path . --script res://tools/maps/mummy_dev_run.gd -- --shot OUT_DIR [--size WxH] [--times 0.6,4,9] [--map mummy_pyramid_hall]
## --map plays ONE map's fixture (its enemy_spawns: 7 mummies + 1 archer, the throne chamber a placeholder boss) instead
## of the journey; --shot saves viewport PNGs at the given seconds and quits.
var size := Vector2i(1280, 720)
var shot_dir := ""
var times: Array = [0.6, 4.0, 10.0]
var map_id := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--size": size = Vector2i(int(args[i + 1].split("x")[0]), int(args[i + 1].split("x")[1]))
			"--shot": shot_dir = args[i + 1]
			"--times": times = Array(args[i + 1].split(",")).map(func(t): return float(t))
			"--map": map_id = args[i + 1]
	root.size = size
	DisplayServer.window_set_size(size)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	if map_id.is_empty():
		if not game_state.start_journey("mummy_waves"):
			printerr("MUMMY_DEV_FAILED start_journey")
			quit(1)
			return
	else:
		game_state.start_stage(game_state.Mode.PVE, map_id)
	if shot_dir.is_empty():
		return  # stay open: play it
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var elapsed := 0.0
	for second in times:
		var frames := int((float(second) - elapsed) * 60.0)
		for i in maxi(frames, 1):
			await process_frame
		elapsed = float(second)
		await RenderingServer.frame_post_draw
		var name := "%s_%dx%d_t%03d.png" % [map_id if not map_id.is_empty() else "journey", size.x, size.y, int(float(second) * 10.0)]
		root.get_texture().get_image().save_png(shot_dir.path_join(name))
		print("shot ", name)
	quit()
