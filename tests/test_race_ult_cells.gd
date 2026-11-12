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
	_viking(ctx)
	_elf(ctx)
	_runeborn(ctx)
	_all_fire_in_play(ctx)


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
	for id in [1, 2, 3]:
		Act.set_cd(sim, id, Act.skills_of(sim, id), 10.0)
	var out := cast(f, 1)
	ctx.check("Commander's Call: taunts enemies within 5 m for 3 s", out.any(func(e): return e["type"] == "race_taunt" and int(e["ticks"]) == 180 and e["enemies"].size() == 2))
	var halved: bool = [1, 2, 3].all(func(id): return Act.skills_of(sim, id).all(func(s): return absf(Act.cd_left(sim, id, s) - 5.0) < 0.02))
	ctx.check("Commander's Call: every ally's skill cooldowns halved (10 s -> 5 s)", halved)
	ctx.check("Commander's Call: valor 6 s on every ally", [1, 2, 3].all(func(id): return int(sim.fighters[id].effects.get("valor", {}).get("left", 0)) == 360))
	# use: 2+ allies with 2+ skills on cooldown AND 2+ enemies within 5 m; or the boss within 5 m.
	var g := squad(["human", "human", "human"])
	var gsim = g.sim
	var gf := Act.enemies(gsim)
	Act.place(gsim, gsim.bodies[1].position, {gf[0]: Vector3(2, 0, 0), gf[1]: Vector3(-2, 0, 0)})
	ctx.check("Commander's Call use: holds while skills are ready", not _matches(gsim, 1))
	for id in [1, 2]:
		Act.set_cd(gsim, id, Act.skills_of(gsim, id).slice(0, 2), 8.0)
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
	Act.set_cd(msim, 2, Act.skills_of(msim, 2), 20.0)
	var first_cd := str(Act.skills_of(msim, 2)[0])
	var cd_set_at: int = msim.tick_count
	var atk: float = msim.fighters[2].stat("ATK")
	var all_events := cast(m, 2)
	all_events.append_array(run_ticks(msim, 60))
	var hits := damage_by(all_events, 2)
	ctx.check("Masterstroke: 3 hits x 3 enemies = 9 hits of 110%% ATK (%d, %.0f vs %.0f)" % [hits.size(), float(hits[0]["damage"]) if not hits.is_empty() else 0.0, roundf(atk * 1.1)],
		hits.size() == 9 and hits.all(func(e): return is_equal_approx(float(e["damage"]), roundf(atk * 1.1))))
	var stuns: Array = all_events.filter(func(e): return e["type"] == "effect_applied" and e["effect"] == "stun")
	ctx.check("Masterstroke: the 3rd hit stuns (%d stuns, at the last hit)" % stuns.size(), stuns.size() == 3 and all_events.find(stuns[0]) > all_events.find(hits[5]))
	var cut: float = 20.0 - (Act.cd_left(msim, 2, first_cd) + float(msim.tick_count - cd_set_at) / 60.0)
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
	Act.set_cd(csim, 3, Act.skills_of(csim, 3), 12.0)
	hits = damage_by(cast(c, 3), 3)
	ctx.check("Called Shot: the boss first, even when weaker", hits.size() == 1 and int(hits[0]["target"]) == cf[1])
	ctx.check("Called Shot: a kill readies every skill", Act.skills_of(csim, 3).all(func(s): return Act.cd_left(csim, 3, s) <= 0.0))
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
	ctx.check("Grand Recital use: skills ready -> holds", not _matches(rsim, 3))
	Act.set_cd(rsim, 3, Act.skills_of(rsim, 3).slice(0, 3), 9.0)
	ctx.check("Grand Recital use: 3 of 4 skills on cooldown + 2 enemies in 7 m -> fires", _matches(rsim, 3))
	cast(r, 3)
	ctx.check("Grand Recital: every skill ready", Act.skills_of(rsim, 3).all(func(s): return Act.cd_left(rsim, 3, s) <= 0.0))
	ctx.check("Grand Recital: recital 6 s (skill damage x1.3 through SKILL_DMG)", int(rsim.fighters[3].effects.get("recital", {}).get("left", 0)) == 360
		and is_equal_approx(RacePassives.skill_dmg(rsim.fighters[3]), 0.3))
	Act.place(rsim, rsim.bodies[3].position, {rf[0]: Vector3(4, 0, 0)})
	Act.set_cd(rsim, 3, Act.skills_of(rsim, 3).slice(0, 3), 9.0)
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


