extends RefCounted
## Race gear sets (design/gdd/race-gear-sets.md 3.5-3.8, 4.1-4.2; Boss 2026-11-13). Pure rules, no randomness.
## A race set (data/items/sets.json kind "race") is 5 pieces: the race weapon of the class + shirt, pants, armband, shoes.
## Any card may wear any piece (its stats always count). The set OPTION works only when the card's race equals the set's
## race: steps at 2 / 4 / 5 worn pieces add cell_mod words to the race passive. A step's numbers are scaled by tier_mul of
## the LOWEST tier among the N best pieces worn (N = the step's pieces; formula 4.1), as formula 4.2 says:
##   scale_add x m; a *_mul field f -> 1 + (f - 1) x m; hp_threshold_add x m; inside extra_actions / extra_effects the
##   fractions, seconds, atk_mul, max_mul, crit_add, cap_max_hp and durations x m. Integer fields (charges_max_add,
##   every_n_add, charges_reset_to, every_n, cooldown_ticks) and thresholds (hp_below, below) are not scaled.
## The option is derived from (worn items, card race, card class) every time: changing race or gear turns it on/off at
## once; logic/race_passives.gd attach() snapshots it at run start. Caps with the skill tree: logic/skill_tree_effects.gd
## combine_passive_mods.

const MUL_FIELDS: Array[String] = ["icd_mul", "duration_mul", "heal_mul", "shield_mul", "atk_mul", "radius_mul"]
const ACTION_KEYS: Array[String] = ["fraction", "seconds", "atk_mul", "cap_max_hp"]


## Every race set the worn `items` touch, matched or not, for the UI and the engine:
## [{"set_id", "name", "race", "count", "total", "matched", "steps": [{"pieces", "name", "active", "tier", "m", "text", "effects"}]}]
## `rules`: ItemRules (catalog + tiers). Sorted by set id.
static func status(rules, items: Array, race: String, class_id: String) -> Array:
	var by_set := {}
	for item in items:
		if item == null:
			continue
		var set_id: String = rules.catalog.entry(item.item_id).get("set", "")
		var info: Dictionary = rules.catalog.sets.get(set_id, {})
		if str(info.get("kind", "")) != "race":
			continue
		if not by_set.has(set_id):
			by_set[set_id] = []
		by_set[set_id].append(int(item.tier))
	var out: Array = []
	var ids: Array = by_set.keys()
	ids.sort()
	for set_id in ids:
		var info: Dictionary = rules.catalog.sets[set_id]
		var tiers: Array = by_set[set_id]
		tiers.sort()
		tiers.reverse()  # best first
		var matched := str(info["race"]) == race
		var steps: Array = []
		for step in info.get("steps", []):
			var pieces := int(step.get("pieces", 0))
			var tier: int = int(tiers[mini(pieces, tiers.size()) - 1]) if not tiers.is_empty() and pieces > 0 else 0
			var tier_id := str(rules.tiers[clampi(tier, 0, rules.tiers.size() - 1)]["id"])
			var block := step_block(step, class_id)
			steps.append({"pieces": pieces, "name": str(step.get("name", "")), "active": matched and tiers.size() >= pieces, "tier": tier_id,
				"m": float(info.get("tier_mul", {}).get(tier_id, 1.0)), "text": str(block.get("text", "")), "effects": block.get("effects", [])})
		out.append({"set_id": set_id, "name": str(info.get("name", set_id)), "race": str(info["race"]), "count": tiers.size(),
			"total": total_pieces(rules.catalog, set_id), "matched": matched, "steps": steps})
	return out


## The step's effects for `class_id`: {"text", "effects"} from "all", else by_class[class], else by_class.default_class, else {}.
static func step_block(step: Dictionary, class_id: String) -> Dictionary:
	if step.get("all") is Dictionary:
		return step["all"]
	var by_class: Dictionary = step.get("by_class", {})
	return by_class.get(class_id, by_class.get("default_class", {}))


## How many pieces the set has for one class: the highest step's pieces (5).
static func total_pieces(catalog, set_id: String) -> int:
	var most := 0
	for step in catalog.sets.get(set_id, {}).get("steps", []):
		most = maxi(most, int(step.get("pieces", 0)))
	return most


## The scaled cell_mod effects of every ACTIVE step (matched race only), in set then step order.
static func active_mods(rules, items: Array, race: String, class_id: String) -> Array:
	var mods: Array = []
	for entry in status(rules, items, race, class_id):
		for step in entry["steps"]:
			if not step["active"]:
				continue
			for effect in step["effects"]:
				if str(effect.get("type", "")) == "cell_mod":
					mods.append(scale_mod(effect, float(step["m"])))
	return mods


## Formula 4.2 on one cell_mod: the bonus part of every number x m.
static func scale_mod(mod: Dictionary, m: float) -> Dictionary:
	var out: Dictionary = mod.duplicate(true)
	if out.has("scale_add"):
		out["scale_add"] = float(out["scale_add"]) * m
	if out.has("hp_threshold_add"):
		out["hp_threshold_add"] = float(out["hp_threshold_add"]) * m
	for key in MUL_FIELDS:
		if out.has(key):
			out[key] = 1.0 + (float(out[key]) - 1.0) * m
	if out.has("extra_actions"):
		out["extra_actions"] = scale_actions(out["extra_actions"], m)
	if out.has("extra_effects"):
		var effects: Array = []
		for effect in out["extra_effects"]:
			effects.append(scale_effect(effect, m))
		out["extra_effects"] = effects
	return out


static func scale_actions(actions: Array, m: float) -> Array:
	var out: Array = []
	for raw in actions:
		var action: Dictionary = (raw as Dictionary).duplicate(true)
		for key in ACTION_KEYS:
			if action.get(key) is float or action.get(key) is int:
				action[key] = float(action[key]) * m
		if action.has("duration"):
			action["duration"] = int(round(float(action["duration"]) * m))
		out.append(action)
	return out


static func scale_effect(effect: Dictionary, m: float) -> Dictionary:
	var out: Dictionary = effect.duplicate(true)
	match str(out.get("type", "")):
		"skill_mod":
			for key in ["damage_mul", "cooldown_mul", "radius_mul"]:
				if out.has(key):
					out[key] = 1.0 + (float(out[key]) - 1.0) * m
			if out.has("crit_add"):
				out["crit_add"] = float(out["crit_add"]) * m
		"low_hp_scaling":
			out["max_mul"] = float(out["max_mul"]) * m
		"stat_mod":
			for key in ["add", "mul"]:
				if out.has(key):
					out[key] = float(out[key]) * m
	if out.get("actions") is Array:
		out["actions"] = scale_actions(out["actions"], m)
	return out
