extends RefCounted
## Race ultimates at fight time (design/gdd/races-and-classes.md 3.10, 4.2-4.6, 5; phases 6-7). Pure rules.
## RacePassives.attach copies a squad card's ultimate block (data/races/<race>.json classes.<class>.ultimate, else
## default_class.ultimate) into race_state.ultimate. With rules.ultimates_enabled a cast runs like this (3.10.3):
##  1. start(): the pilot pressed ultimate (GameSim routes input.ultimate here) with a full gauge while IDLE, grounded,
##     not stunned/asleep/shocked, not mid skill cast and with HP >= min_hp. The gauge drops to 0 and the synthetic move
##     <race>_<class>_ultimate starts (startup = cast_ticks, recovery = recover_ticks, power 0, registered into
##     CombatData.moves). Events: attack_started (client clip, class_sim counter) and ultimate_cast.
##  2. The wind-up: hits do not stagger the caster (Combat.apply_hit treats it as armored); a stun/sleep/shock clears
##     the move and death ends it: the cast is lost (race_ult_lost), the gauge stays 0.
##  3. resolve() at the end of the wind-up: self_hp_cost (not damage), then the actions in order with one shared
##     context {"ultimate": true, "damage": damage dealt so far, cached centers/targets}, then the race event
##     ultimate_cast (Runeborn runes fill and discharge, 3.4).
## Lasting parts live in race_state (checkpointed): "jobs" (repeat burst hits, delayed detonations) and "zones".
## Every event an ultimate causes carries "ultimate": true (the gauge ignores them, class_sim measures them).
## Deterministic: no RNG; ties break by distance, then fighter id.

const RaceData := preload("res://logic/race_data.gd")
const Fighter := preload("res://logic/fighter.gd")
const Effects := preload("res://logic/effects.gd")
const Loader := preload("res://logic/combat_data_loader.gd")
const PASSIVES_PATH := "res://logic/race_passives.gd"  ## loaded at call time (it preloads this file)
const DEFAULT_CAST_RANGE := 9.0  ## a center/target with no cast_range looks this far (m)
const DEFAULT_FURY := 1.5  ## rules.fury_factor fallback (formula 4.6)


static func _passives():
	return load(PASSIVES_PATH)


## The synthetic move id of this card's ultimate.
static func move_id(fighter) -> String:
	return "%s_%s_ultimate" % [fighter.race_state.get("race", ""), fighter.race_state.get("class", "")]


## Puts the card's synthetic ultimate move into the combat data (idempotent). Called on attach and after a restore.
static func register_move(combat, fighter) -> void:
	var ult: Dictionary = fighter.race_state.get("ultimate", {})
	if combat == null or ult.is_empty() or combat.moves.has(move_id(fighter)):
		return
	var raw := {"startup": maxi(1, int(ult.get("cast_ticks", 30))), "active": 1, "recovery": maxi(0, int(ult.get("recover_ticks", 20))),
		"power": 0.0, "hit_offset": [0.0, 0.0, 0.0], "hit_size": [1.0, 1.0, 1.0], "melee": false}
	combat.moves[move_id(fighter)] = Loader._normalize_move(raw, "race ultimate " + move_id(fighter), combat)


## Can fighter `id` start its ultimate now (3.10.3 step 1)?
static func ready(sim, id: int) -> bool:
	var fighter = sim.fighters.get(id)
	if fighter == null or fighter.race_state.get("ultimate", {}).is_empty() or not _passives().ultimates_enabled():
		return false
	var ult: Dictionary = fighter.race_state["ultimate"]
	var need: float = _passives().TreeEffects.fire_threshold(fighter, float(sim.combat.rules["ultimate_gauge_max"]))  # tree Berserkergang
	if fighter.gauge < need or fighter.state != Fighter.State.IDLE or not fighter.is_alive():
		return false
	if fighter.incapacitated or fighter.rooted or not sim.bodies[id].grounded:
		return false
	if bool(fighter.skill_view.get("casting", false)) or bool(fighter.skill_view.get("moving", false)):
		return false
	return fighter.hp >= fighter.max_hp() * float(ult.get("min_hp", 0.0))


