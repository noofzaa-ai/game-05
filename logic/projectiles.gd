extends RefCounted
## Ranged attacks: projectiles (arrows, magic bolts) and ground areas (a telegraphed circle that
## detonates after a delay). Pure rules, tick-based and deterministic like the rest of the simulation.
##
## A move fires them through its "spawns" list (combat.json; any fighter's move, player or monster):
##   {"projectile": id, "frame": f, "offset": [forward, up, side], "angle": degrees}
##   {"area": id, "frame": f}
##   {"blink": meters, "frame": f}   (a short teleport along the facing; negative = backwards, the
##                                    mage's escape; it stops short of walls and the stage edge)
## `frame` is the move frame it happens on (default: the end of the wind-up, i.e. the strike), so an
## archer knocked out of its draw never shoots. The definitions live in combat.json "projectiles" and
## "areas" (see combat_data_loader.gd for the fields).
##
## Damage, guard, dodge and effects are the melee rules (Combat.apply_hit) with the firing move's
## power: a projectile pushes along its flight, so a guard facing it blocks it (unless the move
## ignores guard); dodge i-frames, getting up and lying down let it fly through. An area pushes away
## from its center and cannot be guarded unless its data says so; i-frames avoid it too.
## Projectiles stop at walls and the floor (the map's solid boxes) and at the edge of the stage.
## EXTENDING: a new projectile or area is data; a new flight rule (bounce, split) is a field here.

