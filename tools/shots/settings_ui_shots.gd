extends SceneTree
## Settings panel shots over the hub (client/graphics_panel.gd). Run windowed:
##   godot --path . --script res://tools/shots/settings_ui_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/settings_ui/<W>x<H>),
## ZORX_LANG=th|en (default en), ZORX_CHANGE=1 also shoots after switching Drawn style to Lite.
## The player's saved graphics settings are put back at the end.
const Options := preload("res://client/graphics_options.gd")


func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var prefix := OS.get_environment("ZORX_SHOT")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://build/settings_ui/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	var saved := Options.snapshot()
	var tokens = load("res://client/card_tokens.gd")
	if OS.get_environment("ZORX_LANG") == "th":
		tokens.language = "th"
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
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 20:
		await process_frame
	Options.set_value("drawn_style", "on")
	var panel = load("res://client/graphics_panel.gd").new()
	screen.add_child(panel)
	await _shot(prefix + ".png")
	if OS.get_environment("ZORX_CHANGE") == "1":
		var lite: Button = panel.find_child("Drawn_lite", true, false)
		if lite != null:
			lite.grab_focus()
			lite.pressed.emit()
		print("CHANGE drawn_style=", Options.value("drawn_style"))
		await _shot(prefix + "_after_lite.png")
		var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
		if scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			await _shot(prefix + "_scrolled.png")
	for key in saved:
		Options.set_value(key, saved[key])
	quit()
