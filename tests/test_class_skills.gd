extends RefCounted
## Class skills v2 (design/gdd/class-skills.md): data/clip validation (acceptance 1-2), the numbers of section 4
## (acceptance 4), events (5), the engine features E1-E16 and every skill's pilot rule (positive and negative scene, 3).
## A bare sim: no walls, one grunt type with the stats set per test (DEF 0 unless a test needs it), crit off.
const SkillData := preload("res://logic/class_skills/skill_data.gd")
const Skills := preload("res://logic/class_skills/engine.gd")
const UseRules := preload("res://logic/class_skills/use_rules.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const CombatLoader := preload("res://logic/combat_data_loader.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const Codec := preload("res://logic/state_codec.gd")


func run(ctx) -> void:
	_data(ctx)
	_timing(ctx)
	_shield_rush(ctx)
	_iron_guard(ctx)
	_intercept(ctx)
	_breaker_slam(ctx)
	_reaping_arc(ctx)
	_crater_leap(ctx)
	_hook_sweep(ctx)
	_battle_trance(ctx)
	_heartseeker(ctx)
	_pinning_shot(ctx)
	_rapid_fire(ctx)
	_vault_shot(ctx)
	_arcane_orb(ctx)
	_repulse_nova(ctx)
	_starfall(ctx)
	_warding_veil(ctx)
	_lost_cast(ctx)
	_tree_and_race_hooks(ctx)
	_checkpoint(ctx)


# ---------------------------------------------------------------- fixture

## Players 1..n of `classes` at x = 0, -2, ...; enemies 10.. of `enemy_type` parked far away. ATK 100, DEF 0, crit 0.
static func world(classes: Array, enemy_count: int = 4, enemy_type: String = "goblin") -> Sim:
	var w := World.new()
	w.half_width = 60.0
	w.half_depth = 60.0
	var sim := Sim.new(w, CombatLoader.load_default(), _rng())
	for i in classes.size():
		var id := i + 1
		sim.add_player(id, Vector3(-2.0 * i, 0, 0), {"ATK": 100, "DEF": 0, "HP": 1000, "CRIRATE": 0, "STAMINA": 100}, str(preload("res://logic/card_deck.gd").class_data(str(classes[i])).get("weapon", "fists")))
		sim.bodies[id].grounded = true
		if not str(classes[i]).is_empty():
			Skills.attach(sim, id, str(classes[i]))
			sim.fighters[id].race_state["class"] = str(classes[i])
	for k in enemy_count:
		var e := 10 + k
		sim.add_enemy(e, Vector3(40.0 + 5.0 * k, 0, 40.0), enemy_type)
		sim.fighters[e].stats["DEF"] = 0.0
		sim.fighters[e].stats["HP"] = 100000.0
		sim.fighters[e].hp = 100000.0
		sim.fighters[e].stats["EFFECT_RES"] = 0.0
		sim.fighters[e].max_poise = 0.0
	return sim


static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	return r


static func put(sim, id: int, pos: Vector3) -> void:
	sim.bodies[id].position = pos
	sim.bodies[id].velocity = Vector3.ZERO


## Ticks only the class-skill engine (no AI, no basic attacks): `n` times.
static func step(sim, n: int) -> Array:
	var seen: Array = []
	for _i in n:
		sim.events.clear()
		Skills.step(sim)
		sim.tick_count += 1
		seen.append_array(sim.events)
	return seen


static func of(events: Array, kind: String, extra: Dictionary = {}) -> Array:
	return events.filter(func(e):
		if str(e.get("type", "")) != kind:
			return false
		for key in extra:
			if e.get(key) != extra[key]:
				return false
		return true)


static func hits(events: Array, skill: String, target: int = -1) -> Array:
	return of(events, "skill_hit").filter(func(e): return str(e.get("skill", "")) == skill and (target < 0 or int(e["target"]) == target))


static func lost(sim, id: int) -> float:
	return 100000.0 - sim.fighters[id].hp


# ---------------------------------------------------------------- data

func _data(ctx) -> void:
	var data = SkillData.load_default()
	ctx.check("class skill data loads with no errors %s" % [data.errors], data.errors.is_empty())
	var all: Array = []
	for c in ["sword_shield", "greatsword", "longbow", "magic"]:
		ctx.check("class %s has 4 skills" % c, data.class_skills(c).size() == 4)
		all.append_array(data.class_skills(c))
	ctx.check("16 different skill ids", all.size() == 16 and all.filter(func(x): return all.count(x) == 1).size() == 16)
	ctx.check("no old skill id is reused", all.filter(func(x): return SkillData.OLD_IDS.has(x)).is_empty())
	ctx.check("the GDD 3.6 class lists", data.class_skills("sword_shield") == ["shield_rush", "iron_guard", "intercept", "breaker_slam"]
		and data.class_skills("greatsword") == ["reaping_arc", "crater_leap", "hook_sweep", "battle_trance"]
		and data.class_skills("longbow") == ["heartseeker_shot", "pinning_shot", "rapid_fire", "vault_shot"]
		and data.class_skills("magic") == ["arcane_orb", "repulse_nova", "starfall", "warding_veil"])
	var no_vfx: Array = all.filter(func(x): return str(data.skill(x).get("vfx", "")) != "class_skill/" + x)
	ctx.check("every skill has its vfx key class_skill/<id> %s" % [no_vfx], no_vfx.is_empty())
	# a wrong clip name or time fails the validation (acceptance 2)
	var bad = SkillData.new()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SkillData.PATH))
	raw["skills"]["shield_rush"]["motion"]["segs"][0][0] = "no_such_clip"
	raw["skills"]["arcane_orb"]["motion"]["segs"][0][2] = 99.0
	raw["skills"]["starfall"]["stats"]["stun"] = 0.3
	raw["skills"]["starfall"]["kind"] = "laser"
	bad.parse(raw)
	ctx.check("a wrong clip name fails validation", bad.errors.any(func(e): return e.contains("no_such_clip")))
	ctx.check("a window past the clip length fails validation", bad.errors.any(func(e): return e.contains("arcane_orb") and e.contains("outside")))
	ctx.check("an unknown kind fails validation", bad.errors.any(func(e): return e.contains("laser")))


