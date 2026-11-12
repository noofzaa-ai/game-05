extends RefCounted
## Card skill tree DATA (design/gdd/skill-tree.md 3.1, 3.4, 3.5, 3.8-3.10, acceptance 1, 8): loads the class branch of every
## class (data/classes/<id>.json "skill_tree") and the race branch + combo capstones of every race (data/races/<id>.json
## "skill_tree") against data/skill_tree/rules.json, with strict validation in race_data.gd style: a wrong tier count,
## type, cost, gate, OR pair, unknown effect type, event, action, target, stat, skill, status or mechanic id is a LOAD
## ERROR (`errors`), never a silent no-op. A class with no combo in a race is only a warning (the race has none to offer).
## Independent of the old skill system's chart/tree/gems (data/skill_system/tree, gems): Boss 2026-11-13, those go.
## Pure data. The rules that learn/validate a card's tree are in logic/skill_tree.gd.

const RULES_FILE := "res://data/skill_tree/rules.json"
const TEXTS_FILE := "res://data/skill_tree/texts.json"  ## player-facing node descriptions (the node `text` is the spec line)
const CLASS_FOLDER := "res://data/classes/"
const RACE_FOLDER := "res://data/races/"
const RaceData := preload("res://logic/race_data.gd")
const BRANCH_CLASS := "class"
const BRANCH_RACE := "race"
const BRANCH_COMBO := "combo"
const NODE_KEYS: Array[String] = ["id", "tier", "type", "cost", "excl", "name", "text", "icon", "effects"]
const MOD_OPS: Array = [0, 1, 2]  ## ZorxStatMod ADD, MUL, SET (GDD 3.5 skill_upgrade)

var rules: Dictionary = {}
var classes: Dictionary = {}  ## class id -> {"skills": [4 skill ids], "nodes": [node]}
var races: Dictionary = {}  ## race id -> {"nodes": [node], "combo": {class id: node}}
var by_id: Dictionary = {}  ## node id -> {"node", "branch", "owner": class or race id, "class"?: combo class}
var texts: Dictionary = {}  ## language -> {node id: player sentence}
var errors: Array[String] = []
var warnings: Array[String] = []
var _race_data
var _status_ids: Array = []
var _all_skills: Array = []  ## every class's skill_tree.skills (trigger/pilot skill ids are checked against it)

static var _default = null


## The game's tree data (cached). Tests use load_from() for fixtures.
static func load_default():
	if _default == null:
		_default = load_from(CLASS_FOLDER, RACE_FOLDER, RULES_FILE)
	return _default


static func load_from(class_folder: String, race_folder: String, rules_file: String, race_data = null):
	var data = load("res://logic/skill_tree_data.gd").new()
	data._race_data = race_data if race_data != null else (RaceData.load_default() if race_folder == RACE_FOLDER else RaceData.load_from(race_folder))
	data._status_ids = data._race_data._status_ids
	var parsed = RaceData._read(rules_file)
	if not parsed is Dictionary:
		data.errors.append("skill_tree rules missing or not an object")
		return data
	data.rules = parsed
	data._check_rules()
	if not data.errors.is_empty():
		return data
	for file in _json_files(class_folder):  # the skill ids first: race/combo nodes may name any class's skill
		var listed = RaceData._read(class_folder + file)
		if listed is Dictionary and listed.get("skill_tree") is Dictionary and listed["skill_tree"].get("skills") is Array:
			for skill in listed["skill_tree"]["skills"]:
				if skill is String and skill.is_valid_identifier():
					data._all_skills.append(skill)
	for file in _json_files(class_folder):
		var class_file = RaceData._read(class_folder + file)
		var class_id: String = str(file).get_basename()
		if not class_file is Dictionary or not class_file.get("skill_tree") is Dictionary:
			data.errors.append("class %s: skill_tree missing" % class_id)
			continue
		data._load_class(class_id, class_file["skill_tree"])
	for file in _json_files(race_folder):
		if file == RaceData.RULES_FILE:
			continue
		var race_file = RaceData._read(race_folder + file)
		var race_id: String = str(file).get_basename()
		if not race_file is Dictionary or not race_file.get("skill_tree") is Dictionary:
			data.errors.append("race %s: skill_tree missing" % race_id)
			continue
		data._load_race(race_id, race_file["skill_tree"])
	for race_id in data.races:
		for class_id in data.classes:
			if not data.races[race_id]["combo"].has(class_id):
				data.warnings.append("race %s: no combo for class %s" % [race_id, class_id])
	var parsed_texts = RaceData._read(TEXTS_FILE)
	data.texts = parsed_texts if parsed_texts is Dictionary else {}
	if rules_file == RULES_FILE:  # the game's own data: every node needs its player sentence
		for id in data.by_id:
			if str(data.texts.get("en", {}).get(id, "")).is_empty():
				data.errors.append("texts.json: no description for %s" % id)
	return data


