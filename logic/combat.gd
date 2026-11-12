extends RefCounted
## The fighting rules: attacks and chains, guard, dodge, special and ultimate skills, hit detection,
## damage, stun, knockback, launching, lying down and getting up, death. Pure functions over
## fighters and bodies; the simulation calls them every tick in a fixed order.
## EXTENDING: new states live in fighter.gd and get a branch in update_fighter(); status effects
## and new skill kinds are applied inside apply_hit() / start_skill().

const ClassSkills := preload("res://logic/class_skills/engine.gd")
const CombatData := preload("res://logic/combat_data.gd")
const Effects := preload("res://logic/effects.gd")
const Fighter := preload("res://logic/fighter.gd")
const Movement := preload("res://logic/movement.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const SimBody := preload("res://logic/sim_body.gd")
const SimInput := preload("res://logic/sim_input.gd")

const LANDING_GRACE_TICKS := 3  ## a launched fighter cannot "land" in its first few ticks
const ARMORED_KNOCKBACK_FACTOR := 0.25  ## a hit that does not break the poise only nudges the target


## Advances one fighter by one tick and returns the input its body should use for movement
## (neutral while attacking, guarding, dodging, stunned or down).
static func update_fighter(id: int, fighter: Fighter, body: SimBody, input: SimInput, data: CombatData, events: Array[Dictionary]) -> SimInput:
	fighter.state_ticks += 1
	_tick_timers(fighter, data)
	Effects.tick(id, fighter, data, events)
	fighter.running = false
	if body.grounded and fighter.state != Fighter.State.ATTACK:
		fighter.air_run = false  # landed: the running speed carried through the jump ends
	body.move_speed_multiplier = (1.0 + fighter.stat("MOVESPD") / 100.0) * float(fighter.stats.get("EQUIPMENT_MOVE_FACTOR",1.0))  # buffs and debuffs change the walking speed
	var can_be_interrupted := fighter.state == Fighter.State.IDLE or fighter.state == Fighter.State.GUARD or fighter.state == Fighter.State.ATTACK or fighter.state == Fighter.State.DODGE
	if fighter.incapacitated and can_be_interrupted:
		# Stunned or asleep: whatever it was doing is interrupted and it can do nothing until it wears off.
		fighter.move_id = ""
		fighter.buffered = ""
		fighter.dodge_left = 0
		if fighter.state != Fighter.State.IDLE:
			_set_state(fighter, Fighter.State.IDLE)
		return SimInput.new()
	if fighter.rooted:
		input = Effects.rooted_input(input)

	match fighter.state:
		Fighter.State.IDLE:
			return _update_idle(id, fighter, body, input, data, events)
		Fighter.State.GUARD:
			if not body.grounded or not input.guard:
				_set_state(fighter, Fighter.State.IDLE)
			elif input.dodge and _can_dodge(fighter, body, data):
				_start_dodge(id, fighter, body, input, data, events)
		Fighter.State.DODGE:
			fighter.dodge_left -= 1
			if fighter.dodge_left <= 0:
				_set_state(fighter, Fighter.State.IDLE)
		Fighter.State.ATTACK:
			_advance_attack(id, fighter, body, input, data, events)
		Fighter.State.HITSTUN:
			if fighter.launched:
				if body.grounded and fighter.state_ticks > LANDING_GRACE_TICKS:
					fighter.launched = false
					fighter.down_left = int(data.rules["down_ticks"])
					_set_state(fighter, Fighter.State.DOWN)
					events.append({"type": "knocked_down", "player": id})
			else:
				fighter.hitstun_left -= 1
				if fighter.hitstun_left <= 0:
					fighter.combo_hits = 0
					_set_state(fighter, Fighter.State.IDLE)
		Fighter.State.DOWN:
			fighter.down_left -= 1
			if fighter.down_left <= 0:
				fighter.combo_hits = 0
				fighter.invulnerable_left = int(data.rules["wakeup_invulnerable_ticks"])
				_set_state(fighter, Fighter.State.IDLE)
				events.append({"type": "got_up", "player": id})
	return SimInput.new()


## True while nothing can hurt the fighter: getting up, lying down, the first part of a dodge,
## or the invulnerable frames of a skill (ultimate, special).
static func is_invulnerable(fighter: Fighter, data: CombatData) -> bool:
	if fighter.invulnerable_left > 0 or fighter.state == Fighter.State.DOWN:
		return true
	if fighter.state == Fighter.State.DODGE:
		return fighter.state_ticks <= int(data.rules["dodge_invulnerable_ticks"])
	if fighter.state == Fighter.State.ATTACK:
		var move: Dictionary = data.moves[fighter.move_id]
		var from: int = move["invuln_from"]
		return from >= 0 and fighter.move_frame >= from and fighter.move_frame < int(move["invuln_to"])
	return false


## Finds every hit that lands this tick (all attackers are judged against the same positions, so
## two fighters hitting each other at the same moment both connect), then applies them.
static func resolve_hits(fighters: Dictionary, bodies: Dictionary, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary],historical_boxes:Dictionary={}) -> void:
	var ids := fighters.keys()
	ids.sort()
	var landed: Array[Vector2i] = []  ## (attacker id, target id)
	## The move each hit was made with, noted now: an earlier hit this tick can knock an attacker
	## out of its own move before its hit is applied (two fighters trading blows).
	var moves_used := {}
	for attacker_id in ids:
		var attacker: Fighter = fighters[attacker_id]
		if not is_attack_active(attacker, data) or float(data.moves[attacker.move_id]["power"]) <= 0.0 or not data.moves[attacker.move_id]["melee"]:
			continue  # (a move with no power is a pure cast; a ranged move hits only with what it fires)
		var box := hitbox_world(bodies[attacker_id], attacker, data)
		for target_id in ids:
			if target_id == attacker_id or attacker.hit_ids.has(target_id):
				continue
			var target: Fighter = fighters[target_id]
			if target.team == attacker.team or not target.is_alive() or is_invulnerable(target, data):
				continue
			var target_box:AABB=historical_boxes.get(attacker_id,{}).get(target_id,bodies[target_id].aabb()) if attacker.team=="player" and target.team=="enemy" else bodies[target_id].aabb()
			if target_box.intersects(box) and hits_footprint(bodies[attacker_id], attacker, data,target_box):
				landed.append(Vector2i(attacker_id, target_id))
				moves_used[Vector2i(attacker_id, target_id)] = attacker.move_id
	# Cleave (greatsword class signature, GDD races 3.2): a heavy swing deals more per extra enemy it hits.
	var swing_size := {}  ## attacker id -> enemies this swing has hit, counting this tick's landings
	for pair in landed:
		swing_size[pair.x] = int(swing_size.get(pair.x, fighters[pair.x].hit_ids.size())) + 1
	for pair in landed:
		var cleave := 1.0
		if str(moves_used[pair]).contains("heavy") and not fighters[pair.x].race_state.is_empty():
			cleave = RacePassives.cleave_mul(fighters[pair.x], int(swing_size[pair.x]))
		apply_hit(pair.x, pair.y, moves_used[pair], fighters, bodies, data, rng, events, {}, cleave)