func _timing(ctx) -> void:
	var data = SkillData.load_default()
	var expect := {"shield_rush": [[0.40], 1.31], "intercept": [[0.67], 1.52], "breaker_slam": [[1.26], 1.98], "reaping_arc": [[0.65], 1.37],
		"crater_leap": [[1.28], 1.81], "hook_sweep": [[0.62], 1.32], "battle_trance": [[0.54], 1.21], "heartseeker_shot": [[1.20], 1.72],
		"pinning_shot": [[0.90], 1.55], "rapid_fire": [[0.69, 0.94, 1.19, 1.44], 1.96], "vault_shot": [[1.32], 1.84], "arcane_orb": [[0.41], 1.38],
		"repulse_nova": [[0.81], 1.72], "starfall": [[1.08], 1.80], "warding_veil": [[1.10], 1.75]}
	for skill in expect:
		var t: Dictionary = data.skill(skill)["timing"]
		var rel: Array = t["releases"]
		var ok: bool = rel.size() == expect[skill][0].size() and absf(float(t["end"]) - float(expect[skill][1])) <= 0.015
		for i in mini(rel.size(), expect[skill][0].size()):
			ok = ok and absf(float(rel[i]) - float(expect[skill][0][i])) <= 0.015
		ctx.check("%s release %s / total %.2f s match GDD 3.2-3.5" % [skill, rel.map(func(x): return snappedf(x, 0.01)), t["end"]], ok)
	var travel := {"shield_rush": [0.0, 0.40], "intercept": [0.17, 0.67], "breaker_slam": [1.03, 1.17], "reaping_arc": [0.10, 0.58],
		"crater_leap": [0.56, 1.06], "hook_sweep": [0.15, 0.68], "vault_shot": [0.17, 0.57]}
	for skill in travel:
		var tr: Array = data.skill(skill)["timing"]["travel"]
		ctx.check("%s travel frames %s = skill t %s" % [skill, tr.map(func(x): return snappedf(x, 0.01)), travel[skill]],
			tr.size() == 2 and absf(float(tr[0]) - travel[skill][0]) <= 0.015 and absf(float(tr[1]) - travel[skill][1]) <= 0.015)
	ctx.check("hook sweep pull at skill t 0.08", absf(float(data.skill("hook_sweep")["timing"]["pull"][0]) - 0.08) <= 0.015)
	var guard: Dictionary = data.skill("iron_guard")["timing"]
	ctx.check("iron guard counter: release 0.40 s after it starts, 1.39 s long", absf(float(guard["counter_release"]) - 0.40) <= 0.015 and absf(float(guard["counter_length"]) - 1.39) <= 0.015)


# ---------------------------------------------------------------- sword_shield

