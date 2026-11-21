extends SceneTree
## Orc Warlock boss accessory set shots (2026-11-21): the Warlock pieces in Storage (bag + tooltip), worn on the hero card,
## and as in-fight drop popups. Copy of boss_gold_shots.gd with the Warlock ids. Run windowed:
##   godot --path . --script res://tools/shots/orc_warlock_set_shots.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=path prefix (default build/orc_warlock_set/<W>x<H>).
## Shots: Storage with boss pieces (gold frames) and a boss staff selected (details: gold name + boss option), the
## character screen with boss pieces worn and the necklace selected, and the in-fight drop popups (boss vs zone).
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
		prefix = ProjectSettings.globalize_path("res://build/orc_warlock_set/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	# the project's canvas_items stretch stays on (as the game runs): 844x390 shows the real phone canvas scaled
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var rules = gs.item_rules
	var ItemSystem = load("res://logic/item_system.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var made := {}
	var tiers := {"boss_orc_warlock_necklace": 1, "boss_orc_warlock_earring": 0, "boss_orc_warlock_bracelet": 2, "boss_orc_warlock_ring": 1,
		"boss_orc_warlock_back": 3, "boss_mummy_high_wizard_ring": 2, "boss_goblin_chief_bracelet": 0}
	for id in tiers:
		var piece = ItemSystem.create_item(rules, "shot-" + id, str(rules.catalog.entry(id)["slot"]), int(tiers[id]), rng, "", id)
		gs.profile.stash.items.push_front(piece)
		made[id] = piece
	gs.profile.stash.capacity = maxi(gs.profile.stash.capacity, gs.profile.stash.items.size())
	load("res://logic/card_progress.gd").grant(gs.profile.card_deck, "sword_shield", 999999)  # level 20+: the pieces are wearable
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = root.get_visible_rect().size
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 20:
		await process_frame
	# Storage: boss pieces first, the staff selected
	screen.open_service("storage")
	var store = screen._panels["storage"]
	store.select_item(made["boss_orc_warlock_necklace"].id)
	await _shot(prefix + "_storage_warlock_necklace.png")
	store.select_item(made["boss_orc_warlock_back"].id)
	await _shot(prefix + "_storage_warlock_cloak.png")
	store.close()
	# character (hero card): wear the mummy necklace + ring + cloak on the Sword & Shield card, select the necklace
	var worn = gs.profile.loadout_of("sword_shield")
	for id in ["boss_orc_warlock_necklace", "boss_orc_warlock_earring", "boss_orc_warlock_bracelet", "boss_orc_warlock_ring", "boss_orc_warlock_back"]:
		gs.profile.stash.items.erase(made[id])
		worn.equip(made[id], 0)
	screen.open_character("sword_shield")
	for i in 30:
		await process_frame
	screen._character.select_slot("ring:0")
	await _shot(prefix + "_char_warlock_ring.png")
	screen._character.select_slot("back:0")
	await _shot(prefix + "_char_warlock_cloak.png")
	screen.queue_free()
	# drop popups: a boss drop and a legendary zone drop side by side (the real LootPopups node over a camera)
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 6, 8)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.14, 0.12)
	bg.size = root.get_visible_rect().size
	var layer := CanvasLayer.new()
	layer.layer = -1
	layer.add_child(bg)
	root.add_child(layer)
	var popups = load("res://client/loot_popups.gd").new()
	var top := CanvasLayer.new()
	top.add_child(popups)
	root.add_child(top)
	await process_frame
	var InkUi = load("res://client/ink_ui.gd")
	var ItemText = load("res://client/item_text.gd")
	var ItemAssets = load("res://client/item_assets.gd")
	var lines := [["boss_orc_warlock_necklace", 1], ["boss_orc_warlock_ring", 0], ["boss_orc_warlock_back", 2], ["race_human_sword_shield_weapon", 3]]
	var n := 0
	for pair in lines:
		var id: String = pair[0]
		if rules.catalog.entry(id).is_empty():
			continue
		var color: Color = InkUi.rarity_color(ItemText.rarity_key_for(id, int(pair[1]), rules), true)
		popups.show_pickup(Vector3(-1.5, 0, 0), "%s ×1" % str(rules.catalog.entry(id).get("name", id)), color, ItemAssets.icon_for_id(id, rules.catalog, "human"), n)
		n += 1
	for i in 3:
		await process_frame
	await _shot(prefix + "_drop_popups.png")
	quit()
