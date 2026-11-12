extends RefCounted
## Class identity (design/gdd/races-and-classes.md 3.2, phase 3): per-class pilot profiles in data/classes/*.json
## (peel / densest / lowest_hp + boss_first + kite / magic hold + frost_armor support, Hunter's Mark focus fire,
## heavy_every) and the class signatures Cleave (greatsword) and Hunter's Mark (longbow).
const RaceTest := preload("res://tests/test_race_passives.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const Combat := preload("res://logic/combat.gd")
const Deck := preload("res://logic/card_deck.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")


func run(ctx) -> void:
	_profiles_in_data(ctx)
	_no_pilot_is_old_behaviour(ctx)
	_peel(ctx)
	_densest_and_cleave_target(ctx)
	_longbow_target_and_kite(ctx)
	_marked_focus(ctx)
	_heavy_every(ctx)
	_magic_hold(ctx)
	_hunters_mark(ctx)
	_cleave(ctx)


static func enemies(sim) -> Array:
	var ids: Array = sim.fighters.keys().filter(func(id): return sim.fighters[id].team == "enemy" and sim.fighters[id].is_alive())
	ids.sort()
	return ids


## Parks every enemy far away, then places the listed ones at `at + offset`.
static func place(sim, at: Vector3, offsets: Dictionary) -> void:
	for e in enemies(sim):
		sim.bodies[e].position = at + Vector3(40.0 + 6.0 * float(e), 0, 40.0)  # 6 m apart: never a pack
	for e in offsets:
		sim.bodies[e].position = at + offsets[e]


func _profiles_in_data(ctx) -> void:
	ctx.check("class pilots: S&S peel, GS densest, bow lowest_hp, magic holds",
		str(Deck.class_data("sword_shield")["pilot"]["target"]) == "peel" and str(Deck.class_data("greatsword")["pilot"]["target"]) == "densest"
		and str(Deck.class_data("longbow")["pilot"]["target"]) == "lowest_hp" and int(Deck.class_data("magic")["pilot"]["skill_min_targets"]) == 2)
	ctx.check("class signatures load with the race vocabulary (no data errors)", preload("res://logic/race_data.gd").load_from("res://data/races/").errors.is_empty())
	var f := RaceTest.squad(["human", "viking", "elf"])
	ctx.check("a squad card reads its class pilot", float(Pilot.pilot_profile(f.sim.fighters[1]).get("reaction", 0.0)) == 0.95)


## A class with no `pilot` block (and a fighter with no class) keeps today's rule: the nearest enemy.
func _no_pilot_is_old_behaviour(ctx) -> void:
	Deck._class_cache["test_no_pilot"] = {"id": "test_no_pilot"}
	var plain := Fighter.new()
	plain.race_state = {"class": "test_no_pilot"}
	ctx.check("class without pilot: empty profile", Pilot.pilot_profile(plain).is_empty() and Pilot.pilot_profile(Fighter.new()).is_empty())
	ctx.check("class without pilot: target = nearest", Pilot.pick_target(null, 1, {}, 1.5, 42) == 42)
	ctx.check("class without pilot: old engage ranges", is_equal_approx(Pilot._engage_range(RaceTest.squad(["human"], ["longbow"]).combat, _styled("longbow"), {}), Pilot.SHOOT_RANGE))
	Deck._class_cache.erase("test_no_pilot")


func _styled(style: String) -> Fighter:
	var fighter := Fighter.new()
	fighter.style = style
	return fighter


## S&S peel: the enemy nearest the most-hurt ally, even when another enemy is nearer the tank.
func _peel(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "elf"])
	var sim = f.sim
	var foes := enemies(sim)
	var tank: Vector3 = sim.bodies[1].position
	sim.bodies[3].position = tank + Vector3(0, 0, 8.0)
	sim.fighters[3].hp = sim.fighters[3].max_hp() * 0.4
	place(sim, tank, {foes[0]: Vector3(1.0, 0, 0), foes[1]: sim.bodies[3].position - tank + Vector3(1.0, 0, 0)})
	var profile := Pilot.pilot_profile(sim.fighters[1])
	ctx.check("peel: tank goes for the enemy on the hurt bow, not the nearest", Pilot.pick_target(sim, 1, profile, 1.5, foes[0]) == foes[1])
	sim.fighters[3].hp = sim.fighters[3].max_hp()
	sim.fighters[2].hp = sim.fighters[2].max_hp()
	ctx.check("peel: nobody hurt -> nearest", Pilot.pick_target(sim, 1, profile, 1.5, foes[0]) == foes[0])


