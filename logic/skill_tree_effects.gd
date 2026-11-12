extends RefCounted
## Card skill tree effects in battle (design/gdd/skill-tree.md 3.5, 3.9, 4.5-4.7, 6.4). Pure rules.
## attach() reads the card's learned nodes (server-validated, re-checked by SkillTree.repaired) and folds them into the
## fighter's race_state, which logic/race_passives.gd already runs and checkpoints:
##  - race vocabulary effects (stat_mod, low_hp_scaling, skill_mod, trigger, charges, aggro, cleave) join race_state.effects
##    with src "tree";
##  - cell_mod rewrites the card's race cell: "passive" = the src "passive" effects, "ultimate" = race_state.ultimate
##    (whatever race / class the card is: one node works on every cell);
##  - signature_mod rewrites the class signature entries (aggro: every/radius/duration; cleave: per target / max;
##    Hunter's Mark trigger: mark duration, extra actions);
##  - gauge_mod, skill_upgrade, pilot_mod and mechanic are stored in race_state.tree and read through the hooks below.
## Skill ids come only from the node data (skill_upgrade.skill, trigger.skill), so re-pointing a node to another skill is
## a data change. Mechanic ids are stored and exposed (mechanics()); the engine does not run them yet.
## Deterministic: no randomness here.

const SkillTree := preload("res://logic/skill_tree.gd")
const TreeData := preload("res://logic/skill_tree_data.gd")
const CardProgress := preload("res://logic/card_progress.gd")
const RaceData := preload("res://logic/race_data.gd")
const Effects := preload("res://logic/effects.gd")
const EFFECTS_FILE := "res://data/combat/effects.json"
const RACE_EFFECT_TYPES: Array[String] = ["stat_mod", "low_hp_scaling", "skill_mod", "trigger", "charges", "aggro", "cleave"]
## Node actions this module runs (race_passives.run_action hands them over). reflect / death_save load but stay inert.
const ACTIONS: Array[String] = ["pull", "cleanse", "skill_status"]
const SCALED_ACTION_KEYS: Array[String] = ["fraction", "atk_mul", "seconds"]

static var _status_durations: Dictionary = {}


## Folds the card's learned tree into `fighter.race_state` (call after RacePassives.attach built it).
static func attach(fighter, run) -> void:
	if fighter.race_state.is_empty() or run == null or not "card_id" in run:
		return
	var data = TreeData.load_default()
	if not data.errors.is_empty():
		return
	var deck: Dictionary = run.profile.card_deck
	var class_id := str(run.card_id)
	var race := str(fighter.race_state.get("race", ""))
	var tree := SkillTree.repaired(SkillTree.owned(deck, class_id), class_id, race, CardProgress.points_of(deck, class_id), data)
	var state := {"nodes": [], "gauge": {}, "sig": {}, "skills": {}, "pilot": {}, "mechanics": {}, "start_pending": false}
	var effects: Array = fighter.race_state["effects"]
	for branch in SkillTree.BRANCHES:
		for id in tree[branch]:
			state["nodes"].append(id)
			for effect in data.node(id).get("effects", []):
				_take(fighter, state, effects, (effect as Dictionary).duplicate(true))
	fighter.race_state["tree"] = state
	state["start_pending"] = float(state["gauge"].get("start", 0.0)) > 0.0
	_rebuild_derived(fighter)


