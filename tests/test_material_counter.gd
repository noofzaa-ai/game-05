extends RefCounted
## Boss 2026-11-13: materials no longer take bag slots. They are a counter in the run bag and the stash
## (no cap); only items (gear) use slots. Old saves with material stacks load with the same counts and
## those stacks no longer fill slots.
const Inventory := preload("res://logic/inventory.gd")
const Item := preload("res://logic/item.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")


func run(ctx) -> void:
	var bag := Inventory.new(2, {"ore": 99})
	ctx.check("materials: a large material count takes no slot", bag.add_material("ore", 500) == 500 and bag.slots_used() == 0 and bag.free_slots() == 2)
	ctx.check("materials: many kinds take no slot", bag.add_material("herb", 1000) == 1000 and bag.add_material("wood", 3) == 3 and bag.slots_used() == 0)
	ctx.check("materials: items still use slots", bag.add_item(Item.new()) and bag.add_item(Item.new()) and not bag.add_item(Item.new()) and bag.slots_used() == 2)
	ctx.check("materials: a bag full of items still takes materials", bag.add_material("ore", 250) == 250 and bag.material_count("ore") == 750)

	# An old save: a 3-slot stash holding 3 items and 300 ore (formerly 4 slots of stacks: over capacity).
	var rules = ItemRulesLoader.load_default()
	var camp = CampDataLoader.load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var profile = Profile.new_player(rules, camp, rng)
	var saved: Dictionary = profile.to_dict()
	saved["stash"]["materials"] = {"ore": 300, "leather": 150, "essence": 120}
	var loaded = Profile.from_dict(JSON.parse_string(JSON.stringify(saved)), rules, camp)
	ctx.check("materials: an old save keeps its material counts", loaded != null and loaded.stash.material_count("ore") == 300 and loaded.stash.material_count("leather") == 150 and loaded.stash.material_count("essence") == 120)
	ctx.check("materials: an old save's material stacks free their slots", loaded != null and loaded.stash.slots_used() == loaded.stash.items.size())

	# A run: a bag full of items still keeps every material and brings it all home.
	var trip = Run.start(profile, camp)
	while trip.bag.free_slots() > 0:
		trip.bag.add_item(Item.new())
	var got: Dictionary = trip.loot_into_bag({"gold": 5, "materials": {"ore": 400, "herb": 250}, "items": []})
	ctx.check("materials: loot into a full bag loses no material", got["lost_materials"].is_empty() and trip.bag.material_count("ore") == 400)
	var before: int = profile.stash.material_count("ore")
	var home: Dictionary = trip.return_to_camp()
	ctx.check("materials: every material reaches the stash", profile.stash.material_count("ore") == before + 400 and home["left_materials"].is_empty())
