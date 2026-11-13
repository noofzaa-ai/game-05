extends RefCounted
## Skill tree `mechanic` nodes and the node actions reflect / death_save in battle (design/gdd/skill-tree.md 3.5,
## 3.8-3.10; data/skill_tree/rules.json vocabulary.mechanics). Pure rules, static, no nodes.
## A learned mechanic is stored by TreeEffects.attach in race_state.tree.mechanics {id: params}; this file runs each id.
## Hooks (one call each, so the engines stay readable):
##  - step(): once per tick per race fighter from RacePassives.step, after the triggers: reads this tick's events
##    (kills, heals, casts, heavies, ultimates, discharges) and runs the timers (death save, Twin Ultimate echo,
##    Mastery Overflow, World Tree revive, Blink Caster, Warding Sigil breaks).
##  - attach_rewrites(): data rewrites of the card's cells at attach (Spring Rite cap, Shatterglyph, Grand Runeweaver
##    focus, Blood Cyclone whirl).
##  - damage: dealt_mul (Pack Hunt, Called Target), taken_mul (Bulwark Guard), skill_damage_mul (Arcane Convergence),
##    deadeye (Deadeye), cheat_death (Valhalla's Call `death_save`), titan_radius (Titan's Swing).
##  - class skill casts: cast_mods / cast_done / release_copy (Weave Rhythm, Grand Archmage, Disciplined Casting,
##    Skirmisher, Blood Sorcery).
## All state lives in race_state (checkpointed). Deterministic: no RNG.

