extends RefCounted
## Class skills v2 at fight time (design/gdd/class-skills.md 3.1-3.5, 4, 5, 6.1 E1-E16). Pure rules, static, no nodes.
## Every bit of state lives in Fighter.skill_state (a plain dictionary, so checkpoints, rollback and the wire carry it
## with no extra code):
##   skills [4 ids], cd {id: tick the skill is ready again}, cast {} (the cast running now), stance {}, trance {},
##   veil {} (on the veiled ally), link {} (on the linked ally: who takes the share), counters [] (attackers to answer),
##   jobs [] (orbs in flight, delayed hits), shots (Rapid Fire arrows fired).
## A cast (cast()): the cooldown and stamina are spent at once (GDD 3.1 rule 6: a lost cast still costs its cooldown);
## the caster cannot act until the clip window ends (GameSim blanks its input, busy()); stun/sleep or death before a
## release loses the rest of the cast. Travel moves the body only inside the clip's travel frames (rule 9, D10).
## Damage = ATK x fraction x bonuses x crit, then the target's DEF rule (4.1). Events: skill_cast once per cast,
## skill_hit once per enemy per hit (the race engine and the gauge read them), skill_heavy once for a heavy-hit skill
## (race event heavy_hit, 5.2), class_skill_* for the client.

const SkillData := preload("res://logic/class_skills/skill_data.gd")
const Fighter := preload("res://logic/fighter.gd")
const Effects := preload("res://logic/effects.gd")
const COMBAT := "res://logic/combat.gd"  ## loaded at call time (combat.gd preloads this file)
const RaceData := preload("res://logic/race_data.gd")
const SimBody := preload("res://logic/sim_body.gd")
const TREE := "res://logic/skill_tree_effects.gd"
const RACE := "res://logic/race_passives.gd"
const ATTACKED_RADIUS := 3.0  ## an enemy this close to an ally counts as attacking it (GDD 3.7 "being attacked")


# ---------------------------------------------------------------- setup and queries

## Gives fighter `id` its class's 4 skills (data/class_skills/class_skills.json classes). All skills start ready.
static func attach(sim, id: int, class_id: String) -> bool:
	var ids: Array = SkillData.load_default().class_skills(class_id)
	if ids.is_empty() or not sim.fighters.has(id):
		return false
	var state: Dictionary = sim.fighters[id].skill_state
	state["class"] = class_id
	state["skills"] = ids.duplicate()
	state["cd"] = {}
	for skill in ids:
		state["cd"][skill] = sim.tick_count
	for key in ["cast", "stance", "trance"]:
		state[key] = {}
	state["counters"] = []
	state["jobs"] = []
	return true


static func has_skills(fighter) -> bool:
	return not fighter.skill_state.get("skills", []).is_empty()


## True while the fighter is inside a class-skill clip window (it cannot move, attack or start another skill).
static func busy(fighter) -> bool:
	return not fighter.skill_state.get("cast", {}).is_empty()


## Hits do not stagger a caster mid-skill, in Iron Guard or in Battle Trance (GDD 3.2 S2, 3.3 G4).
static func armored(fighter, tick: int) -> bool:
	var s: Dictionary = fighter.skill_state
	if s.is_empty():
		return false
	return not s.get("cast", {}).is_empty() or int(s.get("trance", {}).get("until", -1)) > tick


## Seconds until `skill` is ready (0 = ready).
static func cooldown_left(sim, fighter, skill: String) -> float:
	return maxf(0.0, float(int(fighter.skill_state.get("cd", {}).get(skill, 0)) - sim.tick_count) / SkillData.TICKS)


## Battle Trance's heavy_every override (E8) for the pilot, or 0.
static func heavy_every(sim, fighter) -> int:
	var trance: Dictionary = fighter.skill_state.get("trance", {})
	return int(trance.get("heavy_every", 0)) if int(trance.get("until", -1)) > sim.tick_count else 0


## skill_refresh (races 3.6, formula 4.4) on a card's 4 skills: remaining' = max(0, remaining x (1 - fraction) - seconds).
## Returns the seconds cut in total.
static func refresh_cooldowns(sim, id: int, fraction: float, seconds: float) -> float:
	var cd: Dictionary = sim.fighters[id].skill_state.get("cd", {})
	var cut := 0.0
	for skill in cd:
		var remaining := maxf(0.0, float(int(cd[skill]) - sim.tick_count) / SkillData.TICKS)
		var after := maxf(0.0, remaining * (1.0 - fraction) - seconds)
		if after < remaining:
			cut += remaining - after
			cd[skill] = sim.tick_count + SkillData.ticks(after)
	return cut


## The cast's numbers: the skill's stats -> tree skill_upgrade -> race skill_mod (skill-tree.md 3.6, races 4.4).
## {"error": reason} when the race refuses (Blood Rite below its HP floor).
static func cast_stats(fighter, skill: String) -> Dictionary:
	var data: Dictionary = SkillData.load_default().skill(skill)
	var stats: Dictionary = data.get("stats", {}).duplicate(true)
	stats["skill_id"] = skill
	stats["crit_chance"] = 0.0
	stats["statuses"] = []
	load(TREE).upgrade_skill(fighter, stats)
	var refusal: String = load(RACE).modify_skill_stats(fighter, stats)
	if not refusal.is_empty():
		return {"error": refusal}
	return stats


# ---------------------------------------------------------------- cast

