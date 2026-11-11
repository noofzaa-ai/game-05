extends RefCounted
## A scripted player for balance checks: walks to the nearest monster, presses light attack in range,
## and reacts to monster attacks (dodges telegraphed heavies, guards light hits) with a given chance
## (`skill`, 0..1) decided once per monster attack; with the same chance it guards an arrow or bolt
## about to arrive and steps out of a hex circle before it bursts. Used by test_journey.gd and the
## balance sweep.

const Fighter := preload("res://logic/fighter.gd")
const GameSim := preload("res://logic/game_sim.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const Run := preload("res://logic/run.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const PLAYER := 1


## Plays the journey's current fight once. Returns {"won": bool, "hp": 0..1 left, "ticks": int}.
static func play(journey, combat, seed: int, skill: float, max_ticks: int = 60 * 150) -> Dictionary:
	var map = MapLoader.load_by_id(str(journey.current["map"]))
	var world := SimWorld.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sim := GameSim.new(world, combat, rng)
	sim.add_player(PLAYER, map.spawn)
	sim.attach_run(PLAYER, journey.run, journey.item_rules, journey.loot_data)
	journey.populate(sim, map, PLAYER, 100)
	var react := RandomNumberGenerator.new()
	react.seed = seed * 31 + 7
	var decided := {}  ## enemy id -> [move_id, reacts?] for its current attack
	var tick := 0
	while tick < max_ticks:
		var me: Fighter = sim.fighters[PLAYER]
		if not me.is_alive() or sim.living_enemy_count() == 0:
			break
		sim.set_input(PLAYER, _decide(sim, combat, skill, react, decided, tick))
		sim.tick()
		tick += 1
	var player: Fighter = sim.fighters[PLAYER]
	return {"won": player.is_alive() and sim.living_enemy_count() == 0, "hp": maxf(player.hp, 0.0) / player.max_hp(), "ticks": tick}


static func _decide(sim, combat, skill: float, react: RandomNumberGenerator, decided: Dictionary, tick: int, player_id: int = PLAYER) -> SimInput:
	var input := SimInput.new()
	var me: Fighter = sim.fighters[player_id]
	var at: Vector3 = sim.bodies[player_id].position
	# Ranged attacks, with the same once-per-attack chance (`skill`): step out of a marked circle before
	# it bursts, guard toward an arrow or bolt about to arrive.
	for area in sim.areas:
		var off: Vector2 = _flat(at - Vector3(area["pos"]))
		if area["team"] != me.team and int(area["age"]) < int(area["delay"]) and off.length() < float(area["radius"]) + 0.6:
			var key := "area%d" % int(area["id"])
			if not decided.has(key):
				decided[key] = [key, react.randf() < skill, 0.0]
			if decided[key][1]:
				input.move = off.normalized() if off.length() > 0.05 else Vector2.RIGHT
				return input
	for shot in sim.projectiles:
		var to_me: Vector2 = _flat(at - Vector3(shot["pos"]))
		var heading: Vector2 = _flat(Vector3(shot["vel"]))
		if shot["team"] != me.team and to_me.length() < 3.5 and heading.dot(to_me) > 0.0:
			var key := "shot%d" % int(shot["id"])
			if not decided.has(key):
				decided[key] = [key, react.randf() < skill, 0.0]
			if decided[key][1]:
				input.guard = true
				input.aim = -to_me
				return input
	var nearest := -1
	var nearest_distance := INF
	for id in sim.fighters:
		var other: Fighter = sim.fighters[id]
		if other.team == me.team or not other.is_alive():
			continue
		var delta: Vector2 = _flat(sim.bodies[id].position - at)
		var distance := delta.length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = id
		if other.state == Fighter.State.ATTACK and not other.move_id.is_empty():
			var move: Dictionary = combat.moves.get(other.move_id, {})
			if not decided.has(id) or decided[id][0] != other.move_id or other.move_frame < decided[id][2]:
				decided[id] = [other.move_id, react.randf() < skill, other.move_frame]
			decided[id][2] = other.move_frame
			var reach := 8.0 if other.enemy_type == "charger" else 3.0
			var winding := other.move_frame <= float(move.get("startup", 10)) + float(move.get("active", 3))
			if decided[id][1] and winding and distance < reach:
				if bool(move.get("telegraph", false)) and me.dodge_cooldown == 0 and me.energy >= float(combat.rules["dodge_energy"]):
					input.dodge = true
					input.move = Vector2(-delta.y, delta.x).normalized()  # step sideways out of the lane
					return input
				input.guard = true
				input.aim = delta
				return input
		elif decided.has(id):
			decided.erase(id)
	if nearest == -1:
		return input
	var toward: Vector2 = _flat(sim.bodies[nearest].position - at)
	if nearest_distance > 1.4:
		input.move = toward.normalized()
	elif tick % 9 == 0:
		input.light = true
		input.aim = toward
	return input


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
