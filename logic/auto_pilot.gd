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
##
## Survival (Boss 2026-11-23; tools/balance/survival_probe.gd measures it): a pilot carrying any SURVIVAL_FIELDS
## (telegraph_reaction, retreat_below, boss_kite_distance, stamina_reserve, support_boss_below, alone_caution) also
## (a)(f) leaves every wind-up marker / marked ground it stands in early (_escape_hazards: walk, run, last-tick dodge,
## guard when stamina pays), never ignores a blow that would kill, holds attack-skill clips and heavies while a boss
## winds up nearby, never walks into a marker; (b)(g) below retreat_below HP (or with most allies down while a boss is
## healthy) it stops trading: an ultimate first, then the back line kites, the front line guards and hits openings;
## (c) a back-line card the boss targets keeps out of its reach (circling, up to boss_kite_distance); (d) keeps
## stamina_reserve for a dodge/guard; (e) Warding Veil's pilot_support rule wards an ally a boss is on earlier.
## Without those fields the old path runs unchanged (tests/test_autopilot_survival.gd compares it with a frozen copy).

const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const RaceUltimates := preload("res://logic/race_ultimates.gd")
const Combat := preload("res://logic/combat.gd")
const ClassSkills := preload("res://logic/class_skills/engine.gd")
const ClassSkillUse := preload("res://logic/class_skills/use_rules.gd")
const Movement := preload("res://logic/movement.gd")
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
	var survival := _has_survival(profile)  ## pilot survival fields present (else the old behaviour, unchanged)
	var hold_skills := false
	if survival:
		var dodge_or_run = _escape_hazards(sim, combat, id, me, profile, memory, reaction)  # (a)(f) telegraphs and marked ground
		if dodge_or_run != null:
			return dodge_or_run
		hold_skills = bool(memory.get("hold_skills", false))

	for area in ([] if survival else sim.areas):  # a marked circle that is about to burst: step out of it
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
		if survival and other.state == Fighter.State.ATTACK and bool(combat.moves.get(other.move_id, {}).get("telegraph", false)):
			continue  # telegraphed moves: _escape_hazards decided already (timed to the marker, not at its first tick)
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
				if survival and me.energy < _guard_cost(combat, move):
					input.move = -delta.normalized()  # (d) too little stamina to hold this blow: step away instead of a guard that breaks
					return input
				input.guard = true
				input.aim = delta
				return input
		elif decided.has(other_id):
			decided.erase(other_id)
	if nearest == -1:
		return input
	if not me.pin.is_empty():
		return _pinned(sim, combat, id, me, profile, memory, tick, survival, hold_skills, nearest)

	var engage := _engage_range(combat, me, profile)
	var class_pick: Dictionary = {}
	if ClassSkills.has_skills(me) and me.state == Fighter.State.IDLE and not ClassSkills.busy(me):
		# class skills v2 (design/gdd/class-skills.md 3.7): the use rules pick the skill and its target; defensive ones
		# (Vault Shot replaces the kite dodge, Repulse Nova, Intercept ...) come before walking or the ultimate.
		class_pick = ClassSkillUse.pick(sim, id, pick_target(sim, id, profile, engage, nearest))
	if survival and not class_pick.is_empty() and (_clip_too_long(sim, id, str(class_pick["skill"])) or (float(SkillData_priority(str(class_pick["skill"]))) >= 1.0 \
			and (hold_skills or _short_of_reserve(sim, id, me, profile, str(class_pick["skill"]))))):
		class_pick = {}  # (a)(d) no clip that still locks the card when a blow it stands under lands, no attack-skill clip
		# while a boss winds up nearby, nor one that eats the dodge/guard reserve
	if not class_pick.is_empty() and float(SkillData_priority(str(class_pick["skill"]))) < 1.0:
		return _skill_input(sim, id, me, class_pick)
	var careful := survival and _cautious(sim, id, me, profile)
	if survival:
		if careful and RaceUltimates.ready(sim, id) and wants_ultimate(sim, id, engage):
			input.ultimate = true  # (b) a ready ultimate whose use rule holds now goes before backing off
			input.aim = _flat(sim.bodies[nearest].position - at)
			return input
		var kited = _kite_input(sim, id, me, profile, careful, memory, tick)  # (b)(c) back line: away from the boss on it, wider when hurt
		if kited != null:
			return kited
		if careful and str(profile.get("line", "")) == "front":
			var held = _careful_melee(sim, combat, id, me)  # (b)(g) front line: guard the focused boss, hit its openings
			if held != null:
				return held
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
		if survival:
			input.move = _safe_move(sim, id, input.move)  # (f) never walk into a marked area or a wind-up marker
			input.run = input.run and me.energy > float(profile.get("stamina_reserve", 0.0)) + 10.0  # (d) keep a reserve
		return input

	input.aim = toward
	if me.state != Fighter.State.IDLE and me.state != Fighter.State.ATTACK:
		return input
	# (the old weapon ultimate button is off for players: GameSim drops it, so a full gauge never freezes the pilot)
	if not class_pick.is_empty():
		return _skill_input(sim, id, me, class_pick)
	return _swing(sim, me, profile, memory, tick, hold_skills, input)


