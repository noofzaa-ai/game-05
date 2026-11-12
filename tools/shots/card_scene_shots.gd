extends SceneTree
## Hub shot with the painted card scenes (client/card_scene_layers.gd), plus the character screen window.
## Run windowed: godot --path . --script res://tools/shots/card_scene_shots.gd   (ZORX_SIZE=WxH, default 1920x1080)
## Output: build/card_scene/hub_<W>x<H>.png and char_<W>x<H>.png
const OUT := "res://build/card_scene"


func _initialize() -> void:
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run() -> void:
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	DirAccess.make_dir_recursive_absolute(OUT)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen._layout()
	for i in 40:
		await process_frame
	await _shot("%s/hub_%dx%d.png" % [OUT, size.x, size.y])
	screen.open_character("longbow")
	for i in 30:
		await process_frame
	await _shot("%s/char_%dx%d.png" % [OUT, size.x, size.y])
	quit()
