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


## Wave mode (data/journeys/goblin_waves.json): one fight, 12 waves, counts x1.5, the boss last; the squad of 3 wins it.
func _wave_checks(ctx) -> void:
	var f := F.make(31)
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	ctx.check("the wave journey file is valid %s" % [data.errors], data.is_valid() and data.wave_mode and is_equal_approx(data.wave_count_scale, 1.5))
	var trips := {1: f.run, 2: F.make(32).run, 3: F.make(33).run}
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
	var released := 0
	var memories := {}
	for id in journey.player_ids():
		memories[id] = Pilot.new_memory(id)
	var tick := 0
	var boss_seen := false
	while tick < 60 * 600 and (sim.living_enemy_count() + sim.pending_wave_count() > 0):
		for id in journey.player_ids():
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick, 0.9).encode()))
		sim.tick()
		tick += 1
		for id in sim.fighters:
			if sim.fighters[id].enemy_type == "goblin_chief":
				boss_seen = true
		var alive := 0
		for id in journey.player_ids():
			if sim.fighters[id].is_alive(): alive += 1
		if alive == 0: break
	ctx.check("the squad clears all 12 waves, the Chief included (ticks %d)" % tick, sim.living_enemy_count() + sim.pending_wave_count() == 0 and boss_seen)
