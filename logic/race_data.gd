extends RefCounted
## Races (design/gdd/races-and-classes.md 3.3-3.7): one file per race in data/races/ (the folder listing IS the race
## list) plus data/races/rules.json (starter races, Alliance, caps, and the fixed effect vocabulary).
## Pure data + strict validation: an unknown effect type, event, action, target, center, stat or status id is a LOAD
## ERROR (`errors` not empty), never a silent no-op at runtime. A class with no cell in a race uses that race's
## `default_class`; that is only a warning (`warnings`), so a new class works with every race at once.
## Rules that RUN the effects live in logic/race_passives.gd.

const FOLDER := "res://data/races/"
const RULES_FILE := "rules.json"
const EFFECTS_FILE := "res://data/combat/effects.json"
const CLASS_FOLDER := "res://data/classes/"
const STAT_NAMES := preload("res://logic/combat_data_loader.gd").STAT_NAMES
## Fields a skill_mod may carry (3.6 #3); Blood Rite's `min_hp` is the "cannot cast below" gate.
const SKILL_MOD_FIELDS: Array[String] = ["type", "damage_mul", "cooldown_mul", "radius_mul", "crit_add", "hp_cost", "min_hp"]
const HEAL_SOURCES: Array[String] = ["max_hp", "damage", "source_max_hp"]
const SHIELD_SOURCES: Array[String] = ["source_max_hp", "damage"]

var races: Dictionary = {}  ## id -> race file (Dictionary)
var rules: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
var _status_ids: Array = []
var _class_ids: Array = []

static var _default = null


## The game's races (cached). Tests that need a fresh or broken set use load_from().
static func load_default():
	if _default == null:
		_default = load_from(FOLDER)
	return _default


## Loads every race file in `folder` (+ its rules.json). `status_ids` / `class_ids` default to the game's.
static func load_from(folder: String, status_ids: Array = [], class_ids: Array = []):
	var data = load("res://logic/race_data.gd").new()
	data._status_ids = status_ids if not status_ids.is_empty() else _game_status_ids()
	data._class_ids = class_ids if not class_ids.is_empty() else _game_class_ids()
	var parsed_rules = _read(folder + RULES_FILE)
	if not parsed_rules is Dictionary:
		data.errors.append("rules.json missing or not an object")
		return data
	data.rules = parsed_rules
	data._check_rules()
	var files := Array(DirAccess.get_files_at(folder))
	files.sort()
	for file in files:
		if not file.ends_with(".json") or file == RULES_FILE:
			continue
		var race = _read(folder + file)
		if not race is Dictionary:
			data.errors.append("%s: not a JSON object" % file)
			continue
		if str(race.get("id", "")) != file.get_basename():
			data.errors.append("%s: id must be the file name" % file)
			continue
		data._check_race(race)
		data.races[race["id"]] = race
	if data.races.is_empty():
		data.errors.append("no race files")
	for class_id in data.rules.get("starter_races", {}):
		if not data.races.has(str(data.rules["starter_races"][class_id])):
			data.errors.append("starter_races.%s: unknown race %s" % [class_id, data.rules["starter_races"][class_id]])
	if not data.races.has(str(data.rules.get("default_race", ""))):
		data.errors.append("default_race: unknown race")
	for class_id in data._class_ids:  # class signatures (3.2) use the same vocabulary
		var class_file = _read(CLASS_FOLDER + str(class_id) + ".json")
		if class_file is Dictionary and class_file.has("signature"):
			data._check_effects("class %s.signature" % class_id, class_file["signature"])
	return data


## Race ids in card order (`order`, then id).
func ids() -> Array:
	var list := races.keys()
	list.sort_custom(func(a, b): return [int(races[a].get("order", 99)), a] < [int(races[b].get("order", 99)), b])
	return list


func has_race(id: String) -> bool:
	return races.has(id)


## The race a class card starts with (and an old card without a race gets): rules.starter_races, else default_race.
func starter_race(class_id: String) -> String:
	var race := str(rules.get("starter_races", {}).get(class_id, rules.get("default_race", "")))
	return race if races.has(race) else str(rules.get("default_race", ""))


func default_race() -> String:
	return str(rules.get("default_race", ""))


## {"name", "text", "effects"} for this race x class: the class cell, else the race's default_class passive. {} if unknown.
func passive_for(race: String, class_id: String) -> Dictionary:
	if not races.has(race):
		return {}
	var cell: Dictionary = races[race].get("classes", {}).get(class_id, {})
	if cell.has("passive"):
		return cell["passive"]
	return races[race].get("default_class", {}).get("passive", {})


