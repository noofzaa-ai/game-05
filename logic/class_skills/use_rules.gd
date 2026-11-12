extends RefCounted
## Auto-pilot rules for the class skills v2 (design/gdd/class-skills.md 3.2-3.5 "AI rule", 3.7; E15). Pure rules,
## deterministic (no RNG; ties break by distance, then fighter id). Each skill's `use` block in
## data/class_skills/class_skills.json lists conditions: the first `any_of` entry that matches (with its own `and`, and
## the block's `and`) picks who/where the skill goes. Race conditions (enemies_near, boss_near, elite_near, self_hurt,
## boss_telegraph, ally_hurt) are logic/auto_pilot.gd use_matches; the skill-only ones are here.
## pick() returns the skill to cast now and its choice {"target", "point"}, in the GDD 3.7 priority order.

const SkillData := preload("res://logic/class_skills/skill_data.gd")
const Skills := preload("res://logic/class_skills/engine.gd")
const PILOT := "res://logic/auto_pilot.gd"  ## loaded at call time (auto_pilot preloads this file)
const ULTS := "res://logic/race_ultimates.gd"
const RACE_CONDITIONS: Array[String] = ["enemies_near", "boss_near", "elite_near", "self_hurt", "boss_telegraph", "ally_hurt"]
const ATTACKED_RADIUS := 3.0  ## an enemy this close to an ally counts as attacking it
const BACKLINE: Array[String] = ["magic", "longbow"]


## The ready skill to cast now (lowest priority number first, then slot order) -> {"skill", "choice"}, or {}.
## `target` = the pilot's current target (-1 = none). Skills on cooldown or short of stamina are skipped.
static func pick(sim, id: int, target: int) -> Dictionary:
	var fighter = sim.fighters[id]
	var data = SkillData.load_default()
	var order: Array = []
	var skills: Array = fighter.skill_state.get("skills", [])
	for slot in skills.size():
		var skill := str(skills[slot])
		var info: Dictionary = data.skill(skill)
		var priority := float(info.get("priority", 2))
		if info.has("boss_priority") and _boss_within(sim, id, float(info.get("boss_radius", 3.0))):
			priority = float(info["boss_priority"])  # Battle Trance goes first when the boss is in range (3.7)
		order.append([priority, slot, skill])
	order.sort()
	var held: Dictionary = fighter.skill_state.get("held", {})
	fighter.skill_state["held"] = held
	for row in order:
		var skill: String = row[2]
		if Skills.cooldown_left(sim, fighter, skill) > 0.0 or fighter.energy < float(data.skill(skill).get("stamina", 0.0)):
			held.erase(skill)
			continue
		if not held.has(skill):
			held[skill] = sim.tick_count  # ready since (the held_for rules)
		var choice := choose(sim, id, skill, target)
		if not choice.is_empty():
			held.erase(skill)
			return {"skill": skill, "choice": choice}
	return {}


## The skill's use rule now: {} = do not cast, else {"target": id, "point": Vector3 (optional)}.
static func choose(sim, id: int, skill: String, target: int) -> Dictionary:
	var use: Dictionary = SkillData.load_default().skill(skill).get("use", {})
	for rule in use.get("any_of", []):
		var choice := matches(sim, id, skill, rule, target)
		if choice.is_empty():
			continue
		var ok := true
		for extra in use.get("and", []):
			if matches(sim, id, skill, extra, target).is_empty():
				ok = false
				break
		if ok:
			return choice
	return {}


