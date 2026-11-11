extends RefCounted
const F := preload("res://tests/online_fixture.gd")
const Codec := preload("res://logic/state_codec.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const SimInput := preload("res://logic/sim_input.gd")

func run(ctx) -> void:
	_pending_ranged(ctx)
	for boss in [false, true]:
		var f := F.make()
		var sim = F.simulation(f, boss)
		for tick in 300:
			sim.set_input(1, input_for(tick))
			sim.tick()
		# Exercise nondefault fields even if this particular bot has not hit them yet.
		sim.fighters[1].cooldowns["test"] = 100
		sim.fighters[1].hit_ids.assign([100])
		sim._ai[100]._detour_left = 25
		sim._ai[100]._detour_direction = Vector2.LEFT
		sim.wave_heal_fraction = 0.4
		sim.class_styles[1] = sim.fighters[1].style
		var saved: Dictionary = sim.snapshot()
		var digest := Codec.digest(saved)
		var copy := Sim.new(World.new(), f["combat"], F.rng(999))
		copy.item_rules = f["rules"]
		copy.loot_data = f["loot"]
		# checkpoint is JSON-compatible without rounding int64 RNG values or dictionary keys.
		var json_saved := {"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(saved["checkpoint"]))}
		ctx.check("M1-3 restores %s checkpoint" % boss, copy.restore(json_saved, f["camp"]))
		ctx.check("M1-3 immediate full state equals original %s" % boss, Codec.digest(copy.snapshot()) == digest)
		for tick in range(300, 600):
			sim.set_input(1, input_for(tick))
			copy.set_input(1, input_for(tick))
			sim.tick()
			copy.tick()
		ctx.check("M1-3 300+restore+300 equals uninterrupted600 %s" % boss, Codec.digest(copy.snapshot()) == Codec.digest(sim.snapshot()))
		ctx.check("M1-3 saved snapshot remains immutable after live ticks %s" % boss, Codec.digest(saved) == digest)
		ctx.check("M1-3 AI world references rebound %s" % boss, copy._ai[100].world == copy.world)
		ctx.check("wave heal and class styles survive restore %s" % boss, copy.wave_heal_fraction == 0.4 and copy.class_styles.get(1, "") == sim.fighters[1].style)
	var empty := Sim.new(World.new())
	ctx.check("M1-3 version rejection leaves target unchanged", not empty.restore({"v": 9}) and empty.tick_count == 0)
	var a := F.make()
	var source = F.simulation(a)
	ctx.check("M1-3 missing economy dependencies rejected", not Sim.new(World.new(), a["combat"]).restore(source.snapshot()))

static func input_for(tick: int):
	var input := SimInput.new()
	input.move = Vector2.RIGHT if tick % 180 < 90 else Vector2.LEFT
	input.light = tick % 17 == 0
	input.special = tick % 111 == 0
	input.guard = tick % 60 < 10
	input.jump = tick % 121 == 0
	return SimInput.decode(input.encode())


func _pending_ranged(ctx) -> void:
	var f := F.make()
	var sim = F.simulation(f, true)
	var ranged = load("res://logic/projectiles.gd")
	var owner = sim.fighters[100]
	for move_id in f["combat"].moves:
		for entry in f["combat"].moves[move_id]["spawns"]:
			owner.move_id = move_id
			if entry.has("projectile") and sim._ranged["projectiles"].is_empty():
				ranged._fire(sim._ranged, 100, owner, sim.fighters, sim.bodies, entry, sim.combat, sim.events)
			if entry.has("area") and sim._ranged["areas"].is_empty():
				ranged._place_area(sim._ranged, 100, owner, sim.fighters, sim.bodies, entry, sim.combat, sim.events)
	sim.projectiles = sim._ranged["projectiles"]
	sim.areas = sim._ranged["areas"]
	ctx.check("M1-3 checkpoint exercised with live projectile, warning area and boss waves", not sim.projectiles.is_empty() and not sim.areas.is_empty() and sim.pending_wave_count() > 0)
	var copy := Sim.new(World.new(), f["combat"], F.rng())
	copy.item_rules = f["rules"]
	copy.loot_data = f["loot"]
	ctx.check("M1-3 restore pending attacks", copy.restore(sim.snapshot(), f["camp"]))
	var equal := Codec.digest(copy.snapshot()) == Codec.digest(sim.snapshot())
	for tick in 180:
		sim.set_input(1, input_for(tick))
		copy.set_input(1, input_for(tick))
		sim.tick()
		copy.tick()
		equal = equal and Codec.digest(copy.snapshot()) == Codec.digest(sim.snapshot())
	ctx.check("M1-3 projectile/area hits, IDs, wave and events continue identically every tick", equal)