func _shield_rush(ctx) -> void:
	var sim := world(["sword_shield", "longbow"])
	put(sim, 2, Vector3(4, 0, 0))
	sim.fighters[2].hp = 300.0
	put(sim, 10, Vector3(5.5, 0, 0))  # on the hurt archer, 5.5 m from the tank
	ctx.check("GDD 3.7 priority: Intercept (defensive) goes before Shield Rush when both qualify", UseRules.pick(sim, 1, 10).get("skill", "") == "intercept")
	var choice := UseRules.choose(sim, 1, "shield_rush", 10)
	ctx.check("S1 pilot: peel target attacking an ally 2-7 m away -> Shield Rush on it", int(choice.get("target", -1)) == 10)
	ctx.check("S1 cast starts", Skills.cast(sim, 1, "shield_rush", choice) == "")
	var mid := step(sim, 12)
	var x_mid: float = sim.bodies[1].position.x
	var ev := step(sim, 20)
	ctx.check("S1 dashes only in its travel frames, to 1 m from the target (x %.2f -> %.2f)" % [x_mid, sim.bodies[1].position.x], x_mid > 0.5 and x_mid < 4.5 and absf(sim.bodies[1].position.x - 4.5) < 0.05)
	ctx.check("S1 70%% ATK = 70 (%s)" % [lost(sim, 10)], is_equal_approx(lost(sim, 10), 70.0))
	ctx.check("S1 stuns 0.8 s", sim.fighters[10].effects.has("stun") and int(sim.fighters[10].effects["stun"]["left"]) <= 48 and int(sim.fighters[10].effects["stun"]["left"]) > 30)
	ctx.check("S1 fires skill_cast once and one skill_hit", of(mid + ev, "skill_cast").size() == 1 and hits(mid + ev, "shield_rush").size() == 1)
	var neg := world(["sword_shield"])
	put(neg, 10, Vector3(6, 0, 0))
	ctx.check("S1 pilot: no hurt ally and target 6 m away -> no Shield Rush", UseRules.choose(neg, 1, "shield_rush", 10).is_empty())
	put(neg, 10, Vector3(2.5, 0, 0))
	ctx.check("S1 pilot: current target within 3 m -> Shield Rush", not UseRules.choose(neg, 1, "shield_rush", 10).is_empty())
	# stops on the first enemy in the path
	var path := world(["sword_shield"])
	put(path, 10, Vector3(6, 0, 0))
	put(path, 11, Vector3(3, 0, 0.1))
	Skills.cast(path, 1, "shield_rush", {"target": 10})
	step(path, 40)
	ctx.check("S1 stops on the first enemy in its path and hits it", lost(path, 11) > 0.0 and lost(path, 10) == 0.0 and absf(path.bodies[1].position.x - 2.0) < 0.1)


func _iron_guard(ctx) -> void:
	var sim := world(["sword_shield"])
	put(sim, 10, Vector3(1, 0, 0))
	put(sim, 11, Vector3(-1, 0, 0))
	ctx.check("S2 pilot: 2 enemies near but not attacking -> no Iron Guard", UseRules.choose(sim, 1, "iron_guard", 10).is_empty())
	for e in [10, 11]:
		sim.fighters[e].state = Fighter.State.ATTACK
	sim.fighters[10].direction = Vector2i(-1, 0)
	sim.fighters[11].direction = Vector2i(1, 0)
	ctx.check("S2 pilot: 2 enemies within 3 m attacking this card -> Iron Guard", not UseRules.choose(sim, 1, "iron_guard", 10).is_empty())
	sim.fighters[11].direction = Vector2i(-1, 0)
	ctx.check("S2 pilot: one of them swings the other way -> no Iron Guard", UseRules.choose(sim, 1, "iron_guard", 10).is_empty())
	sim.fighters[11].direction = Vector2i(1, 0)
	for e in [10, 11]:
		sim.fighters[e].state = Fighter.State.IDLE  # (a test-made attack state has no move)
	var lone := world(["sword_shield"])
	put(lone, 10, Vector3(5, 0, 0))
	lone.fighters[1].hp = 100.0
	ctx.check("S2 pilot: never with no enemy within 3 m (even hurt)", UseRules.choose(lone, 1, "iron_guard", 10).is_empty())
	put(lone, 10, Vector3(2, 0, 0))
	ctx.check("S2 pilot: own HP below 50% with an enemy within 3 m", not UseRules.choose(lone, 1, "iron_guard", 10).is_empty())
	ctx.check("S2 cast", Skills.cast(sim, 1, "iron_guard") == "")
	step(sim, 2)
	var taken := Skills.incoming(1, 10, 100.0, true, sim.fighters, sim.bodies, sim.combat, [], sim.tick_count)
	ctx.check("S2 takes half damage (%s)" % taken, is_equal_approx(taken, 50.0))
	for k in 6:
		Skills.incoming(1, 10, 10.0, true, sim.fighters, sim.bodies, sim.combat, [], sim.tick_count)
		step(sim, 20)
	ctx.check("S2 counters capped at 2 per stance (PO default), 50%% ATK each (%s)" % lost(sim, 10), is_equal_approx(lost(sim, 10), 100.0))
	Skills.incoming(1, 11, 10.0, false, sim.fighters, sim.bodies, sim.combat, [], sim.tick_count)
	step(sim, 2)
	ctx.check("S2 ranged hits are not countered", lost(sim, 11) == 0.0)
	ctx.check("S2 the caster cannot act during the stance", Skills.busy(sim.fighters[1]))
	step(sim, 240)
	ctx.check("S2 the stance ends after 3 s + exit", not Skills.busy(sim.fighters[1]) and sim.fighters[1].skill_state["stance"].is_empty())
	ctx.check("S2 after it ends damage is normal", is_equal_approx(Skills.incoming(1, 10, 100.0, true, sim.fighters, sim.bodies, sim.combat, [], sim.tick_count), 100.0))