## Predict only our melee contact pause, using the same geometry as resolve_hits.
## No target mutation, damage, RNG, rewards, VFX or event emission. Authority may correct it.
static func predict_attacker_hitstop(id:int,fighters:Dictionary,bodies:Dictionary,data:CombatData,historical_boxes:Dictionary={})->void:
	var attacker:Fighter=fighters[id]
	if not is_attack_active(attacker,data):return
	var move:Dictionary=data.moves[attacker.move_id]
	if not move["melee"] or float(move["power"])<=0.0:return
	var box:=hitbox_world(bodies[id],attacker,data)
	for target_id in fighters:
		if target_id==id or attacker.hit_ids.has(target_id):continue
		var target:Fighter=fighters[target_id]
		if target.team==attacker.team or not target.is_alive() or is_invulnerable(target,data):continue
		var target_box:AABB=historical_boxes.get(id,{}).get(target_id,bodies[target_id].aabb())
		if target_box.intersects(box) and hits_footprint(bodies[id],attacker,data,target_box):
			attacker.hit_ids.append(target_id)
			attacker.hitstop=int(move["hitstop"])


static func is_attack_active(fighter: Fighter, data: CombatData) -> bool:
	if fighter.state != Fighter.State.ATTACK:
		return false
	var move: Dictionary = data.moves[fighter.move_id]
	return fighter.move_frame >= move["startup"] and fighter.move_frame < move["startup"] + move["active"]


## The move's hit box right now, for a fighter facing +x: {"offset", "size"}. A traveling wave
## (grow_from < 1, the ultimates) keeps its back edge and pushes its front edge out over the active
## frames, from grow_from of the full length to all of it, so a far target is hit only when the wave
## gets there.
static func hit_box(fighter: Fighter, data: CombatData) -> Dictionary:
	var move: Dictionary = data.moves[fighter.move_id]
	var offset: Vector3 = move["hit_offset"]
	var size: Vector3 = move["hit_size"]
	var range_factor := float(fighter.skill_view.get("range_mul",1))
	offset.x *= range_factor
	size.x *= range_factor
	var grow := float(move.get("grow_from", 1.0))
	if grow < 1.0:
		var t := clampf((fighter.move_frame - float(move["startup"])) / maxf(1.0, float(move["active"]) - 1.0), 0.0, 1.0)
		var back := offset.x - size.x * 0.5
		var length := size.x * lerpf(grow, 1.0, t)
		offset = Vector3(back + length * 0.5, offset.y, offset.z)
		size = Vector3(length, size.y, size.z)
	return {"offset": offset, "size": size}


## The attack's hit box in the world. The move data describes it for a fighter facing +x
## (x = forward, z = sideways); it is turned to follow the fighter's real direction, so the same
## move works facing any of the eight directions. For a diagonal facing this is the bounding box of
## the turned box; `hits_footprint` does the exact test against the turned box.
static func hitbox_world(body: SimBody, fighter: Fighter, data: CombatData) -> AABB:
	var box := hit_box(fighter, data)
	var offset: Vector3 = box["offset"]
	var size: Vector3 = box["size"]
	var forward := Vector2(fighter.direction).normalized()
	var side := Vector2(-forward.y, forward.x)
	var shift := forward * offset.x + side * offset.z
	var center := body.position + Vector3(shift.x, offset.y, shift.y)
	var world_size := Vector3(
		absf(forward.x) * size.x + absf(side.x) * size.z, size.y,
		absf(forward.y) * size.x + absf(side.y) * size.z)
	return AABB(center - world_size / 2.0, world_size)