## Viking (red): HP and kills in 4 ways (Fury-scaled taunt burst, kill-extended whirl, execute chain, HP-cost nuke).
func _viking(ctx) -> void:
	var data = RaceData.load_default()
	ctx.check("Viking: 4 class ultimates + a default, fury_factor 1.5", ["sword_shield", "greatsword", "longbow", "magic"].all(func(c): return not str(data.ultimate_for("viking", c).get("name", "")).is_empty())
		and data.ultimate_for("viking", "no_such_class")["name"] == "Battle Fury" and float(data.rules["fury_factor"]) == 1.5)
	# V/S&S Unbowed Roar: taunt r7 4 s, unbowed 6 s, burst r3 100% fury. 4.6: at 60% HP -> 160%.
	var f := squad(["viking", "viking", "viking"])
	var sim = f.sim
	var foes := Act.enemies(sim)
	Act.place(sim, sim.bodies[1].position, {foes[0]: Vector3(2, 0, 0), foes[1]: Vector3(6, 0, 0)})
	var tank = sim.fighters[1]
	tank.hp = tank.max_hp() * 0.6
	var atk: float = tank.stat("ATK")
	var out := cast(f, 1)
	var hits := damage_by(out, 1)
	ctx.check("Unbowed Roar: taunts within 7 m for 4 s", out.any(func(e): return e["type"] == "race_taunt" and int(e["ticks"]) == 240 and e["enemies"].size() == 2))
	ctx.check("Unbowed Roar: unbowed 6 s on self", int(tank.effects.get("unbowed", {}).get("left", 0)) == 360)
	# Unbowed (+30% ATK) lands first (action order), then the burst: 100% x 1.3 ATK x (1 + 1.5 x 0.4) = 160% of the buffed ATK.
	ctx.check("formula 4.6: Unbowed burst at 60%% HP = 160%% of the Unbowed ATK, only within 3 m (%s vs %.0f)" % [hits.map(func(e): return e["damage"]), roundf(atk * 1.3 * 1.6)],
		hits.size() == 1 and int(hits[0]["target"]) == foes[0] and is_equal_approx(float(hits[0]["damage"]), roundf(atk * 1.3 * 1.6)))
	var u := squad(["viking", "viking", "viking"])
	var uf := Act.enemies(u.sim)
	Act.place(u.sim, u.sim.bodies[1].position, {uf[0]: Vector3(5, 0, 0), uf[1]: Vector3(6, 0, 0)})
	ctx.check("Unbowed Roar use: 2 enemies in 7 m, all healthy -> holds", not _matches(u.sim, 1))
	Act.place(u.sim, u.sim.bodies[1].position, {uf[0]: Vector3(5, 0, 0), uf[1]: Vector3(6, 0, 0), uf[2]: Vector3(-6, 0, 0)})
	ctx.check("Unbowed Roar use: 3 enemies in 7 m -> fires", _matches(u.sim, 1))
	Act.place(u.sim, u.sim.bodies[1].position, {uf[0]: u.sim.bodies[3].position - u.sim.bodies[1].position + Vector3(1, 0, 0)})
	u.sim.fighters[3].hp = u.sim.fighters[3].max_hp() * 0.5
	ctx.check("Unbowed Roar use: a hurt ally (<60%) with an enemy on it -> fires", _matches(u.sim, 1))

	# V/GS Ragnarok Whirl: follow zone r3 3 s, 55% fury every 0.5 s = 6 pulses at full HP.
	var w := squad(["viking", "viking", "viking"])
	var wsim = w.sim
	var wf := Act.enemies(wsim)
	Act.place(wsim, wsim.bodies[2].position, {wf[0]: Vector3(1, 0, 0)})
	var gs = wsim.fighters[2]
	gs.hp = gs.max_hp()
	var gatk: float = gs.stat("ATK")
	var all := cast(w, 2)
	all.append_array(run_ticks(wsim, 200))
	hits = damage_by(all, 2)
	ctx.check("Ragnarok Whirl: 6 pulses of 55%% ATK at full HP (%d x %s)" % [hits.size(), hits[0]["damage"] if not hits.is_empty() else 0],
		hits.size() == 6 and hits.all(func(e): return is_equal_approx(float(e["damage"]), roundf(gatk * 0.55))))
	var ws := squad(["viking", "viking", "viking"])
	var wsf := Act.enemies(ws.sim)
	Act.place(ws.sim, ws.sim.bodies[2].position, {wsf[0]: Vector3(1, 0, 0), wsf[1]: Vector3(-1, 0, 0)})
	ctx.check("Ragnarok Whirl use: 2 enemies in 3 m -> holds", not _matches(ws.sim, 2))
	Act.place(ws.sim, ws.sim.bodies[2].position, {wsf[0]: Vector3(1, 0, 0), wsf[1]: Vector3(-1, 0, 0), wsf[2]: Vector3(0, 0, 2)})
	ctx.check("Ragnarok Whirl use: 3 enemies in 3 m -> fires", _matches(ws.sim, 2))

	# V/Bow Executioner's Volley: 220% at the lowest-HP% enemy in 12 m, x2 below 30%, chain_on_kill 3.
	var x := squad(["viking", "viking", "viking"])
	var xsim = x.sim
	var xf := Act.enemies(xsim)
	Act.place(xsim, xsim.bodies[3].position, {xf[0]: Vector3(6, 0, 0), xf[1]: Vector3(7, 0, 1)})
	xsim.fighters[xf[0]].hp = xsim.fighters[xf[0]].max_hp() * 0.6
	xsim.fighters[xf[1]].hp = xsim.fighters[xf[1]].max_hp() * 0.8
	var batk: float = xsim.fighters[3].stat("ATK")
	hits = damage_by(cast(x, 3), 3)
	ctx.check("Executioner: 220%% at the lowest HP%% target in 12 m (%s)" % [hits.map(func(e): return e["damage"])],
		hits.size() == 1 and int(hits[0]["target"]) == xf[0] and is_equal_approx(float(hits[0]["damage"]), roundf(batk * 2.2)))
	var xu := squad(["viking", "viking", "viking"])
	var xuf := Act.enemies(xu.sim)
	Act.place(xu.sim, xu.sim.bodies[3].position, {xuf[0]: Vector3(6, 0, 0)})
	xu.sim.fighters[xuf[0]].hp = xu.sim.fighters[xuf[0]].max_hp() * 0.4
	ctx.check("Executioner use: one enemy at 40% -> holds", not _matches(xu.sim, 3))
	xu.sim.fighters[xuf[0]].hp = xu.sim.fighters[xuf[0]].max_hp() * 0.25
	ctx.check("Executioner use: an enemy below 30% in 12 m -> fires", _matches(xu.sim, 3))

	# V/Magic Blood Moon: 15% current HP first; zone r4 4 s at densest within 9 m; 45% fury x2.0 per 0.5 s; rage on allies inside.
	# 4.6: caster at 80% pays 12% -> 68%, m = 0.32 -> each pulse 45% x 1.64 = 73.8%; 8 pulses.
	var b := squad(["viking", "viking", "viking"], MAGIC_SQUAD)
	var bsim = b.sim
	var bf := Act.enemies(bsim)
	Act.place(bsim, bsim.bodies[3].position, {bf[0]: Vector3(6, 0, 0), bf[1]: Vector3(6.5, 0, 1), bf[2]: Vector3(6, 0, -1)})
	bsim.bodies[2].position = bsim.bodies[3].position + Vector3(6, 0, 0.5)  # an ally standing in the moon
	var mage = bsim.fighters[3]
	mage.hp = mage.max_hp() * 0.8
	var matk: float = mage.stat("ATK")
	all = cast(b, 3)
	ctx.check("Blood Moon: pays 15%% of current HP first (%.3f of max)" % (mage.hp / mage.max_hp()), absf(mage.hp / mage.max_hp() - 0.68) < 0.001)
	all.append_array(run_ticks(bsim, 260))
	hits = damage_by(all, 3).filter(func(e): return int(e["target"]) == bf[0])
	ctx.check("formula 4.6: Blood Moon 8 pulses of 45%% x 1.64 = 74%% each (%d x %s vs %.0f)" % [hits.size(), hits[0]["damage"] if not hits.is_empty() else 0, roundf(matk * 0.45 * 1.64)],
		hits.size() == 8 and hits.all(func(e): return is_equal_approx(float(e["damage"]), roundf(matk * 0.45 * 1.64))))
	ctx.check("Blood Moon: rage on the ally inside (first pulse only), not on the one outside", bsim.fighters[2].effects.has("rage") and not bsim.fighters[1].effects.has("rage"))
	var bu := squad(["viking", "viking", "viking"], MAGIC_SQUAD)
	var buf := Act.enemies(bu.sim)
	Act.place(bu.sim, bu.sim.bodies[3].position, {buf[0]: Vector3(6, 0, 0), buf[1]: Vector3(6.5, 0, 1)})
	ctx.check("Blood Moon use: 2 enemies in r4 -> holds", not _matches(bu.sim, 3))
	Act.place(bu.sim, bu.sim.bodies[3].position, {buf[0]: Vector3(6, 0, 0), buf[1]: Vector3(6.5, 0, 1), buf[2]: Vector3(8, 0, -2)})
	ctx.check("Blood Moon use: 3 enemies in r4 of a point within 9 m -> fires", _matches(bu.sim, 3))
	bu.sim.fighters[3].hp = bu.sim.fighters[3].max_hp() * 0.2
	ctx.check("Blood Moon: below 25% HP it never fires, even past max_hold_ticks (5)", not RaceUltimates.ready(bu.sim, 3))


