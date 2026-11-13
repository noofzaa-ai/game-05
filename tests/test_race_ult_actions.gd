extends RefCounted
## Race ultimate engine (design/gdd/races-and-classes.md 3.6, 3.10.3-3.10.5, 4.2-4.6, 5): the cast pipeline (start,
## wind-up, resolve, lost on stun/death, ultimate_cast), the actions zone and skill_refresh, burst v2 fields,
## revive, split heal/shield and the ultimate caps, the new statuses, and the pilot's use conditions.
## Ultimate blocks are set on the fighters here (the race files get theirs race by race).
const RaceTest := preload("res://tests/test_race_passives.gd")
const F := preload("res://tests/online_fixture.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const Codec := preload("res://logic/state_codec.gd")
const Fighter := preload("res://logic/fighter.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const RaceUltimates := preload("res://logic/race_ultimates.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const SimInput := preload("res://logic/sim_input.gd")


func run(ctx) -> void:
	_statuses(ctx)
	_cast_pipeline(ctx)
	_lost_cast(ctx)
	_burst_v2(ctx)
	_zone(ctx)
	_skill_refresh(ctx)
	_revive(ctx)
	_split_and_caps(ctx)
	_use_rules(ctx)
	_checkpoint_mid_cast(ctx)


static func enemies(sim) -> Array:
	var ids: Array = sim.fighters.keys().filter(func(id): return sim.fighters[id].team == "enemy" and sim.fighters[id].is_alive())
	ids.sort()
	return ids


## Parks every enemy far apart, then places the listed ones at `at + offset`.
static func place(sim, at: Vector3, offsets: Dictionary) -> void:
	for e in enemies(sim):
		sim.bodies[e].position = at + Vector3(40.0 + 6.0 * float(e), 0, 40.0)
	for e in offsets:
		sim.bodies[e].position = at + offsets[e]


## Gives fighter `id` this ultimate (and its move), full gauge, plain round stats.
static func arm(sim, id: int, ult: Dictionary, atk: float = 100.0) -> void:
	var f = sim.fighters[id]
	f.race_state["ultimate"] = ult
	f.race_state["race"] = "test"
	RaceUltimates.register_move(sim.combat, f)
	f.stats["ATK"] = atk
	f.stats["CRIDMG"] = 150.0
	f.stat_mods.clear()
	f.gauge = 100.0
	f.state = Fighter.State.IDLE
	f.move_id = ""
	sim.bodies[id].grounded = true  # (a fresh test squad has not landed yet; the GDD needs a grounded caster)


## Starts and resolves fighter `id`'s ultimate right away (the wind-up skipped).
static func cast_now(sim, id: int) -> Array:
	sim.events.clear()
	var ok := RaceUltimates.start(sim, id)
	var f = sim.fighters[id]
	f.move_frame = float(sim.combat.moves[RaceUltimates.move_id(f)]["startup"])
	RacePassives.step(sim)
	return sim.events.duplicate() if ok else []


## Class skills v2 (logic/class_skills/engine.gd): the card's skill ids, set/read cooldowns in seconds.
static func skills_of(sim, id: int) -> Array:
	return sim.fighters[id].skill_state.get("skills", [])


static func set_cd(sim, id: int, skills: Array, seconds: float) -> void:
	for skill in skills:
		sim.fighters[id].skill_state["cd"][str(skill)] = sim.tick_count + int(round(seconds * 60.0))


static func cd_left(sim, id: int, skill: String) -> float:
	return preload("res://logic/class_skills/engine.gd").cooldown_left(sim, sim.fighters[id], skill)


static func zero_def(sim) -> void:
	for e in enemies(sim):
		sim.fighters[e].stats["DEF"] = 0.0
		sim.fighters[e].stats["HP"] = 100000.0
		sim.fighters[e].hp = 100000.0


func _statuses(ctx) -> void:
	var combat = preload("res://logic/combat_data_loader.gd").load_default()
	ctx.check("new statuses: valor ATK/DEF +20%, unbowed ATK +30% DEF +40%, recital SKILL_DMG +30% STAREGEN +40 (360 ticks)",
		combat.errors.is_empty() and combat.effects["valor"]["stats"]["ATK"]["mul"] == 0.2 and combat.effects["unbowed"]["stats"]["DEF"]["mul"] == 0.4
		and combat.effects["recital"]["stats"]["SKILL_DMG"]["mul"] == 0.3 and int(combat.effects["recital"]["duration"]) == 360)
	var mage := Fighter.new()
	mage.stats = {"HP": 750.0}
	mage.race_state = {"effects": [], "pseudo": {}}
	mage.stat_mods = {"SKILL_DMG": {"add": 0.0, "mul": 0.3}}
	ctx.check("recital's SKILL_DMG reaches the skill_mod hook (x1.3)", is_equal_approx(RacePassives.skill_dmg(mage), 0.3))


func _cast_pipeline(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	arm(sim, 2, {"name": "Test Ult", "cast_ticks": 30, "recover_ticks": 20, "actions": [{"action": "apply_status", "status": "valor", "target": "allies_all", "duration": 360}]})
	var gs = sim.fighters[2]
	gs.gauge = 99.0
	ctx.check("cast: not ready below a full gauge", not RaceUltimates.ready(sim, 2))
	gs.gauge = 100.0
	gs.effects["stun"] = {"left": 50, "stacks": 1, "age": 0, "dps": 0.0, "source": 1}
	preload("res://logic/effects.gd").refresh(gs, sim.combat)
	ctx.check("cast: not ready while stunned", not RaceUltimates.ready(sim, 2))
	gs.effects.clear()
	preload("res://logic/effects.gd").refresh(gs, sim.combat)
	sim.events.clear()
	var press := SimInput.new()
	press.ultimate = true
	sim.set_input(2, press)
	sim.tick()
	ctx.check("cast: the press starts the synthetic move, gauge -> 0", gs.move_id == "test_greatsword_ultimate" and gs.gauge == 0.0 and gs.state == Fighter.State.ATTACK)
	ctx.check("cast: attack_started (client, class_sim) and ultimate_cast events", sim.events.any(func(e): return e["type"] == "attack_started" and e["move"] == "test_greatsword_ultimate")
		and sim.events.any(func(e): return e["type"] == "ultimate_cast" and e["name"] == "Test Ult"))
	ctx.check("cast: the old weapon ultimate never starts", not gs.move_id.begins_with("greatsword_"))
	sim.set_input(2, SimInput.new())
	var resolved_at := -1
	for t in 40:
		sim.tick()
		if resolved_at < 0 and sim.events.any(func(e): return e["type"] == "race_ult_resolved"):
			resolved_at = t + 1
	ctx.check("cast: the actions resolve at the end of the wind-up (~30 ticks: %d)" % resolved_at, resolved_at >= 28 and resolved_at <= 33)
	ctx.check("cast: valor on every ally", [1, 2, 3].all(func(id): return sim.fighters[id].effects.has("valor")))


## A wind-up is lost when the caster is stunned or killed (3.10.3 step 4); hits alone do not stagger it.
func _lost_cast(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	arm(sim, 2, {"name": "Test", "cast_ticks": 40, "recover_ticks": 10, "actions": [{"action": "apply_status", "status": "valor", "target": "self"}]})
	var gs = sim.fighters[2]
	RaceUltimates.start(sim, 2)
	var foe: int = enemies(sim)[0]
	gs.direction = Vector2i(1, 0)
	sim.fighters[foe].direction = Vector2i(1, 0)
	preload("res://logic/combat.gd").apply_hit(foe, 2, str(sim.combat.styles[sim.fighters[foe].style]["ground_light"]), sim.fighters, sim.bodies, sim.combat, sim.rng, sim.events)
	ctx.check("wind-up: a plain hit does not stagger the caster", gs.state == Fighter.State.ATTACK and gs.move_id == "test_greatsword_ultimate")
	gs.effects["stun"] = {"left": 60, "stacks": 1, "age": 0, "dps": 0.0, "source": 1}
	preload("res://logic/effects.gd").refresh(gs, sim.combat)
	sim.events.clear()
	for t in 50:
		sim.tick()
	ctx.check("wind-up: stunned -> the cast is lost, gauge stays 0, no valor", not gs.effects.has("valor") and gs.gauge < 5.0 and not gs.race_state.has("ult"))
	var g := RaceTest.squad(["human", "human", "human"])
	arm(g.sim, 2, {"name": "Test", "cast_ticks": 40, "recover_ticks": 10, "actions": [{"action": "apply_status", "status": "valor", "target": "allies_all"}]})
	RaceUltimates.start(g.sim, 2)
	g.sim.fighters[2].state = Fighter.State.DEAD
	g.sim.events.clear()
	RacePassives.step(g.sim)
	ctx.check("wind-up: killed -> lost (race_ult_lost), nothing resolves", g.sim.events.any(func(e): return e["type"] == "race_ult_lost") and not g.sim.fighters[1].effects.has("valor"))


func _burst_v2(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	zero_def(sim)
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[2].position
	place(sim, at, {foes[0]: Vector3(1.0, 0, 0), foes[1]: Vector3(-1.0, 0, 0)})
	# Fury (4.6): Unbowed burst 100% at 60% HP -> 160%.
	arm(sim, 2, {"name": "Fury", "cast_ticks": 1, "actions": [{"action": "burst", "center": "self", "radius": 3.0, "atk_mul": 1.0, "fury": true}]})
	sim.fighters[2].hp = sim.fighters[2].max_hp() * 0.6
	var out := cast_now(sim, 2)
	var hits: Array = out.filter(func(e): return e["type"] == "race_burst_hit")
	ctx.check("formula 4.6: fury burst 100%% at 60%% HP -> 160 per target (%s)" % [hits.map(func(e): return e["damage"])], hits.size() == 2 and hits.all(func(e): return is_equal_approx(float(e["damage"]), 160.0) and bool(e["ultimate"])))
	# Repeat hits: 3 x 110%, 24 ticks apart, stun on the 3rd only.
	arm(sim, 2, {"name": "Masterstroke", "cast_ticks": 1, "actions": [{"action": "burst", "center": "self", "radius": 3.5, "atk_mul": 1.1, "hits": 3, "interval_ticks": 24, "last_status": "stun"}]})
	sim.fighters[2].hp = sim.fighters[2].max_hp()
	for e in foes:
		sim.fighters[e].control_immune_left = 0
	cast_now(sim, 2)
	var count := 0
	var stunned_early := false
	for t in 60:
		sim.tick_count += 1
		sim.events.clear()
		RacePassives.step(sim)
		count += sim.events.filter(func(e): return e["type"] == "race_burst_hit" and int(e["target"]) == foes[0]).size()
		if t < 40 and sim.fighters[foes[0]].effects.has("stun"):
			stunned_early = true
	ctx.check("burst hits: 3 hits total on each enemy (%d more after the first)" % count, count == 2)
	ctx.check("burst last_status: stun only on the 3rd hit", not stunned_early and sim.fighters[foes[0]].effects.has("stun"))
	# Target-HP bonus + chain on kill: lowest HP% target, x2 below 30%, each kill shoots the next, never twice.
	var g := RaceTest.squad(["human", "human", "elf"])
	var gsim = g.sim
	zero_def(gsim)
	var gf := enemies(gsim)
	place(gsim, gsim.bodies[3].position, {gf[0]: Vector3(5, 0, 0), gf[1]: Vector3(6, 0, 1), gf[2]: Vector3(7, 0, -1)})
	gsim.fighters[gf[0]].hp = 100.0
	gsim.fighters[gf[1]].hp = 150.0
	gsim.fighters[gf[2]].hp = 50000.0
	arm(gsim, 3, {"name": "Executioner", "cast_ticks": 1, "actions": [{"action": "burst", "target": "enemy_lowest_hp_pct", "cast_range": 12.0, "radius": 0.6, "pick": "nearest", "atk_mul": 2.2, "bonus_target_below_hp": 0.3, "bonus_mul": 2.0, "chain_on_kill": 3}]})
	out = cast_now(gsim, 3)
	hits = out.filter(func(e): return e["type"] == "race_burst_hit")
	ctx.check("Executioner: 220%% x2 on a target below 30%% = 440 (%s)" % [hits.map(func(e): return e["damage"])], not hits.is_empty() and is_equal_approx(float(hits[0]["damage"]), 440.0))
	ctx.check("Executioner: each kill chains to the next lowest-HP%% enemy, never the same one (%d hits)" % hits.size(),
		hits.size() == 3 and hits.map(func(e): return int(e["target"])) == [gf[0], gf[1], gf[2]])
	# force_crit + target boss_or_highest_hp: CRIDMG applies with no crit roll.
	var c := RaceTest.squad(["human", "human", "human"])
	zero_def(c.sim)
	var cf := enemies(c.sim)
	place(c.sim, c.sim.bodies[3].position, {cf[0]: Vector3(8, 0, 0)})
	arm(c.sim, 3, {"name": "Called Shot", "cast_ticks": 1, "actions": [{"action": "burst", "target": "enemy_highest_hp", "cast_range": 12.0, "radius": 0.6, "pick": "nearest", "atk_mul": 4.5, "force_crit": true, "status": "sunder"}]})
	hits = cast_now(c.sim, 3).filter(func(e): return e["type"] == "race_burst_hit")
	ctx.check("Called Shot: 450%% x CRIDMG 150%% = 675 at 8 m (%s)" % [hits.map(func(e): return e["damage"])], hits.size() == 1 and is_equal_approx(float(hits[0]["damage"]), 675.0) and c.sim.fighters[cf[0]].effects.has("sunder"))
	# delayed: each hit leaves a detonation 120 ticks later at that spot.
	var d := RaceTest.squad(["human", "human", "human"])
	zero_def(d.sim)
	var df := enemies(d.sim)
	place(d.sim, d.sim.bodies[3].position, {df[0]: Vector3(6, 0, 0)})
	arm(d.sim, 3, {"name": "Glyph", "cast_ticks": 1, "actions": [{"action": "burst", "pick": "spread", "cast_range": 12.0, "radius": 0.6, "atk_mul": 0.7, "delayed": {"ticks": 120, "atk_mul": 0.6, "radius": 1.5, "status": "sunder"}}]})
	cast_now(d.sim, 3)
	var detonated := -1
	for t in 130:
		d.sim.tick_count += 1
		d.sim.events.clear()
		RacePassives.step(d.sim)
		if detonated < 0 and d.sim.events.any(func(e): return e["type"] == "race_burst_hit" and is_equal_approx(float(e["damage"]), 60.0)):
			detonated = t + 1
	ctx.check("delayed glyph: 60%% detonation + sunder 120 ticks later (%d)" % detonated, detonated == 120 and d.sim.fighters[df[0]].effects.has("sunder"))


func _zone(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	zero_def(sim)
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[2].position
	place(sim, at, {foes[0]: Vector3(1.0, 0, 0)})
	# Ragnarok Whirl: follow, 3 s, pulse every 0.5 s 55%, +0.5 s per kill (max +2 s).
	arm(sim, 2, {"name": "Whirl", "cast_ticks": 1, "actions": [{"action": "zone", "center": "self", "radius": 3.0, "duration_ticks": 180, "every_ticks": 30, "follow": true,
		"extend_on_kill_ticks": 30, "extend_max_ticks": 120, "pulse": [{"action": "burst", "center": "zone", "radius": 3.0, "atk_mul": 0.55}]}]})
	cast_now(sim, 2)
	var pulses := 1
	sim.bodies[2].position += Vector3(10, 0, 0)  # it follows the caster: the foe is out of it now
	var hits_after_move := 0
	for t in 200:
		sim.tick_count += 1
		sim.events.clear()
		RacePassives.step(sim)
		pulses += sim.events.filter(func(e): return e["type"] == "race_zone_pulse").size()
		hits_after_move += sim.events.filter(func(e): return e["type"] == "race_burst_hit").size()
	ctx.check("zone: 3 s with a pulse every 0.5 s = 6 pulses (%d)" % pulses, pulses == 6)
	ctx.check("zone follow: it moves with the caster", hits_after_move == 0)
	# Kill extension, capped.
	var g := RaceTest.squad(["human", "human", "human"])
	var gsim = g.sim
	var gf := enemies(gsim)
	for e in gf:
		gsim.fighters[e].stats["DEF"] = 0.0
		gsim.fighters[e].hp = 1.0
	place(gsim, gsim.bodies[2].position, {})
	arm(gsim, 2, {"name": "Whirl", "cast_ticks": 1, "actions": [{"action": "zone", "center": "self", "radius": 3.0, "duration_ticks": 180, "every_ticks": 30, "follow": true,
		"extend_on_kill_ticks": 30, "extend_max_ticks": 120, "pulse": [{"action": "burst", "center": "zone", "radius": 3.0, "atk_mul": 0.55}]}]})
	cast_now(gsim, 2)
	var ends_at := -1
	for t in 400:
		gsim.tick_count += 1
		if t % 30 == 5 and t < 300:  # an enemy walks in and dies on the next pulse
			for e in gf:
				if gsim.fighters[e].is_alive():
					gsim.bodies[e].position = gsim.bodies[2].position + Vector3(1, 0, 0)
					break
		gsim.events.clear()
		RacePassives.step(gsim)
		if ends_at < 0 and gsim.events.any(func(e): return e["type"] == "race_zone_end"):
			ends_at = t + 1
	ctx.check("zone extend: kills add 0.5 s each, capped at +2 s (ends at %d, cap 300)" % ends_at, ends_at == 300)
	# on_end: shield allies for 30% of the zone's damage, split, cap 15% max HP each (Arcane Singularity).
	var s := RaceTest.squad(["human", "human", "human"])
	zero_def(s.sim)
	var sf := enemies(s.sim)
	place(s.sim, s.sim.bodies[3].position, {sf[0]: Vector3(4, 0, 0)})
	arm(s.sim, 3, {"name": "Singularity", "cast_ticks": 1, "actions": [{"action": "zone", "center": "densest", "cast_range": 9.0, "radius": 4.0, "duration_ticks": 60, "every_ticks": 30,
		"pulse": [{"action": "burst", "center": "zone", "radius": 4.0, "atk_mul": 1.0}],
		"on_end": [{"action": "shield", "target": "allies_all", "fraction_of": "damage", "fraction": 0.30, "split": true, "cap_max_hp": 0.15, "duration_ticks": 600}]}]}, 10.0)  # ATK 10 = a starter card (HP scale 100)
	for id in [1, 2, 3]:
		s.sim.fighters[id].clear_shield()
	cast_now(s.sim, 3)
	for t in 70:
		s.sim.tick_count += 1
		s.sim.events.clear()
		RacePassives.step(s.sim)
	# 2 pulses x 10 = 20 damage; 30% = 6 over 3 allies = 2 each (cap 15% of ~100 HP not reached).
	ctx.check("zone on_end: 30%% of 20 zone damage split over 3 allies = 2 each (%s)" % [[1, 2, 3].map(func(id): return s.sim.fighters[id].shield)],
		[1, 2, 3].all(func(id): return is_equal_approx(s.sim.fighters[id].shield, 2.0)))
	# densest center falls back to the caster when nobody is in range (5).
	var e := RaceTest.squad(["human", "human", "human"])
	place(e.sim, e.sim.bodies[3].position, {})
	arm(e.sim, 3, {"name": "Z", "cast_ticks": 1, "actions": [{"action": "zone", "center": "densest", "cast_range": 9.0, "radius": 4.0, "duration_ticks": 60, "every_ticks": 30, "pulse": [{"action": "burst", "center": "zone", "radius": 4.0, "atk_mul": 1.0}]}]})
	var zone_events: Array = cast_now(e.sim, 3).filter(func(ev): return ev["type"] == "race_zone")
	ctx.check("zone at densest with nobody in range: at the caster", zone_events.size() == 1 and Vector3(zone_events[0]["pos"]).is_equal_approx(e.sim.bodies[3].position))


func _skill_refresh(ctx) -> void:
	# Formula 4.4: remaining' = max(0, remaining x (1 - fraction) - seconds).
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	var skills: Array = skills_of(sim, 1)
	for i in 4:
		set_cd(sim, 1, [skills[i]], 10.0 * float(i + 1))  # 10, 20, 30, 40 s left
	arm(sim, 1, {"name": "Call", "cast_ticks": 1, "actions": [{"action": "skill_refresh", "target": "allies_all", "fraction": 0.5}]})
	cast_now(sim, 1)
	var left: Array = skills.map(func(s): return snappedf(cd_left(sim, 1, s), 0.01))
	ctx.check("skill_refresh fraction 0.5: 10/20/30/40 s -> 5/10/15/20 s (%s)" % [left], left == [5.0, 10.0, 15.0, 20.0])
	arm(sim, 1, {"name": "Flat", "cast_ticks": 1, "actions": [{"action": "skill_refresh", "target": "self", "seconds": 1.0, "cap_seconds": 2.5}]})
	var ctx2 := {"ultimate": true, "points": {}, "picked": {}}
	for i in 4:
		RaceUltimates.skill_refresh(sim, 1, {"action": "skill_refresh", "target": "self", "seconds": 1.0, "cap_seconds": 2.5}, ctx2)
	left = skills.map(func(s): return snappedf(cd_left(sim, 1, s), 0.01))
	ctx.check("skill_refresh seconds 1 per hit, cap 2.5 s per cast (%s)" % [left], left == [2.5, 7.5, 12.5, 17.5])
	ctx.check("skill_refresh never goes below 0", RaceUltimates.skill_refresh(sim, 1, {"action": "skill_refresh", "target": "self", "fraction": 1.0}, {"ultimate": true}) and skills.all(func(s): return cd_left(sim, 1, s) <= 0.0))
	sim.fighters[1].skill_state = {}
	sim.skill_system = null
	ctx.check("skill_refresh with no skills: nothing to refresh (5)", not RaceUltimates.skill_refresh(sim, 1, {"action": "skill_refresh", "target": "self", "fraction": 1.0}, {}))


func _revive(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	sim.enable_coop([1, 2, 3])
	var down = sim.fighters[1]
	var event := {"type": "killed", "target": 1}
	preload("res://logic/coop.gd").down(sim, 1, event)
	arm(sim, 3, {"name": "Rebirth", "cast_ticks": 1, "actions": [{"action": "heal", "target": "ally_downed", "fraction_of": "max_hp", "fraction": 0.35},
		{"action": "heal", "target": "allies_all", "fraction_of": "max_hp", "fraction": 0.20}]})
	sim.fighters[2].hp = sim.fighters[2].max_hp() * 0.5
	var out := cast_now(sim, 3)
	ctx.check("revive: a downed ally stands up at 35%% max HP (%.2f) with the co-op invulnerability" % (down.hp / down.max_hp()),
		down.is_alive() and absf(down.hp / down.max_hp() - 0.35 - 0.20) < 0.001 and down.invulnerable_left > 0 and out.any(func(e): return e["type"] == "revived" and int(e["player"]) == 1))
	ctx.check("revive: the rest of the ultimate still runs (20% heal)", absf(sim.fighters[2].hp / sim.fighters[2].max_hp() - 0.70) < 0.001)
	preload("res://logic/coop.gd").down(sim, 1, {"type": "killed", "target": 1})
	arm(sim, 3, sim.fighters[3].race_state["ultimate"])
	cast_now(sim, 3)
	ctx.check("revive: once per ally per wave", down.state == Fighter.State.DOWNED)
	sim._waves_released += 1
	arm(sim, 3, sim.fighters[3].race_state["ultimate"])
	cast_now(sim, 3)
	ctx.check("revive: allowed again next wave", down.is_alive())
	down.state = Fighter.State.DEAD
	ctx.check("revive: a fully dead ally is never a target", RaceUltimates.targets_v2(sim, 3, "ally_downed", {}, {}).is_empty())


func _split_and_caps(ctx) -> void:
	# 4.2 split: Thornbloom 4 x 250 = 1000 dealt, 40% = 400 over 3 allies = 133 each, cap 12% of 1000 -> 120.
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	for id in [1, 2, 3]:
		sim.fighters[id].stats["HP"] = 1000.0
		sim.fighters[id].hp = 100.0
		sim.fighters[id].race_state["pseudo"] = {}
		sim.fighters[id].race_state["effects"] = []
	var action := {"action": "heal", "target": "allies_all", "fraction_of": "damage", "fraction": 0.40, "split": true, "cap_max_hp": 0.12}
	RacePassives.run_action(sim, 1, action, {"ultimate": true, "damage": 1000.0, "points": {}, "picked": {}})
	ctx.check("formula 4.2 split: 400 over 3 allies capped at 120 each (%s)" % [[1, 2, 3].map(func(id): return sim.fighters[id].hp)], [1, 2, 3].all(func(id): return is_equal_approx(sim.fighters[id].hp, 220.0)))
	# Ultimate heals skip the per-second passive cap (6%); passive heals keep it.
	for id in [1, 2, 3]:
		sim.fighters[id].hp = 100.0
	RacePassives.run_action(sim, 1, {"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.20}, {"damage": 0.0})
	var passive_heal: float = sim.fighters[1].hp - 100.0
	RacePassives.run_action(sim, 2, {"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.20}, {"ultimate": true, "points": {}, "picked": {}})
	ctx.check("4.2: passive heal capped at 6%%/s (%.0f), ultimate heal exempt (%.0f)" % [passive_heal, sim.fighters[2].hp - 100.0], is_equal_approx(passive_heal, 60.0) and is_equal_approx(sim.fighters[2].hp, 300.0))
	# 4.3: an ultimate shield may reach 50% max HP; a passive one stops at 30%.
	sim.fighters[1].clear_shield()
	RacePassives.run_action(sim, 1, {"action": "shield", "target": "self", "fraction_of": "source_max_hp", "fraction": 0.45}, {"ultimate": true, "points": {}, "picked": {}})
	sim.fighters[2].clear_shield()
	RacePassives.run_action(sim, 2, {"action": "shield", "target": "self", "fraction_of": "source_max_hp", "fraction": 0.45}, {})
	ctx.check("4.3: ultimate shield cap 50%% (%.0f), passive 30%% (%.0f)" % [sim.fighters[1].shield, sim.fighters[2].shield], is_equal_approx(sim.fighters[1].shield, 450.0) and is_equal_approx(sim.fighters[2].shield, 300.0))
	# self_hp_cost (Blood Moon): 15% of current HP first, not damage (no hurt, no gauge).
	arm(sim, 3, {"name": "Blood Moon", "cast_ticks": 1, "self_hp_cost": 0.15, "min_hp": 0.25, "actions": [{"action": "apply_status", "status": "rage", "target": "self"}]})
	sim.fighters[3].hp = 800.0
	var out := cast_now(sim, 3)
	ctx.check("self_hp_cost: 15%% of 800 = 120 paid, no hurt (hp %.0f)" % sim.fighters[3].hp, is_equal_approx(sim.fighters[3].hp, 680.0) and out.any(func(e): return e["type"] == "race_hp_cost" and is_equal_approx(float(e["amount"]), 120.0)))
	arm(sim, 3, sim.fighters[3].race_state["ultimate"])
	sim.fighters[3].hp = 200.0
	ctx.check("min_hp: cannot fire below 25%", not RaceUltimates.ready(sim, 3))


func _use_rules(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[2].position
	place(sim, at, {foes[0]: Vector3(1, 0, 0), foes[1]: Vector3(-1, 0, 0)})
	ctx.check("use enemies_near 3 within 3 m: 2 -> holds", not Pilot.use_matches(sim, 2, {"if": "enemies_near", "radius": 3.0, "min": 3}))
	place(sim, at, {foes[0]: Vector3(1, 0, 0), foes[1]: Vector3(-1, 0, 0), foes[2]: Vector3(0, 0, 1)})
	ctx.check("use enemies_near 3 within 3 m: 3 -> fires", Pilot.use_matches(sim, 2, {"if": "enemies_near", "radius": 3.0, "min": 3}))
	ctx.check("use enemies_at_point: 3 within r4 of a point within 9 m", Pilot.use_matches(sim, 3, {"if": "enemies_at_point", "cast_range": 9.0, "radius": 4.0, "min": 3}) == (_flat_d(sim, 3, foes[0]) <= 9.0))
	ctx.check("use and_ally_hurt_below: nobody hurt -> holds", not Pilot.use_matches(sim, 2, {"if": "enemies_near", "radius": 3.0, "min": 3, "and_ally_hurt_below": 0.75}))
	sim.fighters[1].hp = sim.fighters[1].max_hp() * 0.4
	ctx.check("use ally_hurt below 0.5 -> fires", Pilot.use_matches(sim, 3, {"if": "ally_hurt", "below": 0.5}))
	ctx.check("use ally_hurt min_allies 2 -> holds with one hurt", not Pilot.use_matches(sim, 3, {"if": "ally_hurt", "below": 0.5, "min_allies": 2}))
	ctx.check("use squad_hp_below 0.55: average 80% -> holds", not Pilot.use_matches(sim, 3, {"if": "squad_hp_below", "below": 0.55}))
	ctx.check("use self_hurt", Pilot.use_matches(sim, 1, {"if": "self_hurt", "below": 0.5}) and not Pilot.use_matches(sim, 2, {"if": "self_hurt", "below": 0.5}))
	sim.fighters[foes[0]].enemy_type = "goblin_chief"
	ctx.check("use boss_near / elite_near", Pilot.use_matches(sim, 2, {"if": "boss_near", "radius": 3.0}) and Pilot.use_matches(sim, 2, {"if": "elite_near", "radius": 3.0}))
	sim.fighters[foes[0]].hp = sim.fighters[foes[0]].max_hp() * 0.2
	ctx.check("use execute_ready below 30% within 12 m", Pilot.use_matches(sim, 2, {"if": "execute_ready", "range": 12.0, "below": 0.3}))
	ctx.check("use ally_downed: nobody down -> holds", not Pilot.use_matches(sim, 3, {"if": "ally_downed"}))
	# max_hold_ticks: fire anyway after holding a full gauge that long with an enemy in engage range.
	sim.tick_count = 1000
	arm(sim, 2, {"name": "H", "cast_ticks": 1, "actions": [{"action": "apply_status", "status": "valor", "target": "self"}], "use": {"any_of": [{"if": "enemies_near", "radius": 3.0, "min": 9}], "max_hold_ticks": 360}})
	sim.fighters[2].race_state["full_at"] = sim.tick_count - 100
	ctx.check("max_hold_ticks: held 100 of 360 -> waits", not Pilot.wants_ultimate(sim, 2, 1.6))
	sim.fighters[2].race_state["full_at"] = sim.tick_count - 360
	ctx.check("max_hold_ticks: held 360 with an enemy in reach -> fires", Pilot.wants_ultimate(sim, 2, 1.6))
	place(sim, at, {})
	ctx.check("max_hold_ticks: nobody in engage range -> still waits (5)", not Pilot.wants_ultimate(sim, 2, 1.6))
	# The pilot presses ultimate before skills when the rule matches.
	place(sim, at, {foes[0]: Vector3(1, 0, 0)})
	sim.fighters[2].race_state["ultimate"]["use"] = {"any_of": [{"if": "enemies_near", "radius": 3.0, "min": 1}]}
	var input: SimInput = Pilot.decide(sim, f.combat, 2, Pilot.new_memory(1), 0, 0.0)
	ctx.check("pilot: full gauge + matching rule -> presses ultimate", input.ultimate)


func _flat_d(sim, a: int, b: int) -> float:
	var d: Vector3 = sim.bodies[a].position - sim.bodies[b].position
	return Vector2(d.x, d.z).length()


## Mid-cast and mid-zone checkpoint: 300 ticks + restore + more equals uninterrupted.
func _checkpoint_mid_cast(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	var foes := enemies(sim)
	place(sim, sim.bodies[2].position, {foes[0]: Vector3(1, 0, 0)})
	arm(sim, 2, {"name": "Z", "cast_ticks": 20, "recover_ticks": 10, "actions": [{"action": "zone", "center": "self", "radius": 3.0, "duration_ticks": 120, "every_ticks": 30, "pulse": [{"action": "burst", "center": "zone", "radius": 3.0, "atk_mul": 0.2}]},
		{"action": "burst", "center": "self", "radius": 3.0, "atk_mul": 0.1, "hits": 3, "interval_ticks": 40}]})
	var press := SimInput.new()
	press.ultimate = true
	sim.set_input(2, press)
	sim.tick()
	sim.set_input(2, SimInput.new())
	for t in 30:
		sim.tick()
	var copy = Sim.new(World.new(), f.combat, F.rng(1))
	copy.item_rules = f.rules
	copy.loot_data = f.loot
	ctx.check("mid-cast checkpoint restores", copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(sim.snapshot()["checkpoint"]))}, f.camp))
	ctx.check("mid-cast checkpoint: zones and jobs are saved", not copy.fighters[2].race_state.get("zones", []).is_empty() and not copy.fighters[2].race_state.get("jobs", []).is_empty())
	for t in 150:
		sim.tick()
		copy.tick()
	ctx.check("mid-cast checkpoint: 30 + restore + 150 equals uninterrupted", Codec.digest(copy.snapshot()) == Codec.digest(sim.snapshot()))
