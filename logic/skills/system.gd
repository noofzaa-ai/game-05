extends RefCounted
## Fixed-tick adapter for the extracted Lab rules. Owns no scene nodes or presentation assets.
const Build := preload("res://logic/skill_build.gd")
const Codec := preload("res://logic/state_codec.gd")
const Checkpoint := preload("res://logic/skills/checkpoint.gd")
var _sim_ref: WeakRef
var sim:
	get: return _sim_ref.get_ref() if _sim_ref != null else null
var targets: Dictionary = {}
var casters: Dictionary = {}
var builds: Dictionary = {}
var _restoring := false
var _base_stats: Dictionary = {}

func setup(simulation) -> void:
	_sim_ref = weakref(simulation)

func attach(id: int, build: Dictionary) -> void:
	if not Build.validate(build).is_empty():
		casters.erase(id)
		builds.erase(id)
		sim.fighters[id].skill_hit_filter = Callable()
		sim.fighters[id].skill_base_hit = Callable()
		sim.fighters[id].skill_view = {}
		return
	builds[id] = build.duplicate(true)
	_sync_targets()
	var caster := ZorxSkillRuntime.new()
	caster.owner_id = id
	caster.pattern = {"katana":"fast", "dagger":"fast", "spear":"mid", "hammer":"heavy", "bow":"ranged", "staff":"ranged"}.get(build.start, "mid")
	var actor := ZorxSkillActor.new()
	actor.base_max_hp = sim.fighters[id].max_hp()
	actor.max_hp = actor.base_max_hp
	actor.hp = sim.fighters[id].hp
	caster.bind_actor(actor)
	caster.crit_rng.seed = sim.rng.seed ^ (id * 7919)
	caster.healed.connect(actor.heal)
	caster.visual_requested.connect(_visual_requested.bind(id))
	for target_id in targets:
		if sim.fighters[target_id].team != sim.fighters[id].team: caster.connect_target(targets[target_id])
	casters[id] = caster
	if sim.runs.has(id):
		for skill in sim.runs[id].skill_cooldowns:
			caster.cooldowns[skill] = maxf(0,float(sim.runs[id].skill_cooldowns[skill]))
	var passive := Build.basic_stats(build)
	passive.owner_id = id
	caster.configure_passives(passive)
	_base_stats[id] = sim.fighters[id].stats.duplicate(true)
	sim.fighters[id].skill_hit_filter = _base_incoming.bind(id)
	sim.fighters[id].skill_base_hit = _base_outgoing.bind(id)
	publish_views()

func _visual_requested(event: Dictionary, id: int) -> void:
	if _restoring or sim == null: return
	var out := event.duplicate(true)
	out.merge({"type":"skill_visual","player":id},true)
	sim.events.append(out)

func _base_incoming(amount: float, source_id: int, melee: bool, id: int) -> float:
	var actor: ZorxSkillActor = casters[id].actor
	actor.hp = sim.fighters[id].hp
	return actor.receive_attack(amount, targets.get(source_id), melee)

func _base_outgoing(target_id: int, damage: float, id: int) -> void:
	if not targets.has(target_id): return
	var caster: ZorxSkillRuntime = casters[id]
	caster.actor.hp = sim.fighters[id].hp
	var target: ZorxSkillTarget = targets[target_id]
	target.hp = sim.fighters[target_id].hp
	var context: Dictionary = Build.basic_stats(builds[id])
	var equipment_scale: float = sim.fighters[id].stat("ATK") / maxf(1.0,float(Build.config().get("reference_atk",20)))
	context.burn_damage_mul = float(context.get("burn_damage_mul",1))*equipment_scale
	context.bleed_damage_mul = float(context.get("bleed_damage_mul",1))*equipment_scale
	context.equipment_scale = equipment_scale
	context.owner_id = id
	context.skill_id = "basic_attack"
	context.origin_cast_id = -sim.tick_count - 1
	context.statuses = ["burn"] if "all_hits_burn" in context.get("events", []) else []
	if target.statuses.has("bleed") and "blood_leech" in context.get("events", []) and damage > 0:
		caster.blood_heals = caster.blood_heals.filter(func(entry): return caster.clock-float(entry.at)<1.0)
		var used := 0.0
		for entry in caster.blood_heals: used += float(entry.amount)
		var healing := minf(caster.actor.max_hp*0.01,maxf(0.0,caster.actor.max_hp*0.03-used))
		caster.actor.heal(healing)
		caster.blood_heals.append({"at":caster.clock,"amount":healing})
		sim.fighters[id].hp = caster.actor.hp
	for status in context.statuses: target.apply_status(status, context)
	if target.hp <= 0 and not target.dead:
		target.dead = true
		context.base_kill = true
		context.burning = target.statuses.has("burn")
		context.shocked = target.statuses.has("shock")
		context.status_snapshot = target.statuses.duplicate(true)
		target.died.emit(target, context)
		target.clear_statuses()