## Elf (green): healing in 4 shapes (zone, damage-to-heal, single target + guard, revive).
func _elf(ctx) -> void:
	var data = RaceData.load_default()
	ctx.check("Elf: 4 class ultimates + a default; Rebirth Bloom charge_mul 0.85", ["sword_shield", "greatsword", "longbow", "magic"].all(func(c): return not str(data.ultimate_for("elf", c).get("name", "")).is_empty())
		and data.ultimate_for("elf", "no_such_class")["name"] == "Lifebloom Surge" and float(data.ultimate_for("elf", "magic")["charge_mul"]) == 0.85)
	# E/S&S Heartwood Bastion: taunt r5 3 s; grove r5 6 s: allies inside heal 2.5% max HP/s (12 pulses x 1.25%), enemies slowed.
	var f := squad(["elf", "elf", "elf"])
	var sim = f.sim
	var foes := Act.enemies(sim)
	Act.place(sim, sim.bodies[1].position, {foes[0]: Vector3(2, 0, 0)})
	sim.bodies[2].position = sim.bodies[1].position + Vector3(0, 0, 2)
	sim.bodies[3].position = sim.bodies[1].position + Vector3(0, 0, 12)
	for id in [1, 2, 3]:
		sim.fighters[id].hp = sim.fighters[id].max_hp() * 0.3
		sim.fighters[id].effects.clear()
		sim.fighters[id].race_state["pseudo"] = {}  # (no Elf Trio HEALING bonus: the plain numbers)
	var out := cast(f, 1)
	out.append_array(run_ticks(sim, 400))
	var healed_in: float = (sim.fighters[2].hp / sim.fighters[2].max_hp()) - 0.3
	ctx.check("Heartwood: an ally in the grove heals 2.5%%/s for 6 s = 15%% (%.3f)" % healed_in, absf(healed_in - 0.15) < 0.002)
	ctx.check("Heartwood: an ally outside heals nothing", is_equal_approx(sim.fighters[3].hp / sim.fighters[3].max_hp(), 0.3))
	ctx.check("Heartwood: taunt 3 s and slow on enemies inside", out.any(func(e): return e["type"] == "race_taunt" and int(e["ticks"]) == 180)
		and out.any(func(e): return e["type"] == "effect_applied" and e["effect"] == "slow" and int(e["target"]) == foes[0]))
	var h := squad(["elf", "elf", "elf"])
	h.sim.bodies[2].position = h.sim.bodies[1].position + Vector3(0, 0, 2)
	h.sim.bodies[3].position = h.sim.bodies[1].position + Vector3(0, 0, 3)
	Act.place(h.sim, h.sim.bodies[1].position, {})
	ctx.check("Heartwood use: allies near but healthy -> holds", not _matches(h.sim, 1))
	h.sim.fighters[2].hp = h.sim.fighters[2].max_hp() * 0.6
	ctx.check("Heartwood use: 2+ allies within 5 m and one below 65% -> fires", _matches(h.sim, 1))

	# E/GS Thornbloom Cleave: 180% in 3.5 m + slow, then 40% of the damage heals all allies, split, cap 12% each (4.2).
	var t := squad(["elf", "elf", "elf"])
	var tsim = t.sim
	var tf := Act.enemies(tsim)
	Act.place(tsim, tsim.bodies[2].position, {tf[0]: Vector3(1, 0, 0), tf[1]: Vector3(-1, 0, 0), tf[2]: Vector3(0, 0, 1)})
	for id in [1, 2, 3]:
		tsim.fighters[id].hp = tsim.fighters[id].max_hp() * 0.2
		tsim.fighters[id].effects.clear()
		tsim.fighters[id].race_state["pseudo"] = {}
	var gatk: float = tsim.fighters[2].stat("ATK")
	out = cast(t, 2)
	var hits := damage_by(out, 2)
	var dealt := 0.0
	for e in hits:
		dealt += float(e["damage"])
	ctx.check("Thornbloom: 180%% on each of 3 enemies (%s vs %.0f)" % [hits.map(func(e): return e["damage"]), roundf(gatk * 1.8)], hits.size() == 3 and hits.all(func(e): return is_equal_approx(float(e["damage"]), roundf(gatk * 1.8))))
	var ok := true
	for id in [1, 2, 3]:
		var fighter = tsim.fighters[id]
		var want: float = minf(0.40 * dealt / 3.0, 0.12 * fighter.max_hp())
		ok = ok and absf(fighter.hp - (0.2 * fighter.max_hp() + want)) < 0.01
	ctx.check("formula 4.2 split: 40%% of %.0f damage over 3 allies, capped at 12%% max HP each" % dealt, ok)
	ctx.check("Thornbloom: the heals are ultimate heals (exempt from the 6%/s passive cap)", out.filter(func(e): return e["type"] == "race_heal").all(func(e): return bool(e["ultimate"])))
	var tu := squad(["elf", "elf", "elf"])
	var tuf := Act.enemies(tu.sim)
	Act.place(tu.sim, tu.sim.bodies[2].position, {tuf[0]: Vector3(1, 0, 0), tuf[1]: Vector3(-1, 0, 0), tuf[2]: Vector3(0, 0, 1)})
	ctx.check("Thornbloom use: 3 enemies, nobody hurt -> holds", not _matches(tu.sim, 2))
	tu.sim.fighters[1].hp = tu.sim.fighters[1].max_hp() * 0.7
	ctx.check("Thornbloom use: 3 enemies and an ally below 75% -> fires", _matches(tu.sim, 2))
	Act.place(tu.sim, tu.sim.bodies[2].position, {tuf[0]: Vector3(1, 0, 0), tuf[1]: Vector3(-1, 0, 0), tuf[2]: Vector3(0, 0, 1), tuf[3]: Vector3(0, 0, -1)})
	tu.sim.fighters[1].hp = tu.sim.fighters[1].max_hp()
	ctx.check("Thornbloom use: 4 enemies -> fires even with nobody hurt", _matches(tu.sim, 2))

	# E/Bow Guardian Seedshot: heal the most-hurt ally 15% + regen 6 s; then 4 arrows 100% 0.25 s apart at the enemy nearest that ally, slow.
	var g := squad(["elf", "elf", "elf"])
	var gsim = g.sim
	var gf := Act.enemies(gsim)
	gsim.fighters[1].hp = gsim.fighters[1].max_hp() * 0.3
	gsim.fighters[2].hp = gsim.fighters[2].max_hp() * 0.6
	for id in [1, 2]:
		gsim.fighters[id].race_state["pseudo"] = {}
		gsim.fighters[id].effects.clear()
	Act.place(gsim, gsim.bodies[1].position, {gf[0]: Vector3(1.5, 0, 0), gf[1]: Vector3(3.0, 0, 0)})
	var batk: float = gsim.fighters[3].stat("ATK")
	out = cast(g, 3)
	out.append_array(run_ticks(gsim, 60))
	hits = damage_by(out, 3)
	ctx.check("Seedshot: the most-hurt ally heals 15%% + regen 6 s (%.3f)" % (gsim.fighters[1].hp / gsim.fighters[1].max_hp()),
		gsim.fighters[1].hp / gsim.fighters[1].max_hp() >= 0.449 and int(gsim.fighters[1].effects.get("regen", {}).get("left", 0)) >= 300)  # (the Elf Trio wave-start regen may stack its own time on top)
	ctx.check("Seedshot: 4 arrows of 100%% at the enemy nearest that ally, 15 ticks apart (%s)" % [hits.map(func(e): return [e["target"], e["damage"]])],
		hits.size() == 4 and hits.all(func(e): return int(e["target"]) == gf[0] and is_equal_approx(float(e["damage"]), roundf(batk))))
	var gu := squad(["elf", "elf", "elf"])
	var guf := Act.enemies(gu.sim)
	Act.place(gu.sim, gu.sim.bodies[1].position, {guf[0]: Vector3(1, 0, 0), guf[1]: Vector3(-1, 0, 0)})
	gu.sim.fighters[1].hp = gu.sim.fighters[1].max_hp() * 0.7
	ctx.check("Seedshot use: an ally at 70% -> holds", not _matches(gu.sim, 3))
	gu.sim.fighters[1].hp = gu.sim.fighters[1].max_hp() * 0.6
	ctx.check("Seedshot use: an ally below 65% with 2 enemies on them -> fires", _matches(gu.sim, 3))
	Act.place(gu.sim, gu.sim.bodies[1].position, {})
	ctx.check("Seedshot use: the same ally with nobody on them -> holds", not _matches(gu.sim, 3))

	# E/Magic Rebirth Bloom: revive downed at 35% (once per ally per wave), heal all 20%, regen 6 s on all.
	var r := squad(["elf", "elf", "elf"], MAGIC_SQUAD)
	var rsim = r.sim
	rsim.enable_coop([1, 2, 3])
	preload("res://logic/coop.gd").down(rsim, 1, {"type": "killed", "target": 1})
	ctx.check("Rebirth Bloom use: an ally downed -> fires at once", _matches(rsim, 3))
	rsim.fighters[2].hp = rsim.fighters[2].max_hp() * 0.5
	for id in [1, 2]:
		rsim.fighters[id].race_state["pseudo"] = {}
	out = cast(r, 3)
	ctx.check("Rebirth Bloom: the downed ally stands up (35%% + the 20%% squad heal = %.2f)" % (rsim.fighters[1].hp / rsim.fighters[1].max_hp()),
		rsim.fighters[1].is_alive() and absf(rsim.fighters[1].hp / rsim.fighters[1].max_hp() - 0.55) < 0.001)
	ctx.check("Rebirth Bloom: living allies heal 20% and everyone gets regen 6 s", absf(rsim.fighters[2].hp / rsim.fighters[2].max_hp() - 0.7) < 0.001
		and [1, 2, 3].all(func(id): return rsim.fighters[id].effects.has("regen")))
	var ru := squad(["elf", "elf", "elf"], MAGIC_SQUAD)
	ru.sim.fighters[1].hp = ru.sim.fighters[1].max_hp() * 0.6
	ctx.check("Rebirth Bloom use: squad average 87% -> holds", not _matches(ru.sim, 3))
	for id in [1, 2, 3]:
		ru.sim.fighters[id].hp = ru.sim.fighters[id].max_hp() * 0.5
	ctx.check("Rebirth Bloom use: squad average below 55% -> fires", _matches(ru.sim, 3))