## Starts `skill` for fighter `id`. `choice`: {"target": enemy or ally id, "point": Vector3} from the pilot's use rule
## (logic/class_skills/use_rules.gd). Returns "" or why it did not start (nothing is spent then).
static func cast(sim, id: int, skill: String, choice: Dictionary = {}) -> String:
	var fighter = sim.fighters.get(id)
	if fighter == null or not fighter.skill_state.get("skills", []).has(skill):
		return "invalid_skill"
	if not fighter.is_alive() or fighter.incapacitated or fighter.state != Fighter.State.IDLE or busy(fighter):
		return "cannot_cast"
	if int(fighter.skill_state["cd"].get(skill, 0)) > sim.tick_count:
		return "cooldown"
	var data: Dictionary = SkillData.load_default().skill(skill)
	var cost := float(data.get("stamina", 0.0))
	if fighter.energy < cost:
		return "not_enough_stamina"
	var stats := cast_stats(fighter, skill)
	if stats.has("error"):
		return str(stats["error"])
	var kind := str(data["kind"])
	var at: Vector3 = sim.bodies[id].position
	var target := int(choice.get("target", -1))
	var cast := {"skill": skill, "kind": kind, "cast_time": float(stats.get("cast_time", 1.0)), "start": sim.tick_count, "stats": stats, "target": target, "done": 0, "aim": at + Vector3.RIGHT}
	var timing: Dictionary = scaled_timing(data["timing"], float(stats.get("cast_time", 1.0)))
	if str(stats.get("origin", "")) == "target" and kind == "circle":  # Remote Nova (tree behavior remote): at the densest point
		var best: Dictionary = load("res://logic/race_ultimates.gd").densest_point(sim, id, float(stats.get("remote_range", 7.0)), float(stats.get("radius", 3.0)))
		if best["pos"] == null:
			return "no_target"
		choice = {"target": -1, "point": best["pos"]}
		target = -1
		kind = "remote_circle"
		cast["kind"] = kind
		cast["target"] = -1
	match kind:
		"stance", "self_buff":
			pass
		"ally_leap", "ally_buff":
			if not _ally_ok(sim, id, target):
				return "no_target"
		"leap_slam", "delayed_circle", "remote_circle":
			if not choice.get("point") is Vector3:
				return "no_target"
			cast["point"] = choice["point"]
		_:
			if kind in ["circle", "pull_circle", "arc"] and target < 0:
				target = _nearest_enemy(sim, id, INF)
				cast["target"] = target
			if not kind in ["circle", "pull_circle"] and not _enemy_ok(sim, id, target):
				return "no_target"
	if target >= 0 and sim.bodies.has(target):
		cast["aim"] = sim.bodies[target].position
	elif cast.has("point"):
		cast["aim"] = cast["point"]
	_face(sim, id, cast["aim"])
	cast["travel"] = _plan_travel(sim, id, kind, cast, timing)
	var length: float = float(timing["end"])
	if kind == "stance":
		length = float(stats.get("duration", 3.0)) + float(timing.get("exit", 0.0))
		fighter.skill_state["stance"] = {"until": sim.tick_count + SkillData.ticks(float(stats.get("duration", 3.0))), "taken_mul": float(stats.get("taken_mul", 0.5)),
			"counter": float(stats.get("counter", 0.5)), "left": int(stats.get("max_counters", 2)), "icd": SkillData.ticks(float(stats.get("counter_icd", 0.3))), "next": 0,
			"fortify": float(stats.get("counter_fortify", 0.0)), "reflect": float(stats.get("thorns", 0.0)), "stats": stats}
	cast["end"] = sim.tick_count + SkillData.ticks(length)
	cast["releases"] = _release_ticks(sim, kind, stats, timing)
	cast["pull"] = (timing["pull"] as Array).map(func(t): return sim.tick_count + SkillData.ticks(float(t)))
	fighter.skill_state["cast"] = cast
	fighter.skill_state["now"] = sim.tick_count
	fighter.skill_state["cd"][skill] = sim.tick_count + SkillData.ticks(float(stats["cooldown"]))
	fighter.energy -= cost
	fighter.energy_wait = int(sim.combat.rules.get("energy_regen_delay_ticks", 0))
	if load(RACE).pay_skill_hp(sim, id, fighter) > 0.0:
		pass  # Blood Rite (races 3.4)
	preload("res://logic/relic_effects.gd").skill_cast(fighter)
	sim.events.append({"type": "class_skill_start", "player": id, "skill": skill, "start": sim.tick_count, "end": cast["end"], "target": target,
		"aim": cast["aim"], "vfx": str(data.get("vfx", ""))})
	return ""


## Release ticks: the clip's release times; Rapid Fire adds arrows past the 4 clip releases at the same spacing.
## The skill's clip timing with every time x `mul` (a tree cast_time mod); the client plays the clip at speed / mul.
static func scaled_timing(timing: Dictionary, mul: float) -> Dictionary:
	if is_equal_approx(mul, 1.0):
		return timing
	var out: Dictionary = timing.duplicate(true)
	for key in ["releases", "travel", "pull"]:
		out[key] = (timing[key] as Array).map(func(t): return float(t) * mul)
	for key in ["end", "exit", "counter_release", "counter_length"]:
		if timing.has(key):
			out[key] = float(timing[key]) * mul
	return out


static func _release_ticks(sim, kind: String, stats: Dictionary, timing: Dictionary) -> Array:
	var out: Array = (timing["releases"] as Array).map(func(t): return sim.tick_count + SkillData.ticks(float(t)))
	if kind == "stance":
		return [sim.tick_count]
	if kind == "volley":
		var arrows := int(stats.get("arrows", out.size()))
		var gap: int = (int(out[1]) - int(out[0])) if out.size() > 1 else 15
		while out.size() < arrows:
			out.append(int(out[-1]) + gap)
		out = out.slice(0, arrows)
	return out


## The travel of this cast: {"from_tick", "to_tick", "from" Vector3, "to" Vector3} or {} (rule 9).
static func _plan_travel(sim, id: int, kind: String, cast: Dictionary, timing: Dictionary) -> Dictionary:
	var span: Array = timing.get("travel", [])
	if span.size() != 2:
		return {}
	var stats: Dictionary = cast["stats"]
	var at: Vector3 = sim.bodies[id].position
	var to := at
	match kind:
		"dash_strike":
			var target_pos: Vector3 = sim.bodies[int(cast["target"])].position
			var dir := _flat_dir(target_pos - at)
			var length := clampf(_flat(target_pos - at).length() - float(stats.get("stop_short", 1.0)), 0.0, float(stats.get("dash_max", 6.0)))
			# stops on the first enemy in the path (it becomes the one hit)
			for e in _enemy_ids(sim, id):
				var p: Vector3 = sim.bodies[e].position
				var along := (_flat(p - at)).dot(Vector2(dir.x, dir.z))
				var side := absf((_flat(p - at)).cross(Vector2(dir.x, dir.z)))
				if e != int(cast["target"]) and side < SimBody.HALF_WIDTH * 2.0 and along > 0.0 and along - float(stats.get("stop_short", 1.0)) < length:
					length = maxf(0.0, along - float(stats.get("stop_short", 1.0)))
					cast["target"] = e
			to = at + dir * length
		"ally_leap":
			var ally_pos: Vector3 = sim.bodies[int(cast["target"])].position
			var dir := _flat_dir(ally_pos - at)
			to = at + dir * clampf(_flat(ally_pos - at).length() - float(stats.get("stop_short", 1.0)), 0.0, float(stats.get("range", 8.0)))
		"leap_slam":
			var point: Vector3 = cast["point"]
			var dir := _flat_dir(point - at)
			to = at + dir * minf(_flat(point - at).length(), float(stats.get("range", 7.0)))
		"vault_shot":
			var from_e := int(cast["target"])
			var away := _flat_dir(at - sim.bodies[from_e].position)
			if away == Vector3.ZERO:
				away = Vector3.LEFT
			to = at + away * float(stats.get("distance", 4.0))
		"circle", "arc", "pull_circle":
			var dir := _flat_dir(Vector3(cast["aim"]) - at)
			to = at + dir * float(stats.get("hop", stats.get("step", 0.0)))
	to.y = at.y
	return {"from_tick": sim.tick_count + SkillData.ticks(float(span[0])), "to_tick": sim.tick_count + SkillData.ticks(float(span[1])), "from": at, "to": to}