static func _take(fighter, state: Dictionary, effects: Array, effect: Dictionary) -> void:
	var kind := str(effect.get("type", ""))
	if RACE_EFFECT_TYPES.has(kind):
		effects.append({"src": "tree", "effect": effect})
		return
	match kind:
		"cell_mod":
			if str(effect["cell"]) == "ultimate":
				var ult: Dictionary = fighter.race_state.get("ultimate", {})
				if not ult.is_empty():
					fighter.race_state["ultimate"] = cell_mod_ultimate(ult, effect)
			else:
				for entry in effects:
					if str(entry["src"]) == "passive":
						entry["effect"] = cell_mod_effect(entry["effect"], effect)
		"gauge_mod":
			var g: Dictionary = state["gauge"]
			for key in effect:
				if key == "type":
					continue
				if str(key).ends_with("_mul"):
					g[key] = float(g.get(key, 1.0)) * float(effect[key])
				elif str(key) in ["kill_add", "discharge_add", "start", "after_cast"]:
					g[key] = float(g.get(key, 0.0)) + float(effect[key])
				else:
					g[key] = effect[key]
		"signature_mod":
			for entry in effects:
				if str(entry["src"]) == "signature":
					entry["effect"] = signature_mod_effect(entry["effect"], effect)
			for key in effect:
				if key != "type":
					state["sig"][key] = effect[key]
		"skill_upgrade":
			var skill := str(effect["skill"])
			if not state["skills"].has(skill):
				state["skills"][skill] = []
			state["skills"][skill].append(effect)
		"pilot_mod":
			for key in effect:
				if key != "type":
					state["pilot"][key] = effect[key]
		"mechanic":
			var params: Dictionary = effect.duplicate(true)
			params.erase("type")
			state["mechanics"][str(effect["id"])] = params


## race_state.pseudo / scaling are derived from the effects list (RacePassives.attach built them before the tree joined).
static func _rebuild_derived(fighter) -> void:
	var pseudo := {}
	var scaling: Array = []
	for entry in fighter.race_state["effects"]:
		var effect: Dictionary = entry["effect"]
		if effect["type"] == "low_hp_scaling":
			scaling.append(effect)
		if effect["type"] == "stat_mod" and not RaceData.STAT_NAMES.has(str(effect["stat"])):
			var mod: Dictionary = pseudo.get(str(effect["stat"]), {"add": 0.0, "mul": 0.0})
			mod["add"] += float(effect.get("add", 0.0))
			mod["mul"] += float(effect.get("mul", 0.0))
			pseudo[str(effect["stat"])] = mod
	fighter.race_state["pseudo"] = pseudo
	fighter.race_state["scaling"] = scaling


# ---------------------------------------------------------------- cell_mod (GDD 3.5, 4.6)

## One passive effect after a cell_mod: value' = value x scale x field_mul (formula 4.6).
static func cell_mod_effect(effect: Dictionary, mod: Dictionary) -> Dictionary:
	var out: Dictionary = effect.duplicate(true)
	var scale := float(mod.get("scale", 1.0))
	match str(out["type"]):
		"stat_mod":
			for key in ["add", "mul"]:
				if out.has(key):
					out[key] = float(out[key]) * scale
		"low_hp_scaling":
			out["max_mul"] = float(out["max_mul"]) * scale
			if mod.has("hp_threshold_add"):
				if out.has("below"):
					out["below"] = float(out["below"]) + float(mod["hp_threshold_add"])
				else:
					out["full_at_hp"] = float(out.get("full_at_hp", 0.2)) + float(mod["hp_threshold_add"])
		"skill_mod":
			for key in ["damage_mul", "cooldown_mul", "radius_mul"]:
				if out.has(key):
					out[key] = 1.0 + (float(out[key]) - 1.0) * scale
			if out.has("crit_add"):
				out["crit_add"] = float(out["crit_add"]) * scale
		"trigger", "charges":
			if out.has("hp_below") and mod.has("hp_threshold_add"):
				out["hp_below"] = float(out["hp_below"]) + float(mod["hp_threshold_add"])
			if out.has("cooldown_ticks") and mod.has("icd_mul"):
				out["cooldown_ticks"] = int(round(float(out["cooldown_ticks"]) * float(mod["icd_mul"])))
			if out.has("every_n") and mod.has("every_n_add"):
				out["every_n"] = maxi(1, int(out["every_n"]) + int(mod["every_n_add"]))
			if str(out["type"]) == "charges":
				if mod.has("charges_max_add"):
					out["max"] = maxf(1.0, float(out["max"]) + float(mod["charges_max_add"]))
				if mod.has("charges_reset_to"):
					out["reset_to"] = int(mod["charges_reset_to"])
			out["actions"] = _mod_actions(out.get("actions", []), mod)
			if mod.has("extra_actions"):
				out["actions"] = out["actions"] + (mod["extra_actions"] as Array).duplicate(true)
	return out


