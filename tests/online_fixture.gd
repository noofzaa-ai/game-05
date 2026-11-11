extends RefCounted
const Rules := preload("res://logic/item_rules_loader.gd")
const Camp := preload("res://logic/camp_data_loader.gd")
const Loot := preload("res://logic/loot_data_loader.gd")
const Combat := preload("res://logic/combat_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const Cosmetic := preload("res://logic/cosmetic_options.gd")

static func rng(seed_value: int = 77) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = seed_value
	return result

static func make(seed_value: int = 77) -> Dictionary:
	var rules = Rules.load_default()
	var camp = Camp.load_default(rules.tiers.size())
	var loot = Loot.load_default(camp.materials.keys(), rules.tiers.size())
	var combat = Combat.load_default()
	var profile = Profile.new_player(rules, camp, rng(seed_value))
	var trip = Run.start(profile, camp)
	var data = JourneyData.load_by_id("ink_road", combat.enemies.keys())
	return {"profile": profile, "run": trip, "rules": rules, "camp": camp,
		"loot": loot, "combat": combat, "data": data, "location": "camp",
		"cosmetics": Cosmetic.load_default(),
		"journey": Journey.start(data, trip, rules, loot, combat.weapon_ids, seed_value)}

static func simulation(f: Dictionary, boss: bool = false):
	var journey = f["journey"]
	if boss:
		journey.completed = journey.data.stage_count - 1
	journey.choose(0)
	var map = Map.load_by_id(journey.current["map"])
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var sim := Sim.new(world, f["combat"], rng(12345))
	sim.add_player(1, map.spawn)
	sim.attach_run(1, f["run"], f["rules"], f["loot"])
	journey.populate(sim, map, 1, 100)
	return sim
