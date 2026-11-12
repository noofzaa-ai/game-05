extends RefCounted
## Race ultimates (design/gdd/races-and-classes.md 3.10, 4.7; phases 5-7). Chunk B: the gauge is back on safely
## (3.10.6): the race engine fills it by formula 4.7 with the class rates, the skill system and motion prediction
## no longer wipe it, the old gains skip race cards, checkpoints keep it, it carries across waves and clears at run end.
const RaceTest := preload("res://tests/test_race_passives.gd")
const F := preload("res://tests/online_fixture.gd")
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const Fighter := preload("res://logic/fighter.gd")
const Combat := preload("res://logic/combat.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const RaceData := preload("res://logic/race_data.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Deck := preload("res://logic/card_deck.gd")


func run(ctx) -> void:
	_gauge_data(ctx)
	_formula_examples(ctx)
	_gauge_sources(ctx)
	_old_gains_skip_race_cards(ctx)
	_no_wipe(ctx)
	_switch_off(ctx)
	_fight_fills_and_skills_cast(ctx)
	_checkpoint_and_waves(ctx)
	_run_end_clears(ctx)


static func enemy(sim) -> int:
	return RaceTest.enemy_of(sim)


## A squad card with ATK and max HP set to round numbers (no race stat effects on ATK).
static func card(sim, id: int, atk: float, max_hp: float):
	var f = sim.fighters[id]
	f.stats["ATK"] = atk
	f.stats["HP"] = max_hp
	f.hp = max_hp
	f.stat_mods.clear()
	f.gauge = 0.0
	return f


func _gauge_data(ctx) -> void:
	var data = RaceData.load_default()
	ctx.check("rules.json: ultimates_enabled on and the gauge rule 1.5 / 2.0 / 1.2 / 2.0 / 4", bool(data.rules["ultimates_enabled"])
		and data.rules["gauge"] == {"time": 1.5, "dealt": 2.0, "taken": 1.2, "support": 2.0, "kill": 4.0} and data.errors.is_empty())
	ctx.check("class gauge rates: S&S dealt 0.8 taken 1.4, bow taken 0.6, magic support 1.2",
		Deck.class_data("sword_shield")["gauge"] == {"dealt": 0.8, "taken": 1.4, "support": 1.0} and float(Deck.class_data("longbow")["gauge"]["taken"]) == 0.6
		and float(Deck.class_data("magic")["gauge"]["support"]) == 1.2 and float(Deck.class_data("greatsword")["gauge"]["dealt"]) == 1.0)


## Formula 4.7 examples, one second of each (time 60 ticks + the second's damage in one tick).
func _formula_examples(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	var foe := enemy(sim)
	# Greatsword ATK 150 dealing 1.3x ATK/s -> 1.5 + 2.6 = 4.1/s.
	var gs = card(sim, 2, 150.0, 1000.0)
	var gain := 0.0
	for t in 59:
		gain += RacePassives.gain_gauge(sim, 2, gs, [], true)
	gain += RacePassives.gain_gauge(sim, 2, gs, [{"type": "hit", "attacker": 2, "target": foe, "damage": 195.0, "move": "greatsword_light_1"}], true)
	ctx.check("formula 4.7: greatsword 1.3x ATK/s -> 4.1/s (%.3f)" % gain, absf(gain - 4.1) < 0.001)
	# Tank taking 1.5% max HP/s, dealing 0.6x ATK/s -> 1.5 + 0.8*2*0.6 + 1.4*1.2*1.5 = 5.0/s.
	var tank = card(sim, 1, 100.0, 1000.0)
	gain = 0.0
	for t in 59:
		gain += RacePassives.gain_gauge(sim, 1, tank, [], true)
	gain += RacePassives.gain_gauge(sim, 1, tank, [{"type": "hit", "attacker": 1, "target": foe, "damage": 60.0, "move": "blade_light_1"},
		{"type": "hit", "attacker": foe, "target": 1, "damage": 15.0, "move": "goblin_jab", "absorbed": 0.0}], true)
	ctx.check("formula 4.7: tank 1.5%% max HP taken + 0.6x ATK dealt -> 4.98/s (%.3f)" % gain, absf(gain - 4.98) < 0.001)
	# Bow dealing 1.6x ATK/s -> 1.5 + 3.2 = 4.7/s.
	var bow = card(sim, 3, 100.0, 800.0)
	gain = 0.0
	for t in 59:
		gain += RacePassives.gain_gauge(sim, 3, bow, [], true)
	gain += RacePassives.gain_gauge(sim, 3, bow, [{"type": "hit", "attacker": 3, "target": foe, "damage": 160.0, "move": "longbow_light_1"}], true)
	ctx.check("formula 4.7: bow 1.6x ATK/s -> 4.7/s (%.3f)" % gain, absf(gain - 4.7) < 0.001)
	# Mage dealing 1.2x + healing allies 0.3x ATK/s -> 1.5 + 2.4 + 1.2*2.0*0.3 = 4.62/s.
	var m := RaceTest.squad(["human", "human", "human"], ["sword_shield", "greatsword", "magic"])
	var msim = m.sim
	var mage = card(msim, 3, 100.0, 750.0)
	gain = 0.0
	for t in 59:
		gain += RacePassives.gain_gauge(msim, 3, mage, [], true)
	gain += RacePassives.gain_gauge(msim, 3, mage, [{"type": "skill_hit", "attacker": 3, "target": enemy(msim), "damage": 120.0, "move": "skill:fireball"},
		{"type": "race_heal", "player": 3, "target": 1, "amount": 30.0}], true)
	ctx.check("formula 4.7: mage 1.2x dealt + 0.3x ATK healed -> 4.62/s (%.3f)" % gain, absf(gain - 4.62) < 0.001)
	ctx.check("formula 4.7: greatsword full in ~22-25 s at 4.1/s", 100.0 / 4.1 > 22.0 and 100.0 / 4.1 < 25.0)


func _gauge_sources(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	var foe := enemy(sim)
	var gs = card(sim, 2, 100.0, 1000.0)
	ctx.check("gauge: a kill gives +4 (+ the tick's time)", absf(RacePassives.gain_gauge(sim, 2, gs, [{"type": "killed", "target": foe, "by": 2}], true) - 4.025) < 0.0001)
	gs.gauge = 0.0
	ctx.check("gauge: no time gain with no living enemy", RacePassives.gain_gauge(sim, 2, gs, [], false) == 0.0)
	ctx.check("gauge: damage taken counts after the shield (100 blow, 60 absorbed -> 40 = 4%% -> 4.8)",
		absf(RacePassives.gain_gauge(sim, 2, gs, [{"type": "hit", "attacker": foe, "target": 2, "damage": 100.0, "absorbed": 60.0, "move": "goblin_jab"}], false) - 4.8) < 0.0001)
	gs.gauge = 0.0
	ctx.check("gauge: healing yourself is not support", RacePassives.gain_gauge(sim, 2, gs, [{"type": "race_heal", "player": 2, "target": 2, "amount": 500.0}], false) == 0.0)
	ctx.check("gauge: an ultimate's damage never feeds it (no chaining)", RacePassives.gain_gauge(sim, 2, gs,
		[{"type": "race_burst_hit", "attacker": 2, "target": foe, "damage": 500.0, "ultimate": true}, {"type": "hit", "attacker": 2, "target": foe, "damage": 500.0, "move": "x_ultimate"}], false) == 0.0)
	gs.state = Fighter.State.ATTACK
	gs.move_id = "human_greatsword_ultimate"
	ctx.check("gauge: no gain while the ultimate is casting", RacePassives.gain_gauge(sim, 2, gs, [{"type": "killed", "target": foe, "by": 2}], true) == 0.0)
	gs.state = Fighter.State.IDLE
	gs.move_id = ""
	gs.gauge = 99.0
	RacePassives.gain_gauge(sim, 2, gs, [{"type": "killed", "target": foe, "by": 2}], true)
	ctx.check("gauge: capped at ultimate_gauge_max, overflow lost", gs.gauge == 100.0)
	ctx.check("gauge: running totals by source for class_sim", float(gs.race_state["gauge_by"].get("kill", 0.0)) >= 8.0 and gs.race_state["gauge_by"].has("taken"))


## The old gains (gauge_per_hit_dealt on a melee hit, ULTREGEN per tick) skip a race card; plain fighters keep them.
func _old_gains_skip_race_cards(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	var foe := enemy(sim)
	var tank = sim.fighters[1]
	tank.gauge = 0.0
	tank.direction = Vector2i(1, 0)
	Combat.apply_hit(1, foe, str(sim.combat.styles[tank.style]["ground_light"]), sim.fighters, sim.bodies, sim.combat, sim.rng, sim.events)
	ctx.check("race card: a melee hit no longer adds gauge_per_hit_dealt (counted once by the race engine)", tank.gauge == 0.0)
	tank.stats["ULTREGEN"] = 60.0
	Combat._tick_timers(tank, sim.combat)
	ctx.check("race card: ULTREGEN does not fill the race gauge", tank.gauge == 0.0)
	var plain = sim.fighters[foe]
	plain.stats["ULTREGEN"] = 60.0
	plain.gauge = 0.0
	Combat._tick_timers(plain, sim.combat)
	ctx.check("a fighter without a race keeps ULTREGEN", is_equal_approx(plain.gauge, 1.0))


## The skill system's view publish and motion prediction no longer zero a race card's gauge.
func _no_wipe(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	ctx.check("skill-build system is on (the case that wiped the gauge)", preload("res://logic/skill_build.gd").enabled() and sim.skill_system != null and sim.skill_system.casters.has(1))
	sim.fighters[1].gauge = 50.0
	sim.skill_system.publish_views()
	ctx.check("publish_views keeps a race card's gauge", sim.fighters[1].gauge == 50.0)
	sim.fighters[1].gauge = 40.0
	var motion = preload("res://logic/skills/motion_prediction.gd").new()
	motion.setup(sim, 1, sim.skill_system.builds[1], sim.fighters[1].skill_view)
	motion.before_tick()
	motion.advance()
	ctx.check("motion prediction keeps it too (prediction and authority agree)", sim.fighters[1].gauge == 40.0)
	motion.system.dispose()


## ultimates_enabled false: today's behaviour (gauge retired, old rules).
func _switch_off(ctx) -> void:
	var rules: Dictionary = RaceData.load_default().rules
	rules["ultimates_enabled"] = false
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	sim.fighters[1].gauge = 50.0
	sim.skill_system.publish_views()
	var wiped: bool = sim.fighters[1].gauge == 0.0
	sim.fighters[2].gauge = 0.0
	sim.events.clear()
	RacePassives.step(sim)
	var no_gain: bool = sim.fighters[2].gauge == 0.0
	rules["ultimates_enabled"] = true
	ctx.check("ultimates_enabled false: the gauge stays retired (wiped on publish)", wiped and not RacePassives.owns_gauge(Fighter.new()))
	ctx.check("ultimates_enabled false: the race engine does not fill it", no_gain)


## A real squad fight with the pilot: gauges fill from 0 and class skills still cast in the same run.
func _fight_fills_and_skills_cast(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "elf"])
	var sim = f.sim
	var memories := {}
	for id in [1, 2, 3]:
		sim.set_class_style(id, str(Deck.class_data(RaceTest.CARDS[id - 1]).get("weapon", "")))
		memories[id] = Pilot.new_memory(id * 7919 + 1)
		sim.fighters[id].gauge = 0.0
	var casts := 0
	for tick in 1200:
		for id in [1, 2, 3]:
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick).encode()))
		sim.tick()
		casts += sim.events.filter(func(e): return e["type"] == "skill_cast").size()
	var gauges: Array = [1, 2, 3].map(func(id): return snappedf(sim.fighters[id].gauge, 0.1))
	ctx.check("20 s squad fight: every card's gauge filled (%s)" % [gauges], gauges.all(func(g): return g >= 20.0))
	ctx.check("20 s squad fight: class skills still cast (%d)" % casts, casts > 0)


## Checkpoint keeps the gauge; a new wave does not reset it.
func _checkpoint_and_waves(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	RacePassives.step(sim)
	sim.fighters[2].gauge = 37.5
	sim.fighters[2].race_state["gauge_by"] = {"time": 3.0}
	var copy = Sim.new(World.new(), f.combat, F.rng(1))
	copy.item_rules = f.rules
	copy.loot_data = f.loot
	copy.restore({"v": 1, "checkpoint": JSON.parse_string(JSON.stringify(sim.snapshot()["checkpoint"]))}, f.camp)
	ctx.check("checkpoint keeps the race gauge", copy.fighters[2].gauge == 37.5 and float(copy.fighters[2].race_state["gauge_by"]["time"]) == 3.0)
	sim._waves_released += 1  # the next wave arrives
	sim.events.clear()
	RacePassives.step(sim)
	ctx.check("the gauge carries into the next wave (%.3f)" % sim.fighters[2].gauge, sim.fighters[2].gauge >= 37.5)
	# Between stages/fights the party journey carries each member's own gauge (not the primary's).
	for id in [1, 2, 3]:
		sim.fighters[id].gauge = 10.0 * id
	f.journey.capture_party(sim)
	ctx.check("journey carry: one gauge per squad member", [1, 2, 3].all(func(id): return float(f.journey.gauge_by_player[id]) == 10.0 * id))


func _run_end_clears(ctx) -> void:
	var f := RaceTest.squad(["human", "human", "human"])
	var sim = f.sim
	for id in [1, 2, 3]:
		sim.fighters[id].gauge = 60.0
	f.journey.capture_party(sim)
	f.journey.died()
	ctx.check("run end (party lost): every carried gauge is 0", f.journey.gauge_by_player.values().all(func(g): return float(g) == 0.0) and f.journey.gauge == 0.0)
	f.journey.capture_party(sim)
	ctx.check("run end: a late capture does not bring it back", f.journey.gauge_by_player.values().all(func(g): return float(g) == 0.0))
	var solo := RaceTest.squad(["elf"], ["longbow"])
	solo.journey.gauge = 70.0
	solo.journey.died()
	solo.journey.gauge = 55.0  # (what a client capture after the death would write)
	ctx.check("run end (solo): the gauge is cleared and stays 0", solo.journey.gauge == 0.0)
	var copy = preload("res://logic/journey.gd").from_dict(JSON.parse_string(JSON.stringify(solo.journey.to_dict())), solo.data, solo.rules, solo.camp, solo.loot, solo.combat.weapon_ids)
	ctx.check("run end: a saved finished journey loads with gauge 0", copy != null and copy.gauge == 0.0)
