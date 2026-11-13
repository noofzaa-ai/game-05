extends SceneTree
## Class skill VFX in a real battle (client/skills/class_skill_vfx.gd): runs the wave journey with the auto-battler
## and saves a window capture `AFTER` seconds after each skill's VFX appears (the first cast of each skill).
## Run WITH a window:
##   godot --path . --script res://tools/shots/class_skill_vfx_live.gd
## Env: SQUAD=sword_shield,greatsword,magic, SECONDS=90, ZOOM=6, AFTER=0.25, OUT=res://build/class_skill_vfx/ingame/
## Also prints the class VFX live count and frame times (process) once a second.

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "res://build/class_skill_vfx/ingame/"
	DirAccess.make_dir_recursive_absolute(out)
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var squad := OS.get_environment("SQUAD")
	if not squad.is_empty():
		var ok: bool = preload("res://logic/card_deck.gd").set_squad(game_state.profile.card_deck, Array(squad.split(",")))
		print("squad ", squad, " set: ", ok)
	game_state.start_journey()
	var zoom := int(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else 6
	var limit := int(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 90
	var after := float(OS.get_environment("AFTER")) if OS.get_environment("AFTER") != "" else 0.25
	var shot := {}  ## skill -> seconds left until the capture
	var taken := {}
	var frames := 0
	var log_lines: Array = []
	while frames < limit * 60:
		await process_frame
		frames += 1
		var scene = current_scene
		if zoom > 0 and frames == 30 and scene != null and scene.get("_rig") != null:
			for i in zoom:
				scene._rig._orbit(Vector2.ZERO, 0.88)
		if scene == null or scene.get("_class_vfx") == null:
			continue
		var vfx = scene._class_vfx
		for fx in vfx._live:
			var skill := str(fx["skill"])
			if int(fx["player"]) >= 0 and not taken.has(skill) and not shot.has(skill):
				shot[skill] = after
		var ready := ""
		for skill in shot.keys():
			shot[skill] = float(shot[skill]) - 1.0 / 60.0
			if float(shot[skill]) <= 0.0:
				ready = skill
		if ready != "":
			shot.erase(ready)
			taken[ready] = true
			var cls := str(preload("res://logic/class_skills/skill_data.gd").load_default().skill(ready).get("class", ""))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out + "%s_%s.png" % [cls, ready])
			var line := "t=%.2fs %s/%s live=%d" % [frames / 60.0, cls, ready, vfx.live_count()]
			log_lines.append(line)
			print(line)
	var file := FileAccess.open(out + "log_%s.txt" % (squad.replace(",", "_") if not squad.is_empty() else "starter"), FileAccess.WRITE)
	file.store_string("\n".join(log_lines) + "\n")
	file.close()
	quit()