## One condition: {} when it does not hold, else the choice it gives ({"target": -1} = no particular target).
static func matches(sim, id: int, skill: String, rule: Dictionary, target: int) -> Dictionary:
	var me = sim.fighters[id]
	var at: Vector3 = sim.bodies[id].position
	var kind := str(rule.get("if", ""))
	var out := {}
	if RACE_CONDITIONS.has(kind):
		if load(PILOT).use_matches(sim, id, rule):
			out = {"target": target}
	else:
		match kind:
			"target_within":
				if _enemy(sim, id, target) and _d(sim, id, target) <= float(rule.get("radius", 3.0)):
					out = {"target": target}
			"nearest_within":
				var e := _nearest(sim, id, at, float(rule.get("radius", 3.0)), [])
				if e >= 0:
					out = {"target": e}
			"peel_target_attacking_ally":
				var e := peel_target(sim, id)
				if e >= 0:
					var d := _d(sim, id, e)
					if d >= float(rule.get("min", 0.0)) and d <= float(rule.get("max", 7.0)):
						out = {"target": e}
			"self_attacked_by":
				if _enemies(sim, id).filter(func(e): return _flat(sim.bodies[e].position - at).length() <= float(rule.get("radius", 3.0))).size() >= int(rule.get("count", 1)):
					out = {"target": target}
			"self_hp_at_least":
				if me.hp >= me.max_hp() * float(rule.get("at_least", 0.0)):
					out = {"target": target}
			"ally_below_hp_attacked":
				var ally := hurt_ally(sim, id, rule)
				if ally >= 0:
					out = {"target": ally}
			"enemies_in_arc", "boss_in_arc":
				var aim := target if _enemy(sim, id, target) else _nearest(sim, id, at, INF, [])
				if aim >= 0:
					var stats := Skills.cast_stats(me, skill)
					var inside: Array = Skills.in_arc(sim, id, at, sim.bodies[aim].position, float(stats.get("radius", 3.0)), float(stats.get("arc_deg", 240.0)))
					if kind == "boss_in_arc":
						if inside.any(func(e): return Skills.is_boss(sim.fighters[e])):
							out = {"target": aim}
					elif inside.size() >= int(rule.get("min", 1)):
						out = {"target": aim}
			"held_for":
				var since := int(me.skill_state.get("held", {}).get(skill, sim.tick_count))
				if sim.tick_count - since >= SkillData.ticks(float(rule.get("seconds", 3.0))):
					out = {"target": target}
			"dense_point":
				var best: Dictionary = load(ULTS).densest_point(sim, id, float(rule.get("reach", 7.0)), float(rule.get("radius", 2.5)))
				if best["pos"] != null and int(best["count"]) >= int(rule.get("min", 1)):
					var point: Vector3 = best["pos"]
					var ok := not rule.has("farther_than") or _flat(point - at).length() > float(rule["farther_than"])
					if ok and bool(rule.get("with_elite", false)):
						ok = _enemies(sim, id).any(func(e): return Skills.is_elite(sim.fighters[e]) and _flat(sim.bodies[e].position - point).length() <= float(rule.get("radius", 2.5)))
					if ok:
						out = {"target": -1, "point": point}
			"boss_between":
				for e in _enemies(sim, id):
					var d := _d(sim, id, e)
					if Skills.is_boss(sim.fighters[e]) and d >= float(rule.get("min", 0.0)) and d <= float(rule.get("max", 7.0)):
						out = {"target": e, "point": sim.bodies[e].position}
						break
				if out.is_empty() and kind == "boss_between":
					pass
			"loose_pack":
				var outer: Array = _enemies(sim, id).filter(func(e): return _flat(sim.bodies[e].position - at).length() <= float(rule.get("radius", 5.0)))
				var inner: Array = outer.filter(func(e): return _flat(sim.bodies[e].position - at).length() <= float(rule.get("inner", 2.5)))
				var pullable: Array = outer.filter(func(e): return not Skills.is_elite(sim.fighters[e]))
				if outer.size() >= int(rule.get("min", 3)) and inner.size() < int(rule.get("inner_below", 2)) and not pullable.is_empty():
					out = {"target": target}
			"best_shot":
				var range_m := float(rule.get("range", 12.0))
				var inside: Array = _enemies(sim, id).filter(func(e): return _d(sim, id, e) <= range_m)
				var pickers: Array = [func(e): return Skills.is_boss(sim.fighters[e]), func(e): return Skills.is_elite(sim.fighters[e]),
					func(e): return sim.fighters[e].effects.has("sunder"), func(e): return e == target]
				for test in pickers:
					var found: Array = inside.filter(test)
					if not found.is_empty():
						out = {"target": _closest_of(sim, id, found)}
						break
			"enemy_near_backline":
				var guard: Array = [id]
				for a in _allies(sim, id):
					if a != id and BACKLINE.has(str(sim.fighters[a].race_state.get("class", ""))):
						guard.append(a)
				var best := -1
				var best_d := INF
				for e in _enemies(sim, id):
					if sim.fighters[e].effects.has("shock") or _d(sim, id, e) > float(rule.get("range", 12.0)):
						continue
					for a in guard:
						var d := _flat(sim.bodies[e].position - sim.bodies[a].position).length()
						if d <= float(rule.get("distance", 3.0)) and d < best_d:
							best_d = d
							best = e
				if best >= 0:
					out = {"target": best}
			"closing_enemy":
				var best := -1
				var best_speed := 0.05
				for e in _enemies(sim, id):
					if sim.fighters[e].effects.has("shock") or _d(sim, id, e) > float(rule.get("range", 8.0)):
						continue
					var toward := _flat(at - sim.bodies[e].position).normalized()
					var v: Vector3 = sim.bodies[e].velocity
					var speed := Vector2(v.x, v.z).dot(toward)
					if speed > best_speed:
						best_speed = speed
						best = e
				if best >= 0:
					out = {"target": best}
			"target_cluster":
				if _enemy(sim, id, target) and _d(sim, id, target) <= float(rule.get("range", 12.0)):
					var c: Vector3 = sim.bodies[target].position
					if _enemies(sim, id).filter(func(e): return _flat(sim.bodies[e].position - c).length() <= float(rule.get("radius", 2.0))).size() >= int(rule.get("min", 2)):
						out = {"target": target}
			"target_is_boss":
				if _enemy(sim, id, target) and Skills.is_boss(sim.fighters[target]) and _d(sim, id, target) <= float(rule.get("range", 12.0)):
					out = {"target": target}
	if out.is_empty():
		return {}
	for extra in rule.get("and", []):
		if matches(sim, id, skill, extra, target).is_empty():
			return {}
	return out