## Starts the cast (3.10.3 step 2). Returns false (nothing changes) when not ready.
static func start(sim, id: int) -> bool:
	if not ready(sim, id):
		return false
	var fighter = sim.fighters[id]
	var ult: Dictionary = fighter.race_state["ultimate"]
	register_move(sim.combat, fighter)
	fighter.gauge = _passives().TreeEffects.gauge_after_cast(fighter)  # 0, or the tree's after_cast (Mastery Overflow)
	fighter.race_state["full_at"] = -1
	var move := move_id(fighter)
	fighter.move_id = move
	fighter.move_frame = 0.0
	fighter.hit_ids.clear()
	fighter.spawns_done = 0
	fighter.buffered = ""
	fighter.active_started = false
	fighter.state = Fighter.State.ATTACK
	fighter.state_ticks = 0
	fighter.race_state["ult"] = {"move": move, "at": sim.tick_count, "done": false}
	sim.events.append({"type": "attack_started", "player": id, "move": move})
	sim.events.append({"type": "ultimate_cast", "player": id, "name": str(ult.get("name", "")), "race": str(fighter.race_state["race"]),
		"class": str(fighter.race_state["class"]), "vfx": str(ult.get("vfx", "")), "clip": str(ult.get("clip", "ultimate")), "cast_ticks": int(ult.get("cast_ticks", 30))})
	return true


## One tick of fighter `id`'s ultimate state (all race fighters, dead too): a pending cast resolves or is lost,
## then due jobs and zones run. Called by RacePassives.step before the passives read this tick's events.
static func step(sim, id: int, fighter) -> void:
	var pending: Dictionary = fighter.race_state.get("ult", {})
	if not pending.is_empty():
		var casting: bool = fighter.is_alive() and fighter.state == Fighter.State.ATTACK and fighter.move_id == str(pending["move"])
		if not bool(pending["done"]):
			if not casting:
				fighter.race_state.erase("ult")  # stunned, shocked, asleep or killed in the wind-up: the cast is lost (3.10.3 step 4)
				sim.events.append({"type": "race_ult_lost", "player": id, "move": str(pending["move"])})
			elif fighter.move_frame >= float(sim.combat.moves[str(pending["move"])]["startup"]):
				pending["done"] = true
				resolve(sim, id)
		elif not casting:
			fighter.race_state.erase("ult")
	_run_jobs(sim, id, fighter)
	_run_zones(sim, id, fighter)


## The end of the wind-up (3.10.3 step 3).
static func resolve(sim, id: int) -> void:
	var fighter = sim.fighters[id]
	var ult: Dictionary = fighter.race_state["ultimate"]
	var cost: float = float(ult.get("self_hp_cost", 0.0)) * fighter.hp
	if cost > 0.0:  # not damage: no hurt event, no runes, no gauge (5)
		fighter.hp = maxf(1.0, fighter.hp - cost)
		sim.events.append({"type": "race_hp_cost", "player": id, "amount": cost, "ultimate": true})
	var ctx := {"ultimate": true, "damage": 0.0, "points": {}, "picked": {}}
	var did := 0
	for action in ult.get("actions", []):
		if _passives().run_action(sim, id, action, ctx):
			did += 1
	sim.events.append({"type": "race_ult_resolved", "player": id, "name": str(ult.get("name", "")), "did": did, "damage": float(ctx["damage"]), "ultimate": true})
	_passives().fire(sim, id, "ultimate_cast", {})  # Runeborn: the rune passive fills and discharges (3.4)


# ------------------------------------------------------------------ burst (v1 + v2 fields)