func _sync_targets() -> void:
	for id in targets.keys():
		if not sim.fighters.has(id):
			var old = targets[id]
			for caster in casters.values(): caster.targets.erase(old)
			targets.erase(id)
			casters.erase(id)
			builds.erase(id)
			_base_stats.erase(id)
	for id in sim.fighters:
		var fighter = sim.fighters[id]
		if not targets.has(id):
			var target := ZorxSkillTarget.new()
			target.entity_id = id
			target.damage_filter = _filter_damage.bind(id)
			target.hit_allowed = _hit_allowed.bind(id)
			target.damaged.connect(_damaged.bind(id))
			target.died.connect(_died.bind(id))
			targets[id] = target
			for owner_id in casters:
				if sim.fighters[owner_id].team != fighter.team: casters[owner_id].connect_target(target)
		var target: ZorxSkillTarget = targets[id]
		target.position = sim.bodies[id].position
		target.max_hp = fighter.max_hp()
		target.hp = fighter.hp
		target.dead = not fighter.is_alive()

func before_tick() -> void:
	_sync_targets()
	for id in casters:
		var caster: ZorxSkillRuntime = casters[id]
		caster.actor.position = sim.bodies[id].position
		caster.actor.hp = sim.fighters[id].hp
		if caster.actor.hp <= 0: caster._cancel_on_death()
		elif targets[id].movement_multiplier() <= 0:
			caster.pending = caster.pending.filter(func(event):return event.get("started",false))
			caster.jobs = caster.jobs.filter(func(job):return job.kind != "release" or int(job.data.get("pulse",0)) > 0)
			caster.cast_until = caster.clock
			caster.cast_pose.clear()
			caster.movements.clear()
			caster.actor.invulnerable = false
		caster.obstacles.assign(sim.world.solids)
		caster.movement_bounds = AABB(Vector3(-sim.world.half_width,-1000,-sim.world.half_depth), Vector3(sim.world.half_width*2,2000,sim.world.half_depth*2))
		var base: Dictionary = _base_stats.get(id,sim.fighters[id].stats)
		sim.fighters[id].stats.HP = float(base.get("HP",100)) * float(caster.actor.passive_stats.get("hp_max_mul",1))
		caster.actor.base_max_hp = float(base.get("HP",100))
		caster.actor.max_hp = sim.fighters[id].max_hp()

