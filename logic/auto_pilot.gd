extends RefCounted
## The auto-battle brain for one of our fighters (the game is an auto-battler: the player arranges the
## squad, then the fights run by themselves). It reads the simulation like a player would and returns a
## SimInput, so everything it does goes through the same rules as a human or a bot: no cheating, no
## damage injection. Pure rules: no nodes, no client code.
##
## Per tick, in order: (1) step out of a marked ground attack, (2) guard an arrow about to arrive,
## (3) dodge or guard a close enemy attack that is about to land, (4) walk (run when far) to the nearest
## living enemy, (5) in reach: ultimate when the gauge is full, a skill-build skill when one is ready,
## otherwise a light chain with a heavy finisher. `memory` is one dictionary per fighter that the caller
## keeps between ticks (decisions made once per enemy attack, skill timers); `reaction` (0..1) is the
## chance this fighter reacts to a given enemy attack at all (so a squad does not look robotic).
## Determinism: all randomness comes from `memory.rng`, which the caller seeds (the sim's replays stay exact).

const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")

const REACH := 1.5  ## stop walking and start swinging inside this distance (metres, body to body)
const BLADE_REACH := 1.45  ## the weapon reach number REACH was tuned for (data/combat/weapons.json blade)
const SHOOT_RANGE := 6.0  ## a class that shoots (its light move fires projectiles) stops this far from the target
const RUN_DISTANCE := 5.0  ## run (spends stamina) when the target is further than this
const SWING_EVERY := 9  ## ticks between presses of an attack button
const HEAVY_EVERY := 4  ## every Nth press is a heavy
const SKILL_RANGE := 7.0
const ULTIMATE_RANGE := 3.4  ## the ultimate strikes a box this far ahead: a shooter waits for the enemy to come this close
const SKILL_RETRY_TICKS := 150  ## after trying a slot, wait this long before trying it again
const GUARD_REACH := 3.0
const CHARGER_REACH := 8.0


