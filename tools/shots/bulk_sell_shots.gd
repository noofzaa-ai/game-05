extends SceneTree
## Shop Sell tab bulk-sale buttons (White / Blue / White+Blue) with a mixed fixture stash. Run windowed:
##   godot --path . --script res://tools/shots/bulk_sell_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/bulk_sell/<W>x<H>).
const ItemSystem := preload("res://logic/item_system.gd")
const Shop := preload("res://logic/shop.gd")


func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _piece(rules, id: String, slot: String, tier: int, item_id: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	return ItemSystem.create_item(rules, id, slot, tier, rng, "", item_id)


func _dump(shop, p, label: String) -> void:
	var tiers := {}
	for it in p.stash.items:
		tiers[it.tier] = int(tiers.get(it.tier, 0)) + 1
	print(label, " stash=", p.stash.items.size(), " tiers=", tiers, " gold=", p.stash.gold, " status=", shop._status.text)
	for key in shop.BULK:
		var b: Button = shop._bulk_buttons[key]
		print("  ", key, " text='", b.text, "' disabled=", b.disabled, " visible=", b.is_visible_in_tree(), " rect=", b.get_global_rect(), " plan=", shop.bulk_plan(p, key)["ids"])


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var prefix := OS.get_environment("ZORX_SHOT")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://build/bulk_sell/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var p = gs.profile
	var rules = gs.item_rules
	p.stash.items.clear()
	p.stash.capacity = 80
	var n := 0
	for tier in [0, 0, 0, 1, 1, 2, 3, 0, 1]:
		n += 1
		p.stash.items.append(_piece(rules, "fx-%d" % n, ["shirt", "pants", "shoes"][n % 3], tier, "armour_magic_" + ["shirt", "pants", "shoes"][n % 3]))
	p.stash.items.append(_piece(rules, "fx-boss-w", "ring", 0, "boss_goblin_chief_ring"))
	p.stash.items.append(_piece(rules, "fx-boss-b", "necklace", 1, "boss_orc_warlock_necklace"))
	p.stash.items.append(_piece(rules, "fx-boss-sword", "weapon", 1, "boss_orc_warlock_sword"))
	var relic = _piece(rules, "fx-relic", "shirt", 0, "armour_magic_shirt")
	p.stash.items.append(relic)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(p.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(p.stash.gold)
	screen._layout()
	for i in 20:
		await process_frame
	screen.open_service("shop")
	var shop = screen._panels["shop"]
	shop.select_tab("sell")
	_dump(shop, p, "BEFORE")
	await _shot(prefix + "_0_sell.png")
	shop._bulk_pressed("white")
	_dump(shop, p, "WHITE ARMED")
	await _shot(prefix + "_1_white_armed.png")
	await shop._bulk_pressed("white")
	for i in 4:
		await process_frame
	_dump(shop, p, "WHITE SOLD")
	await _shot(prefix + "_2_white_sold.png")
	shop._bulk_pressed("both")
	_dump(shop, p, "BOTH ARMED")
	await _shot(prefix + "_3_both_armed.png")
	await shop._bulk_pressed("both")
	for i in 4:
		await process_frame
	_dump(shop, p, "BOTH SOLD")
	await _shot(prefix + "_4_both_sold.png")
	shop.close()
	quit()