## Squad synergy from the races of the squad at run start (3.5, first match wins): 3 of one race = Trio,
## 2 of one race = Pair, 3 different = Alliance, otherwise none (a solo card, a mixed duo).
## Returns {"kind": "trio"|"pair"|"alliance"|"none", "race", "name", "text", "effects"} (plain data, read-only for UI).
func synergy_for(squad_races: Array) -> Dictionary:
	var counts := {}
	for race in squad_races:
		counts[str(race)] = int(counts.get(str(race), 0)) + 1
	var best := ""
	for race in ids():  # deterministic tie order (a duo can only have one pair anyway)
		if counts.has(race) and (best.is_empty() or int(counts[race]) > int(counts[best])):
			best = race
	if not best.is_empty() and int(counts[best]) >= 3 and races.has(best):
		return _synergy("trio", best, "Trio", races[best].get("synergy", {}).get("3", {}))
	if not best.is_empty() and int(counts[best]) == 2 and races.has(best):
		return _synergy("pair", best, "Pair", races[best].get("synergy", {}).get("2", {}))
	if squad_races.size() >= 3 and counts.size() == squad_races.size():
		var alliance: Dictionary = rules.get("alliance", {})
		return _synergy("alliance", "", str(alliance.get("name", "Alliance")), alliance)
	return {"kind": "none", "race": "", "name": "", "text": "", "effects": []}


func _synergy(kind: String, race: String, name: String, block: Dictionary) -> Dictionary:
	return {"kind": kind, "race": race, "name": name, "text": str(block.get("text", "")), "effects": block.get("effects", []).duplicate(true)}


# ---------------------------------------------------------------- validation

func _check_rules() -> void:
	var vocab = rules.get("vocabulary")
	if not vocab is Dictionary:
		errors.append("rules.json: vocabulary missing")
		return
	for key in ["effect_types", "events", "actions", "targets", "centers", "pseudo_stats"]:
		if not vocab.get(key) is Array:
			errors.append("rules.json: vocabulary.%s missing" % key)
	if not rules.get("starter_races") is Dictionary:
		errors.append("rules.json: starter_races missing")
	if rules.has("alliance"):
		_check_effects("rules.alliance", rules["alliance"].get("effects", []) if rules["alliance"] is Dictionary else null)
	else:
		errors.append("rules.json: alliance missing")


func _check_race(race: Dictionary) -> void:
	var where := str(race["id"])
	if not race.get("classes") is Dictionary:
		errors.append("%s: classes missing" % where)
		return
	for class_id in race["classes"]:
		if not _class_ids.has(str(class_id)):
			errors.append("%s: unknown class %s" % [where, class_id])
			continue
		_check_cell("%s.%s" % [where, class_id], race["classes"][class_id])
	for class_id in _class_ids:
		if not race["classes"].has(class_id):
			warnings.append("%s: no cell for class %s (default_class is used)" % [where, class_id])
	if not race.get("default_class") is Dictionary or not race["default_class"].get("passive") is Dictionary:
		errors.append("%s: default_class.passive missing" % where)
	else:
		_check_cell(where + ".default_class", race["default_class"])
	var synergy = race.get("synergy")
	if not synergy is Dictionary or not synergy.get("2") is Dictionary or not synergy.get("3") is Dictionary:
		errors.append("%s: synergy.2 and synergy.3 required" % where)
	else:
		for size in ["2", "3"]:
			_check_effects("%s.synergy.%s" % [where, size], synergy[size].get("effects"))


func _check_cell(where: String, cell) -> void:
	if not cell is Dictionary or not cell.get("passive") is Dictionary:
		errors.append("%s: passive missing" % where)
		return
	_check_effects(where + ".passive", cell["passive"].get("effects"))
	if cell.get("ultimate") is Dictionary:  # ultimates run in a later phase; their actions must still be valid words
		_check_actions(where + ".ultimate", cell["ultimate"].get("actions", []))


