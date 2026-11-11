extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile(); state.profile.created = true
	var hub = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	for i in 20: await process_frame
	hub.close_menu()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hub-icons-desktop.png")
	root.size = Vector2i(1573, 720)
	hub.shortcut_css_override = Vector2(852, 390)
	hub._menu_fit_key = ""; hub._fit_menu()
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hub-icons-mobile.png")
	print("Shortcut hit box CSS: ", hub._menu_button.size, " scale ", hub._shortcut_root.scale)
	quit()
