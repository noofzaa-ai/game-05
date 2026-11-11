extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile()
	var sheet = load("res://client/player_info_panel.gd").new()
	root.add_child(sheet)
	sheet.setup(state.profile, state.item_rules)
	var item = state.profile.loadout.item_at("shirt", 0)
	sheet._show_item(item, "shirt")
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/player-info-desktop.png")
	root.size = Vector2i(1573, 720)
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/player-info-mobile.png")
	root.size = Vector2i(720, 1573)
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/player-info-portrait.png")
	root.size = Vector2i(1573, 720)
	sheet.queue_free()
	await process_frame
	var layout := Control.new()
	root.add_child(layout)
	for i in 2:
		var b = load("res://client/hub_shortcut_button.gd").new()
		b.caption = "Menu" if i == 0 else "Player Info"
		b.symbol = "menu_bold" if i == 0 else "player_info"
		b.position = Vector2(40, 40 + 76 * i)
		layout.add_child(b)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/player-info-buttons.png")
	layout.queue_free()
	await process_frame
	root.size = Vector2i(1600, 720)
	state.profile.created = true
	var hub = load("res://scenes/hub.tscn").instantiate()
	hub.density_override = 1.0
	root.add_child(hub)
	for i in 20: await process_frame
	hub.close_menu()
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/player-info-hub-buttons.png")
	hub._open_player_info()
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/player-info-hub-panel.png")
	quit()
