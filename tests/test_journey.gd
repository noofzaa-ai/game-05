extends RefCounted
## The 12-stage journey: how its choices are laid out, the difficulty curve, treasure and challenge
## rewards, the flow from the first fight to the boss (and death), and the path screen.

const Bot := preload("res://tests/journey_bot.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const GameSim := preload("res://logic/game_sim.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")

var _combat
var _rules
var _camp
var _loot
var _data


func run(ctx) -> void:
	_combat = CombatDataLoader.load_default()
	_rules = ItemRulesLoader.load_default()
	_camp = CampDataLoader.load_default(_rules.tiers.size())
	_loot = LootDataLoader.load_default(_camp.materials.keys(), _rules.tiers.size())
	_data = JourneyData.load_by_id("ink_road", _combat.enemies.keys())
	ctx.check("the journey data loads without errors %s" % [_data.errors], _data.is_valid())
	if not _data.is_valid():
		return
	ctx.check("bag banking at camp is on (Boss 2026-10-09)", _data.camp_banks_bag == true)
	ctx.check("a broken journey file reports errors", not JourneyData.parse("{\"version\": 1}").is_valid())
	_check_generation(ctx)
	_check_curve(ctx)
	_check_rewards(ctx)
	_check_flow(ctx)
	await _check_screen(ctx)


func _new_journey(seed: int) -> Journey:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var profile = Profile.new_player(_rules, _camp, rng)
	return Journey.start(_data, Run.start(profile, _camp), _rules, _loot, _combat.weapon_ids, seed)


func _check_generation(ctx) -> void:
	var shape_ok := true
	var camps_ok := true
	var choices_ok := true
	var no_rest := true
	var first_camps := {}
	var slots := 0
	var treasures := 0
	var challenges := 0
	for seed in range(1, 301):
		var journey := _new_journey(seed)
		shape_ok = shape_ok and journey.nodes.size() == 12 and journey.nodes[11].size() == 1 and journey.nodes[11][0]["kind"] == "boss"
		shape_ok = shape_ok and journey.nodes[0].size() == 1 and journey.nodes[0][0]["kind"] == "combat"
		var camp_stages: Array[int] = []
		for stage in range(1, 13):
			var options: Array = journey.nodes[stage - 1]
			if options.size() == 1 and options[0]["kind"] == "camp":
				camp_stages.append(stage)
			for node in options:
				no_rest = no_rest and node["kind"] != "rest"
				if node["kind"] == "camp" and options.size() != 1:
					camps_ok = false
			if stage in [1, 12] or camp_stages.has(stage):
				continue
			choices_ok = choices_ok and options.size() == 3 and options.any(func(n): return n["kind"] == "combat")
			for node in options:
				choices_ok = choices_ok and JourneyData.CHOICE_TYPES.has(node["kind"])
				if node["kind"] in ["combat", "challenge"]:
					choices_ok = choices_ok and _data.fight_map_pool().has(node["map"])
				slots += 1
				treasures += 1 if node["kind"] == "treasure" else 0
				challenges += 1 if node["kind"] == "challenge" else 0
		camps_ok = camps_ok and camp_stages.size() == 2 and camp_stages[1] == 11 and camp_stages[0] in [5, 6, 7] and camp_stages[0] == journey.first_camp
		first_camps[journey.first_camp] = true
	ctx.check("every journey has 12 stages: a plain fight first, the boss last", shape_ok)
	ctx.check("exactly two camps: one at stage 5, 6 or 7 and one at stage 11", camps_ok)
	ctx.check("the first camp lands on each of 5, 6 and 7 across seeds", first_camps.size() == 3)
	ctx.check("other stages offer 3 choices (combat/challenge/treasure), always one plain combat", choices_ok)
	ctx.check("there are no plain rest nodes among the choices", no_rest)
	var treasure_share := float(treasures) / float(slots)
	ctx.check("treasure is rare (%.1f%% of choice slots, 3-20%%)" % (treasure_share * 100.0), treasure_share > 0.03 and treasure_share < 0.2)
	ctx.check("challenges are offered (%d of %d slots)" % [challenges, slots], challenges > slots / 10)
	ctx.check("the same seed lays out the same journey", str(_new_journey(42).nodes) == str(_new_journey(42).nodes))
	ctx.check("different seeds lay out different journeys", str(_new_journey(42).nodes) != str(_new_journey(43).nodes))


func _check_curve(ctx) -> void:
	var rising := true
	var harder := true
	var last := 0.0
	for stage in range(1, 12):
		var fight: Dictionary = _data.stages[stage - 1]
		var threat := Journey.threat(fight, _combat)
		rising = rising and threat >= last
		last = threat
		if not fight.get("challenge", {}).is_empty():
			harder = harder and Journey.threat(fight["challenge"], _combat) > threat
	ctx.check("plain fights get no easier from stage 1 to 11", rising)
	ctx.check("a challenge is harder than the plain fight at the same stage", harder)
	ctx.check("the boss is the hardest plain fight", Journey.threat(_data.stages[11], _combat, _data.boss) > last)
	# Late stages retuned friendlier for the enlarged arena pool incl. goblin_arena_c (Boss 2026-10-14;
	# bot skill 0.6, 300 runs on goblin_arena_a/b/c: st9 plain 99% / challenge 64%, st10 97/57%, st11 71/57%;
	# boss on brush_ring 35/40/67% at skill 0.3/0.6/0.9). The bigger floors let the ranged goblins kite, so
	# the small-arena numbers no longer held. Lock the new threat band so a later edit is a choice, not drift.
	var late_ok := true
	var late_text := ""
	for stage in [9, 10, 11]:
		var plain := Journey.threat(_data.stages[stage - 1], _combat)
		var hard := Journey.threat(_data.stages[stage - 1]["challenge"], _combat)
		late_text += " st%d %.2f/%.2f" % [stage, plain, hard]
		late_ok = late_ok and plain >= 3.1 and plain <= 4.0 and hard >= 3.9 and hard <= 4.6
	ctx.check("stages 9-11 keep the enlarged-arena tuning (plain 3.1-4.0, challenge 3.9-4.6 threat):%s" % late_text, late_ok)
	ctx.check("the boss keeps its tuning (power 0.85, hp_mult 1.3)", is_equal_approx(float(_data.stages[11]["power"]), 0.85) and is_equal_approx(float(_data.boss["hp_mult"]), 1.3))
	ctx.check("stages 1-2 are gentle (at most ~1 base grunt pair each)", Journey.threat(_data.stages[0], _combat) <= 1.0 and Journey.threat(_data.stages[1], _combat) <= 1.2)
	# A fresh starter-gear character played by an unskilled bot clears stage 1 and 2 every time.
	var wins := 0
	for seed in range(1, 4):
		for stage in [1, 2]:
			var journey := _new_journey(seed)
			journey.current = {"stage": stage, "kind": "combat", "map": _data.combat_maps[seed % _data.combat_maps.size()]}
			var result := Bot.play(journey, _combat, seed, 0.3)
			wins += 1 if result["won"] and result["hp"] > 0.6 else 0
	ctx.check("an unskilled bot with starter gear clears stages 1-2 with most of its health (%d/6)" % wins, wins == 6)
	# Each goblin variant's first stage (archer 3, mage 5, knight 6) is an introduction, not a wall: a
	# middling bot (it guards arrows and steps out of hex circles 60% of the time) with starter gear and
	# full health wins every time with at least 55% health left (measured 2026-10-12: about 75-85%).
	var intro_hp := []
	var intro_ok := true
	for stage in [3, 5, 6]:
		for seed in range(1, 3):
			var journey := _new_journey(seed)
			journey.current = {"stage": stage, "kind": "combat", "map": _data.combat_maps[seed % _data.combat_maps.size()]}
			var result := Bot.play(journey, _combat, seed, 0.6)
			intro_hp.append(snappedf(result["hp"], 0.01))
			intro_ok = intro_ok and result["won"] and result["hp"] >= 0.55
	ctx.check("the archer, mage and knight introductions (stages 3, 5, 6) are won with health to spare %s" % [intro_hp], intro_ok)


func _check_rewards(ctx) -> void:
	var rare: int = _rules.tiers.map(func(t): return t["id"]).find("rare")
	var all_ok := true
	var tiers := {}
	for seed in range(1, 201):
		var journey := _new_journey(seed)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var item = journey.treasure_item(rng)
		all_ok = all_ok and item != null and item.tier >= rare and _rules.slot(item.slot).size() > 0 and not item.item_id.is_empty()
		if item != null:
			tiers[item.tier] = true
	ctx.check("treasure always gives a wearable catalog piece (with a model) of tier rare or better", all_ok)
	ctx.check("treasure tiers vary (rare and better)", tiers.size() >= 2)
	var journey := _new_journey(5)
	journey.nodes[1] = [{"stage": 2, "kind": "treasure", "map": ""}]
	journey.stage_cleared(1.0)  # (not in a fight: ignored)
	journey.state = Journey.CHOOSING
	journey.completed = 1
	journey.choose(0)
	ctx.check("choosing treasure waits for its chest: nothing in the bag yet", journey.state == Journey.AT_NODE and journey.is_treasure_closed() and journey.run.bag.items.is_empty())
	var opened := journey.open_treasure()
	ctx.check("opening the treasure puts the piece in the bag without a fight", opened.get("items", []).size() == 1 and journey.run.bag.items.size() == 1 and not journey.is_treasure_closed())
	ctx.check("a treasure opens only once", journey.open_treasure().is_empty() and journey.run.bag.items.size() == 1)
	journey.leave_node()
	ctx.check("leaving the treasure moves on to stage 3", journey.state == Journey.CHOOSING and journey.stage_number() == 3)
	var unopened := _new_journey(6)
	unopened.nodes[1] = [{"stage": 2, "kind": "treasure", "map": ""}]
	unopened.completed = 1
	unopened.choose(0)
	unopened.leave_node()
	ctx.check("a treasure left unopened still lands in the bag (leave_node opens it)", unopened.run.bag.items.size() == 1 and unopened.stage_number() == 3)
	# Challenge pays more than a plain fight over many seeds (its extra reward roll).
	var challenge_gold := 0
	for seed in range(1, 41):
		var j := _new_journey(seed)
		j.completed = 3
		j.nodes[3] = [{"stage": 4, "kind": "challenge", "map": "ink_garden"}]
		j.choose(0)
		j.stage_cleared(0.5)
		challenge_gold += int(j.last_reward.get("gold", 0))
	ctx.check("a won challenge pays an extra reward", challenge_gold > 0)


## Plays a journey end to end through its rules: real fights for the first stages (bot), then the
## remaining stages by their results, a camp heal, the boss set-up, the win; and a death.
func _check_flow(ctx) -> void:
	var journey := _new_journey(7)
	journey.choose(0)
	var first := Bot.play(journey, _combat, 7, 0.6)
	ctx.check("stage 1 is won by the bot", first["won"])
	journey.stage_cleared(first["hp"])
	ctx.check("after stage 1 the player picks stage 2 from 3 choices", journey.state == Journey.CHOOSING and journey.choices().size() == 3 and journey.progress_text() == "Stage 2/12")
	var camp_healed := false
	while journey.state == Journey.CHOOSING and journey.stage_number() < 12:
		var options: Array = journey.choices()
		var pick := 0
		for i in options.size():
			if options[i]["kind"] == "combat":
				pick = i
		var node := journey.choose(pick)
		if node["kind"] == "camp":
			journey.hp_fraction = 1.0
			camp_healed = journey.state == Journey.AT_NODE
			journey.run.bag.gold = 40
			var stash_before: int = journey.run.profile.stash.gold
			ctx.check("a camp offers bag banking", journey.can_bank_bag())
			journey.bank_bag()
			ctx.check("banking at a camp moves the bag to the stash and the journey goes on", journey.run.profile.stash.gold == stash_before + 40 and journey.run.bag.gold == 0 and journey.state == Journey.AT_NODE)
			ctx.check("a camp cannot be left with the bag lost", journey.abandon().is_empty() and not journey.is_over())
			journey.leave_node()
		else:
			journey.stage_cleared(0.3)
	ctx.check("camps were visited on the way", camp_healed and journey.path.count("camp") == 2)
	ctx.check("stage 12 is the boss room", journey.choices().size() == 1 and journey.choices()[0]["kind"] == "boss")
	journey.hp_fraction = 0.3
	journey.choose(0)
	var map = MapLoader.load_by_id(str(journey.current["map"]))
	ctx.check("the boss map loads", map.is_valid())
	var sim := _sim_for(map, journey)
	var bosses := journey.populate(sim, map, 1, 100)
	var base: Dictionary = _combat.enemy_stats("goblin_chief", int(_data.stages[11]["level"]))
	var boss = sim.fighters[bosses[0]] if bosses.size() == 1 else null
	ctx.check("one boss with boosted HP and poise", boss != null and is_equal_approx(boss.max_hp(), float(base["HP"]) * float(_data.stages[11]["power"]) * float(_data.boss["hp_mult"])) and float(_data.boss["hp_mult"]) > 1.0 and boss.max_poise > float(_combat.enemies["goblin_chief"]["poise"]) and boss.enemy_type == "goblin_chief")
	ctx.check("the player keeps the health carried over", is_equal_approx(sim.fighters[1].hp, sim.fighters[1].max_hp() * 0.3))
	# Boss 2026-10-12: the archer and mage are wave 2; they join when the Chief drops below boss_hp_below.
	var starters: Array = sim.fighters.values().filter(func(f): return f.team == "enemy").map(func(f): return f.enemy_type)
	ctx.check("the boss fight opens without its archer and mage (wave 2 waits) %s" % [starters], not starters.has("goblin_archer") and not starters.has("goblin_mage") and sim.pending_wave_count() == 1)
	sim.tick()
	ctx.check("wave 2 stays back while the Chief is healthy", sim.pending_wave_count() == 1)
	boss.hp = boss.max_hp() * (float(_data.stages[11]["waves"]["boss_hp_below"]) - 0.05)
	sim.tick()
	var arrived: Array = sim.events.filter(func(e): return e["type"] == "wave_arrived")
	var now: Array = sim.fighters.values().filter(func(f): return f.team == "enemy").map(func(f): return f.enemy_type)
	ctx.check("a hurt Chief calls the archer and mage (wave 2) %s" % [now], sim.pending_wave_count() == 0 and arrived.size() == 1 and now.has("goblin_archer") and now.has("goblin_mage"))
	journey.run.bag.gold = 55
	var stash_gold: int = journey.run.profile.stash.gold
	journey.stage_cleared(0.2)
	ctx.check("beating the boss wins the journey", journey.state == Journey.WON and journey.is_over())
	journey.run.return_to_camp()
	ctx.check("the won bag comes home", journey.run.profile.stash.gold == stash_gold + 55)

	# Leaving before a camp: the bag is lost, the stash is kept, and there is no going home with it.
	var quitter := _new_journey(5)
	quitter.choose(0)
	quitter.stage_cleared(0.8)
	quitter.run.bag.gold = 25
	var quitter_stash: int = quitter.run.profile.stash.gold
	ctx.check("going home with the bag only works from a camp", quitter.retreat().is_empty() and quitter.state == Journey.CHOOSING)
	quitter.abandon()
	ctx.check("leaving before a camp loses the bag and ends the journey", quitter.state == Journey.ABANDONED and quitter.is_over() and quitter.run.bag.gold == 0 and quitter.run.profile.stash.gold == quitter_stash)

	# Death in the middle: the bag is lost and the journey ends.
	var doomed := _new_journey(9)
	doomed.choose(0)
	doomed.run.bag.gold = 30
	var doomed_map = MapLoader.load_by_id(str(doomed.current["map"]))
	var doomed_sim := _sim_for(doomed_map, doomed)
	doomed.hp_fraction = 0.02
	doomed.populate(doomed_sim, doomed_map, 1, 100)
	var bag_lost := false
	for i in 60 * 60:
		doomed_sim.set_input(1, SimInput.new())
		doomed_sim.tick()
		bag_lost = bag_lost or doomed_sim.events.any(func(e): return e["type"] == "bag_lost")
		if not doomed_sim.fighters[1].is_alive():
			break
	ctx.check("a player standing still at 2% health is killed and loses the bag", bag_lost and doomed.run.bag.gold == 0)
	doomed.died()
	ctx.check("death ends the journey", doomed.state == Journey.LOST and doomed.choices().is_empty() and doomed.retreat().is_empty())


func _sim_for(map, journey) -> GameSim:
	var world := SimWorld.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sim := GameSim.new(world, _combat, rng)
	sim.add_player(1, map.spawn)
	sim.attach_run(1, journey.run, _rules, _loot)
	return sim


## The path screen and a journey stage in the real scenes.
func _check_screen(ctx) -> void:
	var game_state: Node = ctx.root.get_node_or_null("GameState")
	if not game_state.ensure_profile():
		ctx.check("profile for the journey screen", false)
		return
	game_state.auto_battle = false
	ctx.check("a journey starts from the hub call", game_state.start_journey("ink_road", 11))
	# Stage 1 is a single plain fight: the journey goes straight into it (no route screen first).
	for i in 30:
		await ctx.process_frame
	var stage: Node = ctx.current_scene
	var sim = stage.get("_session") if stage != null else null
	ctx.check("the chosen fight loads the stage with the journey's monsters", sim != null and stage.get("_journey") != null and sim.living_enemy_count() == 4)
	ctx.check("the HUD line shows the stage progress", stage != null and str(stage.call("_bag_text")).begins_with("Stage 1/12"))
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			sim.fighters[id].hp = 1.0
			sim.fighters[id].stats["DEF"] = 0.0
	game_state.journey.stage_cleared(1.0)  # (the clear itself is covered above; move the journey on)
	game_state.go_journey()
	for i in 4:
		await ctx.process_frame
	var buttons: Array = ctx.current_scene.get("_buttons")
	ctx.check("the route screen (fallback, Esc between stages) offers the 3 choices for stage 2", ctx.current_scene.scene_file_path == "res://scenes/journey.tscn" and buttons.size() == 3)
	game_state.journey = null
	game_state.go_hub()
	for i in 3:
		await ctx.process_frame