## The light/heavy press rhythm once a target is in reach (heavy every Nth press).
static func _swing(sim, me: Fighter, profile: Dictionary, memory: Dictionary, tick: int, hold_skills: bool, input: SimInput) -> SimInput:
	if tick % SWING_EVERY == 0:
		memory["swings"] = int(memory["swings"]) + 1
		var every := ClassSkills.heavy_every(sim, me)  # Battle Trance: every 2nd swing is a heavy (class-skills.md 3.3 G4)
		if preload("res://logic/skill_tree_mechanics.gd").take_momentum(me):
			memory["swings"] = int(memory["swings"]) + 1  # Momentum: the next heavy comes one swing earlier
		if int(memory["swings"]) % maxi(1, every if every > 0 else int(profile.get("heavy_every", HEAVY_EVERY))) == 0 and not hold_skills:
			input.heavy = true
		else:
			input.light = true
	return input


## Card pin (Boss 2026-11-26, data/combat/pin.json): walk to the pin first, then stay within pin_radius of it. Only
## enemies reachable from inside that circle are fought: a shooter shoots anything in its engage range, a melee card
## steps (inside the circle) toward an enemy whose body comes within pin_radius + reach of the pin, else it waits.
## Never kites or chases out; hazard escapes and guards ran before this (decide) and the card walks back after.
static func _pinned(sim, combat, id: int, me: Fighter, profile: Dictionary, memory: Dictionary, tick: int, survival: bool, hold_skills: bool, nearest: int) -> SimInput:
	var input := SimInput.new()
	var rules: Dictionary = sim.pin_rules() if sim.has_method("pin_rules") else {}
	var radius := float(rules.get("pin_radius", 1.5))
	var at: Vector3 = sim.bodies[id].position
	var pin := Vector3(float(me.pin["x"]), at.y, float(me.pin["z"]))
	var home: Vector2 = _flat(pin - at)
	if home.length() > radius:
		input.move = home.normalized()  # on the way to the pin: no fighting yet
		input.run = home.length() > float(rules.get("run_distance", RUN_DISTANCE)) and me.energy > 25.0 and not me.exhausted
		if survival:
			input.move = _safe_move(sim, id, input.move)
		input.aim = input.move
		return input
	var engage := _engage_range(combat, me, profile)
	var shooter := _is_shooter(combat, me)
	var reach_from_pin := engage if shooter else radius + engage
	var origin: Vector3 = at if shooter else pin
	var in_reach: Array = _enemy_ids(sim, id).filter(func(e): return _flat(sim.bodies[e].position - origin).length() <= reach_from_pin)
	if in_reach.is_empty():
		if home.length() > float(rules.get("arrive", 0.35)):
			input.move = _safe_move(sim, id, home.normalized()) if survival else home.normalized()
		input.aim = _flat(sim.bodies[nearest].position - at)
		return input
	in_reach.sort()
	var target := pick_target(sim, id, profile, engage, nearest)
	if not in_reach.has(target):
		target = _best(in_reach, func(e): return -_flat(sim.bodies[e].position - at).length())
	var toward: Vector2 = _flat(sim.bodies[target].position - at)
	if RaceUltimates.ready(sim, id) and wants_ultimate(sim, id, engage):
		input.ultimate = true
		input.aim = toward
		return input
	if ClassSkills.has_skills(me) and me.state == Fighter.State.IDLE and not ClassSkills.busy(me):
		var pick := ClassSkillUse.pick(sim, id, target)
		if not pick.is_empty() and not (survival and (_clip_too_long(sim, id, str(pick["skill"])) or (float(SkillData_priority(str(pick["skill"]))) >= 1.0 				and (hold_skills or _short_of_reserve(sim, id, me, profile, str(pick["skill"])))))):
			return _skill_input(sim, id, me, pick)
	if toward.length() > engage:
		var step := toward.normalized()
		var next := _flat(at - pin) + step * 0.3
		if next.length() <= radius - 0.2:  # leave room for body pushes
			input.move = _safe_move(sim, id, step) if survival else step  # melee: close in, inside the circle only
		input.aim = toward
		return input
	input.aim = toward
	if me.state != Fighter.State.IDLE and me.state != Fighter.State.ATTACK:
		return input
	return _swing(sim, me, profile, memory, tick, hold_skills, input)


