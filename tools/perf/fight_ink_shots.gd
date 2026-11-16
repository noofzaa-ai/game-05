extends SceneTree
## Fight outline check (2026-11-16): shots of the wave fight at the overview and at the closest camera zoom.
##   godot --path . --script res://tools/perf/fight_ink_shots.gd -- --tag=after --size=1280x720 --shots=<dir>
## Saves <dir>/<tag>_<WxH>_{overview,closest}.png. Run windowed (not --headless).
const Options := preload("res://client/graphics_options.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1280, 720)
	var shots := ""
	var tag := "shot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--shots="): shots = a.substr(8)
		elif a.begins_with("--tag="): tag = a.substr(6)
	var had_config := FileAccess.file_exists(Options.PATH)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var deck: Dictionary = game_state.profile.card_deck
	for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
		deck["cards"][pair[0]]["race"] = pair[1]
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	seed(7)
	game_state.start_journey(game_state.DEFAULT_JOURNEY, 7)
	await _frames(420)
	var stage: Node = current_scene
	DirAccess.make_dir_recursive_absolute(shots)
	await _shot(stage, shots, "%s_%dx%d_overview" % [tag, size.x, size.y])
	stage.set_physics_process(true)
	var rig = stage.get("_rig")
	if rig != null:
		for i in 40: rig._orbit(Vector2.ZERO, 0.7)  # the wheel/pinch zoom: down to ARENA_CLOSEST
	await _frames(150)
	await _shot(stage, shots, "%s_%dx%d_closest" % [tag, size.x, size.y])
	if not had_config: DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	quit()


func _shot(stage: Node, dir: String, name: String) -> void:
	stage.set_physics_process(false)
	await _frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