func cast(id: int, slot: int, aim: Vector3) -> String:
	if not casters.has(id) or slot < 0 or slot > 3: return "invalid_skill_slot"
	var fighter = sim.fighters[id]
	if not fighter.is_alive() or fighter.incapacitated or fighter.state != fighter.State.IDLE: return "cannot_cast"
	var build: Dictionary = builds[id]
	if Build.start_for(fighter.style) != build.start: return "weapon_tree_mismatch"
	var row: Dictionary = build.skills[slot]
	var cost := float(Build.config().stamina.get(row.skill, 0))
	if fighter.energy < cost: return "not_enough_stamina"
	var stats := Build.calculate(build, slot)
	var scale: float = fighter.stat("ATK") / maxf(1.0,float(Build.config().get("reference_atk",20)))
	stats.damage = float(stats.damage) * scale
	stats.burn_damage_mul = float(stats.get("burn_damage_mul",1)) * scale
	stats.bleed_damage_mul = float(stats.get("bleed_damage_mul",1)) * scale
	stats.equipment_scale = scale
	stats.owner_id = id
	stats.skill_id = row.skill  # rides along in every hit context: picks the impact tier and the event's move
	stats.crit_chance = minf(1.0,float(stats.get("crit_chance",0))+fighter.stat("CRIRATE") / 100.0)
	stats.crit_multiplier = fighter.stat("CRIDMG", 150.0) / 100.0
	preload("res://logic/skill_tree_effects.gd").upgrade_skill(fighter, stats)  # tree skill_upgrade, before the race mods (skill-tree.md 3.6)
	var race_refusal: String = preload("res://logic/race_passives.gd").modify_skill_stats(fighter, stats)  # race skill_mod (GDD races 4.4)
	if not race_refusal.is_empty(): return race_refusal
	var caster: ZorxSkillRuntime = casters[id]
	var skill: ZorxSkillData = load(Build.ROOT + "skills/" + row.skill + ".tres")
	var problem := caster.request_cast(skill, stats, sim.bodies[id].position, aim)
	if not problem.is_empty(): return problem
	var facing := Vector2(aim.x-sim.bodies[id].position.x,aim.z-sim.bodies[id].position.z)
	if facing.length_squared() > .00001: fighter.direction = preload("res://logic/combat.gd").direction_from(facing)
	fighter.energy -= cost
	if preload("res://logic/race_passives.gd").pay_skill_hp(sim, id, fighter) > 0.0: caster.actor.hp = fighter.hp  # Blood Rite
	fighter.energy_wait = int(sim.combat.rules.energy_regen_delay_ticks)
	caster.cast_pose = {"skill":row.skill, "family":fighter.style, "started":caster.clock, "windup":maxf(0,caster.cast_until-caster.clock), "aim":aim}
	preload("res://logic/relic_effects.gd").skill_cast(fighter)
	sim.events.append({"type":"skill_cast", "player":id, "skill":row.skill, "slot":slot, "effect":str(row.get("effect","")), "start":caster.clock, "release":caster.cast_until, "aim":aim})
	return ""

func advance() -> void:
	for id in targets:
		targets[id].position = sim.bodies[id].position
		targets[id].hp = sim.fighters[id].hp
		targets[id].dead = not sim.fighters[id].is_alive()
	for target in targets.values(): target.advance(1.0 / 60.0)
	for id in casters:
		var caster: ZorxSkillRuntime = casters[id]
		caster.actor.position = sim.bodies[id].position
		caster.actor.hp = sim.fighters[id].hp
		caster.advance(1.0 / 60.0)
		if sim.runs.has(id):
			for skill in caster.cooldowns: sim.runs[id].skill_cooldowns[skill] = maxf(0,float(caster.cooldowns[skill])-caster.clock)
		sim.bodies[id].position = caster.actor.position
		sim.fighters[id].hp = caster.actor.hp
		for target in caster.targets:
			if sim.bodies.has(target.entity_id): sim.bodies[target.entity_id].position = target.position
	publish_views()

func publish_views() -> void:
	for id in targets:
		if not sim.fighters.has(id): continue
		var target: ZorxSkillTarget = targets[id]
		var statuses := {}
		for status in target.statuses:
			var entries = target.statuses[status]
			statuses[status] = {"stacks":entries.size(), "left":float(entries[-1].left)} if entries is Array else {"stacks":int(entries.get("stacks",1)), "left":float(entries.left)}
		var view := {"statuses":statuses, "movement":target.movement_multiplier(), "vulnerability":target._vulnerability()}
		if casters.has(id):
			var caster: ZorxSkillRuntime = casters[id]
			var slots: Array = []
			for row in builds[id].skills:
				slots.append({"skill":row.skill, "left":maxf(0,float(caster.cooldowns.get(row.skill,0))-caster.clock), "cost":float(Build.config().stamina.get(row.skill,0))})
			var basic := Build.basic_stats(builds[id])
			view.merge({"clock":caster.clock, "slots":slots, "pose":caster.cast_pose.duplicate(true), "casting":caster.is_casting(), "moving":not caster.movements.is_empty(), "shield":caster.actor.shield,
				"heal_allowed":float(caster.actor.passive_stats.get("heal_allowed",1)), "dodge_cd_mul":float(caster.actor.passive_stats.get("dodge_cd_mul",1)), "move_mul":caster.actor.multiplier("move_speed_mul"), "attack_mul":float(basic.get("damage",1))*caster.actor.multiplier("buff_damage_mul"), "range_mul":float(basic.get("range_mul",1)), "projectile_speed_mul":float(basic.get("projectile_speed",1)), "crit_bonus":float(basic.get("crit_chance",0)), "passives":basic.get("events",[])})
			view["visuals"] = _visuals(caster)
			view["motion"] = preload("res://logic/skills/motion_prediction.gd").capsule(caster,builds[id])
			if not preload("res://logic/race_passives.gd").owns_gauge(sim.fighters[id]): sim.fighters[id].gauge = 0  # retired gauge, unless race ultimates own it (GDD races 3.10.6)
		if sim.fighters[id].style=="bow":view["shot_aim"]=sim.fighters[id].shot_direction
		sim.fighters[id].skill_view = view

