extends SceneTree
## Hub-look review shots (Boss 2026-11-12): the end-of-run summary (won with loot, lost, left with nothing), the
## battle HUD (squad cards, trip panel, wave banner), the hub's online pill, and the Shop / Storage / Tailor tiles
## with long names. Run windowed:
##   godot --path . --script res://tools/shots/look2_shots.gd
## ZORX_SIZE=WxH (default 1920x1080); PNGs in build/look2/<W>x<H>_*.png.
var _prefix := ""


func _initialize():
	call_deferred("run")


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	await _wait(8)
	await RenderingServer.frame_post_draw
	var path := "%s_%s.png" % [_prefix, name]
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _fake_loot(gs, count: int) -> void:
	gs.run_loot = {"items": [], "gold": 0, "materials": {}, "wave": 7}
	var catalog_ids: Array = gs.item_rules.catalog.items.keys()
	if catalog_ids.is_empty():
		catalog_ids = ["round_shield"]
	var items: Array = []
	for i in count:
		var id: String = str(catalog_ids[(i * 7) % catalog_ids.size()])
		items.append({"item_id": id, "tier": i % 4, "slot": str(gs.item_rules.catalog.entry(id).get("slot", "shirt"))})
	gs.note_run_loot(1234, {"ore": 6, "wood": 11}, items)


func _summary(gs, state: String, wave: int, loot: int, name: String) -> void:
	_fake_loot(gs, loot)
	if loot == 0:
		gs.run_loot = {"items": [], "gold": 0, "materials": {}, "wave": wave}
	gs.run_loot["wave"] = wave
	gs.journey.state = state
	change_scene_to_file(gs.JOURNEY_SCENE)
	await _wait(20)
	await _shot(name)


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	_prefix = ProjectSettings.globalize_path("res://build/look2/%dx%d" % [size.x, size.y])
	DirAccess.make_dir_recursive_absolute(_prefix.get_base_dir())
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var only := OS.get_environment("ZORX_ONLY")
	# The hub with the online pill (offline here).
	if only.is_empty() or only == "hub":
		gs.go_card_deck()
		await _wait(60)
		await _shot("hub_online_pill")
	# Battle HUD: start the wave journey and let a few seconds of the fight run.
	if only.is_empty() or only == "battle" or only == "summary":
		gs.start_journey(gs.DEFAULT_JOURNEY, 77)
		await _wait(30)
	if only.is_empty() or only == "battle":
		Engine.time_scale = 2.0
		await _wait(200)
		var scene = current_scene
		if scene != null and scene.get("_squad_panel") != null:
			var panel = scene._squad_panel
			var ids: Array = panel._order
			if not ids.is_empty():
				panel.callout(ids[0], "Shield Bash", Color(0.4, 0.7, 1.0))
				panel.callout(ids[-1], "Piercing Arrow", Color(0.5, 0.9, 0.4))
		if scene != null and scene.get("_hud") != null:
			scene._hud.show_skill_banner("Wave 3")
		await _wait(12)
		await _shot("battle_hud")
		Engine.time_scale = 1.0
	if only.is_empty() or only == "summary":
		await _summary(gs, "won", 13, 20, "summary_won")
		await _summary(gs, "lost", 7, 5, "summary_lost")
		await _summary(gs, "abandoned", 2, 0, "summary_left_empty")
	if only.is_empty() or only == "tiles":
		gs.journey = null
		gs.profile.stash.gold = 5000
		var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
		screen.auto_wire = false
		change_scene_to_node(screen)
		await _wait(4)
		screen.size = Vector2(size)
		screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
		screen.set_gold(gs.profile.stash.gold)
		screen._layout()
		await _wait(20)
		screen.open_service("shop")
		var shop = screen._panels["shop"]
		shop.select_tab("buy")
		await _shot("shop_buy_names")
		shop.close()
		await _wait(4)
		screen.open_service("tailor")
		var tailor = screen._panels["tailor"]
		tailor.select_card("sword_shield")
		tailor.select_category("fashion")
		await _shot("tailor_fashion_names")
		tailor.close()
		await _wait(4)
		screen.open_service("storage")
		await _shot("storage_names")
	quit()