func _intercept(ctx) -> void:
	var sim := world(["sword_shield", "longbow"])
	put(sim, 2, Vector3(6, 0, 0))
	sim.fighters[2].hp = 500.0
	put(sim, 10, Vector3(7, 0, 0))
	var pick := UseRules.choose(sim, 1, "intercept", 10)
	ctx.check("S3 pilot: ally below 60% and attacked within 8 m -> Intercept on it", int(pick.get("target", -1)) == 2)
	sim.fighters[1].hp = 300.0
	ctx.check("S3 pilot: not when the tank is below 40%", UseRules.choose(sim, 1, "intercept", 10).is_empty())
	sim.fighters[1].hp = 1000.0
	sim.fighters[2].hp = 700.0
	ctx.check("S3 pilot: all allies above 60% -> no cast", UseRules.choose(sim, 1, "intercept", 10).is_empty())
	sim.fighters[2].hp = 500.0
	ctx.check("S3 cast", Skills.cast(sim, 1, "intercept", pick) == "")
	var ev := step(sim, 50)
	ctx.check("S3 leaps to 1 m from the ally (x %.2f)" % sim.bodies[1].position.x, absf(sim.bodies[1].position.x - 5.0) < 0.05)
	ctx.check("S3 links the ally and taunts on landing", not sim.fighters[2].skill_state.get("link", {}).is_empty() and not of(ev, "race_taunt").is_empty())
	# formula 4.2: D = 200 raw, tank DEF rule 30% (DEF 42.857), tank in Iron Guard: tank takes 28
	sim.fighters[1].stats["DEF"] = 300.0 / 7.0
	sim.fighters[1].skill_state["stance"] = {"until": sim.tick_count + 100, "taken_mul": 0.5, "counter": 0.5, "left": 0, "icd": 18, "next": 0, "stats": {}}
	var events: Array = []
	var ally_takes := Skills.incoming(2, 10, 200.0, true, sim.fighters, sim.bodies, sim.combat, events, sim.tick_count)
	ctx.check("4.2 example: tank takes 28 of a 200 blow (%s)" % [1000.0 - sim.fighters[1].hp], is_equal_approx(1000.0 - sim.fighters[1].hp, 28.0))
	ctx.check("4.2 the ally takes 60%% of its own share (%s)" % ally_takes, is_equal_approx(ally_takes, 120.0))
	ctx.check("redirected damage is a skill_hit on the tank (gauge taken / hurt)", events.any(func(e): return e["type"] == "skill_hit" and int(e["target"]) == 1 and str(e["effect"]) == "redirect"))
	put(sim, 2, Vector3(30, 0, 0))
	step(sim, 1)
	ctx.check("S3 the link breaks past 10 m", sim.fighters[2].skill_state.get("link", {}).is_empty())
	# an ally who dies during the leap: no link, cooldown spent
	var dead := world(["sword_shield", "longbow"])
	put(dead, 2, Vector3(6, 0, 0))
	dead.fighters[2].hp = 500.0
	Skills.cast(dead, 1, "intercept", {"target": 2})
	dead.fighters[2].state = Fighter.State.DEAD
	step(dead, 50)
	ctx.check("S3 ally dies mid-leap: no link, cooldown spent", dead.fighters[2].skill_state.get("link", {}).is_empty() and Skills.cooldown_left(dead, dead.fighters[1], "intercept") > 0.0)


func _breaker_slam(ctx) -> void:
	var sim := world(["sword_shield"])
	put(sim, 10, Vector3(1.5, 0, 0))
	put(sim, 11, Vector3(-2, 0, 1))
	put(sim, 12, Vector3(4, 0, 0))
	ctx.check("S4 pilot: 2+ enemies within 3 m", not UseRules.choose(sim, 1, "breaker_slam", 10).is_empty())
	Skills.cast(sim, 1, "breaker_slam", {"target": 10})
	var before: float = sim.bodies[1].position.x
	var early := step(sim, 60)
	ctx.check("S4 does not move before its hop frames", is_equal_approx(sim.bodies[1].position.x, before))
	var ev := step(sim, 70)
	ctx.check("S4 90%% ATK to all within 3 m + weaken (%s, %s, far %s)" % [lost(sim, 10), lost(sim, 11), lost(sim, 12)],
		is_equal_approx(lost(sim, 10), 90.0) and is_equal_approx(lost(sim, 11), 90.0) and lost(sim, 12) == 0.0 and sim.fighters[10].effects.has("weaken"))
	ctx.check("S4 hops about 0.3 m forward", absf(sim.bodies[1].position.x - before - 0.3) < 0.05)
	var neg := world(["sword_shield"])
	put(neg, 10, Vector3(1.5, 0, 0))
	ctx.check("S4 pilot: 1 grunt within 3 m -> no cast", UseRules.choose(neg, 1, "breaker_slam", 10).is_empty())


# ---------------------------------------------------------------- greatsword

