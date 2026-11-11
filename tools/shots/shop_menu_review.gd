extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	var state := root.get_node("GameState")
	state.ensure_profile()
	state.profile.stash.gold = 5000  # local screenshot only, never persisted
	var screen = load("res://client/camp_screen.gd").new()
	screen.merchant_mode = true
	root.add_child(screen)
	screen.setup(state.profile, state.camp_data, state.item_rules, preload("res://logic/combat_data_loader.gd").load_default())
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/merchant-shop.png")
	quit()
