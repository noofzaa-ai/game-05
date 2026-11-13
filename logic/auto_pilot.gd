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
##
## Class pilot profiles (design/gdd/races-and-classes.md 3.2): a squad card whose class file (data/classes/<id>.json)
## has a `pilot` block uses it instead of the constants below: `target` (nearest | peel | densest | lowest_hp |
## marked_first, + `boss_first`), `prefer_marked` (Hunter's Mark focus fire), `shoot_range`, `kite_distance`,
## `heavy_every`, `reaction`, the skill hold rule `skill_min_targets` and the `support_skill` / `support_below` rule.
## A fighter with no class profile (no race_state, or a class without `pilot`) behaves exactly as before.

const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const RaceUltimates := preload("res://logic/race_ultimates.gd")
const Combat := preload("res://logic/combat.gd")
const ClassSkills := preload("res://logic/class_skills/engine.gd")
const ClassSkillUse := preload("res://logic/class_skills/use_rules.gd")
const TARGETED_RADIUS := 3.0  ## use rule targeted_by_min: enemies this close to an ally count as on it
const DEFAULT_HOLD_TICKS := 480  ## use.max_hold_ticks fallback

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
const DEFAULT_REACTION := 0.85  ## used when the caller passes no reaction and the class has no pilot.reaction
const DENSE_RADIUS := 2.5  ## pilot target "densest": other enemies counted within this radius (pilot.dense_radius)
const HOLD_RADIUS := 2.0  ## skill hold rule: smallest area radius counted around the target