func _check_effects(where: String, effects) -> void:
	if not effects is Array:
		errors.append("%s: effects must be a list" % where)
		return
	var vocab: Dictionary = rules.get("vocabulary", {})
	for effect in effects:
		if not effect is Dictionary:
			errors.append("%s: an effect is not an object" % where)
			continue
		var kind := str(effect.get("type", ""))
		if not vocab.get("effect_types", []).has(kind):
			errors.append("%s: unknown effect type '%s'" % [where, kind])
			continue
		match kind:
			"stat_mod":
				_check_stat(where, effect.get("stat"))
				if not (effect.get("mul") is float or effect.get("add") is float):
					errors.append("%s: stat_mod needs mul or add" % where)
			"low_hp_scaling":
				_check_stat(where, effect.get("stat"))
				if not effect.get("max_mul") is float:
					errors.append("%s: low_hp_scaling needs max_mul" % where)
			"skill_mod":
				for key in effect:
					if not SKILL_MOD_FIELDS.has(str(key)):
						errors.append("%s: unknown skill_mod field '%s'" % [where, key])
			"trigger":
				_check_event(where, effect.get("on"))
				_check_actions(where, effect.get("actions"))
			"charges":
				var gains = effect.get("gain_on")
				for event in (gains if gains is Array else [gains]):
					_check_event(where, event)
				if not effect.get("max") is float or float(effect["max"]) < 1.0:
					errors.append("%s: charges needs max >= 1" % where)
				_check_actions(where, effect.get("actions"))
			"cleave":
				for key in ["per_extra", "max_bonus"]:
					if not effect.get(key) is float:
						errors.append("%s: cleave needs %s" % [where, key])
			"aggro":
				for key in ["radius", "every_ticks", "duration_ticks"]:
					if not effect.get(key) is float:
						errors.append("%s: aggro needs %s" % [where, key])


func _check_actions(where: String, actions) -> void:
	if not actions is Array or (actions as Array).is_empty():
		errors.append("%s: actions must be a non-empty list" % where)
		return
	var vocab: Dictionary = rules.get("vocabulary", {})
	for action in actions:
		if not action is Dictionary:
			errors.append("%s: an action is not an object" % where)
			continue
		var kind := str(action.get("action", ""))
		if not vocab.get("actions", []).has(kind):
			errors.append("%s: unknown action '%s'" % [where, kind])
			continue
		if action.has("target") and not vocab.get("targets", []).has(str(action["target"])):
			errors.append("%s: unknown target '%s'" % [where, action["target"]])
		if action.has("center") and not vocab.get("centers", []).has(str(action["center"])):
			errors.append("%s: unknown center '%s'" % [where, action["center"]])
		if action.has("status"):
			_check_status(where, action["status"])
		match kind:
			"apply_status":
				if not action.has("status") or not action.has("target"):
					errors.append("%s: apply_status needs status and target" % where)
			"heal":
				if not action.has("target") or not HEAL_SOURCES.has(str(action.get("fraction_of", ""))) or not action.get("fraction") is float:
					errors.append("%s: heal needs target, fraction_of (max_hp|damage|source_max_hp) and fraction" % where)
			"shield":
				if not action.has("target") or not SHIELD_SOURCES.has(str(action.get("fraction_of", ""))) or not action.get("fraction") is float:
					errors.append("%s: shield needs target, fraction_of and fraction" % where)
			"burst":
				if not action.get("atk_mul") is float or not action.get("radius") is float:
					errors.append("%s: burst needs atk_mul and radius" % where)
				if action.get("delayed") is Dictionary and action["delayed"].has("status"):
					_check_status(where, action["delayed"]["status"])
			"zone":
				_check_actions(where + ".zone.pulse", action.get("pulse"))
				if action.has("on_end"):
					_check_actions(where + ".zone.on_end", action["on_end"])


func _check_event(where: String, event) -> void:
	if not rules.get("vocabulary", {}).get("events", []).has(str(event)):
		errors.append("%s: unknown event '%s'" % [where, event])


func _check_stat(where: String, stat) -> void:
	if not STAT_NAMES.has(str(stat)) and not rules.get("vocabulary", {}).get("pseudo_stats", []).has(str(stat)):
		errors.append("%s: unknown stat '%s'" % [where, stat])


func _check_status(where: String, status) -> void:
	if not _status_ids.has(str(status)):
		errors.append("%s: unknown status '%s'" % [where, status])


static func _read(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


static func _game_status_ids() -> Array:
	var parsed = _read(EFFECTS_FILE)
	return parsed.get("effects", {}).keys() if parsed is Dictionary else []


static func _game_class_ids() -> Array:
	var out := []
	for file in DirAccess.get_files_at(CLASS_FOLDER):
		if file.ends_with(".json"):
			out.append(file.get_basename())
	return out