## True when this fighter's light attack fires projectiles (longbow, magic).
static func _is_shooter(combat, me: Fighter) -> bool:
	var style: Dictionary = combat.styles.get(me.style, {})
	return not combat.moves.get(str(style.get("ground_light", "")), {}).get("spawns", []).is_empty()


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
	# Combos (Boss 2026-11-25): an enemy in engage range carrying a state this card's ready skills pay off wins
	# (more matching states first, then nearer). Mark counts for every class (+15%).
	if not me.skill_state.get("skills", []).is_empty():
		var wanted: Array = ClassSkills.Combos.wanted_states(sim, id)
		var combo := _best(enemies, func(e):
			var d: float = _flat(sim.bodies[e].position - at).length()
			if d > engage:
				return -INF
			var n := wanted.filter(func(st): return ClassSkills.Combos.has(sim.fighters[e], str(st))).size()
			return float(n) * 1000.0 - d if n > 0 else -INF)
		if combo >= 0:
			return combo
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


# --- survival (Boss 2026-11-23: "do not stand there while the boss hits you to death") ----------------------------
# Every function below reads only what a player sees (warning markers, marked ground, who the boss walks at, HP and
# stamina bars) and is active only when the class pilot carries the survival fields (SURVIVAL_FIELDS); a profile
# without them keeps the old behaviour exactly. Randomness: memory.rng only (one roll per telegraphed move / area).

const SURVIVAL_FIELDS: Array[String] = ["telegraph_reaction", "retreat_below", "boss_kite_distance", "stamina_reserve", "support_boss_below", "alone_caution"]
const SAFE_CLIP_TICKS := 45.0  ## a skill clip up to this long is fine next to a boss; longer ones wait for an opening
const BOSS_REACH_MARGIN := 2.5  ## "in reach of a boss": its attack_range + this (a slam/dash reaches past attack_range)
const SQRT2 := 1.4143
const BODY_HALF := 0.4  ## a body's half width (logic/sim_body.gd HALF_WIDTH)
const ESCAPE_MARGIN := 0.45  ## metres past the edge of a marker that count as out of it
const DODGE_LEAD := 8  ## dodge when the blow is this many ticks away (inside the dodge's invulnerable ticks)
const GUARD_LEAD := 14  ## start a guard this many ticks before a guardable blow lands
const BOSS_WATCH := 6.0  ## a boss winding up a telegraph within this distance: do not start a skill clip or a heavy
const FOCUS_RADIUS := 3.0  ## a boss this close and facing the card counts as on it (front-line caution)
const KITE_CHECK_TICKS := 40  ## kiting that has not gained KITE_MIN_GAIN metres in this long (wall, corner, faster boss) ...
const KITE_MIN_GAIN := 0.5
const KITE_PAUSE_TICKS := 90  ## ... stops for this long: the card fights back instead of running in place
const KITE_MARGIN := 1.5  ## a back-line card the boss targets moves away once the boss is within its reach + this


