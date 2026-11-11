extends SceneTree
## Card character screen shots (docs/ui/hub_layout_spec.md §4). Run windowed:
##   godot --path . --script res://tools/shots/card_character_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/hub2/<W>x<H>).
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
		prefix = ProjectSettings.globalize_path("res://build/hub2/%dx%d" % [size.x, size.y])
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
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 30:
		await process_frame
	screen.open_character("sword_shield")
	var ch = screen._character
	for i in 30:
		await process_frame
	ch.select_slot("offhand:0")
	await _shot(prefix + "_char_sword_shield.png")
	# equip before / after: pick a hat in storage, wear it
	var hat = null
	for item in gs.profile.stash.items:
		if item.slot == "hat":
			hat = item
			break
	ch.select_slot("hat:0")
	if hat != null:
		ch.select_stash_item(hat.id)
	await _shot(prefix + "_equip_before.png")
	if hat != null:
		await ch._equip(hat.id, "hat")
	print("EQUIP worn=", gs.profile.loadout_of("sword_shield").item_at("hat", 0) != null)
	await _shot(prefix + "_equip_after.png")
	ch.switch_card(1)
	for i in 20:
		await process_frame
	ch.select_slot("offhand:0")
	await _shot(prefix + "_char_greatsword_locked.png")
	# a refused equip: the shield on the Great Sword card
	var result: Dictionary = gs.get_session().command({"type": "equip", "item": "nope", "source": "stash", "card": "greatsword"})
	print("REFUSE ", result)
	ch.select_tab("outfit")
	await _shot(prefix + "_char_outfit_tab.png")
	quit()
