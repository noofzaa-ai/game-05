extends RefCounted
## Reads and validates data/items/rules.json. A mistake never crashes the game: the rules come back
## with `errors` filled in (and the game can refuse to start a farm run with broken rules).

const ItemRules := preload("res://logic/item_rules.gd")

const RULES_PATH := "res://data/items/rules.json"
const SUPPORTED_VERSION := 1
const PROBABILITY_TOLERANCE := 0.001


static func load_default() -> ItemRules:
	if not FileAccess.file_exists(RULES_PATH):
		var missing := ItemRules.new()
		missing.errors.append("rules file not found: %s" % RULES_PATH)
		return missing
	var rules := parse(FileAccess.get_file_as_string(RULES_PATH))
	# Backend mounts this public balance file; web uses defaults until authoritative sync.
	var tuning_path := OS.get_environment("ZORX_EQUIPMENT_CONFIG")
	if tuning_path.is_empty(): tuning_path = "res://data/items/equipment_tuning.json"
	if not apply_tuning(JSON.parse_string(FileAccess.get_file_as_string(tuning_path)), rules):
		rules.errors.append("invalid equipment tuning: " + tuning_path)
	var slot_ids: Array = rules.slots.map(func(slot): return slot["id"])
	rules.catalog = ItemRules.ItemCatalog.load_default(slot_ids, rules.stat_ids)
	for error in rules.catalog.errors:
		rules.errors.append("catalog: " + error)
	return rules


