extends RefCounted
## Card skill tree effects in battle (design/gdd/skill-tree.md 3.5, 4.5-4.7; acceptance 6, 7): learned nodes reach the
## fighter, cell_mod / gauge_mod / signature_mod / skill_upgrade change the numbers by the GDD formulas, trigger filters
## and node actions run. Nodes are looked up in the data by their effect shape, never by a hard-coded skill id.
const RP := preload("res://tests/test_race_passives.gd")
const SkillTree := preload("res://logic/skill_tree.gd")
const TreeData := preload("res://logic/skill_tree_data.gd")
const TreeEffects := preload("res://logic/skill_tree_effects.gd")
const Progress := preload("res://logic/card_progress.gd")
const Deck := preload("res://logic/card_deck.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const Fighter := preload("res://logic/fighter.gd")
const SS := "sword_shield"
const GS := "greatsword"
const LB := "longbow"


func run(ctx) -> void:
	_no_tree_no_change(ctx)
	_cell_mods(ctx)
	_gauge_mods(ctx)
	_signature_mods(ctx)
	_skill_upgrades(ctx)
	_triggers_and_actions(ctx)
	_exposed(ctx)


## The first node of `owner`'s branch whose effects contain one matching `pred` (Callable(effect) -> bool).
func _find(nodes: Array, pred: Callable) -> Dictionary:
	for n in nodes:
		for effect in n["effects"]:
			if pred.call(effect):
				return n
	return {}


## Gives `card` enough levels and writes `ids` straight into its tree (the rules are tested elsewhere; repair still runs
## at attach, so an invalid set would be dropped).
func _with_tree(f: Dictionary, card: String, ids: Array) -> void:
	Progress.grant(f.profile.card_deck, card, 10000000)
	var tree := SkillTree.empty()
	var data = TreeData.load_default()
	for id in ids:
		tree[data.branch_of(id)].append(id)
	f.profile.card_deck["cards"][card]["skill_tree"] = tree


## A squad fight with these races where `prepare` (Callable(f)) learns nodes before the fighters attach.
func _squad(races: Array, prepare: Callable) -> Dictionary:
	var f := RP.squad(races)  # builds and attaches; re-attach after the tree is written
	prepare.call(f)
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	return f


## The gate-filling class nodes (all T1 + one per T2 pair) so a deeper node passes repair.
func _class_path(data, card: String, through_tier: int) -> Array:
	var out: Array = []
	var pairs := {}
	for n in data.class_nodes(card):
		if int(n["tier"]) > through_tier:
			continue
		if not str(n["excl"]).is_empty():
			if pairs.has(n["excl"]):
				continue
			pairs[n["excl"]] = true
		out.append(n["id"])
	return out


func _race_path(data, race: String, through_tier: int) -> Array:
	return data.race_nodes(race).filter(func(n): return int(n["tier"]) <= through_tier and str(n["excl"]).is_empty()).map(func(n): return n["id"])


func _id_of(f: Dictionary, card: String) -> int:
	for id in f.sim.runs:
		if str(f.sim.runs[id].card_id) == card:
			return id
	return -1


func _no_tree_no_change(ctx) -> void:
	var f := RP.squad(["human", "viking", "elf"])
	var me = f.sim.fighters[1]
	ctx.check("a card with no tree has an empty tree state", TreeEffects.nodes(me).is_empty() and TreeEffects.mechanics(me).is_empty())
	ctx.check("no tree: the ultimate fires at the full gauge", TreeEffects.fire_threshold(me, 100.0) == 100.0 and TreeEffects.gauge_after_cast(me) == 0.0)


func _cell_mods(ctx) -> void:
	var data = TreeData.load_default()
	# 4.6 Thick Blood on Berserker: full_at 0.2 -> 0.3; at 50% HP bonus = 0.40 x 0.5 / 0.7 = 0.286.
	var thick := _find(data.race_nodes("viking"), func(e): return e["type"] == "cell_mod" and e.has("hp_threshold_add"))
	var f := _squad(["human", "viking", "elf"], func(f): _with_tree(f, GS, [thick["id"]]))
	var gs = f.sim.fighters[_id_of(f, GS)]
	gs.hp = gs.max_hp() * 0.5
	ctx.check("4.6 Thick Blood: Berserker at 50%% HP = 0.286 (%.3f)" % RacePassives.scaling_mul(gs, "ATK"), absf(RacePassives.scaling_mul(gs, "ATK") - 0.4 * 0.5 / 0.7) < 0.001)
	# 4.6 Drilled Ranks on Rallying Drill: icd 10 s x 0.75 = 7.5 s (cooldown_ticks 600 -> 450).
	var drilled := _find(data.race_nodes("human"), func(e): return e["type"] == "cell_mod" and e.has("icd_mul"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, SS, [drilled["id"]]))
	var ss = f.sim.fighters[_id_of(f, SS)]
	var drill: Array = ss.race_state["effects"].filter(func(e): return e["src"] == "passive" and e["effect"].has("cooldown_ticks"))
	ctx.check("4.6 Drilled Ranks: Rallying Drill 600 -> 450 ticks", drill.size() == 1 and int(drill[0]["effect"]["cooldown_ticks"]) == 450)
	# 4.6 Blood Price on Unbowed Roar: fury 1.5 -> 2.0.
	var price := _find(data.race_nodes("viking"), func(e): return e["type"] == "cell_mod" and e.has("fury_add"))
	f = _squad(["viking", "viking", "elf"], func(f): _with_tree(f, SS, _race_path(data, "viking", 1) + [price["id"]]))
	ss = f.sim.fighters[_id_of(f, SS)]
	var fury: Array = ss.race_state["ultimate"]["actions"].filter(func(a): return a.has("fury"))
	ctx.check("4.6 Blood Price: the ultimate's fury 1.5 -> 2.0 %s" % [fury.map(func(a): return a["fury"])], not fury.is_empty() and fury.all(func(a): return absf(float(a["fury"]) - 2.0) < 0.001))
	# Overgrowth on any Elf ultimate: heals x1.3, radii x1.25.
	var grow := _find(data.race_nodes("elf"), func(e): return e["type"] == "cell_mod" and e.has("heal_mul") and str(e["cell"]) == "ultimate")
	f = RP.squad(["human", "viking", "elf"])
	var lb_before: Dictionary = f.sim.fighters[_id_of(f, LB)].race_state["ultimate"].duplicate(true)
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, LB, _race_path(data, "elf", 1) + [grow["id"]]))
	var lb_after: Dictionary = f.sim.fighters[_id_of(f, LB)].race_state["ultimate"]
	ctx.check("Overgrowth changes the Elf ultimate's numbers", JSON.stringify(lb_before["actions"]) != JSON.stringify(lb_after["actions"]))
	# Quick Glyphs: Runeborn rune max -1 (bow 6 -> 5).
	var glyphs := _find(data.race_nodes("runeborn"), func(e): return e["type"] == "cell_mod" and e.has("charges_max_add"))
	f = _squad(["human", "viking", "runeborn"], func(f): _with_tree(f, LB, [glyphs["id"]]))
	var charges: Array = f.sim.fighters[_id_of(f, LB)].race_state["effects"].filter(func(e): return e["effect"]["type"] == "charges")
	ctx.check("Quick Glyphs: bow runes 6 -> 5", charges.size() == 1 and int(charges[0]["effect"]["max"]) == 5)


