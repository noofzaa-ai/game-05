extends RefCounted
const F := preload("res://tests/online_fixture.gd")
const Bot := preload("res://tests/journey_bot.gd")
const Codec := preload("res://logic/state_codec.gd")
const SimInput := preload("res://logic/sim_input.gd")

func run(ctx) -> void:
	for boss in [false, true]:
		var first := trace(boss)
		var second := trace(boss)
		ctx.check("M1-4 seeded journey bot %s identical every60ticks" % ("boss" if boss else "normal"), first == second and first.size() == 20)

	for count in [2,4]:
		var first := trace_party(count)
		ctx.check("M1/M2 party%d exact replay every60ticks" % count, first == trace_party(count) and first.size() == 20)

static func trace(boss: bool) -> Array:
	var f := F.make()
	var sim = F.simulation(f, boss)
	var react := F.rng(888)
	var decided := {}
	var hashes: Array = []
	for tick in 1200:
		var input = Bot._decide(sim, f["combat"], .7, react, decided, tick)
		sim.set_input(1, SimInput.decode(input.encode()))
		sim.tick()
		if (tick + 1) % 60 == 0:
			hashes.append(Codec.digest(sim.snapshot()))
	return hashes

static func trace_party(count: int) -> Array:
	var f := F.make()
	var trips := {1:f.run}
	for id in range(2,count+1): trips[id] = F.make(77+id).run
	f.journey = preload("res://logic/coop_journey.gd").start_party(f.data,trips,f.rules,f.loot,f.combat.weapon_ids,77)
	var sim = F.simulation(f,true)
	var reactions := {}
	var decisions := {}
	for id in trips:
		reactions[id] = F.rng(888+id)
		decisions[id] = {}
	var hashes: Array = []
	for tick in 1200:
		for id in trips:
			var input = Bot._decide(sim,f.combat,.7,reactions[id],decisions[id],tick,id)
			sim.set_input(id,SimInput.decode(input.encode()))
		sim.tick()
		f.journey.capture_party(sim)
		if sim._coop.wiped: f.journey.died()
		for event in sim.events:
			if event.type == "stage_cleared" and not f.journey.is_over(): f.journey.stage_cleared(f.journey.hp_fraction)
		if (tick+1)%60 == 0: hashes.append(Codec.digest({"sim":sim.snapshot(),"journey":f.journey.to_dict()}))
	return hashes