## The player-facing sentence of a node in `language` (English when missing; the spec line as the last resort,
## without backticks).
func description(node_id: String, language: String = "en") -> String:
	var text := str(texts.get(language, {}).get(node_id, texts.get("en", {}).get(node_id, "")))
	return text if not text.is_empty() else str(node(node_id).get("text", "")).replace("`", "")


# ---------------------------------------------------------------- queries

func tiers(branch: String) -> Array:
	return rules.get("branches", {}).get(branch, [])


## The tier rule {"tier", "gate", "count", "type", "cost", "exclusive"} of a branch, {} when unknown.
func tier_rule(branch: String, tier: int) -> Dictionary:
	for rule in tiers(branch):
		if int(rule["tier"]) == tier:
			return rule
	return {}


func combo_rule() -> Dictionary:
	return rules.get("combo", {})


func class_reset_gold_per_point() -> int:
	return int(rules.get("class_reset_gold_per_point", 0))


func class_nodes(class_id: String) -> Array:
	return classes.get(class_id, {}).get("nodes", [])


func race_nodes(race_id: String) -> Array:
	return races.get(race_id, {}).get("nodes", [])


## The combo capstone of this class x race ({} when the race has none for the class).
func combo_node(race_id: String, class_id: String) -> Dictionary:
	return races.get(race_id, {}).get("combo", {}).get(class_id, {})


func node(node_id: String) -> Dictionary:
	return by_id.get(node_id, {}).get("node", {})


## "class" | "race" | "combo" | "" for an unknown id.
func branch_of(node_id: String) -> String:
	return str(by_id.get(node_id, {}).get("branch", ""))


## The class's 4 skills (its skill_tree "skills").
func class_skills(class_id: String) -> Array:
	return classes.get(class_id, {}).get("skills", [])


# ---------------------------------------------------------------- validation

func _check_rules() -> void:
	for branch in [BRANCH_CLASS, BRANCH_RACE]:
		var list = rules.get("branches", {}).get(branch) if rules.get("branches") is Dictionary else null
		if not list is Array or (list as Array).is_empty():
			errors.append("skill_tree rules: branches.%s missing" % branch)
			continue
		var last_gate := -1
		for at in list.size():
			var rule = list[at]
			if not rule is Dictionary or int(rule.get("tier", 0)) != at + 1 or not _is_number(rule.get("gate")) or not _is_number(rule.get("count")) or not _is_number(rule.get("cost")) or not rule.get("exclusive") is bool or not str(rule.get("type", "")) in ["minor", "major", "capstone"]:
				errors.append("skill_tree rules: branches.%s tier %d needs tier/gate/count/type/cost/exclusive" % [branch, at + 1])
				continue
			if int(rule["gate"]) < last_gate or (at == 0 and int(rule["gate"]) != 0):
				errors.append("skill_tree rules: branches.%s gates must start at 0 and never go down" % branch)
			if bool(rule["exclusive"]) and int(rule["count"]) % 2 != 0:
				errors.append("skill_tree rules: branches.%s tier %d is exclusive with an odd count" % [branch, at + 1])
			last_gate = int(rule["gate"])
	var combo = rules.get("combo")
	if not combo is Dictionary or not _is_number(combo.get("class_gate")) or not _is_number(combo.get("race_gate")) or not _is_number(combo.get("cost")):
		errors.append("skill_tree rules: combo needs class_gate, race_gate and cost")
	if not _is_number(rules.get("class_reset_gold_per_point")) or float(rules["class_reset_gold_per_point"]) < 0.0:
		errors.append("skill_tree rules: class_reset_gold_per_point missing")
	var vocab = rules.get("vocabulary")
	if not vocab is Dictionary:
		errors.append("skill_tree rules: vocabulary missing")
		return
	for key in ["effect_types", "events", "actions", "targets", "stats", "trigger_filters", "skill_statuses", "skill_behaviors", "cell_mod_fields", "gauge_mod_fields", "signature_mod_fields", "pilot_mod_fields"]:
		if not vocab.get(key) is Array:
			errors.append("skill_tree rules: vocabulary.%s missing" % key)
	if not vocab.get("mechanics") is Dictionary:
		errors.append("skill_tree rules: vocabulary.mechanics missing")


