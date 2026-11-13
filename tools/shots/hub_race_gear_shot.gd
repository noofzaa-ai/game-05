extends SceneTree
## The hub with the card portraits dressed in each card's worn gear (race outfit, weapon, shield). Run windowed:
##   godot --path . --script res://tools/shots/hub_race_gear_shot.gd
## ZORX_SIZE=WxH (default 1920x1080), ZORX_SHOT=png path (default build/settings_ui/hub_race_gear.png).
## Prints each card's worn weapon and armour ids so the shot can be checked against the profile.
func _initialize():
	call_deferred("run")


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1920, 1080)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var path := OS.get_environment("ZORX_SHOT")
	if path.is_empty():
		path = ProjectSettings.globalize_path("res://build/settings_ui/hub_race_gear.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var assets = load("res://client/item_assets.gd")
	for id in load("res://logic/card_deck.gd").classes():
		var loadout = gs.profile.loadout_of(id)
		var line := "CARD %s:" % id
		for slot in ["weapon", "offhand"] + Array(assets.BODY_SLOTS):
			var item = loadout.item_at(slot, 0) if loadout != null else null
			line += " %s=%s" % [slot, item.item_id if item != null else "-"]
		print(line)
		var looks: Dictionary = assets.looks(loadout, gs.item_rules.catalog, id)
		print("  looks weapon=", looks["weapon"].get("path", ""), " shirt=", looks.get("shirt", ""))
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.size = Vector2(size)
	screen.show_deck(gs.profile.card_deck, assets.cosmetics())
	screen.set_gold(gs.profile.stash.gold)
	screen._layout()
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)
	quit()
