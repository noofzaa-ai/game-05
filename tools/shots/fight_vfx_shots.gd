extends SceneTree
## Fight VFX check (2026-11-17): grabs the longbow shot and the heavy-blow ground cracks in a real wave fight.
##   godot --path . --script res://tools/shots/fight_vfx_shots.gd -- --tag=after --shots=<dir>
## Saves <dir>/<tag>_longbow_N.png, <tag>_heavy_N.png, <tag>_knight_N.png. Run windowed (not --headless).
const Options := preload("res://client/graphics_options.gd")
const WANT := {"longbow": 3, "heavy": 3, "knight": 2}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var shots := "res://build/fight_vfx"
	var tag := "shot"
	var zoom := 8
	var squad := "longbow"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
		elif a.begins_with("--tag="): tag = a.substr(6)
		elif a.begins_with("--squad="): squad = a.substr(8)
		elif a.begins_with("--zoom="): zoom = int(a.substr(7))
	var had_config := FileAccess.file_exists(Options.PATH)
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var deck: Dictionary = game_state.profile.card_deck
	for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
		deck["cards"][pair[0]]["race"] = pair[1]
	deck["squad"] = [squad]  # (a one-card squad: the camera follows that fighter)
	seed(7)
	game_state.start_journey(game_state.DEFAULT_JOURNEY, 7)
	await _frames(120)
	var stage: Node = current_scene
	DirAccess.make_dir_recursive_absolute(shots)
	var rig = stage.get("_rig")
	if rig != null:
		for i in zoom: rig._orbit(Vector2.ZERO, 0.85)
	var got := {"longbow": 0, "heavy": 0, "knight": 0}
	var last := {"longbow": -999, "heavy": -999, "knight": -999}
	var frame := 0
	while frame < 9000 and got[squad if squad == "longbow" else "heavy"] < WANT[squad if squad == "longbow" else "heavy"]:
		await process_frame
		frame += 1
		var session = stage.get("_session")
		if session == null:
			continue
		var kind := ""
		for e in session.events:
			var move := str(e.get("move", ""))
			var t := str(e.get("type", ""))
			if t == "attack_active" and move.begins_with("longbow_light"):
				kind = "longbow"
			elif t == "hit" and move.ends_with("_heavy") and not move.begins_with("longbow"):
				kind = "heavy"
			elif t == "hit" and move.begins_with("goblin_knight_overhead"):
				kind = "knight"
		if kind != "" and got[kind] < WANT[kind] and frame - int(last[kind]) > 240:
			last[kind] = frame
			await _frames(4 if kind == "longbow" else 6)
			await _shot(stage, shots, "%s_%s_%s_%d" % [tag, squad, kind, got[kind]])
			got[kind] += 1
			stage.set_physics_process(true)
	print("captured ", got, " in ", frame, " frames")
	if not had_config: DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	quit()


func _shot(stage: Node, dir: String, name: String) -> void:
	stage.set_physics_process(false)
	await _frames(1)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