func _visuals(caster: ZorxSkillRuntime) -> Array:
	var result: Array = []
	for shot in caster.projectiles:
		var skill: String = shot.skill.id
		if shot.stats.behavior in ["storm","parry"]: skill = "piercing_shot"
		elif shot.stats.behavior == "shatter": skill = "ice_lance"
		result.append({"id":"shot:"+str(shot.visual_id),"skill":skill,"phase":"projectile","position":shot.position+Vector3.UP*.65,"direction":shot.direction,"scale":Vector3.ONE})
	for entity in caster.constructs:
		var factor: float = maxf(.1,float(entity.stats.get("radius",1)))
		result.append({"id":"construct:"+str(entity.source_id),"skill":entity.skill.id,"phase":"persistent","position":entity.position,"direction":entity.dir,"scale":Vector3(factor,1,factor)})
	for zone in caster.zones:
		var length: float = zone.start.distance_to(zone.end)
		result.append({"id":"zone:"+str(zone.born),"skill":zone.skill.id,"phase":"persistent","position":(zone.start+zone.end)*.5,"direction":(zone.end-zone.start).normalized(),"scale":Vector3(float(zone.stats.trail_width)*float(zone.stats.radius),1,maxf(.1,length*.5))})
	for buff in caster.actor.buffs:
		var skill: String = {"shield":"blood_shield","armor":"frost_armor","cry":"war_cry"}.get(buff.id,"")
		if not skill.is_empty(): result.append({"id":"buff:"+str(buff.id),"skill":skill,"phase":"persistent","position":caster.actor.position,"direction":Vector3.FORWARD,"scale":Vector3.ONE})
	return result.slice(0,64)

func _filter_damage(amount: float, context: Dictionary, id: int) -> float:
	var fighter = sim.fighters[id]
	if fighter.invulnerable_left > 0 or fighter.eliminated: return 0.0
	var reduction: float = fighter.stat("DEF") / (fighter.stat("DEF") + float(sim.combat.rules.defense_constant))
	var incoming: float = amount * (1.0 - reduction)
	if casters.has(id):
		var source: ZorxSkillTarget = targets.get(int(context.get("owner_id",0)))
		incoming = casters[id].actor.receive_attack(incoming, source, false)
	return incoming - fighter.absorb(incoming)  # race shield (GDD races 4.3) after the skill actor's own shield

func _hit_allowed(id: int) -> bool:
	return sim != null and sim.fighters.has(id) and sim.fighters[id].is_alive() and not preload("res://logic/combat.gd").is_invulnerable(sim.fighters[id],sim.combat)

func on_dodge(id: int) -> void:
	if not casters.has(id): return
	var context := Build.basic_stats(builds[id])
	if not "dodge_chill" in context.get("events",[]): return
	context.owner_id = id
	var caster: ZorxSkillRuntime = casters[id]
	for target in caster._in_radius(sim.bodies[id].position,3):
		target.apply_status("chill",context)
		target.apply_status("chill",context)
	caster._spawn_visual(load(Build.ROOT+"skills/ice_lance.tres"),sim.bodies[id].position,1)

func _damaged(amount: float, kind: String, context: Dictionary, id: int) -> void:
	if _restoring: return
	sim.fighters[id].hp = targets[id].hp
	if casters.has(id): casters[id].actor.hp = targets[id].hp
	var dot: bool = kind in ["burn","bleed"]
	var attacker := int(context.get("owner_id",0))
	var crit := bool(context.get("critical",false))
	var periodic: bool = dot or bool(context.get("periodic",false))
	var tier := impact_tier(str(context.get("skill_id","")), kind)
	if amount > 0.0 and not periodic: _apply_hitstop(id, attacker, tier, crit)
	sim.events.append({"type":"skill_dot" if dot else "skill_hit", "attacker":attacker, "target":id, "damage":amount, "effect":kind, "pos":targets[id].position, "crit":crit, "dir":Vector2.ZERO, "move":"skill:" + str(context.get("skill_id","")), "ranged":true,
		"impact":tier, "periodic":periodic, "gems":context.get("gem_ids",[]).duplicate()})