## Exact ground test of a target's box against the attacker's turned hit box. Facing along an
## axis the bounding box test is already exact; diagonally the corners of the bounding box would
## hit things the swing never reaches, so the target's footprint is tested in the swing's own frame.
static func hits_footprint(body: SimBody, fighter: Fighter, data: CombatData, target: AABB) -> bool:
	if fighter.direction.x == 0 or fighter.direction.y == 0:
		return true
	var box := hit_box(fighter, data)
	var offset: Vector3 = box["offset"]
	var size: Vector3 = box["size"]
	var forward := Vector2(fighter.direction).normalized()
	var side := Vector2(-forward.y, forward.x)
	var origin := Vector2(body.position.x, body.position.z)
	var along := Vector2(INF, -INF)
	var across := Vector2(INF, -INF)
	for corner in [Vector2(target.position.x, target.position.z), Vector2(target.end.x, target.position.z), Vector2(target.position.x, target.end.z), Vector2(target.end.x, target.end.z)]:
		var local: Vector2 = corner - origin
		along = Vector2(minf(along.x, local.dot(forward)), maxf(along.y, local.dot(forward)))
		across = Vector2(minf(across.x, local.dot(side)), maxf(across.y, local.dot(side)))
	return along.y >= offset.x - size.x * 0.5 and along.x <= offset.x + size.x * 0.5 		and across.y >= offset.z - size.z * 0.5 and across.x <= offset.z + size.z * 0.5


## True while a telegraphed move (a monster's slam or rush) is still in its wind-up: the client
## shows its warning then.
static func is_telegraphing(fighter: Fighter, data: CombatData) -> bool:
	if fighter.state != Fighter.State.ATTACK:
		return false
	var move: Dictionary = data.moves[fighter.move_id]
	return bool(move["telegraph"]) and fighter.move_frame < float(move["startup"])


## The ground area a telegraphed move is about to hit (for the warning marker). A rushing move
## covers its whole run, not just the hit box at its starting point.
static func telegraph_zone(body: SimBody, fighter: Fighter, data: CombatData) -> AABB:
	var move: Dictionary = data.moves[fighter.move_id]
	var zone := hitbox_world(body, fighter, data)
	var advance := float(move["advance"])
	if advance <= 0.0:
		return zone
	var run := advance / 60.0 / (1.0 - Movement.KNOCKBACK_FRICTION)  # how far the surge carries it
	var forward := Vector3(fighter.direction.x, 0.0, fighter.direction.y).normalized()
	return zone.merge(AABB(zone.position + forward * run, zone.size))


## The warning marker's real shape on the ground for a telegraphed move that is winding up, in the
## move's own facing (not an axis-aligned bounding box), so the player sees which way it points:
## {"kind": "lane", "origin": Vector3 (back center, at the feet), "dir": Vector2, "length",
##  "width", "far_width"} for a swing/rush (a rush covers its whole run) or a shot's flight line, or
## {"kind": "circle", "center", "radius"} for a blow all around the fighter or a ground area the
## caster is about to place on its target. "progress" runs 0 -> 1 over the wind-up. Empty when the
## fighter is not telegraphing.
static func telegraph_shape(id: int, fighters: Dictionary, bodies: Dictionary, data: CombatData) -> Dictionary:
	var fighter: Fighter = fighters[id]
	if not is_telegraphing(fighter, data):
		return {}
	var body: SimBody = bodies[id]
	var move: Dictionary = data.moves[fighter.move_id]
	var progress := clampf(fighter.move_frame / maxf(1.0, float(move["startup"])), 0.0, 1.0)
	var forward := Vector2(fighter.direction).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	var side := Vector2(-forward.y, forward.x)
	var feet := body.position
	if not bool(move.get("melee", true)):
		var projectiles: Script = load("res://logic/projectiles.gd")  # loaded here: projectiles.gd preloads this file
		for entry in move.get("spawns", []):
			if entry.has("area"):
				var area: Dictionary = data.areas[entry["area"]]
				var target: int = projectiles.pick_target(id, fighters, bodies, feet, forward, float(area["aim_cone"]), float(area["range"]))
				var center := feet + Vector3(forward.x, 0.0, forward.y) * float(area["range"]) * 0.5
				if target >= 0:
					var spot: Vector3 = bodies[target].position
					center = Vector3(spot.x, feet.y, spot.z)
				return {"kind": "circle", "center": center, "radius": float(area["radius"]), "progress": progress}
			if entry.has("projectile"):
				var shot: Dictionary = data.projectiles[entry["projectile"]]
				var reach := float(shot["range"])
				var aim := forward
				var target: int = projectiles.pick_target(id, fighters, bodies, feet, forward, float(shot["aim_cone"]), reach)
				if target >= 0:
					var flat := Vector2(bodies[target].position.x - feet.x, bodies[target].position.z - feet.z)
					if flat.length() > 0.001:
						aim = flat.normalized()
				var spread := 0.0
				if target < 0:  # without a target, a fan of shots spreads by its angles
					for other in move["spawns"]:
						spread = maxf(spread, absf(float(other.get("angle", 0.0))))
				var lane := 0.6 + float(shot["radius"]) * 2.0
				return {"kind": "lane", "origin": feet, "dir": aim, "length": reach, "width": lane,
					"far_width": lane + 2.0 * reach * tan(deg_to_rad(spread)), "progress": progress}
	var box := hit_box(fighter, data)
	var offset: Vector3 = box["offset"]
	var size: Vector3 = box["size"]
	if absf(offset.x) < 0.01 and absf(offset.z) < 0.01:
		return {"kind": "circle", "center": feet, "radius": maxf(size.x, size.z) * 0.5, "progress": progress}
	var run := 0.0
	if float(move["advance"]) > 0.0:
		run = float(move["advance"]) / 60.0 / (1.0 - Movement.KNOCKBACK_FRICTION)
	var back := forward * (offset.x - size.x * 0.5) + side * offset.z
	return {"kind": "lane", "origin": feet + Vector3(back.x, 0.0, back.y), "dir": forward,
		"length": size.x + run, "width": size.z, "far_width": size.z, "progress": progress}


