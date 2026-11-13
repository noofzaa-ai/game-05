extends RefCounted
## Skill tree mechanic nodes and the reflect / death_save actions in battle (design/gdd/skill-tree.md 3.5, 3.8-3.10;
## logic/skill_tree_mechanics.gd). One check per mechanic id, with the node's own data numbers (looked up by id, so a
## retune of the data does not break the test). Mechanics are given straight to the fighter (the learn rules and gates
## are tested in test_skill_tree_rules.gd / test_skill_tree_effects.gd).
const RP := preload("res://tests/test_race_passives.gd")
const TreeData := preload("res://logic/skill_tree_data.gd")
const TreeEffects := preload("res://logic/skill_tree_effects.gd")
const Mech := preload("res://logic/skill_tree_mechanics.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const Combat := preload("res://logic/combat.gd")
const Fighter := preload("res://logic/fighter.gd")
const SS := "sword_shield"
const GS := "greatsword"
const LB := "longbow"
const MG := "magic"


func run(ctx) -> void:
	_class_mechanics(ctx)
	_magic_mechanics(ctx)
	_human(ctx)
	_viking(ctx)
	_elf(ctx)
	_runeborn(ctx)
	_reflect_and_death_save(ctx)
	_events_and_heals(ctx)
	_pilot_mods(ctx)


## The params of mechanic `mech_id` in the node data (the effect minus type/id).
func _p(mech_id: String) -> Dictionary:
	var data = TreeData.load_default()
	for node_id in data.by_id:
		for effect in data.by_id[node_id]["node"].get("effects", []):
			if str(effect.get("type", "")) == "mechanic" and str(effect["id"]) == mech_id:
				var out: Dictionary = effect.duplicate(true)
				out.erase("type")
				out.erase("id")
				return out
	return {}


## The node effect of type `kind` whose node has a mechanic or action named `marker` (for trigger nodes).
func _node_effect(node_id: String, kind: String) -> Dictionary:
	for effect in TreeData.load_default().node(node_id).get("effects", []):
		if str(effect["type"]) == kind:
			return effect.duplicate(true)
	return {}


func _give(fighter, mech_id: String) -> Dictionary:
	if not fighter.race_state.has("tree"):
		fighter.race_state["tree"] = {"mechanics": {}}
	var p := _p(mech_id)
	fighter.race_state["tree"]["mechanics"][mech_id] = p
	return p


func _id_of(f: Dictionary, card: String) -> int:
	for id in f.sim.runs:
		if str(f.sim.runs[id].card_id) == card:
			return id
	return -1


func _enemies(sim) -> Array:
	var ids: Array = sim.fighters.keys().filter(func(i): return sim.fighters[i].team == "enemy" and sim.fighters[i].is_alive())
	ids.sort()
	return ids


## Puts every enemy far away except the first `keep`, which go to `spots` (offsets from fighter `id`).
func _place(sim, id: int, spots: Array) -> Array:
	var ids := _enemies(sim)
	var at: Vector3 = sim.bodies[id].position
	for i in ids.size():
		sim.bodies[ids[i]].position = at + (spots[i] if i < spots.size() else Vector3(40.0 + i, 0.0, 0.0))
	return ids.slice(0, spots.size())


func _step(sim, id: int, events: Array) -> void:
	sim.events.clear()
	sim.events.append_array(events)
	Mech.step(sim, id, sim.fighters[id], events)


func _class_mechanics(ctx) -> void:
	var f := RP.squad(["human", "viking", "elf"])
	var sim = f.sim
	var ss := _id_of(f, SS)
	var me = sim.fighters[ss]
	# Unyielding Bulwark: -15% damage taken while the Bulwark taunt is up.
	var guard := _give(me, "bulwark_guard")
	me.race_state["bulwark_until"] = sim.tick_count + 100
	var up := Mech.taken_mul(me, sim.tick_count)
	me.race_state["bulwark_until"] = -1
	ctx.check("Unyielding Bulwark: damage taken x%.2f while taunting, x1 otherwise" % float(guard["damage_taken_mul"]), is_equal_approx(up, 0.85) and Mech.taken_mul(me, sim.tick_count) == 1.0)
	# Immovable: CONTROL_IMMUNE, a stun never lands and a skill knockback does not move the card.
	me.race_state["pseudo"]["CONTROL_IMMUNE"] = {"add": 1.0, "mul": 0.0}
	var enemy: int = _enemies(sim)[0]
	var stunned: bool = preload("res://logic/effects.gd").apply(enemy, sim.fighters[enemy], ss, me, {"id": "stun", "chance": 100.0, "duration": 60}, sim.combat, sim.rng, sim.events)
	var before: Vector3 = sim.bodies[ss].position
	preload("res://logic/class_skills/engine.gd")._push_from(sim, ss, before + Vector3(1, 0, 0), 3.0)
	ctx.check("Immovable: a stun does not land and knockback does not move the card", not stunned and not me.incapacitated and sim.bodies[ss].position == before)
	me.race_state["pseudo"].erase("CONTROL_IMMUNE")

	var gs := _id_of(f, GS)
	var g = sim.fighters[gs]
	# Momentum: a heavy that hit 3 enemies -> the next heavy one swing earlier (once).
	_give(g, "momentum")
	_step(sim, gs, [{"type": "skill_heavy", "player": gs, "skill": "reaping_arc", "targets": 3}])
	ctx.check("Momentum: armed after a 3-target heavy, used once", Mech.take_momentum(g) and not Mech.take_momentum(g))
	_step(sim, gs, [{"type": "skill_heavy", "player": gs, "skill": "reaping_arc", "targets": 2}])
	ctx.check("Momentum: a 2-target heavy does not arm it", not Mech.take_momentum(g))
	# Unstoppable: CONTROL_IMMUNE only while casting a skill or swinging a heavy.
	_give(g, "unstoppable")
	var idle_immune := TreeEffects.control_immune(g)
	g.skill_state["cast"] = {"skill": "reaping_arc"}
	var cast_immune := TreeEffects.control_immune(g)
	g.skill_state["cast"] = {}
	ctx.check("Unstoppable: immune during a skill cast, not when idle", cast_immune and not idle_immune)
	g.race_state["tree"]["mechanics"].erase("unstoppable")
	# Titan's Swing: a heavy hits an enemy standing behind the card.
	_give(g, "titan_swing")
	var behind := _place(sim, gs, [Vector3(-2.0, 0.0, 0.0)])
	var style: Dictionary = sim.combat.styles[g.style]
	g.direction = Vector2i(1, 0)
	g.state = Fighter.State.ATTACK
	g.move_id = str(style["ground_heavy"])
	g.move_frame = float(sim.combat.moves[g.move_id]["startup"])
	g.hit_ids.clear()
	var events: Array[Dictionary] = []
	Combat.resolve_hits(sim.fighters, sim.bodies, sim.combat, sim.rng, events)
	ctx.check("Titan's Swing: the heavy hits an enemy 2 m behind (radius %.1f)" % Mech.titan_radius(g, g.move_id), events.any(func(e): return e["type"] == "hit" and int(e["target"]) == int(behind[0])))
	g.state = Fighter.State.IDLE
	g.move_id = ""

	var lb := _id_of(f, LB)
	var bow = sim.fighters[lb]
	# Pack Hunt: allies deal x1.1 to marked targets.
	_give(bow, "pack_hunt")
	var target = sim.fighters[enemy]
	target.effects.erase("sunder")
	var plain := Mech.dealt_mul(sim.fighters, ss, target, false)
	target.effects["sunder"] = {"left": 600, "stacks": 1, "dps": 0.0, "age": 0, "source": lb}
	ctx.check("Pack Hunt: an ally deals x1.10 to a marked target, x1 to an unmarked one", is_equal_approx(Mech.dealt_mul(sim.fighters, ss, target, false), 1.1) and plain == 1.0)
	# Deadeye: every 4th basic shot on a marked target is a forced crit that pierces.
	var dead := _give(bow, "deadeye")
	var procs: Array = []
	for i in int(dead["every_n"]) * 2:
		procs.append(Mech.deadeye(bow, target, {"projectile": "arrow", "dir": Vector2.RIGHT}))
	ctx.check("Deadeye: shots 4 and 8 on a marked target %s" % [procs], procs.count(true) == 2 and procs[3] and procs[7])
	target.effects.erase("sunder")
	ctx.check("Deadeye: not on an unmarked target", not Mech.deadeye(bow, target, {"projectile": "arrow"}))
	# Skirmisher: dodge cooldown x0.6, the skill after a dodge casts instantly.
	_give(bow, "skirmisher")
	_step(sim, lb, [{"type": "dodge_started", "player": lb}])
	var stats := {"cast_time": 1.0, "damage": 1.0}
	Mech.cast_mods(bow, stats)
	ctx.check("Skirmisher: dodge cooldown x0.6 and an instant cast after a dodge", is_equal_approx(Mech.dodge_cd_mul(bow), 0.6) and stats["cast_time"] == 0.0)


func _magic_mechanics(ctx) -> void:
	var f := RP.squad(["human", "viking", "elf"], [SS, GS, MG])
	var sim = f.sim
	var mg := _id_of(f, MG)
	var me = sim.fighters[mg]
	# Weave Rhythm: every 3rd cast free and +25%.
	_give(me, "weave_rhythm")
	me.race_state["casts"] = 2
	var stats := {"damage": 10.0}
	var free := Mech.cast_mods(me, stats)
	me.race_state["casts"] = 0
	var stats2 := {"damage": 10.0}
	ctx.check("Weave Rhythm: the 3rd cast is free at 12.5 damage, the 1st is not", free and is_equal_approx(stats["damage"], 12.5) and not Mech.cast_mods(me, stats2) and stats2["damage"] == 10.0)
	me.race_state["tree"]["mechanics"].erase("weave_rhythm")
	# Arcane Convergence: the 3rd different skill within 4 s deals x1.4.
	_give(me, "arcane_convergence")
	var enemy: int = _enemies(sim)[0]
	var a := Mech.skill_damage_mul(sim, mg, enemy, "arcane_orb")
	var b := Mech.skill_damage_mul(sim, mg, enemy, "starfall")
	var c := Mech.skill_damage_mul(sim, mg, enemy, "repulse_nova")
	ctx.check("Arcane Convergence: x1, x1, then x1.4 (%.2f %.2f %.2f)" % [a, b, c], a == 1.0 and b == 1.0 and is_equal_approx(c, 1.4))
	# Blink Caster: an enemy within 2.5 m -> blink 5 m away and leave a Repulse Nova.
	_give(me, "blink_caster")
	sim.bodies[mg].position = Vector3(0.0, sim.bodies[mg].position.y, 0.0)  # the middle of the stage: room to blink
	var near := _place(sim, mg, [Vector3(1.5, 0.0, 0.0)])
	var from: Vector3 = sim.bodies[mg].position
	_step(sim, mg, [])
	var moved: float = (sim.bodies[mg].position - from).length()
	ctx.check("Blink Caster: blinked %.1f m and the nova hit the enemy" % moved, absf(moved - 5.0) < 0.01 and sim.events.any(func(e): return e["type"] == "skill_hit" and int(e["target"]) == int(near[0])))
	var at: Vector3 = sim.bodies[mg].position
	sim.bodies[near[0]].position = at + Vector3(1.0, 0, 0)
	_step(sim, mg, [])
	ctx.check("Blink Caster: no second blink inside the 6 s cooldown", sim.bodies[mg].position == at)


func _human(ctx) -> void:
	var f := RP.squad(["human", "human", "human"], [SS, GS, MG])
	var sim = f.sim
	var ss := _id_of(f, SS)
	var me = sim.fighters[ss]
	# Disciplined Casting: after an ultimate the next 2 casts are free.
	_give(me, "free_casts_after_ult")
	_step(sim, ss, [{"type": "ultimate_cast", "player": ss}])
	var cast := {"skill": "shield_rush", "kind": "dash_strike", "stats": {"damage": 1.0}}
	var frees: Array = []
	for i in 3:
		frees.append(Mech.cast_mods(me, {"damage": 1.0}))
		Mech.cast_done(sim, ss, me, cast)
	ctx.check("Disciplined Casting: 2 free casts after an ultimate %s" % [frees], frees == [true, true, false])
	# Scholar's Edge: a skill crit cuts that skill's cooldown by 1 s.
	_give(me, "skill_crit_refresh")
	me.skill_state["cd"]["shield_rush"] = sim.tick_count + 600
	_step(sim, ss, [{"type": "skill_hit", "attacker": ss, "target": _enemies(sim)[0], "skill": "shield_rush", "crit": true, "effect": "hit", "damage": 5.0}])
	ctx.check("Scholar's Edge: a crit cuts 60 ticks (%d left)" % (int(me.skill_state["cd"]["shield_rush"]) - sim.tick_count), int(me.skill_state["cd"]["shield_rush"]) - sim.tick_count == 540)
	# Drillmaster's Wall: a skill cast halves the remaining Bulwark cycle.
	_give(me, "bulwark_haste_on_skill")
	var index := -1
	for i in me.race_state["effects"].size():
		if me.race_state["effects"][i]["effect"]["type"] == "aggro":
			index = i
	sim.tick_count += 1000
	me.race_state["fx"][str(index)] = {"last": sim.tick_count - 80, "n": 0, "wave": 0, "low": false}
	var cycle := int(me.race_state["effects"][index]["effect"]["every_ticks"])
	_step(sim, ss, [{"type": "skill_cast", "player": ss, "skill": "shield_rush"}])
	var left: int = cycle - (sim.tick_count - int(me.race_state["fx"][str(index)]["last"]))
	ctx.check("Drillmaster's Wall: Bulwark %d ticks left -> %d" % [cycle - 80, left], left == (cycle - 80) - (cycle - 80) / 2)
	# Twin Ultimate: the ultimate re-casts 2 s later.
	var p := _give(me, "twin_ultimate")
	_step(sim, ss, [{"type": "race_ult_resolved", "player": ss}])
	sim.tick_count += int(p["delay_ticks"])
	_step(sim, ss, [])
	ctx.check("Twin Ultimate: an echo 2 s after the ultimate", sim.events.any(func(e): return e["type"] == "tree_twin_ultimate" and bool(e["ultimate"])))
	# Mastery Overflow: the passive x1.25 for 8 s after an ultimate (Wide Arcs radius 1.25 -> 1.3125).
	var gs := _id_of(f, GS)
	var g = sim.fighters[gs]
	var mo := _give(g, "mastery_overflow")
	_step(sim, gs, [{"type": "ultimate_cast", "player": gs}])
	var during: float = RacePassives.skill_mods(g)["radius_mul"]
	sim.tick_count += int(mo["ticks"])
	_step(sim, gs, [])
	var after: float = RacePassives.skill_mods(g)["radius_mul"]
	ctx.check("Mastery Overflow: Wide Arcs radius x%.4f during, x%.4f after" % [during, after], is_equal_approx(during, 1.3125) and is_equal_approx(after, 1.25))
	# Perfect Form: a heavy on 3+ enemies refreshes the shortest cooldown (4 s internal cooldown).
	_give(g, "refresh_shortest_on_heavy")
	g.skill_state["cd"]["reaping_arc"] = sim.tick_count + 300
	g.skill_state["cd"]["crater_leap"] = sim.tick_count + 900
	_step(sim, gs, [{"type": "skill_heavy", "player": gs, "targets": 3}])
	var ready: bool = int(g.skill_state["cd"]["reaping_arc"]) <= sim.tick_count and int(g.skill_state["cd"]["crater_leap"]) > sim.tick_count
	g.skill_state["cd"]["reaping_arc"] = sim.tick_count + 300
	_step(sim, gs, [{"type": "skill_heavy", "player": gs, "targets": 3}])
	ctx.check("Perfect Form: the shortest cooldown refreshes, once per 4 s", ready and int(g.skill_state["cd"]["reaping_arc"]) > sim.tick_count)
	# Called Target: marked targets take x1.2 skill damage (not basic hits).
	var lbf := RP.squad(["human", "human", "human"])
	var bow = lbf.sim.fighters[_id_of(lbf, LB)]
	_give(bow, "called_target")
	var t = lbf.sim.fighters[_enemies(lbf.sim)[0]]
	t.effects["sunder"] = {"left": 600, "stacks": 1, "dps": 0.0, "age": 0, "source": 0}
	ctx.check("Called Target: x1.2 skill damage on a marked target, x1 for basic hits", is_equal_approx(Mech.dealt_mul(lbf.sim.fighters, _id_of(lbf, SS), t, true), 1.2) and Mech.dealt_mul(lbf.sim.fighters, _id_of(lbf, SS), t, false) == 1.0)
	# Grand Archmage: every 4th cast fires a 70% copy.
	var mg := _id_of(f, MG)
	var m = sim.fighters[mg]
	_give(m, "grand_archmage")
	m.race_state["casts"] = 3
	var orb := {"skill": "arcane_orb", "kind": "orb", "stats": {"damage": 21.0}}
	Mech.cast_done(sim, mg, m, orb)
	ctx.check("Grand Archmage: the 4th cast gets a x0.7 copy", is_equal_approx(float(orb.get("copy_mul", 0.0)), 0.7))


func _viking(ctx) -> void:
	var f := RP.squad(["viking", "viking", "viking"], [SS, GS, LB])
	var sim = f.sim
	var gs := _id_of(f, GS)
	var g = sim.fighters[gs]
	# Trophy Hunter: a kill extends rage/haste by 2 s.
	var p := _give(g, "extend_buffs_on_kill")
	g.effects["rage"] = {"left": 100, "stacks": 1, "dps": 0.0, "age": 0, "source": gs}
	var enemy: int = _enemies(sim)[0]
	_step(sim, gs, [{"type": "killed", "target": enemy, "by": gs}])
	ctx.check("Trophy Hunter: rage 100 -> %d ticks" % int(g.effects["rage"]["left"]), int(g.effects["rage"]["left"]) == 100 + int(p["ticks"]))
	# Blood Cyclone: Cleave bonus x (1 + missing HP), cap +90%.
	_give(g, "blood_cyclone")
	g.hp = g.max_hp() * 0.5
	ctx.check("Blood Cyclone: Cleave +30%% at half HP -> +45%% (%.2f), cap 0.9" % Mech.cleave_bonus(g, 0.3, 0.45), is_equal_approx(Mech.cleave_bonus(g, 0.3, 0.45), 0.45) and is_equal_approx(Mech.cleave_bonus(g, 0.8, 0.45), 0.9))
	g.hp = g.max_hp()
	# Wall of Fury: Bulwark radius +3 m below 50% HP.
	var ss := _id_of(f, SS)
	var me = sim.fighters[ss]
	_give(me, "wall_of_fury")
	var full := Mech.bulwark_radius_add(me)
	me.hp = me.max_hp() * 0.4
	ctx.check("Wall of Fury: Bulwark +3 m below 50%% HP only", full == 0.0 and Mech.bulwark_radius_add(me) == 3.0)
	# Trophy Volley: a skill kill fires a free arrow at the lowest-HP enemy.
	var lb := _id_of(f, LB)
	var bow = sim.fighters[lb]
	_give(bow, "trophy_volley")
	var ids := _place(sim, lb, [Vector3(3, 0, 0), Vector3(5, 0, 0)])
	sim.fighters[ids[0]].hp = 0.0
	sim.fighters[ids[0]].state = Fighter.State.DEAD
	_step(sim, lb, [{"type": "skill_hit", "attacker": lb, "target": ids[0], "skill": "heartseeker_shot", "effect": "hit", "damage": 50.0}, {"type": "killed", "target": ids[0], "by": lb}])
	ctx.check("Trophy Volley: a skill kill fires a free arrow", sim.events.any(func(e): return e["type"] == "tree_trophy_arrow") and sim.events.any(func(e): return e["type"] == "race_burst_hit" and int(e["target"]) == int(ids[1])))
	# Blood Sorcery (magic): a skill kill heals 5%; skills below 50% HP +20% radius.
	var mf := RP.squad(["viking", "viking", "viking"], [SS, GS, MG])
	var mg := _id_of(mf, MG)
	var m = mf.sim.fighters[mg]
	_give(m, "blood_sorcery")
	m.hp = m.max_hp() * 0.4
	var dead_id: int = _enemies(mf.sim)[0]
	_step(mf.sim, mg, [{"type": "skill_hit", "attacker": mg, "target": dead_id, "skill": "arcane_orb", "effect": "hit", "damage": 50.0}, {"type": "killed", "target": dead_id, "by": mg}])
	var healed: Array = mf.sim.events.filter(func(e): return e["type"] == "race_heal" and int(e["target"]) == mg)
	var st := {"radius": 2.0}
	Mech.cast_mods(m, st)
	ctx.check("Blood Sorcery: a skill kill heals 5%% max HP and the radius is x1.2 below half HP", not healed.is_empty() and is_equal_approx(float(healed[0]["amount"]), m.max_hp() * 0.05) and is_equal_approx(st["radius"], 2.4))


func _elf(ctx) -> void:
	var f := RP.squad(["elf", "elf", "elf"])
	var sim = f.sim
	var ss := _id_of(f, SS)
	var gs := _id_of(f, GS)
	var lb := _id_of(f, LB)
	var me = sim.fighters[ss]
	var ally = sim.fighters[gs]
	# Cleansing Dew: a race heal on an ally below 30% cleanses stun.
	_give(me, "cleansing_dew")
	ally.hp = ally.max_hp() * 0.2
	ally.effects["stun"] = {"left": 60, "stacks": 1, "dps": 0.0, "age": 0, "source": 99}
	_step(sim, ss, [{"type": "race_heal", "player": ss, "target": gs, "amount": 2.0}])
	ctx.check("Cleansing Dew: the stun on a 20%% HP ally is cleansed", not ally.effects.has("stun"))
	# Kin Bond: heals itself 25% of the heal it gives.
	var p := _give(me, "kin_bond")
	me.hp = me.max_hp() * 0.5
	var before: float = me.hp
	_step(sim, ss, [{"type": "race_heal", "player": ss, "target": gs, "amount": 8.0}])
	ctx.check("Kin Bond: healing 8 gives the card %.2f" % (me.hp - before), is_equal_approx(me.hp - before, 8.0 * float(p["fraction"]) * me.heal_factor()))
	# World Tree: the first ally down is revived at 25% after 3 s.
	var wt := _give(me, "world_tree")
	ally.state = Fighter.State.DOWNED
	_step(sim, ss, [])
	sim.tick_count += int(wt["delay_ticks"])
	_step(sim, ss, [])
	ctx.check("World Tree: the downed ally stands at 25%% HP (%.0f%%)" % (100.0 * ally.hp / ally.max_hp()), ally.is_alive() and is_equal_approx(ally.hp, ally.max_hp() * 0.25))
	# Grove Warden: while Bulwark is up, Warden's Grove heals every ally within 5 m.
	_give(me, "grove_warden")
	sim.tick_count += 120
	me.race_state["bulwark_until"] = sim.tick_count + 100
	sim.bodies[gs].position = sim.bodies[ss].position + Vector3(2, 0, 0)
	sim.bodies[lb].position = sim.bodies[ss].position + Vector3(-2, 0, 0)
	ally.hp = ally.max_hp() * 0.5
	sim.fighters[lb].hp = sim.fighters[lb].max_hp() * 0.6
	_step(sim, ss, [{"type": "race_proc", "player": ss, "source": "passive", "on": "guard_block"}])
	var healed: Array = sim.events.filter(func(e): return e["type"] == "race_heal").map(func(e): return int(e["target"]))
	ctx.check("Grove Warden: both allies within 5 m healed %s" % [healed], healed.has(gs) and healed.has(lb))
	# Bark and Blade: with regen on, a 3-enemy heavy heals the most-hurt ally 3%.
	var g = sim.fighters[gs]
	var bb := _give(g, "bark_and_blade")
	g.effects["regen"] = {"left": 600, "stacks": 1, "dps": 0.0, "age": 0, "source": gs}
	sim.tick_count += 120
	_step(sim, gs, [{"type": "skill_heavy", "player": gs, "targets": 3}])
	var heal: Array = sim.events.filter(func(e): return e["type"] == "race_heal")
	ctx.check("Bark and Blade: a 3-target heavy heals 2 x %.3f" % float(bb["per_target"]), not heal.is_empty())
	# Moonwell Arrows: Moonlit Arrow on a marked target roots it.
	var bow = sim.fighters[lb]
	_give(bow, "moonwell_root")
	var enemy: int = _enemies(sim)[0]
	sim.fighters[enemy].effects["sunder"] = {"left": 600, "stacks": 1, "dps": 0.0, "age": 0, "source": lb}
	_step(sim, lb, [{"type": "hit", "attacker": lb, "target": enemy, "damage": 3.0, "move": "x"}, {"type": "race_proc", "player": lb, "source": "passive", "on": "hit"}])
	ctx.check("Moonwell Arrows: the marked target is rooted (shock)", sim.fighters[enemy].effects.has("shock"))
	# Spring Rite: Bloomcaster heal cap 8% -> 12%.
	var mf := RP.squad(["elf", "elf", "elf"], [SS, GS, MG])
	var m = mf.sim.fighters[_id_of(mf, MG)]
	_give(m, "spring_rite")
	Mech.attach_rewrites(m)
	var caps: Array = []
	for entry in m.race_state["effects"]:
		for action in entry["effect"].get("actions", []):
			if action.has("cap_max_hp") and entry["src"] == "passive":
				caps.append(action["cap_max_hp"])
	ctx.check("Spring Rite: Bloomcaster cap 0.12 %s" % [caps], caps == [0.12])


func _runeborn(ctx) -> void:
	var f := RP.squad(["runeborn", "runeborn", "runeborn"])
	var sim = f.sim
	var ss := _id_of(f, SS)
	var gs := _id_of(f, GS)
	var lb := _id_of(f, LB)
	var me = sim.fighters[ss]
	# Warding Sigil: shields +4 s; a broken shield shocks enemies within 2 m.
	var p := _give(me, "warding_sigil")
	var enemy := _place(sim, ss, [Vector3(1, 0, 0)])
	RacePassives.run_action(sim, ss, {"action": "shield", "target": "self", "fraction_of": "source_max_hp", "fraction": 0.1, "duration_ticks": 600}, {})
	var until: int = me.shield_until - sim.tick_count
	var shield_events: Array = sim.events.duplicate()
	me.absorb(me.shield)
	_step(sim, ss, shield_events)
	ctx.check("Warding Sigil: a shield lasts 600 + %d ticks (%d) and its break shocks a 1 m enemy" % [int(p["ticks_add"]), until], until == 600 + int(p["ticks_add"]) and sim.fighters[enemy[0]].effects.has("shock"))
	# Overcharge: runes go 2 past max; the payload scales by runes / max.
	_give(me, "overcharge")
	ctx.check("Overcharge: Rune Aegis discharges at 7 instead of 5", Mech.charges_top(me, 5) == 7)
	# Runic Bulwark: each Bulwark pulse +1 rune per taunted enemy (max 3).
	_give(me, "runic_bulwark")
	me.race_state["tree"]["mechanics"].erase("overcharge")
	_place(sim, ss, [Vector3(1, 0, 0), Vector3(-1, 0, 0)])
	var index := -1
	for i in me.race_state["effects"].size():
		if me.race_state["effects"][i]["effect"]["type"] == "charges":
			index = i
	me.race_state["fx"][str(index)] = {"last": -1, "n": 0, "wave": 0, "low": false, "charges": 0}
	sim.events.clear()
	RacePassives._check_aggro(sim, ss, me)
	ctx.check("Runic Bulwark: 2 taunted -> 2 runes (%d)" % int(me.race_state["fx"][str(index)]["charges"]), int(me.race_state["fx"][str(index)]["charges"]) == 2)
	# Resonance: a discharge gives +1 rune to every other Runeborn ally.
	_give(me, "resonance")
	var bow = sim.fighters[lb]
	var bow_index := -1
	for i in bow.race_state["effects"].size():
		if bow.race_state["effects"][i]["effect"]["type"] == "charges":
			bow_index = i
	bow.race_state["fx"][str(bow_index)] = {"last": -1, "n": 0, "wave": 0, "low": false, "charges": 1}
	sim.tick_count += 1
	Mech.on_discharge(sim, ss, {})
	ctx.check("Resonance: the bow's runes 1 -> 2", int(bow.race_state["fx"][str(bow_index)]["charges"]) == 2)
	# Glyph Arrows: a Glyph Shot discharge marks every enemy within 6 m of the target.
	_give(bow, "glyph_arrows")
	var marked := _place(sim, lb, [Vector3(5, 0, 0), Vector3(8, 0, 0), Vector3(30, 0, 0)])
	for e in marked:
		sim.fighters[e].effects.erase("sunder")
	Mech.on_discharge(sim, lb, {"target": marked[0]})
	ctx.check("Glyph Arrows: enemies within 6 m of the target marked, a far one not", sim.fighters[marked[0]].effects.has("sunder") and sim.fighters[marked[1]].effects.has("sunder") and not sim.fighters[marked[2]].effects.has("sunder"))
	# Shatterglyph: the Runic Edge burst counts as a heavy for Cleave and leaves a shock zone.
	var g = sim.fighters[gs]
	_give(g, "shatterglyph")
	Mech.attach_rewrites(g)
	var actions: Array = []
	for entry in g.race_state["effects"]:
		if entry["effect"]["type"] == "charges":
			actions = entry["effect"]["actions"]
	ctx.check("Shatterglyph: the rune burst cleaves and a shock zone follows", actions.any(func(a): return a["action"] == "burst" and bool(a.get("cleave", false))) and actions.any(func(a): return a["action"] == "zone"))
	# Grand Runeweaver: a skill hit on 3+ enemies gives a rune; Runeweaver's shields also give focus.
	var mf := RP.squad(["runeborn", "runeborn", "runeborn"], [SS, GS, MG])
	var mg := _id_of(mf, MG)
	var m = mf.sim.fighters[mg]
	_give(m, "grand_runeweaver")
	Mech.attach_rewrites(m)
	var mi := -1
	for i in m.race_state["effects"].size():
		if m.race_state["effects"][i]["effect"]["type"] == "charges":
			mi = i
	m.race_state["fx"][str(mi)] = {"last": -1, "n": 0, "wave": 0, "low": false, "charges": 0}
	var three := _enemies(mf.sim).slice(0, 3)
	_step(mf.sim, mg, three.map(func(e): return {"type": "skill_hit", "attacker": mg, "target": e, "skill": "repulse_nova", "effect": "hit", "damage": 5.0}))
	var focus: bool = m.race_state["effects"][mi]["effect"]["actions"].any(func(a): return a["action"] == "apply_status" and a["status"] == "focus")
	ctx.check("Grand Runeweaver: a 3-enemy skill hit gives a rune, shields add focus", int(m.race_state["fx"][str(mi)]["charges"]) == 1 and focus)


func _reflect_and_death_save(ctx) -> void:
	var f := RP.squad(["viking", "viking", "viking"])
	var sim = f.sim
	var ss := _id_of(f, SS)
	var me = sim.fighters[ss]
	var enemy: int = _enemies(sim)[0]
	# Spiked Bastion: 25% of damage taken reflected while the Bulwark taunt is up.
	var spiked: Dictionary = _node_effect("ss_t4_a", "trigger")
	var action: Dictionary = spiked["actions"][0]
	var foe = sim.fighters[enemy]
	var hp0: float = foe.hp
	var off := RacePassives.run_action(sim, ss, action, {"attacker": enemy, "damage": 40.0, "target": ss})
	me.race_state["bulwark_until"] = sim.tick_count + 100
	var on := RacePassives.run_action(sim, ss, action, {"attacker": enemy, "damage": 40.0, "target": ss})
	ctx.check("Spiked Bastion: no reflect without Bulwark; 25%% of 40 = 10 with it (%.0f)" % (hp0 - foe.hp), not off and on and is_equal_approx(hp0 - foe.hp, 10.0))
	# Valhalla's Call: a lethal blow -> 4 s at 1 HP with ATK +50%; a kill in time -> survive at 20%.
	var call: Dictionary = _node_effect("vk_7", "trigger")
	var gs := _id_of(f, GS)
	var g = sim.fighters[gs]
	g.race_state["effects"].append({"src": "tree", "effect": call})
	g.hp = 1.0
	var atk0: float = g.stat("ATK")  # at 1 HP without the save (Berserker and the Viking synergy already count)
	g.hp = 0.0
	var saved := Mech.cheat_death(gs, g, sim.events)
	g.hp = 1.0
	var boost: float = g.stat("ATK") - atk0
	var base_atk: float = g.stats["ATK"]
	_step(sim, gs, [])
	_step(sim, gs, [{"type": "killed", "target": enemy, "by": gs}])
	sim.tick_count += int(call["actions"][0]["duration_ticks"])
	_step(sim, gs, [])
	ctx.check("Valhalla's Call: saved at 1 HP, ATK +%.2f base, a kill -> 20%% HP (%.0f%%)" % [boost / base_atk, 100.0 * g.hp / g.max_hp()], saved and absf(boost / base_atk - 0.5) < 0.02 and g.is_alive() and is_equal_approx(g.hp, g.max_hp() * 0.2) and not g.race_state["scaling"].any(func(s): return bool(s.get("death_save", false))))
	g.hp = 0.0
	ctx.check("Valhalla's Call: once per wave", not Mech.cheat_death(gs, g, sim.events))
	var lb := _id_of(f, LB)
	var bow = sim.fighters[lb]
	bow.race_state["effects"].append({"src": "tree", "effect": call.duplicate(true)})
	bow.hp = 0.0
	Mech.cheat_death(lb, bow, sim.events)
	bow.hp = 1.0
	_step(sim, lb, [])
	sim.tick_count += int(call["actions"][0]["duration_ticks"])
	_step(sim, lb, [])
	ctx.check("Valhalla's Call: no kill in 4 s -> the card goes down", not bow.is_alive())


## Chunk 2: the node events (signature_pulse, overheal, rune_discharge, kite, block), per_target heals.
func _events_and_heals(ctx) -> void:
	var f := RP.squad(["elf", "viking", "elf"])
	var sim = f.sim
	var ss := _id_of(f, SS)
	var gs := _id_of(f, GS)
	var me = sim.fighters[ss]
	# Rallying Wall: each Bulwark pulse fortifies allies within 4 m.
	me.race_state["effects"].append({"src": "tree", "effect": _node_effect("ss_t3_b", "trigger")})
	sim.bodies[gs].position = sim.bodies[ss].position + Vector3(2, 0, 0)
	_place(sim, ss, [Vector3(1, 0, 0)])
	sim.fighters[gs].effects.erase("fortify")
	sim.events.clear()
	RacePassives._check_aggro(sim, ss, me)
	ctx.check("Rallying Wall: the Bulwark pulse fortifies an ally 2 m away", sim.fighters[gs].effects.has("fortify"))
	# Bloom Cascade: overheal from a race heal bounces to the most-hurt ally.
	var lb := _id_of(f, LB)
	var bow = sim.fighters[lb]
	bow.race_state["effects"].append({"src": "tree", "effect": _node_effect("el_8", "trigger")})
	bow.hp = bow.max_hp()
	var hurt = sim.fighters[gs]
	hurt.hp = hurt.max_hp() * 0.5
	sim.events.clear()
	sim.tick_count += 120
	RacePassives.run_action(sim, lb, {"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.05}, {})
	var bounced: Array = sim.events.filter(func(e): return e["type"] == "race_heal" and int(e["target"]) == gs)
	var excess: float = bow.max_hp() * 0.05 * bow.heal_factor()  # the whole heal was overheal
	ctx.check("Bloom Cascade: a heal on a full-HP card bounces its %.1f overheal to the hurt ally (%s)" % [excess, bounced.map(func(e): return snappedf(e["amount"], 0.01))], bounced.size() == 1 and absf(float(bounced[0]["amount"]) - minf(excess * hurt.heal_factor(), hurt.max_hp() * 0.06)) < 0.01)
	# Unstoppable: each heavy heals 2% max HP per enemy hit, cap 8%.
	var g = sim.fighters[gs]
	var unstoppable: Dictionary = {}
	for effect in TreeData.load_default().node("gs_t4_b")["effects"]:
		if effect["type"] == "trigger":
			unstoppable = effect.duplicate(true)
	g.race_state["effects"].append({"src": "tree", "effect": unstoppable})
	var foes := _enemies(sim).slice(0, 5)
	var heals: Array = []
	for n in [3, 5]:
		g.hp = g.max_hp() * 0.5
		sim.tick_count += 120
		var hits: Array = foes.slice(0, n).map(func(e): return {"type": "hit", "attacker": gs, "target": e, "damage": 5.0, "move": "gs_heavy"})
		sim.events.clear()
		sim.events.append_array(hits)
		g.hp = g.max_hp() * 0.5
		RacePassives.step(sim)
		heals.append(sim.events.filter(func(e): return e["type"] == "race_heal" and int(e["target"]) == gs).reduce(func(a, e): return a + float(e["amount"]), 0.0) / g.max_hp())
	# 3 hit: 6%; 5 hit: 10% -> the node cap 8% -> the race passive heal cap of 6% per second (GDD 4.6: race caps still hold)
	ctx.check("Unstoppable: a 3-enemy heavy heals 6%%, a 5-enemy heavy is capped (%s)" % [heals], heals.size() == 2 and absf(heals[0] - minf(0.06 * g.heal_factor(), 0.06)) < 0.002 and absf(heals[1] - 0.06) < 0.002)
	# Red Harvest: the ultimate heals 3% per enemy hit, cap 15%.
	var harvest: Dictionary = TreeData.load_default().node("vk_4")["effects"][0]["extra_actions"][0]
	g.hp = g.max_hp() * 0.5
	sim.events.clear()
	RacePassives.run_action(sim, gs, harvest, {"ultimate": true, "hit": foes.slice(0, 4), "points": {}, "picked": {}})
	var got: float = sim.events.filter(func(e): return e["type"] == "race_heal").reduce(func(a, e): return a + float(e["amount"]), 0.0) / g.max_hp()
	ctx.check("Red Harvest: an ultimate that hit 4 heals 12%% (%.3f)" % got, absf(got - 0.12 * g.heal_factor()) < 0.002)
	# rune_discharge and kite fire as race events.
	var rf := RP.squad(["runeborn", "runeborn", "runeborn"])
	var rs := _id_of(rf, SS)
	var r = rf.sim.fighters[rs]
	r.race_state["effects"].append({"src": "tree", "effect": {"type": "trigger", "on": "rune_discharge", "actions": [{"action": "apply_status", "status": "haste", "target": "self", "duration": 60}]}})
	r.effects.erase("haste")
	RacePassives.add_runes(rf.sim, rs, 10, "test")
	ctx.check("rune_discharge: a trigger on it fires when the runes discharge", r.effects.has("haste"))
	var bf := RP.squad(["human", "viking", "elf"])
	var bl := _id_of(bf, LB)
	var b = bf.sim.fighters[bl]
	_place(bf.sim, bl, [Vector3(1.5, 0, 0)])
	var kites := Mech.kiting(bf.sim, bl)
	var vault: Array = RacePassives.race_events(bl, b, {"type": "skill_cast", "player": bl, "skill": "vault_shot"}, bf.sim.fighters)
	_place(bf.sim, bl, [Vector3(9.0, 0, 0)])
	ctx.check("kite: a dodge from a 1.5 m enemy and Vault Shot are kites, a dodge 9 m away is not", kites and vault.has("kite") and not Mech.kiting(bf.sim, bl))


## Chunk 2: pilot_mod (Skirmisher kite distance, Remote Nova densest cast point).
func _pilot_mods(ctx) -> void:
	var f := RP.squad(["human", "viking", "elf"])
	var lb := _id_of(f, LB)
	var bow = f.sim.fighters[lb]
	var plain := Mech.kite_distance(bow, 0.0)
	bow.race_state["tree"]["pilot"] = {"kite_distance": 5.0}
	ctx.check("Skirmisher: the pilot kites at 5 m instead of %.0f m" % plain, plain == 3.0 and Mech.kite_distance(bow, 3.0) == 5.0)
	var mf := RP.squad(["human", "viking", "elf"], [SS, GS, MG])
	var sim = mf.sim
	var mg := _id_of(mf, MG)
	var m = sim.fighters[mg]
	var remote: Array = TreeData.load_default().node("mg_t2_ring_a")["effects"]
	m.race_state["tree"]["skills"]["repulse_nova"] = [remote[0]]
	m.race_state["tree"]["pilot"] = {"cast_center": "densest"}
	sim.bodies[mg].position = Vector3(0.0, sim.bodies[mg].position.y, 0.0)
	var pack := _place(sim, mg, [Vector3(5, 0, 0), Vector3(5.5, 0, 0.5), Vector3(5, 0, -0.5)])
	var choice: Dictionary = preload("res://logic/class_skills/use_rules.gd").choose(sim, mg, "repulse_nova", pack[0])
	ctx.check("Remote Nova: the pilot casts at the 3-enemy pack 5 m away", choice.get("point") is Vector3 and Vector2(choice["point"].x - sim.bodies[mg].position.x, choice["point"].z - sim.bodies[mg].position.z).length() > 4.0)
	_place(sim, mg, [])
	ctx.check("Remote Nova: nothing within 7 m -> no cast", preload("res://logic/class_skills/use_rules.gd").choose(sim, mg, "repulse_nova", -1).is_empty())
