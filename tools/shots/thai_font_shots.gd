extends SceneTree
## Visual check of the Thai UI fonts (Boss, 2026-10-12: Sarabun body, Taviraj display). Renders the
## camp Inventory screen, the in-combat HUD and the journey route, with a few visible labels
## temporarily replaced by Thai text, so a reviewer can see Thai renders (not boxes) in the real
## theme at the real sizes. Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/thai_font_shots.gd -- <out_dir>
## Saves camp/hud/journey_<size>.png for size wide (1600x900) and phone (932x430, phone landscape).

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Profile := preload("res://logic/profile.gd")

const SIZES := {"wide": Vector2i(1600, 900), "phone": Vector2i(932, 430)}
## Thai strings to drop into visible labels (names of things in the game).
const THAI := ["กระเป๋า", "ถือดาบ", "ค่ายพัก", "การเดินทาง", "ทองคำ", "เกราะเหล็ก", "ดาบเถาวัลย์หยก", "พักผ่อน", "ร้านตีเหล็ก"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://thai_font_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	await _camp_shots(out)
	await _hud_shots(out)
	await _journey_shots(out)
	quit()


## Overwrites up to `count` visible, non-empty Label texts under `root_node` with Thai, in tree order.
func _thai_labels(root_node: Node, count: int) -> void:
	var i := 0
	var stack: Array = [root_node]
	while not stack.is_empty() and i < count:
		var node: Node = stack.pop_front()
		for child in node.get_children():
			stack.append(child)
		if node is Label and not (node as Label).text.strip_edges().is_empty() and node.is_visible_in_tree():
			(node as Label).text = THAI[i % THAI.size()]
			i += 1


func _camp_shots(out: String) -> void:
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var profile = Profile.new_player(rules, camp, rng)
	var ids: Array = rules.catalog.items.keys()
	ids.sort()
	var count := 0
	for item_id in ids:
		if rules.catalog.entry(item_id)["slot"] == "weapon" and count < 10:
			profile.stash.add_item(ItemSystem.create_item(rules, item_id, "weapon", count % 4, rng, "", item_id))
			count += 1
	for item_id in ["aegis_helmet", "aegis_bracers", "aegis_tassets"]:
		profile.loadout.equip(ItemSystem.create_item(rules, item_id, rules.catalog.entry(item_id)["slot"], 2, rng, "", item_id))
	var screen: CanvasLayer = load("res://client/camp_screen.gd").new()
	root.add_child(screen)
	screen.setup(profile, camp, rules, CombatDataLoader.load_default())
	for size_name in SIZES:
		root.size = SIZES[size_name]
		await _frames(14)
		_thai_labels(screen, 10)
		await _frames(6)
		await _save(out.path_join("camp_%s.png" % size_name))
	screen.queue_free()
	await _frames(2)


func _hud_shots(out: String) -> void:
	# Build the HUD and a one-player sim directly, so the shot does not depend on scenes/stage.tscn
	# (another agent is mid-edit on the stage / enemy bars). The HUD text path is the same either way.
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var data = CombatDataLoader.load_default()
	var world = load("res://logic/sim_world.gd").new()
	world.half_width = 20.0
	world.half_depth = 20.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sim = load("res://logic/game_sim.gd").new(world, data, rng)
	sim.add_player(1, Vector3.ZERO)
	var run = load("res://logic/run.gd").start(game_state.profile, game_state.camp_data)
	sim.attach_run(1, run, game_state.item_rules, game_state.loot_data)
	var player = sim.fighters[1]
	player.stats["HP"] = 1000.0
	player.stats["STAMINA"] = 100.0
	player.hp = player.max_hp() * 0.5
	player.energy = player.max_energy() * 0.6
	player.gauge = float(data.rules["ultimate_gauge_max"]) * 0.6
	var hud: CanvasLayer = load("res://client/hud.gd").new()
	root.add_child(hud)
	await _frames(6)
	for size_name in SIZES:
		root.size = SIZES[size_name]
		hud.compact_override = 0 if size_name == "wide" else 1
		hud._layout()
		for i in 60:
			hud.update_from(player, data, 3, "Camera 8 High", "Bag 9/20    Gold 340")
			await process_frame
		var ink_ui: Script = load("res://client/ink_ui.gd")
		hud.add_loot("+ ดาบเถาวัลย์หยก  Epic", ink_ui.call("rarity_color", "purple", true))
		hud.add_loot("+ หอกขี้เถ้า  Rare", ink_ui.call("rarity_color", "blue", true))
		hud.add_loot("+ 25 ทอง", ink_ui.call("rarity_color", "gold", true))
		hud.show_skill_banner("จันทร์เสี้ยว")  # a Thai skill name in the display font
		hud.set_prompt("Q  =  จุดพักผ่อน")
		for i in 24:
			hud.update_from(player, data, 3, "Camera 8 High", "Bag 9/20    Gold 340")
			await process_frame
		await _save(out.path_join("hud_%s.png" % size_name))
		for line in hud._loot_feed.get_children():
			line.free()
	hud.queue_free()
	await _frames(2)


func _journey_shots(out: String) -> void:
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.profile.created = true
	game_state.go_hub()
	await _frames(30)
	game_state.start_journey("ink_road", 11)
	await _frames(24)
	var journey := _find_journey(root)
	for size_name in SIZES:
		root.size = SIZES[size_name]
		await _frames(14)
		if journey != null:
			_thai_labels(journey, 8)
		await _frames(6)
		await _save(out.path_join("journey_%s.png" % size_name))


func _find_journey(node: Node) -> Node:
	if node.get_script() != null and str(node.get_script().resource_path).ends_with("journey_screen.gd"):
		return node
	for child in node.get_children():
		var found := _find_journey(child)
		if found != null:
			return found
	return null


func _tier(key: String) -> Color:
	var ink_ui: Script = load("res://client/ink_ui.gd")
	return ink_ui.call("rarity_color", key, true)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