## How hard a skill's blow lands (0 none .. 3 heavy), from data/skill_system/integration.json "impact".
static func impact_tier(skill_id: String, kind: String = "hit") -> int:
	var impact: Dictionary = Build.config().get("impact", {})
	if kind == "reflect": return int(impact.get("reflect_tier", 1))
	return int(impact.get("tiers", {}).get(skill_id, impact.get("default_tier", 1)))

## Hit-stop for a landed skill blow, the same freeze weapon hits use (logic/combat.gd sets it on
## both sides). Takes the larger of what is already pending so AoE/multi-hits never stack it.
func _apply_hitstop(target_id: int, attacker_id: int, tier: int, crit: bool) -> void:
	var impact: Dictionary = Build.config().get("impact", {})
	var on_target: Array = impact.get("target_hitstop", [])
	var on_caster: Array = impact.get("caster_hitstop", [])
	var cap := int(impact.get("max_hitstop", 10))
	if tier <= 0 or tier >= on_target.size(): return
	var ticks := mini(cap, int(on_target[tier]) + (int(impact.get("crit_hitstop_bonus", 0)) if crit else 0))
	var target = sim.fighters.get(target_id)
	if target != null and ticks > 0 and target.is_alive(): target.hitstop = maxi(target.hitstop, ticks)
	if attacker_id == target_id or tier >= on_caster.size(): return
	var caster = sim.fighters.get(attacker_id)
	if caster != null and int(on_caster[tier]) > 0: caster.hitstop = maxi(caster.hitstop, mini(cap, int(on_caster[tier])))

func _died(_target: ZorxSkillTarget, context: Dictionary, id: int) -> void:
	if sim.fighters.has(id) and not context.get("base_kill",false):
		sim.fighters[id].state = sim.fighters[id].State.DEAD
		sim.fighters[id].move_id = ""
	if not _restoring and not context.get("base_kill", false): sim.events.append({"type":"killed", "target":id, "by":int(context.get("owner_id",0))})

func save() -> Dictionary:
	var target_states := {}
	var caster_states := {}
	for id in targets: target_states[id] = Checkpoint.pack_value(Codec.fields(targets[id], ["global_position", "damage_filter", "hit_allowed"]))
	for id in casters: caster_states[id] = Checkpoint.capture(casters[id])
	return {"builds":builds.duplicate(true), "base_stats":_base_stats.duplicate(true), "targets":target_states, "casters":caster_states}

func restore(saved: Dictionary, reuse_existing: bool = false) -> void:
	_restoring = true
	# Rollback restores values into the existing graph. Rebuilding casters every tick
	# reparses builds and reconnects signals; only topology/build changes require it.
	var reusable: bool = reuse_existing and builds == saved.get("builds",{}) and casters.keys() == saved.get("casters",{}).keys() and targets.keys() == saved.get("targets",{}).keys()
	if not reusable:
		targets.clear()
		casters.clear()
		builds.clear()
		_sync_targets()
		for id in saved.get("builds", {}): attach(id, saved.builds[id])
	for id in saved.get("targets", {}):
		if targets.has(id): Codec.apply_fields(targets[id], Checkpoint.unpack_value(saved.targets[id], targets))
	for id in saved.get("casters", {}):
		if casters.has(id): Checkpoint.restore(casters[id], saved.casters[id], targets)
	_base_stats = saved.get("base_stats",_base_stats).duplicate(true)
	publish_views()
	_restoring = false

func dispose() -> void:
	# Prediction graphs are short-lived across scene/reconnect. Targets and casters
	# bind callbacks to each other; explicitly release those cycles on retirement.
	if sim != null:
		for id in casters:
			if sim.fighters.has(id):
				sim.fighters[id].skill_hit_filter = Callable()
				sim.fighters[id].skill_base_hit = Callable()
	for target in targets.values():
		target.damage_filter = Callable()
		target.hit_allowed = Callable()
	var objects: Array = targets.values() + casters.values()
	for caster in casters.values():
		if caster.actor != null: objects.append(caster.actor)
	for object in objects:
		for signal_info in object.get_signal_list():
			for connection in object.get_signal_connection_list(signal_info.name):
				if object.is_connected(signal_info.name, connection.callable):
					object.disconnect(signal_info.name, connection.callable)
	targets.clear(); casters.clear(); builds.clear(); _base_stats.clear(); _sim_ref = null