## burst (3.6): every living enemy within `radius` of `center` takes atk_mul x ATK vs its DEF (+ status). v2 fields:
## hits + interval_ticks (repeats as jobs), last_status (the final hit's status), force_crit, bonus_target_below_hp +
## bonus_mul, fury (true = rules.fury_factor, or a number; formula 4.6), chain_on_kill (a new shot at the next target
## for each kill, never one already hit), delayed {ticks, atk_mul, radius, status} (a detonation on each hit spot),
## target (shoot at that target kind instead of a center) + cast_range, pick ("nearest": only the enemy nearest the
## center; "spread": each hit on a different enemy within cast_range, then the boss, then the nearest), on_hit / on_kill
## [actions]. Returns true when it went off (even if nobody stood in it).
static func burst(sim, id: int, action: Dictionary, ctx: Dictionary) -> bool:
	var hits := maxi(1, int(action.get("hits", 1)))
	var index := int(ctx.get("hit_index", 1))
	if not ctx.has("refreshed"):
		ctx["refreshed"] = {}  # one skill_refresh cap per cast, shared by the later hits of this burst (Masterstroke 4 s)
	if hits > 1 and index == 1:
		var every := maxi(1, int(action.get("interval_ticks", 15)))
		var jobs: Array = sim.fighters[id].race_state.get("jobs", [])
		if not ctx.has("hit"):
			ctx["hit"] = []
		var shared := {"hit": ctx["hit"], "refreshed": ctx["refreshed"]}  # all hits of this burst share one hit list and one refresh cap
		for k in range(2, hits + 1):
			var later := _job_ctx(ctx)
			later["hit_index"] = k
			later["shared"] = shared
			jobs.append({"at": sim.tick_count + every * (k - 1), "action": action, "ctx": later})
		sim.fighters[id].race_state["jobs"] = jobs
	return _burst_once(sim, id, action, ctx, index, hits)


static func _burst_once(sim, id: int, action: Dictionary, ctx: Dictionary, index: int, hits: int) -> bool:
	var source = sim.fighters[id]
	var radius := float(action["radius"])
	var hit_list: Array = ctx.get("hit", [])
	var victims: Array = []
	var center = null
	var pick := str(action.get("pick", ""))
	if pick == "spread":
		var chosen := _spread_target(sim, id, action, ctx)
		if chosen < 0:
			return false
		center = sim.bodies[chosen].position
		victims = [chosen]
	elif action.has("target"):
		var found: Array = _passives().targets(sim, id, str(action["target"]), ctx, action)
		if found.is_empty():
			return false  # nobody valid (5: damage actions with no target do nothing)
		center = sim.bodies[int(found[0])].position
	else:
		center = center_of(sim, id, str(action.get("center", "zone" if ctx.has("zone_pos") else "self")), action, ctx)
	if center == null:
		return false
	if victims.is_empty():
		var ids: Array = sim.fighters.keys()
		ids.sort()
		var best := -1
		var best_d := INF
		for target_id in ids:
			var t = sim.fighters[target_id]
			if t.team == source.team or not t.is_alive():
				continue
			var d := _flat(sim.bodies[target_id].position - center).length()
			if d > radius:
				continue
			if pick == "nearest":
				if d < best_d:
					best_d = d
					best = target_id
			else:
				victims.append(target_id)
		if pick == "nearest" and best >= 0:
			victims = [best]
	sim.events.append({"type": "race_burst", "player": id, "pos": center, "radius": radius, "ultimate": bool(ctx.get("ultimate", false))})
	var status := str(action.get("status", ""))
	if index == hits and action.has("last_status"):
		status = str(action["last_status"])
	elif action.has("last_status"):
		status = ""
	for target_id in victims:
		var target = sim.fighters[target_id]
		var mul := float(action["atk_mul"])
		if bool(action.get("cleave", false)):  # tree Shatterglyph: this burst counts as a heavy for Cleave
			mul *= _passives().cleave_mul(source, victims.size())
		if action.has("bonus_target_below_hp") and target.hp < target.max_hp() * float(action["bonus_target_below_hp"]):
			mul *= float(action.get("bonus_mul", 2.0))
		var killed := hit_enemy(sim, id, target_id, mul, action, ctx)
		if not hit_list.has(target_id):
			hit_list.append(target_id)
		ctx["hit"] = hit_list
		if not killed and not status.is_empty():
			Effects.apply(id, source, target_id, target, {"id": status, "chance": 100.0, "duration": int(action.get("duration", 0))}, sim.combat, sim.rng, sim.events)
		for extra in action.get("on_hit", []):
			_passives().run_action(sim, id, extra, ctx)
		if action.get("delayed") is Dictionary:
			var delayed: Dictionary = action["delayed"].duplicate(true)
			delayed["action"] = "burst"
			delayed["center"] = "job"
			var later := _job_ctx(ctx)
			later["job_pos"] = sim.bodies[target_id].position
			var jobs: Array = source.race_state.get("jobs", [])
			jobs.append({"at": sim.tick_count + int(delayed.get("ticks", 120)), "action": delayed, "ctx": later})
			source.race_state["jobs"] = jobs
		if killed:
			for extra in action.get("on_kill", []):
				_passives().run_action(sim, id, extra, ctx)
			var chain_left := int(ctx.get("chain_left", int(action.get("chain_on_kill", 0))))
			if chain_left > 0 and action.has("target"):
				ctx["chain_left"] = chain_left - 1
				_burst_once(sim, id, action, ctx, index, hits)  # the next arrow: the next target kind match, never one already hit
	return true


