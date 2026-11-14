extends SceneTree
## Measures the class card hub's frame rate with no pointer on any card (all portraits animating).
##   godot --path . --script res://tools/perf/hub_fps.gd   (windowed; ZORX_SIZE=WxH, default 1920x1080)
## ZORX_CARD_INK=0 / 1 forces the card ink-wash look off / on (A/B against CardTokens.PORTRAIT_INK).
## Prints "HUB_FPS avg=.. min=.. p1_ms=.. frames=.." after a warm-up.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var ink := OS.get_environment("ZORX_CARD_INK")
	if not ink.is_empty():
		load("res://client/card_portrait.gd").ink_look = ink == "1"
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	for i in 120:
		await process_frame
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in 600:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var avg_ms := total / times.size()
	var worst_1 := times[int(times.size() * 0.99)]
	print("HUB_FPS avg=%.1f min=%.1f p1_ms=%.1f frames=%d" % [1000.0 / avg_ms, 1000.0 / times[-1], worst_1, times.size()])
	quit()
