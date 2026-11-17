extends RefCounted
## Regression (Boss bug 2026-11-17, live wave 9): the Magic card stood still and never attacked the Goblin Chief.
## Starfall (a point skill, kind delayed_circle) was picked by its `boss_near` rule, a race condition that gave no
## "point"; ClassSkills.cast refused it ("no_target", nothing spent), so the pilot picked it again every tick and
## never reached its bolts. Fix: logic/class_skills/use_rules.gd _race_point gives such a choice the boss's position.
const Fixture := preload("res://tests/test_class_skills.gd")
const UseRules := preload("res://logic/class_skills/use_rules.gd")
const Skills := preload("res://logic/class_skills/engine.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")

const BOSS := 20


func run(ctx) -> void:
	_choice(ctx)
	_pilot_vs_lone_boss(ctx)


## A Runeborn Magic card (race_state as RacePassives.attach builds it, so the full tick runs the race step) and the
## Chief alone (no dense point: only the boss_near rule can pick Starfall).
static func _scene():
	var sim = Fixture.world(["magic"], 0)
	var races = preload("res://logic/race_data.gd").load_default()
	var effects: Array = []
	for effect in races.passive_for("runeborn", "magic").get("effects", []):
		effects.append({"src": "passive", "effect": effect.duplicate(true)})
	sim.fighters[1].race_state = {"race": "runeborn", "class": "magic", "passive": "", "synergy": "none", "effects": effects, "fx": {}, "pseudo": {},
		"scaling": [], "wave": 0, "heal_window": [-1, 0.0], "ultimate": races.ultimate_for("runeborn", "magic").duplicate(true), "full_at": -1, "group": ""}
	sim.add_enemy(BOSS, Vector3(6, 0, 0), "goblin_chief")
	sim.fighters[BOSS].stats["HP"] = 100000.0
	sim.fighters[BOSS].hp = 100000.0
	return sim


func _choice(ctx) -> void:
	var sim = _scene()
	var choice := UseRules.choose(sim, 1, "starfall", BOSS)
	ctx.check("Starfall on boss_near: the choice has a point (%s)" % [choice], choice.get("point") is Vector3)
	ctx.check("Starfall on boss_near: aimed at the boss", int(choice.get("target", -1)) == BOSS and choice.get("point") is Vector3 and Vector2(choice["point"].x, choice["point"].z).distance_to(Vector2(6, 0)) < 0.01)
	ctx.check("Starfall on boss_near: the cast starts (no 'no_target' refusal)", Skills.cast(sim, 1, "starfall", choice) == "")
	var far = _scene()
	Fixture.put(far, BOSS, Vector3(11, 0, 0))
	ctx.check("Starfall: boss beyond 9 m -> not picked", UseRules.choose(far, 1, "starfall", BOSS).is_empty())


## The full tick loop (AutoPilot -> GameSim): over 10 s the card casts Starfall and keeps shooting; it never stands
## for more than 2 s pressing a skill that does not start (before the fix: frozen the whole time, 0 damage).
func _pilot_vs_lone_boss(ctx) -> void:
	var sim = _scene()
	var memory := Pilot.new_memory(7)
	var hp_before: float = sim.fighters[BOSS].hp
	var starfalls := 0
	var attacking := 0
	var stuck := 0
	var worst := 0
	for tick in 600:
		var input: SimInput = Pilot.decide(sim, sim.combat, 1, memory, tick)
		sim.set_input(1, SimInput.decode(input.encode()))
		sim.tick()
		for event in sim.events:
			if str(event["type"]) == "skill_cast" and str(event.get("skill", "")) == "starfall":
				starfalls += 1
		var me: Fighter = sim.fighters[1]
		if me.state == Fighter.State.ATTACK:
			attacking += 1
		stuck = stuck + 1 if input.skill_slot >= 0 and me.state == Fighter.State.IDLE and not Skills.busy(me) else 0
		worst = maxi(worst, stuck)
	var dealt: float = hp_before - sim.fighters[BOSS].hp
	ctx.check("Magic vs lone Chief: Starfall cast at least once (%d)" % starfalls, starfalls >= 1)
	ctx.check("Magic vs lone Chief: never stuck re-pressing a refused skill > 2 s (worst %d ticks)" % worst, worst <= 120)
	ctx.check("Magic vs lone Chief: attacks with its bolts (%d ticks in ATTACK)" % attacking, attacking >= 120)
	ctx.check("Magic vs lone Chief: deals damage to the boss (%.0f)" % dealt, dealt > 0.0)