## The nearest of the eight directions (four axes and four diagonals) for a vector on the ground
## (x, z); zero if there is none. Diagonals are (+-1, +-1).
static func direction_from(vector: Vector2) -> Vector2i:
	if vector.length() < 0.0001:
		return Vector2i.ZERO
	var sector := roundi(atan2(vector.y, vector.x) / (PI / 4.0))
	var angle := float(sector) * PI / 4.0
	return Vector2i(roundi(signf(snappedf(cos(angle), 0.01))), roundi(signf(snappedf(sin(angle), 0.01))))


## Ticks left before the special skill of this fighter's style may be used again (0 = ready).
static func special_cooldown_left(fighter: Fighter, data: CombatData) -> int:
	var style: Dictionary = _style(data, fighter)
	if not style.has("special"):
		return 0
	return int(fighter.cooldowns.get(style["special"], 0))


## `source` is set for a hit from a projectile or a ground area (projectiles.gd): {"dir": the push
## (its flight, or away from the area's center), "pos": where it lands, "projectile" or "area": its id,
## "unblockable": true for an area that cannot be guarded}. The attacker is then not frozen by the
## hit-stop and its move's own once-per-target list is left alone. Returns "blocked" or "hit".
## `damage_mul` scales the rolled damage (Cleave, before guard and DEF floors are applied again by rounding).
static func apply_hit(attacker_id: int, target_id: int, move_id: String, fighters: Dictionary, bodies: Dictionary, data: CombatData, rng: RandomNumberGenerator, events: Array[Dictionary], source: Dictionary = {}, damage_mul: float = 1.0) -> String:
	var attacker: Fighter = fighters[attacker_id]
	var target: Fighter = fighters[target_id]
	var attacker_body: SimBody = bodies[attacker_id]
	var target_body: SimBody = bodies[target_id]
	var move: Dictionary = data.moves[move_id]
	var ranged := source.has("dir")
	if not ranged:
		attacker.hit_ids.append(target_id)

	# The direction the blow pushes the target: along the attacker's facing for a forward swing, or
	# straight away from the attacker for a blast around it (the ultimates); a projectile pushes
	# along its flight.
	var offset: Vector3 = move["hit_offset"]
	var delta := Vector2(target_body.position.x - attacker_body.position.x, target_body.position.z - attacker_body.position.z)
	var push_dir: Vector2i = attacker.direction if offset.x > 0.0 else direction_from(delta)
	if ranged:
		push_dir = direction_from(source["dir"])
	if push_dir == Vector2i.ZERO:
		push_dir = attacker.direction
	var push: Vector2 = Vector2(source["dir"]).normalized() if ranged and Vector2(source["dir"]).length() > 0.001 else Vector2(push_dir).normalized()
	# Guarding only works against hits coming from the front (the way the guarder faces), and not
	# against moves that ignore guard (or areas that cannot be guarded).
	var blocked := target.state == Fighter.State.GUARD and not bool(move["ignores_guard"]) and not bool(source.get("unblockable", false)) and Vector2(target.direction).normalized().dot(-push) > 0.6  # guards the front, 45 degrees either way
	if blocked:
		# Guarding costs stamina only when a hit is actually received; holding it up is free.
		# Not enough stamina left to take the blow = the guard breaks and the hit goes through.
		var guard_cost := float(data.rules["guard_energy_per_power"]) * float(move["power"])
		if target.energy >= guard_cost:
			_spend_energy(target, guard_cost, data)
		else:
			blocked = false
			_spend_energy(target, target.energy, data)
			events.append({"type": "guard_broken", "attacker": attacker_id, "target": target_id})

	var roll := compute_damage(attacker, target, move, data, rng)
	var damage: float = roll["damage"]
	if damage_mul != 1.0:
		damage = roundf(damage * damage_mul)
	var crit: bool = roll["crit"]
	if blocked:
		damage = maxf(float(data.rules["min_damage"]), roundf(damage * (1.0 - float(data.rules["guard_damage_reduction"]))))
	if not blocked:
		var relic_multiplier:float=preload("res://logic/relic_effects.gd").multiplier(attacker,move_id)
		if relic_multiplier>1:damage=roundf(damage*relic_multiplier)
	if target.skill_hit_filter.is_valid():
		damage = target.skill_hit_filter.call(damage, attacker_id, not ranged)
		if damage <= 0.0: return "blocked"
	if not target.skill_state.is_empty():  # class skills v2: Warding Veil, Iron Guard (+ counter), Intercept link (class-skills.md 4.2)
		damage = ClassSkills.incoming(target_id, attacker_id, damage, not ranged, fighters, bodies, data, events, int(target.skill_state.get("now", 0)))
	var absorbed := target.absorb(damage)  # race shield first (GDD races 4.3); the event keeps the full damage
	target.hp = maxf(0.0, target.hp - (damage - absorbed))
	if attacker.skill_base_hit.is_valid(): attacker.skill_base_hit.call(target_id, damage)
	Effects.wake(target_id, target, data, events)  # a blow wakes a sleeper

	if not ranged:
		attacker.hitstop = int(move["hitstop"])
	target.hitstop = int(move["hitstop"])

	if not blocked:preload("res://logic/relic_effects.gd").hit(attacker_id,attacker,target_id,target,move_id,data,events)
	var killed := target.hp <= 0.0
	var hit_point: Vector3 = source["pos"] if source.has("pos") else target_body.position + Vector3(-push.x * 0.25, 1.1, -push.y * 0.25)  ## roughly where the blow lands
	if blocked and not killed:
		target_body.knockback = push * float(move["knockback"]) * float(data.rules["guard_knockback_factor"])
		events.append({"type": "blocked", "attacker": attacker_id, "target": target_id, "damage": int(damage), "pos": hit_point, "dir": push, "move": move_id, "ranged": ranged, "absorbed": absorbed})
		return "blocked"

	# The ultimate gauge is hard to fill: it only grows by landing hits (taking hits adds
	# gauge_per_hit_taken, which is 0 in the shipped data).
	# A squad card with race ultimates on fills its gauge in the race engine instead (GDD races 3.10.6, formula 4.7).
	var gauge_max := float(data.rules["ultimate_gauge_max"])
	if not RacePassives.owns_gauge(attacker):
		attacker.gauge = minf(gauge_max, attacker.gauge + float(data.rules["gauge_per_hit_dealt"]))
	if not RacePassives.owns_gauge(target):
		target.gauge = minf(gauge_max, target.gauge + float(data.rules["gauge_per_hit_taken"]))

	attacker.combo_dealt += 1
	attacker.combo_damage += int(damage)
	attacker.combo_timer = int(data.rules["combo_window_ticks"])

	# Poise is armor against flinching: each hit wears it down and the target keeps doing what it
	# was doing (a brute keeps swinging) until it is gone, then it staggers and the armor comes back.
	var armored := false
	# A race ultimate's wind-up is not staggered by hits (unbreakable poise, GDD races 3.10.3); stun/death still end it.
	if not killed and target.state == Fighter.State.ATTACK and target.move_id == str(target.race_state.get("ult", {}).get("move", "-")):
		armored = true
	elif not killed and ClassSkills.armored(target, int(target.skill_state.get("now", 0))):
		armored = true  # mid class skill / Iron Guard / Battle Trance: hits do not stagger (class-skills.md 3.2-3.3)
	elif target.max_poise > 0.0 and not killed:
		target.poise_wait = int(data.rules["poise_regen_delay_ticks"])
		target.poise -= float(move["power"]) * float(data.rules["poise_damage_per_power"])
		if target.poise > 0.0:
			armored = true
		else:
			target.poise = target.max_poise
			events.append({"type": "poise_broken", "target": target_id})

	# The move's buffs and debuffs (a blocked hit gives none; a killed target needs none).
	if not killed:
		Effects.apply_move_effects(move["effects"], "hit", attacker_id, attacker, target_id, target, data, rng, events)

	var launching: bool = float(move["launch"]) > 0.0 and not armored
	if armored:
		target_body.knockback = push * float(move["knockback"]) * ARMORED_KNOCKBACK_FACTOR
	else:
		target.direction = -push_dir
		target_body.knockback = push * float(move["knockback"])
		if launching:
			target_body.velocity.y = float(move["launch"])
			target_body.grounded = false
		target.combo_hits = target.combo_hits + 1 if target.state == Fighter.State.HITSTUN else 1
		target.move_id = ""
		target.buffered = ""
		if killed:
			target.launched = false
			_set_state(target, Fighter.State.DEAD)
		else:
			target.launched = launching or (target.state == Fighter.State.HITSTUN and target.launched)
			target.hitstun_left = int(move["hitstun"])
			_set_state(target, Fighter.State.HITSTUN)

	events.append({
		"type": "hit", "attacker": attacker_id, "target": target_id, "damage": int(damage),
		"crit": crit, "combo": target.combo_hits, "launched": launching, "armored": armored,
		"move": move_id, "power": float(move["power"]), "pos": hit_point, "dir": push,
		"attacker_combo": attacker.combo_dealt, "attacker_combo_damage": attacker.combo_damage,
		"ranged": ranged, "projectile": str(source.get("projectile", "")), "area": str(source.get("area", "")),
		"absorbed": absorbed,
	})
	if killed:
		events.append({"type": "killed", "target": target_id, "by": attacker_id})
	return "hit"