func _load_class(class_id: String, block: Dictionary) -> void:
	var where := "class %s" % class_id
	var skills = block.get("skills")
	if not skills is Array or (skills as Array).size() != 4 or not skills.all(func(s): return s is String and s.is_valid_identifier()) or (skills as Array).duplicate().filter(func(s): return skills.count(s) > 1).size() > 0:
		errors.append("%s: skill_tree.skills must be 4 different skill ids" % where)
		skills = []
	var nodes := _load_branch(where, BRANCH_CLASS, block.get("nodes"), class_id)
	classes[class_id] = {"skills": skills, "nodes": nodes}
	for entry in nodes:  # class nodes upgrade only this class's own skills
		for effect in entry["effects"]:
			if effect.get("type") == "skill_upgrade" and not (skills as Array).has(str(effect.get("skill", ""))):
				errors.append("%s.%s: skill_upgrade of a skill this class does not have (%s)" % [where, entry["id"], effect.get("skill")])


func _load_race(race_id: String, block: Dictionary) -> void:
	var where := "race %s" % race_id
	var nodes := _load_branch(where, BRANCH_RACE, block.get("nodes"), race_id)
	var combos := {}
	var raw_combos = block.get("combo", {})
	if not raw_combos is Dictionary:
		errors.append("%s: combo must be an object {class id: node}" % where)
		raw_combos = {}
	var combo := combo_rule()
	for class_id in raw_combos:
		var n = raw_combos[class_id]
		var at := "%s.combo.%s" % [where, class_id]
		if not _check_node(at, n):
			continue
		if int(n["tier"]) != 0 or str(n["type"]) != str(combo.get("type", "capstone")) or int(n["cost"]) != int(combo.get("cost", 3)) or not str(n["excl"]).is_empty():
			errors.append("%s: a combo is tier 0, type %s, cost %d, no excl" % [at, combo.get("type", "capstone"), int(combo.get("cost", 3))])
			continue
		if not _register(at, n, BRANCH_COMBO, race_id, str(class_id)):
			continue
		combos[str(class_id)] = n
	races[race_id] = {"nodes": nodes, "combo": combos}


## Validates one branch's node list against its tier rules; returns the sound nodes.
func _load_branch(where: String, branch: String, raw, owner: String) -> Array:
	var out: Array = []
	if not raw is Array:
		errors.append("%s: skill_tree.nodes must be a list" % where)
		return out
	var per_tier := {}
	var pairs := {}
	for n in raw:
		var at := "%s.%s" % [where, n.get("id", "?") if n is Dictionary else "?"]
		if not _check_node(at, n):
			continue
		var rule := tier_rule(branch, int(n["tier"]))
		if rule.is_empty():
			errors.append("%s: unknown tier %s" % [at, n["tier"]])
			continue
		if str(n["type"]) != str(rule["type"]) or int(n["cost"]) != int(rule["cost"]):
			errors.append("%s: tier %d nodes are %s, cost %d" % [at, int(rule["tier"]), rule["type"], int(rule["cost"])])
			continue
		var excl := str(n["excl"])
		if bool(rule["exclusive"]) == excl.is_empty():
			errors.append("%s: tier %d %s an OR pair id (excl)" % [at, int(rule["tier"]), "needs" if bool(rule["exclusive"]) else "has no"])
			continue
		if not _register(at, n, branch, owner):
			continue
		per_tier[int(n["tier"])] = int(per_tier.get(int(n["tier"]), 0)) + 1
		if not excl.is_empty():
			if not pairs.has(excl):
				pairs[excl] = []
			pairs[excl].append(n)
		out.append(n)
	for rule in tiers(branch):
		if int(per_tier.get(int(rule["tier"]), 0)) != int(rule["count"]):
			errors.append("%s: tier %d needs %d nodes, has %d" % [where, int(rule["tier"]), int(rule["count"]), int(per_tier.get(int(rule["tier"]), 0))])
	for excl in pairs:
		var members: Array = pairs[excl]
		if members.size() != 2:
			errors.append("%s: OR pair %s needs exactly 2 nodes, has %d" % [where, excl, members.size()])
		elif int(members[0]["tier"]) != int(members[1]["tier"]):
			errors.append("%s: OR pair %s spans two tiers" % [where, excl])
	return out