static func parse(text: String) -> ItemRules:
	var rules := ItemRules.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		rules.errors.append("invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return rules
	if typeof(json.data) != TYPE_DICTIONARY:
		rules.errors.append("top level must be an object")
		return rules
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		rules.errors.append("unsupported version (expected %d)" % SUPPORTED_VERSION)

	_parse_stats(root, rules)
	_parse_tiers(root, rules)
	_parse_slots(root, rules)
	_parse_main_stats(root, rules)
	_parse_substats(root, rules)
	_parse_enhancement(root, rules)
	_parse_durability(root, rules)
	_parse_refine(root, rules)
	return rules


static func _dict(parent: Dictionary, key: String, rules: ItemRules) -> Dictionary:
	if typeof(parent.get(key)) != TYPE_DICTIONARY:
		rules.errors.append("%s must be an object" % key)
		return {}
	return parent[key]


static func _list(parent: Dictionary, key: String, rules: ItemRules) -> Array:
	if typeof(parent.get(key)) != TYPE_ARRAY:
		rules.errors.append("%s must be a list" % key)
		return []
	return parent[key]


static func _parse_stats(root: Dictionary, rules: ItemRules) -> void:
	var stats := _dict(root, "stats", rules)
	for stat in stats:
		var entry: Variant = stats[stat]
		if typeof(entry) != TYPE_DICTIONARY:
			rules.errors.append("stats.%s must be an object" % stat)
			continue
		rules.stat_ids.append(str(stat))
		rules.stat_base[str(stat)] = float(entry.get("base", 0.0))
		rules.stat_unit[str(stat)] = str(entry.get("unit", "flat"))
	if rules.stat_ids.is_empty():
		rules.errors.append("stats must list at least one stat")


static func _parse_tiers(root: Dictionary, rules: ItemRules) -> void:
	var seen: Array[String] = []
	var index := 0
	for tier in _list(root, "tiers", rules):
		var label := "tiers[%d]" % index
		index += 1
		if typeof(tier) != TYPE_DICTIONARY:
			rules.errors.append("%s must be an object" % label)
			continue
		var id := str(tier.get("id", ""))
		if id.is_empty() or seen.has(id):
			rules.errors.append("%s needs a unique id" % label)
		seen.append(id)
		var count := int(tier.get("substat_count", -1))
		if count < 0:
			rules.errors.append("%s.substat_count must be 0 or more" % label)
		rules.tiers.append({"id": id, "color": str(tier.get("color", "")), "substat_count": count})
	if rules.tiers.is_empty():
		rules.errors.append("tiers must list at least one tier")


static func _parse_slots(root: Dictionary, rules: ItemRules) -> void:
	var seen: Array[String] = []
	var index := 0
	for slot in _list(root, "slots", rules):
		var label := "slots[%d]" % index
		index += 1
		if typeof(slot) != TYPE_DICTIONARY:
			rules.errors.append("%s must be an object" % label)
			continue
		var id := str(slot.get("id", ""))
		if id.is_empty() or seen.has(id):
			rules.errors.append("%s needs a unique id" % label)
		seen.append(id)
		var count := int(slot.get("count", 0))
		if count < 1:
			rules.errors.append("%s.count must be at least 1" % label)
		var main_stat := str(slot.get("main_stat", ""))
		if not rules.stat_ids.has(main_stat):
			rules.errors.append("%s.main_stat '%s' is not a known stat" % [label, main_stat])
		var classes: Array[String] = []
		if slot.has("classes"):
			if not slot["classes"] is Array or slot["classes"].is_empty():
				rules.errors.append("%s.classes must be a non-empty list of class ids" % label)
			else:
				for class_id in slot["classes"]:
					classes.append(str(class_id))
		rules.slots.append({"id": id, "count": count, "main_stat": main_stat, "classes": classes})
	if rules.slots.is_empty():
		rules.errors.append("slots must list at least one slot")


static func _parse_main_stats(root: Dictionary, rules: ItemRules) -> void:
	var table := _dict(root, "main_stat_by_tier", rules)
	for stat in rules.stat_ids:
		var values: Variant = table.get(stat)
		if typeof(values) != TYPE_ARRAY or values.size() != rules.tiers.size():
			rules.errors.append("main_stat_by_tier.%s needs one number per tier (%d)" % [stat, rules.tiers.size()])
			continue
		var numbers: Array[float] = []
		for value in values:
			numbers.append(float(value))
		rules.main_by_tier[stat] = numbers


static func _parse_substats(root: Dictionary, rules: ItemRules) -> void:
	var sub := _dict(root, "substat", rules)
	var ranges: Dictionary = sub.get("range", {}) if typeof(sub.get("range")) == TYPE_DICTIONARY else {}
	for stat in rules.stat_ids:
		var pair: Variant = ranges.get(stat)
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or float(pair[0]) > float(pair[1]):
			rules.errors.append("substat.range.%s must be [min, max] with min <= max" % stat)
			continue
		rules.substat_range[stat] = Vector2(float(pair[0]), float(pair[1]))
	var multipliers: Variant = sub.get("tier_multiplier")
	if typeof(multipliers) != TYPE_ARRAY or multipliers.size() != rules.tiers.size():
		rules.errors.append("substat.tier_multiplier needs one number per tier (%d)" % rules.tiers.size())
	else:
		for value in multipliers:
			rules.tier_multiplier.append(float(value))
	rules.substat_boost_step = float(sub.get("boost_step", 0.0))


static func _parse_durability(root: Dictionary, rules: ItemRules) -> void:
	var durability := _dict(root, "durability", rules)
	rules.durability_max = float(durability.get("max", 0.0))
	rules.durability_full_above = float(durability.get("full_stats_above", -1.0))
	rules.durability_broken_factor = float(durability.get("broken_factor", -1.0))
	rules.armor_wear_per_full_hp = float(durability.get("armor_wear_per_full_hp", -1.0))
	rules.weapon_wear_per_hit = float(durability.get("weapon_wear_per_hit", -1.0))
	rules.death_wear = float(durability.get("death_wear", -1.0))
	if rules.durability_max <= 0.0:
		rules.errors.append("durability.max must be above 0")
	if rules.durability_full_above <= 0.0 or rules.durability_full_above > 1.0:
		rules.errors.append("durability.full_stats_above must be above 0 and at most 1")
	if rules.durability_broken_factor < 0.0 or rules.durability_broken_factor > 1.0:
		rules.errors.append("durability.broken_factor must be between 0 and 1")
	if rules.armor_wear_per_full_hp < 0.0 or rules.weapon_wear_per_hit < 0.0 or rules.death_wear < 0.0:
		rules.errors.append("durability wear numbers must be 0 or more")


static func _parse_enhancement(root: Dictionary, rules: ItemRules) -> void:
	var enhancement := _dict(root, "enhancement", rules)
	rules.max_level = int(enhancement.get("max_level", 0))
	rules.main_bonus_per_level = float(enhancement.get("main_stat_bonus_per_level", 0.0))
	if rules.max_level < 1:
		rules.errors.append("enhancement.max_level must be at least 1")

	var index := 0
	for row in _list(enhancement, "table", rules):
		var label := "enhancement.table[%d]" % index
		index += 1
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("levels")) != TYPE_ARRAY or row["levels"].size() != 2:
			rules.errors.append("%s needs \"levels\": [first, last]" % label)
			continue
		var odds := {}
		var total := 0.0
		for outcome in rules.OUTCOMES:
			var probability := float(row.get(outcome, 0.0))
			if probability < 0.0:
				rules.errors.append("%s.%s must not be negative" % [label, outcome])
			odds[outcome] = probability
			total += probability
		if absf(total - 1.0) > PROBABILITY_TOLERANCE:
			rules.errors.append("%s probabilities must add up to 1 (got %.3f)" % [label, total])
		for level in range(int(row["levels"][0]), int(row["levels"][1]) + 1):
			if rules.odds_by_level.has(level):
				rules.errors.append("%s: level %d is covered twice" % [label, level])
			rules.odds_by_level[level] = odds
	for level in range(1, rules.max_level + 1):
		if not rules.odds_by_level.has(level):
			rules.errors.append("enhancement.table does not cover level %d" % level)

	var protection: Dictionary = enhancement.get("protection", {}) if typeof(enhancement.get("protection")) == TYPE_DICTIONARY else {}
	for outcome in protection:
		if not rules.OUTCOMES.has(str(outcome)) or not rules.OUTCOMES.has(str(protection[outcome])):
			rules.errors.append("enhancement.protection entries must map one outcome to another")
			continue
		rules.protection[str(outcome)] = str(protection[outcome])


