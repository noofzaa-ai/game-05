extends RefCounted
## Card pin (Boss 2026-11-26): GameSim.set_pin/clear_pin + logic/auto_pilot.gd _pinned. A pinned card walks to the pin,
## stays within data/combat/pin.json pin_radius, shoots/hits only what it reaches from there, still escapes hazards
## and walks back; pins clear on death, wave end and fight end; invalid pins are rejected or clamped.

const Pilot := preload("res://logic/auto_pilot.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const GameSim := preload("res://logic/game_sim.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Survival := preload("res://tests/test_autopilot_survival.gd")


func run(ctx) -> void:
	var combat = CombatDataLoader.load_default()
	var radius := float(GameSim.pin_rules()["pin_radius"])
	ctx.check("pin radius is data-driven and ~1.5 m (%s)" % radius, radius >= 1.0 and radius <= 2.5)
	_api_checks(ctx, combat)
	_walk_checks(ctx, combat, radius)
	_shooter_checks(ctx, combat)
	_melee_checks(ctx, combat, radius)
	_hazard_checks(ctx, combat)
	_clear_checks(ctx, combat)


static func _sim(combat, enemy_at: Vector3) -> GameSim:
	var sim: GameSim = Survival._arena(combat, "orc_grunt", enemy_at)
	Survival._settle(sim)
	return sim


static func _dist(sim, id: int) -> float:
	var p: Dictionary = sim.fighters[id].pin
	return Vector2(sim.bodies[id].position.x - float(p["x"]), sim.bodies[id].position.z - float(p["z"])).length()


func _api_checks(ctx, combat) -> void:
	var sim := _sim(combat, Vector3(10.0, 0.05, 0.0))
	ctx.check("an enemy cannot be pinned", sim.set_pin(100, 0.0, 0.0).is_empty())
	ctx.check("an unknown id cannot be pinned", sim.set_pin(55, 0.0, 0.0).is_empty())
	ctx.check("a NaN point is rejected", sim.set_pin(1, NAN, 0.0).is_empty())
	var clamped := sim.set_pin(1, 99.0, -99.0)
	ctx.check("a point outside the arena is clamped inside (%s)" % [clamped], absf(float(clamped.get("x", 0.0)) - 15.6) < 0.01 and absf(float(clamped.get("z", 0.0)) + 8.6) < 0.01)
	ctx.check("the pin is plain numbers {x, z}", sim.get_pin(1).size() == 2 and typeof(sim.get_pin(1)["x"]) == TYPE_FLOAT)
	sim.set_pin(2, 1.0, 1.0, [1, 2, 3])
	ctx.check("one card per player: pinning another card of the squad releases the first", sim.get_pin(1).is_empty() and not sim.get_pin(2).is_empty())
	ctx.check("clear_pin releases it", sim.clear_pin(2) and sim.get_pin(2).is_empty() and not sim.clear_pin(2))
	sim.set_pin(3, 2.0, 2.0)
	var saved = sim._checkpoint()
	ctx.check("the pin is saved in checkpoints", JSON.stringify(saved).contains("\"pin\""))
	sim.fighters[2].state = Fighter.State.DEAD
	ctx.check("a dead card cannot be pinned", sim.set_pin(2, 0.0, 0.0).is_empty())


static func _drive(sim, combat, ticks: int, mems: Dictionary, watch: Callable = Callable()) -> void:
	for t in ticks:
		for id in [1, 2, 3]:
			if sim.fighters.has(id):
				sim.set_input(id, Pilot.decide(sim, combat, id, mems[id], sim.tick_count))
		sim.tick()
		if watch.is_valid():
			watch.call()


func _walk_checks(ctx, combat, radius: float) -> void:
	var sim := _sim(combat, Vector3(12.0, 0.05, 6.0))
	sim.fighters[100].stats["MOVESPD"] = -90.0  # a near-still enemy far from the pin: nothing to fight from there
	sim.fighters[100].stats["HP"] = 1.0e9
	sim.fighters[100].hp = 1.0e9  # the free cards fight it; it must not die (the fight end clears pins)
	sim.set_pin(1, -10.0, -6.0)
	var mems := {1: Pilot.new_memory(1), 2: Pilot.new_memory(2), 3: Pilot.new_memory(3)}
	_drive(sim, combat, 360, mems)
	ctx.check("a pinned sword card walks to the pin (%.2f m off)" % _dist(sim, 1), _dist(sim, 1) <= radius)
	var worst := [0.0]
	_drive(sim, combat, 300, mems, func(): worst[0] = maxf(worst[0], _dist(sim, 1)))
	ctx.check("it stays at the pin and never chases the far enemy (max %.2f m)" % worst[0], worst[0] <= radius + 0.15)
	var free := _sim(combat, Vector3(8.0, 0.05, 0.0))
	var input = Pilot.decide(free, combat, 1, Pilot.new_memory(1), 0)
	ctx.check("an unpinned card still walks at the enemy (%s)" % [input.move], input.move.x > 0.5)


func _shooter_checks(ctx, combat) -> void:
	var sim := _sim(combat, Vector3(-1.0, 0.05, -3.0))  # 5 m from the longbow at (-6, -3)
	sim.set_pin(2, -6.0, -3.0)
	var shots := 0
	var moved := 0.0
	var mem := Pilot.new_memory(9)
	for t in 120:
		var input = Pilot.decide(sim, combat, 2, mem, t)
		if input.light or input.heavy or input.skill_slot >= 0 or input.ultimate:
			shots += 1
		moved = maxf(moved, input.move.dot(Vector2(1, 0)))
	ctx.check("a pinned longbow shoots an enemy in range from the pin (%d presses)" % shots, shots > 0)
	ctx.check("and does not walk toward it (%.2f)" % moved, moved < 0.1)
	sim.bodies[100].position = Vector3(14.0, 0.05, -3.0)  # 20 m: out of reach
	var none := 0
	for t in 60:
		var input = Pilot.decide(sim, combat, 2, mem, t)
		if input.light or input.heavy or input.move.x > 0.1:
			none += 1
	ctx.check("an enemy out of shoot range from the pin is not chased (%d)" % none, none == 0)


func _melee_checks(ctx, combat, radius: float) -> void:
	var sim := _sim(combat, Vector3(6.0, 0.05, 0.0))
	sim.set_pin(1, 0.0, 0.0)
	var mem := Pilot.new_memory(5)
	var bad := 0
	for t in 60:
		var input = Pilot.decide(sim, combat, 1, mem, t)
		if input.light or input.heavy or input.move.length() > 0.1:
			bad += 1
	ctx.check("a pinned melee card waits at the pin while the enemy is 6 m out (%d)" % bad, bad == 0)
	sim.bodies[100].position = Vector3(1.6, 0.05, 0.0)
	var hits := 0
	for t in 60:
		var input = Pilot.decide(sim, combat, 1, mem, t)
		if input.light or input.heavy or input.skill_slot >= 0:
			hits += 1
	ctx.check("it swings once the enemy walks into reach (%d)" % hits, hits > 0)
	var sim2 := _sim(combat, Vector3(5.0, 0.05, 0.0))
	sim2.set_pin(1, 0.0, 0.0)
	sim2.set_pin(2, -6.0, -3.0)
	sim2.set_pin(3, -6.0, 3.0)
	var hp0: float = sim2.fighters[100].hp
	var mems := {1: Pilot.new_memory(1), 2: Pilot.new_memory(2), 3: Pilot.new_memory(3)}
	var worst := [0.0, 0.0]
	_drive(sim2, combat, 400, mems, func():
		var f: Fighter = sim2.fighters[1]
		if f.is_alive() and not f.pin.is_empty():
			worst[0] = maxf(worst[0], _dist(sim2, 1))
			if f.state == Fighter.State.IDLE and _dist(sim2, 1) > worst[1]:
				worst[1] = _dist(sim2, 1))
	ctx.check("the enemy that walked in was hurt (%.0f -> %.0f)" % [hp0, sim2.fighters[100].hp], sim2.fighters[100].hp < hp0)
	ctx.check("the melee card never walked out of its circle (max %.2f m idle, %.2f m incl. knockback)" % [worst[1], worst[0]], worst[1] <= radius + 0.6 and worst[0] <= radius + 1.0)  # swing lunges and body pushes carry ~0.5 m; it walks back


func _hazard_checks(ctx, combat) -> void:
	var sim := _sim(combat, Vector3(10.0, 0.05, 0.0))
	sim.set_pin(2, -6.0, -3.0)
	sim.areas.append({"id": 77, "def": "hw_curse", "owner": 100, "team": "enemy", "move": "mummy_hw_curse", "pos": Vector3(-6.0, 0.05, -3.0), "radius": 2.0, "age": 30, "delay": 44, "active": 3, "hit": []})
	var input = Pilot.decide(sim, combat, 2, Pilot.new_memory(3), 0)
	ctx.check("a mark over the pin: the card steps out (%s)" % [input.move], input.move.length() > 0.5 or input.dodge)
	sim.areas.clear()
	sim.bodies[2].position = Vector3(-6.0, 0.05, 0.2)  # 3.2 m out after the escape
	var back = Pilot.decide(sim, combat, 2, Pilot.new_memory(3), 1)
	ctx.check("after the mark it walks back to the pin (%s)" % [back.move], back.move.y < -0.8)


func _clear_checks(ctx, combat) -> void:
	var sim := _sim(combat, Vector3(10.0, 0.05, 0.0))
	sim.set_pin(1, 0.0, 0.0)
	sim.fighters[1].hp = 0.0
	sim.fighters[1].state = Fighter.State.DEAD
	sim.tick()
	ctx.check("a pin clears when its card dies", sim.get_pin(1).is_empty())
	var sim2 := _sim(combat, Vector3(10.0, 0.05, 0.0))
	sim2.queue_wave([{"id": 101, "position": Vector3(10.0, 0.05, 2.0), "type": "orc_grunt", "level": 1}])
	sim2.set_pin(2, -6.0, -3.0)
	sim2.fighters[100].hp = 0.0
	sim2.fighters[100].state = Fighter.State.DEAD
	sim2.tick()
	ctx.check("pins clear when the next wave arrives", sim2.get_pin(2).is_empty())
	sim2.set_pin(2, -6.0, -3.0)
	sim2.fighters[101].hp = 0.0
	sim2.fighters[101].state = Fighter.State.DEAD
	sim2.tick()
	ctx.check("pins clear when the fight is won", sim2.get_pin(2).is_empty())
