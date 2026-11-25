extends RefCounted
## Cross-class combo states (Boss 2026-11-25, design/gdd/class-skills.md 3.8). Pure rules, static, no nodes.
## Data: data/combat/combos.json (states + per-skill sets/payoffs). A class skill SETS states; another skill PAYS OFF a
## state its target (scope "target") or the cast (scope "cast") finds. State storage: Fighter.combo_states
## {state id: ticks left} (checkpointed with the fighter). Some states are also read from existing machinery:
## stagger = a stun/shock/sleep or hitstun, airborne = Fighter.launched, sunder = the effects.json status (the state's
## duration is the status's), hasted = the haste status, guarded = a Warding Veil / Intercept link on the ally.
## Payoff event: {"type": "combo", "attacker", "target", "skill", "states": [ids], "damage": bonus damage it added}.
## Tally (per fighter, checkpointed): Fighter.combo_payoffs / combo_bonus; fight_totals() sums a team.

const PATH := "res://data/combat/combos.json"
const Fighter := preload("res://logic/fighter.gd")
const STATES: Array[String] = ["stagger", "cluster", "mark", "sunder", "airborne", "taunt", "guarded", "hasted"]
const TAUNTING := "_taunting"  ## internal marker on a tank that taunted recently (Warding Veil payoff); not a UI state

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json := JSON.new()
		if FileAccess.file_exists(PATH) and json.parse(FileAccess.get_file_as_string(PATH)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			_data = json.data
		else:
			_data = {"states": {}, "skills": {}}
	return _data


static func skill(id: String) -> Dictionary:
	return data().get("skills", {}).get(id, {})


static func state_ticks(state: String) -> int:
	return int(round(float(data().get("states", {}).get(state, {}).get("duration", 2.0)) * 60.0))


static func payoffs(skill_id: String, scope: String) -> Array:
	return skill(skill_id).get("payoffs", []).filter(func(p): return str(p.get("scope", "target")) == scope)


# ---------------------------------------------------------------- state queries

static func has(fighter, state: String) -> bool:
	if fighter == null or not fighter.is_alive():
		return false
	if int(fighter.combo_states.get(state, 0)) > 0:
		return true
	match state:
		"stagger":
			return fighter.effects.has("stun") or fighter.effects.has("shock") or fighter.effects.has("sleep") or fighter.state == Fighter.State.HITSTUN
		"airborne":
			return fighter.launched
		"sunder":
			return fighter.effects.has("sunder")
		"hasted":
			return fighter.effects.has("haste")
		"guarded":
			return not fighter.skill_state.get("veil", {}).is_empty() or not fighter.skill_state.get("link", {}).is_empty()
	return false


static func states_of(fighter) -> Array:
	return STATES.filter(func(s): return has(fighter, s))


## The states of `needs` that `fighter` carries when the payoff matches (all / any), else [].
static func matched(fighter, payoff: Dictionary) -> Array:
	var needs: Array = payoff.get("needs", [])
	var found: Array = needs.filter(func(s): return has(fighter, str(s)))
	if str(payoff.get("match", "all")) == "any":
		return found
	return found if found.size() == needs.size() else []


static func set_state(sim, source_id: int, target_id: int, state: String, ticks: int = -1) -> void:
	var target = sim.fighters.get(target_id)
	if target == null or not target.is_alive():
		return
	if ticks < 0:
		ticks = state_ticks(state)
	if state == "sunder":  # the real status (DEF -40%), so Hunter's Mark and the old bonus_status rules see it too
		var Effects = load("res://logic/effects.gd")
		Effects.apply(source_id, sim.fighters[source_id], target_id, target, {"id": "sunder", "chance": 100.0, "duration": ticks}, sim.combat, sim.rng, sim.events)
		return
	target.combo_states[state] = maxi(int(target.combo_states.get(state, 0)), ticks)


static func consume(fighter, states: Array) -> void:
	for s in states:
		fighter.combo_states.erase(str(s))
		if str(s) == "airborne":
			fighter.launched = false


## Damage multiplier of any hit on `target` from the Mark state (any class, basic attacks and skills).
static func mark_mul(target) -> float:
	if target != null and int(target.combo_states.get("mark", 0)) > 0:
		return 1.0 + float(data().get("mark_bonus", 0.15))
	return 1.0


## Records a payoff: the event + the attacker's tally.
static func fire(sim, attacker_id: int, target_id: int, skill_id: String, states: Array, bonus: float = 0.0) -> void:
	var a = sim.fighters.get(attacker_id)
	if a != null:
		a.combo_payoffs += 1
		a.combo_bonus += maxf(0.0, bonus)
	sim.events.append({"type": "combo", "attacker": attacker_id, "target": target_id, "skill": skill_id, "states": states.duplicate(), "damage": maxf(0.0, bonus)})


## Adds bonus damage (not a new payoff) to the attacker's tally: the Mark +15% share.
static func add_bonus(fighters: Dictionary, attacker_id: int, bonus: float) -> void:
	if bonus > 0.0 and fighters.has(attacker_id):
		fighters[attacker_id].combo_bonus += bonus


## {"count", "damage"} of every fighter on `team`.
static func fight_totals(sim, team: String = "player") -> Dictionary:
	var out := {"count": 0, "damage": 0.0}
	for id in sim.fighters:
		var f = sim.fighters[id]
		if f.team == team:
			out["count"] += f.combo_payoffs
			out["damage"] += f.combo_bonus
	return out


# ---------------------------------------------------------------- per tick

## Counts every state down; clears the dead; Intercept's daze watch (airborne enemies hitting a guard).
static func step(sim) -> void:
	var ids: Array = sim.fighters.keys()
	ids.sort()
	for id in ids:
		var f = sim.fighters[id]
		if f.combo_states.is_empty():
			continue
		if not f.is_alive():
			f.combo_states = {}
			continue
		for key in f.combo_states.keys():
			var left := int(f.combo_states[key]) - 1
			if left <= 0:
				f.combo_states.erase(key)
			else:
				f.combo_states[key] = left
	for id in ids:
		var f = sim.fighters[id]
		var watch: Dictionary = f.skill_state.get("daze_watch", {}) if not f.skill_state.is_empty() else {}
		if watch.is_empty():
			continue
		if int(watch["until"]) <= sim.tick_count or not f.is_alive():
			f.skill_state.erase("daze_watch")
			continue
		var at: Vector3 = sim.bodies[id].position
		for e in ids:
			var en = sim.fighters[e]
			if en.team == f.team or not has(en, "airborne"):
				continue
			if Vector2(sim.bodies[e].position.x - at.x, sim.bodies[e].position.z - at.z).length() > float(watch["radius"]):
				continue
			consume(en, ["airborne"])
			var Effects = load("res://logic/effects.gd")
			Effects.apply(id, f, e, en, {"id": "stun", "chance": 100.0, "duration": int(round(float(watch["daze"]) * 60.0))}, sim.combat, sim.rng, sim.events)
			fire(sim, id, e, "intercept", ["airborne"])


# ---------------------------------------------------------------- skill hooks (engine.gd)

## Per-hit payoffs of a skill on one target: {"mul", "crit", "stun", "states", "consume"}; fires nothing.
static func hit_payoff(sim, attacker_id: int, target_id: int, stats: Dictionary) -> Dictionary:
	var out := {"mul": 1.0, "crit": false, "stun": 0.0, "states": [], "consume": []}
	var skill_id := str(stats.get("skill_id", ""))
	var target = sim.fighters[target_id]
	for p in payoffs(skill_id, "target"):
		var found := matched(target, p)
		if found.is_empty():
			continue
		if skill_id == "iron_guard" or skill_id == "intercept" or skill_id == "vault_shot":
			continue  # handled where their effect happens (counter spread, daze watch, the extra shot)
		var mul := float(p.get("damage_mul", 1.0))
		if p.has("per_target"):  # Arcane Orb: +per_target per other enemy in the burst
			mul = minf(float(p.get("max_mul", 2.0)), 1.0 + float(p["per_target"]) * float(maxi(0, int(stats.get("_burst", 1)) - 1)))
		out["mul"] *= mul
		out["crit"] = out["crit"] or bool(p.get("crit", false))
		out["stun"] = maxf(float(out["stun"]), float(p.get("stun", 0.0)))
		for s in found:
			if not out["states"].has(s):
				out["states"].append(s)
		if bool(p.get("consume", false)):
			out["consume"] += found
	return out


## The states a skill sets on an enemy it hit (taunt comes from Iron Guard's pulse, not from its counters).
static func set_on_hit(sim, attacker_id: int, target_id: int, stats: Dictionary) -> void:
	var skill_id := str(stats.get("skill_id", ""))
	var states: Dictionary = data().get("states", {})
	for s in skill(skill_id).get("sets", []):
		if str(states.get(s, {}).get("side", "enemy")) != "enemy" or s == "taunt":
			continue
		var ticks := -1
		if s == "stagger" and stats.has("_stagger_mul"):
			ticks = int(round(state_ticks("stagger") * float(stats["_stagger_mul"])))
		set_state(sim, attacker_id, target_id, str(s), ticks)


## Cast-scope payoffs, read when the cast starts. Changes `stats` / the choice in place; returns the states paid off
## (the caller fires the event once the cast is accepted).
static func on_cast(sim, id: int, skill_id: String, stats: Dictionary, choice: Dictionary) -> Array:
	var paid: Array = []
	var at: Vector3 = sim.bodies[id].position
	var me = sim.fighters[id]
	for p in payoffs(skill_id, "cast"):
		var found: Array = []
		match skill_id:
			"shield_rush":  # dash to a marked enemy in range, longer stagger
				var best := -1
				var best_d := INF
				for e in _enemies(sim, id):
					var d := _d(sim, at, e)
					if has(sim.fighters[e], "mark") and d <= float(stats.get("range", 7.0)) and d < best_d:
						best_d = d
						best = e
				if best >= 0:
					choice["target"] = best
					stats["stun"] = float(stats.get("stun", 0.0)) * float(p.get("stun_mul", 1.5))
					stats["_stagger_mul"] = float(p.get("stagger_mul", 1.5))
					found = ["mark"]
			"crater_leap":
				var point: Vector3 = choice.get("point", at)
				if _enemies(sim, id).any(func(e): return has(sim.fighters[e], "cluster") and _d(sim, point, e) <= float(stats.get("radius", 2.5)) * float(p.get("radius_mul", 1.5))):
					stats["radius"] = float(stats["radius"]) * float(p.get("radius_mul", 1.5))
					found = ["cluster"]
			"hook_sweep":
				if _enemies(sim, id).any(func(e): return has(sim.fighters[e], "airborne") and _d(sim, at, e) <= float(p.get("pull_range", 9.0))):
					stats["pull_range"] = maxf(float(stats.get("pull_range", 5.0)), float(p.get("pull_range", 9.0)))
					stats["pull"] = maxf(float(stats.get("pull", 2.0)), float(p.get("pull_range", 9.0)) - 1.0)
					found = ["airborne"]
			"battle_trance":
				if has(me, "hasted"):
					found = ["hasted"]
				elif _enemies(sim, id).any(func(e): return has(sim.fighters[e], "taunt") and _d(sim, at, e) <= float(p.get("radius", 5.0))):
					found = ["taunt"]
				if not found.is_empty():
					stats["duration"] = float(stats.get("duration", 6.0)) * float(p.get("duration_mul", 1.5))
			"rapid_fire":
				var t = sim.fighters.get(int(choice.get("target", -1)))
				if t != null and t.team != me.team:
					found = matched(t, p)
				if not found.is_empty():
					stats["arrows"] = maxi(int(stats.get("arrows", 4)), int(p.get("arrows", 6)))
			"repulse_nova":
				for a in sim.fighters:
					if sim.fighters[a].team == me.team and has(sim.fighters[a], "guarded") and _d(sim, at, a) <= float(p.get("radius", 4.0)):
						found = ["guarded"]
						break
				if not found.is_empty():
					stats["knockback"] = float(stats.get("knockback", 0.0)) * float(p.get("knockback_mul", 1.5))
					stats["damage"] = float(stats["damage"]) * float(p.get("damage_mul", 1.0))
			"warding_veil":
				var ally = sim.fighters.get(int(choice.get("target", -1)))
				if ally != null and ally.team == me.team and int(ally.combo_states.get(TAUNTING, 0)) > 0:
					stats["thorns"] = float(stats.get("thorns", 0.0)) + float(p.get("reflect", 0.3))
					found = ["taunt"]
		for s in found:
			if not paid.has(s):
				paid.append(s)
	return paid


## What a skill sets at release apart from hits: Iron Guard's taunt pulse, Intercept's guard (+ daze watch).
static func on_release(sim, id: int, skill_id: String, stats: Dictionary, target: int) -> void:
	match skill_id:
		"iron_guard":
			var radius := float(skill(skill_id).get("taunt_radius", 3.0))
			var ticks := state_ticks("taunt")
			load("res://logic/race_passives.gd").pulse_aggro(sim, id, radius, ticks)
			for e in _enemies(sim, id):
				if _d(sim, sim.bodies[id].position, e) <= radius:
					set_state(sim, id, e, "taunt", ticks)
			sim.fighters[id].combo_states[TAUNTING] = ticks
		"intercept":
			if sim.fighters.has(target) and sim.fighters[target].team == sim.fighters[id].team:
				sim.fighters[target].combo_states["guarded"] = state_ticks("guarded")
			for p in skill(skill_id).get("payoffs", []):
				sim.fighters[id].skill_state["daze_watch"] = {"until": sim.tick_count + state_ticks("guarded"), "radius": float(p.get("daze_radius", 3.0)), "daze": float(p.get("daze", 1.0))}
		"warding_veil":
			if sim.fighters.has(target) and sim.fighters[target].team == sim.fighters[id].team:
				sim.fighters[target].combo_states["hasted"] = state_ticks("hasted")


## Iron Guard counter vs a clustered attacker: the other enemies of the cluster near it (excluding the attacker).
static func counter_spread(sim, id: int, attacker: int) -> Array:
	for p in skill("iron_guard").get("payoffs", []):
		if not matched(sim.fighters[attacker], p).is_empty():
			var at: Vector3 = sim.bodies[attacker].position
			return _enemies(sim, id).filter(func(e): return e != attacker and _d(sim, at, e) <= float(p.get("counter_radius", 2.5)))
	return []


## Vault Shot vs a taunted target: how many extra shots and the gap (s).
static func extra_shots(sim, target: int) -> Array:
	for p in skill("vault_shot").get("payoffs", []):
		if sim.fighters.has(target) and not matched(sim.fighters[target], p).is_empty():
			return [int(p.get("extra_shots", 1)), float(p.get("shot_gap", 0.25))]
	return [0, 0.0]


# ---------------------------------------------------------------- pilot helpers

## Payoff states the skills of `id` that are ready (or nearly) want on an enemy, plus "mark" (every class gains on it).
static func wanted_states(sim, id: int) -> Array:
	var me = sim.fighters[id]
	var out: Array = ["mark"]
	var Skills = load("res://logic/class_skills/engine.gd")
	for s in me.skill_state.get("skills", []):
		if Skills.cooldown_left(sim, me, str(s)) > 1.0:
			continue
		for p in payoffs(str(s), "target") + payoffs(str(s), "cast"):
			for n in p.get("needs", []):
				if str(data().get("states", {}).get(n, {}).get("side", "enemy")) == "enemy" and not out.has(n):
					out.append(str(n))
	return out


## Seconds until an ally's running cast releases a skill that sets one of `needs` (INF = none coming).
static func setup_coming(sim, id: int, needs: Array) -> float:
	var best := INF
	for a in sim.fighters:
		var f = sim.fighters[a]
		if a == id or f.team != sim.fighters[id].team or not f.is_alive():
			continue
		var cast: Dictionary = f.skill_state.get("cast", {}) if not f.skill_state.is_empty() else {}
		if cast.is_empty() or int(cast.get("done", 0)) >= cast.get("releases", []).size():
			continue
		var sets: Array = skill(str(cast["skill"])).get("sets", [])
		if needs.any(func(n): return sets.has(n)):
			best = minf(best, float(int(cast["releases"][int(cast["done"])]) - sim.tick_count) / 60.0)
	return best


static func _enemies(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(e): return sim.fighters[e].team != team and sim.fighters[e].is_alive())
	out.sort()
	return out


static func _d(sim, at: Vector3, e: int) -> float:
	var p: Vector3 = sim.bodies[e].position
	return Vector2(p.x - at.x, p.z - at.z).length()