const TreeEffects := preload("res://logic/skill_tree_effects.gd")
const Effects := preload("res://logic/effects.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimBody := preload("res://logic/sim_body.gd")
const RACE := "res://logic/race_passives.gd"
const SKILLS := "res://logic/class_skills/engine.gd"
const ULTS := "res://logic/race_ultimates.gd"
const DEFAULT_MARK := "sunder"  ## Hunter's Mark when the card has no Hunter's Mark trigger of its own (data fallback)


static func params(fighter, id: String):
	if fighter == null or fighter.race_state.is_empty():
		return null
	return TreeEffects.mechanics(fighter).get(id)


static func has(fighter, id: String) -> bool:
	return params(fighter, id) != null


# ---------------------------------------------------------------- attach-time rewrites

static func attach_rewrites(fighter) -> void:
	var mech: Dictionary = TreeEffects.mechanics(fighter)
	if mech.is_empty():
		return
	for entry in fighter.race_state["effects"]:
		if str(entry["src"]) != "passive":
			continue
		var effect: Dictionary = entry["effect"]
		if mech.has("spring_rite") and str(effect["type"]) == "trigger":  # Bloomcaster heal cap 8% -> 12%
			for action in effect.get("actions", []):
				if str(action.get("action", "")) == "heal" and action.has("cap_max_hp"):
					action["cap_max_hp"] = float(mech["spring_rite"]["heal_cap"])
		if str(effect["type"]) != "charges":
			continue
		if mech.has("shatterglyph"):  # Runic Edge burst counts as a heavy for Cleave + a shock zone
			var p: Dictionary = mech["shatterglyph"]
			var extra: Array = []
			for action in effect["actions"]:
				if str(action.get("action", "")) == "burst":
					action["cleave"] = true
					extra.append({"action": "zone", "center": "self", "radius": float(p["radius"]), "duration_ticks": int(p["ticks"]), "every_ticks": int(p["ticks"]),
						"pulse": [{"action": "apply_status", "status": str(p["status"]), "target": "enemies_in_zone", "first_only": true}]})
			effect["actions"] = effect["actions"] + extra
		if mech.has("grand_runeweaver"):  # Runeweaver's shields also give focus
			var p: Dictionary = mech["grand_runeweaver"]
			var extra: Array = []
			for action in effect["actions"]:
				if str(action.get("action", "")) == "shield":
					extra.append({"action": "apply_status", "status": str(p["status"]), "target": str(action.get("target", "self")), "duration": int(p["ticks"])})
			effect["actions"] = effect["actions"] + extra
	if mech.has("blood_cyclone"):  # Ragnarok Whirl: +kill_add_ticks per kill, cap cap_ticks
		for action in fighter.race_state.get("ultimate", {}).get("actions", []):
			if action.has("extend_on_kill_ticks"):
				action["extend_on_kill_ticks"] = int(mech["blood_cyclone"]["kill_add_ticks"])
				action["extend_max_ticks"] = int(mech["blood_cyclone"]["cap_ticks"])


# ---------------------------------------------------------------- damage hooks

## Outgoing damage multiplier from the attacker's squad: Pack Hunt (any hit), Called Target (skill hits) on marked targets.
static func dealt_mul(fighters: Dictionary, attacker_id: int, target, skill: bool) -> float:
	var attacker = fighters.get(attacker_id)
	if attacker == null or attacker.team == target.team:
		return 1.0
	var pack := 1.0
	var called := 1.0
	for other_id in fighters:
		var ally = fighters[other_id]
		if ally.team != attacker.team or ally.race_state.is_empty():
			continue
		var p = params(ally, "pack_hunt")
		if p != null and target.effects.has(mark_status(ally)):
			pack = maxf(pack, float(p["marked_damage_mul"]))
		var c = params(ally, "called_target")
		if skill and c != null and target.effects.has(mark_status(ally)):
			called = maxf(called, float(c["skill_damage_mul"]))
	return pack * called


## Hunter's Mark's status: the card's own signature trigger, else the default.
static func mark_status(fighter) -> String:
	for entry in fighter.race_state.get("effects", []):
		if str(entry["src"]) == "signature" and str(entry["effect"]["type"]) == "trigger":
			for action in entry["effect"].get("actions", []):
				if str(action.get("action", "")) == "apply_status":
					return str(action["status"])
	return DEFAULT_MARK


## Incoming damage multiplier: Bulwark Guard while this card's Bulwark taunt is up (tick = the hit's tick).
static func taken_mul(target, tick: int) -> float:
	var p = params(target, "bulwark_guard")
	if p == null or not bulwark_up(target, tick):
		return 1.0
	return float(p["damage_taken_mul"])


static func bulwark_up(fighter, tick: int) -> bool:
	return int(fighter.race_state.get("bulwark_until", -1)) > tick


## Arcane Convergence: logs this skill hit; x damage_mul once the target was hit by `skills` different class skills of
## this card within window_ticks (this hit included).
static func skill_damage_mul(sim, id: int, target_id: int, skill: String) -> float:
	var fighter = sim.fighters[id]
	var mul: float = dealt_mul(sim.fighters, id, sim.fighters[target_id], true)
	var p = params(fighter, "arcane_convergence")
	if p == null or skill.is_empty():
		return mul
	var log_all: Dictionary = fighter.race_state.get("conv", {})
	var hits: Dictionary = log_all.get(str(target_id), {})
	hits[skill] = sim.tick_count
	log_all[str(target_id)] = hits
	fighter.race_state["conv"] = log_all
	return mul * (float(p["damage_mul"]) if _converged(sim, fighter, target_id) else 1.0)


static func _converged(sim, fighter, target_id: int) -> bool:
	var p = params(fighter, "arcane_convergence")
	if p == null:
		return false
	var hits: Dictionary = fighter.race_state.get("conv", {}).get(str(target_id), {})
	var fresh := 0
	for skill in hits:
		if sim.tick_count - int(hits[skill]) <= int(p["window_ticks"]):
			fresh += 1
	return fresh >= int(p["skills"])


## A class-skill kill by fighter `id`: Arcane Convergence burst when the target died converged.
static func skill_kill(sim, id: int, target_id: int) -> void:
	var fighter = sim.fighters[id]
	if not _converged(sim, fighter, target_id):
		return
	var p: Dictionary = params(fighter, "arcane_convergence")
	fighter.race_state["conv"].erase(str(target_id))
	load(RACE).run_action(sim, id, {"action": "burst", "center": "target", "radius": float(p["radius"]), "atk_mul": float(p["atk_mul"])}, {"target": target_id})
	sim.events.append({"type": "tree_convergence", "player": id, "target": target_id, "pos": sim.bodies[target_id].position, "radius": float(p["radius"])})


## Deadeye: true when this basic projectile hit on a marked target is the every_n-th (forced crit + pierce).
static func deadeye(attacker, target, source: Dictionary) -> bool:
	var p = params(attacker, "deadeye")
	if p == null or not source.has("projectile") or bool(source.get("pierce_copy", false)) or not target.effects.has(mark_status(attacker)):
		return false
	var n := int(attacker.race_state.get("deadeye_n", 0)) + 1
	attacker.race_state["deadeye_n"] = n
	return n % maxi(1, int(p["every_n"])) == 0


## The next living enemy behind `target_id` on the shot's line (0.6 m wide, 12 m), or -1 (Deadeye's pierce).
static func pierce_next(fighters: Dictionary, bodies: Dictionary, attacker_id: int, target_id: int, dir: Vector2) -> int:
	if dir.length() < 0.001:
		return -1
	var d := dir.normalized()
	var from: Vector3 = bodies[target_id].position
	var best := -1
	var best_along := INF
	var ids: Array = fighters.keys()
	ids.sort()
	for e in ids:
		var f = fighters[e]
		if e == target_id or f.team == fighters[attacker_id].team or not f.is_alive():
			continue
		var off := Vector2(bodies[e].position.x - from.x, bodies[e].position.z - from.z)
		var along := off.dot(d)
		if along > 0.0 and along <= 12.0 and absf(off.cross(d)) <= 0.6 and along < best_along:
			best_along = along
			best = e
	return best


## Titan's Swing: the radius of this card's heavy sweep (0 = not a heavy or no node).
static func titan_radius(fighter, move_id: String) -> float:
	var p = params(fighter, "titan_swing")
	if p == null or not move_id.contains("heavy"):
		return 0.0
	return float(p["radius"])


## Skirmisher: dodge cooldown multiplier.
static func dodge_cd_mul(fighter) -> float:
	var p = params(fighter, "skirmisher")
	return 1.0 if p == null else float(p["dodge_cd_mul"])


## Wall of Fury: extra Bulwark radius below `below` HP.
static func bulwark_radius_add(fighter) -> float:
	var p = params(fighter, "wall_of_fury")
	if p == null or fighter.hp >= fighter.max_hp() * float(p["below"]):
		return 0.0
	return float(p["radius_add"])


## Blood Cyclone on a Cleave bonus: x (1 + missing HP), capped at max_bonus. Returns the bonus.
static func cleave_bonus(fighter, bonus: float, cap: float) -> float:
	var p = params(fighter, "blood_cyclone")
	if p == null:
		return minf(bonus, cap)
	var missing := clampf(1.0 - fighter.hp / maxf(1.0, fighter.max_hp()), 0.0, 1.0)
	return minf(bonus * (1.0 + missing), float(p["max_bonus"]))


# ---------------------------------------------------------------- Valhalla's Call (death_save)

## A blow brought this card to 0 HP. True = it lives on at 1 HP: a death save is running, or a lethal_hit trigger with
## a death_save action is ready this wave (it starts now). The caller sets HP to 1 and does not kill.
static func cheat_death(target_id: int, target, events: Array) -> bool:
	if target.race_state.is_empty():
		return false
	if not target.race_state.get("death_save", {}).is_empty():
		return true
	var effects: Array = target.race_state.get("effects", [])
	for index in effects.size():
		var effect: Dictionary = effects[index]["effect"]
		if str(effect["type"]) != "trigger" or str(effect.get("on", "")) != "lethal_hit":
			continue
		for action in effect.get("actions", []):
			if str(action.get("action", "")) != "death_save":
				continue
			var fx: Dictionary = target.race_state["fx"].get(str(index), {"last": -1, "n": 0, "wave": -1, "low": false})
			target.race_state["fx"][str(index)] = fx
			if bool(effect.get("once_per_wave", false)) and int(fx["wave"]) == int(target.race_state["wave"]):
				continue
			fx["wave"] = int(target.race_state["wave"])
			var boost := {"stat": "ATK", "max_mul": float(action.get("atk_mul", 0.0)), "below": 2.0, "death_save": true}
			boost["type"] = "low_hp_scaling"  # the ATK boost rides the race low-HP scaling list (below 2.0 = always on)
			target.race_state["scaling"] = target.race_state.get("scaling", []) + [boost]
			target.race_state["death_save"] = {"until": -1, "ticks": int(action.get("duration_ticks", 240)), "survive": float(action.get("survive_if_kill", 0.0)), "kill": false}
			events.append({"type": "race_proc", "player": target_id, "source": str(effects[index]["src"]), "name": "death_save", "on": "lethal_hit"})
			events.append({"type": "tree_death_save", "player": target_id})
			return true
	return false


static func _death_save_tick(sim, id: int, fighter, events: Array) -> void:
	var save: Dictionary = fighter.race_state.get("death_save", {})
	if save.is_empty():
		return
	if int(save["until"]) < 0:
		save["until"] = sim.tick_count + int(save["ticks"])
	for event in events:
		if str(event.get("type", "")) == "killed" and int(event.get("by", -1)) == id and sim.fighters.has(int(event["target"])) and sim.fighters[int(event["target"])].team != fighter.team:
			save["kill"] = true
	if sim.tick_count < int(save["until"]):
		fighter.hp = maxf(1.0, fighter.hp)
		return
	fighter.race_state.erase("death_save")
	fighter.race_state["scaling"] = fighter.race_state.get("scaling", []).filter(func(e): return not bool(e.get("death_save", false)))
	if bool(save["kill"]):
		fighter.hp = maxf(fighter.hp, fighter.max_hp() * float(save["survive"]))
		sim.events.append({"type": "tree_death_save_end", "player": id, "survived": true})
		return
	fighter.hp = 0.0
	fighter.state = Fighter.State.DEAD
	fighter.state_ticks = 0
	fighter.move_id = ""
	Effects.clear(fighter, sim.combat)
	sim.events.append({"type": "tree_death_save_end", "player": id, "survived": false})
	sim.events.append({"type": "killed", "target": id, "by": -1})


# ---------------------------------------------------------------- class skill casts

## Changes a cast's stats before it starts (peek: nothing is spent). Returns true when the cast costs no stamina.
static func cast_mods(fighter, stats: Dictionary) -> bool:
	if fighter.race_state.is_empty():
		return false
	var free := false
	var n := int(fighter.race_state.get("casts", 0)) + 1
	var weave = params(fighter, "weave_rhythm")
	if weave != null and n % maxi(1, int(weave["every_n"])) == 0:
		free = true
		if stats.has("damage"):
			stats["damage"] = float(stats["damage"]) * float(weave["damage_mul"])
	if int(fighter.race_state.get("free_casts", 0)) > 0:
		free = true
	var sorcery = params(fighter, "blood_sorcery")
	if sorcery != null and stats.has("radius") and fighter.hp < fighter.max_hp() * float(sorcery["below"]):
		stats["radius"] = float(stats["radius"]) * float(sorcery["radius_mul"])
	if bool(fighter.race_state.get("instant_cast", false)):
		stats["cast_time"] = 0.0  # Skirmisher: the skill after a dodge casts instantly
	return free


## The cast started: counters move on; Grand Archmage marks the cast to fire twice.
static func cast_done(sim, id: int, fighter, cast: Dictionary) -> void:
	if fighter.race_state.is_empty():
		return
	var n := int(fighter.race_state.get("casts", 0)) + 1
	fighter.race_state["casts"] = n
	if int(fighter.race_state.get("free_casts", 0)) > 0:
		fighter.race_state["free_casts"] = int(fighter.race_state["free_casts"]) - 1
	fighter.race_state.erase("instant_cast")
	var arch = params(fighter, "grand_archmage")
	if arch != null and n % maxi(1, int(arch["every_n"])) == 0 and cast["stats"].has("damage") and str(cast["kind"]) != "stance":
		cast["copy_mul"] = float(arch["copy_mul"])
		sim.events.append({"type": "tree_archmage", "player": id, "skill": str(cast["skill"])})


## Grand Archmage's free copy of release `index` (same target/aim, damage x copy_mul, no skill_cast event).
static func release_copy(sim, id: int, fighter, cast: Dictionary, index: int) -> void:
	var copy: Dictionary = cast.duplicate()
	copy.erase("copy_mul")
	copy["stats"] = cast["stats"].duplicate(true)
	copy["stats"]["damage"] = float(copy["stats"]["damage"]) * float(cast["copy_mul"])
	load(SKILLS)._release(sim, id, fighter, copy, -1 - index)


# ---------------------------------------------------------------- runes

## Overcharge: the count at which runes discharge (max + over_max).
static func charges_top(fighter, top: int) -> int:
	var p = params(fighter, "overcharge")
	return top if p == null else top + int(p["over_max"])


## A discharge happened (runes spent): Resonance, Glyph Arrows.
static func on_discharge(sim, id: int, context: Dictionary) -> void:
	var fighter = sim.fighters[id]
	var res = params(fighter, "resonance")
	if res != null and int(fighter.race_state.get("resonance_tick", -1)) != sim.tick_count:
		fighter.race_state["resonance_tick"] = sim.tick_count  # one gift per tick: two Resonance cards never loop
		for other in _ally_ids(sim, id):
			if other != id and str(sim.fighters[other].race_state.get("race", "")) == "runeborn":
				sim.fighters[other].race_state["resonance_tick"] = sim.tick_count
				load(RACE).add_runes(sim, other, int(res["runes"]), "resonance")
	var glyph = params(fighter, "glyph_arrows")
	if glyph != null:
		var center: Vector3 = sim.bodies[id].position
		var target := int(context.get("target", -1))
		if sim.bodies.has(target):
			center = sim.bodies[target].position
		var status := mark_status(fighter)
		for e in _enemy_ids(sim, id):
			if _flat(sim.bodies[e].position - center).length() <= float(glyph["radius"]):
				Effects.apply(id, fighter, e, sim.fighters[e], {"id": status, "chance": 100.0, "duration": 0}, sim.combat, sim.rng, sim.events)


# ---------------------------------------------------------------- per tick

static func step(sim, id: int, fighter, events: Array) -> void:
	_death_save_tick(sim, id, fighter, events)
	var mech: Dictionary = TreeEffects.mechanics(fighter)
	if mech.is_empty() or not fighter.is_alive():
		return
	var rs: Dictionary = fighter.race_state
	var skill_hit_by: Dictionary = {}  # skill -> {target: true} hit by this card this tick
	var crit_skills: Dictionary = {}
	for event in events:
		var kind := str(event.get("type", ""))
		match kind:
			"skill_hit":
				if int(event.get("attacker", -1)) == id and str(event.get("effect", "")) == "hit":
					var by: Dictionary = skill_hit_by.get(str(event["skill"]), {})
					by[int(event["target"])] = true
					skill_hit_by[str(event["skill"])] = by
					if bool(event.get("crit", false)):
						crit_skills[str(event["skill"])] = true
			"skill_cast":
				if int(event.get("player", -1)) == id:
					rs["last_cast_tick"] = sim.tick_count
					if mech.has("bulwark_haste_on_skill"):
						_bulwark_haste(sim, fighter)
			"dodge_started":
				if int(event.get("player", -1)) == id and mech.has("skirmisher"):
					rs["instant_cast"] = true
			"ultimate_cast":
				if int(event.get("player", -1)) == id:
					if mech.has("free_casts_after_ult"):
						rs["free_casts"] = int(mech["free_casts_after_ult"]["casts"])
					if mech.has("mastery_overflow"):
						_overflow_start(sim, fighter, mech["mastery_overflow"])
			"race_ult_resolved":
				if int(event.get("player", -1)) == id and mech.has("twin_ultimate"):
					rs["twin_at"] = sim.tick_count + int(mech["twin_ultimate"]["delay_ticks"])
			"killed":
				if int(event.get("by", -1)) == id and sim.fighters.has(int(event["target"])) and sim.fighters[int(event["target"])].team != fighter.team:
					_on_kill(sim, id, fighter, int(event["target"]), events, mech)
			"race_heal":
				if int(event.get("player", -1)) == id and not bool(event.get("kin", false)):
					_on_heal(sim, id, fighter, event, mech)
			"race_shield":
				if int(event.get("player", -1)) == id and mech.has("warding_sigil"):
					var watch: Dictionary = rs.get("sigil", {})
					watch[str(event["target"])] = true
					rs["sigil"] = watch
			"race_proc":
				if int(event.get("player", -1)) == id and str(event.get("source", "")) == "passive":
					_on_passive_proc(sim, id, fighter, event, events, mech)
	var heavy := heavy_targets(events, id)
	if heavy > 0:
		_on_heavy(sim, id, fighter, heavy, mech)
	if mech.has("skill_crit_refresh"):
		for skill in crit_skills:
			_cut_cooldown(sim, fighter, str(skill), float(mech["skill_crit_refresh"]["seconds"]))
	if mech.has("grand_runeweaver"):
		for skill in skill_hit_by:
			if skill_hit_by[skill].size() >= int(mech["grand_runeweaver"]["min_targets"]):
				load(RACE).add_runes(sim, id, 1, "grand_runeweaver")
				break
	_timers(sim, id, fighter, mech)


## Enemies this card's heavy swings / heavy skills hit this tick (the most of one swing).
static func heavy_targets(events: Array, id: int) -> int:
	var hit := {}
	var most := 0
	for event in events:
		var kind := str(event.get("type", ""))
		if kind == "hit" and int(event.get("attacker", -1)) == id and str(event.get("move", "")).contains("heavy"):
			hit[int(event["target"])] = true
		elif kind == "skill_heavy" and int(event.get("player", -1)) == id:
			most = maxi(most, int(event.get("targets", 0)))
	return maxi(most, hit.size())


static func _on_heavy(sim, id: int, fighter, n: int, mech: Dictionary) -> void:
	var rs: Dictionary = fighter.race_state
	if mech.has("momentum") and n >= int(mech["momentum"]["min_targets"]):
		rs["momentum"] = true
	if mech.has("refresh_shortest_on_heavy"):
		var p: Dictionary = mech["refresh_shortest_on_heavy"]
		if n >= int(p["min_targets"]) and (int(rs.get("perfect_form", -1)) < 0 or sim.tick_count - int(rs["perfect_form"]) >= int(p["cooldown_ticks"])):
			var cd: Dictionary = fighter.skill_state.get("cd", {})
			var best := ""
			var best_left := INF
			for skill in cd:
				var left: int = int(cd[skill]) - sim.tick_count
				if left > 0 and left < best_left:
					best_left = left
					best = str(skill)
			if not best.is_empty():
				cd[best] = sim.tick_count
				rs["perfect_form"] = sim.tick_count
				sim.events.append({"type": "race_skill_refresh", "player": id, "target": id, "seconds": best_left / 60.0, "skill": best})
	if mech.has("bark_and_blade") and n >= 2 and fighter.effects.has("regen"):
		var p: Dictionary = mech["bark_and_blade"]
		var fraction := minf(float(p["per_target"]) * float(n - 1), float(p["cap"]))
		load(RACE).run_action(sim, id, {"action": "heal", "target": "ally_most_hurt", "fraction_of": "max_hp", "fraction": fraction}, {})


static func _on_kill(sim, id: int, fighter, dead: int, events: Array, mech: Dictionary) -> void:
	if mech.has("extend_buffs_on_kill"):
		var p: Dictionary = mech["extend_buffs_on_kill"]
		for status in p["statuses"]:
			if fighter.effects.has(str(status)):
				fighter.effects[str(status)]["left"] = int(fighter.effects[str(status)]["left"]) + int(p["ticks"])
	var by_skill: bool = events.any(func(e): return str(e.get("type", "")) == "skill_hit" and int(e.get("attacker", -1)) == id and int(e.get("target", -1)) == dead)
	if not by_skill:
		return
	if mech.has("blood_sorcery"):
		load(RACE).run_action(sim, id, {"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": float(mech["blood_sorcery"]["heal"])}, {})
	if mech.has("trophy_volley"):
		var p: Dictionary = mech["trophy_volley"]
		var key := int(fighter.race_state.get("last_cast_tick", -1))
		var fired: Array = fighter.race_state.get("trophy", [key, 0])
		if int(fired[0]) != key:
			fired = [key, 0]
		if int(fired[1]) < int(p["per_cast"]):
			fired[1] = int(fired[1]) + 1
			fighter.race_state["trophy"] = fired
			load(RACE).run_action(sim, id, {"action": "burst", "target": "enemy_lowest_hp_pct", "cast_range": 12.0, "pick": "nearest", "radius": 0.6, "atk_mul": float(p["atk_mul"])}, {})
			sim.events.append({"type": "tree_trophy_arrow", "player": id})


static func _on_heal(sim, id: int, fighter, event: Dictionary, mech: Dictionary) -> void:
	var target_id := int(event["target"])
	var target = sim.fighters.get(target_id)
	if target == null:
		return
	var amount := float(event.get("amount", 0.0))
	if mech.has("cleansing_dew") and target.hp - amount < target.max_hp() * float(mech["cleansing_dew"]["below"]):
		load(RACE).run_action(sim, id, {"action": "cleanse", "target": "target", "statuses": mech["cleansing_dew"]["statuses"]}, {"target": target_id})
		if target_id == id:  # "target" never picks the card itself: cleanse it directly
			TreeEffects.run_action(sim, id, {"action": "cleanse", "target": "self", "statuses": mech["cleansing_dew"]["statuses"]}, {})
	if mech.has("kin_bond") and target_id != id:
		var back: float = minf(amount * float(mech["kin_bond"]["fraction"]) * fighter.heal_factor(), fighter.max_hp() - fighter.hp)
		if back > 0.0:
			fighter.hp += back
			sim.events.append({"type": "race_heal", "player": id, "target": id, "amount": back, "kin": true, "ultimate": false})


## A passive proc of this card: Moonwell Arrows (Moonlit Arrow roots a marked target), Grove Warden (Warden's Grove
## heals every ally in range while Bulwark is up).
static func _on_passive_proc(sim, id: int, fighter, event: Dictionary, events: Array, mech: Dictionary) -> void:
	var on := str(event.get("on", ""))
	if mech.has("moonwell_root") and on == "hit":
		var target := -1
		for e in events:
			if str(e.get("type", "")) == "hit" and int(e.get("attacker", -1)) == id:
				target = int(e["target"])
		if target >= 0 and sim.fighters[target].is_alive() and sim.fighters[target].effects.has(mark_status(fighter)) and _passive_on(fighter, "hit", "heal"):
			Effects.apply(id, fighter, target, sim.fighters[target], {"id": "shock", "chance": 100.0, "duration": int(mech["moonwell_root"]["root_ticks"])}, sim.combat, sim.rng, sim.events)
	if mech.has("grove_warden") and on == "guard_block" and bulwark_up(fighter, sim.tick_count):
		var heal: Dictionary = _passive_action(fighter, "guard_block", "heal")
		if heal.is_empty():
			return
		var healed := {}
		for e in events:
			if str(e.get("type", "")) == "race_heal" and int(e.get("player", -1)) == id:
				healed[int(e["target"])] = true
		var race = load(RACE)
		for ally in _ally_ids(sim, id):
			if healed.has(ally) or _flat(sim.bodies[ally].position - sim.bodies[id].position) .length() > float(mech["grove_warden"]["radius"]):
				continue
			var target = sim.fighters[ally]
			var amount: float = race._within_heal_cap(sim, target, race.heal_amount(heal, fighter, target, 0.0))
			var got: float = minf(amount, target.max_hp() - target.hp)
			if got > 0.0:
				target.hp += got
				sim.events.append({"type": "race_heal", "player": id, "target": ally, "amount": got, "ultimate": false, "kin": true})


static func _passive_on(fighter, on: String, action_kind: String) -> bool:
	return not _passive_action(fighter, on, action_kind).is_empty()


static func _passive_action(fighter, on: String, action_kind: String) -> Dictionary:
	for entry in fighter.race_state.get("effects", []):
		if str(entry["src"]) == "passive" and str(entry["effect"]["type"]) == "trigger" and str(entry["effect"].get("on", "")) == on:
			for action in entry["effect"].get("actions", []):
				if str(action.get("action", "")) == action_kind:
					return action
	return {}


## Drillmaster's Wall: each skill cast halves the remaining Bulwark cycle.
static func _bulwark_haste(sim, fighter) -> void:
	var effects: Array = fighter.race_state["effects"]
	for index in effects.size():
		var effect: Dictionary = effects[index]["effect"]
		if str(effect["type"]) != "aggro":
			continue
		var fx: Dictionary = fighter.race_state["fx"].get(str(index), {})
		if fx.is_empty() or int(fx.get("last", -1)) < 0:
			continue
		var left: int = int(effect["every_ticks"]) - (sim.tick_count - int(fx["last"]))
		if left > 0:
			fx["last"] = int(fx["last"]) - left / 2


static func _cut_cooldown(sim, fighter, skill: String, seconds: float) -> void:
	var cd: Dictionary = fighter.skill_state.get("cd", {})
	if cd.has(skill) and int(cd[skill]) > sim.tick_count:
		cd[skill] = maxi(sim.tick_count, int(cd[skill]) - int(round(seconds * 60.0)))


# ---------------------------------------------------------------- Mastery Overflow

static func _overflow_start(sim, fighter, p: Dictionary) -> void:
	var rs: Dictionary = fighter.race_state
	if rs.has("overflow"):
		rs["overflow"]["until"] = sim.tick_count + int(p["ticks"])
		return
	var orig := {}
	var effects: Array = rs["effects"]
	for index in effects.size():
		if str(effects[index]["src"]) == "passive":
			orig[str(index)] = effects[index]["effect"]
			effects[index]["effect"] = TreeEffects.cell_mod_effect(effects[index]["effect"], {"scale": float(p["passive_mul"])})
	rs["overflow"] = {"until": sim.tick_count + int(p["ticks"]), "orig": orig}
	_rederive(fighter)


static func _overflow_end(fighter) -> void:
	var rs: Dictionary = fighter.race_state
	var orig: Dictionary = rs["overflow"]["orig"]
	for key in orig:
		rs["effects"][int(key)]["effect"] = orig[key]
	rs.erase("overflow")
	_rederive(fighter)


static func _rederive(fighter) -> void:
	var keep: Array = fighter.race_state.get("scaling", []).filter(func(e): return bool(e.get("death_save", false)))
	TreeEffects._rebuild_derived(fighter)
	fighter.race_state["scaling"] = fighter.race_state["scaling"] + keep


# ---------------------------------------------------------------- timers

static func _timers(sim, id: int, fighter, mech: Dictionary) -> void:
	var rs: Dictionary = fighter.race_state
	if rs.has("overflow") and sim.tick_count >= int(rs["overflow"]["until"]):
		_overflow_end(fighter)
	if int(rs.get("twin_at", -1)) >= 0 and sim.tick_count >= int(rs["twin_at"]):
		rs.erase("twin_at")
		_twin_echo(sim, id, fighter, mech["twin_ultimate"])
	if mech.has("world_tree"):
		_world_tree(sim, id, fighter, mech["world_tree"])
	if mech.has("blink_caster"):
		_blink(sim, id, fighter, mech["blink_caster"])
	if mech.has("warding_sigil"):
		_sigil_breaks(sim, id, fighter, mech["warding_sigil"])


## Twin Ultimate: the ultimate's actions again at `scale` of their numbers (ultimate context: no gauge; no echo of it).
static func _twin_echo(sim, id: int, fighter, p: Dictionary) -> void:
	var ult: Dictionary = fighter.race_state.get("ultimate", {})
	if ult.is_empty() or fighter.incapacitated:
		return
	var echo: Dictionary = TreeEffects.cell_mod_ultimate(ult, {"scale": float(p["scale"])})
	var ctx := {"ultimate": true, "damage": 0.0, "points": {}, "picked": {}, "echo": true}
	var did := 0
	for action in echo.get("actions", []):
		if load(RACE).run_action(sim, id, action, ctx):
			did += 1
	sim.events.append({"type": "tree_twin_ultimate", "player": id, "name": str(ult.get("name", "")), "did": did, "ultimate": true})


## World Tree: the first ally down this wave is revived at hp after delay_ticks while this card lives.
static func _world_tree(sim, id: int, fighter, p: Dictionary) -> void:
	var rs: Dictionary = fighter.race_state
	var wave := int(rs.get("wave", 0))
	var pending: Dictionary = rs.get("world_tree", {})
	if pending.is_empty() or int(pending.get("wave", 0)) != wave:
		if int(rs.get("world_tree_used", -1)) == wave:
			return
		var ids: Array = sim.fighters.keys()
		ids.sort()
		for other in ids:
			var f = sim.fighters[other]
			if other != id and f.team == fighter.team and f.state == Fighter.State.DOWNED and not f.eliminated:
				rs["world_tree"] = {"wave": wave, "target": other, "at": sim.tick_count + int(p["delay_ticks"])}
				rs["world_tree_used"] = wave
				return
		return
	if sim.tick_count < int(pending["at"]):
		return
	rs.erase("world_tree")
	if load(ULTS).revive(sim, id, int(pending["target"]), float(p["hp"])):
		sim.events.append({"type": "tree_world_tree", "player": id, "target": int(pending["target"])})


## Blink Caster: an enemy within trigger_radius -> blink `distance` m away from it and leave a free Repulse Nova.
static func _blink(sim, id: int, fighter, p: Dictionary) -> void:
	var rs: Dictionary = fighter.race_state
	if int(rs.get("blink_at", -1)) >= 0 and sim.tick_count - int(rs["blink_at"]) < int(p["cooldown_ticks"]):
		return
	if fighter.state != Fighter.State.IDLE or fighter.incapacitated or fighter.rooted or load(SKILLS).busy(fighter):
		return
	var at: Vector3 = sim.bodies[id].position
	var near := -1
	var near_d := float(p["trigger_radius"])
	for e in _enemy_ids(sim, id):
		var d := _flat(sim.bodies[e].position - at).length()
		if d <= near_d:
			near_d = d
			near = e
	if near < 0:
		return
	var away := _flat(at - sim.bodies[near].position)
	var dir := away.normalized() if away.length() > 0.01 else Vector2.LEFT
	var to := at + Vector3(dir.x, 0.0, dir.y) * float(p["distance"])
	to.x = clampf(to.x, -sim.world.half_width, sim.world.half_width)
	to.z = clampf(to.z, -sim.world.half_depth, sim.world.half_depth)
	var body = sim.bodies[id]
	var box := AABB(Vector3(to.x - SimBody.HALF_WIDTH, to.y + 0.05, to.z - SimBody.HALF_DEPTH), Vector3(SimBody.HALF_WIDTH * 2.0, body.height - 0.1, SimBody.HALF_DEPTH * 2.0))
	for solid in sim.world.solids:
		if box.intersects(solid):
			return  # no room behind: try again next tick
	rs["blink_at"] = sim.tick_count
	body.position = to
	body.knockback = Vector2.ZERO
	sim.events.append({"type": "tree_blink", "player": id, "from": at, "to": to})
	var skills = load(SKILLS)
	for skill in fighter.skill_state.get("skills", []):
		var data: Dictionary = preload("res://logic/class_skills/skill_data.gd").load_default().skill(str(skill))
		if str(data.get("kind", "")) == "circle":  # Repulse Nova: the card's self-centred ring (no cooldown spent)
			var stats: Dictionary = skills.cast_stats(fighter, str(skill))
			if not stats.has("error"):
				skills._circle(sim, id, at, float(stats["radius"]), stats)
				sim.events.append({"type": "tree_blink_nova", "player": id, "skill": str(skill), "pos": at, "radius": float(stats["radius"])})
			break


## Warding Sigil: a shield this card gave that broke (absorbed to 0, not timed out) shocks enemies near its owner.
static func _sigil_breaks(sim, id: int, fighter, p: Dictionary) -> void:
	var watch: Dictionary = fighter.race_state.get("sigil", {})
	for key in watch.keys():
		var target = sim.fighters.get(int(key))
		if target == null or not target.is_alive():
			watch.erase(key)
			continue
		if target.shield > 0.0:
			continue
		watch.erase(key)
		var ended: bool = sim.events.any(func(e): return str(e.get("type", "")) == "race_shield_end" and int(e.get("target", -1)) == int(key))
		if ended:
			continue
		var at: Vector3 = sim.bodies[int(key)].position
		for e in _enemy_ids(sim, id):
			if _flat(sim.bodies[e].position - at).length() <= float(p["radius"]):
				Effects.apply(id, fighter, e, sim.fighters[e], {"id": str(p["status"]), "chance": 100.0, "duration": 0}, sim.combat, sim.rng, sim.events)
		sim.events.append({"type": "tree_sigil_break", "player": id, "target": int(key), "pos": at, "radius": float(p["radius"])})


## Warding Sigil: extra ticks on this card's shields.
static func shield_ticks_add(fighter) -> int:
	var p = params(fighter, "warding_sigil")
	return 0 if p == null else int(p["ticks_add"])


## Momentum: true once after a qualifying heavy (the pilot brings the next heavy one swing earlier).
static func take_momentum(fighter) -> bool:
	if not bool(fighter.race_state.get("momentum", false)):
		return false
	fighter.race_state.erase("momentum")
	return true


# ---------------------------------------------------------------- chunk 2: events, per_target, pilot

## How many enemies the hit behind this trigger touched (per_target heals): an ultimate's own hit list, else the most
## enemies one heavy / skill_heavy of this card hit this tick, else the targets of this card's hits this tick (min 1).
static func targets_hit(sim, id: int, context: Dictionary) -> int:
	if context.get("hit") is Array and not (context["hit"] as Array).is_empty():
		return (context["hit"] as Array).size()
	if bool(context.get("ultimate", false)):
		var seen := {}
		for e in sim.events:
			if str(e.get("type", "")) == "race_burst_hit" and int(e.get("attacker", -1)) == id:
				seen[int(e["target"])] = true
		return maxi(1, seen.size())
	return maxi(1, heavy_targets(sim.events, id))


## A dodge is a kite when an enemy stands within the card's kite distance (pilot profile, tree pilot_mod).
## The dodge has moved the card one tick already, so one tick of dodge travel is allowed on top (dodge_speed / 60).
static func kiting(sim, id: int) -> bool:
	var fighter = sim.fighters[id]
	var reach := kite_distance(fighter, 0.0)
	if reach <= 0.0:
		return false
	reach += float(sim.combat.rules.get("dodge_speed", 0.0)) / 60.0
	var at: Vector3 = sim.bodies[id].position
	return _enemy_ids(sim, id).any(func(e): return _flat(sim.bodies[e].position - at).length() < reach)


## The class skill that is a kite step: data kind vault_shot.
static func kite_skill(skill: String) -> bool:
	return not skill.is_empty() and str(preload("res://logic/class_skills/skill_data.gd").load_default().skill(skill).get("kind", "")) == "vault_shot"


## The pilot's kite distance: the larger of the class pilot's and the tree pilot_mod's (Skirmisher 3 -> 5 m).
static func kite_distance(fighter, profile_value: float) -> float:
	var mod := float(TreeEffects.pilot_mods(fighter).get("kite_distance", 0.0)) if not fighter.race_state.is_empty() else 0.0
	var own := profile_value
	if own <= 0.0 and not fighter.race_state.is_empty():
		own = float(preload("res://logic/card_deck.gd").class_data(str(fighter.race_state.get("class", ""))).get("pilot", {}).get("kite_distance", 0.0))
	return maxf(own, mod)


## The skill hold rule's extra targets (pilot_mod hold_min_targets_add).
static func hold_add(fighter) -> int:
	return 0 if fighter.race_state.is_empty() else int(TreeEffects.pilot_mods(fighter).get("hold_min_targets_add", 0))


## pilot_mod cast_center densest (Remote Nova): a circle skill whose cast is remote is used when the densest point
## within its remote range holds the use rule's `min` enemies (+ hold_add). Returns {} or the choice, null = not this case.
static func remote_choice(sim, id: int, skill: String, use: Dictionary):
	var fighter = sim.fighters[id]
	if fighter.race_state.is_empty() or str(TreeEffects.pilot_mods(fighter).get("cast_center", "")) != "densest":
		return null
	var stats: Dictionary = load(SKILLS).cast_stats(fighter, skill)
	if stats.has("error") or str(stats.get("origin", "")) != "target":
		return null
	var need := 1
	for rule in use.get("any_of", []):
		need = maxi(need, int(rule.get("min", 1)))
	need += hold_add(fighter)
	var best: Dictionary = load(ULTS).densest_point(sim, id, float(stats.get("remote_range", 7.0)), float(stats.get("radius", 3.0)))
	if best["pos"] == null or int(best["count"]) < need:
		return {}
	return {"target": -1, "point": best["pos"]}


# ---------------------------------------------------------------- helpers

static func _ally_ids(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(o): return sim.fighters[o].team == team and sim.fighters[o].is_alive())
	out.sort()
	return out


static func _enemy_ids(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(o): return sim.fighters[o].team != team and sim.fighters[o].is_alive())
	out.sort()
	return out


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