static func new_memory(seed: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return {"rng": rng, "decided": {}, "swings": 0, "slot_ready_at": {}, "next_slot": 0}


static func decide(sim, combat, id: int, memory: Dictionary, tick: int, reaction: float = 0.85) -> SimInput:
	var input := SimInput.new()
	var me: Fighter = sim.fighters.get(id)
	if me == null or not me.is_alive() or me.incapacitated:
		return input
	var at: Vector3 = sim.bodies[id].position
	var rng: RandomNumberGenerator = memory["rng"]
	var decided: Dictionary = memory["decided"]

	for area in sim.areas:  # a marked circle that is about to burst: step out of it
		var off: Vector2 = _flat(at - Vector3(area["pos"]))
		if area["team"] != me.team and int(area["age"]) < int(area["delay"]) and off.length() < float(area["radius"]) + 0.6:
			var key := "area%d" % int(area["id"])
			if not decided.has(key):
				decided[key] = [key, rng.randf() < reaction, 0.0]
			if decided[key][1]:
				input.move = off.normalized() if off.length() > 0.05 else Vector2.RIGHT
				return input
	for shot in sim.projectiles:  # an arrow or bolt about to arrive: guard toward it
		var to_me: Vector2 = _flat(at - Vector3(shot["pos"]))
		var heading: Vector2 = _flat(Vector3(shot["vel"]))
		if shot["team"] != me.team and to_me.length() < 3.5 and heading.dot(to_me) > 0.0:
			var key := "shot%d" % int(shot["id"])
			if not decided.has(key):
				decided[key] = [key, rng.randf() < reaction, 0.0]
			if decided[key][1]:
				input.guard = true
				input.aim = -to_me
				return input

	var nearest := -1
	var nearest_distance := INF
	for other_id in sim.fighters:
		var other: Fighter = sim.fighters[other_id]
		if other.team == me.team or not other.is_alive():
			continue
		var delta: Vector2 = _flat(sim.bodies[other_id].position - at)
		var distance := delta.length()
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and other_id < nearest):
			nearest_distance = distance
			nearest = other_id
		if other.state == Fighter.State.ATTACK and not other.move_id.is_empty():  # react once per enemy attack
			var move: Dictionary = combat.moves.get(other.move_id, {})
			if not decided.has(other_id) or decided[other_id][0] != other.move_id or other.move_frame < decided[other_id][2]:
				decided[other_id] = [other.move_id, rng.randf() < reaction, other.move_frame]
			decided[other_id][2] = other.move_frame
			var reach := CHARGER_REACH if other.enemy_type == "charger" else GUARD_REACH
			var winding := other.move_frame <= float(move.get("startup", 10)) + float(move.get("active", 3))
			if decided[other_id][1] and winding and distance < reach:
				if bool(move.get("telegraph", false)) and me.dodge_cooldown == 0 and me.energy >= float(combat.rules["dodge_energy"]):
					input.dodge = true
					input.move = Vector2(-delta.y, delta.x).normalized()  # sidestep out of the lane
					return input
				input.guard = true
				input.aim = delta
				return input
		elif decided.has(other_id):
			decided.erase(other_id)
	if nearest == -1:
		return input

	var toward: Vector2 = _flat(sim.bodies[nearest].position - at)
	var engage := _engage_range(combat, me)
	if nearest_distance > engage:
		input.move = toward.normalized()
		input.run = nearest_distance > RUN_DISTANCE and me.energy > 25.0
		return input

	input.aim = toward
	if me.state != Fighter.State.IDLE and me.state != Fighter.State.ATTACK:
		return input
	if me.gauge >= float(combat.rules["ultimate_gauge_max"]) and me.state == Fighter.State.IDLE and nearest_distance <= ULTIMATE_RANGE:
		input.ultimate = true
		return input
	var slot := _ready_skill_slot(sim, me, id, memory, tick)
	if slot >= 0 and nearest_distance < SKILL_RANGE and me.state == Fighter.State.IDLE:
		input.skill_slot = slot
		input.aim_distance = clampf(nearest_distance, 1.0, 8.0)
		return input
	if tick % SWING_EVERY == 0:
		memory["swings"] = int(memory["swings"]) + 1
		if int(memory["swings"]) % HEAVY_EVERY == 0:
			input.heavy = true
		else:
			input.light = true
	return input


## How close this fighter walks before it starts attacking: shooters stand off, long weapons start earlier.
static func _engage_range(combat, me: Fighter) -> float:
	var style: Dictionary = combat.styles.get(me.style, {})
	var light: Dictionary = combat.moves.get(str(style.get("ground_light", "")), {})
	if not light.get("spawns", []).is_empty():
		return SHOOT_RANGE
	var reach := float(combat.weapons.get(me.style, {}).get("params", {}).get("reach", BLADE_REACH))
	return REACH * maxf(1.0, reach / BLADE_REACH)


## The next skill-build slot worth trying (round robin), or -1. The sim reports no cooldown to read, so
## each slot is retried only every SKILL_RETRY_TICKS; a failed cast (stamina, cooldown) costs nothing.
static func _ready_skill_slot(sim, me: Fighter, id: int, memory: Dictionary, tick: int) -> int:
	var system = sim.skill_system
	if system == null or not system.casters.has(id):
		return -1
	var ready_at: Dictionary = memory["slot_ready_at"]
	for step in 4:
		var slot: int = (int(memory["next_slot"]) + step) % 4
		if int(ready_at.get(slot, 0)) > tick:
			continue
		var cost := float(preload("res://logic/skill_build.gd").config().stamina.get(system.builds[id].skills[slot].skill, 0))
		if me.energy < cost:
			continue
		ready_at[slot] = tick + SKILL_RETRY_TICKS
		memory["next_slot"] = (slot + 1) % 4
		return slot
	return -1


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