const Combat := preload("res://logic/combat.gd")
const CombatData := preload("res://logic/combat_data.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimBody := preload("res://logic/sim_body.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const TICK := 1.0 / 60.0
const SUBSTEPS := 3  ## collision checks per tick (no fast projectile skips through a thin body)
const CHEST := 0.55  ## homing and aiming go for this fraction of the target's body height
const EDGE_MARGIN := 1.5  ## a projectile this far outside the stage limits is gone


## Fires the spawns of every attacking fighter whose move just reached their frame.
## `state` holds the live lists: {"projectiles": Array, "areas": Array, "next_id": int}.
static func spawn_from_moves(state: Dictionary, fighters: Dictionary, bodies: Dictionary, world: SimWorld, data: CombatData, events: Array[Dictionary]) -> void:
	var ids := fighters.keys()
	ids.sort()
	for id in ids:
		var fighter: Fighter = fighters[id]
		if fighter.state != Fighter.State.ATTACK or not data.moves.has(fighter.move_id):
			continue
		var spawns: Array = data.moves[fighter.move_id]["spawns"]
		while fighter.spawns_done < spawns.size() and fighter.move_frame >= float(spawns[fighter.spawns_done]["frame"]):
			var entry: Dictionary = spawns[fighter.spawns_done]
			fighter.spawns_done += 1
			if entry.has("projectile"):
				_fire(state, id, fighter, fighters, bodies, entry, data, events)
			elif entry.has("area"):
				_place_area(state, id, fighter, fighters, bodies, entry, data, events)
			else:
				_blink(id, fighter, bodies[id], world, float(entry["blink"]), events)


## Moves every projectile and ticks every area one tick: hits, walls, detonations.
static func step(state: Dictionary, fighters: Dictionary, bodies: Dictionary, world: SimWorld, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	var kept: Array = []
	for shot in state["projectiles"]:
		if _fly(shot, fighters, bodies, world, data, rng, events):
			kept.append(shot)
	state["projectiles"] = kept
	var waiting: Array = []
	for area in state["areas"]:
		if _tick_area(area, fighters, bodies, data, rng, events):
			waiting.append(area)
	state["areas"] = waiting


## The opponent a shot from `body` along `forward` goes for: the nearest living one within `cone`
## degrees of it and `reach` meters (-1 if none). Used for aim assist and homing.
static func pick_target(owner_id: int, fighters: Dictionary, bodies: Dictionary, from: Vector3, forward: Vector2, cone: float, reach: float) -> int:
	var owner: Fighter = fighters[owner_id]
	var best := -1
	var best_distance := INF
	var ids := fighters.keys()
	ids.sort()
	for id in ids:
		var other: Fighter = fighters[id]
		if other.team == owner.team or not other.is_alive():
			continue
		var flat := Vector2(bodies[id].position.x - from.x, bodies[id].position.z - from.z)
		var distance := flat.length()
		if distance > reach or distance < 0.001:
			continue
		if absf(rad_to_deg(forward.angle_to(flat))) > cone:
			continue
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


# --- projectiles ---------------------------------------------------------------------------------

static func _fire(state: Dictionary, owner_id: int, fighter: Fighter, fighters: Dictionary, bodies: Dictionary, entry: Dictionary, data: CombatData, events: Array[Dictionary]) -> void:
	var definition: Dictionary = data.projectiles[entry["projectile"]]
	var body: SimBody = bodies[owner_id]
	var aim: Vector2 = fighter.shot_direction if fighter.style=="bow" and fighter.shot_direction!=Vector2.ZERO else Vector2(fighter.direction)
	var forward := aim.normalized().rotated(deg_to_rad(float(entry["angle"])))
	var offset: Vector3 = entry["offset"]
	var side := Vector2(-forward.y, forward.x)
	var start := body.position + Vector3(forward.x * offset.x + side.x * offset.z, offset.y, forward.y * offset.x + side.y * offset.z)
	# Aim assist: straight at the nearest opponent near the facing (a free aim, not just eight ways).
	var target := pick_target(owner_id, fighters, bodies, body.position, forward, float(definition["aim_cone"]), float(definition["range"]))
	if target >= 0:
		var flat := Vector2(bodies[target].position.x - start.x, bodies[target].position.z - start.z)
		if flat.length() > 0.001:
			forward = flat.normalized()
	var speed_factor: float = float(fighter.skill_view.get("projectile_speed_mul",1)) if fighter.style=="bow" else 1.0
	var range_factor: float = float(fighter.skill_view.get("range_mul",1)) if fighter.style=="bow" else 1.0
	var velocity := Vector3(forward.x, 0.0, forward.y) * float(definition["speed"]) * speed_factor + Vector3.UP * float(definition["lift"])
	var shot := {
		"id": int(state["next_id"]), "def": str(entry["projectile"]), "owner": owner_id, "team": fighter.team,
		"move": fighter.move_id, "pos": start, "vel": velocity, "traveled": 0.0, "age": 0,
		"range": float(definition["range"])*range_factor, "hit": [], "pierce_left": int(definition["pierce"]), "target": target if float(definition["homing"]) > 0.0 else -1,
	}
	state["next_id"] = int(state["next_id"]) + 1
	state["projectiles"].append(shot)
	events.append({"type": "projectile_fired", "player": owner_id, "shot": shot["id"], "projectile": shot["def"], "look": definition["look"], "move": fighter.move_id, "pos": start, "dir": forward})


## One tick of flight. False when the projectile is gone.
static func _fly(shot: Dictionary, fighters: Dictionary, bodies: Dictionary, world: SimWorld, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> bool:
	var definition: Dictionary = data.projectiles[shot["def"]]
	shot["age"] = int(shot["age"]) + 1
	var velocity: Vector3 = shot["vel"]
	# Weak homing: the horizontal heading turns toward the target by at most `homing` degrees a second.
	var target: int = shot["target"]
	if target >= 0 and fighters.has(target) and fighters[target].is_alive():
		var flat := Vector2(velocity.x, velocity.z)
		var to := Vector2(bodies[target].position.x - shot["pos"].x, bodies[target].position.z - shot["pos"].z)
		if to.length() > 0.001 and flat.length() > 0.001:
			var turn := clampf(flat.angle_to(to), -deg_to_rad(float(definition["homing"])) * TICK, deg_to_rad(float(definition["homing"])) * TICK)
			flat = flat.rotated(turn)
			velocity = Vector3(flat.x, velocity.y, flat.y)
	velocity.y -= float(definition["gravity"]) * TICK
	shot["vel"] = velocity
	var step: Vector3 = velocity * TICK / float(SUBSTEPS)
	var radius := float(definition["radius"])
	for i in SUBSTEPS:
		shot["pos"] += step
		shot["traveled"] = float(shot["traveled"]) + step.length()
		var pos: Vector3 = shot["pos"]
		var victim := _body_at(shot, fighters, bodies, pos, radius, data)
		if victim >= 0:
			shot["hit"].append(victim)
			var push := Vector2(velocity.x, velocity.z).normalized()
			var blocked := Combat.apply_hit(int(shot["owner"]), victim, str(shot["move"]), fighters, bodies, data, rng, events, {"dir": push, "pos": pos, "projectile": shot["def"]}) == "blocked"
			if blocked or int(shot["pierce_left"]) <= 0:
				_end(shot, "blocked" if blocked else "hit", events)
				return false
			shot["pierce_left"] = int(shot["pierce_left"]) - 1
		if bool(definition["walls"]) and _in_solid(world, pos, radius * 0.5):
			_end(shot, "wall", events)
			return false
	var pos: Vector3 = shot["pos"]
	if float(shot["traveled"]) >= float(shot.get("range",definition["range"])):
		_end(shot, "spent", events)
		return false
	if absf(pos.x) > world.half_width + EDGE_MARGIN or absf(pos.z) > world.half_depth + EDGE_MARGIN or pos.y < -2.0:
		_end(shot, "gone", events)
		return false
	return true


## The fighter the projectile touches now (-1 = none): an opponent, alive, not yet hit by it, and
## not untouchable (i-frames let a shot fly through).
static func _body_at(shot: Dictionary, fighters: Dictionary, bodies: Dictionary, pos: Vector3, radius: float, data: CombatData) -> int:
	var ids := fighters.keys()
	ids.sort()
	for id in ids:
		var other: Fighter = fighters[id]
		if other.team == shot["team"] or not other.is_alive() or shot["hit"].has(id):
			continue
		if Combat.is_invulnerable(other, data):
			continue
		if bodies[id].aabb().grow(radius).has_point(pos):
			return id
	return -1


static func _in_solid(world: SimWorld, pos: Vector3, inset: float) -> bool:
	for solid in world.solids:
		if solid.grow(-inset).has_point(pos):
			return true
	return false


static func _end(shot: Dictionary, reason: String, events: Array[Dictionary]) -> void:
	events.append({"type": "projectile_ended", "player": shot["owner"], "shot": shot["id"], "projectile": shot["def"], "reason": reason, "pos": shot["pos"]})


# --- blink ---------------------------------------------------------------------------------------

## Teleports the fighter `meters` along its facing (backwards when negative), to the farthest free
## spot on the way in steps of a quarter meter: never into a wall or past the edge of the stage.
static func _blink(id: int, fighter: Fighter, body: SimBody, world: SimWorld, meters: float, events: Array[Dictionary]) -> void:
	var dir := Vector2(fighter.direction).normalized() * signf(meters)
	var from := body.position
	var best := from
	var steps := int(absf(meters) / 0.25)
	for i in range(1, steps + 1):
		var spot := from + Vector3(dir.x, 0.0, dir.y) * 0.25 * float(i)
		if absf(spot.x) > world.half_width or absf(spot.z) > world.half_depth:
			break
		var box := AABB(Vector3(spot.x - SimBody.HALF_WIDTH, spot.y + 0.05, spot.z - SimBody.HALF_DEPTH), Vector3(SimBody.HALF_WIDTH * 2.0, body.height - 0.1, SimBody.HALF_DEPTH * 2.0))
		var blocked := false
		for solid in world.solids:
			if solid.intersects(box):
				blocked = true
				break
		if blocked:
			break
		best = spot
	body.position = best
	body.knockback = Vector2.ZERO
	events.append({"type": "blinked", "player": id, "from": from, "pos": best})


# --- areas ---------------------------------------------------------------------------------------

## Marks the ground at the opponent the caster faces (within the area's range; else straight ahead
## at half the range). It goes off `delay` ticks later wherever the target has gone.
static func _place_area(state: Dictionary, owner_id: int, fighter: Fighter, fighters: Dictionary, bodies: Dictionary, entry: Dictionary, data: CombatData, events: Array[Dictionary]) -> void:
	var definition: Dictionary = data.areas[entry["area"]]
	var body: SimBody = bodies[owner_id]
	var forward := Vector2(fighter.direction).normalized()
	var target := pick_target(owner_id, fighters, bodies, body.position, forward, float(definition["aim_cone"]), float(definition["range"]))
	var center := body.position + Vector3(forward.x, 0.0, forward.y) * float(definition["range"]) * 0.5
	if target >= 0:
		var spot: SimBody = bodies[target]
		center = Vector3(spot.position.x, spot.position.y if spot.grounded else body.position.y, spot.position.z)
	var area := {
		"id": int(state["next_id"]), "def": str(entry["area"]), "owner": owner_id, "team": fighter.team,
		"move": fighter.move_id, "pos": center, "radius": float(definition["radius"]), "age": 0,
		"delay": int(definition["delay"]), "active": int(definition["active"]), "hit": [],
	}
	state["next_id"] = int(state["next_id"]) + 1
	state["areas"].append(area)
	events.append({"type": "area_placed", "player": owner_id, "area": area["id"], "kind": area["def"], "look": definition["look"], "pos": center, "radius": area["radius"], "delay": area["delay"]})


## One tick of an area. It warns for `delay` ticks, then hurts everyone of the other team standing
## in it for `active` ticks (each once). False when it is over.
static func _tick_area(area: Dictionary, fighters: Dictionary, bodies: Dictionary, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> bool:
	var definition: Dictionary = data.areas[area["def"]]
	area["age"] = int(area["age"]) + 1
	var age: int = area["age"]
	var delay: int = area["delay"]
	if age < delay:
		return true
	var center: Vector3 = area["pos"]
	if age == delay:
		events.append({"type": "area_detonated", "player": area["owner"], "area": area["id"], "kind": area["def"], "look": definition["look"], "pos": center, "radius": area["radius"]})
	if not fighters.has(int(area["owner"])):
		return age < delay + int(area["active"])
	var ids := fighters.keys()
	ids.sort()
	for id in ids:
		var other: Fighter = fighters[id]
		if other.team == area["team"] or not other.is_alive() or area["hit"].has(id) or Combat.is_invulnerable(other, data):
			continue
		var feet: Vector3 = bodies[id].position
		var flat := Vector2(feet.x - center.x, feet.z - center.z)
		if flat.length() > float(area["radius"]) + SimBody.HALF_WIDTH or feet.y > center.y + float(definition["height"]) or feet.y + bodies[id].height < center.y - 0.2:
			continue
		area["hit"].append(id)
		var push := flat.normalized() if flat.length() > 0.05 else Vector2(fighters[id].direction).normalized() * -1.0
		Combat.apply_hit(int(area["owner"]), id, str(area["move"]), fighters, bodies, data, rng, events, {"dir": push, "pos": feet + Vector3(0.0, 0.6, 0.0), "area": area["def"], "unblockable": not bool(definition["guardable"])})
	return age < delay + int(area["active"])