# ---------------------------------------------------------------- per tick

## One authoritative tick for every fighter with class skills: travel, releases, counters, jobs, buff ends, views.
## GameSim calls it after the hits of the tick, before the race engine reads the events.
static func step(sim) -> void:
	var ids: Array = sim.fighters.keys()
	ids.sort()
	for id in ids:
		var fighter = sim.fighters[id]
		if fighter.skill_state.is_empty():
			continue
		fighter.skill_state["now"] = sim.tick_count + 1  # the tick Combat.apply_hit runs next (stance/veil clocks)
		_expire(sim, id, fighter)
		if fighter.skill_state.has("skills"):
			_run_cast(sim, id, fighter)
			_run_jobs(sim, id, fighter)
		_run_counters(sim, id, fighter)
		publish_view(sim, id, fighter)


static func _expire(sim, id: int, fighter) -> void:
	var s: Dictionary = fighter.skill_state
	for key in ["veil", "link"]:
		if s.has(key) and int(s[key].get("until", -1)) <= sim.tick_count:
			s.erase(key)
			sim.events.append({"type": "class_skill_end", "player": id, "what": key})
	if s.has("link"):
		var by := int(s["link"]["by"])
		var caster = sim.fighters.get(by)
		if caster == null or not caster.is_alive() or not fighter.is_alive() or _flat(sim.bodies[by].position - sim.bodies[id].position).length() > float(s["link"]["break"]):
			s.erase("link")  # 3.2 S3: the link breaks past 10 m or when the tank goes down
			sim.events.append({"type": "class_skill_end", "player": id, "what": "link"})
	if s.has("stance") and not s["stance"].is_empty() and int(s["stance"]["until"]) <= sim.tick_count:
		s["stance"] = {}
	if s.has("trance") and not s["trance"].is_empty() and int(s["trance"]["until"]) <= sim.tick_count:
		s["trance"] = {}


static func _run_cast(sim, id: int, fighter) -> void:
	var cast: Dictionary = fighter.skill_state["cast"]
	if cast.is_empty():
		return
	var releases: Array = cast["releases"]
	var pending := int(cast["done"]) < releases.size()
	if not fighter.is_alive() or fighter.incapacitated:
		# 3.1 rule 6: lost before a release; after it only the recovery ends early (5.3: the client plays hurt)
		fighter.skill_state["cast"] = {}
		if str(cast["kind"]) == "stance":
			fighter.skill_state["stance"] = {}
		sim.events.append({"type": "class_skill_lost" if pending else "class_skill_cut", "player": id, "skill": str(cast["skill"])})
		return
	_travel(sim, id, cast)
	for t in cast["pull"]:
		if int(t) == sim.tick_count:
			var st: Dictionary = cast["stats"]
			pull(sim, id, sim.bodies[id].position, float(st.get("pull_range", 5.0)), float(st.get("pull", 2.0)), float(st.get("pull_min", 1.0)))
	while int(cast["done"]) < releases.size() and int(releases[int(cast["done"])]) <= sim.tick_count:
		var index := int(cast["done"])
		cast["done"] = index + 1
		_release(sim, id, fighter, cast, index)
		if fighter.skill_state["cast"].is_empty():
			return
	if sim.tick_count >= int(cast["end"]):
		fighter.skill_state["cast"] = {}
		sim.events.append({"type": "class_skill_end", "player": id, "skill": str(cast["skill"])})


## Moves the body linearly from `from` to `to` over the travel frames, stopping at walls/stage edges (5.1).
static func _travel(sim, id: int, cast: Dictionary) -> void:
	var travel: Dictionary = cast.get("travel", {})
	if travel.is_empty() or bool(travel.get("stopped", false)):
		return
	var t0 := int(travel["from_tick"])
	var t1 := int(travel["to_tick"])
	if sim.tick_count < t0 or sim.tick_count >= t1 + 1:
		return
	var fighter = sim.fighters[id]
	if str(SkillData.load_default().skill(str(cast["skill"])).get("motion", {}).get("invulnerable", "")) == "travel":
		fighter.invulnerable_left = maxi(fighter.invulnerable_left, 2)
	var f := clampf(float(sim.tick_count - t0 + 1) / float(maxi(1, t1 - t0 + 1)), 0.0, 1.0)
	var body = sim.bodies[id]
	var next: Vector3 = Vector3(travel["from"]).lerp(Vector3(travel["to"]), f)
	next.y = body.position.y
	next.x = clampf(next.x, -sim.world.half_width, sim.world.half_width)
	next.z = clampf(next.z, -sim.world.half_depth, sim.world.half_depth)
	var box := AABB(Vector3(next.x - SimBody.HALF_WIDTH, next.y + 0.05, next.z - SimBody.HALF_DEPTH), Vector3(SimBody.HALF_WIDTH * 2.0, body.height - 0.1, SimBody.HALF_DEPTH * 2.0))
	for solid in sim.world.solids:
		if box.intersects(solid):
			travel["stopped"] = true  # blocked: the effect still fires where it stopped
			return
	body.position = next
	body.knockback = Vector2.ZERO


