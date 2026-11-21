extends SceneTree
## Orc Warlock weapons in the UI (Boss 2026-11-21): the run-end summary of a won orc_camp run with the sword + shield (boss
## gold cells), Storage (bag) with the sword selected (details: gold name + boss option line), the hero card of a level-20
## Sword & Shield card wearing both with the shield selected, and the in-fight drop popups. Run windowed:
##   godot --path . --script res://tools/shots/orc_warlock_weapon_ui_shots.gd
## ZORX_SIZE=WxH (default 1920x1080). Output: build/orc_warlock_weapons/ui_<W>x<H>_*.png
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
	var prefix := ProjectSettings.globalize_path("res://build/orc_warlock_weapons/ui_%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var rules = gs.item_rules
	var ItemSystem = load("res://logic/item_system.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var sword = ItemSystem.create_item(rules, "shot-wl-sword", "weapon", 1, rng, "", "boss_orc_warlock_sword")
	var shield = ItemSystem.create_item(rules, "shot-wl-shield", "offhand", 2, rng, "", "boss_orc_warlock_shield")
	var sword2 = ItemSystem.create_item(rules, "shot-wl-sword2", "weapon", 3, rng, "", "boss_orc_warlock_sword")
	# 1) run-end summary
	var Journey = load("res://logic/journey.gd")
	var j = Journey.new()
	var data = load("res://logic/journey_data.gd").new()
	data.wave_mode = true
	data.display_name = "Orc Camp"
	data.stage_count = 9
	j.data = data
	j.state = Journey.WON
	j.boss_loot = {"1": {"zone": "orc_camp", "coin": "coin_orc_warlock", "coins": 1, "items": [sword, shield], "relics": {}, "first_kill": false}}
	gs.journey = j
	gs.run_loot = {"items": [], "gold": 180, "materials": {"ore": 2}, "wave": 9}
	change_scene_to_file(gs.JOURNEY_SCENE)
	await create_timer(1.5).timeout
	await _shot(prefix + "_summary.png")
	gs.journey = null
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	# 2) storage + hero card
	gs.profile.stash.items.push_front(sword2)
	gs.profile.stash.capacity = maxi(gs.profile.stash.capacity, gs.profile.stash.items.size() + 2)
	load("res://logic/card_progress.gd").grant(gs.profile.card_deck, "sword_shield", 999999)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = root.get_visible_rect().size
	screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 20:
		await process_frame
	screen.open_service("storage")
	var store = screen._panels["storage"]
	store.select_item(sword2.id)
	await _shot(prefix + "_storage_sword.png")
	store.close()
	var worn = gs.profile.loadout_of("sword_shield")
	print("equip sword ", worn.equip(sword, 0), " shield ", worn.equip(shield, 0), " problem ", gs.profile.wear_problem("sword_shield", shield, rules))
	screen.open_character("sword_shield")
	for i in 40:
		await process_frame
	screen._character.select_slot("offhand:0")
	await _shot(prefix + "_char_shield.png")
	screen._character.select_slot("weapon:0")
	await _shot(prefix + "_char_sword.png")
	screen.queue_free()
	# 3) drop popups
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
	var n := 0
	for pair in [["boss_orc_warlock_sword", 1], ["boss_orc_warlock_shield", 0], ["boss_mummy_boss_crook", 2], ["race_human_sword_shield_weapon", 3]]:
		var id: String = pair[0]
		var color: Color = InkUi.rarity_color(ItemText.rarity_key_for(id, int(pair[1]), rules), true)
		popups.show_pickup(Vector3(-1.5, 0, 0), "%s ×1" % str(rules.catalog.entry(id).get("name", id)), color, ItemAssets.icon_for_id(id, rules.catalog, "human"), n)
		n += 1
	for i in 3:
		await process_frame
	await _shot(prefix + "_drop_popups.png")
	quit()