## Damage = ATK x move power, reduced by the target's DEF, x CRIDMG% when it crits.
## Uses exactly one random number (the crit roll). Returns {"damage": float, "crit": bool}.
static func compute_damage(attacker: Fighter, target: Fighter, move: Dictionary, data: CombatData, rng: RandomNumberGenerator) -> Dictionary:
	var attack := attacker.stat("ATK") * float(move["power"]) * float(attacker.skill_view.get("attack_mul",1))
	var defense := target.stat("DEF")
	var reduction := defense / (defense + float(data.rules["defense_constant"]))
	var damage := attack * (1.0 - reduction) * float(target.skill_view.get("vulnerability",1))
	var crit := rng.randf() * 100.0 < attacker.stat("CRIRATE") + float(attacker.skill_view.get("crit_bonus",0))*100.0
	if target.skill_view.get("statuses",{}).has("freeze") and "frozen_crit" in attacker.skill_view.get("passives",[]): crit = true
	if crit:
		damage *= attacker.stat("CRIDMG", 100.0) / 100.0
	return {"damage": maxf(float(data.rules["min_damage"]), roundf(damage)), "crit": crit}


static func _style(data: CombatData, fighter: Fighter) -> Dictionary:
	return data.styles.get(fighter.style, data.styles["fists"])


