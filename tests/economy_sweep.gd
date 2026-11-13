extends SceneTree
## Balance check (not in run_all): plays stages with the scripted bot and compares what a trip earns
## (gold, ore and the other materials, after selling nothing) with what repairing the worn gear costs.
##   godot --headless --path . --script res://tests/economy_sweep.gd
## Gear: the starter set, and a fuller set (weapon + 5 armor pieces at Rare) to see a mid-game kit.

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Fighter := preload("res://logic/fighter.gd")
const GameSim := preload("res://logic/game_sim.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const JourneyBot := preload("res://tests/journey_bot.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Repair := preload("res://logic/repair.gd")
const Run := preload("res://logic/run.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const SEEDS := 12
const FULL_SET := ["race_human_sword_shield_shirt", "race_human_sword_shield_pants", "race_human_sword_shield_armband", "race_human_sword_shield_shoes"]


func _initialize() -> void:
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var loot := LootDataLoader.load_default(camp.materials.keys(), rules.tiers.size())
	var combat := CombatDataLoader.load_default()
	for map_id in ["ink_garden", "shrine_wall"]:
		for kit in ["starter", "full_rare"]:
			for skill in [0.5, 0.85]:
				var total := {"won": 0, "gold": 0, "ore": 0, "leather": 0, "essence": 0, "repair_gold": 0, "repair_ore": 0, "repair_leather": 0, "repair_essence": 0, "broken": 0}
				for seed in SEEDS:
					var result := _trip(map_id, kit, skill, seed, rules, camp, loot, combat)
					for key in result:
						total[key] += result[key]
				var line := "%s %-9s skill %.2f  won %d/%d | earns gold %5.0f ore %4.1f leather %4.1f essence %4.1f | repair gold %5.0f ore %4.1f leather %4.1f essence %4.1f (broken pieces %.1f)" % [
					map_id, kit, skill, total["won"], SEEDS,
					total["gold"] / float(SEEDS), total["ore"] / float(SEEDS), total["leather"] / float(SEEDS), total["essence"] / float(SEEDS),
					total["repair_gold"] / float(SEEDS), total["repair_ore"] / float(SEEDS), total["repair_leather"] / float(SEEDS), total["repair_essence"] / float(SEEDS), total["broken"] / float(SEEDS)]
				print(line)
	quit()


func _trip(map_id: String, kit: String, skill: float, seed: int, rules, camp, loot, combat) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var profile = Profile.new_player(rules, camp, rng)
	if kit == "full_rare":
		profile.loadout.equip(ItemSystem.create_item(rules, "w", "weapon", 1, rng, "", "race_human_sword_shield_weapon"))
		for item_id in FULL_SET:
			profile.loadout.equip(ItemSystem.create_item(rules, item_id, rules.catalog.entry(item_id)["slot"], 1, rng, "", item_id))
	var start_gold: int = profile.stash.gold
	var start := {}
	for id in camp.materials:
		start[id] = profile.stash.material_count(id)
	var run = Run.start(profile, camp)
	var map = MapLoader.load_by_id(map_id)
	var world := SimWorld.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var sim := GameSim.new(world, combat, rng)
	sim.add_player(JourneyBot.PLAYER, map.spawn)
	sim.attach_run(JourneyBot.PLAYER, run, rules, loot)
	var next_id := 100
	for spawn in map.enemy_spawns:
		sim.add_enemy(next_id, spawn["position"], spawn["type"], spawn["level"])
		next_id += 1
	var react := RandomNumberGenerator.new()
	react.seed = seed * 31 + 7
	var decided := {}
	var tick := 0
	while tick < 60 * 240:
		var me: Fighter = sim.fighters[JourneyBot.PLAYER]
		if not me.is_alive() or sim.living_enemy_count() == 0:
			break
		sim.set_input(JourneyBot.PLAYER, JourneyBot._decide(sim, combat, skill, react, decided, tick))
		sim.tick()
		tick += 1
	var won: bool = sim.fighters[JourneyBot.PLAYER].is_alive() and sim.living_enemy_count() == 0
	if won:
		run.return_to_camp()
	var result := {"won": 1 if won else 0, "gold": profile.stash.gold - start_gold, "broken": 0}
	for id in ["ore", "leather", "essence"]:
		result[id] = profile.stash.material_count(id) - int(start[id])
		result["repair_" + id] = 0
	result["repair_gold"] = 0
	for item in profile.loadout.items():
		var quote := Repair.quote(item, camp)
		result["repair_gold"] += int(quote["gold"])
		if quote["kind"] == "broken":
			result["broken"] += 1
		for id in quote["materials"]:
			result["repair_" + id] += int(quote["materials"][id])
	return result
