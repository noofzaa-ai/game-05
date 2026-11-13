extends RefCounted
## The auto-battle brain (logic/auto_pilot.gd): it must clear fights through the normal rules with no help.
const F := preload("res://tests/online_fixture.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Party := preload("res://logic/coop_journey.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const JourneyData := preload("res://logic/journey_data.gd")


func run(ctx) -> void:
	var idle := SimInput.new()
	var f := F.make(5)
	var sim = F.simulation(f)
	var memory := Pilot.new_memory(3)
	var downed = Pilot.decide(sim, f.combat, 1, memory, 0)
	ctx.check("a living fighter next to enemies produces some input", downed != null)
	sim.fighters[1].state = Fighter.State.DEAD
	var dead = Pilot.decide(sim, f.combat, 1, memory, 0)
	ctx.check("a dead fighter does nothing", dead.move == Vector2.ZERO and not dead.light and not dead.heavy and not dead.ultimate)

	# One unit vs the first fight, three units vs the first fight: the pilot alone must win.
	for count in [1, 3]:
		var result := _play_first_stage(count, 77)
		ctx.check("%d auto unit(s) win the first stage (ticks %d)" % [count, result.ticks], result.won and not result.timeout)
		ctx.check("%d auto unit(s) keep someone alive" % count, result.alive > 0)
	# Same seed, same input stream: replays are exact.
	_wave_checks(ctx)
	_class_checks(ctx)
	_card_select_checks(ctx)
	var a := _play_first_stage(1, 99)
	var b := _play_first_stage(1, 99)
	ctx.check("the pilot is deterministic for a given seed", a.ticks == b.ticks and is_equal_approx(a.hp, b.hp))


func _play_first_stage(count: int, seed: int) -> Dictionary:
	var f := F.make(seed)
	var trips := {1: f.run}
	for id in range(2, count + 1):
		trips[id] = F.make(seed + id).run
	var journey = Party.start_party(f.data, trips, f.rules, f.loot, f.combat.weapon_ids, seed) if count > 1 else F.Journey.start(f.data, trips[1], f.rules, f.loot, f.combat.weapon_ids, seed)
	while journey.state != journey.IN_STAGE and not journey.is_over():
		if journey.state == journey.CHOOSING:
			journey.choose(0)
		elif journey.state == journey.AT_NODE:
			journey.leave_node()
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid.box)
	var sim := Sim.new(world, f.combat, F.rng(seed))
	var ids: Array = journey.player_ids() if journey.has_method("player_ids") else [1]
	if ids.size() == 1:
		sim.add_player(1, map.spawn)
		sim.attach_run(1, journey.run, journey.item_rules, journey.loot_data)
	journey.populate(sim, map, 1, 100)
	var memories := {}
	for id in ids:
		memories[id] = Pilot.new_memory(seed * 31 + id)
	var tick := 0
	var max_ticks := 60 * 180
	while tick < max_ticks and sim.living_enemy_count() + sim.pending_wave_count() > 0:
		var any_alive := false
		for id in ids:
			if sim.fighters[id].is_alive():
				any_alive = true
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick).encode()))
		if not any_alive:
			break
		sim.tick()
		tick += 1
	var alive := 0
	var hp := 0.0
	for id in ids:
		if sim.fighters[id].is_alive():
			alive += 1
		hp += maxf(0.0, sim.fighters[id].hp)
	return {"won": sim.living_enemy_count() + sim.pending_wave_count() == 0 and alive > 0, "ticks": tick, "timeout": tick >= max_ticks, "alive": alive, "hp": hp}


## Party trips {1.., member} for these class cards on one account trip (logic/squad_member.gd, as the game does).
static func _squad_trips(base, cards: Array) -> Dictionary:
	var members: Array = preload("res://logic/squad_member.gd").make_squad(base, cards)
	var trips := {}
	for i in members.size():
		trips[i + 1] = members[i]
	return trips


