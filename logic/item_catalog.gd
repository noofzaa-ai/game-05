extends RefCounted
## The game's items made from the model team's assets (data/items/catalog.json) and their set
## bonuses (data/items/sets.json). An item keeps its catalog key in Item.item_id; tier, stats and
## enhancement still come from the rule book. Only data: which model an item shows is the client's
## business (it looks the asset_id up in art/items/item_manifest.json).
## EXTENDING: new assets are added with tools/items/build_catalog.py; set bonuses are edits to sets.json.

const CATALOG_PATH := "res://data/items/catalog.json"
const SETS_PATH := "res://data/items/sets.json"

var items: Dictionary = {}  ## item_id -> {"asset_id", "name", "slot", "weapon_type", "set", "drop_level"}
var sets: Dictionary = {}  ## set id -> {"name", "bonuses": [{"pieces", "stat", "value"}] by pieces, fewest first}
var starter_armor_sets: Array[String] = []
var errors: Array[String] = []


static func load_default(known_slots: Array, known_stats: Array) -> RefCounted:
	var catalog = load("res://logic/item_catalog.gd").new()
	var item_data := _read(CATALOG_PATH, catalog)
	var set_data := _read(SETS_PATH, catalog)
	for id in set_data.get("starter_armor_sets", []):
		catalog.starter_armor_sets.append(str(id))
	catalog.parse(item_data.get("items", {}), set_data.get("sets", {}), known_slots, known_stats)
	return catalog


## Fills the catalog from the files' "items" and "sets" objects, reporting mistakes in `errors`.
func parse(item_data: Dictionary, set_data: Dictionary, known_slots: Array, known_stats: Array) -> void:
	for set_id in set_data:
		var bonuses: Array = []
		for bonus in set_data[set_id].get("bonuses", []):
			if not known_stats.has(str(bonus.get("stat", ""))):
				errors.append("set %s: unknown stat '%s'" % [set_id, bonus.get("stat", "")])
				continue
			bonuses.append({"pieces": int(bonus.get("pieces", 0)), "stat": str(bonus["stat"]), "value": float(bonus.get("value", 0.0))})
		bonuses.sort_custom(func(a, b): return a["pieces"] < b["pieces"])
		sets[set_id] = {"name": str(set_data[set_id].get("name", set_id)), "bonuses": bonuses}
		if str(set_data[set_id].get("kind", "")) == "race":  # a race gear set (design/gdd/race-gear-sets.md 3.10): logic/race_sets.gd reads it
			sets[set_id]["kind"] = "race"
			sets[set_id]["race"] = str(set_data[set_id].get("race", ""))
			sets[set_id]["tier_mul"] = (set_data[set_id].get("tier_mul", {}) as Dictionary).duplicate(true)
			sets[set_id]["steps"] = (set_data[set_id].get("steps", []) as Array).duplicate(true)
	for item_id in item_data:
		var entry: Dictionary = item_data[item_id]
		var slot := str(entry.get("slot", ""))
		if not known_slots.has(slot):
			errors.append("item %s: unknown slot '%s'" % [item_id, slot])
			continue
		var set_id := str(entry.get("set", ""))
		if not set_id.is_empty() and not sets.has(set_id):
			errors.append("item %s: set '%s' is not in sets.json" % [item_id, set_id])
		items[item_id] = {
			"asset_id": str(entry.get("asset_id", "")), "name": str(entry.get("name", item_id)), "slot": slot,
			"armor_class": str(entry.get("armor_class", "")), "main_stat": str(entry.get("main_stat", "")), "asset_path": str(entry.get("asset_path", "")), "icon_path": str(entry.get("icon_path", "")), "source_style": str(entry.get("source_style", "")),
			"weapon_type": str(entry.get("weapon_type", "")), "set": set_id, "drop_level": int(entry.get("drop_level", 1)),
			"procedural": bool(entry.get("procedural", false)),  ## the client builds the look in code (no model file)
			"race": str(entry.get("race", "")), "class": str(entry.get("class", "")),  ## race gear: the set's race, the class whose look it is
			"fallback_asset_path": str(entry.get("fallback_asset_path", "")), "fallback_icon_path": str(entry.get("fallback_icon_path", "")),  ## shown until the Studio file exists
		}


func entry(item_id: String) -> Dictionary:
	return items.get(item_id, {})


## The catalog items a monster of `level` can drop into `slot_id` (a weapon also has to be of
## `weapon_type`), sorted by id so a seed always picks the same one.
func candidates(slot_id: String, weapon_type: String, level: int) -> Array[String]:
	var found: Array[String] = []
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item["slot"] == slot_id and item["drop_level"] <= maxi(level, 1) and (slot_id != "weapon" or item["weapon_type"] == weapon_type):
			found.append(item_id)
	found.sort()
	return found


## What a dropped / rewarded piece can be (Boss 2026-10-15: only pieces that have a model, i.e. a
## catalog item): {"slots": the ids of `slot_ids` with a catalog item a monster of `level` can drop
## (weapon only if one of `weapon_types` has one), "weapon_types": those of `weapon_types` that do}.
## Both keep the order they were given in.
func droppable(slot_ids: Array, weapon_types: Array, level: int) -> Dictionary:
	var types: Array[String] = []
	for weapon_type in weapon_types:
		if not candidates("weapon", str(weapon_type), level).is_empty():
			types.append(str(weapon_type))
	var slots: Array[String] = []
	for slot_id in slot_ids:
		if (slot_id == "weapon" and not types.is_empty()) or (slot_id != "weapon" and not candidates(str(slot_id), "", level).is_empty()):
			slots.append(str(slot_id))
	return {"slots": slots, "weapon_types": types}


## How many worn pieces each set has: set id -> count. `item_ids` are the worn items' item_id.
func set_counts(item_ids: Array) -> Dictionary:
	var counts := {}
	for item_id in item_ids:
		var set_id: String = items.get(item_id, {}).get("set", "")
		if not set_id.is_empty():
			counts[set_id] = int(counts.get(set_id, 0)) + 1
	return counts


## The race gear set of `item_id` ({} for a generic set or none).
func race_set_of(item_id: String) -> Dictionary:
	var set_id: String = items.get(item_id, {}).get("set", "")
	return sets.get(set_id, {}) if str(sets.get(set_id, {}).get("kind", "")) == "race" else {}


## The race gear piece id for `race` x `class_id` x `slot_id` ("" when the catalog has none).
func race_piece(race: String, class_id: String, slot_id: String) -> String:
	var id := "race_%s_%s_%s" % [race, class_id, slot_id]
	return id if items.has(id) else ""


## The race off-hand shield id for `race` ("" when the catalog has none).
func race_shield(race: String) -> String:
	var id := "race_%s_shield" % race
	return id if items.has(id) else ""


## The stats the worn sets add: stat -> value. Every step a set has reached counts.
func set_bonus(item_ids: Array) -> Dictionary:
	var totals := {}
	var counts := set_counts(item_ids)
	for set_id in counts:
		for bonus in sets[set_id]["bonuses"]:
			if counts[set_id] >= bonus["pieces"]:
				totals[bonus["stat"]] = float(totals.get(bonus["stat"], 0.0)) + bonus["value"]
	return totals


static func _read(path: String, catalog) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}  # no catalog: items are plain rolled pieces as before
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		catalog.errors.append("%s is not a JSON object" % path)
		return {}
	return data
