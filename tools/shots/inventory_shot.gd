extends SceneTree
## Renders the camp inventory with the test kit (client/test_kit.gd: every modeled weapon and armor piece)
## and part of the Aegis set worn, to a PNG. Optional 2nd arg: a filter category to open (weapon/armor).
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/inventory_shot.gd -- <out.png>

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Profile := preload("res://logic/profile.gd")
const TestKit := preload("res://client/test_kit.gd")


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://inventory.png"
	root.size = Vector2i(1600, 900)
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var profile = Profile.new_player(rules, camp, rng)
	var kit := TestKit.fill(profile, rules, camp, rng)
	for item_id in ["aegis_helmet", "aegis_bracers", "aegis_tassets"]:
		for index in profile.stash.items.size():
			if profile.stash.items[index].item_id == item_id:
				profile.equip_from_stash(index)
				break
	print("test kit: %d pieces, stash %d/%d" % [kit, profile.stash.slots_used(), profile.stash.capacity])
	await process_frame  # (the autoloads the screen uses start first)
	var screen: CanvasLayer = load("res://client/camp_screen.gd").new()
	root.add_child(screen)
	screen.setup(profile, camp, rules, CombatDataLoader.load_default())
	for frame in 20:
		await process_frame
	var gear = screen.gear
	if OS.get_cmdline_user_args().size() > 1:
		gear._set_category(OS.get_cmdline_user_args()[1])
	for key in gear.slot_cells:
		if key.begins_with("hat"):
			gear.slot_cells[key].pressed_cell.emit(gear.slot_cells[key]) if gear.slot_cells[key].has_signal("pressed_cell") else null
	for frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