## Wave mode (data/journeys/goblin_waves.json): one fight, 12 waves, counts x1.5, the boss last; the squad of 3 wins it.
func _wave_checks(ctx) -> void:
	var f := F.make(31)
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	ctx.check("the wave journey file is valid %s" % [data.errors], data.is_valid() and data.wave_mode and is_equal_approx(data.wave_count_scale, 1.5))
	# The squad as the game builds it (one account, each card with its own race, gear and skills; SquadMember),
	# the same squad tools/balance/class_sim.gd measures. Plain runs would have no race passives or ultimates.
	var trips := _squad_trips(f.run, Array(preload("res://logic/card_deck.gd").STARTER_SQUAD))
	var journey = Party.start_party(data, trips, f.rules, f.loot, f.combat.weapon_ids, 31)
	ctx.check("a wave journey is one stage with one map", journey.total_stages() == 1 and journey.nodes.size() == 1 and journey.wave_total() == 12)
	while journey.state != journey.IN_STAGE and not journey.is_over():
		if journey.state == journey.CHOOSING:
			journey.choose(0)
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid.box)
	var sim := Sim.new(world, f.combat, F.rng(31))
	journey.populate(sim, map, 1, 100)
	ctx.check("wave 1 has 4 x 1.5 = 6 goblins on the field", sim.living_enemy_count() == 6)
	ctx.check("eleven more waves are queued", sim.pending_wave_count() == 11)
	var starter: Array = Array(preload("res://logic/card_deck.gd").STARTER_SQUAD)
	for i in starter.size():  # as the game does: each squad member fights in its class's style
		sim.set_class_style(i + 1, str(preload("res://logic/card_deck.gd").class_data(str(starter[i])).get("weapon", "")))
	var released := 0
	var memories := {}
	for id in journey.player_ids():
		memories[id] = Pilot.new_memory(id)
	var tick := 0
	var boss_seen := false
	var waves_reached := 1
	while tick < 60 * 600 and (sim.living_enemy_count() + sim.pending_wave_count() > 0):
		for id in journey.player_ids():
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick, 0.9).encode()))
		sim.tick()
		tick += 1
		for event in sim.events:
			if str(event["type"]) == "wave_arrived":
				waves_reached = int(event["wave"])
		for id in sim.fighters:
			if sim.fighters[id].enemy_type == "goblin_chief":
				boss_seen = true
		var alive := 0
		for id in journey.player_ids():
			if sim.fighters[id].is_alive(): alive += 1
		if alive == 0: break
	# Wave mode is tuned to be lost sometimes (starter squad ~75% over 60 seeds at squad power 1.97, 2026-11-13, tools/balance/class_sim.gd),
	# so one fixed seed only has to reach the Chief's wave; the win rate is measured by the sim tool.
	print("    (starter squad, seed 31: reached wave %d, ticks %d, won %s)" % [waves_reached, tick, sim.living_enemy_count() + sim.pending_wave_count() == 0])
	ctx.check("the squad fights through to the Chief's wave (ticks %d)" % tick, boss_seen)
	var chief_wave: Dictionary = data.stages[-1]
	ctx.check("the Chief's wave is the strongest wave", data.stages.all(func(st): return float(st["power"]) <= float(chief_wave["power"])))
	ctx.check("a squad of 3 meets stronger waves than one fighter", data.wave_power_for(3) > data.wave_power_for(1) and is_equal_approx(data.wave_power_for(5), data.wave_power_for(3)))
	var boss_found := false
	var probe := Sim.new(world, f.combat, F.rng(31))
	var trips2 := {1: F.make(31).run, 2: F.make(32).run, 3: F.make(33).run}
	var journey2 = Party.start_party(data, trips2, f.rules, f.loot, f.combat.weapon_ids, 31)
	while journey2.state != journey2.IN_STAGE and not journey2.is_over():
		journey2.choose(0)
	journey2.populate(probe, map, 1, 100)
	var goblin: Dictionary = f.combat.enemy_stats("goblin", int(data.stages[0]["level"]))
	var first_goblin = probe.fighters[100]
	var party_hp := float(f.combat.coop["hp_multiplier"][2])
	ctx.check("wave HP is scaled for the party once (not twice)", is_equal_approx(first_goblin.max_hp(), float(goblin["HP"]) * float(data.stages[0]["power"]) * data.wave_power_for(3) * party_hp))
	for wave in probe._waves:
		for entry in wave["enemies"]:
			if str(entry["type"]) == "goblin_chief":
				boss_found = is_equal_approx(float(entry.get("poise_scale", 1.0)), float(data.boss["poise_mult"]))
	ctx.check("the wave-mode Chief gets the boss poise_mult", boss_found)


