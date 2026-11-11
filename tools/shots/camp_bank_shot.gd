extends SceneTree
## The journey camp's Rest tab with the "Store the bag in the stash" button: before storing (bag full
## of loot), after storing (the confirmation, button disabled "bag is empty"), and the camp rules saying
## no; on a desktop window (1600x900) and a phone in landscape (932x430). Needs a window (no --headless):
##   godot --path . --script res://tools/shots/camp_bank_shot.gd -- <out_dir>

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")

const SIZES := {"desktop": Vector2i(1600, 900), "phone": Vector2i(932, 430)}


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://camp_bank"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var combat := CombatDataLoader.load_default()
	var loot = LootDataLoader.load_default(camp.materials.keys(), rules.tiers.size())
	for size_name in SIZES:
		root.size = SIZES[size_name]
		for frame in 5:
			await process_frame
		for case in ["ready", "stored", "not_allowed"]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var data = JourneyData.load_by_id("ink_road", combat.enemies.keys())
			data.camp_banks_bag = case != "not_allowed"
			var profile = Profile.new_player(rules, camp, rng)
			var journey = Journey.start(data, Run.start(profile, camp), rules, loot, combat.weapon_ids, 7)
			journey.state = Journey.AT_NODE
			journey.current = {"stage": 5, "kind": "camp", "map": ""}
			for slot in ["shirt", "pants", "weapon"]:
				journey.run.bag.add_item(ItemSystem.create_item(rules, "loot-" + slot, slot, 2, rng))
			journey.run.bag.gold = 140
			journey.run.bag.add_material("ore", 6)
			var screen: CanvasLayer = load("res://client/camp_screen.gd").new()
			screen.density_override = 1.0  # (the window is in points: 932x430 is a phone held sideways)
			root.add_child(screen)
			screen.setup(profile, camp, rules, combat, journey.run, "journey_camp_5", journey)
			screen._tabs.current_tab = 1
			print(size_name, " ", case, " layout ", screen.layout["mode"], " scale ", screen.layout["scale"], " logical ", root.get_visible_rect().size, " window ", DisplayServer.window_get_size(), " bank button ", screen.find_child("Bank", true, false).size.y if screen.find_child("Bank", true, false) else -1.0, " units = ", (screen.find_child("Bank", true, false).size.y * screen._points_per_unit) if screen.find_child("Bank", true, false) else -1.0, " pt")
			for frame in 10:
				await process_frame
			if case == "stored":
				screen._request_bank()
				for frame in 10:
					await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("rest_%s_%s.png" % [case, size_name]))
			if case == "ready":  # the inventory tab before storing (the bag grid full)
				screen._tabs.current_tab = 0
				for frame in 6:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join("inventory_before_%s.png" % size_name))
			if case == "stored":
				screen._tabs.current_tab = 0
				for frame in 6:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join("inventory_after_%s.png" % size_name))
			screen.queue_free()
			await process_frame
	quit()
