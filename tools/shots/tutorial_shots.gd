extends SceneTree
## New-player tutorial shots (design/gdd/tutorial.md 7 test 10). Run windowed (not headless):
##   godot --path . --script res://tools/shots/tutorial_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=folder (default art_source/codex_review/tutorial_ui_2026-11-15).
## Works on a throwaway new-player profile in memory (never saved): sets each step and the races it needs, lets the
## real driver show it, saves <folder>/<W>x<H>_<nn>_<step>.png and prints the cut-out rect for the review.
const Tutorial := preload("res://logic/tutorial.gd")
const Deck := preload("res://logic/card_deck.gd")


func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var folder := OS.get_environment("ZORX_SHOT")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://art_source/codex_review/tutorial_ui_2026-11-15")
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var p = gs.profile
	p.tutorial = {"version": 1, "step": "welcome", "tour_done": false, "unlock_seen": false}
	p.unlocks = {"magic_runeborn": false}
	var races := {"sword_shield": "human", "greatsword": "viking", "longbow": "elf"}
	for id in p.card_deck["cards"]:
		p.card_deck["cards"][id]["race"] = ""
	p.card_deck["squad"] = []
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	root.add_child(screen)
	screen.size = Vector2(size)
	for i in 30:
		await process_frame
	var driver = screen.tutorial
	var n := 0
	for step in Tutorial.steps():
		var id := str(step["id"])
		if str(step["screen"]) == "battle":
			continue
		# the races a player has at this step (the cards before it)
		var at := Tutorial.index_of(id)
		for cls in races:
			var pick := Tutorial.index_of({"sword_shield": "race_ss_pick", "greatsword": "race_gs_pick", "longbow": "race_lb_pick"}[cls])
			p.card_deck["cards"][cls]["race"] = races[cls] if at > pick else ""
		p.card_deck["squad"] = races.keys() if at > Tutorial.index_of("race_lb_pick") else []
		if str(step["group"]) == "unlock":
			p.unlocks["magic_runeborn"] = true
			p.tutorial["unlock_seen"] = false
		p.tutorial["step"] = id
		screen.tutorial_show_hub()
		screen.show_deck(p.card_deck, load("res://client/item_assets.gd").cosmetics())
		driver.refresh()
		for i in (220 if id == "unlock_ceremony" else 40):
			await process_frame
		n += 1
		print("STEP ", id, " hole=", driver.overlay.hole, " box=", driver.overlay._box.get_global_rect(), " visible=", driver.overlay.visible)
		await _shot("%s/%dx%d_%02d_%s.png" % [folder, size.x, size.y, n, id])
		if id == "unlock_ceremony" and driver._ceremony != null:
			driver._ceremony.queue_free()
			driver._ceremony = null
	# first fight lost tip
	p.tutorial["step"] = "tour_equip"
	driver._lost_tip = true
	screen.tutorial_show_hub()
	driver.refresh()
	for i in 30:
		await process_frame
	await _shot("%s/%dx%d_%02d_lost_tip.png" % [folder, size.x, size.y, n + 1])
	# locked Runeborn in the picker
	driver._lost_tip = false
	p.unlocks["magic_runeborn"] = false
	p.tutorial["step"] = "done"
	driver.refresh()
	screen.tutorial_open_character("sword_shield", true)
	for i in 30:
		await process_frame
	await _shot("%s/%dx%d_%02d_locked_runeborn.png" % [folder, size.x, size.y, n + 2])
	quit()
