extends SceneTree
## Measures the hub -> battle hand-over on desktop: the longest single frame (the freeze) and the time until the
## stage has drawn its first two frames. Run windowed:  godot --path . --script res://tools/shots/fight_freeze_measure.gd
## ZORX_MEASURE=old (plain GameState.start_journey, the old path) | new (the FIGHT loading overlay, default).

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	for i in 60:
		await process_frame
	var how := OS.get_environment("ZORX_MEASURE")
	var t0 := Time.get_ticks_usec()
	var last := t0
	var worst := 0
	var frames: Array = []
	if how == "old":
		gs.start_journey()
	else:
		screen._start_fight()
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000)
		worst = maxi(worst, now - last)
		last = now
		var stage = current_scene
		var overlay := root.get_node_or_null("FightLoading")
		if stage != null and stage.get("_scene_presented") == true and overlay == null:
			break
		if now - t0 > 60000000:
			break
	print("MEASURE ", how, " total_ms=", (Time.get_ticks_usec() - t0) / 1000, " worst_frame_ms=", worst / 1000, " frames=", frames.size())
	print("MEASURE frames_ms=", frames.slice(0, 80))
	quit()
