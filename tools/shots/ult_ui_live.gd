extends SceneTree
## Race ultimate HUD in a real battle (client/squad_panel.gd): runs the wave journey with the auto-battler and saves
## window captures of the gauge filling (25/50/75/100% of the first card), and 0.3 s after each ultimate callout.
## Run WITH a window:
##   godot --path . --script res://tools/shots/ult_ui_live.gd
## Env: SQUAD=sword_shield,greatsword,magic  RACES=human,viking,elf (per squad slot)  SECONDS=120  W=1280 H=720
##      OUT=res://build/ult_ui/  TAG=a (file name prefix)

func _initialize() -> void:
	call_deferred("run")


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.get_environment(key) != "" else fallback


func run() -> void:
	var size := Vector2i(int(_env("W", "1280")), int(_env("H", "720")))
	DisplayServer.window_set_size(size)
	await process_frame
	var out := _env("OUT", "res://build/ult_ui/")
	var tag := _env("TAG", "a")
	DirAccess.make_dir_recursive_absolute(out)
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var CardDeck = preload("res://logic/card_deck.gd")
	var deck: Dictionary = game_state.profile.card_deck
	var squad := Array(_env("SQUAD", "sword_shield,greatsword,magic").split(","))
	CardDeck.set_squad(deck, squad)
	var races := Array(_env("RACES", "").split(",", false))
	for i in mini(races.size(), squad.size()):
		CardDeck.set_race(deck, str(squad[i]), str(races[i]))
	game_state.start_journey()
	var limit := int(_env("SECONDS", "120"))
	var steps := [0.25, 0.5, 0.75, 1.0]
	var pending := {}  ## file -> frames left
	var frames := 0
	var log_lines: Array = []
	while frames < limit * 60:
		await process_frame
		frames += 1
		var scene = current_scene
		if scene == null or scene.get("_squad_panel") == null or scene.get("_session") == null:
			continue
		var panel = scene._squad_panel
		if panel._order.is_empty():
			continue
		var first: int = panel._order[0]
		if not steps.is_empty() and panel.gauge_shown(first) >= float(steps[0]):
			pending["%s_gauge_%03d.png" % [tag, int(float(steps[0]) * 100.0)]] = 1
			steps.pop_front()
		for event in scene._session.events:
			if str(event.get("type", "")) == "ultimate_cast":
				var file := "%s_callout_%s.png" % [tag, str(event.get("vfx", "")).trim_prefix("race_ult/")]
				pending[file] = 18
				log_lines.append("t=%.2fs ultimate %s by %d (%s)" % [frames / 60.0, event.get("name", ""), int(event.get("player", -1)), event.get("vfx", "")])
				print(log_lines[-1])
		for file in pending.keys():
			pending[file] = int(pending[file]) - 1
			if int(pending[file]) <= 0:
				pending.erase(file)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out + file)
	var log_file := FileAccess.open(out + "log_%s.txt" % tag, FileAccess.WRITE)
	log_file.store_string("\n".join(log_lines) + "\n")
	log_file.close()
	quit()