## One damage instance of a race burst on enemy `target_id`: ATK x mul vs DEF (+ crit if force_crit, + fury), shields
## first, kills are normal "killed" events by the caster. Adds the damage to ctx.damage. Returns true on a kill.
static func hit_enemy(sim, id: int, target_id: int, mul: float, action: Dictionary, ctx: Dictionary) -> bool:
	var source = sim.fighters[id]
	var target = sim.fighters[target_id]
	var rules: Dictionary = sim.combat.rules
	var defense: float = target.stat("DEF")
	var damage: float = source.stat("ATK") * mul * (1.0 - defense / (defense + float(rules["defense_constant"])))
	if bool(action.get("force_crit", false)):
		damage *= source.stat("CRIDMG", 100.0) / 100.0
	var fury = action.get("fury", false)
	var factor := float(fury) if (fury is float or fury is int) else (float(RaceData.load_default().rules.get("fury_factor", DEFAULT_FURY)) if fury == true else 0.0)
	if factor > 0.0:  # formula 4.6: x (1 + factor x the caster's missing HP fraction now)
		damage *= 1.0 + factor * clampf(1.0 - source.hp / maxf(1.0, source.max_hp()), 0.0, 1.0)
	damage = maxf(float(rules["min_damage"]), roundf(damage))
	var absorbed: float = target.absorb(damage)
	target.hp = maxf(0.0, target.hp - (damage - absorbed))
	var ult := bool(ctx.get("ultimate", false))
	sim.events.append({"type": "race_burst_hit", "attacker": id, "target": target_id, "damage": damage, "absorbed": absorbed, "pos": sim.bodies[target_id].position, "ultimate": ult})
	ctx["damage"] = float(ctx.get("damage", 0.0)) + damage
	if target.hp > 0.0:
		return false
	target.state = Fighter.State.DEAD
	target.state_ticks = 0
	target.move_id = ""
	target.launched = false
	Effects.clear(target, sim.combat)
	sim.events.append({"type": "killed", "target": target_id, "by": id, "ultimate": ult})
	return true


## "spread" pick: an enemy within cast_range not hit by this cast yet (nearest first), else the boss, else the nearest.
static func _spread_target(sim, id: int, action: Dictionary, ctx: Dictionary) -> int:
	var at: Vector3 = sim.bodies[id].position
	var reach := float(action.get("cast_range", DEFAULT_CAST_RANGE))
	var hit: Array = ctx.get("hit", [])
	var fresh := -1
	var fresh_d := INF
	var nearest := -1
	var nearest_d := INF
	var boss := -1
	var ids: Array = sim.fighters.keys()
	ids.sort()
	for e in ids:
		var f = sim.fighters[e]
		if f.team == sim.fighters[id].team or not f.is_alive():
			continue
		var d := _flat(sim.bodies[e].position - at).length()
		if d > reach:
			continue
		if d < nearest_d:
			nearest_d = d
			nearest = e
		if boss < 0 and is_boss(f):
			boss = e
		if not hit.has(e) and d < fresh_d:
			fresh_d = d
			fresh = e
	return fresh if fresh >= 0 else (boss if boss >= 0 else nearest)


# ------------------------------------------------------------------ zone