static func _has_survival(profile: Dictionary) -> bool:
	for field in SURVIVAL_FIELDS:
		if profile.has(field):
			return true
	return false


## Stamina a guard against `move` costs (combat rule guard_energy_per_power x power).
static func _guard_cost(combat, move: Dictionary) -> float:
	return float(combat.rules["guard_energy_per_power"]) * float(move.get("power", 1.0))


## Roughly what one blow of `move` from `attacker` takes off `me` (no crit, no guard): the lethal check.
static func _blow(combat, attacker: Fighter, me: Fighter, move: Dictionary) -> float:
	var defense := me.stat("DEF")
	return attacker.stat("ATK") * float(move.get("power", 1.0)) * (1.0 - defense / (defense + float(combat.rules["defense_constant"])))


## One roll per threat (key), kept in memory.decided: [move/key, react?, frame]. A blow that would kill always reacts.
static func _will_react(memory: Dictionary, key, tag: String, frame: float, chance: float, lethal: bool) -> bool:
	var decided: Dictionary = memory["decided"]
	if not decided.has(key) or decided[key][0] != tag or frame < float(decided[key][2]):
		decided[key] = [tag, memory["rng"].randf() < chance, frame]
	decided[key][2] = frame
	return lethal or bool(decided[key][1])


## (a)(f) Telegraph awareness: every boss/elite wind-up marker and every enemy ground mark the card stands in, with the
## ticks left before it lands. Returns the most urgent one {"ticks", "out" (exit direction), "need" (metres to leave),
## "guardable", "cost", "lethal", "key", "tag", "frame", "from"} or {}.
static func _threats(sim, combat, id: int, me: Fighter) -> Array:
	var at: Vector3 = sim.bodies[id].position
	var out: Array = []
	for e in _enemy_ids(sim, id):
		var foe: Fighter = sim.fighters[e]
		if not Combat.is_telegraphing(foe, combat):
			continue
		var move: Dictionary = combat.moves[foe.move_id]
		if not bool(move.get("melee", true)) and not move.get("spawns", []).is_empty():
			continue  # a cast that places a ground mark or fires a shot: the mark/shot itself is handled when it exists
		var shape := _danger_shape(Combat.telegraph_shape(e, sim.fighters, sim.bodies, combat))
		if not in_telegraph(shape, at, ESCAPE_MARGIN):
			continue
		var exit := _exit(shape, at)
		out.append({"ticks": (float(move["startup"]) - foe.move_frame) / foe.attack_speed_factor(), "out": exit[0], "need": exit[1],
			"guardable": not bool(move.get("ignores_guard", false)), "cost": _guard_cost(combat, move), "lethal": _blow(combat, foe, me, move) >= me.hp,
			"key": "t%d" % e, "tag": foe.move_id, "frame": foe.move_frame, "from": _flat(sim.bodies[e].position - at)})
	for area in sim.areas:
		if area["team"] == me.team or int(area["age"]) >= int(area["delay"]):
			continue
		var shape := {"kind": "circle", "center": area["pos"], "radius": float(area["radius"]) + 0.4}  # + the body's half width
		if not in_telegraph(shape, at, ESCAPE_MARGIN):
			continue
		var exit := _exit(shape, at)
		var owner: Fighter = sim.fighters.get(int(area["owner"]))
		var move: Dictionary = combat.moves.get(str(area["move"]), {})
		out.append({"ticks": float(int(area["delay"]) - int(area["age"])), "out": exit[0], "need": exit[1], "guardable": false, "cost": 0.0,
			"lethal": owner != null and _blow(combat, owner, me, move) >= me.hp, "key": "area%d" % int(area["id"]), "tag": "area", "frame": float(area["age"]), "from": Vector2.ZERO})
	out.sort_custom(func(a, b): return a["ticks"] < b["ticks"])
	return out


