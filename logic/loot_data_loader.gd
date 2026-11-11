extends RefCounted
## Reads and validates data/loot/loot.json. Mistakes come back as `errors`, never as a crash.
## `material_ids` (from the camp data) and `tier_count` (from the item rules) let it check the
## references; leave them empty / 0 to skip those checks.

const LootData := preload("res://logic/loot_data.gd")

const DATA_PATH := "res://data/loot/loot.json"
const SUPPORTED_VERSION := 1


static func load_default(material_ids: Array = [], tier_count: int = 0) -> LootData:
	if not FileAccess.file_exists(DATA_PATH):
		var missing := LootData.new()
		missing.errors.append("loot file not found: %s" % DATA_PATH)
		return missing
	return parse(FileAccess.get_file_as_string(DATA_PATH), material_ids, tier_count)


static func parse(text: String, material_ids: Array = [], tier_count: int = 0) -> LootData:
	var data := LootData.new()
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
	data.gold_per_level = float(root.get("gold_per_level", -1.0))
	if data.gold_per_level < 0.0:
		data.errors.append("gold_per_level must be 0 or more")

	var last_level := 0
	if typeof(root.get("tier_weights")) != TYPE_ARRAY or root["tier_weights"].is_empty():
		data.errors.append("tier_weights must list at least one bracket")
	else:
		for bracket in root["tier_weights"]:
			var weights: Array = []
			if typeof(bracket) == TYPE_DICTIONARY and typeof(bracket.get("weights")) == TYPE_ARRAY:
				for value in bracket["weights"]:
					weights.append(float(value))
			var level := int(bracket.get("min_level", 0)) if typeof(bracket) == TYPE_DICTIONARY else 0
			var total := 0.0
			for value in weights:
				total += value
			if level <= last_level or weights.is_empty() or total <= 0.0 or (tier_count > 0 and weights.size() != tier_count):
				data.errors.append("tier_weights needs brackets with rising min_level, one positive weight per tier (%d) and a total above 0" % tier_count)
				continue
			last_level = level
			data.tier_weights.append({"min_level": level, "weights": weights})
		if not data.tier_weights.is_empty() and int(data.tier_weights[0]["min_level"]) != 1:
			data.errors.append("the first tier_weights bracket must start at min_level 1")

	var tables: Dictionary = root.get("tables", {}) if typeof(root.get("tables")) == TYPE_DICTIONARY else {}
	if tables.is_empty():
		data.errors.append("tables must list at least one table")
	for id in tables:
		var label := "tables.%s" % id
		if typeof(tables[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var gold := _range(tables[id].get("gold", [0, 0]), label + ".gold", data)
		var drops: Array = []
		for entry in (tables[id].get("drops", []) if typeof(tables[id].get("drops")) == TYPE_ARRAY else []):
			if typeof(entry) != TYPE_DICTIONARY:
				data.errors.append("%s.drops entries must be objects" % label)
				continue
			var chance := float(entry.get("chance", -1.0))
			if chance < 0.0 or chance > 1.0:
				data.errors.append("%s.drops chance must be between 0 and 1" % label)
			var drop := {"chance": chance}
			if entry.has("material"):
				var material := str(entry["material"])
				if not material_ids.is_empty() and not material_ids.has(material):
					data.errors.append("%s.drops names an unknown material '%s'" % [label, material])
				drop["material"] = material
				drop["count"] = _range(entry.get("count", [1, 1]), label + ".drops.count", data)
			elif bool(entry.get("item", false)):
				drop["item"] = true
			else:
				data.errors.append("%s.drops entries need a material or \"item\": true" % label)
			drops.append(drop)
		data.tables[str(id)] = {"gold": gold, "drops": drops}

	var by_enemy: Dictionary = root.get("by_enemy", {}) if typeof(root.get("by_enemy")) == TYPE_DICTIONARY else {}
	for enemy in by_enemy:
		if not data.tables.has(str(by_enemy[enemy])):
			data.errors.append("by_enemy.%s points to an unknown table '%s'" % [enemy, by_enemy[enemy]])
		data.by_enemy[str(enemy)] = str(by_enemy[enemy])
	return data


static func _range(value: Variant, label: String, data: LootData) -> Vector2i:
	if typeof(value) != TYPE_ARRAY or value.size() != 2 or int(value[0]) < 0 or int(value[1]) < int(value[0]):
		data.errors.append("%s must be [min, max] with 0 <= min <= max" % label)
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))
