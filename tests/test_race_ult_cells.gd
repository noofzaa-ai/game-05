extends RefCounted
## The 16 race ultimates as data (design/gdd/races-and-classes.md 3.7, 3.10.1, 4; phase 6-7), race by race, and the
## strict load checks of ultimate blocks. Each cell: its data numbers, a scripted cast with the GDD numbers, and its
## `use` rule firing in its scene and holding in its negative scene.
const RaceTest := preload("res://tests/test_race_passives.gd")
const Act := preload("res://tests/test_race_ult_actions.gd")
const RaceData := preload("res://logic/race_data.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const RaceUltimates := preload("res://logic/race_ultimates.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Fighter := preload("res://logic/fighter.gd")
const FIXTURE := "user://test_race_ult_cells_fixture/"
const MAGIC_SQUAD := ["sword_shield", "greatsword", "magic"]


func run(ctx) -> void:
	_strict_validation(ctx)
	_human(ctx)


## A squad of these races with each card's own ultimate from the data, gauges full, bodies grounded.
static func squad(races: Array, cards: Array = RaceTest.CARDS) -> Dictionary:
	var f := RaceTest.squad(races, cards)
	for id in range(1, cards.size() + 1):
		var fighter = f.sim.fighters[id]
		fighter.gauge = 100.0
		f.sim.bodies[id].grounded = true
		RaceUltimates.register_move(f.sim.combat, fighter)
	Act.zero_def(f.sim)
	return f


static func ult(f: Dictionary, id: int) -> Dictionary:
	return f.sim.fighters[id].race_state["ultimate"]


static func damage_by(events: Array, id: int) -> Array:
	return events.filter(func(e): return e["type"] == "race_burst_hit" and int(e["attacker"]) == id)


static func run_ticks(sim, ticks: int) -> Array:
	var seen: Array = []
	for t in ticks:
		sim.tick_count += 1
		sim.events.clear()
		RacePassives.step(sim)
		seen.append_array(sim.events)
	return seen


static func cast(f: Dictionary, id: int) -> Array:
	var sim = f.sim
	var fighter = sim.fighters[id]
	fighter.gauge = 100.0
	fighter.state = Fighter.State.IDLE
	fighter.move_id = ""
	sim.bodies[id].grounded = true
	return Act.cast_now(sim, id)


func _load_with_ultimate(ultimate) -> Array:
	DirAccess.make_dir_recursive_absolute(FIXTURE)
	for file in DirAccess.get_files_at(FIXTURE):
		DirAccess.remove_absolute(FIXTURE + file)
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/races/rules.json"))
	rules["starter_races"] = {}
	rules["default_race"] = "testrace"
	var race: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/races/human.json"))
	race["id"] = "testrace"
	race["classes"]["greatsword"]["ultimate"] = ultimate
	for pair in [["rules.json", rules], ["testrace.json", race]]:
		var file := FileAccess.open(FIXTURE + str(pair[0]), FileAccess.WRITE)
		file.store_string(JSON.stringify(pair[1]))
		file.close()  # flushed before the loader reads it
	return RaceData.load_from(FIXTURE).errors


func _strict_validation(ctx) -> void:
	var data = RaceData.load_default()
	ctx.check("race data with ultimates loads with no errors %s" % [data.errors], data.errors.is_empty())
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/races/human.json"))["classes"]["greatsword"]["ultimate"]
	ctx.check("a sound ultimate block loads", _load_with_ultimate(good).is_empty())
	var cases := {
		"unknown use condition": func(u): u["use"]["any_of"] = [{"if": "moon_is_full"}],
		"unknown use field": func(u): u["use"]["any_of"] = [{"if": "enemies_near", "radius": 3.0, "min": 3, "colour": "red"}],
		"unknown clip key": func(u): u["clip"] = "dance",
		"unknown ultimate field": func(u): u["explodes"] = true,
		"no actions": func(u): u["actions"] = [],
		"unknown action": func(u): u["actions"] = [{"action": "teleport"}],
		"unknown center": func(u): u["actions"] = [{"action": "burst", "center": "moon", "radius": 3.0, "atk_mul": 1.0}],
		"unknown pick": func(u): u["actions"] = [{"action": "burst", "center": "self", "radius": 3.0, "atk_mul": 1.0, "pick": "random"}],
		"unknown last_status": func(u): u["actions"] = [{"action": "burst", "center": "self", "radius": 3.0, "atk_mul": 1.0, "last_status": "petrify"}],
		"zone without radius": func(u): u["actions"] = [{"action": "zone", "center": "self", "duration_ticks": 60, "pulse": [{"action": "burst", "center": "zone", "radius": 1.0, "atk_mul": 1.0}]}],
		"no use block": func(u): u.erase("use"),
		"no cast_ticks": func(u): u.erase("cast_ticks"),
		"unknown condition inside and": func(u): u["use"]["any_of"] = [{"if": "enemies_near", "radius": 3.0, "min": 1, "and": [{"if": "sneeze"}]}],
	}
	for name in cases:
		var bad: Dictionary = good.duplicate(true)
		cases[name].call(bad)
		ctx.check("an ultimate with an %s fails the load" % name, not _load_with_ultimate(bad).is_empty())


## Human (gold): skills in 4 ways (team refresh, refresh per hit, refresh on kill, self full refresh).
func _human(ctx) -> void:
	var data = RaceData.load_default()
	ctx.check("Human: 4 class ultimates + a default, all named", ["sword_shield", "greatsword", "longbow", "magic"].all(func(c): return not str(data.ultimate_for("human", c).get("name", "")).is_empty())
		and data.ultimate_for("human", "no_such_class")["name"] == "Rally")
	# H/S&S Commander's Call: taunt r5 3 s, skill cooldowns halved on all allies, valor 6 s.
	var f := squad(["human", "human", "human"])
	var sim = f.sim
	var foes := Act.enemies(sim)
	Act.place(sim, sim.bodies[1].position, {foes[0]: Vector3(2, 0, 0), foes[1]: Vector3(-2, 0, 0)})
	var system = sim.skill_system
	for id in [1, 2, 3]:
		for row in system.builds[id].skills:
			system.casters[id].cooldowns[str(row.skill)] = system.casters[id].clock + 10.0
	var out := cast(f, 1)
	ctx.check("Commander's Call: taunts enemies within 5 m for 3 s", out.any(func(e): return e["type"] == "race_taunt" and int(e["ticks"]) == 180 and e["enemies"].size() == 2))
	var halved: bool = [1, 2, 3].all(func(id): return system.builds[id].skills.all(func(r): return absf(float(system.casters[id].cooldowns[str(r.skill)]) - system.casters[id].clock - 5.0) < 0.001))
	ctx.check("Commander's Call: every ally's skill cooldowns halved (10 s -> 5 s)", halved)
	ctx.check("Commander's Call: valor 6 s on every ally", [1, 2, 3].all(func(id): return int(sim.fighters[id].effects.get("valor", {}).get("left", 0)) == 360))
	# use: 2+ allies with 2+ skills on cooldown AND 2+ enemies within 5 m; or the boss within 5 m.
	var g := squad(["human", "human", "human"])
	var gsim = g.sim
	var gf := Act.enemies(gsim)
	Act.place(gsim, gsim.bodies[1].position, {gf[0]: Vector3(2, 0, 0), gf[1]: Vector3(-2, 0, 0)})
	ctx.check("Commander's Call use: holds while skills are ready", not _matches(gsim, 1))
	for id in [1, 2]:
		for row in gsim.skill_system.builds[id].skills.slice(0, 2):
			gsim.skill_system.casters[id].cooldowns[str(row.skill)] = gsim.skill_system.casters[id].clock + 8.0
	ctx.check("Commander's Call use: 2 allies x 2 skills on cooldown + 2 enemies in 5 m -> fires", _matches(gsim, 1))
	Act.place(gsim, gsim.bodies[1].position, {gf[0]: Vector3(2, 0, 0)})
	ctx.check("Commander's Call use: only 1 enemy near -> holds", not _matches(gsim, 1))
	gsim.fighters[gf[0]].enemy_type = "goblin_chief"
	ctx.check("Commander's Call use: the boss within 5 m -> fires", _matches(gsim, 1))

	# H/GS Masterstroke: 110% x3 in 3.5 m, 0.4 s apart, stun on the 3rd; each enemy hit: 1 s refresh, cap 4 s per cast.
	var m := squad(["human", "human", "human"])
	var msim = m.sim
	var mf := Act.enemies(msim)
	Act.place(msim, msim.bodies[2].position, {mf[0]: Vector3(1, 0, 0), mf[1]: Vector3(-1, 0, 0), mf[2]: Vector3(0, 0, 1)})
	for e in mf:
		msim.fighters[e].control_immune_left = 0
	var caster = msim.skill_system.casters[2]
	for row in msim.skill_system.builds[2].skills:
		caster.cooldowns[str(row.skill)] = caster.clock + 20.0
	var atk: float = msim.fighters[2].stat("ATK")
	var all_events := cast(m, 2)
	all_events.append_array(run_ticks(msim, 60))
	var hits := damage_by(all_events, 2)
	ctx.check("Masterstroke: 3 hits x 3 enemies = 9 hits of 110%% ATK (%d, %.0f vs %.0f)" % [hits.size(), float(hits[0]["damage"]) if not hits.is_empty() else 0.0, roundf(atk * 1.1)],
		hits.size() == 9 and hits.all(func(e): return is_equal_approx(float(e["damage"]), roundf(atk * 1.1))))
	var stuns: Array = all_events.filter(func(e): return e["type"] == "effect_applied" and e["effect"] == "stun")
	ctx.check("Masterstroke: the 3rd hit stuns (%d stuns, at the last hit)" % stuns.size(), stuns.size() == 3 and all_events.find(stuns[0]) > all_events.find(hits[5]))
	var cut: float = 20.0 - (float(caster.cooldowns[str(msim.skill_system.builds[2].skills[0].skill)]) - caster.clock)
	ctx.check("Masterstroke: 9 enemy hits refresh 1 s each, capped at 4 s per cast (%.2f)" % cut, absf(cut - 4.0) < 0.05)
	var mu := squad(["human", "human", "human"])
	var mf2 := Act.enemies(mu.sim)
	Act.place(mu.sim, mu.sim.bodies[2].position, {mf2[0]: Vector3(1, 0, 0), mf2[1]: Vector3(-1, 0, 0)})
	ctx.check("Masterstroke use: 2 enemies in 3.5 m -> holds", not _matches(mu.sim, 2))
	Act.place(mu.sim, mu.sim.bodies[2].position, {mf2[0]: Vector3(1, 0, 0), mf2[1]: Vector3(-1, 0, 0), mf2[2]: Vector3(0, 0, 1.5)})
	ctx.check("Masterstroke use: 3 enemies in 3.5 m -> fires", _matches(mu.sim, 2))

	# H/Bow Called Shot: 450% forced crit + sunder 7 s on boss_or_highest_hp in 12 m; a kill readies every skill.
	var c := squad(["human", "human", "human"])
	var csim = c.sim
	var cf := Act.enemies(csim)
	Act.place(csim, csim.bodies[3].position, {cf[0]: Vector3(10, 0, 0), cf[1]: Vector3(4, 0, 0)})
	csim.fighters[cf[0]].stats["HP"] = 200000.0
	csim.fighters[cf[0]].hp = 200000.0
	var bow_atk: float = csim.fighters[3].stat("ATK")
	var crit: float = csim.fighters[3].stat("CRIDMG", 100.0) / 100.0
	hits = damage_by(cast(c, 3), 3)
	ctx.check("Called Shot: one 450%% x CRIDMG shot at the toughest enemy in 12 m (%s)" % [hits.map(func(e): return e["damage"])],
		hits.size() == 1 and int(hits[0]["target"]) == cf[0] and is_equal_approx(float(hits[0]["damage"]), roundf(bow_atk * 4.5 * crit)))
	ctx.check("Called Shot: sunder 7 s", int(csim.fighters[cf[0]].effects.get("sunder", {}).get("left", 0)) == 420)
	csim.fighters[cf[1]].enemy_type = "goblin_chief"
	csim.fighters[cf[1]].hp = 10.0
	var bcaster = csim.skill_system.casters[3]
	for row in csim.skill_system.builds[3].skills:
		bcaster.cooldowns[str(row.skill)] = bcaster.clock + 12.0
	hits = damage_by(cast(c, 3), 3)
	ctx.check("Called Shot: the boss first, even when weaker", hits.size() == 1 and int(hits[0]["target"]) == cf[1])
	ctx.check("Called Shot: a kill readies every skill", csim.skill_system.builds[3].skills.all(func(r): return float(bcaster.cooldowns[str(r.skill)]) - bcaster.clock <= 0.0))
	var cu := squad(["human", "human", "human"])
	var cuf := Act.enemies(cu.sim)
	Act.place(cu.sim, cu.sim.bodies[3].position, {cuf[0]: Vector3(6, 0, 0)})
	ctx.check("Called Shot use: only goblins -> holds", not _matches(cu.sim, 3))
	cu.sim.fighters[cuf[0]].enemy_type = "goblin_knight"
	ctx.check("Called Shot use: an elite within 12 m -> fires", _matches(cu.sim, 3))
	cu.sim.fighters[cuf[0]].enemy_type = "goblin_chief"
	Act.place(cu.sim, cu.sim.bodies[3].position, {cuf[0]: Vector3(13, 0, 0)})
	ctx.check("Called Shot use: the boss beyond 12 m -> holds", not _matches(cu.sim, 3))

	# H/Magic Grand Recital: all 4 skills ready + recital 6 s (SKILL_DMG +30%, STAREGEN +40).
	var r := squad(["human", "human", "human"], MAGIC_SQUAD)
	var rsim = r.sim
	var rf := Act.enemies(rsim)
	Act.place(rsim, rsim.bodies[3].position, {rf[0]: Vector3(4, 0, 0), rf[1]: Vector3(5, 0, 0)})
	var mcaster = rsim.skill_system.casters[3]
	ctx.check("Grand Recital use: skills ready -> holds", not _matches(rsim, 3))
	for row in rsim.skill_system.builds[3].skills.slice(0, 3):
		mcaster.cooldowns[str(row.skill)] = mcaster.clock + 9.0
	ctx.check("Grand Recital use: 3 of 4 skills on cooldown + 2 enemies in 7 m -> fires", _matches(rsim, 3))
	cast(r, 3)
	ctx.check("Grand Recital: every skill ready", rsim.skill_system.builds[3].skills.all(func(row): return float(mcaster.cooldowns.get(str(row.skill), 0.0)) - mcaster.clock <= 0.0))
	ctx.check("Grand Recital: recital 6 s (skill damage x1.3 through SKILL_DMG)", int(rsim.fighters[3].effects.get("recital", {}).get("left", 0)) == 360
		and is_equal_approx(RacePassives.skill_dmg(rsim.fighters[3]), 0.3))
	Act.place(rsim, rsim.bodies[3].position, {rf[0]: Vector3(4, 0, 0)})
	for row in rsim.skill_system.builds[3].skills.slice(0, 3):
		mcaster.cooldowns[str(row.skill)] = mcaster.clock + 9.0
	ctx.check("Grand Recital use: 1 enemy near and no boss -> holds", not _matches(rsim, 3))
	ctx.check("formula 4.4: Human mage in Human Trio with recital = 1.30 x 1.20 x 1.30 = 2.03x skill damage",
		absf(_skill_damage_mul(rsim.fighters[3]) - 2.028) < 0.001)


static func _matches(sim, id: int) -> bool:
	for rule in sim.fighters[id].race_state["ultimate"]["use"]["any_of"]:
		if Pilot.use_matches(sim, id, rule):
			return true
	return false


static func _skill_damage_mul(fighter) -> float:
	var stats := {"damage": 1.0}
	RacePassives.modify_skill_stats(fighter, stats)
	return float(stats["damage"])
