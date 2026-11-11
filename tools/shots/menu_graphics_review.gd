extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1600, 720)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile()
	state.profile.created = true
	var hub = load("res://scenes/hub.tscn").instantiate()
	hub.density_override = 1.0
	root.add_child(hub)
	for i in 20: await process_frame
	hub.open_menu()
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu-graphics-review.png")
	root.size = Vector2i(1864, 860)
	hub.density_override = 2.0
	hub._menu_fit_key = ""
	hub._fit_menu()
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu-graphics-phone.png")
	quit()