func _register(at: String, n: Dictionary, branch: String, owner: String, combo_class: String = "") -> bool:
	var id := str(n["id"])
	if by_id.has(id):
		errors.append("%s: node id %s is used twice" % [at, id])
		return false
	by_id[id] = {"node": n, "branch": branch, "owner": owner, "class": combo_class}
	return true


func _check_node(at: String, n) -> bool:
	if not n is Dictionary:
		errors.append("%s: a node is not an object" % at)
		return false
	for key in NODE_KEYS:
		if not n.has(key):
			errors.append("%s: node needs %s" % [at, key])
			return false
	if not n["id"] is String or str(n["id"]).is_empty() or not _is_number(n["tier"]) or not _is_number(n["cost"]) or not n["excl"] is String or not n["name"] is String or not n["text"] is String or not n["icon"] is String:
		errors.append("%s: node fields have the wrong types" % at)
		return false
	if not str(n["type"]) in ["minor", "major", "capstone"]:
		errors.append("%s: unknown node type %s" % [at, n["type"]])
		return false
	return _check_effects(at, n["effects"])


## Node effects: the race vocabulary (stat_mod, low_hp_scaling, skill_mod, trigger, charges, aggro, cleave, all
## actions) plus the node-only words of rules.vocabulary (GDD 3.5).
func _check_effects(at: String, effects) -> bool:
	var before := errors.size()
	if not effects is Array or (effects as Array).is_empty():
		errors.append("%s: effects must be a non-empty list" % at)
		return false
	var vocab: Dictionary = rules["vocabulary"]
	for effect in effects:
		if not effect is Dictionary:
			errors.append("%s: an effect is not an object" % at)
			continue
		var kind := str(effect.get("type", ""))
		match kind:
			"skill_upgrade":
				if not _skill_exists(str(effect.get("skill", ""))):
					errors.append("%s: skill_upgrade of unknown skill %s" % [at, effect.get("skill")])
				var mods = effect.get("mods", [])
				if not mods is Array:
					errors.append("%s: skill_upgrade mods must be a list" % at)
				else:
					for mod in mods:
						if not mod is Dictionary or not mod.get("stat") is String or not MOD_OPS.has(int(mod.get("op", -1))) or not _is_number(mod.get("value")):
							errors.append("%s: a skill_upgrade mod needs stat, op (0 add, 1 mul, 2 set) and value" % at)
				if effect.has("status") and not vocab["skill_statuses"].has(str(effect["status"])):
					errors.append("%s: unknown skill status %s" % [at, effect["status"]])
				if effect.has("behavior") and not vocab["skill_behaviors"].has(str(effect["behavior"])):
					errors.append("%s: unknown skill behavior %s" % [at, effect["behavior"]])
			"cell_mod":
				if not str(effect.get("cell", "")) in ["passive", "ultimate"]:
					errors.append("%s: cell_mod cell must be passive or ultimate" % at)
				_check_fields(at, effect, vocab["cell_mod_fields"])
				if effect.has("extra_actions"):
					_check_actions(at, effect["extra_actions"])
			"gauge_mod":
				_check_fields(at, effect, vocab["gauge_mod_fields"])
			"signature_mod":
				_check_fields(at, effect, vocab["signature_mod_fields"])
				if effect.has("extra_actions"):
					_check_actions(at, effect["extra_actions"])
			"pilot_mod":
				_check_fields(at, effect, vocab["pilot_mod_fields"])
				if effect.has("kite_drop_skill") and not _skill_exists(str(effect["kite_drop_skill"])):
					errors.append("%s: pilot_mod kite_drop_skill unknown" % at)
				if effect.has("cast_center") and str(effect["cast_center"]) != "densest":
					errors.append("%s: pilot_mod cast_center must be densest" % at)
			"mechanic":
				if not vocab["mechanics"].has(str(effect.get("id", ""))):
					errors.append("%s: unknown mechanic %s" % [at, effect.get("id")])
				if effect.has("status"):
					_check_status(at, effect["status"])
				for status in effect.get("statuses", []):
					_check_status(at, status)
			"stat_mod":
				if not vocab["stats"].has(str(effect.get("stat", ""))):
					_race_effect(at, effect)
				elif not _is_number(effect.get("add")) and not _is_number(effect.get("mul")):
					errors.append("%s: stat_mod needs mul or add" % at)
			"trigger":
				for key in effect:
					if not str(key) in ["type", "on", "actions", "chance", "every_n", "cooldown_ticks", "once_per_wave", "hp_below", "new_target"] and not vocab["trigger_filters"].has(str(key)):
						errors.append("%s: unknown trigger field %s" % [at, key])
				if effect.has("skill") and not _skill_exists(str(effect["skill"])):
					errors.append("%s: trigger skill filter unknown" % at)
				if effect.has("target_has"):
					_check_status(at, effect["target_has"])
				var event := str(effect.get("on", ""))
				if not vocab["events"].has(event) and not _race_data.rules.get("vocabulary", {}).get("events", []).has(event):
					errors.append("%s: unknown event '%s'" % [at, event])
				_check_actions(at, effect.get("actions"))
			_:
				if vocab["effect_types"].has(kind):
					errors.append("%s: effect type %s has no checker" % [at, kind])
				else:
					_race_effect(at, effect)
	return errors.size() == before