static func _release(sim, id: int, fighter, cast: Dictionary, index: int) -> void:
	var stats: Dictionary = cast["stats"]
	var skill := str(cast["skill"])
	var at: Vector3 = sim.bodies[id].position
	if index == 0:
		sim.events.append({"type": "skill_cast", "player": id, "skill": skill, "class_skill": true, "pos": at, "aim": cast["aim"]})
	sim.events.append({"type": "class_skill_release", "player": id, "skill": skill, "index": index, "pos": at, "aim": cast["aim"],
		"vfx": str(SkillData.load_default().skill(skill).get("vfx", ""))})
	var target := int(cast["target"])
	match str(cast["kind"]):
		"dash_strike":
			if _enemy_ok(sim, id, target) and _flat(sim.bodies[target].position - at).length() <= float(stats.get("reach", 2.0)):
				_hit(sim, id, target, float(stats["damage"]), stats, {"stun": stats.get("stun", 0.0)})
				_push(sim, id, target, float(stats.get("knockback", 0.0)))
				if float(stats.get("repeat", 0.0)) > 0.0:
					_add_job(fighter, {"kind": "hit", "at": sim.tick_count + 15, "target": target, "frac": float(stats["damage"]) * float(stats.get("repeat_damage_mul", 0.5)), "stats": stats})
			if float(stats.get("aggro", 0.0)) > 0.0:
				load(RACE).pulse_aggro(sim, id, float(stats.get("aggro_radius", 3.0)), SkillData.ticks(float(stats["aggro"])))
		"stance":
			pass
		"ally_leap":
			load(RACE).pulse_aggro(sim, id, float(stats.get("aggro_radius", 3.0)), SkillData.ticks(float(stats.get("aggro", 2.0))))
			var ally = sim.fighters.get(target)
			if ally != null and ally.is_alive() and _flat(sim.bodies[target].position - at).length() <= float(stats.get("link_break", 10.0)):
				ally.skill_state["link"] = {"by": id, "frac": float(stats.get("link", 0.4)), "until": sim.tick_count + SkillData.ticks(float(stats.get("link_duration", 6.0))),
					"break": float(stats.get("link_break", 10.0)), "reflect": float(stats.get("link_reflect", 0.0))}
				sim.events.append({"type": "class_skill_link", "player": id, "target": target, "until": ally.skill_state["link"]["until"]})
		"circle":
			_circle(sim, id, at, float(stats["radius"]), stats)
		"remote_circle":
			_circle(sim, id, Vector3(cast["point"]), float(stats["radius"]), stats)
		"pull_circle":
			_circle(sim, id, at, float(stats["radius"]), stats)
		"arc":
			_arc(sim, id, at, Vector3(cast["aim"]), stats)
		"leap_slam":
			if float(stats.get("pre_pull", 0.0)) > 0.0:
				pull(sim, id, at, float(stats.get("pre_pull_radius", 4.0)), float(stats["pre_pull"]), 1.0)
			_circle(sim, id, at, float(stats["radius"]), stats)
			if float(stats.get("aftershock", 0.0)) > 0.0:
				_add_job(fighter, {"kind": "circle", "at": sim.tick_count + 30, "pos": at, "radius": float(stats["radius"]), "frac": float(stats["damage"]) * float(stats["aftershock"]), "stats": stats})
		"self_buff":
			var ticks := SkillData.ticks(float(stats.get("duration", 6.0)))
			Effects.apply(id, fighter, id, fighter, {"id": "haste", "chance": 100.0, "duration": ticks}, sim.combat, sim.rng, sim.events)
			fighter.skill_state["trance"] = {"until": sim.tick_count + ticks, "heavy_every": int(stats.get("heavy_every", 2)), "reflect": float(stats.get("thorns", 0.0))}
		"shot":
			if _enemy_ok(sim, id, target) and _flat(sim.bodies[target].position - at).length() <= float(stats.get("range", 12.0)) + 0.5:
				var extra := {}
				for key in ["shock", "stun", "slow", "weaken"]:
					if float(stats.get(key, 0.0)) > 0.0:
						extra[key] = stats[key]
				var dir := _flat_dir(sim.bodies[target].position - at)
				var struck: Array = [target]
				_hit(sim, id, target, float(stats["damage"]), stats, extra)
				if int(stats.get("pierce", 0)) > 0:  # Marked Line / Through Pin: the arrow goes on through enemies on its line
					for e in line_hits(sim, id, at, dir, float(stats.get("range", 12.0)), struck).slice(0, int(stats["pierce"])):
						struck.append(e)
						_hit(sim, id, e, float(stats["damage"]), stats, extra)
				for k in int(stats.get("projectile_count", 0)):  # Split Volley: extra arrows in a +-spread cone
					var side := 1.0 if k % 2 == 0 else -1.0
					var angle := deg_to_rad(float(stats.get("spread_deg", 15.0))) * side * float(k / 2 + 1)
					var hit_list := line_hits(sim, id, at, dir.rotated(Vector3.UP, angle), float(stats.get("range", 12.0)), [])
					if not hit_list.is_empty():
						_hit(sim, id, int(hit_list[0]), float(stats["damage"]), stats, extra)
		"volley":
			var range_m := float(stats.get("range", 12.0))
			if not _enemy_ok(sim, id, target) or _flat(sim.bodies[target].position - at).length() > range_m + 0.5:
				target = shot_target(sim, id, range_m, float(stats.get("marked_first", 0.0)) > 0.0)  # 5.1: the next pilot target within 12 m, else lost
				cast["target"] = target
			if target >= 0 and float(stats.get("alternate", 0.0)) > 0.0 and index % 2 == 1:  # Spread Fire: every other arrow on the next nearest
				var other := _nearest_to(sim, id, sim.bodies[target].position, range_m, [target])
				if other >= 0:
					target = other
			if target >= 0:
				var last: bool = index == cast["releases"].size() - 1
				_hit(sim, id, target, float(stats["damage"]), stats, {"stun": stats.get("last_stun", 0.0)} if last else {})
		"vault_shot":
			if float(stats.get("smoke_radius", 0.0)) > 0.0 and not cast.get("travel", {}).is_empty():  # Smoke Vault: one-shot slow at the take-off spot
				var spot: Vector3 = cast["travel"]["from"]
				for e in _enemy_ids(sim, id).filter(func(e): return _flat(sim.bodies[e].position - spot).length() <= float(stats["smoke_radius"])):
					Effects.apply(id, fighter, e, sim.fighters[e], {"id": "slow", "chance": 100.0, "duration": SkillData.ticks(float(stats.get("smoke_slow", 2.0)))}, sim.combat, sim.rng, sim.events)
			if _enemy_ok(sim, id, target) and _flat(sim.bodies[target].position - at).length() <= float(stats.get("range", 12.0)):
				_hit(sim, id, target, float(stats["damage"]), stats, {"slow": stats.get("slow", 0.0)})
		"orb":
			var count := maxi(1, int(stats.get("count", 1)))
			var aim_dir := _flat_dir(Vector3(cast["aim"]) - at)
			if aim_dir == Vector3.ZERO:
				aim_dir = Vector3.RIGHT
			for k in count:
				var angle := deg_to_rad(float(stats.get("spread_deg", 15.0))) * (float(k) - float(count - 1) * 0.5)
				_add_orb(sim, fighter, at, aim_dir.rotated(Vector3.UP, angle), float(stats["damage"]), stats, 0)
			if float(stats.get("repeat", 0.0)) > 0.0:
				_add_orb(sim, fighter, at, aim_dir, float(stats["damage"]) * float(stats.get("repeat_damage_mul", 0.5)), stats, SkillData.ticks(0.4))
		"delayed_circle":
			var point: Vector3 = cast["point"]
			var delay := SkillData.ticks(float(stats.get("delay", 0.8)))
			_add_job(fighter, {"kind": "circle", "at": sim.tick_count + delay, "pos": point, "radius": float(stats["radius"]), "frac": float(stats["damage"]), "stats": stats})
			sim.events.append({"type": "class_skill_telegraph", "player": id, "skill": skill, "pos": point, "radius": float(stats["radius"]), "ticks": delay})
		"ally_buff":
			var ally = sim.fighters.get(target)
			if ally != null and ally.is_alive():
				var until: int = sim.tick_count + SkillData.ticks(float(stats.get("duration", 5.0)))
				ally.skill_state["veil"] = {"until": until, "mul": float(stats.get("taken_mul", 0.7)), "by": id, "slow": float(stats.get("attacker_slow", 0.0)), "reflect": float(stats.get("thorns", 0.0))}
				Effects.apply(id, sim.fighters[id], target, ally, {"id": "haste", "chance": 100.0, "duration": SkillData.ticks(float(stats.get("haste", 3.0)))}, sim.combat, sim.rng, sim.events)
				sim.events.append({"type": "class_skill_veil", "player": id, "target": target, "until": until})