static func _parse_refine(root: Dictionary, rules: ItemRules) -> void:
	if not root.has("refine"): return
	var config = root["refine"]
	if not config is Dictionary or not config.get("enabled") is bool:
		rules.errors.append("refine needs enabled boolean")
		return
	var cap := int(config.get("max_level", 0))
	var rate := float(config.get("bonus_per_level", -1))
	var cost = config.get("cost", {})
	if cap < 1 or cap > 100 or not is_finite(rate) or rate < 0 or not cost is Dictionary:
		rules.errors.append("invalid refine cap/rate/cost")
		return
	if not cost.get("gold") is int and not cost.get("gold") is float:
		rules.errors.append("refine cost needs gold")
		return
	var gold := float(cost.gold)
	if not is_finite(gold) or gold < 0 or gold != floorf(gold) or gold > 2147483647 or not cost.get("materials") is Dictionary:
		rules.errors.append("invalid refine cost")
		return
	for count in cost.materials.values():
		if not (count is int or count is float) or not is_finite(float(count)) or float(count) < 0 or float(count) != floorf(float(count)) or float(count) > 2147483647:
			rules.errors.append("invalid refine material count")
			return
	if config.has("success_chances") or config.has("failure_floors"):
		var chances = config.get("success_chances")
		var floors = config.get("failure_floors")
		if not chances is Array or not floors is Array or chances.size() != cap or floors.size() != cap:
			rules.errors.append("refine chance/floor tables must match cap")
			return
		for i in cap:
			if not (chances[i] is int or chances[i] is float) or not is_finite(float(chances[i])) or float(chances[i]) < 0 or float(chances[i]) > 1:
				rules.errors.append("invalid refine success chance")
				return
			if not (floors[i] is int or floors[i] is float) or not is_finite(float(floors[i])) or float(floors[i]) != floorf(float(floors[i])) or float(floors[i]) < 0 or float(floors[i]) > i + 1:
				rules.errors.append("invalid refine failure floor")
				return
	elif float(config.get("success_chance", 0)) != 1.0:
		rules.errors.append("legacy refine success_chance must be 1")
		return
	rules.refine = config.duplicate(true)


