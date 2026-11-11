extends SceneTree
## Saves the same UI screens at several window sizes, for theme mockups and before/after checks:
##   camp_<size>.png  the camp Inventory tab (a fixed test kit, one worn piece badly worn, a weapon selected)
##   hud_<size>.png   the in-combat HUD with low HP, buffs/debuffs, a combo, loot lines and a skill banner
##   hud_<size>_low_boss.png  low HP (the warning pulse) with a boss bar (not in `plain` runs)
##   hub_<size>.png, journey_<size>.png  the campfire menu and the journey route (not in `plain` runs)
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/ui_theme_shots.gd -- <out_dir> [theme] [plain]
## `theme` is a name from client/ui_themes.gd ("" or "current" = the default look). `plain` puts the
## HUD over a flat backdrop instead of the live stage, so two runs give identical pixels (for diffs).

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Profile := preload("res://logic/profile.gd")

const CAMP_SIZES := {"wide": Vector2i(1600, 900), "phone_landscape": Vector2i(932, 430), "portrait": Vector2i(430, 932)}
var _plain := false
var _stage: Node  ## the HUD shots' stage (freed before the campfire and journey shots)

const HUD_SIZES := {"wide": Vector2i(1600, 900), "phone_landscape": Vector2i(932, 430), "portrait": Vector2i(430, 932)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://ui_shots"
	var theme: String = args[1] if args.size() > 1 else ""
	var plain: bool = args.size() > 2 and args[2] == "plain"
	if not ("/" in out or "\\" in out or ":" in out):  # a theme name given first would write a folder into the project
		push_error("ui_theme_shots: give the output folder first (a path), then the theme")
		quit(1)
		return
	_plain = plain
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame  # (the autoloads start first)
	if theme != "" and theme != "current":
		var themes = load("res://client/ui_themes.gd")
		if not themes.apply(theme):
			push_error("unknown theme " + theme)
			quit(1)
			return
	await _camp_shots(out, plain)
	await _hud_shots(out, plain)
	if not plain:
		await _flow_shots(out)
	quit()


func _camp_shots(out: String, plain: bool) -> void:
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var profile = Profile.new_player(rules, camp, rng)
	var ids: Array = rules.catalog.items.keys()
	ids.sort()
	var count := 0
	for item_id in ids:
		if rules.catalog.entry(item_id)["slot"] == "weapon" and count < 14:
			profile.stash.add_item(ItemSystem.create_item(rules, item_id, "weapon", count % 4, rng, "", item_id))
			count += 1
	for item_id in ["aegis_helmet", "aegis_bracers", "aegis_tassets"]:
		profile.loadout.equip(ItemSystem.create_item(rules, item_id, rules.catalog.entry(item_id)["slot"], 2, rng, "", item_id))
	profile.loadout.items()[0].durability = 8.0  # a piece close to breaking: the danger mark
	var screen: CanvasLayer = load("res://client/camp_screen.gd").new()
	root.add_child(screen)
	screen.setup(profile, camp, rules, CombatDataLoader.load_default())
	for size_name in CAMP_SIZES:
		root.size = CAMP_SIZES[size_name]
		await _frames(12)
		var gear = screen.gear
		if not gear.bag_cells.is_empty():
			gear.select(gear._selection_for(gear.bag_cells[1]))
		if plain:
			gear.doll._texture.visible = false  # (the 3D doll idles in real time: not the same pixels twice)
			await _frames(2)
		await _save(out.path_join("camp_%s.png" % size_name))
	if plain:  # the other tabs and the character creator too, for the before/after check
		root.size = CAMP_SIZES["wide"]
		for tab in [1, 2, 3]:
			screen.show_tab(tab)
			await _frames(8)
			if screen.look != null:
				screen.look.doll._texture.visible = false
			await _save(out.path_join("camp_tab%d.png" % tab))
		screen.queue_free()
		await _frames(2)
		var creator: CanvasLayer = load("res://client/character_creator.gd").new()
		root.add_child(creator)
		creator.setup(profile, rules, CombatDataLoader.load_default())
		creator._rng.seed = 3
		creator.randomize_look()
		await _frames(8)
		creator.look.doll._texture.visible = false
		await _save(out.path_join("creator.png"))
		creator.queue_free()
		await _frames(2)
		return
	screen.queue_free()
	await _frames(2)


func _hud_shots(out: String, plain: bool) -> void:
	root.get_node("GameState").ensure_profile()
	var stage: Node = load("res://scenes/stage.tscn").instantiate()
	_stage = stage
	root.add_child(stage)
	await _frames(20)
	stage.set_physics_process(false)  # freeze the fight; the HUD is fed by hand below
	if plain:
		var layer := CanvasLayer.new()
		layer.layer = 0
		var back := ColorRect.new()
		back.color = Color(0.32, 0.36, 0.30)
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(back)
		root.add_child(layer)
	var hud = stage._hud
	var data = stage._combat_data
	var player = stage._session._sim.fighters[stage.LOCAL_PLAYER_ID]
	player.stats["HP"] = 1000.0  # (the profile's gear is random: fixed numbers keep runs comparable)
	player.stats["STAMINA"] = 100.0
	player.hp = player.max_hp() * 0.38
	player.energy = player.max_energy() * 0.22
	player.gauge = float(data.rules["ultimate_gauge_max"]) * 0.6
	player.dodge_cooldown = 40
	player.effects = {
		"rage": {"left": 420, "stacks": 1, "dps": 0.0, "age": 0, "source": 1},
		"poison": {"left": 210, "stacks": 2, "dps": 0.0, "age": 0, "source": 2},
	}
	player.combo_dealt = 7
	player.combo_damage = 1234
	player.combo_timer = 40
	hud.set_prompt("Q  =  rest point (sort the bag, heal, go home)")
	for size_name in HUD_SIZES:
		root.size = HUD_SIZES[size_name]
		hud.compact_override = 0 if size_name == "wide" else 1
		hud._layout()
		for i in 150:  # ~2.5 s: the HP trail settles
			hud.update_from(player, data, 3, "Camera 8 High", "Bag 9/20    Gold 340")
			await process_frame
		hud.add_loot("+ Golden Blossom Katana  Epic", _tier("purple"))
		hud.add_loot("+ Ash Spear  Rare", _tier("blue"))
		hud.add_loot("+ 25 gold", _tier("gold"))
		hud.show_skill_banner("Crescent Cut")
		for i in 24:
			hud.update_from(player, data, 3, "Camera 8 High", "Bag 9/20    Gold 340")
			await process_frame
		if plain:  # stop everything that moves with real time
			hud.set_process(false)
			hud._skill_tween.kill()
			hud._set_bar(hud._hp, hud._hp_shown, 0.6)
			hud._skill_banner.scale = Vector2.ONE
			hud._skill_banner.modulate.a = 1.0
			hud._combo_count.scale = Vector2.ONE
			hud._combo_box.modulate.a = 1.0
			await _frames(2)
		await _save(out.path_join("hud_%s.png" % size_name))
		hud.set_process(true)
		for line in hud._loot_feed.get_children():
			line.free()
	if not plain and hud.has_method("set_boss"):  # low HP (the warning pulse) and a boss bar
		player.hp = player.max_hp() * 0.18
		for size_name in ["wide", "phone_landscape"]:
			root.size = HUD_SIZES[size_name]
			hud.compact_override = 0 if size_name == "wide" else 1
			hud._layout()
			for i in 90:
				hud.update_from(player, data, 1, "Camera 8 High", "Bag 9/20    Gold 340")
				hud.set_boss("Ink Warlord", 0.62)
				await process_frame
			await _save(out.path_join("hud_%s_low_boss.png" % size_name))
		hud.set_boss("", 0.0)


## The campfire menu and the journey route, at the camp sizes.
func _flow_shots(out: String) -> void:
	var game_state = root.get_node("GameState")
	_stage.queue_free()
	await _frames(2)
	game_state.ensure_profile()
	game_state.profile.created = true
	game_state.go_hub()
	await _frames(30)
	for size_name in CAMP_SIZES:
		root.size = CAMP_SIZES[size_name]
		await _frames(12)
		await _save(out.path_join("hub_%s.png" % size_name))
	game_state.start_journey("ink_road", 11)
	await _frames(20)
	for size_name in CAMP_SIZES:
		root.size = CAMP_SIZES[size_name]
		await _frames(12)
		await _save(out.path_join("journey_%s.png" % size_name))


func _tier(key: String) -> Color:
	var item_text: Script = load("res://client/item_text.gd")
	if item_text.get_script_constant_map().has("TIER_COLORS"):  # (the code before the token refactor)
		return item_text.get_script_constant_map()["TIER_COLORS"][key]
	var ink_ui: Script = load("res://client/ink_ui.gd")
	return ink_ui.call("rarity_color", key, not _plain)  # (plain: the menu colors, as the old code had them)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