# ---------------------------------------------------------------- shapes

static func _circle(sim, id: int, center: Vector3, radius: float, stats: Dictionary, frac: float = -1.0) -> int:
	var victims: Array = _enemy_ids(sim, id).filter(func(e): return _flat(sim.bodies[e].position - center).length() <= radius)
	return _hit_many(sim, id, victims, stats, center, frac)


## E4: enemies within `radius` and within arc_deg / 2 of the aim direction.
static func _arc(sim, id: int, at: Vector3, aim: Vector3, stats: Dictionary) -> int:
	return _hit_many(sim, id, in_arc(sim, id, at, aim, float(stats["radius"]), float(stats.get("arc_deg", 240.0))), stats, at)


static func in_arc(sim, id: int, at: Vector3, aim: Vector3, radius: float, arc_deg: float) -> Array:
	var facing := _flat(aim - at)
	if facing.length() < 0.001:
		facing = Vector2(sim.fighters[id].direction).normalized()
	return _enemy_ids(sim, id).filter(func(e):
		var off := _flat(sim.bodies[e].position - at)
		if off.length() > radius:
			return false
		return arc_deg >= 360.0 or off.length() < 0.05 or rad_to_deg(absf(facing.angle_to(off))) <= arc_deg * 0.5)


## Hits every victim once; a heavy skill (E5) gets Cleave and fires one skill_heavy (race heavy_hit, 5.2).
static func _hit_many(sim, id: int, victims: Array, stats: Dictionary, center: Vector3, frac: float = -1.0) -> int:
	var heavy := float(stats.get("heavy", 0.0)) > 0.0
	var cleave := 1.0
	if heavy:
		cleave = load(RACE).cleave_mul(sim.fighters[id], victims.size())
	var extra := {}
	for key in ["stun", "slow", "weaken", "sunder"]:
		if float(stats.get(key, 0.0)) > 0.0:
			extra[key] = stats[key]
	var damage := float(stats["damage"]) if frac < 0.0 else frac
	for e in victims:
		_hit(sim, id, e, damage * cleave, stats, extra)
		if float(stats.get("knockback", 0.0)) > 0.0:
			_push_from(sim, e, center, float(stats["knockback"]))
	if heavy and not victims.is_empty():
		sim.events.append({"type": "skill_heavy", "player": id, "skill": str(stats.get("skill_id", "")), "targets": victims.size()})
	return victims.size()


# ---------------------------------------------------------------- damage