static func new_memory(seed: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return {"rng": rng, "decided": {}, "swings": 0, "slot_ready_at": {}, "next_slot": 0}


## `reaction` < 0 = the class pilot's reaction (data), else DEFAULT_REACTION; a value >= 0 overrides it (tests, bots).
static func decide(sim, combat, id: int, memory: Dictionary, tick: int, reaction: float = -1.0) -> SimInput:
	var input := SimInput.new()
	var me: Fighter = sim.fighters.get(id)
	if me == null or not me.is_alive() or me.incapacitated:
		return input
	var profile := pilot_profile(me)
	if reaction < 0.0:
		reaction = float(profile.get("reaction", DEFAULT_REACTION))
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

	var engage := _engage_range(combat, me, profile)
	var class_pick: Dictionary = {}
	if ClassSkills.has_skills(me) and me.state == Fighter.State.IDLE and not ClassSkills.busy(me):
		# class skills v2 (design/gdd/class-skills.md 3.7): the use rules pick the skill and its target; defensive ones
		# (Vault Shot replaces the kite dodge, Repulse Nova, Intercept ...) come before walking or the ultimate.
		class_pick = ClassSkillUse.pick(sim, id, pick_target(sim, id, profile, engage, nearest))
	if not class_pick.is_empty() and float(SkillData_priority(str(class_pick["skill"]))) < 1.0:
		return _skill_input(sim, id, me, class_pick)
	var kite := float(profile.get("kite_distance", 0.0))
	if not me.race_state.is_empty():
		kite = preload("res://logic/skill_tree_mechanics.gd").kite_distance(me, kite)  # tree pilot_mod kite_distance (Skirmisher)
	if kite > 0.0 and nearest_distance < kite and me.state == Fighter.State.IDLE and me.dodge_cooldown == 0 and me.energy >= float(combat.rules["dodge_energy"]):
		var away: Vector2 = _flat(at - sim.bodies[nearest].position)
		input.dodge = true  # kite: slide back from an enemy that got too close (pilot.kite_distance)
		input.move = away.normalized() if away.length() > 0.05 else Vector2.LEFT
		return input
	if RaceUltimates.ready(sim, id) and wants_ultimate(sim, id, engage):  # race ultimate first (GDD 3.10.4)
		input.ultimate = true
		input.aim = _flat(sim.bodies[nearest].position - at)
		return input
	if int(me.race_state.get("refreshed_at", -1)) > int(memory.get("refresh_seen", -1)):
		memory["refresh_seen"] = int(me.race_state["refreshed_at"])
		memory["slot_ready_at"].clear()  # an ultimate cut the skill cooldowns: try the skills again at once
	var target := pick_target(sim, id, profile, engage, nearest)
	var target_distance: float = _flat(sim.bodies[target].position - at).length()
	var toward: Vector2 = _flat(sim.bodies[target].position - at)
	if target_distance > engage:
		input.move = toward.normalized()
		input.run = target_distance > RUN_DISTANCE and me.energy > 25.0
		return input

	input.aim = toward
	if me.state != Fighter.State.IDLE and me.state != Fighter.State.ATTACK:
		return input
	# (the old weapon ultimate button is off for players: GameSim drops it, so a full gauge never freezes the pilot)
	if not class_pick.is_empty():
		return _skill_input(sim, id, me, class_pick)
	if tick % SWING_EVERY == 0:
		memory["swings"] = int(memory["swings"]) + 1
		var every := ClassSkills.heavy_every(sim, me)  # Battle Trance: every 2nd swing is a heavy (class-skills.md 3.3 G4)
		if preload("res://logic/skill_tree_mechanics.gd").take_momentum(me):
			memory["swings"] = int(memory["swings"]) + 1  # Momentum: the next heavy comes one swing earlier
		if int(memory["swings"]) % maxi(1, every if every > 0 else int(profile.get("heavy_every", HEAVY_EVERY))) == 0:
			input.heavy = true
		else:
			input.light = true
	return input


## The input that casts a class skill picked by ClassSkillUse.pick: its slot, aimed at the chosen target or point (the
## authority re-reads the use rule, GameSim._cast_class_skill).
static func _skill_input(sim, id: int, me: Fighter, pick: Dictionary) -> SimInput:
	var input := SimInput.new()
	input.skill_slot = me.skill_state["skills"].find(str(pick["skill"]))
	var at: Vector3 = sim.bodies[id].position
	var choice: Dictionary = pick["choice"]
	var aim_at: Vector3 = at
	if choice.get("point") is Vector3:
		aim_at = choice["point"]
	elif sim.bodies.has(int(choice.get("target", -1))):
		aim_at = sim.bodies[int(choice["target"])].position
	var off := _flat(aim_at - at)
	input.aim = off if off.length() > 0.01 else Vector2(me.direction)
	input.aim_distance = clampf(off.length(), 0.5, 12.0)
	return input


static func SkillData_priority(skill: String) -> float:
	return float(preload("res://logic/class_skills/skill_data.gd").load_default().skill(skill).get("priority", 2))


## The class pilot profile (data/classes/<class>.json "pilot") of a squad card, or {} (old behaviour).
static func pilot_profile(me: Fighter) -> Dictionary:
	var class_id := str(me.race_state.get("class", ""))
	if class_id.is_empty():
		return {}
	var pilot = CardDeck.class_data(class_id).get("pilot", {})
	return pilot if pilot is Dictionary else {}


## True when enemy `fighter` is a boss type (data/races/rules.json boss_types).
static func is_boss(fighter: Fighter) -> bool:
	return RaceData.load_default().rules.get("boss_types", []).has(fighter.enemy_type)


## The enemy this fighter goes for (GDD 3.2). No profile = `nearest` (today's rule). `prefer_marked` /
## `marked_first`: a living enemy carrying `mark_status` within the engage range wins first (Hunter's Mark focus
## fire); `boss_first`: the boss while it lives. Ties: nearer, then lower id (deterministic, no RNG).
static func pick_target(sim, id: int, profile: Dictionary, engage: float, nearest: int) -> int:
	if profile.is_empty():
		return nearest
	var me: Fighter = sim.fighters[id]
	var at: Vector3 = sim.bodies[id].position
	var enemies: Array = []
	for other_id in sim.fighters:
		if sim.fighters[other_id].team != me.team and sim.fighters[other_id].is_alive():
			enemies.append(other_id)
	enemies.sort()
	var kind := str(profile.get("target", "nearest"))
	var mark := str(profile.get("mark_status", "sunder"))
	if bool(profile.get("prefer_marked", false)) or kind == "marked_first":
		var marked := _best(enemies, func(e):
			var d: float = _flat(sim.bodies[e].position - at).length()
			return -d if sim.fighters[e].effects.has(mark) and d <= engage else -INF)
		if marked >= 0:
			return marked
	if bool(profile.get("boss_first", false)):
		for e in enemies:
			if is_boss(sim.fighters[e]):
				return e
	match kind:
		"peel":  # the enemy nearest the most-hurt other ally (nobody else hurt = nearest)
			var hurt := -1
			var worst := 1.0
			var allies: Array = sim.fighters.keys()
			allies.sort()
			for other_id in allies:
				var f: Fighter = sim.fighters[other_id]
				if other_id != id and f.team == me.team and f.is_alive() and f.hp / maxf(1.0, f.max_hp()) < worst:
					worst = f.hp / maxf(1.0, f.max_hp())
					hurt = other_id
			if hurt < 0:
				return nearest
			var guard: Vector3 = sim.bodies[hurt].position
			return _best(enemies, func(e): return -_flat(sim.bodies[e].position - guard).length())
		"densest":  # the enemy with the most other enemies around it, then the nearer
			var radius := float(profile.get("dense_radius", DENSE_RADIUS))
			return _best(enemies, func(e):
				var count := 0
				for o in enemies:
					if o != e and _flat(sim.bodies[o].position - sim.bodies[e].position).length() <= radius:
						count += 1
				return float(count) * 1000.0 - _flat(sim.bodies[e].position - at).length())
		"lowest_hp":  # the finisher: least HP left, then the nearer
			return _best(enemies, func(e): return -sim.fighters[e].hp * 1000.0 - _flat(sim.bodies[e].position - at).length())
	return nearest


## The id in `ids` (sorted) with the highest score; -1 when every score is -INF.
static func _best(ids: Array, score: Callable) -> int:
	var best := -1
	var best_score := -INF
	for e in ids:
		var value: float = score.call(e)
		if value > best_score:
			best_score = value
			best = e
	return best


## How close this fighter walks before it starts attacking: shooters stand off, long weapons start earlier.
## A class pilot's `engage_range` (> 0) wins; a shooter uses its `shoot_range` (> 0) instead of SHOOT_RANGE.
static func _engage_range(combat, me: Fighter, profile: Dictionary = {}) -> float:
	if float(profile.get("engage_range", 0.0)) > 0.0:
		return float(profile["engage_range"])
	var style: Dictionary = combat.styles.get(me.style, {})
	var light: Dictionary = combat.moves.get(str(style.get("ground_light", "")), {})
	if not light.get("spawns", []).is_empty():
		return float(profile["shoot_range"]) if float(profile.get("shoot_range", 0.0)) > 0.0 else SHOOT_RANGE
	var reach := float(combat.weapons.get(me.style, {}).get("params", {}).get("reach", BLADE_REACH))
	return REACH * maxf(1.0, reach / BLADE_REACH)


## Race ultimate fire rule (GDD 3.10.4): the cell's `use.any_of` matches now, or the gauge has been full for
## `use.max_hold_ticks` and an enemy is within the class engage range. No randomness. Each condition may also carry
## `and` [conditions] (all must match) and, as in the GDD data, `and_ally_hurt_below`.
static func wants_ultimate(sim, id: int, engage: float) -> bool:
	var me: Fighter = sim.fighters[id]
	var use: Dictionary = me.race_state.get("ultimate", {}).get("use", {})
	for rule in use.get("any_of", []):
		if use_matches(sim, id, rule):
			return true
	var full_at := int(me.race_state.get("full_at", -1))
	if full_at >= 0 and sim.tick_count - full_at >= int(use.get("max_hold_ticks", DEFAULT_HOLD_TICKS)):
		return _enemies_within(sim, id, sim.bodies[id].position, engage) > 0
	return false


## One `use` condition (the fixed list of GDD 3.7).
static func use_matches(sim, id: int, rule: Dictionary) -> bool:
	var me: Fighter = sim.fighters[id]
	var at: Vector3 = sim.bodies[id].position
	var ok := false
	match str(rule.get("if", "")):
		"enemies_near":
			ok = _enemies_within(sim, id, at, float(rule.get("radius", 3.0))) >= int(rule.get("min", 1))
		"enemies_at_point":
			ok = int(RaceUltimates.densest_point(sim, id, float(rule.get("cast_range", 9.0)), float(rule.get("radius", 3.0)))["count"]) >= int(rule.get("min", 1))
		"ally_hurt":
			var near: Array = _allies(sim, id).filter(func(a): return not rule.has("allies_within") or _flat(sim.bodies[a].position - at).length() <= float(rule["allies_within"]))
			var hurt: Array = near.filter(func(a):
				var f: Fighter = sim.fighters[a]
				return f.hp < f.max_hp() * float(rule.get("below", 0.5)) and (not rule.has("targeted_by_min") or _enemies_within(sim, id, sim.bodies[a].position, TARGETED_RADIUS) >= int(rule["targeted_by_min"])))
			if rule.has("allies_within"):
				ok = not hurt.is_empty() and near.size() >= int(rule.get("min_allies", 1))
			else:
				ok = hurt.size() >= int(rule.get("min_allies", 1))
		"squad_hp_below":
			var allies := _allies(sim, id)
			var total := 0.0
			for a in allies:
				total += sim.fighters[a].hp / maxf(1.0, sim.fighters[a].max_hp())
			ok = not allies.is_empty() and total / float(allies.size()) < float(rule.get("below", 0.5))
			if ok and rule.has("enemies_within"):
				ok = _enemies_within(sim, id, at, float(rule["enemies_within"])) >= int(rule.get("min", 1))
		"ally_downed":
			ok = sim.fighters.keys().any(func(o): return sim.fighters[o].team == me.team and sim.fighters[o].state == Fighter.State.DOWNED and not sim.fighters[o].eliminated)
		"self_hurt":
			ok = me.hp < me.max_hp() * float(rule.get("below", 0.5))
			if ok and rule.has("enemies_within"):
				ok = _enemies_within(sim, id, at, float(rule["enemies_within"])) >= int(rule.get("min", 1))
		"boss_near", "elite_near":
			var key := "boss_types" if str(rule["if"]) == "boss_near" else "elite_types"
			var kinds: Array = RaceData.load_default().rules.get(key, [])
			ok = _enemy_ids(sim, id).any(func(e): return kinds.has(sim.fighters[e].enemy_type) and _flat(sim.bodies[e].position - at).length() <= float(rule.get("radius", 5.0)))
		"execute_ready":
			var low: Array = _enemy_ids(sim, id).filter(func(e):
				var f: Fighter = sim.fighters[e]
				return _flat(sim.bodies[e].position - at).length() <= float(rule.get("range", 12.0)) and f.hp < f.max_hp() * float(rule.get("below", 0.3)) and (not bool(rule.get("boss_only", false)) or is_boss(f)))
			ok = low.size() >= int(rule.get("min", 1))
		"skills_on_cooldown":
			var count := 0
			for a in ([id] if int(rule.get("allies", 1)) <= 1 else _allies(sim, id)):
				if ClassSkills.has_skills(sim.fighters[a]):
					var waiting := 0
					for skill in sim.fighters[a].skill_state["skills"]:
						if ClassSkills.cooldown_left(sim, sim.fighters[a], str(skill)) > 0.0:
							waiting += 1
					if waiting >= int(rule.get("min", 1)):
						count += 1
			ok = count >= int(rule.get("allies", 1))
		"boss_telegraph":
			ok = _enemy_ids(sim, id).any(func(e): return is_boss(sim.fighters[e]) and Combat.is_telegraphing(sim.fighters[e], sim.combat) and _flat(sim.bodies[e].position - at).length() <= float(rule.get("radius", 4.0)))
	if ok and rule.has("and_ally_hurt_below"):
		ok = _allies(sim, id).any(func(a): return sim.fighters[a].hp < sim.fighters[a].max_hp() * float(rule["and_ally_hurt_below"]))
	if ok:
		for extra in rule.get("and", []):
			if not use_matches(sim, id, extra):
				return false
	return ok


static func _allies(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(o): return sim.fighters[o].team == team and sim.fighters[o].is_alive())
	out.sort()
	return out


static func _enemy_ids(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(o): return sim.fighters[o].team != team and sim.fighters[o].is_alive())
	out.sort()
	return out


static func _enemies_within(sim, id: int, point: Vector3, radius: float) -> int:
	return _enemy_ids(sim, id).filter(func(e): return _flat(sim.bodies[e].position - point).length() <= radius).size()


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