static func _set_state(fighter: Fighter, state: Fighter.State) -> void:
	fighter.state = state
	fighter.state_ticks = 0


static func _tick_timers(fighter: Fighter, data: CombatData) -> void:
	if fighter.invulnerable_left > 0:
		fighter.invulnerable_left -= 1
	if fighter.dodge_cooldown > 0:
		fighter.dodge_cooldown -= 1
	for move_id in fighter.cooldowns.keys():
		fighter.cooldowns[move_id] -= 1
		if fighter.cooldowns[move_id] <= 0:
			fighter.cooldowns.erase(move_id)
	if fighter.combo_timer > 0:
		fighter.combo_timer -= 1
		if fighter.combo_timer == 0:
			fighter.combo_dealt = 0
			fighter.combo_damage = 0
	if fighter.run_grace > 0:  # a run attack is still possible for a moment after letting go of run
		fighter.run_grace -= 1
		if fighter.run_grace == 0:
			fighter.run_ticks = 0
	# Stamina refills (at the STAREGEN rate) once the wait after spending is over.
	if fighter.energy_wait > 0:
		fighter.energy_wait -= 1
	else:
		fighter.energy = minf(fighter.max_energy(), fighter.energy + fighter.stat("STAREGEN") / 60.0)
	if fighter.exhausted and fighter.energy >= float(data.rules["run_resume_energy"]):
		fighter.exhausted = false
	if fighter.max_poise > 0.0:
		if fighter.poise_wait > 0:
			fighter.poise_wait -= 1
		else:
			fighter.poise = minf(fighter.max_poise, fighter.poise + fighter.max_poise / 120.0)
	# Health (HPREGEN) and the ultimate gauge (ULTREGEN) also refill by themselves.
	if fighter.is_alive():
		fighter.hp = minf(fighter.max_hp(), fighter.hp + fighter.stat("HPREGEN") / 60.0 * fighter.heal_factor())
		if not RacePassives.owns_gauge(fighter):  # the race gauge ignores ULTREGEN (GDD races 3.10.2)
			fighter.gauge = minf(float(data.rules["ultimate_gauge_max"]), fighter.gauge + fighter.stat("ULTREGEN") / 60.0)


static func _spend_energy(fighter: Fighter, amount: float, data: CombatData) -> void:
	fighter.energy = maxf(0.0, fighter.energy - amount)
	fighter.energy_wait = int(data.rules["energy_regen_delay_ticks"])