## GS densest: the enemy with the most others within 2.5 m.
func _densest_and_cleave_target(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "elf"])
	var sim = f.sim
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[2].position
	place(sim, at, {foes[0]: Vector3(1.0, 0, 0), foes[1]: Vector3(-5.0, 0, 0), foes[2]: Vector3(-5.5, 0, 1.0), foes[3]: Vector3(-6.0, 0, -1.0)})
	var picked := Pilot.pick_target(sim, 2, Pilot.pilot_profile(sim.fighters[2]), 1.6, foes[0])
	ctx.check("densest: the greatsword walks to the pack of 3, not the lone nearest goblin", picked in [foes[1], foes[2], foes[3]])


## Bow: lowest HP (finisher); the boss always while alive; kite (dodge back) when an enemy is within 3 m.
func _longbow_target_and_kite(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "elf"])
	var sim = f.sim
	sim.set_class_style(3, "longbow")  # as the client and class_sim do
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[3].position
	place(sim, at, {foes[0]: Vector3(5.0, 0, 0), foes[1]: Vector3(6.5, 0, 0)})
	sim.fighters[foes[1]].hp = 5.0
	var profile := Pilot.pilot_profile(sim.fighters[3])
	ctx.check("lowest_hp: the bow finishes the weakest enemy", Pilot.pick_target(sim, 3, profile, 7.0, foes[0]) == foes[1])
	sim.fighters[foes[0]].enemy_type = "goblin_chief"
	ctx.check("boss_first: the bow shoots the boss while it lives", Pilot.pick_target(sim, 3, profile, 7.0, foes[0]) == foes[0])
	sim.fighters[foes[0]].enemy_type = "goblin"
	ctx.check("bow shoots from 7 m (pilot shoot_range)", is_equal_approx(Pilot._engage_range(f.combat, sim.fighters[3], profile), 7.0))
	place(sim, at, {foes[0]: Vector3(2.0, 0, 0)})
	var bow = sim.fighters[3]
	bow.state = Fighter.State.IDLE
	bow.dodge_cooldown = 0
	bow.energy = bow.max_energy()
	var input: SimInput = Pilot.decide(sim, f.combat, 3, Pilot.new_memory(1), 0, 0.0)
	ctx.check("kite: an enemy within 3 m -> Vault Shot away from it (class-skills.md L4: the kite skill)", input.skill_slot == bow.skill_state["skills"].find("vault_shot"))
	bow.skill_state["cd"]["vault_shot"] = sim.tick_count + 600
	bow.skill_state["cd"]["pinning_shot"] = sim.tick_count + 600
	input = Pilot.decide(sim, f.combat, 3, Pilot.new_memory(1), 0, 0.0)
	ctx.check("kite: Vault Shot on cooldown -> the bow dodges away instead", input.dodge and input.move.x < -0.5)
	bow.dodge_cooldown = 10
	input = Pilot.decide(sim, f.combat, 3, Pilot.new_memory(1), 0, 0.0)
	ctx.check("kite: dodge on cooldown -> no kite", not input.dodge)