func _check_fields(at: String, effect: Dictionary, allowed: Array) -> void:
	for key in effect:
		if str(key) != "type" and not allowed.has(str(key)):
			errors.append("%s: unknown %s field %s" % [at, effect["type"], key])


## A race-vocabulary effect: checked by RaceData (its errors are copied here).
func _race_effect(at: String, effect: Dictionary) -> void:
	var before: int = _race_data.errors.size()
	_race_data._check_effects(at, [effect])
	_take_race_errors(before)


## Actions: the node-only ones are checked here, the rest by RaceData.
func _check_actions(at: String, actions) -> void:
	if not actions is Array or (actions as Array).is_empty():
		errors.append("%s: actions must be a non-empty list" % at)
		return
	var vocab: Dictionary = rules["vocabulary"]
	var race_vocab: Dictionary = _race_data.rules.get("vocabulary", {})
	for action in actions:
		if not action is Dictionary:
			errors.append("%s: an action is not an object" % at)
			continue
		var kind := str(action.get("action", ""))
		var target := str(action.get("target", ""))
		if vocab["targets"].has(target):
			var copy: Dictionary = action.duplicate()
			copy["target"] = "self"  # node-only target (allies_in_radius): check the rest with the race checker
			action = copy
		if action.has("status") and kind != "skill_status":
			_check_status(at, action["status"])
		match kind:
			"pull":
				if not _is_number(action.get("radius")) or not _is_number(action.get("distance")):
					errors.append("%s: pull needs radius and distance" % at)
			"cleanse":
				if not action.get("statuses") is Array:
					errors.append("%s: cleanse needs statuses" % at)
			"skill_status":
				if not vocab["skill_statuses"].has(str(action.get("status", ""))) or not _is_number(action.get("stacks")):
					errors.append("%s: skill_status needs a skill status and stacks" % at)
			"death_save":
				for key in ["duration_ticks", "atk_mul", "survive_if_kill"]:
					if not _is_number(action.get(key)):
						errors.append("%s: death_save needs %s" % [at, key])
			"reflect":
				if not _is_number(action.get("fraction")):
					errors.append("%s: reflect needs fraction" % at)
			_:
				if not race_vocab.get("actions", []).has(kind):
					errors.append("%s: unknown action '%s'" % [at, kind])
					continue
				var before: int = _race_data.errors.size()
				_race_data._check_actions(at, [action])
				_take_race_errors(before)


func _take_race_errors(before: int) -> void:
	while _race_data.errors.size() > before:
		errors.append(_race_data.errors.pop_back())


func _check_status(at: String, status) -> void:
	if not _status_ids.has(str(status)):
		errors.append("%s: unknown status '%s'" % [at, status])


## A skill id some class has (its skill_tree.skills). Not tied to the old skill system's files (Boss 2026-11-13).
func _skill_exists(skill_id: String) -> bool:
	return _all_skills.has(skill_id)


static func _is_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


static func _json_files(folder: String) -> Array:
	var files := Array(DirAccess.get_files_at(folder)).filter(func(f): return str(f).ends_with(".json"))
	files.sort()
	return files