## The `peel` enemy (GDD 3.2 S1): the enemy nearest the most-hurt other ally that stands within ATTACKED_RADIUS of that
## ally (it is attacking it). -1 when nobody threatens an ally.
static func peel_target(sim, id: int) -> int:
	var allies: Array = _allies(sim, id).filter(func(a): return a != id)
	allies.sort_custom(func(a, b):
		var ha: float = sim.fighters[a].hp / maxf(1.0, sim.fighters[a].max_hp())
		var hb: float = sim.fighters[b].hp / maxf(1.0, sim.fighters[b].max_hp())
		return ha < hb if ha != hb else a < b)
	for a in allies:
		var e := _nearest(sim, id, sim.bodies[a].position, ATTACKED_RADIUS, [])
		if e >= 0:
			return e
	return -1


## ally_below_hp_attacked {below, range, self, skip_linked, most_attacked}: the most-hurt ally (or the one most enemies
## attack, then the most hurt) within range, below the HP fraction, with an enemy on it.
static func hurt_ally(sim, id: int, rule: Dictionary) -> int:
	var best := -1
	var best_key := [INF, INF]
	for a in _allies(sim, id):
		if a == id and not bool(rule.get("self", false)):
			continue
		var f = sim.fighters[a]
		if f.hp >= f.max_hp() * float(rule.get("below", 0.6)) or _d(sim, id, a) > float(rule.get("range", 8.0)):
			continue
		if bool(rule.get("skip_linked", false)) and not f.skill_state.get("link", {}).is_empty():
			continue
		var on_it: int = _enemies(sim, id).filter(func(e): return _flat(sim.bodies[e].position - sim.bodies[a].position).length() <= ATTACKED_RADIUS).size()
		if on_it == 0:
			continue
		var key := [-float(on_it) if bool(rule.get("most_attacked", false)) else 0.0, f.hp / maxf(1.0, f.max_hp())]
		if key[0] < best_key[0] or (key[0] == best_key[0] and key[1] < best_key[1]):
			best_key = key
			best = a
	return best


static func _boss_within(sim, id: int, radius: float) -> bool:
	return _enemies(sim, id).any(func(e): return Skills.is_boss(sim.fighters[e]) and _d(sim, id, e) <= radius)


static func _closest_of(sim, id: int, ids: Array) -> int:
	var best := -1
	var best_d := INF
	for e in ids:
		var d := _d(sim, id, e)
		if d < best_d:
			best_d = d
			best = e
	return best


static func _nearest(sim, id: int, point: Vector3, radius: float, skip: Array) -> int:
	var best := -1
	var best_d := radius
	for e in _enemies(sim, id):
		var d := _flat(sim.bodies[e].position - point).length()
		if not skip.has(e) and d <= best_d and (best < 0 or d < best_d):
			best_d = d
			best = e
	return best


static func _enemy(sim, id: int, e: int) -> bool:
	return sim.fighters.has(e) and sim.fighters[e].team != sim.fighters[id].team and sim.fighters[e].is_alive()


static func _enemies(sim, id: int) -> Array:
	return Skills._enemy_ids(sim, id)


static func _allies(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(o): return sim.fighters[o].team == team and sim.fighters[o].is_alive())
	out.sort()
	return out


static func _d(sim, id: int, other: int) -> float:
	return _flat(sim.bodies[other].position - sim.bodies[id].position).length()


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
