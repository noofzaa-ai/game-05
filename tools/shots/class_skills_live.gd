extends SceneTree
## Class skills v2 live check (design/gdd/class-skills.md 3.1 rule 7, D10): runs the real wave journey with the
## auto-battler and saves a window capture at the release frame of the first cast of each skill of each squad card,
## plus one frame mid-travel for skills that move the body. Run WITH a window (not --headless):
##   godot --path . --script res://tools/shots/class_skills_live.gd
## Env: SQUAD=sword_shield,greatsword,magic (default the starter squad), SECONDS=90 (max fight time), ALL=1 (every skill,
## not only the first cast per class). Output: build/class_skills_live/<class>_<skill>_{release,travel}.png + log.txt.
const OUT := "res://build/class_skills_live/"
const SkillData := preload("res://logic/class_skills/skill_data.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var squad := OS.get_environment("SQUAD")
	var deck: Dictionary = game_state.profile.card_deck
	if not squad.is_empty():
		var ok: bool = preload("res://logic/card_deck.gd").set_squad(deck, Array(squad.split(",")))
		print("squad ", squad, " set: ", ok)
	game_state.start_journey()
	var zoom := int(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else 6
	var limit := int(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 90
	var every := OS.get_environment("ALL") != ""
	var log_lines: Array = []
	var done := {}  ## "<id>:<skill>:<kind>" or "<class>" -> true
	var classes_seen := {}
	var frames := 0
	while frames < limit * 60:
		await process_frame
		frames += 1
		if zoom > 0 and frames == 30 and current_scene != null and current_scene.get("_rig") != null:
			for i in zoom:
				current_scene._rig._orbit(Vector2.ZERO, 0.88)  # closer board camera so the poses read
		var session = game_state.get("session")
		if session == null or session.get("fighters") == null:
			continue
		var wanted := ""
		for id in session.fighters:
			var fighter = session.fighters[id]
			var cast: Dictionary = fighter.skill_view.get("class_cast", {})
			if cast.is_empty():
				continue
			var skill := str(cast["skill"])
			var info: Dictionary = SkillData.load_default().skill(skill)
			var cls := str(info.get("class", ""))
			var key := "%s:%s" % [id, skill]
			var t := float(int(cast["now"]) - int(cast["start"])) / 60.0 / float(cast.get("time_mul", 1.0))
			var timing: Dictionary = info.get("timing", {})
			var travel: Array = timing.get("travel", [])
			if not travel.is_empty() and not done.has(key + ":travel") and t >= (float(travel[0]) + float(travel[1])) * 0.5:
				if every or not classes_seen.has(cls + ":travel"):
					wanted = "%s_%s_travel" % [cls, skill]
					done[key + ":travel"] = true
					classes_seen[cls + ":travel"] = true
					break
			var releases: Array = timing.get("releases", [])
			if not releases.is_empty() and not done.has(key + ":release") and t >= float(releases[0]):
				done[key + ":release"] = true
				if every or not classes_seen.has(cls):
					classes_seen[cls] = true
					wanted = "%s_%s_release" % [cls, skill]
					break
		if wanted.is_empty():
			continue
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + wanted + ".png")
		var line := "t=%.2fs %s" % [frames / 60.0, wanted]
		log_lines.append(line)
		print(line)
		if not every and classes_seen.size() >= 6:
			break
	var file := FileAccess.open(OUT + "log_%s.txt" % (squad.replace(",", "_") if not squad.is_empty() else "starter"), FileAccess.WRITE)
	file.store_string("\n".join(log_lines) + "\n")
	file.close()
	quit()