func _gauge_mods(ctx) -> void:
	var data = TreeData.load_default()
	var stance := _find(data.race_nodes("human"), func(e): return e["type"] == "gauge_mod" and e.has("start"))
	var f := _squad(["human", "viking", "elf"], func(f): _with_tree(f, SS, [stance["id"]]))
	var id := _id_of(f, SS)
	var me = f.sim.fighters[id]
	me.gauge = 0.0
	RacePassives.gain_gauge(f.sim, id, me, [], false)
	ctx.check("4.7 Ready Stance: the run starts with 40 gauge", me.gauge >= 40.0)
	var command := _find(data.race_nodes("human"), func(e): return e["type"] == "gauge_mod" and e.has("charge_mul"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, SS, _race_path(data, "human", 2) + [command["id"]]))
	id = _id_of(f, SS)
	me = f.sim.fighters[id]
	me.gauge = 0.0
	var plain := RP.squad(["human", "viking", "elf"])
	var base = plain.sim.fighters[id]
	base.gauge = 0.0
	var with_node: float = RacePassives.gain_gauge(f.sim, id, me, [], true)
	var without: float = RacePassives.gain_gauge(plain.sim, id, base, [], true)
	ctx.check("4.7 Field Command: time gain x1.2 (%.4f vs %.4f)" % [with_node, without], without > 0.0 and absf(with_node / without - 1.2) < 0.001)
	var scent := _find(data.race_nodes("viking"), func(e): return e["type"] == "gauge_mod" and e.has("kill_add"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, GS, [scent["id"]]))
	id = _id_of(f, GS)
	me = f.sim.fighters[id]
	me.gauge = 0.0
	var enemy := RP.enemy_of(f.sim)
	var got: float = RacePassives.gain_gauge(f.sim, id, me, [{"type": "killed", "target": enemy, "by": id}], false)
	ctx.check("Battle Scent: a kill gives 4 + 6 = 10 gauge (%.2f)" % got, absf(got - 10.0) < 0.001)
	var gang := _find(data.race_nodes("viking"), func(e): return e["type"] == "gauge_mod" and e.has("fire_at"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, GS, _race_path(data, "viking", 3) + [gang["id"]]))
	me = f.sim.fighters[_id_of(f, GS)]
	me.hp = me.max_hp() * 0.3
	var low: float = TreeEffects.fire_threshold(me, 100.0)
	me.hp = me.max_hp()
	ctx.check("Berserkergang: 60 gauge below 35%% HP, 100 above (%.0f / %.0f)" % [low, TreeEffects.fire_threshold(me, 100.0)], low == 60.0 and TreeEffects.fire_threshold(me, 100.0) == 100.0)
	var overflow := _find(data.race_nodes("human"), func(e): return e["type"] == "gauge_mod" and e.has("after_cast"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, SS, _race_path(data, "human", 3) + [overflow["id"]]))
	ctx.check("Mastery Overflow: 35 gauge left after a cast", TreeEffects.gauge_after_cast(f.sim.fighters[_id_of(f, SS)]) == 35.0)


