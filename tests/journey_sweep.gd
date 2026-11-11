extends SceneTree
## Balance sweep (not part of run_all): for every stage of the journey, plays the plain and the challenge
## fight N times with the journey bot (fresh starter-gear character, full HP) and prints win rate and
## HP left. godot --headless --path . --script res://tests/journey_sweep.gd -- [trials] [skill]

const Bot := preload("res://tests/journey_bot.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var trials := int(args[0]) if args.size() > 0 else 20
	var skills: Array = [float(args[1])] if args.size() > 1 else [0.3, 0.6, 0.9]
	var combat = CombatDataLoader.load_default()
	var rules = ItemRulesLoader.load_default()
	var camp = CampDataLoader.load_default(rules.tiers.size())
	var loot = LootDataLoader.load_default(camp.materials.keys(), rules.tiers.size())
	var data = JourneyData.load_by_id("ink_road", combat.enemies.keys())
	print("errors: ", data.errors)
	for stage in range(1, data.stage_count + 1):
		for type in ["combat", "challenge"]:
			if type == "challenge" and data.stages[stage - 1].get("challenge", {}).is_empty():
				continue
			if stage == data.stage_count and type == "challenge":
				continue
			var line := "stage %2d %-9s threat %6.1f" % [stage, type if stage < data.stage_count else "boss", Journey.threat(data.stages[stage - 1] if type == "combat" else data.stages[stage - 1]["challenge"], combat, data.boss)]
			for skill in skills:
				var wins := 0
				var hp := 0.0
				var ticks := 0
				for t in trials:
					var rng := RandomNumberGenerator.new()
					rng.seed = t + 1
					var profile = Profile.new_player(rules, camp, rng)
					var journey = Journey.start(data, Run.start(profile, camp), rules, loot, combat.weapon_ids, t)
					journey.current = {"stage": stage, "kind": type if stage < data.stage_count else "boss", "map": data.combat_maps[t % data.combat_maps.size()] if stage < data.stage_count else data.boss_map}
					var result := Bot.play(journey, combat, t + 1, skill)
					wins += 1 if result["won"] else 0
					hp += result["hp"] if result["won"] else 0.0
					ticks += result["ticks"]
				line += "  | skill %.1f win %3d%% hp %3d%% %3ds" % [skill, 100 * wins / trials, int(100.0 * hp / maxf(1, wins)), ticks / trials / 60]
			print(line)
	quit()