func _reaping_arc(ctx) -> void:
	var sim := world(["greatsword"])
	sim.fighters[1].race_state = {"race": "test", "class": "greatsword", "effects": [{"src": "signature", "effect": {"type": "cleave", "per_extra": 0.15, "max_bonus": 0.45}}]}
	put(sim, 10, Vector3(2, 0, 0))
	put(sim, 11, Vector3(1.5, 0, 1.5))
	put(sim, 12, Vector3(1.5, 0, -1.5))
	put(sim, 13, Vector3(-2, 0, 0))  # behind: outside the 240 degree arc
	ctx.check("G1 pilot: 2+ enemies in the arc", not UseRules.choose(sim, 1, "reaping_arc", 10).is_empty())
	Skills.cast(sim, 1, "reaping_arc", {"target": 10})
	var ev := step(sim, 45)
	ctx.check("4.1 example: 3 enemies at ATK 100 -> 182 each (%s %s %s)" % [lost(sim, 10), lost(sim, 11), lost(sim, 12)],
		is_equal_approx(lost(sim, 10), 182.0) and is_equal_approx(lost(sim, 11), 182.0) and is_equal_approx(lost(sim, 12), 182.0))
	ctx.check("G1 the enemy behind is outside the 240 degree arc", lost(sim, 13) == 0.0)
	ctx.check("G1 fires one heavy event per cast", of(ev, "skill_heavy").size() == 1)
	var races: Array = []
	for e in ev:
		races.append_array(RacePassives.race_events(1, sim.fighters[1], e, sim.fighters))
	ctx.check("G1 = one race heavy_hit per cast", races.count("heavy_hit") == 1)
	var neg := world(["greatsword"])
	put(neg, 10, Vector3(2, 0, 0))
	ctx.check("G1 pilot: one grunt -> hold", UseRules.choose(neg, 1, "reaping_arc", 10).is_empty())
	neg.fighters[1].skill_state["cd"]["reaping_arc"] = neg.tick_count - 181
	ctx.check("G1 pilot: held 3 s -> cast on whatever is in front", not UseRules.choose(neg, 1, "reaping_arc", 10).is_empty())


func _crater_leap(ctx) -> void:
	var sim := world(["greatsword"])
	put(sim, 10, Vector3(5, 0, 0))
	put(sim, 11, Vector3(5.5, 0, 1))
	put(sim, 12, Vector3(5.5, 0, -1))
	var choice := UseRules.choose(sim, 1, "crater_leap", 10)
	ctx.check("G2 pilot: densest point with 3+ enemies", choice.get("point") is Vector3)
	Skills.cast(sim, 1, "crater_leap", choice)
	step(sim, 34)
	var still: float = sim.bodies[1].position.x
	var ev := step(sim, 50)
	ctx.check("G2 stands still in the wind-up, then leaps to the point", absf(still) < 0.01 and absf(sim.bodies[1].position.x - 5.0) < 0.6)
	ctx.check("G2 160%% ATK + stagger to everything within 2.5 m (%s)" % [lost(sim, 11)], is_equal_approx(lost(sim, 10), 160.0) and is_equal_approx(lost(sim, 11), 160.0) and sim.fighters[11].effects.has("stun"))
	var neg := world(["greatsword"])
	put(neg, 10, Vector3(2, 0, 0))
	put(neg, 11, Vector3(2.5, 0, 0.5))
	ctx.check("G2 pilot: 2 enemies within 3 m -> no leap", UseRules.choose(neg, 1, "crater_leap", 10).is_empty())
	put(neg, 10, Vector3(5, 0, 0))
	put(neg, 11, Vector3(5.5, 0, 0.5))
	ctx.check("G2 pilot: 2 enemies more than 3 m away -> gap closer", not UseRules.choose(neg, 1, "crater_leap", 10).is_empty())


func _hook_sweep(ctx) -> void:
	var sim := world(["greatsword"], 4)
	put(sim, 10, Vector3(4.5, 0, 0))
	put(sim, 11, Vector3(0, 0, 4))
	put(sim, 12, Vector3(-3.5, 0, 0))
	ctx.check("G3 pilot: 3+ within 5 m, fewer than 2 within 2.5 m", not UseRules.choose(sim, 1, "hook_sweep", 10).is_empty())
	Skills.cast(sim, 1, "hook_sweep", {"target": 10})
	step(sim, 6)
	ctx.check("4.3 example: an enemy at 4.5 m pulled 2 -> 2.5 m (%.2f)" % sim.bodies[10].position.x, absf(sim.bodies[10].position.x - 2.5) < 0.01)
	step(sim, 40)
	ctx.check("G3 90%% ATK + slow on the pulled pack (%s)" % lost(sim, 10), lost(sim, 10) == 90.0 and sim.fighters[10].effects.has("slow"))
	var pull := world(["greatsword"], 2, "goblin_chief")
	put(pull, 10, Vector3(1.2, 0, 0))
	Skills.pull(pull, 1, Vector3.ZERO, 5.0, 2.0, 1.0)
	ctx.check("G3 never pulls past 1 m, bosses/elites are not pulled", absf(pull.bodies[10].position.x - 1.2) < 0.001)
	var small := world(["greatsword"])
	put(small, 10, Vector3(1.2, 0, 0))
	Skills.pull(small, 1, Vector3.ZERO, 5.0, 2.0, 1.0)
	ctx.check("4.3 pull stops at 1 m from the caster", absf(small.bodies[10].position.x - 1.0) < 0.001)
	var neg := world(["greatsword"])
	put(neg, 10, Vector3(1, 0, 0))
	put(neg, 11, Vector3(-1, 0, 0))
	put(neg, 12, Vector3(4, 0, 0))
	ctx.check("G3 pilot: pack already tight -> no Hook Sweep", UseRules.choose(neg, 1, "hook_sweep", 10).is_empty())