static func _update_idle(id: int, fighter: Fighter, body: SimBody, input: SimInput, data: CombatData, events: Array[Dictionary]) -> SimInput:
	# Turn toward where the fighter is going (or toward the aim, if one is given): eight directions.
	var turn := direction_from(input.aim if input.aim != Vector2.ZERO else input.move)
	if turn != Vector2i.ZERO:
		fighter.direction = turn
	var style := _style(data, fighter)
	if fighter.style=="bow":fighter.shot_direction=input.aim.normalized() if input.aim!=Vector2.ZERO else Vector2(fighter.direction).normalized()
	# "fists" has no skill-system weapon family (weapon_starts has no "fists" entry): a player
	# with no weapon equipped, or whose weapon broke mid-run, reaches this style. They keep
	# light/heavy/guard/dodge/jump here same as any weapon; special/ultimate are already
	# stripped for every player upstream in game_sim.gd (class skills replace them), so they simply have none
	# equipped to cast. Previously this returned early and left them unable to act at all.

	if input.dodge:
		if _can_dodge(fighter, body, data):
			_start_dodge(id, fighter, body, input, data, events)
			return SimInput.new()
		if body.grounded and fighter.dodge_cooldown <= 0:
			events.append({"type": "out_of_stamina", "player": id, "action": "dodge"})
	# The ultimate runs on its gauge and costs no stamina.
	if input.ultimate and body.grounded and style.has("ultimate") and not RacePassives.owns_gauge(fighter):  # race cards: GameSim routes it (races 3.10.6)
		var move: Dictionary = data.moves[style["ultimate"]]
		if fighter.gauge >= float(move["gauge_cost"]):
			fighter.gauge -= float(move["gauge_cost"])
			_start_move(id, fighter, style["ultimate"], events)
			return SimInput.new()
	if input.special and body.grounded and style.has("special") and fighter.cooldowns.get(style["special"], 0) <= 0:
		if _start_attack(id, fighter, style["special"], data, events):
			fighter.cooldowns[style["special"]] = int(data.moves[style["special"]]["cooldown"])
			return SimInput.new()
	if input.guard and body.grounded:
		_set_state(fighter, Fighter.State.GUARD)
		return SimInput.new()
	# Run attacks: pressing an attack while running (for at least a short run-up) uses the weapon's
	# run attack. Jump attacks: attacking in the air uses the weapon's air attacks. No charging up:
	# these moves are simply stronger, and each weapon gives them its own effect (knockback, launch,
	# stun) through the weapon data.
	var run_ready := body.grounded and fighter.run_grace > 0 and fighter.run_ticks >= int(data.rules["run_attack_min_ticks"])
	# Bow is deliberately grounded: never turn sprint/jump input into an attack.
	if data.weapons.get(fighter.style,{}).get("grounded_shots_only",false) and (not body.grounded or input.jump or input.run):
		input.light=false; input.heavy=false
	if input.light:
		if run_ready and style.has("run_light"):
			if _start_attack(id, fighter, style["run_light"], data, events):
				_spend_run(fighter)
		elif body.grounded:
			_start_attack(id, fighter, style["ground_light"], data, events)
		else:
			_start_attack(id, fighter, style["air_light"], data, events)
	elif input.heavy:
		if run_ready and style.has("run_heavy"):
			if _start_attack(id, fighter, style["run_heavy"], data, events):
				_spend_run(fighter)
		elif body.grounded:
			_start_attack(id, fighter, style["ground_heavy"], data, events)
		elif style.has("air_heavy"):
			_start_attack(id, fighter, style["air_heavy"], data, events)
	if fighter.state == Fighter.State.ATTACK:
		return SimInput.new()
	return _with_running(fighter, body, _with_jump_cost(id, fighter, body, input, data, events), data)


## Every attack (and every chained follow-up) costs stamina. Returns false, and tells the client,
## when there is not enough: the move simply does not start, so attacks cannot be spammed.
static func _start_attack(id: int, fighter: Fighter, move_id: String, data: CombatData, events: Array[Dictionary]) -> bool:
	var cost := float(data.moves[move_id]["energy_cost"])
	if fighter.energy < cost:
		events.append({"type": "out_of_stamina", "player": id, "action": "attack"})
		return false
	if cost > 0.0:
		_spend_energy(fighter, cost, data)
	_start_move(id, fighter, move_id, events)
	return true


## A run attack uses up the run-up: the next one needs a fresh run.
static func _spend_run(fighter: Fighter) -> void:
	fighter.run_ticks = 0
	fighter.run_grace = 0


## Jumping costs stamina too; without enough the jump is simply dropped from the input.
static func _with_jump_cost(id: int, fighter: Fighter, body: SimBody, input: SimInput, data: CombatData, events: Array[Dictionary]) -> SimInput:
	if not input.jump or not body.grounded:
		return input
	var cost := float(data.rules["jump_energy"])
	if fighter.energy >= cost:
		_spend_energy(fighter, cost, data)
		# Jumping from a run keeps the running speed in the air.
		fighter.air_run = fighter.run_grace > 0 and fighter.run_ticks >= int(data.rules["run_attack_min_ticks"])
		return input
	events.append({"type": "out_of_stamina", "player": id, "action": "jump"})
	var no_jump := SimInput.new()
	no_jump.move = input.move
	no_jump.run = input.run
	return no_jump


## Running spends energy every tick; with none left the fighter walks until it recovers a little.
static func _with_running(fighter: Fighter, body: SimBody, input: SimInput, data: CombatData) -> SimInput:
	var moving := input.move.length() > 0.1 and body.grounded
	var run_jump := not body.grounded and fighter.air_run
	if not input.run and not run_jump:
		return input
	if moving and not fighter.exhausted and fighter.energy > 0.0:
		_spend_energy(fighter, float(data.rules["run_energy_per_second"]) / 60.0, data)
		fighter.running = true
		fighter.run_ticks += 1
		fighter.run_grace = int(data.rules["run_attack_grace_ticks"])
		if fighter.energy <= 0.0:
			fighter.exhausted = true
		return input
	if run_jump and input.move.length() > 0.1:
		return input  # a jump from a run keeps its running speed in the air (no extra stamina)
	var walking := SimInput.new()
	walking.move = input.move
	walking.jump = input.jump
	return walking


