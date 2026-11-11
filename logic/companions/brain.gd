extends RefCounted
## Authority-only input producer. Never writes combat/health/world state.
const SimInput := preload("res://logic/sim_input.gd")
const Fighter := preload("res://logic/fighter.gd")
var leader_id := 1
var attack_wait := 0
var skill_wait := 0
var decision := "idle"
var following := false
const PARTY_LEASH := 14.0
const TARGET_RADIUS := 12.0
const FOLLOW_START := 4.0
const FOLLOW_STOP := 2.75
var navigation := preload("res://logic/companions/navigation.gd").new()

func think(sim, id: int):
	var frame := SimInput.new()
	attack_wait = maxi(0, attack_wait - 1)
	skill_wait = maxi(0, skill_wait - 1)
	decision = "idle"
	if not sim.fighters.has(id) or not sim.bodies.has(id): return frame
	var fighter = sim.fighters[id]
	if not fighter.is_alive(): return frame
	var at: Vector3 = sim.bodies[id].position
	if not sim.bodies[id].grounded: return frame
	# Existing co-op rules revive by remaining idle near a downed ally.
	var rescue := -1
	var rescue_distance := INF
	for ally in sim.fighters:
		if ally == id or sim.fighters[ally].team != fighter.team: continue
		if sim.fighters[ally].state != Fighter.State.DOWNED: continue
		var distance: float = at.distance_to(sim.bodies[ally].position)
		if distance < rescue_distance:
			rescue = ally
			rescue_distance = distance
	if rescue >= 0:
		decision = "revive"
		var radius: float = float(sim.combat.coop["revive_radius"]) * 0.7
		if rescue_distance > radius: frame.move = _walk(sim, at, sim.bodies[rescue].position)
		return frame
	var leader_at: Vector3 = sim.bodies[leader_id].position if sim.bodies.has(leader_id) else at
	# Only regroup when genuinely separated. Nearby combat takes priority inside this leash.
	if at.distance_to(leader_at) > PARTY_LEASH:
		_begin_follow()
		decision = "follow"
		frame.move = _walk(sim, at, leader_at)
		frame.run = not fighter.exhausted and fighter.energy > fighter.max_energy() * 0.35
		return frame
	var target := -1
	var nearest := TARGET_RADIUS
	var ids: Array = sim.fighters.keys()
	ids.sort()
	for enemy in ids:
		var other = sim.fighters[enemy]
		if other.team == fighter.team or not other.is_alive(): continue
		var distance: float = at.distance_to(sim.bodies[enemy].position)
		if distance < nearest and sim.bodies[enemy].position.distance_to(leader_at) <= PARTY_LEASH:
			nearest = distance
			target = enemy
	if target < 0:
		var separation := at.distance_to(leader_at)
		if separation > FOLLOW_START: _begin_follow()
		elif separation <= FOLLOW_STOP: following = false
		if following:
			decision = "follow"
			frame.move = _walk(sim, at, leader_at)
		return frame
	following = false
	var enemy_at: Vector3 = sim.bodies[target].position
	frame.aim = _toward(at, enemy_at)
	frame.aim_distance = nearest
	decision = "fight"
	var enemy = sim.fighters[target]
	if nearest < 2.2 and enemy.state == Fighter.State.ATTACK and fighter.dodge_cooldown <= 0:
		var retreat := at - Vector3(frame.aim.x,0,frame.aim.y)*4.0
		if navigation.line_supported(sim.world,at,retreat):
			frame.move = -frame.aim
			frame.dodge = true # Shared combat decides legality and spends stamina.
		else: frame.guard = true
		return frame
	var reach := _reach(sim.combat, fighter)
	if nearest > reach or not navigation.line_clear(sim.world, at, enemy_at):
		frame.move = _walk(sim, at, enemy_at)
		return frame
	if fighter.state not in [Fighter.State.IDLE, Fighter.State.GUARD]: return frame
	if skill_wait == 0:
		var slots: Array = fighter.skill_view.get("slots", [])
		for slot in mini(4, slots.size()):
			var row: Dictionary = slots[slot]
			if not str(row.get("skill", "")).is_empty() and float(row.get("left", 0)) <= 0 and fighter.energy >= float(row.get("cost", 0)):
				frame.skill_slot = slot
				skill_wait = 45
				return frame
	if attack_wait == 0:
		frame.light = true
		attack_wait = 8
	return frame

func _begin_follow() -> void:
	# A new follow leg must not reuse waypoints from before combat or a long idle pause.
	if not following: navigation = preload("res://logic/companions/navigation.gd").new()
	following = true

func _walk(sim, at: Vector3, goal: Vector3) -> Vector2:
	if at.distance_to(goal) < 2.0 and navigation.line_supported(sim.world, at, goal): return _toward(at, goal)
	return navigation.direction(sim.world, at, goal)

static func _toward(a: Vector3, b: Vector3) -> Vector2:
	return Vector2(b.x - a.x, b.z - a.z).normalized()

static func _reach(combat, fighter) -> float:
	if fighter.style == "bow": return 6.0
	var style: Dictionary = combat.styles.get(fighter.style, {})
	var move: Dictionary = combat.moves.get(style.get("ground_light", ""), {})
	if move.is_empty(): return 1.0
	var offset = move.get("hit_offset", Vector3.ZERO)
	var size = move.get("hit_size", Vector3.ONE)
	# Move resources carry Vector3 values after validation, not the source JSON arrays.
	return maxf(0.5, float(offset.x) + float(size.x) * 0.5 - 0.15)