## One skill hit (4.1): ATK x frac x status bonus x crit vs DEF; shield first; skill_hit / killed events; statuses.
## Returns true on a kill.
static func _hit(sim, id: int, target_id: int, frac: float, stats: Dictionary, extra: Dictionary = {}) -> bool:
	var source = sim.fighters[id]
	var target = sim.fighters[target_id]
	if not target.is_alive() or load(COMBAT).is_invulnerable(target, sim.combat):
		return false
	var rules: Dictionary = sim.combat.rules
	var mul := frac
	var bonus_status := str(stats.get("bonus_status", ""))
	if not bonus_status.is_empty() and target.effects.has(bonus_status):
		mul *= float(stats.get("bonus_mul", 1.5))  # E9
	var chance: float = source.stat("CRIRATE") / 100.0 + float(stats.get("crit_add", 0.0)) / 100.0 + float(stats.get("crit_chance", 0.0))
	var crit: bool = sim.rng.randf() < chance
	var damage: float = source.stat("ATK") * mul
	if crit:
		damage *= source.stat("CRIDMG", 150.0) / 100.0
	var defense: float = target.stat("DEF")
	damage *= 1.0 - defense / (defense + float(rules["defense_constant"]))
	damage = maxf(float(rules["min_damage"]), roundf(damage))
	var absorbed: float = target.absorb(damage)
	target.hp = maxf(0.0, target.hp - (damage - absorbed))
	var skill := str(stats.get("skill_id", ""))
	var tier := int(SkillData.load_default().skill(skill).get("impact_tier", 1))
	sim.events.append({"type": "skill_hit", "attacker": id, "target": target_id, "damage": damage - absorbed, "absorbed": absorbed, "crit": crit,
		"pos": sim.bodies[target_id].position, "move": "skill:" + skill, "skill": skill, "impact": tier, "ranged": true, "dir": Vector2.ZERO, "effect": "hit", "periodic": false})
	_hitstop(sim, id, target_id, tier, crit)
	Effects.wake(target_id, target, sim.combat, sim.events)
	if target.hp <= 0.0:
		_kill(sim, target_id, id)
		return true
	if extra.has("stun") and stats.has("boss_stun") and is_boss(target):
		extra = extra.duplicate()
		extra["stun"] = minf(float(extra["stun"]), float(stats["boss_stun"]))  # Gravity Crush: the longer stagger is for non-bosses
	for key in extra:
		if float(extra[key]) > 0.0:
			Effects.apply(id, source, target_id, target, {"id": str(key), "chance": 100.0, "duration": SkillData.ticks(float(extra[key]))}, sim.combat, sim.rng, sim.events)
	for status in stats.get("statuses", []):  # statuses a tree node adds (only the combat ones exist now)
		if sim.combat.effects.has(str(status)):
			Effects.apply(id, source, target_id, target, {"id": str(status), "chance": 100.0, "duration": 0}, sim.combat, sim.rng, sim.events)
	return false


static func _kill(sim, target_id: int, by: int) -> void:
	var target = sim.fighters[target_id]
	target.state = Fighter.State.DEAD
	target.state_ticks = 0
	target.move_id = ""
	target.launched = false
	Effects.clear(target, sim.combat)
	sim.events.append({"type": "killed", "target": target_id, "by": by})


static func _hitstop(sim, attacker_id: int, target_id: int, tier: int, crit: bool) -> void:
	var impact: Dictionary = SkillData.load_default().impact
	var on_target: Array = impact.get("target_hitstop", [])
	var on_caster: Array = impact.get("caster_hitstop", [])
	var cap := int(impact.get("max_hitstop", 12))
	if tier <= 0 or tier >= on_target.size():
		return
	var target = sim.fighters[target_id]
	if target.is_alive():
		target.hitstop = maxi(target.hitstop, mini(cap, int(on_target[tier]) + (int(impact.get("crit_hitstop_bonus", 0)) if crit else 0)))
	if tier < on_caster.size() and int(on_caster[tier]) > 0:
		var caster = sim.fighters[attacker_id]
		caster.hitstop = maxi(caster.hitstop, mini(cap, int(on_caster[tier])))


## E1 + E3 + E14: the class-skill part of a blow on fighter `target_id` (Combat.apply_hit calls it with the damage after
## the target's DEF). Order: Warding Veil x0.7, Iron Guard x0.5 (+ queue a counter on a melee attacker), then the
## Intercept link takes `frac` of the RAW blow (before the ally's DEF) through the tank's DEF and its own modifiers (4.2).
## Returns what the target itself takes.
static func incoming(target_id: int, attacker_id: int, damage: float, melee: bool, fighters: Dictionary, bodies: Dictionary, data, events: Array, tick: int) -> float:
	var target = fighters[target_id]
	var s: Dictionary = target.skill_state
	if s.is_empty() or damage <= 0.0:
		return damage
	damage = _taken_mods(target_id, target, attacker_id, damage, melee, fighters, data, events, tick)
	var link: Dictionary = s.get("link", {})
	if not link.is_empty() and int(link["until"]) > tick:
		var tank_id := int(link["by"])
		var tank = fighters.get(tank_id)
		if tank != null and tank.is_alive() and not tank.eliminated:
			var own_def: float = target.stat("DEF")
			var raw := damage / maxf(0.01, 1.0 - own_def / (own_def + float(data.rules["defense_constant"])))
			var tank_def: float = tank.stat("DEF")
			var share: float = float(link["frac"]) * raw * (1.0 - tank_def / (tank_def + float(data.rules["defense_constant"])))
			share = _taken_mods(tank_id, tank, attacker_id, share, false, fighters, data, events, tick)
			share = roundf(share)
			damage = damage * (1.0 - float(link["frac"]))
			var absorbed: float = tank.absorb(share)
			tank.hp = maxf(0.0, tank.hp - (share - absorbed))
			events.append({"type": "skill_hit", "attacker": attacker_id, "target": tank_id, "damage": share - absorbed, "absorbed": absorbed, "crit": false,
				"pos": bodies[tank_id].position, "move": "skill:intercept_link", "skill": "intercept_link", "impact": 0, "ranged": true, "dir": Vector2.ZERO,
				"effect": "redirect", "periodic": false, "redirect_from": target_id})
			if float(link.get("reflect", 0.0)) > 0.0 and fighters.has(attacker_id) and fighters[attacker_id].is_alive():
				s["reflect_queue"] = s.get("reflect_queue", []) + [[tank_id, attacker_id, share * float(link["reflect"])]]
			if tank.hp <= 0.0:
				tank.state = Fighter.State.DEAD
				tank.state_ticks = 0
				tank.move_id = ""
				events.append({"type": "killed", "target": tank_id, "by": attacker_id})
	return damage


static func _taken_mods(id: int, fighter, attacker_id: int, damage: float, melee: bool, fighters: Dictionary, data, events: Array, tick: int) -> float:
	var s: Dictionary = fighter.skill_state
	var veil: Dictionary = s.get("veil", {})
	if not veil.is_empty() and int(veil["until"]) > tick:
		damage *= float(veil["mul"])
		if melee and float(veil.get("slow", 0.0)) > 0.0 and fighters.has(attacker_id):
			s["veil_slow"] = s.get("veil_slow", []) + [attacker_id]
	var reflect := 0.0
	if not veil.is_empty() and int(veil["until"]) > tick:
		reflect += float(veil.get("reflect", 0.0))  # Spiked Veil
	var trance: Dictionary = s.get("trance", {})
	if not trance.is_empty() and int(trance["until"]) > tick:
		reflect += float(trance.get("reflect", 0.0))  # Thorned Trance
	if melee and reflect > 0.0 and fighters.has(attacker_id) and fighters[attacker_id].team != fighter.team:
		s["reflect_queue"] = s.get("reflect_queue", []) + [[id, attacker_id, damage * reflect]]
	var stance: Dictionary = s.get("stance", {})
	if not stance.is_empty() and int(stance["until"]) > tick:
		damage *= float(stance["taken_mul"])
		if melee and int(stance["left"]) > 0 and tick >= int(stance["next"]) and fighters.has(attacker_id) and fighters[attacker_id].team != fighter.team:
			stance["left"] = int(stance["left"]) - 1
			stance["next"] = tick + int(stance["icd"])
			s["counters"].append(attacker_id)
	return damage


