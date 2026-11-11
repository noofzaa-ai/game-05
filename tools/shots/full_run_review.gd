extends SceneTree
## Windowed full auto-battle run: card screen -> wave journey -> all waves -> summary.
## Saves PNGs to build/full_run/ and prints wave progress lines starting with "RUN".
##   godot --path . --script res://tools/shots/full_run_review.gd   (SPEED=3 env sets time scale)
const OUT := "res://build/full_run"
var _shot := 0


func _initialize() -> void:
	call_deferred("run")


func snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [OUT, _shot, label])


func run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	gs.go_card_deck()
	for i in 60:
		await process_frame
	await snap("card_deck")
	if not gs.start_journey(gs.DEFAULT_JOURNEY, 77):
		print("RUN start_journey failed")
		quit(1)
		return
	Engine.time_scale = float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 3.0
	var start := Time.get_ticks_msec()
	var last_pending := -1
	while Time.get_ticks_msec() - start < 900000:
		await process_frame
		var secs := (Time.get_ticks_msec() - start) / 1000.0
		var scene = current_scene
		var sess = gs.session
		var sim = sess._sim if sess != null and "_sim" in sess else null
		if sim != null:
			var pending: int = sim.pending_wave_count()
			if pending != last_pending:
				last_pending = pending
				var alive := 0
				for id in sim.fighters:
					if sim.fighters[id].team != "enemy" and sim.fighters[id].hp > 0:
						alive += 1
				print("RUN wave %d/12 squad_alive=%d t=%.0fs" % [12 - pending, alive, secs])
				await snap("wave%02d" % (12 - pending))
		if scene != null and scene.scene_file_path == gs.JOURNEY_SCENE:
			for i in 90:
				await process_frame
			await snap("summary")
			print("RUN summary journey_state=", gs.journey.state if gs.journey != null else "null")
			break
		if scene != null and scene.scene_file_path == gs.CARD_DECK_SCENE and secs > 5.0:
			await snap("back_to_deck")
			print("RUN returned to card deck")
			break
	Engine.time_scale = 1.0
	print("RUN done in %.0fs" % ((Time.get_ticks_msec() - start) / 1000.0))
	quit()