## The ultimate block after a cell_mod (actions rewritten, extra_actions appended).
static func cell_mod_ultimate(ult: Dictionary, mod: Dictionary) -> Dictionary:
	var out: Dictionary = ult.duplicate(true)
	out["actions"] = _mod_actions(out.get("actions", []), mod)
	if mod.has("extra_actions"):
		out["actions"] = out["actions"] + (mod["extra_actions"] as Array).duplicate(true)
	return out


static func _mod_actions(actions: Array, mod: Dictionary) -> Array:
	var out: Array = []
	for raw in actions:
		var action: Dictionary = (raw as Dictionary).duplicate(true)
		var kind := str(action.get("action", ""))
		var scale := float(mod.get("scale", 1.0))
		for key in SCALED_ACTION_KEYS:
			if action.get(key) is float or action.get(key) is int:
				action[key] = float(action[key]) * scale
		if kind == "heal" and mod.has("heal_mul"):
			action["fraction"] = float(action["fraction"]) * float(mod["heal_mul"])
			if action.has("cap_max_hp"):
				action["cap_max_hp"] = float(action["cap_max_hp"]) * float(mod["heal_mul"])
		if kind == "shield" and mod.has("shield_mul"):
			action["fraction"] = float(action["fraction"]) * float(mod["shield_mul"])
		if kind == "burst" and mod.has("atk_mul"):
			action["atk_mul"] = float(action["atk_mul"]) * float(mod["atk_mul"])
		if kind == "burst" and mod.has("fury_add") and action.has("fury") and action["fury"] != false:
			var base := float(action["fury"]) if (action["fury"] is float or action["fury"] is int) else float(RaceData.load_default().rules.get("fury_factor", 1.5))
			action["fury"] = base + float(mod["fury_add"])
		if kind == "skill_refresh" and mod.has("refresh_add"):
			if action.has("fraction"):
				action["fraction"] = minf(1.0, float(action["fraction"]) + float(mod["refresh_add"]))
			if action.has("seconds"):
				action["seconds"] = float(action["seconds"]) + float(mod["refresh_add"])
		if mod.has("radius_mul") and action.has("radius"):
			action["radius"] = float(action["radius"]) * float(mod["radius_mul"])
		if mod.has("duration_mul") and kind == "zone" and action.has("duration_ticks"):  # Runic Ultimate: its zones last longer
			action["duration_ticks"] = int(round(float(action["duration_ticks"]) * float(mod["duration_mul"])))
		for key in ["pulse", "on_end", "on_hit", "on_kill"]:
			if action.get(key) is Array:
				action[key] = _mod_actions(action[key], mod)
		out.append(action)
	return out


# ---------------------------------------------------------------- signature_mod

static func signature_mod_effect(effect: Dictionary, mod: Dictionary) -> Dictionary:
	var out: Dictionary = effect.duplicate(true)
	match str(out["type"]):
		"aggro":
			out["every_ticks"] = float(out["every_ticks"]) * float(mod.get("every_mul", 1.0))
			out["radius"] = float(out["radius"]) + float(mod.get("radius_add", 0.0))
			out["duration_ticks"] = float(out["duration_ticks"]) + float(mod.get("duration_add", 0.0))
		"cleave":
			out["per_extra"] = float(out["per_extra"]) + float(mod.get("per_target_add", 0.0))
			out["max_bonus"] = float(out["max_bonus"]) + float(mod.get("max_add", 0.0))
		"trigger":
			if mod.has("mark_duration_add"):
				for action in out.get("actions", []):
					if str(action.get("action", "")) == "apply_status":
						action["duration"] = int(action.get("duration", status_duration(str(action["status"])))) + int(mod["mark_duration_add"])
			if mod.has("extra_actions"):
				out["actions"] = out["actions"] + (mod["extra_actions"] as Array).duplicate(true)
	return out


static func status_duration(status: String) -> int:
	if _status_durations.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EFFECTS_FILE))
		for id in (parsed.get("effects", {}) if parsed is Dictionary else {}):
			if parsed["effects"][id] is Dictionary:
				_status_durations[id] = int(parsed["effects"][id].get("duration", 0))
	return int(_status_durations.get(status, 0))


# ---------------------------------------------------------------- hooks the race engine calls

static func tree_of(fighter) -> Dictionary:
	return fighter.race_state.get("tree", {})