## Iron Guard counters (E3), Thorned Link reflects and Thorned Veil slows, run on the next class-skill step.
static func _run_counters(sim, id: int, fighter) -> void:
	var s: Dictionary = fighter.skill_state
	var queue: Array = s.get("counters", [])
	if not queue.is_empty():
		s["counters"] = []
		var stance: Dictionary = s.get("stance", {})
		var stats: Dictionary = stance.get("stats", {"skill_id": "iron_guard", "damage": 0.5})
		for attacker in queue:
			if not sim.fighters.has(attacker) or not sim.fighters[attacker].is_alive():
				continue
			var counter_stats: Dictionary = stats.duplicate()
			counter_stats["skill_id"] = "iron_guard"
			_hit(sim, id, attacker, float(stance.get("counter", 0.5)), counter_stats, {})
			sim.events.append({"type": "class_skill_counter", "player": id, "target": attacker})
			if float(stance.get("fortify", 0.0)) > 0.0:
				Effects.apply(id, fighter, id, fighter, {"id": "fortify", "chance": 100.0, "duration": SkillData.ticks(float(stance["fortify"]))}, sim.combat, sim.rng, sim.events)
	for row in s.get("reflect_queue", []):
		if sim.fighters.has(int(row[1])) and sim.fighters[int(row[1])].is_alive():
			_flat_damage(sim, int(row[0]), int(row[1]), float(row[2]), "intercept")
	s.erase("reflect_queue")
	for attacker in s.get("veil_slow", []):
		if sim.fighters.has(attacker) and sim.fighters[attacker].is_alive():
			var by := int(s.get("veil", {}).get("by", id))
			Effects.apply(by, sim.fighters.get(by, fighter), attacker, sim.fighters[attacker], {"id": "slow", "chance": 100.0, "duration": SkillData.ticks(float(s.get("veil", {}).get("slow", 2.0)))}, sim.combat, sim.rng, sim.events)
	s.erase("veil_slow")


## A reflect: a fixed amount (already through the DEF rule of the blow it came from).
static func _flat_damage(sim, id: int, target_id: int, amount: float, skill: String) -> void:
	var target = sim.fighters[target_id]
	amount = maxf(1.0, roundf(amount))
	target.hp = maxf(0.0, target.hp - amount)
	sim.events.append({"type": "skill_hit", "attacker": id, "target": target_id, "damage": amount, "absorbed": 0.0, "crit": false, "pos": sim.bodies[target_id].position,
		"move": "skill:" + skill, "skill": skill, "impact": 0, "ranged": true, "dir": Vector2.ZERO, "effect": "reflect", "periodic": false})
	if target.hp <= 0.0:
		_kill(sim, target_id, id)


# ---------------------------------------------------------------- jobs (orbs, delayed hits)

static func _add_job(fighter, job: Dictionary) -> void:
	fighter.skill_state["jobs"].append(job)


static func _add_orb(sim, fighter, at: Vector3, dir: Vector3, frac: float, stats: Dictionary, delay: int) -> void:
	_add_job(fighter, {"kind": "orb", "at": sim.tick_count + delay, "pos": at + Vector3.UP * 0.0, "dir": dir, "left": float(stats.get("range", 12.0)),
		"speed": float(stats.get("speed", 12.0)), "radius": float(stats.get("radius", 2.0)), "frac": frac, "stats": stats})


static func _run_jobs(sim, id: int, fighter) -> void:
	var jobs: Array = fighter.skill_state.get("jobs", [])
	if jobs.is_empty():
		return
	var kept: Array = []
	for job in jobs:
		if sim.tick_count < int(job["at"]):
			kept.append(job)
			continue
		match str(job["kind"]):
			"hit":
				if _enemy_ok(sim, id, int(job["target"])):
					_hit(sim, id, int(job["target"]), float(job["frac"]), job["stats"])
			"circle":
				_circle(sim, id, job["pos"], float(job["radius"]), job["stats"], float(job["frac"]))
				sim.events.append({"type": "class_skill_impact", "player": id, "skill": str(job["stats"].get("skill_id", "")), "pos": job["pos"], "radius": float(job["radius"])})
			"orb":
				var step: float = float(job["speed"]) / SkillData.TICKS
				var pos: Vector3 = Vector3(job["pos"]) + Vector3(job["dir"]) * minf(step, float(job["left"]))
				job["left"] = float(job["left"]) - step
				job["pos"] = pos
				var touched := _enemy_ids(sim, id).any(func(e): return _flat(sim.bodies[e].position - pos).length() <= 0.6)
				if touched or float(job["left"]) <= 0.0:
					_circle(sim, id, pos, float(job["radius"]), job["stats"], float(job["frac"]))
					sim.events.append({"type": "class_skill_impact", "player": id, "skill": str(job["stats"].get("skill_id", "")), "pos": pos, "radius": float(job["radius"])})
				else:
					kept.append(job)
	fighter.skill_state["jobs"] = kept


# ---------------------------------------------------------------- movement helpers

## E7 pull (formula 4.3): enemies within `range_m` of `center` move `distance` m toward it, final distance >= `min_d`;
## bosses and elites are not pulled. Returns the ids moved.
static func pull(sim, id: int, center: Vector3, range_m: float, distance: float, min_d: float) -> Array:
	var moved: Array = []
	for e in _enemy_ids(sim, id):
		if is_elite(sim.fighters[e]):
			continue
		var pos: Vector3 = sim.bodies[e].position
		var off := _flat(pos - center)
		var d := off.length()
		if d > range_m or d < 0.001:
			continue
		var final_d := maxf(min_d, d - distance)
		if final_d >= d:
			continue
		var p := Vector2(center.x, center.z) + off / d * final_d
		sim.bodies[e].position = Vector3(p.x, pos.y, p.y)
		moved.append(e)
	if not moved.is_empty():
		sim.events.append({"type": "class_skill_pull", "player": id, "enemies": moved, "pos": center})
	return moved