## zone (3.6): a lasting area at `center` that runs its `pulse` actions every `every_ticks` for `duration_ticks` (the
## first pulse at once). follow: it moves with the caster and ends early if the caster is stunned/asleep/dead.
## extend_on_kill_ticks (+ extend_max_ticks): each kill by the caster while it lasts adds time. Pulse actions with
## first_only run on the first pulse only. on_end actions run with context damage = the zone's total damage.
static func start_zone(sim, id: int, action: Dictionary, ctx: Dictionary) -> bool:
	var pos = center_of(sim, id, str(action.get("center", "self")), action, ctx)
	if pos == null:
		pos = sim.bodies[id].position  # 5: a zone with no valid center falls back to the caster
	var zone := {"action": action, "pos": pos, "until": sim.tick_count + int(action.get("duration_ticks", 180)), "next": sim.tick_count,
		"extended": 0, "pulses": 0, "ctx": {"ultimate": bool(ctx.get("ultimate", false)), "damage": 0.0, "points": {}, "picked": {}, "zone_pos": pos, "zone_radius": float(action["radius"])}}
	var zones: Array = sim.fighters[id].race_state.get("zones", [])
	zones.append(zone)
	sim.fighters[id].race_state["zones"] = zones
	sim.events.append({"type": "race_zone", "player": id, "pos": pos, "radius": float(action["radius"]), "ticks": int(action.get("duration_ticks", 180)), "follow": bool(action.get("follow", false)), "ultimate": bool(ctx.get("ultimate", false))})
	_run_zones(sim, id, sim.fighters[id])
	return true


static func _run_zones(sim, id: int, fighter) -> void:
	var zones: Array = fighter.race_state.get("zones", [])
	if zones.is_empty():
		return
	var kept: Array = []
	for zone in zones:
		var action: Dictionary = zone["action"]
		var zctx: Dictionary = zone["ctx"]
		if bool(action.get("follow", false)):
			if not fighter.is_alive() or fighter.incapacitated:
				zone["until"] = sim.tick_count  # a whirl ends early when the caster is stunned or dies (5)
			else:
				zone["pos"] = sim.bodies[id].position
		zctx["zone_pos"] = zone["pos"]
		if sim.tick_count < int(zone["until"]) and sim.tick_count >= int(zone["next"]):
			zctx["first"] = int(zone["pulses"]) == 0
			zctx["points"] = {}
			zctx["picked"] = {}
			for pulse in action.get("pulse", []):
				if bool(pulse.get("first_only", false)) and not bool(zctx["first"]):
					continue
				_passives().run_action(sim, id, pulse, zctx)
			zone["pulses"] = int(zone["pulses"]) + 1
			zone["next"] = int(zone["next"]) + maxi(1, int(action.get("every_ticks", 30)))
			sim.events.append({"type": "race_zone_pulse", "player": id, "pos": zone["pos"], "radius": float(action["radius"]), "ultimate": bool(zctx.get("ultimate", false))})
		# Kill extension: every kill by the caster this tick (its pulse included) while the zone lasts, once per tick.
		if int(action.get("extend_on_kill_ticks", 0)) > 0 and int(zone.get("kill_tick", -1)) != sim.tick_count and int(zone["pulses"]) > 0:
			zone["kill_tick"] = sim.tick_count
			for event in sim.events:
				if str(event.get("type", "")) == "killed" and int(event.get("by", -1)) == id:
					var add := mini(int(action["extend_on_kill_ticks"]), int(action.get("extend_max_ticks", 0)) - int(zone["extended"]))
					if add > 0:
						zone["extended"] = int(zone["extended"]) + add
						zone["until"] = int(zone["until"]) + add
		if sim.tick_count >= int(zone["until"]):
			for end_action in action.get("on_end", []):
				_passives().run_action(sim, id, end_action, zctx)
			sim.events.append({"type": "race_zone_end", "player": id, "pos": zone["pos"], "damage": float(zctx["damage"]), "ultimate": bool(zctx.get("ultimate", false))})
			continue
		kept.append(zone)
	fighter.race_state["zones"] = kept


# ------------------------------------------------------------------ jobs (repeat hits, delayed detonations)

static func _job_ctx(ctx: Dictionary) -> Dictionary:
	var out := {"ultimate": bool(ctx.get("ultimate", false)), "damage": 0.0, "points": ctx.get("points", {}).duplicate(true), "picked": ctx.get("picked", {}).duplicate(true),
		"hit": ctx.get("hit", []), "refreshed": ctx.get("refreshed", {})}
	if ctx.has("zone_pos"):
		out["zone_pos"] = ctx["zone_pos"]
	return out