func _signature_mods(ctx) -> void:
	var data = TreeData.load_default()
	var arc := _find(data.class_nodes(GS), func(e): return e["type"] == "signature_mod" and e.has("per_target_add"))
	var f := _squad(["human", "viking", "elf"], func(f): _with_tree(f, GS, _class_path(data, GS, 2) + [arc["id"]]))
	var gs = f.sim.fighters[_id_of(f, GS)]
	ctx.check("Executioner's Arc: Cleave +20%% per extra, max +60%% (4 hit: %.2f, 6 hit: %.2f)" % [RacePassives.cleave_mul(gs, 4), RacePassives.cleave_mul(gs, 6)], absf(RacePassives.cleave_mul(gs, 4) - 1.6) < 0.001 and absf(RacePassives.cleave_mul(gs, 6) - 1.6) < 0.001 and absf(RacePassives.cleave_mul(gs, 2) - 1.2) < 0.001)
	var wall := _find(data.class_nodes(SS), func(e): return e["type"] == "signature_mod" and e.has("every_mul"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, SS, _class_path(data, SS, 2) + [wall["id"]]))
	var aggro: Array = f.sim.fighters[_id_of(f, SS)].race_state["effects"].filter(func(e): return e["effect"]["type"] == "aggro")
	ctx.check("Unyielding Bulwark: cycle 8 s -> 6 s (480 -> 360 ticks)", aggro.size() == 1 and int(aggro[0]["effect"]["every_ticks"]) == 360)


func _skill_upgrades(ctx) -> void:
	var data = TreeData.load_default()
	# Acceptance 6: each T2 modifier gives the old gem's numbers. Damage x0.7 and +2 projectiles (multishot), per 4.5.
	for card in data.classes:
		for n in data.class_nodes(card):
			for effect in n["effects"]:
				if effect["type"] != "skill_upgrade":
					continue
				var stats := {"skill_id": effect["skill"], "damage": 16.0, "projectile_count": 1.0, "radius": 3.0, "cooldown": 5.0, "repeat": 1.0, "repeat_damage_mul": 1.0, "statuses": []}
				var fighter := Fighter.new()
				fighter.race_state = {"tree": {"skills": {effect["skill"]: [effect]}}}
				TreeEffects.upgrade_skill(fighter, stats)
				var expected := {"damage": 16.0, "projectile_count": 1.0, "radius": 3.0, "cooldown": 5.0, "repeat": 1.0, "repeat_damage_mul": 1.0}
				for op in [0, 1, 2]:
					for mod in effect["mods"]:
						if int(mod["op"]) == op:
							var v := float(expected.get(mod["stat"], 0.0))
							expected[mod["stat"]] = v + float(mod["value"]) if op == 0 else (v * float(mod["value"]) if op == 1 else float(mod["value"]))
				var same := true
				for key in expected:
					same = same and absf(float(stats.get(key, 0.0)) - float(expected[key])) < 0.0001
				if effect.has("status"):
					same = same and stats["statuses"].has(effect["status"])
				if not same:
					ctx.check("%s upgrades its skill by its mods" % n["id"], false)
	var triple := _find(data.class_nodes("magic"), func(e): return e["type"] == "skill_upgrade" and e["mods"].any(func(m): return m["stat"] == "projectile_count"))
	var effect: Dictionary = triple["effects"][0]
	var fighter := Fighter.new()
	fighter.race_state = {"tree": {"skills": {effect["skill"]: [effect]}}}
	var stats := {"skill_id": effect["skill"], "damage": 16.0, "projectile_count": 1.0, "statuses": []}
	TreeEffects.upgrade_skill(fighter, stats)
	ctx.check("4.5 Triple Fireball: 3 x 16 x 0.7 = 33.6 on a pack", absf(stats["projectile_count"] * stats["damage"] - 33.6) < 0.001)
	var other := {"skill_id": "not_this_skill", "damage": 16.0}
	TreeEffects.upgrade_skill(fighter, other)
	ctx.check("an upgrade touches only its own skill", other["damage"] == 16.0)