## Classes (data/classes/*.json "weapon" -> data/combat/weapons.json): each class fights in its own style.
func _class_checks(ctx) -> void:
	var f := F.make(41)
	var combat = f.combat
	ctx.check("class weapons are styles but never loot weapons", combat.styles.has("longbow") and combat.styles.has("magic") and combat.styles.has("greatsword") and not combat.weapon_ids.has("longbow") and combat.weapon_ids.has("blade"))
	ctx.check("longbow and magic shoot, the great sword and blade swing", not combat.moves["longbow_light_1"]["spawns"].is_empty() and not combat.moves["magic_light_1"]["spawns"].is_empty() and combat.moves["greatsword_light_1"]["spawns"].is_empty() and combat.moves["blade_light_1"]["spawns"].is_empty())
	ctx.check("a shooter stops at range, a melee class at reach", is_equal_approx(Pilot._engage_range(combat, _fighter("longbow")), Pilot.SHOOT_RANGE) and is_equal_approx(Pilot._engage_range(combat, _fighter("blade")), Pilot.REACH) and Pilot._engage_range(combat, _fighter("greatsword")) > Pilot.REACH)
	for seed in [31, 32]:
		var data = JourneyData.load_by_id("goblin_waves", combat.enemies.keys())
		var trips := _squad_trips(F.make(seed).run, ["greatsword", "longbow", "magic"])
		var journey = Party.start_party(data, trips, f.rules, f.loot, combat.weapon_ids, seed)
		while journey.state != journey.IN_STAGE and not journey.is_over():
			if journey.state == journey.CHOOSING:
				journey.choose(0)
		var map = Map.load_by_id(str(journey.current.map))
		var world := World.new()
		world.half_width = map.half_width
		world.half_depth = map.half_depth
		for solid in map.solids:
			world.add_solid(solid.box)
		var sim := Sim.new(world, combat, F.rng(seed))
		journey.populate(sim, map, 1, 100)
		var classes := ["greatsword", "longbow", "magic"]
		for i in 3:
			sim.set_class_style(i + 1, classes[i])
		ctx.check("the class sets the fighter's style (seed %d)" % seed, sim.fighters[1].style == "greatsword" and sim.fighters[2].style == "longbow" and sim.fighters[3].style == "magic")
		var memories := {}
		for id in journey.player_ids():
			memories[id] = Pilot.new_memory(id)
		var tick := 0
		var arrows_seen := false
		while tick < 60 * 600 and (sim.living_enemy_count() + sim.pending_wave_count() > 0):
			for id in journey.player_ids():
				sim.set_input(id, SimInput.decode(Pilot.decide(sim, combat, id, memories[id], tick, 0.9).encode()))
			sim.tick()
			tick += 1
			for shot in sim.projectiles:
				if shot["team"] == "player":
					arrows_seen = true
			var alive := 0
			for id in journey.player_ids():
				if sim.fighters[id].is_alive(): alive += 1
			if alive == 0: break
		ctx.check("great sword + longbow + magic fire their shots (seed %d)" % seed, arrows_seen)
		ctx.check("great sword + longbow + magic fight through to the Chief's wave (seed %d, ticks %d)" % [seed, tick], sim.pending_wave_count() == 0)


func _fighter(style: String) -> Fighter:
	var fighter := Fighter.new()
	fighter.style = style
	return fighter


## Picking a squad card tells the stage which fighter the camera follows.
func _card_select_checks(ctx) -> void:
	var panel = preload("res://client/squad_panel.gd").new()
	var picked := []
	panel.selected.connect(func(id: int) -> void: picked.append(id))
	panel.select(2)
	ctx.check("selecting a card that does not exist is ignored", picked.is_empty())
	panel._cards[2] = {}
	panel.select(2)
	ctx.check("selecting a squad card reports its fighter id", picked == [2])
	panel.free()