## Runeborn (cyan/violet): release in 4 shapes (team shield, slam + lingering zone, delayed glyphs, damage-to-shield);
## every cast also fills the card's rune passive (ultimate_cast, gain max) so it discharges at once (3.4).
func _runeborn(ctx) -> void:
	var data = RaceData.load_default()
	ctx.check("Runeborn: 4 class ultimates + a default; Runebreaker plays the class charge clip", ["sword_shield", "greatsword", "longbow", "magic"].all(func(c): return not str(data.ultimate_for("runeborn", c).get("name", "")).is_empty())
		and data.ultimate_for("runeborn", "no_such_class")["name"] == "Rune Ward" and str(data.ultimate_for("runeborn", "greatsword")["clip"]) == "charge")
	# R/S&S Bastion Glyph: shield all 15% of the caster's max HP 8 s (ultimate cap 50%), taunt r5 3 s; Rune Aegis discharges.
	var f := squad(["runeborn", "runeborn", "runeborn"])
	var sim = f.sim
	var foes := Act.enemies(sim)
	Act.place(sim, sim.bodies[1].position, {foes[0]: Vector3(2, 0, 0)})
	RacePassives.step(sim)  # wave start (the Runeborn Trio wave shield lands first)
	for id in [1, 2, 3]:
		sim.fighters[id].clear_shield()
	var tank = sim.fighters[1]
	var out := cast(f, 1)
	var shields: Array = out.filter(func(e): return e["type"] == "race_shield" and bool(e["ultimate"]))
	var ok := shields.size() == 3
	for e in shields:
		var target = sim.fighters[int(e["target"])]
		ok = ok and is_equal_approx(float(e["amount"]), minf(0.15 * tank.max_hp(), 0.5 * target.max_hp()))
	ctx.check("Bastion Glyph: every ally shielded 15%% of the tank's max HP (%s)" % [shields.map(func(e): return snappedf(float(e["amount"]), 0.1))], ok)
	ctx.check("Bastion Glyph: taunt 3 s", out.any(func(e): return e["type"] == "race_taunt" and int(e["ticks"]) == 180))
	ctx.check("Bastion Glyph: Rune Aegis discharges at once (ultimate_cast fills the runes)", out.any(func(e): return e["type"] == "race_proc" and int(e["player"]) == 1 and e["on"] == "ultimate_cast" and bool(e.get("discharge", false)))
		and tank.effects.has("fortify"))
	var b := squad(["runeborn", "runeborn", "runeborn"])
	var bf := Act.enemies(b.sim)
	Act.place(b.sim, b.sim.bodies[1].position, {bf[0]: Vector3(2, 0, 0), bf[1]: Vector3(-2, 0, 0)})
	ctx.check("Bastion Glyph use: 2 enemies in 5 m, nobody hurt -> holds", not _matches(b.sim, 1))
	Act.place(b.sim, b.sim.bodies[1].position, {bf[0]: Vector3(2, 0, 0), bf[1]: Vector3(-2, 0, 0), bf[2]: Vector3(0, 0, 3)})
	ctx.check("Bastion Glyph use: 3 enemies in 5 m -> fires", _matches(b.sim, 1))
	Act.place(b.sim, b.sim.bodies[1].position, {})
	b.sim.fighters[2].hp = b.sim.fighters[2].max_hp() * 0.6
	b.sim.fighters[3].hp = b.sim.fighters[3].max_hp() * 0.6
	ctx.check("Bastion Glyph use: 2 allies below 70% -> fires", _matches(b.sim, 1))

	# R/GS Runebreaker: 200% + shock in r3 at densest within 4 m; a zone there 3 s, 35% every 0.5 s; Runic Edge discharges.
	var r := squad(["runeborn", "runeborn", "runeborn"])
	var rsim = r.sim
	var rf := Act.enemies(rsim)
	Act.place(rsim, rsim.bodies[2].position, {rf[0]: Vector3(3, 0, 0), rf[1]: Vector3(3.5, 0, 1), rf[2]: Vector3(3.5, 0, -1), rf[3]: Vector3(-3.5, 0, 0)})
	for e in rf:
		rsim.fighters[e].control_immune_left = 0
		rsim.fighters[e].stats["EFFECT_RES"] = 0.0
	var gatk: float = rsim.fighters[2].stat("ATK")
	var all := cast(r, 2)
	var slam: Array = damage_by(all, 2).filter(func(e): return is_equal_approx(float(e["damage"]), roundf(gatk * 2.0)))
	ctx.check("Runebreaker: 200%% on the 3-pack at the densest point, not the lone one (%d)" % slam.size(), slam.size() == 3 and not slam.any(func(e): return int(e["target"]) == rf[3]))
	ctx.check("Runebreaker: the pack is shocked", [rf[0], rf[1], rf[2]].all(func(e): return rsim.fighters[e].effects.has("shock")))
	ctx.check("Runebreaker: Runic Edge discharges at once", all.any(func(e): return e["type"] == "race_proc" and int(e["player"]) == 2 and e["on"] == "ultimate_cast"))
	all.append_array(run_ticks(rsim, 200))
	var glyph: Array = damage_by(all, 2).filter(func(e): return int(e["target"]) == rf[0] and is_equal_approx(float(e["damage"]), roundf(gatk * 0.35)))
	ctx.check("Runebreaker: the glyph zone hits 35%% every 0.5 s for 3 s = 6 pulses (%d)" % glyph.size(), glyph.size() == 6)
	var ru := squad(["runeborn", "runeborn", "runeborn"])
	var ruf := Act.enemies(ru.sim)
	Act.place(ru.sim, ru.sim.bodies[2].position, {ruf[0]: Vector3(3, 0, 0), ruf[1]: Vector3(3.5, 0, 1)})
	ctx.check("Runebreaker use: 2 enemies in r3 -> holds", not _matches(ru.sim, 2))
	Act.place(ru.sim, ru.sim.bodies[2].position, {ruf[0]: Vector3(3, 0, 0), ruf[1]: Vector3(3.5, 0, 1), ruf[2]: Vector3(3.5, 0, -1)})
	ctx.check("Runebreaker use: 3 enemies in r3 of a point within 4 m -> fires", _matches(ru.sim, 2))
	Act.place(ru.sim, ru.sim.bodies[2].position, {ruf[0]: Vector3(8, 0, 0), ruf[1]: Vector3(8.5, 0, 1), ruf[2]: Vector3(8.5, 0, -1)})
	ctx.check("Runebreaker use: the pack beyond 4 m -> holds", not _matches(ru.sim, 2))

	# R/Bow Glyph Barrage: 6 arrows 70% over 1.2 s spread over distinct enemies within 12 m (the rest on the boss, else
	# the nearest); each hit leaves a glyph: 2 s later 60% in r1.5 + sunder; Glyph Shot discharges (focus + shield).
	var g := squad(["runeborn", "runeborn", "runeborn"])
	var gsim = g.sim
	var gf := Act.enemies(gsim)
	Act.place(gsim, gsim.bodies[3].position, {gf[0]: Vector3(5, 0, 0), gf[1]: Vector3(7, 0, 3), gf[2]: Vector3(9, 0, -3)})
	var batk: float = gsim.fighters[3].stat("ATK")
	all = cast(g, 3)
	all.append_array(run_ticks(gsim, 220))
	var arrows: Array = damage_by(all, 3).filter(func(e): return is_equal_approx(float(e["damage"]), roundf(batk * 0.7)))
	var targets := {}
	for e in arrows:
		targets[int(e["target"])] = int(targets.get(int(e["target"]), 0)) + 1
	ctx.check("Glyph Barrage: 6 arrows of 70%%, each of the 3 enemies hit first, then the nearest (%s)" % [targets], arrows.size() == 6 and targets.size() == 3 and int(targets[gf[0]]) == 4)
	var glyphs: Array = damage_by(all, 3).filter(func(e): return is_equal_approx(float(e["damage"]), roundf(batk * 0.6)))
	ctx.check("Glyph Barrage: 6 glyphs detonate 60%% 2 s later (%d hits on enemies standing in them)" % glyphs.size(), glyphs.size() >= 6 and gsim.fighters[gf[1]].effects.has("sunder"))
	ctx.check("Glyph Barrage: Glyph Shot discharges (focus)", gsim.fighters[3].effects.has("focus"))
	var gu := squad(["runeborn", "runeborn", "runeborn"])
	var guf := Act.enemies(gu.sim)
	Act.place(gu.sim, gu.sim.bodies[3].position, {guf[0]: Vector3(6, 0, 0), guf[1]: Vector3(8, 0, 0)})
	ctx.check("Glyph Barrage use: 2 enemies in 12 m -> holds", not _matches(gu.sim, 3))
	gu.sim.fighters[guf[0]].enemy_type = "goblin_chief"
	ctx.check("Glyph Barrage use: the boss within 12 m -> fires", _matches(gu.sim, 3))

	# R/Magic Arcane Singularity: zone r4 4 s at densest within 9 m, 45% every 0.5 s, shock on the first pulse;
	# on_end: shield all 30% of the zone's damage, split, cap 15% max HP each; Runeweaver discharges (shield all 10%).
	var a := squad(["runeborn", "runeborn", "runeborn"], MAGIC_SQUAD)
	var asim = a.sim
	var af := Act.enemies(asim)
	Act.place(asim, asim.bodies[3].position, {af[0]: Vector3(6, 0, 0), af[1]: Vector3(6.5, 0, 1), af[2]: Vector3(6.5, 0, -1)})
	for e in af:
		asim.fighters[e].control_immune_left = 0
		asim.fighters[e].stats["EFFECT_RES"] = 0.0
	RacePassives.step(asim)
	for id in [1, 2, 3]:
		asim.fighters[id].clear_shield()
	var matk: float = asim.fighters[3].stat("ATK")
	all = cast(a, 3)
	ctx.check("Singularity: Runeweaver discharges on the cast (shield all 10% of the mage's max HP)", all.any(func(e): return e["type"] == "race_proc" and int(e["player"]) == 3 and e["on"] == "ultimate_cast"))
	all.append_array(run_ticks(asim, 260))
	var shocks: Array = all.filter(func(e): return e["type"] == "effect_applied" and e["effect"] == "shock" and int(e["source"]) == 3)
	var pulses: Array = damage_by(all, 3).filter(func(e): return int(e["target"]) == af[0] and is_equal_approx(float(e["damage"]), roundf(matk * 0.45)))
	ctx.check("Singularity: 8 pulses of 45%% on each enemy inside (%d)" % pulses.size(), pulses.size() == 8)
	var first_pulse := all.find(all.filter(func(e): return e["type"] == "race_zone_pulse")[0])
	var at_first: int = all.slice(0, first_pulse + 1).filter(func(e): return e["type"] == "effect_applied" and e["effect"] == "shock").size()
	ctx.check("Singularity: shock on the first pulse only (%d at the first pulse, %d in all)" % [at_first, shocks.size()], at_first == 3 and shocks.size() == 3)
	var zone_dmg := 0.0
	for e in all:
		if e["type"] == "race_zone_end" and int(e["player"]) == 3:
			zone_dmg = float(e["damage"])
	var end_at := -1
	for i in all.size():
		if all[i]["type"] == "race_zone_end" and int(all[i]["player"]) == 3:
			end_at = i
	var ends: Array = []
	for i in range(maxi(0, end_at - 6), end_at):  # the on_end shields come just before the zone_end event
		if all[i]["type"] == "race_shield" and int(all[i]["player"]) == 3 and bool(all[i]["ultimate"]):
			ends.append(all[i])
	var ok_end := ends.size() == 3
	for e in ends:
		ok_end = ok_end and absf(float(e["amount"]) - minf(0.30 * zone_dmg / 3.0, 0.15 * asim.fighters[3].max_hp())) < 0.01  # cap_max_hp is of the caster (4.3 shield_amount)
	ctx.check("Singularity on_end: 30%% of the zone's %.0f damage, split over 3, cap 15%% max HP (%s)" % [zone_dmg, ends.map(func(e): return snappedf(float(e["amount"]), 0.1))], ok_end and zone_dmg > 0.0)
	var au := squad(["runeborn", "runeborn", "runeborn"], MAGIC_SQUAD)
	var auf := Act.enemies(au.sim)
	Act.place(au.sim, au.sim.bodies[3].position, {auf[0]: Vector3(6, 0, 0), auf[1]: Vector3(6.5, 0, 1)})
	ctx.check("Singularity use: 2 enemies in r4 -> holds", not _matches(au.sim, 3))
	Act.place(au.sim, au.sim.bodies[3].position, {auf[0]: Vector3(6, 0, 0), auf[1]: Vector3(6.5, 0, 1), auf[2]: Vector3(7, 0, -2)})
	ctx.check("Singularity use: 3 enemies in r4 of a point within 9 m -> fires", _matches(au.sim, 3))