static func _run_jobs(sim, id: int, fighter) -> void:
	var jobs: Array = fighter.race_state.get("jobs", [])
	if jobs.is_empty():
		return
	var later: Array = []
	var due: Array = []
	for job in jobs:
		if sim.tick_count >= int(job["at"]):
			due.append(job)
		else:
			later.append(job)
	fighter.race_state["jobs"] = later
	for job in due:
		var ctx: Dictionary = job["ctx"]
		var action: Dictionary = job["action"]
		if ctx.has("shared"):  # the burst's earlier hits so far (spread picks a new enemy; the refresh cap is per cast)
			ctx["hit"] = ctx["shared"]["hit"]
			ctx["refreshed"] = ctx["shared"]["refreshed"]
		_burst_once(sim, id, action, ctx, int(ctx.get("hit_index", 1)), maxi(1, int(action.get("hits", 1))) if not action.has("ticks") else 1)


# ------------------------------------------------------------------ skill_refresh

## skill_refresh (3.6, formula 4.4): each of the target's 4 class-skill cooldowns: remaining' = max(0, remaining x
## (1 - fraction) - seconds). cap_seconds caps the flat seconds one cast may give each target (Masterstroke 4 s).
## A card with no class skills = nothing to refresh (5). Returns true when a cooldown got shorter.
static func skill_refresh(sim, id: int, action: Dictionary, ctx: Dictionary) -> bool:
	var did := false
	var given: Dictionary = ctx.get("refreshed", {})
	for target_id in _passives().targets(sim, id, str(action.get("target", "self")), ctx, action):
		var class_card: bool = sim.fighters.has(target_id) and not sim.fighters[target_id].skill_state.get("skills", []).is_empty()
		if class_card:  # class skills v2 (design/gdd/class-skills.md): the card's 4 skills live in Fighter.skill_state
			var secs := float(action.get("seconds", 0.0))
			if action.has("cap_seconds"):
				secs = clampf(float(action["cap_seconds"]) - float(given.get(target_id, 0.0)), 0.0, secs)
			given[target_id] = float(given.get(target_id, 0.0)) + secs
			var cut_v2: float = preload("res://logic/class_skills/engine.gd").refresh_cooldowns(sim, target_id, float(action.get("fraction", 0.0)), secs)
			if cut_v2 > 0.0:
				did = true
				sim.fighters[target_id].race_state["refreshed_at"] = sim.tick_count
				sim.events.append({"type": "race_skill_refresh", "player": id, "target": target_id, "seconds": cut_v2, "ultimate": bool(ctx.get("ultimate", false))})
			continue
	ctx["refreshed"] = given
	return did


# ------------------------------------------------------------------ revive

## heal on target ally_downed (3.10.5): a downed squad member stands up at fraction x max HP through the co-op revive
## rules (revive_invulnerable_ticks), once per ally per wave. Returns true when revived.
static func revive(sim, id: int, target_id: int, fraction: float) -> bool:
	var target = sim.fighters[target_id]
	if target.state != Fighter.State.DOWNED or target.eliminated:
		return false
	var wave: int = sim._waves_released + 1
	if int(target.race_state.get("ult_revived_wave", 0)) == wave:
		return false
	target.race_state["ult_revived_wave"] = wave
	target.state = Fighter.State.IDLE
	target.state_ticks = 0
	target.hp = maxf(1.0, target.max_hp() * fraction)
	target.invulnerable_left = int(sim.combat.coop.get("revive_invulnerable_ticks", 60)) if sim.combat.coop is Dictionary else 60
	target.bleedout_left = 0
	target.revive_progress = 0
	target.reviver = -1
	sim.events.append({"type": "revived", "player": target_id, "by": id, "ultimate": true})
	return true


# ------------------------------------------------------------------ centers and targets

static func is_boss(fighter) -> bool:
	return RaceData.load_default().rules.get("boss_types", []).has(fighter.enemy_type)