static func _push(sim, id: int, target_id: int, distance: float) -> void:
	if distance > 0.0 and sim.fighters.has(target_id):
		_push_from(sim, target_id, sim.bodies[id].position, distance)


## Knockback `distance` m straight away from `center` (bosses/elites are not moved; walls stop it, 5.1).
static func _push_from(sim, target_id: int, center: Vector3, distance: float) -> void:
	var target = sim.fighters[target_id]
	if is_elite(target) or not target.is_alive():
		return
	var body = sim.bodies[target_id]
	var dir := _flat_dir(body.position - center)
	if dir == Vector3.ZERO:
		dir = Vector3.RIGHT
	var to: Vector3 = body.position + dir * distance
	to.x = clampf(to.x, -sim.world.half_width, sim.world.half_width)
	to.z = clampf(to.z, -sim.world.half_depth, sim.world.half_depth)
	body.position = to


static func _face(sim, id: int, point: Vector3) -> void:
	var off := _flat(point - sim.bodies[id].position)
	if off.length() > 0.001:
		sim.fighters[id].direction = load(COMBAT).direction_from(off)


# ---------------------------------------------------------------- targets

static func is_boss(fighter) -> bool:
	return RaceData.load_default().rules.get("boss_types", []).has(fighter.enemy_type)


static func is_elite(fighter) -> bool:
	return is_boss(fighter) or RaceData.load_default().rules.get("elite_types", []).has(fighter.enemy_type)


static func _enemy_ids(sim, id: int) -> Array:
	var team: String = sim.fighters[id].team
	var out: Array = sim.fighters.keys().filter(func(o): return sim.fighters[o].team != team and sim.fighters[o].is_alive())
	out.sort()
	return out


static func _enemy_ok(sim, id: int, target: int) -> bool:
	return sim.fighters.has(target) and sim.fighters[target].team != sim.fighters[id].team and sim.fighters[target].is_alive()


static func _ally_ok(sim, id: int, target: int) -> bool:
	return sim.fighters.has(target) and sim.fighters[target].team == sim.fighters[id].team and sim.fighters[target].is_alive()


static func _nearest_enemy(sim, id: int, within: float) -> int:
	var best := -1
	var best_d := within
	for e in _enemy_ids(sim, id):
		var d := _flat(sim.bodies[e].position - sim.bodies[id].position).length()
		if d < best_d:
			best_d = d
			best = e
	return best


## The longbow's next shot target (L3 retarget, 5.1): the boss in range, else the lowest HP in range, ties nearer then id.
static func shot_target(sim, id: int, range_m: float, marked_first: bool = false) -> int:
	var at: Vector3 = sim.bodies[id].position
	var inside: Array = _enemy_ids(sim, id).filter(func(e): return _flat(sim.bodies[e].position - at).length() <= range_m)
	if marked_first:  # Hunter's Rhythm: arrows retarget to Hunter's Mark (sunder) first
		var marked: Array = inside.filter(func(e): return sim.fighters[e].effects.has("sunder"))
		if not marked.is_empty():
			inside = marked
	for e in inside:
		if is_boss(sim.fighters[e]):
			return e
	var best := -1
	var best_score := INF
	for e in inside:
		var score: float = sim.fighters[e].hp * 1000.0 + _flat(sim.bodies[e].position - at).length()
		if score < best_score:
			best_score = score
			best = e
	return best


## Enemies (not in `skip`) within 0.6 m of the line from `at` along `dir` up to `length`, nearest first.
static func line_hits(sim, id: int, at: Vector3, dir: Vector3, length: float, skip: Array) -> Array:
	var d2 := Vector2(dir.x, dir.z)
	var found: Array = []
	for e in _enemy_ids(sim, id):
		if skip.has(e):
			continue
		var off := _flat(sim.bodies[e].position - at)
		var along := off.dot(d2)
		if along > 0.0 and along <= length and absf(off.cross(d2)) <= 0.6:
			found.append([along, e])
	found.sort()
	return found.map(func(row): return row[1])


static func _nearest_to(sim, id: int, point: Vector3, range_m: float, skip: Array) -> int:
	var best := -1
	var best_d := INF
	for e in _enemy_ids(sim, id):
		var d := _flat(sim.bodies[e].position - point).length()
		if not skip.has(e) and _flat(sim.bodies[e].position - sim.bodies[id].position).length() <= range_m and d < best_d:
			best_d = d
			best = e
	return best


# ---------------------------------------------------------------- view for the client

## fighter.skill_view keys the client reads (E16): class_cast {skill, start, end, now, target, aim} while casting;
## class_buffs {stance, trance, veil, link}. Other skill_view keys are left alone.
static func publish_view(sim, id: int, fighter) -> void:
	var s: Dictionary = fighter.skill_state
	var cast: Dictionary = s.get("cast", {})
	var view: Dictionary = fighter.skill_view
	view["casting"] = not cast.is_empty()
	view["moving"] = false
	if cast.is_empty():
		view.erase("class_cast")
	else:
		view["class_cast"] = {"skill": str(cast["skill"]), "start": int(cast["start"]), "end": int(cast["end"]), "now": sim.tick_count, "target": int(cast["target"]), "aim": cast["aim"]}
		var travel: Dictionary = cast.get("travel", {})
		view["moving"] = not travel.is_empty() and sim.tick_count >= int(travel["from_tick"]) and sim.tick_count <= int(travel["to_tick"])
	var buffs := {}
	for key in ["stance", "trance", "veil", "link"]:
		if not s.get(key, {}).is_empty():
			buffs[key] = int(s[key].get("until", 0))
	view["class_buffs"] = buffs
	if s.has("skills"):
		var slots: Array = []
		for skill in s["skills"]:
			slots.append({"skill": skill, "left": cooldown_left(sim, fighter, str(skill)), "cost": float(SkillData.load_default().skill(str(skill)).get("stamina", 0.0))})
		view["slots"] = slots


# ---------------------------------------------------------------- small math

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _flat_dir(v: Vector3) -> Vector3:
	var f := Vector2(v.x, v.z)
	if f.length() < 0.0001:
		return Vector3.ZERO
	f = f.normalized()
	return Vector3(f.x, 0.0, f.y)