## Hunter's Mark focus: the other cards prefer a sundered target inside their engage range.
func _marked_focus(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "elf"])
	var sim = f.sim
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[2].position
	place(sim, at, {foes[0]: Vector3(1.0, 0, 0), foes[1]: Vector3(1.4, 0, 0.6)})
	var profile := Pilot.pilot_profile(sim.fighters[2])
	ctx.check("marked: no mark -> class rule", Pilot.pick_target(sim, 2, profile, 1.6, foes[0]) == foes[0])
	sim.fighters[foes[1]].effects["sunder"] = {"left": 100, "stacks": 1}
	ctx.check("marked: the greatsword switches to the marked enemy in reach", Pilot.pick_target(sim, 2, profile, 1.6, foes[0]) == foes[1])
	sim.bodies[foes[1]].position = at + Vector3(9.0, 0, 0)
	ctx.check("marked: a mark outside the engage range is ignored", Pilot.pick_target(sim, 2, profile, 1.6, foes[0]) == foes[0])


## heavy_every: the greatsword's 3rd press is a heavy (others every 4th).
func _heavy_every(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "elf"])
	var sim = f.sim
	var foes := enemies(sim)
	sim.set_class_style(2, "greatsword")
	var counts := {}
	for id in [1, 2]:
		place(sim, sim.bodies[id].position, {foes[0]: Vector3(0.8, 0, 0)})
		sim.fighters[id].state = Fighter.State.ATTACK  # not idle: no skills, just the swing rhythm
		var memory := Pilot.new_memory(1)
		var first_heavy := -1
		for press in range(1, 9):
			var input: SimInput = Pilot.decide(sim, f.combat, id, memory, press * Pilot.SWING_EVERY, 0.0)
			if input.heavy and first_heavy < 0:
				first_heavy = press
		counts[id] = first_heavy
	ctx.check("heavy_every: greatsword heavy on press 3, S&S on press 4 (%s)" % [counts], int(counts[2]) == 3 and int(counts[1]) == 4)


## Magic (class-skills.md 3.5, 3.7): Arcane Orb waits for 2+ enemies around the target (or the boss); Warding Veil
## waits for an ally below 60% (pilot support_skill: warding_veil). Rules from data/class_skills/class_skills.json.
func _magic_hold(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "runeborn"], ["sword_shield", "greatsword", "magic"])
	var sim = f.sim
	var Use = preload("res://logic/class_skills/use_rules.gd")
	ctx.check("magic pilot support_skill is warding_veil", str(Pilot.pilot_profile(sim.fighters[3]).get("support_skill", "")) == "warding_veil")
	var foes := enemies(sim)
	var at: Vector3 = sim.bodies[3].position
	place(sim, at, {foes[0]: Vector3(5.0, 0, 0)})
	ctx.check("magic hold: 1 enemy in the area -> Arcane Orb held", Use.choose(sim, 3, "arcane_orb", foes[0]).is_empty())
	place(sim, at, {foes[0]: Vector3(5.0, 0, 0), foes[1]: Vector3(5.5, 0, 0.5)})
	ctx.check("magic hold: 2 enemies in the area -> Arcane Orb goes", not Use.choose(sim, 3, "arcane_orb", foes[0]).is_empty())
	place(sim, at, {foes[0]: Vector3(5.0, 0, 0)})
	sim.fighters[foes[0]].enemy_type = "goblin_chief"
	ctx.check("magic hold: the boss alone -> goes", not Use.choose(sim, 3, "arcane_orb", foes[0]).is_empty())
	sim.fighters[foes[0]].enemy_type = "goblin"
	place(sim, at, {foes[0]: sim.bodies[1].position - at + Vector3(1.0, 0, 0)})
	ctx.check("magic support: Warding Veil held while every ally is above 60%", Use.choose(sim, 3, "warding_veil", foes[0]).is_empty())
	sim.fighters[1].hp = sim.fighters[1].max_hp() * 0.5
	ctx.check("magic support: an attacked ally below 60% -> Warding Veil goes", int(Use.choose(sim, 3, "warding_veil", foes[0]).get("target", -1)) == 1)