func _battle_trance(ctx) -> void:
	var sim := world(["greatsword"], 1, "goblin_chief")
	put(sim, 10, Vector3(2, 0, 0))
	var pick := UseRules.pick(sim, 1, 10)
	ctx.check("G4 first when the boss is within 3 m", pick.get("skill", "") == "battle_trance")
	Skills.cast(sim, 1, "battle_trance", pick["choice"])
	step(sim, 40)
	ctx.check("G4 haste + heavy every 2nd swing + no stagger", sim.fighters[1].effects.has("haste") and Skills.heavy_every(sim, sim.fighters[1]) == 2 and Skills.armored(sim.fighters[1], sim.tick_count))
	step(sim, 360)
	ctx.check("G4 ends after 6 s", Skills.heavy_every(sim, sim.fighters[1]) == 0)
	var neg := world(["greatsword"])
	put(neg, 10, Vector3(5, 0, 0))
	ctx.check("G4 pilot: no enemy within 3 m -> no cast", UseRules.choose(neg, 1, "battle_trance", 10).is_empty())


# ---------------------------------------------------------------- longbow

func _heartseeker(ctx) -> void:
	var sim := world(["longbow"], 3)
	sim.add_enemy(20, Vector3(9, 0, 0), "goblin_chief")
	sim.fighters[20].stats["DEF"] = 0.0
	sim.fighters[20].stats["HP"] = 100000.0
	sim.fighters[20].hp = 100000.0
	put(sim, 10, Vector3(3, 0, 0))
	var choice := UseRules.choose(sim, 1, "heartseeker_shot", 10)
	ctx.check("L1 pilot: the boss in range first", int(choice.get("target", -1)) == 20)
	Effects_apply(sim, 20, "sunder")
	sim.fighters[20].stats["DEF"] = 0.0
	sim.fighters[1].stats["CRIRATE"] = -25.0  # crit off for the exact number (+25 from the skill)
	Skills.cast(sim, 1, "heartseeker_shot", choice)
	step(sim, 110)
	ctx.check("L1 260%% ATK x1.5 on a sundered target = 390 (%s)" % lost(sim, 20), is_equal_approx(lost(sim, 20), 390.0))
	var far := world(["longbow"])
	put(far, 10, Vector3(13, 0, 0))
	ctx.check("L1 pilot: nobody within 12 m -> no shot", UseRules.choose(far, 1, "heartseeker_shot", 10).is_empty())


static func Effects_apply(sim, id: int, status: String) -> void:
	preload("res://logic/effects.gd").apply(id, sim.fighters[id], id, sim.fighters[id], {"id": status, "chance": 100.0, "duration": 600}, sim.combat, sim.rng, sim.events)


func _pinning_shot(ctx) -> void:
	var sim := world(["longbow", "magic"])
	put(sim, 2, Vector3(6, 0, 0))
	put(sim, 10, Vector3(7.5, 0, 0))
	put(sim, 11, Vector3(11, 0, 0))
	sim.fighters[2].race_state["class"] = "magic"
	var choice := UseRules.choose(sim, 1, "pinning_shot", 11)
	ctx.check("L2 pilot: the enemy near a back-line ally", int(choice.get("target", -1)) == 10)
	Skills.cast(sim, 1, "pinning_shot", choice)
	step(sim, 95)
	ctx.check("L2 120%% ATK + shock 1.5 s (%s)" % lost(sim, 10), is_equal_approx(lost(sim, 10), 120.0) and sim.fighters[10].effects.has("shock") and sim.fighters[10].rooted)
	ctx.check("L2 pilot: never on a target already shocked", UseRules.choose(sim, 1, "pinning_shot", 11).get("target", -1) != 10)
	var neg := world(["longbow"])
	put(neg, 10, Vector3(9, 0, 0))
	ctx.check("L2 pilot: nobody threatening and nobody closing -> no cast", UseRules.choose(neg, 1, "pinning_shot", 10).is_empty())


func _rapid_fire(ctx) -> void:
	var sim := world(["longbow"])
	put(sim, 10, Vector3(6, 0, 0))
	put(sim, 11, Vector3(8, 0, 0))
	sim.fighters[10].hp = 120.0
	ctx.check("L3 pilot: target within 12 m", not UseRules.choose(sim, 1, "rapid_fire", 10).is_empty())
	Skills.cast(sim, 1, "rapid_fire", {"target": 10})
	var ev := step(sim, 120)
	ctx.check("L3 four skill_hits, no basic hit", hits(ev, "rapid_fire").size() == 4 and of(ev, "hit").is_empty())
	ctx.check("L3 55%% each; target dies after arrow 3, arrow 4 retargets (%s)" % lost(sim, 11), not sim.fighters[10].is_alive() and is_equal_approx(lost(sim, 11), 55.0))
	var gaps: Array = []
	var hit_ticks: Array = []
	for e in of(ev, "class_skill_release"):
		hit_ticks.append(int(e.get("index", 0)))
	ctx.check("L3 4 releases", hit_ticks == [0, 1, 2, 3])