## Every one of the 16 ultimates fires in a real squad fight driven by the pilot (GDD 10: fired count > 0 per cell).
func _all_fire_in_play(ctx) -> void:
	var fired := {}
	for races in [["human", "human", "human"], ["viking", "viking", "viking"], ["elf", "elf", "elf"], ["runeborn", "runeborn", "runeborn"]]:
		for cards in [RaceTest.CARDS, MAGIC_SQUAD]:
			var f := RaceTest.squad(races, cards)
			var sim = f.sim
			var memories := {}
			for id in [1, 2, 3]:
				sim.set_class_style(id, str(preload("res://logic/card_deck.gd").class_data(cards[id - 1]).get("weapon", "")))
				memories[id] = Pilot.new_memory(id * 7919 + 1)
			for tick in 60 * 150:
				if sim.living_enemy_count() + sim.pending_wave_count() == 0:
					break
				for id in [1, 2, 3]:
					sim.set_input(id, preload("res://logic/sim_input.gd").decode(Pilot.decide(sim, f.combat, id, memories[id], tick).encode()))
				sim.tick()
				for e in sim.events:
					if e["type"] == "ultimate_cast":
						fired["%s:%s" % [e["race"], e["class"]]] = int(fired.get("%s:%s" % [e["race"], e["class"]], 0)) + 1
	var missing: Array = []
	for race in ["human", "viking", "elf", "runeborn"]:
		for c in ["sword_shield", "greatsword", "longbow", "magic"]:
			if not fired.has("%s:%s" % [race, c]):
				missing.append("%s:%s" % [race, c])
	ctx.check("all 16 ultimates fire in a 150 s pilot squad fight (missing %s)" % [missing], missing.is_empty())