## Hunter's Mark (longbow signature, any race): sunder on the first hit on a target new to this card only.
func _hunters_mark(ctx) -> void:
	var f := RaceTest.squad(["human", "viking", "human"])
	var sim = f.sim
	RacePassives.step(sim)
	var foes := enemies(sim)
	var out := RaceTest.react(sim, {"type": "hit", "attacker": 3, "target": foes[0], "damage": 10, "move": "longbow_light_1"})
	ctx.check("Hunter's Mark: first hit on a target applies sunder", sim.fighters[foes[0]].effects.has("sunder")
		and out.any(func(e): return e["type"] == "race_proc" and e["name"] == "Hunter's Mark"))
	sim.fighters[foes[0]].effects.erase("sunder")
	out = RaceTest.react(sim, {"type": "hit", "attacker": 3, "target": foes[0], "damage": 10, "move": "longbow_light_1"})
	ctx.check("Hunter's Mark: a second hit on the same target does not mark again", not sim.fighters[foes[0]].effects.has("sunder"))
	RaceTest.react(sim, {"type": "hit", "attacker": 3, "target": foes[1], "damage": 10, "move": "longbow_light_1"})
	ctx.check("Hunter's Mark: a new target is marked", sim.fighters[foes[1]].effects.has("sunder"))
	RaceTest.react(sim, {"type": "hit", "attacker": 2, "target": foes[2], "damage": 10, "move": "greatsword_light_1"})
	ctx.check("Hunter's Mark: only the longbow carries it", not sim.fighters[foes[2]].effects.has("sunder"))


## Cleave (greatsword signature): a heavy hit deals +15% per extra enemy hit, max +45%.
func _cleave(ctx) -> void:
	var gs := Fighter.new()
	gs.race_state = {"effects": [{"src": "signature", "effect": Deck.class_data("greatsword")["signature"][0]}]}
	ctx.check("formula: Cleave 1 / 2 / 4 / 6 enemies -> x1.00 / x1.15 / x1.45 / x1.45",
		is_equal_approx(RacePassives.cleave_mul(gs, 1), 1.0) and is_equal_approx(RacePassives.cleave_mul(gs, 2), 1.15)
		and is_equal_approx(RacePassives.cleave_mul(gs, 4), 1.45) and is_equal_approx(RacePassives.cleave_mul(gs, 6), 1.45))
	var damage := {}
	for count in [1, 3]:
		var f := RaceTest.squad(["human", "viking", "elf"])
		var sim = f.sim
		sim.set_class_style(2, "greatsword")
		var me = sim.fighters[2]
		me.stats["CRIRATE"] = 0.0
		me.direction = Vector2i(1, 0)
		me.state = Fighter.State.ATTACK
		me.move_id = str(f.combat.styles["greatsword"]["ground_heavy"])
		me.move_frame = float(f.combat.moves[me.move_id]["startup"])
		me.hit_ids.clear()
		var box: AABB = Combat.hitbox_world(sim.bodies[2], me, f.combat)
		var foes := enemies(sim)
		var offsets := {}
		for i in count:
			var c: Vector3 = box.get_center()
			offsets[foes[i]] = Vector3(c.x, sim.bodies[2].position.y, c.z + 0.2 * float(i)) - sim.bodies[2].position
			sim.fighters[foes[i]].stats["DEF"] = 0.0
		place(sim, sim.bodies[2].position, offsets)
		sim.events.clear()
		Combat.resolve_hits(sim.fighters, sim.bodies, f.combat, sim.rng, sim.events)
		var hits: Array = sim.events.filter(func(e): return e["type"] == "hit" and int(e["attacker"]) == 2)
		damage[count] = [hits.size(), float(hits[0]["damage"]) if not hits.is_empty() else 0.0]
	ctx.check("Cleave in combat: a heavy into 3 enemies deals x1.30 each (%s)" % [damage],
		int(damage[1][0]) == 1 and int(damage[3][0]) == 3 and absf(float(damage[3][1]) / float(damage[1][1]) - 1.30) < 0.02)
