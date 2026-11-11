extends SceneTree
## Hub service panel shots (Blacksmith, Storage). Run windowed:
##   godot --path . --script res://tools/shots/hub_service_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/hub3/<W>x<H>).
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
		prefix = ProjectSettings.globalize_path("res://build/hub3/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	gs.profile.stash.gold = 5000
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 20:
		await process_frame
	# Blacksmith: the Sword & Shield card's weapon, before / after a refine
	screen.open_service("blacksmith")
	var smith = screen._panels["blacksmith"]
	smith.select_source("sword_shield")
	var weapon = gs.profile.loadout_of("sword_shield").item_at("weapon", 0)
	if weapon != null:
		weapon.durability = weapon.max_durability * 0.4
		smith.select_item(weapon.id)
	await _shot(prefix + "_blacksmith_before.png")
	await smith._on_refine()
	print("REFINE level=", weapon.refine_level if weapon != null else -1, " status=", smith._status.text)
	await _shot(prefix + "_blacksmith_after_refine.png")
	await smith._on_upgrade()
	print("UPGRADE count=", weapon.upgrade_count if weapon != null else -1, " status=", smith._status.text)
	await smith._on_repair()
	print("REPAIR dur=", weapon.durability if weapon != null else -1, " status=", smith._status.text)
	await _shot(prefix + "_blacksmith_after_upgrade_repair.png")
	smith.select_source("storage")
	await _shot(prefix + "_blacksmith_storage.png")
	smith.close()
	# Storage: a hat, the wear picker, wear it on the Great Sword card
	screen.open_service("storage")
	var store = screen._panels["storage"]
	var hat = null
	for item in gs.profile.stash.items:
		if item.slot == "hat":
			hat = item
			break
	if hat != null:
		store.select_item(hat.id)
	await _shot(prefix + "_storage_before.png")
	store._show_wear_picker()
	await _shot(prefix + "_storage_wear_picker.png")
	if hat != null:
		await store._wear(hat.id, "greatsword")
	print("WEAR greatsword hat=", gs.profile.loadout_of("greatsword").item_at("hat", 0) != null, " status=", store._status.text)
	await _shot(prefix + "_storage_after_wear.png")
	if not gs.profile.stash.items.is_empty():
		store.select_item(gs.profile.stash.items[0].id)
		store._ask_discard()
		await _shot(prefix + "_storage_discard_confirm.png")
	store.select_tab("vault")
	await _shot(prefix + "_storage_vault.png")
	store.close()
	# from the character screen: the Blacksmith over it, opened on a piece
	screen.open_character("sword_shield")
	for i in 20:
		await process_frame
	screen._character.select_slot("weapon:0")
	await _shot(prefix + "_char_details.png")
	if weapon != null:
		screen.open_blacksmith_on(weapon.id)
	await _shot(prefix + "_char_blacksmith.png")
	quit()