## The ground a wind-up really hits, from its warning marker: a blow all around the fighter is a square hit box (the
## marker draws its half side as the radius, the corners reach x1.41 of it) and every shape hits a body's half width
## further out. Used for dodging only (what the player sees is unchanged).
static func _danger_shape(shape: Dictionary) -> Dictionary:
	var out := shape.duplicate()
	match str(shape.get("kind", "")):
		"circle":
			out["radius"] = float(shape["radius"]) * SQRT2 + BODY_HALF
		"lane":
			out["width"] = float(shape["width"]) + 2.0 * BODY_HALF
			out["far_width"] = float(shape.get("far_width", shape["width"])) + 2.0 * BODY_HALF
	return out


## The way out of a marker from `point`: [unit direction, metres still to go]. Circle: straight away from the centre;
## lane: sideways to the nearer edge (never out of its far end: the Warlock's Skyfall dashes 3 m down its lane).
static func _exit(shape: Dictionary, point: Vector3) -> Array:
	if str(shape["kind"]) == "circle":
		var off := _flat(point - Vector3(shape["center"]))
		var dir := off.normalized() if off.length() > 0.05 else Vector2.RIGHT
		return [dir, float(shape["radius"]) + ESCAPE_MARGIN - off.length()]
	var dir: Vector2 = Vector2(shape["dir"]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var off := _flat(point - Vector3(shape["origin"]))
	var along := off.dot(dir)
	var across := off.dot(side)
	var t := clampf(along / maxf(0.01, float(shape["length"])), 0.0, 1.0)
	var half := lerpf(float(shape["width"]), float(shape.get("far_width", shape["width"])), t) * 0.5
	var sideways := half + ESCAPE_MARGIN - absf(across)
	return [side * (1.0 if across >= 0.0 else -1.0), sideways]  # always sideways: a rush or dash carries the blow down the lane


## (a)(f) Leave the most urgent marker early (walk, run when walking is too slow), dodge through it at the last ticks,
## or guard a guardable blow when stamina pays for it. null = nothing to do. Also notes memory.hold_skills (a boss
## winding up near the card: no skill clip or heavy now, they would lock it in place).
static func _escape_hazards(sim, combat, id: int, me: Fighter, profile: Dictionary, memory: Dictionary, reaction: float):
	var at: Vector3 = sim.bodies[id].position
	memory["hold_skills"] = _enemy_ids(sim, id).any(func(e): return is_boss(sim.fighters[e]) and Combat.is_telegraphing(sim.fighters[e], combat) and _flat(sim.bodies[e].position - at).length() <= BOSS_WATCH) \
		or not _threats(sim, combat, id, me).is_empty()
	if me.state != Fighter.State.IDLE and me.state != Fighter.State.GUARD:
		return null  # mid-swing, sliding, stunned: nothing can be started this tick
	var chance := float(profile.get("telegraph_reaction", reaction))
	for threat in _threats(sim, combat, id, me):
		if not _will_react(memory, threat["key"], str(threat["tag"]), float(threat["frame"]), chance, bool(threat["lethal"])):
			continue
		var input := SimInput.new()
		var speed: float = Movement.SPEED * sim.bodies[id].move_speed_multiplier / 60.0
		var ticks: float = threat["ticks"]
		var need: float = threat["need"]
		var can_dodge: bool = me.dodge_cooldown == 0 and me.energy >= float(combat.rules["dodge_energy"])
		if ticks <= DODGE_LEAD and can_dodge:
			input.dodge = true  # the slide's invulnerable ticks cover the blow, and it carries the card out
			input.move = threat["out"]
			return input
		if bool(threat["guardable"]) and ticks <= GUARD_LEAD and need > speed * Movement.RUN_MULTIPLIER * maxf(0.0, ticks - 1.0) \
				and me.energy >= float(threat["cost"]) and not can_dodge:
			input.guard = true  # cannot get out in time and no dodge: take it on the shield
			input.aim = threat["from"]
			return input
		input.move = threat["out"]
		input.run = need > speed * maxf(0.0, ticks - DODGE_LEAD) and not me.exhausted  # walking would not make it: run
		return input
	return null


## (a) A skill clip locks the card (no move, guard or dodge) until it ends: refuse one that would still be playing when
## a telegraphed blow it stands in lands (a clip with invulnerable travel, Vault Shot / Intercept, is the exception).
static func _clip_too_long(sim, id: int, skill: String) -> bool:
	var data: Dictionary = preload("res://logic/class_skills/skill_data.gd").load_default().skill(skill)
	if str(data.get("motion", {}).get("invulnerable", "")) == "travel":
		return false
	var me: Fighter = sim.fighters[id]
	var timing: Dictionary = ClassSkills.scaled_timing(data.get("timing", {"end": 1.0}), float(ClassSkills.cast_stats(me, skill).get("cast_time", 1.0)))
	var clip := float(timing.get("end", 1.0)) * 60.0
	var threats := _threats(sim, sim.combat, id, me)
	if not threats.is_empty():
		return clip >= float(threats[0]["ticks"]) - 2.0
	if clip <= SAFE_CLIP_TICKS:
		return false
	# a long clip in reach of a boss that is free to swing: it may wind up mid-clip (its rest is not visible)
	var at: Vector3 = sim.bodies[id].position
	for e in _enemy_ids(sim, id):
		var brain = sim._ai.get(e) if "_ai" in sim else null
		if is_boss(sim.fighters[e]) and brain != null and not _opening(sim, e) \
				and _flat(sim.bodies[e].position - at).length() <= float(brain.attack_range) + BOSS_REACH_MARGIN:
			return true
	return false


## (d) Stamina reserve: with a boss within BOSS_WATCH, a skill whose cost would leave less than pilot.stamina_reserve
## (the dodge/guard money) waits for the bar to refill.
static func _short_of_reserve(sim, id: int, me: Fighter, profile: Dictionary, skill: String) -> bool:
	var reserve := float(profile.get("stamina_reserve", 0.0))
	if reserve <= 0.0 or not _boss_within(sim, id, BOSS_WATCH):
		return false
	var cost := float(preload("res://logic/class_skills/skill_data.gd").load_default().skill(skill).get("stamina", 0.0))
	return me.energy - cost < reserve


static func _boss_within(sim, id: int, radius: float) -> bool:
	var at: Vector3 = sim.bodies[id].position
	return _enemy_ids(sim, id).any(func(e): return is_boss(sim.fighters[e]) and _flat(sim.bodies[e].position - at).length() <= radius)


## (c)(g) Is a boss on this card? Its own target (who it walks at, ranged_first) or a boss within FOCUS_RADIUS facing it.
static func _boss_on_me(sim, id: int) -> int:
	var at: Vector3 = sim.bodies[id].position
	for e in _enemy_ids(sim, id):
		var boss: Fighter = sim.fighters[e]
		if not is_boss(boss):
			continue
		var brain = sim._ai.get(e) if "_ai" in sim else null
		if brain != null and brain.pick_target(boss, sim.bodies[e], sim.bodies, sim.fighters) == id and brain.taunted_by(boss, sim.fighters) < 0:
			return e
		var off := _flat(at - sim.bodies[e].position)
		if off.length() <= FOCUS_RADIUS and Vector2(boss.direction).normalized().dot(off.normalized()) >= 0.5:
			return e
	return -1


## (b)(g) Careful mode: HP under pilot.retreat_below, or too many allies down (pilot.alone_caution share of the squad)
## while a boss still has more than a third of its HP.
static func _cautious(sim, id: int, me: Fighter, profile: Dictionary) -> bool:
	if me.hp < me.max_hp() * float(profile.get("retreat_below", 0.0)):
		return true
	var alone := float(profile.get("alone_caution", 0.0))
	if alone <= 0.0:
		return false
	var squad := 0
	var down := 0
	for o in sim.fighters:
		var f: Fighter = sim.fighters[o]
		if f.team == me.team and o != id:
			squad += 1
			down += 0 if f.is_alive() else 1
	if squad == 0 or float(down) / float(squad) < alone:
		return false
	return _enemy_ids(sim, id).any(func(e): return is_boss(sim.fighters[e]) and sim.fighters[e].hp > sim.fighters[e].max_hp() / 3.0)


## (b)(c) Back line: keep pilot.boss_kite_distance from a boss that is on it (always) or from any enemy when careful;
## move away and around (toward the middle of the board, not into a corner). null = far enough, fight on.
static func _kite_input(sim, id: int, me: Fighter, profile: Dictionary, careful: bool, memory: Dictionary, tick: int):
	var keep := float(profile.get("boss_kite_distance", 0.0))
	if keep <= 0.0 or str(profile.get("line", "")) != "back" or tick < int(memory.get("kite_off_until", -1)):
		return null
	var at: Vector3 = sim.bodies[id].position
	var from := -1
	var focused := _boss_on_me(sim, id)
	if focused >= 0 and _flat(sim.bodies[focused].position - at).length() < _focus_kite(sim, focused, keep) and not _opening(sim, focused):
		from = focused
	elif careful:
		var best := keep
		for e in _enemy_ids(sim, id):
			var d := _flat(sim.bodies[e].position - at).length()
			if d < best:
				best = d
				from = e
	if from < 0:
		memory.erase("kite_from")
		return null
	var gap := _flat(at - sim.bodies[from].position).length()
	if not memory.has("kite_from") or int(memory["kite_from"][0]) != from:
		memory["kite_from"] = [from, tick, gap]
	elif tick - int(memory["kite_from"][1]) >= KITE_CHECK_TICKS:
		if gap < float(memory["kite_from"][2]) + KITE_MIN_GAIN:
			memory["kite_off_until"] = tick + KITE_PAUSE_TICKS  # cornered or out-run: stand and fight for a moment
			memory.erase("kite_from")
			return null
		memory["kite_from"] = [from, tick, gap]
	var away := _flat(at - sim.bodies[from].position)
	away = away.normalized() if away.length() > 0.05 else Vector2.LEFT
	var around := Vector2(-away.y, away.x)
	if around.dot(-_flat(at)) < 0.0:
		around = -around  # circle toward the middle of the board
	var input := SimInput.new()
	input.move = _safe_move(sim, id, (away + around * 0.6).normalized())
	input.run = me.energy > float(profile.get("stamina_reserve", 25.0)) + 10.0 and not me.exhausted
	input.aim = -away
	return input


## How close a boss that targets this card may come before it moves away: its own strike reach + KITE_MARGIN, at
## most pilot.boss_kite_distance (between the two the card stands and shoots). A ranged boss (ai keep_range > 0)
## is not out-walked: 0 (its marks and shots are dodged by _escape_hazards instead).
static func _focus_kite(sim, boss_id: int, keep: float) -> float:
	var brain = sim._ai.get(boss_id) if "_ai" in sim else null
	if brain == null:
		return keep
	if float(brain.keep_range) > 0.0:
		return 0.0
	return minf(keep, float(brain.attack_range) + KITE_MARGIN)


## True while the boss cannot strike right now (recovering from an attack, staggered, down): the window to shoot.
static func _opening(sim, boss_id: int) -> bool:
	var boss: Fighter = sim.fighters[boss_id]
	if boss.state == Fighter.State.HITSTUN or boss.state == Fighter.State.DOWN:
		return true
	if boss.state != Fighter.State.ATTACK:
		return false
	var move: Dictionary = sim.combat.moves.get(boss.move_id, {})
	return boss.move_frame >= float(move.get("startup", 0)) + float(move.get("active", 0)) + 4.0


## (b)(g) Front line in careful mode with a boss on it: hold the guard while the boss is free to swing, hit back only
## while it recovers from an attack (the opening a player waits for). null = not focused, fight normally.
static func _careful_melee(sim, combat, id: int, me: Fighter):
	var boss_id := _boss_on_me(sim, id)
	if boss_id < 0:
		return null
	var boss: Fighter = sim.fighters[boss_id]
	var to_boss := _flat(sim.bodies[boss_id].position - sim.bodies[id].position)
	if to_boss.length() > FOCUS_RADIUS + 1.0:
		return null
	if boss.state == Fighter.State.ATTACK:
		var move: Dictionary = combat.moves.get(boss.move_id, {})
		if boss.move_frame >= float(move.get("startup", 0)) + float(move.get("active", 0)):
			return null  # recovering: the opening, swing
	elif boss.state != Fighter.State.IDLE:
		return null  # staggered or down: swing
	var input := SimInput.new()
	input.aim = to_boss
	if me.energy >= float(combat.rules["guard_energy_per_power"]) * 0.6:
		input.guard = true
	else:
		input.move = -to_boss.normalized()  # no stamina for a guard: back off until it refills
	return input


## (e) Support earlier: an ally (or this card) under pilot.support_boss_below that a boss is on. Used by the
## warding_veil use rule "pilot_support" (logic/class_skills/use_rules.gd), so the authority checks the same rule.
static func support_choice(sim, id: int, max_range: float) -> int:
	var me: Fighter = sim.fighters[id]
	var below := float(pilot_profile(me).get("support_boss_below", 0.0))
	if below <= 0.0:
		return -1
	var best := -1
	var best_hp := INF
	for a in _allies(sim, id):
		var f: Fighter = sim.fighters[a]
		var frac := f.hp / maxf(1.0, f.max_hp())
		if frac >= below or _flat(sim.bodies[a].position - sim.bodies[id].position).length() > max_range or _boss_on_me(sim, a) < 0:
			continue
		if frac < best_hp or (frac == best_hp and a < best):
			best_hp = frac
			best = a
	return best


## (f) A step that would walk into marked ground or a boss wind-up marker turns aside (or stops).
static func _safe_move(sim, id: int, move: Vector2) -> Vector2:
	if move == Vector2.ZERO:
		return move
	var at: Vector3 = sim.bodies[id].position
	var combat = sim.combat
	if _in_hazard(sim, combat, id, at):
		return move  # already inside: the escape decides
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var step := move.rotated(turn)
		if not _in_hazard(sim, combat, id, at + Vector3(step.x, 0.0, step.y) * 0.9):
			return step
	return Vector2.ZERO


static func _in_hazard(sim, combat, id: int, point: Vector3) -> bool:
	for area in sim.areas:
		if area["team"] != sim.fighters[id].team and int(area["age"]) < int(area["delay"]) and _flat(point - Vector3(area["pos"])).length() <= float(area["radius"]) + 0.4:
			return true
	for e in _enemy_ids(sim, id):
		if Combat.is_telegraphing(sim.fighters[e], combat) and in_telegraph(_danger_shape(Combat.telegraph_shape(e, sim.fighters, sim.bodies, combat)), point, 0.2):
			return true
	return false


## True when `point` stands inside a telegraph warning shape (Combat.telegraph_shape: the marker a player sees), with
## `margin` metres to spare. Circle: centre + radius. Lane: from origin along dir for length, width widening to far_width.
static func in_telegraph(shape: Dictionary, point: Vector3, margin: float = 0.3) -> bool:
	match str(shape.get("kind", "")):
		"circle":
			return _flat(point - Vector3(shape["center"])).length() <= float(shape["radius"]) + margin
		"lane":
			var dir: Vector2 = Vector2(shape["dir"]).normalized()
			var off := _flat(point - Vector3(shape["origin"]))
			var along := off.dot(dir)
			var length := float(shape["length"])
			if along < -margin or along > length + margin:
				return false
			var t := clampf(along / maxf(0.01, length), 0.0, 1.0)
			var half := lerpf(float(shape["width"]), float(shape.get("far_width", shape["width"])), t) * 0.5
			return absf(off.dot(Vector2(-dir.y, dir.x))) <= half + margin
	return false


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
