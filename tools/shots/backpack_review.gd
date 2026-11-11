extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1573, 720)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile(); state.profile.created = true
	var hub = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	for i in 20: await process_frame
	hub.close_menu()
	hub._bag_button.pressed.emit()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/backpack-mobile.png")
	print("Backpack title: ", hub._camp_screen._title.text, "; pages: ", hub._camp_screen._tabs.get_tab_count())
	quit()
