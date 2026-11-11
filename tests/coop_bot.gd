extends RefCounted
## Real combat inputs (the auto-battle pilot, logic/auto_pilot.gd) for every participant, including idle-near-ally revives. No damage injection.
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")

static func play(journey, combat, seed: int, skill: float, max_ticks: int = 18000) -> Dictionary:
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids: world.add_solid(solid.box)
	var sim := Sim.new(world,combat,F.rng(seed))
	var ids: Array = journey.player_ids() if journey.has_method("player_ids") else [1]
	if ids.size() == 1:
		sim.add_player(1,map.spawn)
		sim.attach_run(1,journey.run,journey.item_rules,journey.loot_data)
	journey.populate(sim,map,1,100)
	var memories := {}
	for id in ids:
		memories[id] = Pilot.new_memory(seed * 31 + id)
	var tick := 0
	while tick < max_ticks and (not sim._coop.wiped if ids.size() > 1 else sim.fighters[1].is_alive()) and (sim.living_enemy_count() > 0 or sim.pending_wave_count() > 0):
		for id in ids:
			var input := SimInput.new()
			if sim.fighters[id].is_alive():
				var ally := -1
				for other in ids:
					if sim.fighters[other].state == Fighter.State.DOWNED:
						ally = other
						break
				if ally >= 0:
					var off: Vector3 = sim.bodies[ally].position - sim.bodies[id].position
					if off.length() > float(combat.coop.revive_radius) * .8: input.move = Vector2(off.x,off.z).normalized()
				else:
					input = Pilot.decide(sim,combat,id,memories[id],tick,skill)
			sim.set_input(id,SimInput.decode(input.encode()))
		sim.tick()
		tick += 1
	if ids.size() > 1:
		journey.capture_party(sim)
	else:
		journey.hp_fraction = maxf(0,sim.fighters[1].hp / sim.fighters[1].max_hp())
		journey.gauge = sim.fighters[1].gauge
	var survived: bool = not sim._coop.wiped if ids.size() > 1 else sim.fighters[1].is_alive()
	var won: bool = survived and sim.living_enemy_count() == 0 and sim.pending_wave_count() == 0
	if won: journey.stage_cleared(journey.hp_fraction)
	elif not survived: journey.died()
	return {"won":won,"ticks":tick,"timeout":tick == max_ticks,"sim":sim}

static func journey_run(count: int, seed: int, skill: float) -> Dictionary:
	var f := F.make(seed)
	var trips := {}
	for id in range(1,count+1):
		var trip = F.make(seed + id).run
		trips[id] = trip
	var j = Party.start_party(f.data,trips,f.rules,f.loot,f.combat.weapon_ids,seed) if count > 1 else F.Journey.start(f.data,trips[1],f.rules,f.loot,f.combat.weapon_ids,seed)
	var total_ticks := 0
	var timeouts := 0
	while not j.is_over():
		if j.state == j.CHOOSING:
			var choice := 0
			var options: Array = j.choices()
			for i in options.size():
				if options[i].kind in ["camp","treasure"]:
					choice = i
					break
			j.choose(choice)
		if j.state == j.AT_NODE:
			if j.treasure_pending: j.open_treasure()
			if j.is_at_camp():
				if count > 1:
					for id in j.player_ids(): j.bank_bag_for(id)
				else: j.bank_bag()
			j.leave_node()
		elif j.state == j.IN_STAGE:
			var result := play(j,f.combat,seed * 100 + j.stage_number(),skill)
			total_ticks += result.ticks
			if result.timeout:
				timeouts += 1
				break
	return {"won":j.state == j.WON,"stages":j.completed,"ticks":total_ticks,"timeouts":timeouts,"journey":j}
