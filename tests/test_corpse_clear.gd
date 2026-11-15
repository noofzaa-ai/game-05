extends RefCounted
## Fallen enemies leave a wave-mode fight (logic/game_sim.gd corpse_clear_ticks, Boss 2026-11-15: 3 s after they fall).
## - the wave journey data sets 3 s and populate hands the sim 180 ticks; a plain sim keeps its corpses (0);
## - a fallen enemy stays exactly corpse_clear_ticks ticks, then leaves fighters, bodies, AI and inputs;
## - it waits while a shot of its own is still flying;
## - the same seed and inputs give the same fight, kills, loot and waves cleared with and without clearing
##   (clearing never touches the RNG or rewards), and the sim no longer carries every corpse by the late waves;
## - a checkpoint keeps the clearing state.
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
	var f := F.make(51)
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	ctx.check("the wave journey clears corpses after 3 s (%.1f)" % data.corpse_clear_seconds, is_equal_approx(data.corpse_clear_seconds, 3.0))
	var plain = F.simulation(f)
	ctx.check("a plain sim keeps its corpses (corpse_clear_ticks 0)", plain.corpse_clear_ticks == 0)

	# Exact timing on a plain sim: kill enemy 2 by hand, count ticks until it is gone.
	var sim = F.simulation(F.make(52))
	sim.corpse_clear_ticks = 180
	var enemy := -1
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			enemy = id
			break
	_kill(sim, enemy)
	var gone_after := -1
	for tick in 400:
		sim.tick()
		if not sim.fighters.has(enemy):
			gone_after = tick + 1
			break
	ctx.check("a fallen enemy leaves the sim 180 ticks (3 s) after it fell (%d)" % gone_after, gone_after >= 180 and gone_after <= 182)
	ctx.check("it leaves bodies, AI and inputs too", not sim.bodies.has(enemy) and not sim._ai.has(enemy) and not sim._inputs.has(enemy) and not sim._fallen.has(enemy))

	# A shot of its own still flying keeps it in the sim (projectiles look up their owner).
	var shooter = F.simulation(F.make(53))
	shooter.corpse_clear_ticks = 2
	var archer := -1
	for id in shooter.fighters:
		if shooter.fighters[id].team == "enemy":
			archer = id
			break
	_kill(shooter, archer)
	shooter._ranged["projectiles"].append({"id": 999, "owner": archer, "life": 100000})
	for tick in 5:
		shooter._clear_corpses()
		shooter.tick_count += 1
	var kept: bool = shooter.fighters.has(archer)
	shooter._ranged["projectiles"].clear()
	shooter._clear_corpses()
	ctx.check("a corpse with a shot still out stays, then goes once the shot ended", kept and not shooter.fighters.has(archer))

	# Whole wave fights, same seed: corpses cleared vs kept (the old way).
	var cleared := _wave_fight(f, data, 31, true, ctx)
	var kept_run := _wave_fight(f, data, 31, false, ctx)
	print("    (wave fight seed 31: cleared %s / kept %s)" % [cleared, kept_run])
	ctx.check("clearing corpses keeps the fight identical: ticks, waves, kills, loot (%s vs %s)" % [cleared.digest, kept_run.digest], cleared.digest == kept_run.digest)
	ctx.check("the late waves carry no pile of corpses (max %d fighters in the sim vs %d)" % [cleared.max_fighters, kept_run.max_fighters], cleared.max_fighters < kept_run.max_fighters and cleared.end_dead <= 12 and kept_run.end_dead > 30)
	ctx.check("the fight reaches the late waves (wave %d)" % cleared.waves, cleared.waves >= 8)
	# Seed 1 used to report the stage cleared with waves still queued (a race-trigger kill after the wave release).
	var early := _wave_fight(f, data, 1, true, ctx)
	ctx.check("a wave fight is never reported cleared while waves are still queued (%d)" % early.early_clear, early.early_clear == 0)

	# Checkpoints keep the clearing state.
	var saved = F.simulation(F.make(54))
	saved.corpse_clear_ticks = 180
	var victim := -1
	for id in saved.fighters:
		if saved.fighters[id].team == "enemy":
			victim = id
			break
	_kill(saved, victim)
	for tick in 10:
		saved.tick()
	var g := F.make(54)
	var copy = F.simulation(g)
	var restored: bool = copy.restore(saved.snapshot(), g["camp"])
	ctx.check("a checkpoint keeps corpse_clear_ticks and when each corpse fell", restored and copy.corpse_clear_ticks == 180 and copy._fallen.get(victim, -1) == saved._fallen.get(victim, -2))


func _kill(sim, id: int) -> void:
	sim.fighters[id].hp = 0.0
	sim.fighters[id].state = Fighter.State.DEAD
	sim.fighters[id].state_ticks = 0


## One wave fight of the starter squad with the auto-pilot. Returns a digest of everything the run decides
## (tick count, waves, kills in order, loot) plus how many fighters the sim carried.
func _wave_fight(f: Dictionary, data, seed_value: int, clear: bool, ctx) -> Dictionary:
	var members: Array = preload("res://logic/squad_member.gd").make_squad(F.make(seed_value).run, Array(preload("res://logic/card_deck.gd").STARTER_SQUAD))
	var trips := {}
	for i in members.size():
		trips[i + 1] = members[i]
	var journey = Party.start_party(data, trips, f.rules, f.loot, f.combat.weapon_ids, seed_value)
	while journey.state != journey.IN_STAGE and not journey.is_over():
		journey.choose(0)
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid.box)
	var sim := Sim.new(world, f.combat, F.rng(seed_value))
	journey.populate(sim, map, 1, 100)
	if not clear:
		sim.corpse_clear_ticks = 0
	var starter: Array = Array(preload("res://logic/card_deck.gd").STARTER_SQUAD)
	for i in starter.size():
		sim.set_class_style(i + 1, str(preload("res://logic/card_deck.gd").class_data(str(starter[i])).get("weapon", "")))
	var memories := {}
	for id in journey.player_ids():
		memories[id] = Pilot.new_memory(id)
	var kills: Array = []
	var gold := 0
	var items := 0
	var max_fighters := 0
	var early_clear := 0
	var tick := 0
	while tick < 60 * 600 and sim.living_enemy_count() + sim.pending_wave_count() > 0:
		for id in journey.player_ids():
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick, 0.9).encode()))
		sim.tick()
		tick += 1
		journey.note_waves(sim)
		max_fighters = maxi(max_fighters, sim.fighters.size())
		for event in sim.events:
			match str(event["type"]):
				"stage_cleared":
					if sim.pending_wave_count() > 0: early_clear += 1
				"killed":
					kills.append([tick, int(event["target"]), int(event.get("by", -1))])
				"loot":
					gold += int(event["gold"])
					items += event["items"].size()
		var alive := 0
		for id in journey.player_ids():
			if sim.fighters[id].is_alive(): alive += 1
		if alive == 0: break
	var end_dead := 0
	for id in sim.fighters:
		if not sim.fighters[id].is_alive() and sim.fighters[id].team == "enemy": end_dead += 1
	var hp := 0.0
	for id in journey.player_ids():
		hp += maxf(0.0, sim.fighters[id].hp)
	return {"digest": "t%d w%d k%d h%d g%d i%d hp%.2f" % [tick, journey.waves_cleared, kills.size(), hash(kills), gold, items, hp],
		"max_fighters": max_fighters, "end_dead": end_dead, "early_clear": early_clear, "waves": sim._waves_released + 1}