## Where a burst/zone sits (3.6 centers). Cached per cast in ctx.points so actions of one cast agree.
## densest: the enemy position within cast_range (9) with the most enemies within `radius` (ties: nearer, lower id),
## else null. boss_or_highest_hp: the living boss within cast_range, else the highest-HP enemy there, else null.
## ally_most_hurt: that ally (cached with the targets). zone / job: the current zone's / job's spot.
static func center_of(sim, id: int, kind: String, action: Dictionary, ctx: Dictionary):
	var points: Dictionary = ctx.get("points", {})
	ctx["points"] = points
	match kind:
		"self":
			return sim.bodies[id].position
		"target":
			var target := int(ctx.get("target", -1))
			return sim.bodies[target].position if sim.bodies.has(target) else sim.bodies[id].position
		"zone":
			return ctx.get("zone_pos", sim.bodies[id].position)
		"job":
			return ctx.get("job_pos", null)
		"densest":
			if not points.has("densest"):
				points["densest"] = densest_point(sim, id, float(action.get("cast_range", DEFAULT_CAST_RANGE)), float(action["radius"]))["pos"]
			return points["densest"]
		"boss_or_highest_hp":
			if not points.has("boss_or_highest_hp"):
				var found: Array = _passives().targets(sim, id, "enemy_highest_hp", ctx, action)
				points["boss_or_highest_hp"] = sim.bodies[int(found[0])].position if not found.is_empty() else null
			return points["boss_or_highest_hp"]
		"ally_most_hurt":
			var ally: Array = _passives().targets(sim, id, "ally_most_hurt", ctx, action)
			return sim.bodies[int(ally[0])].position if not ally.is_empty() else null
	return null


## {"pos": Vector3 or null, "count": int}: the enemy position within `reach` of fighter `id` with the most living
## enemies within `radius` of it (itself included).
static func densest_point(sim, id: int, reach: float, radius: float) -> Dictionary:
	var at: Vector3 = sim.bodies[id].position
	var enemies: Array = []
	for e in sim.fighters:
		if sim.fighters[e].team != sim.fighters[id].team and sim.fighters[e].is_alive():
			enemies.append(e)
	enemies.sort()
	var best = null
	var best_count := 0
	var best_d := INF
	for e in enemies:
		var p: Vector3 = sim.bodies[e].position
		var d := _flat(p - at).length()
		if d > reach:
			continue
		var count := 0
		for o in enemies:
			if _flat(sim.bodies[o].position - p).length() <= radius:
				count += 1
		if count > best_count or (count == best_count and d < best_d):
			best = p
			best_count = count
			best_d = d
	return {"pos": best, "count": best_count}


## The v2 targets (3.6). `ctx.picked` caches single picks per cast (ally_most_hurt, enemy_highest_hp) so a heal and
## the burst after it agree on who. Lists are in id order.
static func targets_v2(sim, id: int, kind: String, ctx: Dictionary, action: Dictionary) -> Array:
	var me = sim.fighters[id]
	var at: Vector3 = sim.bodies[id].position
	var ids: Array = sim.fighters.keys()
	ids.sort()
	var reach := float(action.get("cast_range", INF))
	var hit: Array = ctx.get("hit", [])
	match kind:
		"ally_downed":
			return ids.filter(func(o): return sim.fighters[o].team == me.team and sim.fighters[o].state == Fighter.State.DOWNED and not sim.fighters[o].eliminated)
		"allies_in_zone", "enemies_in_zone":
			var pos: Vector3 = ctx.get("zone_pos", at)
			var r := float(ctx.get("zone_radius", 0.0))
			var allies := kind == "allies_in_zone"
			return ids.filter(func(o): return (sim.fighters[o].team == me.team) == allies and sim.fighters[o].is_alive() and _flat(sim.bodies[o].position - pos).length() <= r)
		"enemies_in_radius":
			var r := float(action.get("radius", 0.0))
			return ids.filter(func(o): return sim.fighters[o].team != me.team and sim.fighters[o].is_alive() and _flat(sim.bodies[o].position - at).length() <= r)
		"enemy_lowest_hp_pct", "enemy_highest_hp":
			var lowest := kind == "enemy_lowest_hp_pct"
			var best := -1
			var best_score := INF
			var boss := -1
			for o in ids:
				var f = sim.fighters[o]
				if f.team == me.team or not f.is_alive() or hit.has(o) or _flat(sim.bodies[o].position - at).length() > reach:
					continue
				if not lowest and boss < 0 and is_boss(f):
					boss = o
				var score: float = f.hp / maxf(1.0, f.max_hp()) if lowest else -f.hp
				if score < best_score:
					best_score = score
					best = o
			if not lowest and boss >= 0:
				best = boss  # boss_or_highest_hp: the boss first
			return [best] if best >= 0 else []
	return []


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