## gauge_mod on one tick's gauge parts (formula 4.7 x GDD 4.7 node terms), in place. Also applies `start` once.
static func gauge_parts(fighter, parts: Dictionary, kills: int) -> void:
	var g: Dictionary = tree_of(fighter).get("gauge", {})
	if g.is_empty():
		return
	if bool(tree_of(fighter).get("start_pending", false)):
		tree_of(fighter)["start_pending"] = false
		fighter.gauge = maxf(fighter.gauge, float(g["start"]))
	var charge := float(g.get("charge_mul", 1.0))
	if fighter.hp < fighter.max_hp() * float(g.get("below", 0.0)):
		charge *= float(g.get("low_hp_mul", 1.0))
	for key in ["time", "dealt", "taken", "support"]:
		parts[key] = float(parts.get(key, 0.0)) * charge
	parts["support"] = float(parts["support"]) * float(g.get("support_mul", 1.0))
	parts["kill"] = float(parts.get("kill", 0.0)) + float(g.get("kill_add", 0.0)) * float(kills)


## The gauge the ultimate needs now (Berserkergang fire_at below fire_below_hp), else `top`.
static func fire_threshold(fighter, top: float) -> float:
	var g: Dictionary = tree_of(fighter).get("gauge", {})
	if g.has("fire_at") and fighter.hp < fighter.max_hp() * float(g.get("fire_below_hp", 0.0)):
		return minf(top, float(g["fire_at"]))
	return top


## Gauge left after an ultimate cast (Mastery Overflow after_cast), else 0.
static func gauge_after_cast(fighter) -> float:
	return float(tree_of(fighter).get("gauge", {}).get("after_cast", 0.0))


## Gauge a rune discharge gives (Stored Power discharge_add).
static func discharge_gauge(fighter) -> float:
	return float(tree_of(fighter).get("gauge", {}).get("discharge_add", 0.0))


## skill_upgrade on a cast's stats (GDD 3.6: base -> node mods, before the race skill_mod), in place. The build_calc
## order: every ADD, then every MUL, then every SET. A node status joins the skill's statuses; "remote" casts at target.
static func upgrade_skill(fighter, stats: Dictionary) -> void:
	var upgrades: Array = tree_of(fighter).get("skills", {}).get(str(stats.get("skill_id", "")), [])
	if upgrades.is_empty():
		return
	for op in [0, 1, 2]:
		for upgrade in upgrades:
			for mod in upgrade.get("mods", []):
				if int(mod["op"]) != op:
					continue
				var stat := str(mod["stat"])
				match op:
					0: stats[stat] = float(stats.get(stat, 0.0)) + float(mod["value"])
					1: stats[stat] = float(stats.get(stat, 0.0)) * float(mod["value"])
					2: stats[stat] = float(mod["value"])
	for upgrade in upgrades:
		if upgrade.has("status"):
			var statuses: Array = stats.get("statuses", [])
			if not statuses.has(str(upgrade["status"])):
				statuses.append(str(upgrade["status"]))
			stats["statuses"] = statuses
		if str(upgrade.get("behavior", "")) == "remote":
			stats["origin"] = "target"


## Trigger filters (GDD 3.5): skill, min_targets, target_has, self_below_hp. True when the trigger may fire.
static func filter_ok(sim, id: int, effect: Dictionary, context: Dictionary) -> bool:
	var fighter = sim.fighters[id]
	if effect.has("skill"):
		var skill := str(context.get("skill", str(context.get("move", "")).trim_prefix("skill:")))
		if skill != str(effect["skill"]):
			return false
	if effect.has("self_below_hp") and fighter.hp >= fighter.max_hp() * float(effect["self_below_hp"]):
		return false
	if effect.has("target_has"):
		var target = sim.fighters.get(int(context.get("target", -1)))
		if target == null or not target.effects.has(str(effect["target_has"])):
			return false
	if effect.has("min_targets"):
		var move := str(context.get("move", ""))
		var hit := {}
		for event in sim.events:
			if str(event.get("type", "")) in ["hit", "skill_hit"] and int(event.get("attacker", -1)) == id and str(event.get("move", "")) == move:
				hit[int(event.get("target", -1))] = true
		if hit.size() < int(effect["min_targets"]):
			return false
	return true