func _vault_shot(ctx) -> void:
	var sim := world(["longbow"])
	put(sim, 10, Vector3(2, 0, 0))
	var choice := UseRules.choose(sim, 1, "vault_shot", 10)
	ctx.check("L4 pilot: an enemy within 3 m", int(choice.get("target", -1)) == 10)
	Skills.cast(sim, 1, "vault_shot", choice)
	step(sim, 9)
	ctx.check("L4 stays still before its travel frames", is_equal_approx(sim.bodies[1].position.x, 0.0))
	step(sim, 30)
	ctx.check("L4 moves 4 m away from the nearest enemy (x %.2f)" % sim.bodies[1].position.x, absf(sim.bodies[1].position.x + 4.0) < 0.05)
	step(sim, 60)
	ctx.check("L4 90%% ATK + slow (%s)" % lost(sim, 10), is_equal_approx(lost(sim, 10), 90.0) and sim.fighters[10].effects.has("slow"))
	var neg := world(["longbow"])
	put(neg, 10, Vector3(5, 0, 0))
	ctx.check("L4 pilot: nobody within 3 m -> no cast", UseRules.choose(neg, 1, "vault_shot", 10).is_empty())


# ---------------------------------------------------------------- magic

func _arcane_orb(ctx) -> void:
	var sim := world(["magic"])
	put(sim, 10, Vector3(6, 0, 0))
	put(sim, 11, Vector3(7, 0, 0.5))
	ctx.check("M1 pilot: 2+ enemies within 2 m of the target", not UseRules.choose(sim, 1, "arcane_orb", 10).is_empty())
	Skills.cast(sim, 1, "arcane_orb", {"target": 10})
	step(sim, 27)
	ctx.check("M1 the orb is in flight after the throw", lost(sim, 10) == 0.0 and not sim.fighters[1].skill_state["jobs"].is_empty())
	step(sim, 40)
	ctx.check("M1 bursts on the first enemy: 100%% to both in r2 (%s %s)" % [lost(sim, 10), lost(sim, 11)], is_equal_approx(lost(sim, 10), 100.0) and is_equal_approx(lost(sim, 11), 100.0))
	var neg := world(["magic"])
	put(neg, 10, Vector3(6, 0, 0))
	ctx.check("M1 pilot: one target -> hold", UseRules.choose(neg, 1, "arcane_orb", 10).is_empty())
	neg.fighters[1].skill_state["cd"]["arcane_orb"] = neg.tick_count - 241
	ctx.check("M1 pilot: held 4 s -> cast anyway", not UseRules.choose(neg, 1, "arcane_orb", 10).is_empty())


func _repulse_nova(ctx) -> void:
	var sim := world(["magic"], 2, "goblin")
	put(sim, 10, Vector3(1.5, 0, 0))
	ctx.check("M2 pilot: 1 enemy within 2.5 m", not UseRules.choose(sim, 1, "repulse_nova", 10).is_empty())
	Skills.cast(sim, 1, "repulse_nova", {"target": 10})
	step(sim, 55)
	ctx.check("M2 90%% ATK, knockback 2.5 m, slow (%s, x %.2f)" % [lost(sim, 10), sim.bodies[10].position.x], is_equal_approx(lost(sim, 10), 90.0) and absf(sim.bodies[10].position.x - 4.0) < 0.01 and sim.fighters[10].effects.has("slow"))
	var neg := world(["magic"])
	put(neg, 10, Vector3(3.5, 0, 0))
	ctx.check("M2 pilot: no enemy within 3 m -> no cast", UseRules.choose(neg, 1, "repulse_nova", 10).is_empty())
	var boss := world(["magic"], 1, "goblin_chief")
	put(boss, 10, Vector3(1.5, 0, 0))
	Skills.cast(boss, 1, "repulse_nova", {"target": 10})
	step(boss, 55)
	ctx.check("M2 bosses take damage and slow but no knockback", lost(boss, 10) > 0.0 and is_equal_approx(boss.bodies[10].position.x, 1.5))


func _starfall(ctx) -> void:
	var sim := world(["magic"])
	put(sim, 10, Vector3(7, 0, 0))
	put(sim, 11, Vector3(7.5, 0, 1))
	put(sim, 12, Vector3(7.5, 0, -1))
	var choice := UseRules.choose(sim, 1, "starfall", 10)
	ctx.check("M3 pilot: 3+ enemies in r2.5 of a point within 9 m", choice.get("point") is Vector3)
	Skills.cast(sim, 1, "starfall", choice)
	var ev := step(sim, 66)
	ctx.check("M3 telegraph at release, no damage yet", of(ev, "class_skill_telegraph").size() == 1 and lost(sim, 10) == 0.0)
	ev = step(sim, 48)
	ctx.check("M3 impact 0.8 s later: 220%% + stagger (%s)" % lost(sim, 10), is_equal_approx(lost(sim, 10), 220.0) and sim.fighters[11].effects.has("stun"))
	var neg := world(["magic"])
	put(neg, 10, Vector3(7, 0, 0))
	put(neg, 11, Vector3(7.5, 0, 1))
	ctx.check("M3 pilot: 2 grunts -> no cast", UseRules.choose(neg, 1, "starfall", 10).is_empty())


