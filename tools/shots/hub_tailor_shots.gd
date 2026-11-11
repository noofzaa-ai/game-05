extends SceneTree
## Tailor (and Shop) shots. Run windowed:
##   godot --path . --script res://tools/shots/hub_tailor_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/hub4/<W>x<H>).
func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 8:
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
		prefix = ProjectSettings.globalize_path("res://build/hub4/%dx%d" % [size.x, size.y])
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
	for i in 20:
		await process_frame
	# Tailor from the side menu: hair, then a look change
	screen.open_service("tailor")
	var tailor = screen._panels["tailor"]
	tailor.select_card("greatsword")
	tailor.select_category("hair")
	for i in 20:
		await process_frame
	await _shot(prefix + "_tailor_hair_before.png")
	await tailor._set_look("hair", "e")
	print("LOOK hair=", gs.profile.card_deck["cards"]["greatsword"]["hair"], " status=", tailor._status.text)
	for i in 10:
		await process_frame
	await _shot(prefix + "_tailor_hair_after.png")
	tailor.select_category("eyes")
	await _shot(prefix + "_tailor_eyes.png")
	# Fashion: buy one copy, wear it on Great Sword, then refuse the same piece on a second card
	tailor.select_category("fashion")
	tailor.select_piece("red")
	await _shot(prefix + "_tailor_fashion_before.png")
	await tailor._buy("fashion", "red")
	print("BUY status=", tailor._status.text, " owned=", gs.profile.mall_owned.count("fashion:red"))
	await tailor._wear("fashion", "red")
	print("WEAR status=", tailor._status.text)
	await _shot(prefix + "_tailor_fashion_after.png")
	tailor.select_card("longbow")
	tailor.select_piece("red")
	await tailor._wear("fashion", "red")
	print("REFUSE status=", tailor._status.text)
	await _shot(prefix + "_tailor_no_free_copy.png")
	tailor.select_category("back")
	await _shot(prefix + "_tailor_back.png")
	tailor.close()
	# the character screen's Outfit tab opens the Tailor for that card
	screen.open_character("sword_shield")
	for i in 20:
		await process_frame
	screen._character.select_tab("outfit")
	await _shot(prefix + "_char_outfit_tab_tailor.png")
	print("OUTFIT tab tailor visible=", screen._panels["tailor"].visible, " card=", screen._panels["tailor"].card)
	screen._panels["tailor"].close()
	screen._character.close()
	for i in 6:
		await process_frame
	# Shop: Buy (the stock is empty with the current data), Sell one piece, mark two and sell them together
	screen.open_service("shop")
	var shop = screen._panels["shop"]
	shop.select_tab("buy")
	await _shot(prefix + "_shop_buy.png")
	shop.select_tab("sell")
	var first = gs.profile.stash.items[0] if not gs.profile.stash.items.is_empty() else null
	if first != null:
		shop.select_item(first.id)
	await _shot(prefix + "_shop_sell_before.png")
	var gold_before: int = gs.profile.stash.gold
	if first != null:
		await shop._sell(first.id, load("res://logic/shop.gd").item_sell_price(first, gs.item_rules))
	print("SELL gold ", gold_before, " -> ", gs.profile.stash.gold, " status=", shop._status.text)
	await _shot(prefix + "_shop_sell_after.png")
	for n in 2:
		if n < gs.profile.stash.items.size():
			shop._toggle_mark(gs.profile.stash.items[n].id)
	await _shot(prefix + "_shop_marked.png")
	gold_before = gs.profile.stash.gold
	await shop._sell_marked()
	print("BATCH gold ", gold_before, " -> ", gs.profile.stash.gold, " status=", shop._status.text)
	await _shot(prefix + "_shop_batch_after.png")
	shop.close()
	quit()
