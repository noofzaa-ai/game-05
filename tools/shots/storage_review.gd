extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile()
	var panel = load("res://client/storage_panel.gd").new()
	root.add_child(panel)
	panel.setup(state.profile, state.item_rules, state.camp_data, state.get_session())
	for cell in panel._cells:
		if cell.source == "stash" and cell.item != null:
			panel._select(cell)
			break
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/storage-desktop.png")
	root.size = Vector2i(1573, 720)
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/storage-mobile.png")
	root.size = Vector2i(720, 1573)
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/storage-portrait.png")
	quit()