## Atomic public tuning sync. Only these two equipment systems are configurable here.
static func apply_tuning(value: Variant, rules: ItemRules) -> bool:
	if not value is Dictionary or value.get("version", value.get("v", 0)) != 1: return false
	if not value.get("refine") is Dictionary or not value.get("upgrade") is Dictionary: return false
	var candidate := ItemRules.new()
	_parse_refine(value, candidate)
	if not candidate.errors.is_empty(): return false
	var config: Dictionary = value.upgrade
	if not config.get("enabled") is bool: return false
	if not _bounded_integer(config.get("max_attempts"), 1, 5) or not _bounded_integer(config.get("max_substats"), 4, 4): return false
	var cost = config.get("cost")
	if not cost is Dictionary or not _bounded_integer(cost.get("gold"), 0, 2147483647) or not cost.get("materials") is Dictionary: return false
	for id in cost.materials:
		if not id is String or not _bounded_integer(cost.materials[id], 0, 2147483647): return false
	var increments = config.get("increments")
	if not increments is Dictionary or increments.size() != rules.stat_ids.size(): return false
	for stat in rules.stat_ids:
		var values = increments.get(stat)
		if not values is Array or values.size() != rules.tiers.size(): return false
		for amount in values:
			if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount) <= 0.0 or float(amount) > 1000000.0: return false
	if value.has("mobility") and not _valid_mobility(value.mobility): return false
	if value.has("armor"):
		var armor_config = value.armor
		if not armor_config is Dictionary or not armor_config.get("class_base_multipliers") is Dictionary: return false
		for kind in ["heavy","light","cloth"]:
			if not armor_config.class_base_multipliers.get(kind) is Dictionary: return false
			for stat in ["HP","DEF"]:
				var amount = armor_config.class_base_multipliers[kind].get(stat)
				if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount)<=0 or float(amount)>2: return false
		rules.armor=armor_config.duplicate(true)
	rules.mobility = value.get("mobility", {}).duplicate(true)
	rules.refine = candidate.refine
	rules.upgrade = config.duplicate(true)
	return true


static func _bounded_integer(value: Variant, low: int, high: int) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high


static func _valid_mobility(value: Variant) -> bool:
	if not value is Dictionary or not value.get("enabled") is bool: return false
	for key in ["base_move_multiplier","base_dodge_multiplier"]:
		var number = value.get(key)
		if not (number is float or number is int) or not is_finite(float(number)) or float(number)<=0 or float(number)>1: return false
	for key in ["slot_weights","armor_penalties","set_classes","item_classes","weapon_penalties"]:
		if not value.get(key) is Dictionary: return false
	var total := 0.0
	for slot in value.slot_weights:
		if slot not in ["shirt","pants","shoes","armband"]: return false  # the hat slot is gone (Boss 2026-11-13)
		var amount = value.slot_weights[slot]
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount)<0 or float(amount)>1: return false
		total+=float(amount)
	if absf(total-1.0)>.0001: return false
	for key in ["armor_penalties","weapon_penalties"]:
		for id in value[key]:
			var amount = value[key][id]
			if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount)<0 or float(amount)>=1: return false
	for kind in ["heavy","light","cloth"]:
		if not value.armor_penalties.has(kind): return false
	for key in ["set_classes","item_classes"]:
		for id in value[key]:
			if not value.armor_penalties.has(value[key][id]): return false
	return true
