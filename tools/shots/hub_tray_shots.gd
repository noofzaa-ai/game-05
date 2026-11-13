extends SceneTree
## The hub squad tray (card_deck_screen.gd TraySlot). Run windowed:
##   godot --path . --script res://tools/shots/hub_tray_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/settings_ui/tray_<W>x<H>).
## Shoots the full squad, then a squad of two (the "+" empty slot), and a crop of the tray for each.
func _initialize():
	call_deferred("run")


func _shot(path: String, screen: Control) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path + ".png")
	var bar: Control = screen._bar
	var r := Rect2i(Vector2i(bar.global_position) - Vector2i(10, 40), Vector2i(bar.size) + Vector2i(20, 50 + int(screen._synergy.size.y) + 20))
	r = r.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.get_region(r).save_png(path + "_crop.png")
	print("SHOT ", path)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var prefix := OS.get_environment("ZORX_SHOT")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://build/settings_ui/tray_%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	var deck: Dictionary = gs.profile.card_deck.duplicate(true)
	screen.show_deck(deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 30:
		await process_frame
	await _shot(prefix, screen)
	for slot in screen._slots:
		print("SLOT ", slot.index, " ", slot.class_id, " size=", slot.size)
	var squad: Array = screen._squad().duplicate()
	if squad.size() > 2:
		squad.resize(2)
		screen._set_squad(squad)
		await _shot(prefix + "_two", screen)
	quit()
