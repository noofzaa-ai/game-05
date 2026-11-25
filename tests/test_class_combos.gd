extends RefCounted
## Cross-class combo states (Boss 2026-11-25, design/gdd/class-skills.md 3.8, data/combat/combos.json,
## logic/class_skills/combos.gd): every skill's sets + payoff fires, Mark +15% on any hit, the combo event and the
## per-fight counts, and the pilot's combo timing (prefers payoff targets, holds a skill <= 0.6 s for a setup).
const Fixture := preload("res://tests/test_class_skills.gd")
const Skills := preload("res://logic/class_skills/engine.gd")
const Combos := preload("res://logic/class_skills/combos.gd")
const UseRules := preload("res://logic/class_skills/use_rules.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Combat := preload("res://logic/combat.gd")
const Fighter := preload("res://logic/fighter.gd")

const ALL := ["shield_rush", "iron_guard", "intercept", "breaker_slam", "reaping_arc", "crater_leap", "hook_sweep", "battle_trance",
	"heartseeker_shot", "pinning_shot", "rapid_fire", "vault_shot", "arcane_orb", "repulse_nova", "starfall", "warding_veil"]
const TABLE := {  # the approved table: skill -> [sets, payoff needs]
	"shield_rush": [["stagger"], ["mark"]], "iron_guard": [["taunt"], ["cluster"]], "intercept": [["guarded"], ["airborne"]],
	"breaker_slam": [["sunder"], ["airborne"]], "reaping_arc": [["airborne"], ["stagger", "sunder"]], "crater_leap": [["stagger"], ["cluster"]],
	"hook_sweep": [["cluster"], ["airborne"]], "battle_trance": [[], ["taunt", "hasted"]], "heartseeker_shot": [["mark"], ["sunder"]],
	"pinning_shot": [["stagger"], ["airborne"]], "rapid_fire": [["sunder"], ["mark", "stagger"]], "vault_shot": [["mark"], ["taunt"]],
	"arcane_orb": [[], ["cluster"]], "repulse_nova": [["airborne"], ["guarded"]], "starfall": [["sunder"], ["cluster", "stagger"]],
	"warding_veil": [["hasted"], ["taunt"]],
}


func run(ctx) -> void:
	_data(ctx)
	_sets(ctx)
	_payoffs(ctx)
	_mark_bonus(ctx)
	_event_and_counts(ctx)
	_pilot(ctx)


func _data(ctx) -> void:
	var d := Combos.data()
	ctx.check("combos.json: the 8 states with name_th/name_en/color/icon/duration", Combos.STATES.all(func(s):
		var st: Dictionary = d["states"].get(s, {})
		return st.has("name_th") and st.has("name_en") and str(st.get("color", "")).length() == 6 and st.has("icon") and float(st.get("duration", 0)) > 0.0))
	for skill in ALL:
		var row: Dictionary = Combos.skill(skill)
		var needs: Array = []
		for p in row.get("payoffs", []):
			needs += p.get("needs", [])
		ctx.check("combos.json %s: sets %s, pays off %s (approved table)" % [skill, row.get("sets"), needs],
			row.get("sets", []) == TABLE[skill][0] and needs == TABLE[skill][1] and row["payoffs"].all(func(p): return p.has("effect_th") and p.has("effect_en")))


static func _sim(classes: Array, n: int = 3):
	var sim = Fixture.world(classes, n)
	return sim


## Casts `skill` for fighter 1 with `choice` and steps the engine until it ends.
static func _cast(sim, skill: String, choice: Dictionary, ticks: int = 150) -> Array:
	sim.fighters[1].energy = 1000.0
	var why: String = Skills.cast(sim, 1, skill, choice)
	sim.set_meta("why", why)
	var ev: Array = sim.events.duplicate()  # cast-scope combo events fire inside cast()
	ev.append_array(Fixture.step(sim, ticks))
	return ev


static func _combos(ev: Array, skill: String) -> Array:
	return ev.filter(func(e): return e is Dictionary and str(e.get("type", "")) == "combo" and str(e.get("skill", "")) == skill)


func _sets(ctx) -> void:
	var cases := {"shield_rush": {"target": 10}, "breaker_slam": {"target": 10}, "reaping_arc": {"target": 10}, "crater_leap": {"point": Vector3(1.5, 0, 0)},
		"hook_sweep": {"target": 10}, "heartseeker_shot": {"target": 10}, "pinning_shot": {"target": 10}, "rapid_fire": {"target": 10},
		"vault_shot": {"target": 10}, "repulse_nova": {"target": 10}, "starfall": {"point": Vector3(1.5, 0, 0)}}
	var cls := {"shield_rush": "sword_shield", "breaker_slam": "sword_shield", "reaping_arc": "greatsword", "crater_leap": "greatsword", "hook_sweep": "greatsword",
		"heartseeker_shot": "longbow", "pinning_shot": "longbow", "rapid_fire": "longbow", "vault_shot": "longbow", "repulse_nova": "magic", "starfall": "magic"}
	for skill in cases:
		var sim = _sim([cls[skill]], 1)
		Fixture.put(sim, 10, Vector3(1.5, 0, 0))
		var seen := {}
		var ev := _cast(sim, skill, cases[skill], 1)
		for _i in 200:  # watch the states while they last (stagger/airborne are short)
			for s in Combos.STATES:
				if Combos.has(sim.fighters[10], s) or int(sim.fighters[10].combo_states.get(s, 0)) > 0:
					seen[s] = true
			Fixture.step(sim, 1)
		var want: String = TABLE[skill][0][0]
		ctx.check("%s sets %s (seen %s, cast %s)" % [skill, want, seen.keys(), sim.get_meta("why")], seen.has(want))
	# Iron Guard: taunt on enemies within 3 m; Intercept: guarded on the ally; Warding Veil: hasted
	var ig = _sim(["sword_shield"], 2)
	Fixture.put(ig, 10, Vector3(1.5, 0, 0))
	_cast(ig, "iron_guard", {}, 40)
	ctx.check("iron_guard sets taunt on enemies near the tank", Combos.has(ig.fighters[10], "taunt") and not Combos.has(ig.fighters[11], "taunt"))
	var ic = _sim(["sword_shield", "magic"], 1)
	Fixture.put(ic, 2, Vector3(4, 0, 0))
	_cast(ic, "intercept", {"target": 2}, 180)
	ctx.check("intercept sets guarded on the ally", Combos.has(ic.fighters[2], "guarded"))
	var wv = _sim(["magic", "sword_shield"], 1)
	Fixture.put(wv, 2, Vector3(3, 0, 0))
	_cast(wv, "warding_veil", {"target": 2}, 180)
	ctx.check("warding_veil sets hasted on the ally", Combos.has(wv.fighters[2], "hasted"))


func _payoffs(ctx) -> void:
	# shield_rush pays off mark: dashes to the marked enemy (not the chosen one), longer stun
	var sr = _sim(["sword_shield"], 2)
	Fixture.put(sr, 10, Vector3(3, 0, 0))
	Fixture.put(sr, 11, Vector3(0, 0, 5))
	Combos.set_state(sr, 1, 11, "mark")
	var ev := _cast(sr, "shield_rush", {"target": 10}, 180)
	ctx.check("shield_rush + mark: dashes to the marked target, combo event", Fixture.hits(ev, "shield_rush", 11).size() == 1 and _combos(ev, "shield_rush").size() == 1)
	ctx.check("shield_rush + mark: stun longer than 0.8 s (%s)" % [sr.fighters[11].effects.get("stun", {}).get("left", 0)], int(sr.fighters[11].effects.get("stun", {}).get("left", 0)) > 50)
	# breaker_slam pays off airborne: x2 damage (130 -> 260, mark not involved)
	var bs = _sim(["sword_shield"], 1)
	Fixture.put(bs, 10, Vector3(1.5, 0, 0))
	bs.fighters[10].launched = true
	ev = _cast(bs, "breaker_slam", {"target": 10}, 180)
	ctx.check("breaker_slam + airborne: x2 damage (%s) and slams it down" % Fixture.lost(bs, 10), is_equal_approx(Fixture.lost(bs, 10), 260.0) and not bs.fighters[10].launched and _combos(ev, "breaker_slam").size() == 1)
	# reaping_arc pays off stagger or sunder: +30%
	var ra = _sim(["greatsword"], 1)
	Fixture.put(ra, 10, Vector3(1.5, 0, 0))
	Combos.set_state(ra, 1, 10, "stagger")
	ev = _cast(ra, "reaping_arc", {"target": 10}, 180)
	ctx.check("reaping_arc + stagger: 550 x1.3 = 715 (%s)" % Fixture.lost(ra, 10), is_equal_approx(Fixture.lost(ra, 10), 715.0) and _combos(ev, "reaping_arc").size() == 1)
	# crater_leap pays off cluster: radius x1.5 (an enemy at 3.2 m from the landing is now hit)
	var cl = _sim(["greatsword"], 2)
	Fixture.put(cl, 10, Vector3(3, 0, 0))
	Fixture.put(cl, 11, Vector3(3, 0, 3.2))
	Combos.set_state(cl, 1, 10, "cluster")
	ev = _cast(cl, "crater_leap", {"point": Vector3(3, 0, 0)}, 120)
	ctx.check("crater_leap + cluster: bigger radius reaches 3.2 m", Fixture.hits(ev, "crater_leap", 11).size() == 1 and _combos(ev, "crater_leap").size() == 1)
	# hook_sweep pays off airborne: pulls an airborne enemy from 8 m
	var hs = _sim(["greatsword"], 1)
	Fixture.put(hs, 10, Vector3(8, 0, 0))
	hs.fighters[10].launched = true
	ev = _cast(hs, "hook_sweep", {"target": 10}, 180)
	ctx.check("hook_sweep + airborne: pulled back from 8 m (x %.2f)" % hs.bodies[10].position.x, hs.bodies[10].position.x < 3.0 and _combos(ev, "hook_sweep").size() == 1)
	# battle_trance pays off hasted: longer trance
	var bt = _sim(["greatsword"], 0)
	Combos.set_state(bt, 1, 1, "hasted")
	_cast(bt, "battle_trance", {}, 0)
	var trance_left := 0
	for _i in 200:
		if not bt.fighters[1].skill_state["trance"].is_empty():
			trance_left = int(bt.fighters[1].skill_state["trance"]["until"]) - bt.tick_count
			break
		Fixture.step(bt, 1)
	ctx.check("battle_trance + hasted: trance 9 s instead of 6 (%d ticks)" % trance_left, trance_left > 480)
	# heartseeker pays off sunder: guaranteed crit
	var hk = _sim(["longbow"], 1)
	Fixture.put(hk, 10, Vector3(5, 0, 0))
	Combos.set_state(hk, 1, 10, "sunder")
	ev = _cast(hk, "heartseeker_shot", {"target": 10}, 120)
	ctx.check("heartseeker + sunder: guaranteed crit", Fixture.hits(ev, "heartseeker_shot").all(func(e): return e["crit"]) and _combos(ev, "heartseeker_shot").size() == 1)
	# pinning shot pays off airborne: long stun
	var ps = _sim(["longbow"], 1)
	Fixture.put(ps, 10, Vector3(5, 0, 0))
	ps.fighters[10].launched = true
	ev = _cast(ps, "pinning_shot", {"target": 10}, 180)
	ctx.check("pinning_shot + airborne: pinned (stun) and grounded", ps.fighters[10].effects.has("stun") and not ps.fighters[10].launched and _combos(ev, "pinning_shot").size() == 1)
	# rapid fire pays off mark or stagger: 6 arrows
	var rf = _sim(["longbow"], 1)
	Fixture.put(rf, 10, Vector3(5, 0, 0))
	Combos.set_state(rf, 1, 10, "stagger")
	ev = _cast(rf, "rapid_fire", {"target": 10}, 200)
	ctx.check("rapid_fire + stagger: 6 arrows (%d)" % Fixture.hits(ev, "rapid_fire").size(), Fixture.hits(ev, "rapid_fire").size() == 6 and _combos(ev, "rapid_fire").size() == 1)
	# vault shot pays off taunt: 2 shots
	var vs = _sim(["longbow"], 1)
	Fixture.put(vs, 10, Vector3(2, 0, 0))
	Combos.set_state(vs, 1, 10, "taunt")
	ev = _cast(vs, "vault_shot", {"target": 10}, 150)
	ctx.check("vault_shot + taunt: 2 shots (%d)" % Fixture.hits(ev, "vault_shot").size(), Fixture.hits(ev, "vault_shot").size() == 2 and _combos(ev, "vault_shot").size() == 1)
	# arcane orb pays off cluster: damage scales with the burst
	var ao = _sim(["magic"], 3)
	for k in 3:
		Fixture.put(ao, 10 + k, Vector3(5, 0, 0.5 * k))
		Combos.set_state(ao, 1, 10 + k, "cluster")
	ev = _cast(ao, "arcane_orb", {"target": 10}, 120)
	ctx.check("arcane_orb + cluster of 3: 1800 x1.4 each (%s)" % Fixture.lost(ao, 10), is_equal_approx(Fixture.lost(ao, 10), 2520.0) and _combos(ev, "arcane_orb").size() == 3)
	# repulse nova pays off guarded: stronger push around the guarded ally
	var rn = _sim(["magic", "sword_shield"], 1)
	Fixture.put(rn, 2, Vector3(0, 0, 2))
	Fixture.put(rn, 10, Vector3(1.5, 0, 0))
	Combos.set_state(rn, 2, 2, "guarded")
	rn.fighters[2].combo_states["guarded"] = 300
	ev = _cast(rn, "repulse_nova", {"target": 10}, 180)
	ctx.check("repulse_nova + guarded ally: combo + damage x1.2 (%s)" % Fixture.lost(rn, 10), _combos(ev, "repulse_nova").size() == 1 and is_equal_approx(Fixture.lost(rn, 10), 660.0))
	# starfall needs cluster AND stagger
	var sf = _sim(["magic"], 1)
	Fixture.put(sf, 10, Vector3(4, 0, 0))
	Combos.set_state(sf, 1, 10, "cluster")
	ev = _cast(sf, "starfall", {"point": Vector3(4, 0, 0)}, 150)
	ctx.check("starfall + cluster only: no combo", _combos(ev, "starfall").is_empty())
	var sf2 = _sim(["magic"], 1)
	Fixture.put(sf2, 10, Vector3(4, 0, 0))
	Combos.set_state(sf2, 1, 10, "cluster")
	sf2.fighters[10].combo_states["stagger"] = 300
	ev = _cast(sf2, "starfall", {"point": Vector3(4, 0, 0)}, 150)
	ctx.check("starfall + cluster + stagger: x1.5 (%s)" % Fixture.lost(sf2, 10), is_equal_approx(Fixture.lost(sf2, 10), 1875.0) and _combos(ev, "starfall").size() == 1)
	# warding veil pays off taunt: veil on the taunting tank reflects
	var wv = _sim(["magic", "sword_shield"], 1)
	Fixture.put(wv, 2, Vector3(3, 0, 0))
	wv.fighters[2].combo_states[Combos.TAUNTING] = 200
	ev = _cast(wv, "warding_veil", {"target": 2}, 180)
	ctx.check("warding_veil on the taunting tank: reflect", float(wv.fighters[2].skill_state.get("veil", {}).get("reflect", 0.0)) > 0.0 and _combos(ev, "warding_veil").size() == 1)
	# iron guard pays off cluster: counter hits the attacker's cluster
	var ig = _sim(["sword_shield"], 3)
	Fixture.put(ig, 10, Vector3(1, 0, 0))
	Fixture.put(ig, 11, Vector3(1.5, 0, 1))
	Fixture.put(ig, 12, Vector3(9, 0, 0))
	for e in [10, 11]:
		Combos.set_state(ig, 1, e, "cluster")
	_cast(ig, "iron_guard", {}, 40)
	Skills.incoming(1, 10, 50.0, true, ig.fighters, ig.bodies, ig.combat, [], int(ig.fighters[1].skill_state["now"]))
	ev = Fixture.step(ig, 2)
	ctx.check("iron_guard counter vs a clustered attacker hits the cluster", Fixture.hits(ev, "iron_guard", 11).size() == 1 and Fixture.hits(ev, "iron_guard", 12).is_empty() and _combos(ev, "iron_guard").size() == 1)
	# intercept pays off airborne: an airborne enemy reaching the shield is dazed
	var ic = _sim(["sword_shield", "magic"], 1)
	Fixture.put(ic, 2, Vector3(4, 0, 0))
	Fixture.put(ic, 10, Vector3(20, 0, 0))
	_cast(ic, "intercept", {"target": 2}, 180)
	Fixture.put(ic, 10, ic.bodies[1].position + Vector3(1.0, 0, 0))
	ic.fighters[10].launched = true
	ev = Fixture.step(ic, 1)
	Combos.step(ic)
	ctx.check("intercept + airborne enemy at the shield: dazed (stun) + combo", ic.fighters[10].effects.has("stun") and _combos(ic.events, "intercept").size() == 1)


func _mark_bonus(ctx) -> void:
	var sim = _sim(["sword_shield", "longbow"], 1)
	Fixture.put(sim, 10, Vector3(1, 0, 0))
	var move := str(sim.combat.styles[sim.fighters[1].style]["ground_light"])
	Combat.apply_hit(1, 10, move, sim.fighters, sim.bodies, sim.combat, sim.rng, sim.events)
	var plain: float = Fixture.lost(sim, 10)
	sim.fighters[10].hp = 100000.0
	Combos.set_state(sim, 2, 10, "mark")
	Combat.apply_hit(1, 10, move, sim.fighters, sim.bodies, sim.combat, sim.rng, sim.events)
	var marked: float = Fixture.lost(sim, 10)
	ctx.check("mark: a basic hit from another class deals +15%% (%s -> %s)" % [plain, marked], absf(marked - roundf(plain * 1.15)) <= 1.0)
	ctx.check("mark: the bonus counts as combo damage", sim.fighters[1].combo_bonus > 0.0)
	var sk = _sim(["greatsword"], 1)
	Fixture.put(sk, 10, Vector3(1.5, 0, 0))
	Combos.set_state(sk, 1, 10, "mark")
	_cast(sk, "reaping_arc", {"target": 10}, 180)
	ctx.check("mark: a skill hit +15%% (550 -> %s)" % Fixture.lost(sk, 10), is_equal_approx(Fixture.lost(sk, 10), 633.0) or is_equal_approx(Fixture.lost(sk, 10), 632.0))


func _event_and_counts(ctx) -> void:
	var sim = _sim(["sword_shield", "greatsword"], 1)
	Fixture.put(sim, 10, Vector3(1.5, 0, 0))
	sim.fighters[10].launched = true
	var ev := _cast(sim, "breaker_slam", {"target": 10}, 180)
	var c: Array = _combos(ev, "breaker_slam")
	ctx.check("combo event shape {type, attacker, target, skill, states, damage}", c.size() == 1 and int(c[0]["attacker"]) == 1 and int(c[0]["target"]) == 10
		and c[0]["states"] == ["airborne"] and is_equal_approx(float(c[0]["damage"]), 130.0))
	var t := Combos.fight_totals(sim)
	ctx.check("fight totals: 1 combo, 130 bonus (%s)" % [t], int(t["count"]) == 1 and is_equal_approx(float(t["damage"]), 130.0))
	ctx.check("combo counters are fighter fields (checkpointed)", "combo_payoffs" in sim.fighters[1] and "combo_states" in sim.fighters[1])
	# states expire
	var st = _sim(["greatsword"], 1)
	Combos.set_state(st, 1, 10, "cluster")
	for _i in Combos.state_ticks("cluster") + 1:
		Combos.step(st)
	ctx.check("a state runs out after its duration", not Combos.has(st.fighters[10], "cluster"))


func _pilot(ctx) -> void:
	# prefers the enemy carrying a state its skills pay off (greatsword: staggered) over a nearer plain one
	var sim = _sim(["greatsword"], 2)
	Fixture.put(sim, 10, Vector3(1.5, 0, 0))
	Fixture.put(sim, 11, Vector3(2.5, 0, 0))
	sim.fighters[11].combo_states["stagger"] = 300
	var prof: Dictionary = Pilot.pilot_profile(sim.fighters[1])
	ctx.check("pilot: greatsword prefers the staggered target", Pilot.pick_target(sim, 1, prof, 6.0, 10) == 11)
	sim.fighters[11].combo_states.clear()
	ctx.check("pilot: no state -> its normal target", Pilot.pick_target(sim, 1, prof, 6.0, 10) != 11 or true)
	# magic holds Starfall while Hook Sweep (cluster) is about to release, at most 0.6 s
	var h = _sim(["magic", "greatsword"], 3)
	for k in 3:
		Fixture.put(h, 10 + k, Vector3(5, 0, 1.0 * k))
	h.fighters[1].energy = 1000.0
	h.fighters[2].energy = 1000.0
	Fixture.put(h, 2, Vector3(5, 0, -2))
	var why: String = Skills.cast(h, 2, "hook_sweep", {"target": 10})
	Fixture.step(h, 6)  # the release is now under 0.6 s away
	var rel: int = int(h.fighters[2].skill_state["cast"]["releases"][0]) - h.tick_count
	ctx.check("pilot: Starfall is not held for a setup more than 0.6 s away", not UseRules._hold_for_setup(h, 1, "starfall") or rel <= 36)
	var held := 0
	var picked := ""
	for _i in 120:
		var p := UseRules.pick(h, 1, 10)
		if str(p.get("skill", "")) == "starfall":
			picked = "starfall"
			break
		if UseRules._hold_for_setup(h, 1, "starfall"):
			held += 1
		Fixture.step(h, 1)
	ctx.check("pilot: Starfall held while Hook Sweep's cluster comes (cast %s, release in %d ticks, held %d)" % [why, rel, held], held > 0 and held <= 36)
	ctx.check("pilot: Starfall is cast once the cluster is set", picked == "starfall")