## True when a min_targets trigger already fired this tick (one swing that hit N enemies fires once, not N times).
static func once_per_tick(sim, effect: Dictionary, fx: Dictionary) -> bool:
	if not effect.has("min_targets"):
		return false
	if int(fx.get("tick", -1)) == sim.tick_count:
		return true
	fx["tick"] = sim.tick_count
	return false


## The node-only targets (GDD 3.5): allies_in_radius {radius}. [] for any other kind.
static func targets(sim, id: int, kind: String, action: Dictionary) -> Array:
	if kind != "allies_in_radius":
		return []
	var me = sim.fighters[id]
	var at: Vector3 = sim.bodies[id].position
	var out: Array = []
	for other in sim.fighters:
		var f = sim.fighters[other]
		var pos: Vector3 = sim.bodies[other].position
		if f.team == me.team and f.is_alive() and Vector2(pos.x - at.x, pos.z - at.z).length() <= float(action.get("radius", 0.0)):
			out.append(other)
	out.sort()
	return out


## The node actions (GDD 3.5): pull, cleanse, skill_status. Returns true when it did something.
static func run_action(sim, id: int, action: Dictionary, context: Dictionary) -> bool:
	match str(action["action"]):
		"pull":
			return pull(sim, id, float(action["radius"]), float(action["distance"]))
		"cleanse":
			var did := false
			for target_id in load("res://logic/race_passives.gd").targets(sim, id, str(action.get("target", "self")), context, action):
				var target = sim.fighters[target_id]
				for status in action.get("statuses", []):
					if target.effects.has(str(status)):
						target.effects.erase(str(status))
						did = true
				if did:
					Effects.refresh(target, sim.combat)
					sim.events.append({"type": "tree_cleanse", "player": id, "target": target_id})
			return did
		"skill_status":
			var system = sim.skill_system
			if system == null:
				return false
			var target_id := int(context.get("target", -1))
			if not system.targets.has(target_id) or not sim.fighters.has(target_id) or not sim.fighters[target_id].is_alive():
				return false
			for _i in maxi(1, int(action.get("stacks", 1))):
				system.targets[target_id].apply_status(str(action["status"]), {"owner_id": id})
			return true
	return false


## pull {radius, distance}: every living enemy within `radius` m moves `distance` m toward fighter `id` (never past it).
static func pull(sim, id: int, radius: float, distance: float) -> bool:
	var me: Vector3 = sim.bodies[id].position
	var ids: Array = sim.fighters.keys()
	ids.sort()
	var moved: Array = []
	for other in ids:
		var f = sim.fighters[other]
		if f.team == sim.fighters[id].team or not f.is_alive():
			continue
		var pos: Vector3 = sim.bodies[other].position
		var flat := Vector2(me.x - pos.x, me.z - pos.z)
		var length := flat.length()
		if length > radius or length < 0.01:
			continue
		var step := minf(distance, maxf(0.0, length - 0.8)) / length
		sim.bodies[other].position = Vector3(pos.x + flat.x * step, pos.y, pos.z + flat.y * step)
		moved.append(other)
	if moved.is_empty():
		return false
	sim.events.append({"type": "tree_pull", "player": id, "enemies": moved, "radius": radius})
	return true


# ---------------------------------------------------------------- read-only views

## The learned node ids in this fight.
static func nodes(fighter) -> Array:
	return tree_of(fighter).get("nodes", [])


## Pilot changes (GDD 6.4) the auto-pilot may read: kite_drop_skill, cast_center, kite_distance, hold_min_targets_add.
static func pilot_mods(fighter) -> Dictionary:
	return tree_of(fighter).get("pilot", {})


## Learned mechanic ids -> params (GDD 3.5 `mechanic`). Not run by the engine yet.
static func mechanics(fighter) -> Dictionary:
	return tree_of(fighter).get("mechanics", {})


## CONTROL_IMMUNE (Immovable): the card ignores stuns, knockback and stagger.
static func control_immune(fighter) -> bool:
	return float(fighter.race_state.get("pseudo", {}).get("CONTROL_IMMUNE", {}).get("add", 0.0)) > 0.0