static func _can_dodge(fighter: Fighter, body: SimBody, data: CombatData) -> bool:
	return fighter.dodge_cooldown <= 0 and body.grounded and fighter.energy >= float(data.rules["dodge_energy"])


## The dodge is a slide: one push in the direction held (or the facing direction), then it fades.
## The fighter cannot be hit during the first part of it.
static func _start_dodge(id: int, fighter: Fighter, body: SimBody, input: SimInput, data: CombatData, events: Array[Dictionary]) -> void:
	var direction := Vector2(input.move.x, input.move.y)
	if direction.length() < 0.1:
		direction = Vector2(fighter.direction)
	direction = direction.normalized()
	body.knockback = direction * float(data.rules["dodge_speed"]) * float(fighter.stats.get("EQUIPMENT_DODGE_FACTOR",1.0))
	fighter.dodge_left = int(data.rules["dodge_ticks"])
	fighter.dodge_cooldown = maxi(1,roundi(float(data.rules["dodge_cooldown"]) * float(fighter.skill_view.get("dodge_cd_mul",1))))
	_spend_energy(fighter, float(data.rules["dodge_energy"]), data)
	fighter.move_id = ""
	fighter.buffered = ""
	_set_state(fighter, Fighter.State.DODGE)
	events.append({"type": "dodge_started", "player": id})


static func _start_move(id: int, fighter: Fighter, move_id: String, events: Array[Dictionary]) -> void:
	fighter.move_id = move_id
	fighter.move_frame = 0.0
	fighter.hit_ids.clear()
	fighter.spawns_done = 0
	fighter.buffered_shot_direction=Vector2.ZERO
	fighter.buffered = ""
	fighter.active_started = false
	_set_state(fighter, Fighter.State.ATTACK)
	events.append({"type": "attack_started", "player": id, "move": move_id})


static func _advance_attack(id: int, fighter: Fighter, body: SimBody, input: SimInput, data: CombatData, events: Array[Dictionary]) -> void:
	var move: Dictionary = data.moves[fighter.move_id]
	if input.light:
		fighter.buffered = "light"
		if fighter.style=="bow" and input.aim!=Vector2.ZERO:fighter.buffered_shot_direction=input.aim.normalized()
	elif input.heavy:
		fighter.buffered = "heavy"
		if fighter.style=="bow" and input.aim!=Vector2.ZERO:fighter.buffered_shot_direction=input.aim.normalized()
	fighter.move_frame += fighter.attack_speed_factor()
	if not fighter.active_started and fighter.move_frame >= float(move["startup"]):
		fighter.active_started = true  # the swing begins: the client draws its slash now
		Effects.apply_move_effects(move["effects"], "cast", id, fighter, -1, null, data, null, events)  # self buffs
		if float(move["advance"]) > 0.0:
			body.knockback = Vector2(fighter.direction).normalized() * float(move["advance"])  # rushing attacks surge forward
		if float(move["dive"]) > 0.0 and not body.grounded:
			body.velocity.y = -float(move["dive"])  # diving attacks plunge toward the ground
		events.append({"type": "attack_active", "player": id, "move": fighter.move_id})

	_carry_dash(fighter, body, move)

	var active_end: int = int(move["startup"]) + int(move["active"])
	var chain_frame := active_end + int(move["recovery"]) if data.weapons.get(fighter.style,{}).get("grounded_shots_only",false) else active_end
	if fighter.buffered != "" and fighter.move_frame >= chain_frame:
		var next_move: String = move["on_light"] if fighter.buffered == "light" else move["on_heavy"]
		if not next_move.is_empty():
			if fighter.style=="bow" and fighter.buffered_shot_direction!=Vector2.ZERO:
				fighter.shot_direction=fighter.buffered_shot_direction
				fighter.direction=direction_from(fighter.shot_direction)
			if _start_attack(id, fighter, next_move, data, events):
				return
			fighter.buffered = ""  # too tired to continue: the combo ends here
	if fighter.move_frame >= active_end + int(move["recovery"]):
		fighter.buffered = ""
		fighter.move_id = ""
		_set_state(fighter, Fighter.State.IDLE)


## A move that carries the fighter forward itself (the skill packs whose caster dashes): over the
## move's own dash window the body is pushed at the speed that covers dash_distance exactly, and the
## push is cleared the tick the window ends so it does not drift on. Walls stop it (Movement).
static func _carry_dash(fighter: Fighter, body: SimBody, move: Dictionary) -> void:
	var distance := float(move["dash_distance"])
	if distance <= 0.0:
		return
	var from := float(move["dash_from"])
	var to := float(move["dash_to"])
	var now := fighter.move_frame
	var before := now - fighter.attack_speed_factor()
	if now >= from and now < to:
		body.knockback = Vector2(fighter.direction).normalized() * (distance * 60.0 / maxf(1.0, to - from))
	elif now >= to and before < to:
		body.knockback = Vector2.ZERO  # the dash is over: no leftover slide
