extends SceneTree
## Saves the hub over ~25 s (idle variants on the class cards) and one shot of the squad tray.
## Output: build/idle/f_###.png (one frame every 0.5 s of game time), build/idle/tray.png, build/idle/hub.png and
## build/idle/clips.txt (the idle clip each card shows per frame).
##   godot --path . --script res://tools/shots/card_idle_frames.gd   (windowed)
const OUT := "res://build/idle"
const SECONDS := 25.0
const STEP := 0.5


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1600, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	DirAccess.make_dir_recursive_absolute(OUT)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var deck: Dictionary = gs.profile.card_deck
	if (deck.get("squad", []) as Array).size() < 2:
		deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	screen.show_deck(deck, load("res://client/item_assets.gd").cosmetics())
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var full := root.get_texture().get_image()
	full.save_png(OUT + "/hub.png")
	var bar: Control = screen._bar
	full.get_region(Rect2i(bar.get_global_rect().grow(16)).intersection(Rect2i(Vector2i.ZERO, size))).save_png(OUT + "/tray.png")
	var log := FileAccess.open(OUT + "/clips.txt", FileAccess.WRITE)
	var frames := int(SECONDS / STEP)
	var game_time := 0.0  # sampled on game time (saving PNGs slows the frame rate; the cards run on frame delta)
	for f in frames:
		while game_time < f * STEP:
			await process_frame
			game_time += screen.get_process_delta_time()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/f_%03d.png" % [OUT, f])
		var line := "%05.1f fps=%d" % [f * STEP, Engine.get_frames_per_second()]
		for id in screen._cards:
			var card = screen._cards[id]
			var clip: String = card.portrait.model.idle_clip() if card.portrait.model != null else "?"
			line += "  %s=%s(%.1f)" % [id, clip if clip != "" else "(main)", card.portrait._variant_left]
		log.store_line(line)
	log.close()
	print("IDLE frames ", frames)
	quit()
