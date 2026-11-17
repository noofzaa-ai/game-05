extends SceneTree
## Item look by race (Boss 2026-11-17): the card character screen of one Sword & Shield card per race, wearing the level-1 starter
## pieces and then the level-15 pieces (same catalog ids, non-starter instance ids). Run windowed:
##   godot --path . --script res://tools/shots/item_look_by_race_shots.gd
## ZORX_SIZE=WxH (default 1600x900), output build/item_look_shots/<race>_<lv>_<W>x<H>.png
const Deck := preload("res://logic/card_deck.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const CARD := "sword_shield"


func _initialize():
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _piece(rules, id: String, slot: String, item_id: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	return ItemSystem.create_item(rules, id, slot, 0, rng, str(rules.catalog.entry(item_id).get("weapon_type", "")), item_id)


func _dress_card(gs, race: String, lv15: bool) -> void:
	var rules = gs.item_rules
	var p = gs.profile
	Deck.set_race(p.card_deck, CARD, race)
	p.card_deck["cards"][CARD]["progress"] = {"level": 15 if lv15 else 1, "xp": 0}
	var worn := Loadout.new(rules)
	var ids := {"weapon": rules.catalog.race_piece(race, CARD, "weapon"), "offhand": rules.catalog.race_shield(race)}
	for slot in ["shirt", "pants", "armband", "shoes"]:
		ids[slot] = rules.catalog.race_piece(race, CARD, slot)
	for slot in ids:
		var prefix := "drop-shot-%s-" % race if lv15 else "starter-kit-v3-%s-" % CARD
		worn.equip(_piece(rules, prefix + slot, slot, str(ids[slot])))
	p.card_gear[CARD]["loadout"] = worn


func run():
	var wanted := OS.get_environment("ZORX_SIZE")
	var size := Vector2i(1600, 900)
	if wanted.contains("x"):
		size = Vector2i(int(wanted.split("x")[0]), int(wanted.split("x")[1]))
	var dir := ProjectSettings.globalize_path("res://build/item_look_shots")
	DirAccess.make_dir_recursive_absolute(dir)
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
	screen._layout()
	for i in 20:
		await process_frame
	for race in RACES:
		for lv15 in [false, true]:
			_dress_card(gs, race, lv15)
			if screen._mode == "character":
				screen._character.close()
				screen._mode = "deck"
			screen.show_deck(gs.profile.card_deck, load("res://client/item_assets.gd").cosmetics())
			screen.open_character(CARD)
			for i in 20:
				await process_frame
			var ch = screen._character
			ch.select_slot("shirt:0")
			var m = ch._portrait.model
			print("LOOK %s %s shirt=%s weapon=%s shield=%s" % [race, "L15" if lv15 else "L1", m._armor_wanted.get("shirt", ""), m._race_weapon_wanted, m._race_shield_wanted])
			await _shot("%s/%s_%s_%dx%d.png" % [dir, race, "L15" if lv15 else "L1", size.x, size.y])
	quit()
