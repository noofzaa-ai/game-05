extends RefCounted
## Reads and validates data/camp/camp.json. A mistake never crashes the game: the data comes back
## with `errors` filled in. `tier_count` (the number of equipment tiers, from the item rules) lets it
## check the repair price table; 0 skips that check.

const CampData := preload("res://logic/camp_data.gd")

const DATA_PATH := "res://data/camp/camp.json"
const SUPPORTED_VERSION := 1
const EFFECT_KEYS: Array[String] = ["stash_slots", "bag_slots", "repair_discount"]


static func load_default(tier_count: int = 0) -> CampData:
	if not FileAccess.file_exists(DATA_PATH):
		var missing := CampData.new()
		missing.errors.append("camp file not found: %s" % DATA_PATH)
		return missing
	return parse(FileAccess.get_file_as_string(DATA_PATH), tier_count)


static func parse(text: String, tier_count: int = 0) -> CampData:
	var data := CampData.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		data.errors.append("invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return data
	if typeof(json.data) != TYPE_DICTIONARY:
		data.errors.append("top level must be an object")
		return data
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		data.errors.append("unsupported version (expected %d)" % SUPPORTED_VERSION)
	_parse_materials(root, data)
	var bag := _dict(root, "bag", data)
	data.bank_slots = int(bag.get("bank_slots", 20))
	if data.bank_slots < 1 or data.bank_slots > 1000: data.errors.append("bag.bank_slots must be 1..1000")
	data.run_slots = int(bag.get("run_slots", 0))
	data.stash_slots = int(bag.get("stash_slots", 0))
	if data.run_slots < 1 or data.stash_slots < 1:
		data.errors.append("bag.run_slots and bag.stash_slots must be at least 1")
	data.rest_heal_fraction = float(_dict(root, "rest", data).get("heal_fraction", -1.0))
	if data.rest_heal_fraction < 0.0 or data.rest_heal_fraction > 1.0:
		data.errors.append("rest.heal_fraction must be between 0 and 1")
	_parse_repair(root, data, tier_count)
	_parse_camp_levels(root, data)
	_parse_facilities(root, data)
	_parse_skills(root, data)
	var starter := _dict(root, "starter", data)
	data.starter = _cost(starter, "starter", data)
	_parse_progression(root, data)
	return data


static func _dict(parent: Dictionary, key: String, data: CampData) -> Dictionary:
	if typeof(parent.get(key)) != TYPE_DICTIONARY:
		data.errors.append("%s must be an object" % key)
		return {}
	return parent[key]


static func _list(parent: Dictionary, key: String, data: CampData) -> Array:
	if typeof(parent.get(key)) != TYPE_ARRAY:
		data.errors.append("%s must be a list" % key)
		return []
	return parent[key]


## {"gold": int, "materials": {id: int}}; every material must exist.
static func _cost(raw: Dictionary, label: String, data: CampData) -> Dictionary:
	var gold := int(raw.get("gold", 0))
	if gold < 0:
		data.errors.append("%s.gold must not be negative" % label)
	var materials := {}
	var raw_materials: Dictionary = raw.get("materials", {}) if typeof(raw.get("materials")) == TYPE_DICTIONARY else {}
	for id in raw_materials:
		if not data.materials.has(str(id)):
			data.errors.append("%s.materials.%s is not a known material" % [label, id])
		elif int(raw_materials[id]) < 1:
			data.errors.append("%s.materials.%s must be at least 1" % [label, id])
		else:
			materials[str(id)] = int(raw_materials[id])
	return {"gold": gold, "materials": materials}


static func _parse_materials(root: Dictionary, data: CampData) -> void:
	var materials := _dict(root, "materials", data)
	for id in materials:
		var label := "materials.%s" % id
		if typeof(materials[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var stack := int(materials[id].get("stack", 0))
		if stack < 1:
			data.errors.append("%s.stack must be at least 1" % label)
		var color: Variant = materials[id].get("color", [1.0, 1.0, 1.0])
		if typeof(color) != TYPE_ARRAY or color.size() != 3:
			data.errors.append("%s.color must be [r, g, b]" % label)
			color = [1.0, 1.0, 1.0]
		data.materials[str(id)] = {"name": str(materials[id].get("name", id)), "stack": stack, "color": Color(float(color[0]), float(color[1]), float(color[2]))}
	if data.materials.is_empty():
		data.errors.append("materials must list at least one material")


static func _parse_repair(root: Dictionary, data: CampData, tier_count: int) -> void:
	var repair := _dict(root, "repair", data)
	data.repair = {"facility": str(repair.get("facility", ""))}
	for kind in ["normal", "broken"]:
		var entry: Dictionary = repair.get(kind, {}) if typeof(repair.get(kind)) == TYPE_DICTIONARY else {}
		var gold := float(entry.get("gold_per_point", -1.0))
		if gold < 0.0:
			data.errors.append("repair.%s.gold_per_point must be 0 or more" % kind)
		var per_point := {}
		var raw: Dictionary = entry.get("materials_per_point", {}) if typeof(entry.get("materials_per_point")) == TYPE_DICTIONARY else {}
		for id in raw:
			if not data.materials.has(str(id)) or float(raw[id]) < 0.0:
				data.errors.append("repair.%s.materials_per_point.%s must be a known material with a number, 0 or more" % [kind, id])
			else:
				per_point[str(id)] = float(raw[id])
		data.repair[kind] = {"gold_per_point": gold, "materials_per_point": per_point}
	var multipliers: Array[float] = []
	for value in _list(repair, "tier_multiplier", data):
		multipliers.append(float(value))
	if multipliers.is_empty() or (tier_count > 0 and multipliers.size() != tier_count):
		data.errors.append("repair.tier_multiplier needs one number per equipment tier (%d)" % tier_count)
	data.repair["tier_multiplier"] = multipliers


static func _parse_camp_levels(root: Dictionary, data: CampData) -> void:
	var expected := 2
	for entry in _list(root, "camp_levels", data):
		if typeof(entry) != TYPE_DICTIONARY or int(entry.get("level", 0)) != expected:
			data.errors.append("camp_levels must list levels 2, 3, 4... in order (expected %d)" % expected)
			expected += 1
			continue
		data.camp_levels.append({"level": expected, "cost": _cost(_as_dict(entry.get("cost")), "camp_levels[level %d].cost" % expected, data)})
		expected += 1


static func _parse_facilities(root: Dictionary, data: CampData) -> void:
	var facilities := _dict(root, "facilities", data)
	for id in facilities:
		var label := "facilities.%s" % id
		if typeof(facilities[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var levels: Array[Dictionary] = []
		var previous := 1
		var index := 0
		for raw in _list(facilities[id], "levels", data):
			var level_label := "%s.levels[%d]" % [label, index]
			index += 1
			if typeof(raw) != TYPE_DICTIONARY:
				data.errors.append("%s must be an object" % level_label)
				continue
			var camp_level := int(raw.get("camp_level", 0))
			if camp_level < previous or camp_level > data.max_camp_level():
				data.errors.append("%s.camp_level must not go down and must be a camp level that exists (1-%d)" % [level_label, data.max_camp_level()])
			previous = maxi(previous, camp_level)
			var effects := {}
			var raw_effects: Dictionary = raw.get("effects", {}) if typeof(raw.get("effects")) == TYPE_DICTIONARY else {}
			for key in raw_effects:
				if not EFFECT_KEYS.has(str(key)):
					data.errors.append("%s.effects.%s is not a known effect" % [level_label, key])
				else:
					effects[str(key)] = float(raw_effects[key])
			if float(effects.get("repair_discount", 0.0)) < 0.0 or float(effects.get("repair_discount", 0.0)) > 0.9:
				data.errors.append("%s.effects.repair_discount must be between 0 and 0.9" % level_label)
			levels.append({"camp_level": camp_level, "cost": _cost(_as_dict(raw.get("cost")), level_label + ".cost", data), "effects": effects})
		if levels.is_empty():
			data.errors.append("%s must have at least one level" % label)
		data.facilities[str(id)] = {"name": str(facilities[id].get("name", id)), "function": str(facilities[id].get("function", "")), "levels": levels}
	if not data.facilities.has(str(data.repair.get("facility", ""))):
		data.errors.append("repair.facility must name a facility")
	var start := _dict(root, "start_levels", data)
	for id in start:
		if not data.facilities.has(str(id)) or int(start[id]) < 0 or int(start[id]) > data.facilities[str(id)]["levels"].size():
			data.errors.append("start_levels.%s must be a facility and a level it has" % id)
			continue
		var built := int(start[id])
		if built >= 1 and int(data.facilities[str(id)]["levels"][built - 1]["camp_level"]) > 1:
			data.errors.append("start_levels.%s: a new player cannot start with a facility level that needs a higher camp level" % id)
		data.start_levels[str(id)] = built
	for id in data.facilities:
		if not data.start_levels.has(id):
			data.start_levels[id] = 0


static func _parse_skills(root: Dictionary, data: CampData) -> void:
	var seen: Array[String] = []
	for raw in _list(root, "skills", data):
		if typeof(raw) != TYPE_DICTIONARY:
			data.errors.append("skills entries must be objects")
			continue
		var id := str(raw.get("id", ""))
		if id.is_empty() or seen.has(id):
			data.errors.append("every skill needs a unique id")
		seen.append(id)
		var camp_level := int(raw.get("camp_level", 0))
		if camp_level < 1 or camp_level > data.max_camp_level():
			data.errors.append("skills.%s.camp_level must be a camp level that exists" % id)
		var stats := {}
		var raw_stats: Dictionary = raw.get("stats", {}) if typeof(raw.get("stats")) == TYPE_DICTIONARY else {}
		if raw_stats.is_empty():
			data.errors.append("skills.%s must give at least one stat" % id)
		for stat in raw_stats:
			stats[str(stat)] = float(raw_stats[stat])
		data.skills.append({"id": id, "name": str(raw.get("name", id)), "camp_level": camp_level, "summary": str(raw.get("summary", "")), "stats": stats})


static func _as_dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _parse_progression(root: Dictionary, data: CampData) -> void:
	var cap := int(root.get("progression_max_level", 0))
	if cap < 0 or cap > 1 + data.camp_levels.size():
		data.errors.append("progression_max_level must be0 or an existing camp level")
	else: data.progression_max_level = cap
	var required: Variant = root.get("progression_facilities", [])
	if not required is Array:
		data.errors.append("progression_facilities must be an array")
		return
	for value in required:
		var id := str(value)
		if not data.facilities.has(id) or data.progression_facilities.has(id):
			data.errors.append("progression_facilities must name unique known facilities")
			continue
		if data.facilities[id]["levels"].size() < data.max_camp_level():
			data.errors.append("progression_facilities.%s needs one level per camp level" % id)
		if int(data.start_levels.get(id, 0)) != 1:
			data.errors.append("progression_facilities.%s must start at level1" % id)
		for index in data.facilities[id]["levels"].size():
			if int(data.facilities[id]["levels"][index]["camp_level"]) > index + 1:
				data.errors.append("progression_facilities.%s cannot require a later camp level than its own level" % id)
		data.progression_facilities.append(id)