func _triggers_and_actions(ctx) -> void:
	var data = TreeData.load_default()
	# A trigger with a `skill` filter fires only for that skill (the id comes from the node data).
	var line := _find(data.class_nodes(LB), func(e): return e["type"] == "trigger" and e.has("skill"))
	var skill := str(line["effects"].filter(func(e): return e.has("skill"))[0]["skill"])
	var f := _squad(["human", "viking", "elf"], func(f): _with_tree(f, LB, [line["id"]]))
	var id := _id_of(f, LB)
	var enemy := RP.enemy_of(f.sim)
	var other_skill := "x_" + skill
	var miss := RP.react(f.sim, {"type": "skill_hit", "attacker": id, "target": enemy, "damage": 5.0, "move": "skill:" + other_skill})
	var hit := RP.react(f.sim, {"type": "skill_hit", "attacker": id, "target": enemy, "damage": 5.0, "move": "skill:" + skill})
	ctx.check("a skill-filtered trigger ignores other skills", RP.procs(miss, id).filter(func(e): return e["source"] == "tree").is_empty())
	ctx.check("and fires on its own skill", not RP.procs(hit, id).filter(func(e): return e["source"] == "tree").is_empty())
	# Faultline: pull enemies 1.5 m toward the card.
	var fault := _find(data.class_nodes(GS), func(e): return e["type"] == "trigger" and e["actions"].any(func(a): return a["action"] == "pull"))
	f = _squad(["human", "viking", "elf"], func(f): _with_tree(f, GS, [fault["id"]]))
	id = _id_of(f, GS)
	enemy = RP.enemy_of(f.sim)
	var me: Vector3 = f.sim.bodies[id].position
	f.sim.bodies[enemy].position = me + Vector3(4.0, 0.0, 0.0)
	var cast_skill := str(fault["effects"][0]["skill"])
	var events := RP.react(f.sim, {"type": "skill_cast", "player": id, "skill": cast_skill})
	var after := Vector2(f.sim.bodies[enemy].position.x - me.x, f.sim.bodies[enemy].position.z - me.z).length()
	ctx.check("Faultline pulls an enemy 4 m -> 2.5 m (%.2f)" % after, absf(after - 2.5) < 0.01 and events.any(func(e): return e["type"] == "tree_pull"))
	# Rallying Wall: the signature_pulse event is not emitted yet, so allies_in_radius is checked directly.
	ctx.check("allies_in_radius finds the card itself", TreeEffects.targets(f.sim, id, "allies_in_radius", {"radius": 4.0}).has(id))


func _exposed(ctx) -> void:
	var data = TreeData.load_default()
	var twin := _find(data.race_nodes("human"), func(e): return e["type"] == "mechanic")
	var f := _squad(["human", "viking", "elf"], func(f): _with_tree(f, SS, _race_path(data, "human", 2) + [twin["id"]]))
	var me = f.sim.fighters[_id_of(f, SS)]
	ctx.check("learned mechanic nodes are exposed by id", TreeEffects.mechanics(me).has(str(twin["effects"].filter(func(e): return e["type"] == "mechanic")[0]["id"])))
	ctx.check("the fighter lists its learned nodes", TreeEffects.nodes(me).has(twin["id"]))
	var snap: Dictionary = f.sim.snapshot()
	ctx.check("the tree state rides in the sim checkpoint", JSON.stringify(preload("res://logic/state_codec.gd").pack(snap)).contains("start_pending"))