func _warding_veil(ctx) -> void:
	var sim := world(["magic", "sword_shield", "longbow"])
	put(sim, 2, Vector3(4, 0, 0))
	put(sim, 3, Vector3(-4, 0, 0))
	sim.fighters[2].hp = 500.0
	sim.fighters[3].hp = 400.0
	put(sim, 10, Vector3(5, 0, 0))
	put(sim, 11, Vector3(4.5, 0, 1))
	put(sim, 12, Vector3(-5, 0, 0))
	var choice := UseRules.choose(sim, 1, "warding_veil", 10)
	ctx.check("M4 pilot: two allies qualify -> the one more enemies attack", int(choice.get("target", -1)) == 2)
	Skills.cast(sim, 1, "warding_veil", choice)
	step(sim, 70)
	ctx.check("M4 veil: damage taken x0.7 + haste", is_equal_approx(Skills.incoming(2, 10, 100.0, true, sim.fighters, sim.bodies, sim.combat, [], sim.tick_count), 70.0) and sim.fighters[2].effects.has("haste"))
	step(sim, 40)
	ctx.check("M4 on cooldown cannot recast", Skills.cast(sim, 1, "warding_veil", choice) == "cooldown")
	sim.fighters[1].skill_state["cd"]["warding_veil"] = 0
	sim.fighters[1].skill_state["cast"] = {}
	Skills.cast(sim, 1, "warding_veil", choice)
	step(sim, 70)
	ctx.check("M4 a second veil refreshes, never stacks", is_equal_approx(Skills.incoming(2, 10, 100.0, true, sim.fighters, sim.bodies, sim.combat, [], sim.tick_count), 70.0))
	var neg := world(["magic", "sword_shield"])
	put(neg, 2, Vector3(4, 0, 0))
	put(neg, 10, Vector3(5, 0, 0))
	ctx.check("M4 pilot: everyone above 60% -> no cast", UseRules.choose(neg, 1, "warding_veil", 10).is_empty())


# ---------------------------------------------------------------- shared rules

func _lost_cast(ctx) -> void:
	var sim := world(["magic"])
	put(sim, 10, Vector3(1.5, 0, 0))
	Skills.cast(sim, 1, "repulse_nova", {"target": 10})
	step(sim, 10)
	Effects_apply(sim, 1, "stun")
	var ev := step(sim, 60)
	ctx.check("stunned before release: the skill is lost, cooldown still runs", lost(sim, 10) == 0.0 and not of(ev, "class_skill_lost").is_empty() and Skills.cooldown_left(sim, sim.fighters[1], "repulse_nova") > 0.0)
	var empty := world(["magic"])
	ctx.check("no valid target: not cast, nothing spent", Skills.cast(empty, 1, "arcane_orb", {"target": -1}) == "no_target" and Skills.cooldown_left(empty, empty.fighters[1], "arcane_orb") == 0.0 and empty.fighters[1].energy == 100.0)


func _tree_and_race_hooks(ctx) -> void:
	var sim := world(["greatsword"])
	sim.fighters[1].race_state = {"race": "test", "class": "greatsword", "effects": [{"src": "race", "effect": {"type": "skill_mod", "damage_mul": 1.5, "cooldown_mul": 0.5}}],
		"tree": {"skills": {"reaping_arc": [{"type": "skill_upgrade", "skill": "reaping_arc", "mods": [{"stat": "radius", "op": 2, "value": 3.75}]}]}}}
	var stats := Skills.cast_stats(sim.fighters[1], "reaping_arc")
	ctx.check("tree skill_upgrade then race skill_mod apply to the new skills (radius %s, dmg %s, cd %s)" % [stats["radius"], stats["damage"], stats["cooldown"]],
		is_equal_approx(float(stats["radius"]), 3.75) and is_equal_approx(float(stats["damage"]), 2.1) and is_equal_approx(float(stats["cooldown"]), 3.0))
	var r := world(["magic"])
	r.fighters[1].skill_state["cd"]["starfall"] = r.tick_count + 600
	var cut := Skills.refresh_cooldowns(r, 1, 0.5, 1.0)
	ctx.check("skill_refresh cuts class-skill cooldowns (10 s -> 4 s)", is_equal_approx(cut, 6.0) and is_equal_approx(Skills.cooldown_left(r, r.fighters[1], "starfall"), 4.0))


func _checkpoint(ctx) -> void:
	var sim := world(["sword_shield", "longbow"])
	put(sim, 2, Vector3(6, 0, 0))
	sim.fighters[2].hp = 500.0
	put(sim, 10, Vector3(7, 0, 0))
	Skills.cast(sim, 1, "intercept", {"target": 2})
	step(sim, 20)
	var snap: Dictionary = Codec.unpack(Codec.pack(sim.fighters[1].skill_state))
	ctx.check("skill_state survives the checkpoint codec unchanged", Codec.digest(snap) == Codec.digest(sim.fighters[1].skill_state))
