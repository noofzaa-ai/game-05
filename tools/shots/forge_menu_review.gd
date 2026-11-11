extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile()
	var screen = load("res://client/camp_screen.gd").new()
	screen.blacksmith_mode = true
	root.add_child(screen)
	screen.setup(state.profile, state.camp_data, state.item_rules, preload("res://logic/combat_data_loader.gd").load_default())
	for mode in ["Refine", "Upgrade"]:
		screen.show_tab(1 if mode == "Refine" else 2)
		var selector = screen._pages[mode].get_child(0)
		if not selector._items.is_empty(): selector._choose(selector._items.keys()[0])
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/forge-" + mode.to_lower() + ".png")
	quit()
