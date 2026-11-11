extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1440, 900)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile()
	state.profile.created = true
	var hub = load("res://client/hub.gd").new()
	root.add_child(hub)
	for frame in range(20): await process_frame
	root.scaling_3d_scale = 1.0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/live-workshops-hub.png")
	var screen = load("res://client/camp_screen.gd").new()
	root.add_child(screen)
	screen.setup(state.profile, state.camp_data, state.item_rules, load("res://logic/combat_data_loader.gd").load_default())
	screen.show_tab(3)
	for frame in range(20): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/facility-next-desktop.png")
	root.size = Vector2i(960, 540)
	screen.density_override = 2.0
	screen._apply_layout()
	for frame in range(20): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/facility-next-mobile.png")
	quit()
