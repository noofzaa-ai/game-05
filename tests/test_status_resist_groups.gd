extends RefCounted
## Per-group status accuracy / resistance (Boss 2026-11-19): CTRL_*, DOT_*, DEBUFF_* next to the general
## EFFECT_ACC / EFFECT_RES. Formula: chance = entry + EFFECT_ACC + GROUP_ACC - EFFECT_RES - GROUP_RES, clamped 0..100;
## total resistance >= 100 = immune (no random number used). CTRL_RES >= 100 also stops stagger/knockback/launch.

const Combat := preload("res://logic/combat.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Effects := preload("res://logic/effects.gd")
const Fighter := preload("res://logic/fighter.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const CONTROL := ["stun", "shock", "sleep"]
const DOT := ["burn", "bleed", "poison"]
const DEBUFF := ["slow", "weaken", "sunder", "wound", "curse", "exhaust"]
const BUFF := ["valor", "unbowed", "recital", "rage", "fortify", "haste", "regen", "focus"]

var _data


func run(ctx) -> void:
	_data = CombatDataLoader.load_default()
	ctx.check("status groups: shipped data valid %s" % [_data.errors], _data.is_valid())
	if not _data.is_valid():
		return
	_test_mapping(ctx)
	_test_formula(ctx)
	_test_immunity(ctx)
	_test_isolation(ctx)
	_test_per_effect(ctx)
	_test_unchanged(ctx)
	_test_physical(ctx)
	_test_tree_immune(ctx)
	_test_data(ctx)


func _pair() -> Array:
	var a := Fighter.new()
	a.stats = _data.full_stats({})
	var b := Fighter.new()
	b.stats = _data.full_stats({})
	b.hp = 100.0
	return [a, b]


func _try(source: Fighter, target: Fighter, id: String, chance: float, seed_value: int = 1) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var events: Array[Dictionary] = []
	target.effects.clear()
	target.control_immune_left = 0
	return Effects.apply(1, source, 2, target, {"id": id, "target": "enemy", "on": "hit", "chance": chance, "duration": 0}, _data, rng, events)


## Lands out of `n` rolls.
func _rate(source: Fighter, target: Fighter, id: String, chance: float, n: int = 400) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var events: Array[Dictionary] = []
	var landed := 0
	for i in n:
		target.effects.clear()
		target.control_immune_left = 0
		if Effects.apply(1, source, 2, target, {"id": id, "target": "enemy", "on": "hit", "chance": chance, "duration": 0}, _data, rng, events):
			landed += 1
	return landed


func _test_mapping(ctx) -> void:
	var ok := true
	for id in CONTROL:
		ok = ok and Effects.group_of(_data.effects[id]) == "control"
	for id in DOT:
		ok = ok and Effects.group_of(_data.effects[id]) == "dot"
	for id in DEBUFF:
		ok = ok and Effects.group_of(_data.effects[id]) == "debuff"
	ctx.check("status groups: stun/shock/sleep = control, burn/bleed/poison = dot, the other 6 debuffs = debuff", ok)
	var covered: Array = CONTROL + DOT + DEBUFF + BUFF
	ctx.check("status groups: every shipped effect (%d) is in exactly one test list" % _data.effects.size(), covered.size() == _data.effects.size() and _data.effects.keys().all(func(k): return covered.has(k)))
	var kinds_ok := true
	for id in CONTROL + DOT + DEBUFF:
		kinds_ok = kinds_ok and _data.effects[id]["kind"] == "debuff"
	for id in BUFF:
		kinds_ok = kinds_ok and _data.effects[id]["kind"] == "buff"
	ctx.check("status groups: the three groups are exactly the debuffs; the buffs are outside them", kinds_ok)


func _test_formula(ctx) -> void:
	var groups := {"control": ["stun", "CTRL_ACC", "CTRL_RES"], "dot": ["burn", "DOT_ACC", "DOT_RES"], "debuff": ["slow", "DEBUFF_ACC", "DEBUFF_RES"]}
	for group in groups:
		var id: String = groups[group][0]
		var acc: String = groups[group][1]
		var res: String = groups[group][2]
		var p := _pair()
		p[0].stats[acc] = 100.0
		ctx.check("%s: %s 100 makes a 0%% chance certain" % [group, acc], _try(p[0], p[1], id, 0.0))
		p = _pair()
		p[0].stats["EFFECT_ACC"] = 100.0
		ctx.check("%s: general EFFECT_ACC adds to the group" % group, _try(p[0], p[1], id, 0.0))
		p = _pair()
		p[0].stats["EFFECT_ACC"] = 20.0
		p[0].stats[acc] = 20.0
		ctx.check("%s: entry 60 + EFFECT_ACC 20 + %s 20 lands every time" % [group, acc], _rate(p[0], p[1], id, 60.0, 200) == 200)
		p = _pair()
		p[1].stats["EFFECT_RES"] = 20.0
		p[1].stats[res] = 20.0
		var landed := _rate(p[0], p[1], id, 100.0)
		ctx.check("%s: 100 - EFFECT_RES 20 - %s 20 lands about 60%% (%d/400)" % [group, res, landed], landed > 400 * 0.5 and landed < 400 * 0.7)
		p = _pair()
		p[0].stats[acc] = 30.0
		p[1].stats[res] = 30.0
		ctx.check("%s: %s 30 against %s 30 cancels" % [group, acc, res], _rate(p[0], p[1], id, 100.0, 100) == 100)
		p = _pair()
		p[0].stats[acc] = 40.0
		p[1].stats["EFFECT_RES"] = 40.0
		ctx.check("%s: group ACC 40 against general RES 40 cancels" % group, _rate(p[0], p[1], id, 100.0, 100) == 100)
		p = _pair()
		p[0].stats["EFFECT_ACC"] = 40.0
		p[1].stats[res] = 40.0
		ctx.check("%s: general ACC 40 against group RES 40 cancels" % group, _rate(p[0], p[1], id, 100.0, 100) == 100)
		p = _pair()
		for other in groups:
			if other != group:
				p[1].stats[groups[other][2]] = 99.0
				p[0].stats[groups[other][1]] = 99.0
		ctx.check("%s: the other groups' ACC/RES do not move it" % group, _rate(p[0], p[1], id, 100.0, 100) == 100)
	var q := _pair()
	q[1].stats["DOT_RES"] = 70.0
	ctx.check("dot: entry 70 against DOT_RES 70 = 0%% never lands", _rate(q[0], q[1], "burn", 70.0, 200) == 0)
	q = _pair()
	q[1].stats["EFFECT_RES"] = 100.0
	q[1].stats["CTRL_RES"] = 100.0
	var events: Array[Dictionary] = []
	ctx.check("a buff on self ignores resistance", Effects.apply(2, q[1], 2, q[1], {"id": "haste", "target": "self", "on": "cast", "chance": 100.0, "duration": 0}, _data, RandomNumberGenerator.new(), events))
	ctx.check("a debuff on self ignores resistance", Effects.apply(2, q[1], 2, q[1], {"id": "slow", "target": "self", "on": "cast", "chance": 100.0, "duration": 0}, _data, RandomNumberGenerator.new(), events))
	q = _pair()
	q[1].stats["DOT_RES"] = 100.0
	var evs: Array[Dictionary] = []
	Effects.apply(1, q[0], 2, q[1], {"id": "burn", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 0}, _data, RandomNumberGenerator.new(), evs)
	ctx.check("effect_resisted event carries group 'dot'", evs.size() == 1 and evs[0]["type"] == "effect_resisted" and evs[0]["group"] == "dot")


func _test_immunity(ctx) -> void:
	for pair in [["stun", "CTRL_RES"], ["burn", "DOT_RES"], ["slow", "DEBUFF_RES"]]:
		var p := _pair()
		p[0].stats["EFFECT_ACC"] = 500.0
		p[0].stats[str(pair[1]).replace("RES", "ACC")] = 500.0
		p[1].stats[pair[1]] = 100.0
		ctx.check("%s >= 100 never lands even with huge ACC (%s)" % [pair[1], pair[0]], _rate(p[0], p[1], pair[0], 100.0, 100) == 0)
		p = _pair()
		p[0].stats["EFFECT_ACC"] = 500.0
		p[1].stats["EFFECT_RES"] = 60.0
		p[1].stats[pair[1]] = 40.0
		ctx.check("general 60 + group 40 = 100 total is immune (%s)" % pair[0], _rate(p[0], p[1], pair[0], 100.0, 100) == 0)
		p = _pair()
		p[0].stats["EFFECT_ACC"] = 500.0
		p[1].stats[pair[1]] = 99.0
		ctx.check("total 99 with huge ACC still lands (%s)" % pair[0], _rate(p[0], p[1], pair[0], 100.0, 50) == 50)
	var p2 := _pair()
	p2[1].stats["DOT_RES"] = 100.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var control_rng := RandomNumberGenerator.new()
	control_rng.seed = 5
	var events: Array[Dictionary] = []
	Effects.apply(1, p2[0], 2, p2[1], {"id": "burn", "target": "enemy", "on": "hit", "chance": 50.0, "duration": 0}, _data, rng, events)
	ctx.check("immunity consumes no random number", rng.randf() == control_rng.randf())


func _test_isolation(ctx) -> void:
	var p := _pair()
	p[1].stats["CTRL_RES"] = 100.0
	ctx.check("CTRL_RES 100 blocks stun", not _try(p[0], p[1], "stun", 100.0))
	ctx.check("CTRL_RES 100 blocks shock", not _try(p[0], p[1], "shock", 100.0))
	ctx.check("CTRL_RES 100 blocks sleep", not _try(p[0], p[1], "sleep", 100.0))
	ctx.check("CTRL_RES 100 does not block slow", _try(p[0], p[1], "slow", 100.0))
	ctx.check("CTRL_RES 100 does not block burn", _try(p[0], p[1], "burn", 100.0))
	p = _pair()
	p[1].stats["DOT_RES"] = 100.0
	ctx.check("DOT_RES 100 blocks burn, bleed, poison", not _try(p[0], p[1], "burn", 100.0) and not _try(p[0], p[1], "bleed", 100.0) and not _try(p[0], p[1], "poison", 100.0))
	ctx.check("DOT_RES 100 does not block stun or slow", _try(p[0], p[1], "stun", 100.0) and _try(p[0], p[1], "slow", 100.0))
	p = _pair()
	p[1].stats["DEBUFF_RES"] = 100.0
	var all_blocked := true
	for id in DEBUFF:
		all_blocked = all_blocked and not _try(p[0], p[1], id, 100.0)
	ctx.check("DEBUFF_RES 100 blocks all six plain debuffs", all_blocked)
	ctx.check("DEBUFF_RES 100 does not block stun or burn", _try(p[0], p[1], "stun", 100.0) and _try(p[0], p[1], "burn", 100.0))
	p = _pair()
	p[1].stats["EFFECT_RES"] = 100.0
	var general := true
	for id in CONTROL + DOT + DEBUFF:
		general = general and not _try(p[0], p[1], id, 100.0)
	ctx.check("general EFFECT_RES 100 blocks all three groups", general)


## With the new stats at 0 the outcomes are exactly the old formula's, for the same seed.
func _test_unchanged(ctx) -> void:
	var same := true
	for acc in [0.0, 25.0]:
		for res in [0.0, 30.0, 99.0]:
			for chance in [40.0, 100.0]:
				for id in ["slow", "burn", "stun"]:
					var p := _pair()
					p[0].stats["EFFECT_ACC"] = acc
					p[1].stats["EFFECT_RES"] = res
					var rng := RandomNumberGenerator.new()
					rng.seed = 42
					var old_rng := RandomNumberGenerator.new()
					old_rng.seed = 42
					for i in 30:
						p[1].effects.clear()
						p[1].control_immune_left = 0
						var events: Array[Dictionary] = []
						var got := Effects.apply(1, p[0], 2, p[1], {"id": id, "target": "enemy", "on": "hit", "chance": chance, "duration": 0}, _data, rng, events)
						var c := clampf(chance + acc - res, 0.0, 100.0)
						var expected: bool = not (c <= 0.0 or (c < 100.0 and old_rng.randf() * 100.0 >= c))
						if got != expected:
							same = false
	ctx.check("new stats at 0: outcomes and rng use match the old EFFECT_ACC/EFFECT_RES formula (30 rolls x 36 setups)", same)


func _arena(player_stats: Dictionary) -> GameSim:
	var world := SimWorld.new()
	world.half_width = 30.0
	world.half_depth = 3.0
	world.add_solid(AABB(Vector3(-40, -0.4, -5), Vector3(80, 0.4, 10)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sim := GameSim.new(world, _data, rng)
	sim.add_player(1, Vector3(0, 0.05, 0), {"CRIRATE": 0, "STAMINA": 1000})
	sim.add_enemy(2, Vector3(1.5, 0.05, 0), "dummy_grunt")
	sim._ai.erase(2)
	for key in player_stats:
		sim.fighters[1].stats[key] = float(player_stats[key])
	sim.fighters[1].stats["HP"] = 100000.0
	sim.fighters[1].hp = 100000.0
	for i in 12:
		sim.tick()
	return sim


## A real heavy hit (the brute's slam: knockback 9, launch 6.5) from fighter 2 on fighter 1.
func _slam(sim: GameSim) -> Dictionary:
	sim.events.clear()
	Combat.apply_hit(2, 1, "brute_slam", sim.fighters, sim.bodies, sim.combat, sim.rng, sim.events)
	var hit: Dictionary = {}
	for e in sim.events:
		if e["type"] == "hit":
			hit = e
	return {"hit": hit, "state": sim.fighters[1].state, "knock": sim.bodies[1].knockback, "vy": sim.bodies[1].velocity.y, "launched": sim.fighters[1].launched}


func _test_physical(ctx) -> void:
	var plain := _slam(_arena({}))
	ctx.check("control baseline: a slam staggers, knocks back and launches (%s)" % [plain], plain["state"] == Fighter.State.HITSTUN and plain["knock"] != Vector2.ZERO and plain["vy"] > 0.0 and plain["launched"])
	var immune := _slam(_arena({"CTRL_RES": 100}))
	ctx.check("CTRL_RES 100: no stagger, no knockback, no launch (%s)" % [immune], immune["state"] != Fighter.State.HITSTUN and immune["knock"] == Vector2.ZERO and immune["vy"] <= 0.0 and not immune["launched"] and immune["hit"].get("armored", false))
	var general := _slam(_arena({"EFFECT_RES": 100}))
	ctx.check("general EFFECT_RES 100 alone: total control resistance 100, so it is immune too", general["state"] != Fighter.State.HITSTUN and general["knock"] == Vector2.ZERO)
	var mixed := _slam(_arena({"EFFECT_RES": 60, "CTRL_RES": 40}))
	ctx.check("60 general + 40 CTRL = 100 stops it", mixed["state"] != Fighter.State.HITSTUN and mixed["knock"] == Vector2.ZERO)
	var partial := _slam(_arena({"CTRL_RES": 99}))
	ctx.check("CTRL_RES 99 still staggers", partial["state"] == Fighter.State.HITSTUN)
	var dot_only := _slam(_arena({"DOT_RES": 100, "DEBUFF_RES": 100}))
	ctx.check("DOT_RES / DEBUFF_RES 100 do not stop stagger", dot_only["state"] == Fighter.State.HITSTUN)
	var sim := _arena({"CTRL_RES": 100})
	var before: Vector3 = sim.bodies[1].position
	preload("res://logic/class_skills/engine.gd")._push_from(sim, 1, before + Vector3(1, 0, 0), 3.0)
	ctx.check("CTRL_RES 100: a class-skill knockback/pull does not move the fighter", sim.bodies[1].position == before)
	sim = _arena({})
	before = sim.bodies[1].position
	preload("res://logic/class_skills/engine.gd")._push_from(sim, 1, before + Vector3(1, 0, 0), 3.0)
	ctx.check("without CTRL_RES the class-skill knockback moves the fighter", sim.bodies[1].position != before)
	var m := _arena({})
	m.fighters[2].stats["CTRL_RES"] = 100.0
	m.events.clear()
	Combat.apply_hit(1, 2, "brute_slam", m.fighters, m.bodies, m.combat, m.rng, m.events)
	ctx.check("a monster with CTRL_RES 100 is not staggered or launched either", m.fighters[2].state != Fighter.State.HITSTUN and not m.fighters[2].launched)


func _test_tree_immune(ctx) -> void:
	var sim := _arena({})
	var me: Fighter = sim.fighters[1]
	me.race_state = {"pseudo": {"CONTROL_IMMUNE": {"add": 1.0, "mul": 0.0}}}
	var events: Array[Dictionary] = []
	var landed := Effects.apply(2, sim.fighters[2], 1, me, {"id": "stun", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 60}, _data, sim.rng, events)
	ctx.check("tree CONTROL_IMMUNE still blocks stun and tags control_immune", not landed and events.size() == 1 and events[0].get("control_immune", false))
	var s := _slam(sim)
	ctx.check("tree CONTROL_IMMUNE still blocks stagger/knockback/launch", s["state"] != Fighter.State.HITSTUN and s["knock"] == Vector2.ZERO)
	me.race_state["pseudo"] = {}
	ctx.check("tree CONTROL_IMMUNE does not touch slow/burn", Effects.apply(2, sim.fighters[2], 1, me, {"id": "slow", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 0}, _data, sim.rng, events))


func _test_data(ctx) -> void:
	var combat_text := FileAccess.get_file_as_string(CombatDataLoader.DATA_PATH)
	var weapons_text := FileAccess.get_file_as_string(CombatDataLoader.WEAPONS_PATH)
	var effects_text := FileAccess.get_file_as_string(CombatDataLoader.EFFECTS_PATH)
	var old_stats := "\"stats\": {\"HP\": 50, \"ATK\": 10.5, \"DEF\": 50, \"MOVESPD\": -40, \"CRIRATE\": 0}"
	var edited := combat_text.replace(old_stats, "\"stats\": {\"HP\": 50, \"ATK\": 10.5, \"DEF\": 50, \"MOVESPD\": -40, \"CRIRATE\": 0, \"CTRL_RES\": 100, \"CTRL_ACC\": 10, \"DOT_RES\": 20, \"DOT_ACC\": 5, \"DEBUFF_RES\": 30, \"DEBUFF_ACC\": 15}")
	ctx.check("test setup: the grunt edit applied", edited != combat_text)
	var data := CombatDataLoader.parse(edited, weapons_text, effects_text)
	ctx.check("a monster with the six group stats loads %s" % [data.errors], data.is_valid())
	if data.is_valid():
		var stats: Dictionary = data.enemy_stats("dummy_grunt")
		ctx.check("the group stats reach the monster's stats at any level", stats.get("CTRL_RES") == 100 and stats.get("DEBUFF_ACC") == 15 and data.enemy_stats("dummy_grunt", 5).get("DOT_RES") == 20)
		var fighter := Fighter.new()
		fighter.stats = data.full_stats(stats)
		ctx.check("Fighter.stat() returns the new stats, and 0 when absent", fighter.stat("CTRL_RES") == 100.0 and Fighter.new().stat("DOT_ACC") == 0.0)
	var bad := CombatDataLoader.parse(edited.replace("\"CTRL_RES\": 100", "\"CTRL_FOO\": 100"), weapons_text, effects_text)
	ctx.check("an unknown stat key is still reported", not bad.is_valid())
	var fx := CombatDataLoader.parse(combat_text, weapons_text, effects_text.replace("\"DEF\": {\"mul\": 0.5}", "\"CTRL_RES\": {\"add\": 50}"))
	ctx.check("a buff/debuff may modify CTRL_RES %s" % [fx.errors], fx.is_valid())
	var f := Fighter.new()
	f.stats = _data.full_stats({})
	f.stat_mods = {"CTRL_RES": {"add": 50.0, "mul": 0.0}}
	ctx.check("stat_mods add to a group stat", f.stat("CTRL_RES") == 50.0)


const GROUP_RES := {"control": "CTRL_RES", "dot": "DOT_RES", "debuff": "DEBUFF_RES"}
const GROUP_ACC := {"control": "CTRL_ACC", "dot": "DOT_ACC", "debuff": "DEBUFF_ACC"}


func _group_of_id(id: String) -> String:
	return "control" if CONTROL.has(id) else ("dot" if DOT.has(id) else "debuff")


func _grunt_stats() -> String:
	return "\"stats\": {\"HP\": 50, \"ATK\": 10.5, \"DEF\": 50, \"MOVESPD\": -40, \"CRIRATE\": 0}"


## The third layer: <GROUP>_<EFFECT>_ACC / _RES, derived by name from every debuff id in effects.json.
func _test_per_effect(ctx) -> void:
	var expected := {"stun": "CTRL_STUN", "shock": "CTRL_SHOCK", "sleep": "CTRL_SLEEP", "burn": "DOT_BURN", "bleed": "DOT_BLEED", "poison": "DOT_POISON",
		"slow": "DEBUFF_SLOW", "weaken": "DEBUFF_WEAKEN", "sunder": "DEBUFF_SUNDER", "wound": "DEBUFF_WOUND", "curse": "DEBUFF_CURSE", "exhaust": "DEBUFF_EXHAUST"}
	var derived: Dictionary = CombatDataLoader.derived_stat_set(_data.effects)
	ctx.check("per-effect keys: 12 debuffs x ACC/RES = 24 derived ids (%d)" % derived.size(), derived.size() == 24)
	var names_ok := true
	for id in expected:
		names_ok = names_ok and derived.has(expected[id] + "_ACC") and derived.has(expected[id] + "_RES") and CombatDataLoader.effect_stat_id(_group_of_id(id), id, "RES") == expected[id] + "_RES"
	ctx.check("per-effect keys: names are group prefix + effect id upper-cased", names_ok)
	ctx.check("per-effect keys: none for buffs or unknown effects", not CombatDataLoader.is_stat_name("DEBUFF_HASTE_RES") and not CombatDataLoader.is_stat_name("CTRL_NOPE_RES"))
	for id in expected:
		var group := _group_of_id(id)
		var acc: String = expected[id] + "_ACC"
		var res: String = expected[id] + "_RES"
		ctx.check("%s: derived ids are valid stat ids" % id, CombatDataLoader.is_stat_name(acc) and CombatDataLoader.is_stat_name(res))
		var p := _pair()
		p[0].stats[acc] = 100.0
		ctx.check("%s: %s 100 makes a 0%% chance certain" % [id, acc], _try(p[0], p[1], id, 0.0))
		p = _pair()
		p[1].stats[res] = 100.0
		p[0].stats["EFFECT_ACC"] = 500.0
		ctx.check("%s: %s 100 = immune even with huge ACC" % [id, res], _rate(p[0], p[1], id, 100.0, 50) == 0)
		p = _pair()
		p[1].stats["EFFECT_RES"] = 30.0
		p[1].stats[GROUP_RES[group]] = 30.0
		p[1].stats[res] = 40.0
		ctx.check("%s: general 30 + group 30 + effect 40 = 100 is immune" % id, _rate(p[0], p[1], id, 100.0, 50) == 0)
		p[1].stats[res] = 30.0
		var landed := _rate(p[0], p[1], id, 100.0, 600)
		ctx.check("%s: three layers of 30 leave about 10%% (%d/600)" % [id, landed], landed > 20 and landed < 110)
		p = _pair()
		p[0].stats["EFFECT_ACC"] = 10.0
		p[0].stats[GROUP_ACC[group]] = 10.0
		p[0].stats[acc] = 10.0
		ctx.check("%s: ACC layers sum: entry 70 + 10 + 10 + 10 lands every time" % id, _rate(p[0], p[1], id, 70.0, 100) == 100)
		p = _pair()
		p[1].stats[res] = 100.0
		var blocked := 0
		for other in expected:
			if not _try(p[0], p[1], other, 100.0):
				blocked += 1
		ctx.check("%s: %s 100 blocks exactly that one effect of the 12 (%d blocked)" % [id, res, blocked], blocked == 1 and not _try(p[0], p[1], id, 100.0))
	var p2 := _pair()
	p2[1].stats["CTRL_STUN_RES"] = 100.0
	ctx.check("CTRL_STUN_RES 100 blocks stun but not shock/sleep/burn/slow", not _try(p2[0], p2[1], "stun", 100.0) and _try(p2[0], p2[1], "shock", 100.0) and _try(p2[0], p2[1], "sleep", 100.0) and _try(p2[0], p2[1], "burn", 100.0) and _try(p2[0], p2[1], "slow", 100.0))
	p2 = _pair()
	p2[1].stats["DOT_BURN_RES"] = 100.0
	ctx.check("DOT_BURN_RES 100 blocks burn only (not bleed/poison/stun)", not _try(p2[0], p2[1], "burn", 100.0) and _try(p2[0], p2[1], "bleed", 100.0) and _try(p2[0], p2[1], "poison", 100.0) and _try(p2[0], p2[1], "stun", 100.0))
	var evs: Array[Dictionary] = []
	p2 = _pair()
	p2[1].stats["DEBUFF_SLOW_RES"] = 100.0
	Effects.apply(1, p2[0], 2, p2[1], {"id": "slow", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 0}, _data, RandomNumberGenerator.new(), evs)
	ctx.check("effect_resisted carries group 'debuff' for a per-effect block", evs.size() == 1 and evs[0]["group"] == "debuff")
	var one := _slam(_arena({"CTRL_STUN_RES": 100, "CTRL_SHOCK_RES": 100, "CTRL_SLEEP_RES": 100}))
	ctx.check("per-effect CTRL_*_RES 100 does NOT block stagger/knockback/launch", one["state"] == Fighter.State.HITSTUN and one["launched"])
	# a real player card (add_player) with the stats
	var sim := _arena({"CTRL_STUN_RES": 100})
	var stunned := Effects.apply(2, sim.fighters[2], 1, sim.fighters[1], {"id": "stun", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 60}, _data, sim.rng, sim.events)
	var slowed := Effects.apply(2, sim.fighters[2], 1, sim.fighters[1], {"id": "slow", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 0}, _data, sim.rng, sim.events)
	ctx.check("a player card with CTRL_STUN_RES 100 resists stun but is slowed", not stunned and slowed)
	sim = _arena({"DOT_POISON_ACC": 100})
	var poisoned := Effects.apply(1, sim.fighters[1], 2, sim.fighters[2], {"id": "poison", "target": "enemy", "on": "hit", "chance": 0.0, "duration": 0}, _data, sim.rng, sim.events)
	ctx.check("a player card with DOT_POISON_ACC 100 lands poison at 0%", poisoned)
	var holder := _arena({})
	holder.fighters[1].stat_mods = {"DOT_BURN_RES": {"add": 100.0, "mul": 0.0}}
	var burned := Effects.apply(2, holder.fighters[2], 1, holder.fighters[1], {"id": "burn", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 0}, _data, holder.rng, holder.events)
	var bled := Effects.apply(2, holder.fighters[2], 1, holder.fighters[1], {"id": "bleed", "target": "enemy", "on": "hit", "chance": 100.0, "duration": 0}, _data, holder.rng, holder.events)
	ctx.check("stat_mods on a player give per-effect RES: burn blocked, bleed lands", not burned and bled)
	# validation
	var combat_text := FileAccess.get_file_as_string(CombatDataLoader.DATA_PATH)
	var weapons_text := FileAccess.get_file_as_string(CombatDataLoader.WEAPONS_PATH)
	var effects_text := FileAccess.get_file_as_string(CombatDataLoader.EFFECTS_PATH)
	var fx := CombatDataLoader.parse(combat_text, weapons_text, effects_text.replace("\"DEF\": {\"mul\": 0.5}", "\"DOT_BURN_RES\": {\"add\": 50}"))
	ctx.check("an effect may modify a per-effect stat %s" % [fx.errors], fx.is_valid())
	var bad_fx := CombatDataLoader.parse(combat_text, weapons_text, effects_text.replace("\"DEF\": {\"mul\": 0.5}", "\"DOT_SLOW_RES\": {\"add\": 50}"))
	ctx.check("a derived-looking key with the wrong group is rejected", not bad_fx.is_valid())
	var old_stats := _grunt_stats()
	var mon := CombatDataLoader.parse(combat_text.replace(old_stats, old_stats.replace("\"CRIRATE\": 0}", "\"CRIRATE\": 0, \"CTRL_STUN_RES\": 100, \"DOT_BURN_ACC\": 20}")), weapons_text, effects_text)
	ctx.check("a monster may carry per-effect stats %s" % [mon.errors], mon.is_valid() and mon.enemy_stats("dummy_grunt").get("CTRL_STUN_RES") == 100)
	var mon_bad := CombatDataLoader.parse(combat_text.replace(old_stats, old_stats.replace("\"CRIRATE\": 0}", "\"CRIRATE\": 0, \"CTRL_HASTE_RES\": 100}")), weapons_text, effects_text)
	ctx.check("a per-effect key of a buff is rejected", not mon_bad.is_valid())
	var extra := effects_text.replace("\"slow\": {", "\"chill\": {\"name\": \"Chill\", \"kind\": \"debuff\", \"color\": [0.5, 0.8, 1.0], \"duration\": 60, \"max_stacks\": 1, \"stats\": {\"MOVESPD\": {\"add\": -10}}},\n\t\t\"slow\": {")
	var with_new := CombatDataLoader.parse(combat_text, weapons_text, extra)
	ctx.check("a new effect id gets its derived keys for free %s" % [with_new.errors], with_new.is_valid() and CombatDataLoader.derived_stat_set(with_new.effects).has("DEBUFF_CHILL_RES"))
