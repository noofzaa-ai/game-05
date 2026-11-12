extends RefCounted
## Reads and validates the combat data: data/combat/combat.json (rules and monsters),
## data/combat/weapons.json (the player's weapons) and data/combat/effects.json (buffs and debuffs). Every weapon is built from shared move
## templates scaled by the weapon's own numbers, so the loader generates all of a weapon's moves.
## Mistakes come back as `errors`, never as a crash.

const CombatData := preload("res://logic/combat_data.gd")
const SimBody := preload("res://logic/sim_body.gd")

const DATA_PATH := "res://data/combat/combat.json"
const WEAPONS_PATH := "res://data/combat/weapons.json"
const EFFECTS_PATH := "res://data/combat/effects.json"
const ULTIMATES_PATH := "res://data/combat/ultimates.json"
const SUPPORTED_VERSION := 1
const MIN_TELEGRAPH_STARTUP := 20  ## ticks (a third of a second): the shortest warning that is fair to react to
const STYLE_ENTRIES: Array[String] = ["ground_light", "ground_heavy", "air_light"]
const OPTIONAL_STYLE_ENTRIES: Array[String] = ["special", "ultimate", "run_light", "run_heavy", "air_heavy"]
const RULE_NUMBERS: Array[String] = [
	"defense_constant", "min_damage", "down_ticks", "wakeup_invulnerable_ticks", "guard_damage_reduction",
	"guard_knockback_factor", "dodge_ticks", "dodge_invulnerable_ticks", "dodge_cooldown", "dodge_speed",
	"ultimate_gauge_max", "gauge_per_hit_dealt", "gauge_per_hit_taken",
	"energy_regen_delay_ticks", "run_energy_per_second", "run_resume_energy", "dodge_energy", "combo_window_ticks",
	"jump_energy", "guard_energy_per_power", "poise_damage_per_power", "poise_regen_delay_ticks",
	"enemy_max_attackers", "attack_assist_range", "run_attack_min_ticks", "run_attack_grace_ticks",
]
const STAT_NAMES: Array[String] = [
	"HP", "ATK", "DEF", "ATKSPD", "MOVESPD", "CRIRATE", "CRIDMG", "EFFECT_ACC", "EFFECT_RES",
	"HPREGEN", "STAREGEN", "ULTREGEN", "STAMINA",
]

## The moves every weapon has (the template names in weapons.json) and which style entry each fills.
const TEMPLATE_KEYS: Array[String] = ["light_1", "light_2", "light_3", "heavy", "air", "air_heavy", "run_light", "run_heavy", "special", "ultimate"]
const STYLE_FROM_TEMPLATE := {
	"ground_light": "light_1", "ground_heavy": "heavy", "air_light": "air", "air_heavy": "air_heavy",
	"run_light": "run_light", "run_heavy": "run_heavy", "special": "special", "ultimate": "ultimate",
}
const WEAPON_NUMBERS: Array[String] = ["speed", "reach", "width", "power", "knockback", "launch", "stun", "stamina"]
const INT_FIELDS: Array[String] = ["startup", "active", "recovery", "hitstun", "hitstop", "cooldown", "invuln_from", "invuln_to"]
const FLOAT_FIELDS: Array[String] = ["power", "knockback", "launch", "energy_cost", "gauge_cost", "advance", "dive", "grow_from", "dash_distance", "dash_from", "dash_to"]
const VECTOR_FIELDS: Array[String] = ["hit_offset", "hit_size"]
const EFFECT_KINDS: Array[String] = ["buff", "debuff"]
const EFFECT_CONTROLS: Array[String] = ["", "stun", "shock", "sleep"]
const EFFECT_STATS: Array[String] = ["HEALING", "SKILL_DMG"]  ## pseudo-stats an effect may change besides STAT_NAMES
const OVERRIDE_FIELDS: Array[String] = [
	"effects", "spawns", "melee", "on_light", "on_heavy",
	"startup", "active", "recovery", "hitstun", "hitstop", "cooldown", "invuln_from", "invuln_to", "power", "knockback",
	"launch", "energy_cost", "gauge_cost", "advance", "dive", "hit_offset", "hit_size", "ignores_guard", "grow_from",
	"dash_distance", "dash_from", "dash_to",
]


static func load_default() -> CombatData:
	if not FileAccess.file_exists(DATA_PATH):
		var missing := CombatData.new()
		missing.errors.append("combat file not found: %s" % DATA_PATH)
		return missing
	return parse(FileAccess.get_file_as_string(DATA_PATH))


## `weapons_text` and `effects_text` default to the shipped files (tests pass their own to try broken ones).
static func parse(text: String, weapons_text: String = "", effects_text: String = "", ultimates_text: String = "") -> CombatData:
	var data := CombatData.new()
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
	_parse_rules(root, data)
	_parse_coop(root, data)
	_parse_effects(effects_text, data)
	_parse_ranged(root, data)
	_parse_moves(root, data)
	_parse_ultimates(ultimates_text, data)
	_parse_weapons(weapons_text, data)
	_parse_styles(root, data)
	_parse_enemies(root, data)
	return data


static func _dict(parent: Dictionary, key: String, data: CombatData) -> Dictionary:
	if typeof(parent.get(key)) != TYPE_DICTIONARY:
		data.errors.append("%s must be an object" % key)
		return {}
	return parent[key]


static func _vec3(value: Variant, label: String, data: CombatData) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		data.errors.append("%s must be [x, y, z]" % label)
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _parse_rules(root: Dictionary, data: CombatData) -> void:
	var rules := _dict(root, "rules", data)
	for key in RULE_NUMBERS:
		if not rules.has(key) or float(rules[key]) < 0.0:
			data.errors.append("rules.%s must be a number, 0 or more" % key)
	if float(rules.get("defense_constant", 0.0)) <= 0.0:
		data.errors.append("rules.defense_constant must be above 0")
	if float(rules.get("guard_damage_reduction", 0.0)) > 1.0 or float(rules.get("guard_knockback_factor", 0.0)) > 1.0:
		data.errors.append("rules.guard_damage_reduction and guard_knockback_factor must be between 0 and 1")
	if float(rules.get("dodge_invulnerable_ticks", 0.0)) > float(rules.get("dodge_ticks", 0.0)):
		data.errors.append("rules.dodge_invulnerable_ticks cannot be longer than dodge_ticks")
	var defaults: Dictionary = rules.get("default_stats", {}) if typeof(rules.get("default_stats")) == TYPE_DICTIONARY else {}
	var clean_defaults := {}
	for stat in STAT_NAMES:
		if not defaults.has(stat):
			data.errors.append("rules.default_stats.%s is missing" % stat)
		clean_defaults[stat] = float(defaults.get(stat, 0.0))
	data.rules = {"default_stats": clean_defaults}
	for key in RULE_NUMBERS:
		data.rules[key] = float(rules.get(key, 0.0))
	for key in ["down_ticks", "wakeup_invulnerable_ticks", "dodge_ticks", "dodge_invulnerable_ticks", "dodge_cooldown", "energy_regen_delay_ticks", "combo_window_ticks", "poise_regen_delay_ticks", "enemy_max_attackers", "run_attack_min_ticks", "run_attack_grace_ticks"]:
		data.rules[key] = int(data.rules[key])
	# How much stronger a monster of level 2, 3... is than level 1: a fraction per level above 1, per stat.
	var scaling := {}
	var raw_scaling: Dictionary = rules.get("enemy_level_scaling", {}) if typeof(rules.get("enemy_level_scaling")) == TYPE_DICTIONARY else {}
	if raw_scaling.is_empty():
		data.errors.append("rules.enemy_level_scaling must list the stats that grow with level")
	for stat in raw_scaling:
		if not STAT_NAMES.has(str(stat)) or float(raw_scaling[stat]) < 0.0:
			data.errors.append("rules.enemy_level_scaling.%s must be a known stat with a number, 0 or more" % stat)
		else:
			scaling[str(stat)] = float(raw_scaling[stat])
	data.rules["enemy_level_scaling"] = scaling


## The buffs and debuffs: every effect id the moves may hand out.
static func _parse_effects(text: String, data: CombatData) -> void:
	if text.is_empty():
		if not FileAccess.file_exists(EFFECTS_PATH):
			data.errors.append("effects file not found: %s" % EFFECTS_PATH)
			return
		text = FileAccess.get_file_as_string(EFFECTS_PATH)
	var json := JSON.new()
	if json.parse(text) != OK:
		data.errors.append("effects.json: invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		data.errors.append("effects.json: top level must be an object")
		return
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		data.errors.append("effects.json: unsupported version (expected %d)" % SUPPORTED_VERSION)
	var rules: Dictionary = root.get("rules", {}) if typeof(root.get("rules")) == TYPE_DICTIONARY else {}
	for key in ["control_immunity_ticks", "dot_interval_ticks"]:
		if not rules.has(key) or float(rules[key]) < 0.0:
			data.errors.append("effects.rules.%s must be a number, 0 or more" % key)
		data.rules[key] = int(rules.get(key, 0))
	if int(data.rules["dot_interval_ticks"]) < 1:
		data.errors.append("effects.rules.dot_interval_ticks must be at least 1")
		data.rules["dot_interval_ticks"] = 1
	var effects: Dictionary = root.get("effects", {}) if typeof(root.get("effects")) == TYPE_DICTIONARY else {}
	if effects.is_empty():
		data.errors.append("effects.effects must list at least one effect")
	for id in effects:
		var label := "effects.%s" % id
		if typeof(effects[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var raw: Dictionary = effects[id]
		var kind := str(raw.get("kind", ""))
		if not EFFECT_KINDS.has(kind):
			data.errors.append("%s.kind must be buff or debuff" % label)
		var control := str(raw.get("control", ""))
		if not EFFECT_CONTROLS.has(control):
			data.errors.append("%s.control must be stun, shock or sleep" % label)
		var duration := int(raw.get("duration", 0))
		if duration < 1:
			data.errors.append("%s.duration must be at least 1 tick" % label)
		var max_stacks := int(raw.get("max_stacks", 1))
		if max_stacks < 1:
			data.errors.append("%s.max_stacks must be at least 1" % label)
		if float(raw.get("dot_power", 0.0)) < 0.0 or float(raw.get("heal_percent", 0.0)) < 0.0:
			data.errors.append("%s.dot_power and heal_percent must not be negative" % label)
		var stats := {}
		var raw_stats: Dictionary = raw.get("stats", {}) if typeof(raw.get("stats")) == TYPE_DICTIONARY else {}
		for stat in raw_stats:
			if not STAT_NAMES.has(str(stat)) and not EFFECT_STATS.has(str(stat)):
				data.errors.append("%s.stats.%s is not a known stat" % [label, stat])
			elif typeof(raw_stats[stat]) != TYPE_DICTIONARY:
				data.errors.append("%s.stats.%s must be {add, mul}" % [label, stat])
			else:
				stats[str(stat)] = {"add": float(raw_stats[stat].get("add", 0.0)), "mul": float(raw_stats[stat].get("mul", 0.0))}
		var color: Variant = raw.get("color", [1.0, 1.0, 1.0])
		if typeof(color) != TYPE_ARRAY or color.size() != 3:
			data.errors.append("%s.color must be [r, g, b]" % label)
			color = [1.0, 1.0, 1.0]
		if stats.is_empty() and control.is_empty() and float(raw.get("dot_power", 0.0)) <= 0.0 and float(raw.get("heal_percent", 0.0)) <= 0.0:
			data.errors.append("%s does nothing (no stats, control, dot_power or heal_percent)" % label)
		data.effects[str(id)] = {
			"name": str(raw.get("name", id)), "kind": kind, "color": Color(float(color[0]), float(color[1]), float(color[2])),
			"duration": duration, "max_stacks": max_stacks, "stats": stats,
			"dot_power": float(raw.get("dot_power", 0.0)), "heal_percent": float(raw.get("heal_percent", 0.0)),
			"control": control, "break_on_damage": bool(raw.get("break_on_damage", false)),
		}


## The `effects` list of a move: the buffs and debuffs it gives out.
static func _normalize_effect_entries(raw: Variant, label: String, data: CombatData) -> Array:
	var entries: Array = []
	if typeof(raw) != TYPE_ARRAY:
		data.errors.append("%s.effects must be a list" % label)
		return entries
	for index in raw.size():
		var entry_label := "%s.effects[%d]" % [label, index]
		if typeof(raw[index]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % entry_label)
			continue
		var item: Dictionary = raw[index]
		var id := str(item.get("id", ""))
		if not data.effects.has(id):
			data.errors.append("%s.id '%s' is not a known effect" % [entry_label, id])
		var target := str(item.get("target", "enemy"))
		if target != "enemy" and target != "self":
			data.errors.append("%s.target must be enemy or self" % entry_label)
		var moment := str(item.get("on", "cast" if target == "self" else "hit"))
		if moment != "hit" and moment != "cast":
			data.errors.append("%s.on must be hit or cast" % entry_label)
		var chance := float(item.get("chance", 100.0))
		if chance < 0.0 or chance > 100.0:
			data.errors.append("%s.chance must be between 0 and 100" % entry_label)
		if moment == "cast" and (target != "self" or chance < 100.0):
			data.errors.append("%s: a cast effect must be on the caster itself with 100%% chance" % entry_label)
		if int(item.get("duration", 0)) < 0:
			data.errors.append("%s.duration must not be negative" % entry_label)
		entries.append({"id": id, "target": target, "on": moment, "chance": chance, "duration": int(item.get("duration", 0))})
	return entries


## A move as the game uses it, read from its JSON description.
static func _normalize_move(raw: Dictionary, label: String, data: CombatData) -> Dictionary:
	return {
		"startup": int(raw.get("startup", 0)),
		"active": int(raw.get("active", 0)),
		"recovery": int(raw.get("recovery", 0)),
		"power": float(raw.get("power", 0.0)),
		"hit_offset": _vec3(raw.get("hit_offset"), label + ".hit_offset", data),
		"hit_size": _vec3(raw.get("hit_size"), label + ".hit_size", data),
		"knockback": float(raw.get("knockback", 0.0)),
		"launch": float(raw.get("launch", 0.0)),
		"hitstun": int(raw.get("hitstun", 0)),
		"hitstop": int(raw.get("hitstop", 0)),
		"on_light": str(raw.get("on_light", "")),
		"on_heavy": str(raw.get("on_heavy", "")),
		"cooldown": int(raw.get("cooldown", 0)),
		"gauge_cost": float(raw.get("gauge_cost", 0.0)),
		"energy_cost": float(raw.get("energy_cost", 0.0)),
		"invuln_from": int(raw.get("invuln_from", -1)),
		"invuln_to": int(raw.get("invuln_to", -1)),
		"ignores_guard": bool(raw.get("ignores_guard", false)),
		"advance": float(raw.get("advance", 0.0)),
		"dive": float(raw.get("dive", 0.0)),
		# A move that carries the fighter forward over a window of its own frames (the skill packs
		# whose caster dashes): how far in metres, and between which frames of the move.
		"dash_distance": float(raw.get("dash_distance", 0.0)),
		"dash_from": float(raw.get("dash_from", 0.0)),
		"dash_to": float(raw.get("dash_to", 0.0)),
		"telegraph": bool(raw.get("telegraph", false)),
		"fixed_reach": bool(raw.get("fixed_reach", false)),
		"grow_from": float(raw.get("grow_from", 1.0)),
		"effects": _normalize_effect_entries(raw.get("effects", []), label, data),
		"spawns": _normalize_spawns(raw, label, data),
		# A move that fires projectiles or marks the ground hits only with those, unless it says
		# "melee": true (a shield bash that also throws something).
		"melee": bool(raw.get("melee", not raw.has("spawns"))),
	}


## A move's "spawns": what it fires and when (projectiles.gd), sorted by frame. A spawn without a
## frame happens at the end of the wind-up (the strike).
static func _normalize_spawns(raw: Dictionary, label: String, data: CombatData) -> Array:
	var out: Array = []
	if not raw.has("spawns"):
		return out
	if typeof(raw["spawns"]) != TYPE_ARRAY:
		data.errors.append("%s.spawns must be a list" % label)
		return out
	for index in raw["spawns"].size():
		var entry = raw["spawns"][index]
		var where := "%s.spawns[%d]" % [label, index]
		if typeof(entry) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % where)
			continue
		var spawn := {"frame": float(entry.get("frame", raw.get("startup", 0))), "offset": _vec3(entry.get("offset", [0.4, 1.0, 0.0]), where + ".offset", data), "angle": float(entry.get("angle", 0.0))}
		if entry.has("projectile"):
			spawn["projectile"] = str(entry["projectile"])
			if not data.projectiles.has(spawn["projectile"]):
				data.errors.append("%s.projectile '%s' is not a known projectile" % [where, spawn["projectile"]])
		elif entry.has("area"):
			spawn["area"] = str(entry["area"])
			if not data.areas.has(spawn["area"]):
				data.errors.append("%s.area '%s' is not a known area" % [where, spawn["area"]])
		elif entry.has("blink"):
			spawn["blink"] = float(entry["blink"])
			if spawn["blink"] == 0.0:
				data.errors.append("%s.blink must not be 0" % where)
		else:
			data.errors.append("%s needs a projectile, an area or a blink" % where)
			continue
		if spawn["frame"] < 0.0:
			data.errors.append("%s.frame must not be negative" % where)
		out.append(spawn)
	out.sort_custom(func(a, b): return a["frame"] < b["frame"])
	return out


## The "projectiles" and "areas" sections (both optional). Placeholders to tune by feel; see
## projectiles.gd for how each field is used.
static func _parse_ranged(root: Dictionary, data: CombatData) -> void:
	var projectiles: Dictionary = root.get("projectiles", {}) if typeof(root.get("projectiles", {})) == TYPE_DICTIONARY else {}
	for id in projectiles:
		if str(id).begins_with("_"):
			continue
		var raw = projectiles[id]
		var label := "projectiles.%s" % id
		if typeof(raw) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var entry := {
			"look": str(raw.get("look", "arrow")),
			"speed": float(raw.get("speed", 12.0)),
			"range": float(raw.get("range", 10.0)),
			"radius": float(raw.get("radius", 0.2)),
			"pierce": int(raw.get("pierce", 0)),
			"gravity": float(raw.get("gravity", 0.0)),
			"lift": float(raw.get("lift", 0.0)),
			"homing": float(raw.get("homing", 0.0)),
			"walls": bool(raw.get("walls", true)),
			"aim_cone": float(raw.get("aim_cone", 35.0)),
		}
		if entry["speed"] <= 0.0 or entry["range"] <= 0.0 or entry["radius"] <= 0.0:
			data.errors.append("%s needs speed, range and radius above 0" % label)
		if entry["pierce"] < 0 or entry["gravity"] < 0.0 or entry["homing"] < 0.0 or entry["aim_cone"] < 0.0 or entry["aim_cone"] > 180.0:
			data.errors.append("%s: pierce, gravity and homing must not be negative; aim_cone is 0-180 degrees" % label)
		data.projectiles[str(id)] = entry
	var areas: Dictionary = root.get("areas", {}) if typeof(root.get("areas", {})) == TYPE_DICTIONARY else {}
	for id in areas:
		if str(id).begins_with("_"):
			continue
		var raw = areas[id]
		var label := "areas.%s" % id
		if typeof(raw) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var entry := {
			"look": str(raw.get("look", "circle")),
			"radius": float(raw.get("radius", 1.5)),
			"delay": int(raw.get("delay", 60)),
			"active": int(raw.get("active", 3)),
			"height": float(raw.get("height", 2.0)),
			"range": float(raw.get("range", 9.0)),
			"aim_cone": float(raw.get("aim_cone", 60.0)),
			"guardable": bool(raw.get("guardable", false)),
		}
		if entry["radius"] <= 0.0 or entry["height"] <= 0.0 or entry["range"] <= 0.0 or entry["active"] < 1:
			data.errors.append("%s needs radius, height and range above 0 and active of at least 1" % label)
		if entry["delay"] < MIN_TELEGRAPH_STARTUP:
			data.errors.append("%s.delay must be at least %d ticks: the circle is its warning" % [label, MIN_TELEGRAPH_STARTUP])
		data.areas[str(id)] = entry


static func _check_move(move: Dictionary, label: String, data: CombatData) -> void:
	if move["advance"] < 0.0 or move["dive"] < 0.0:
		data.errors.append("%s.advance and dive must not be negative" % label)
	if move["dash_distance"] < 0.0 or move["dash_from"] < 0.0:
		data.errors.append("%s.dash_distance and dash_from must not be negative" % label)
	if move["dash_distance"] > 0.0 and move["dash_to"] <= move["dash_from"]:
		data.errors.append("%s moves the fighter forward: dash_to must be after dash_from" % label)
	if move["telegraph"] and move["startup"] < MIN_TELEGRAPH_STARTUP:
		data.errors.append("%s is a telegraphed move: its startup must be at least %d ticks so the player can react" % [label, MIN_TELEGRAPH_STARTUP])
	if move["cooldown"] < 0 or move["gauge_cost"] < 0.0 or move["energy_cost"] < 0.0:
		data.errors.append("%s.cooldown, gauge_cost and energy_cost must not be negative" % label)
	if move["invuln_from"] >= 0 and move["invuln_to"] <= move["invuln_from"]:
		data.errors.append("%s.invuln_to must be greater than invuln_from" % label)
	if move["startup"] < 1 or move["active"] < 1 or move["recovery"] < 0:
		data.errors.append("%s needs startup >= 1, active >= 1, recovery >= 0" % label)
	if move["power"] < 0.0 or (move["power"] == 0.0 and move["effects"].is_empty() and move["spawns"].is_empty()):
		data.errors.append("%s.power must be above 0 (0 is allowed only for a pure cast move that has effects or spawns)" % label)
	if move["grow_from"] <= 0.0 or move["grow_from"] > 1.0:
		data.errors.append("%s.grow_from must be above 0 and at most 1" % label)
	var size: Vector3 = move["hit_size"]
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		data.errors.append("%s.hit_size must be positive" % label)
	if move["knockback"] < 0.0 or move["launch"] < 0.0 or move["hitstun"] < 0 or move["hitstop"] < 0:
		data.errors.append("%s knockback, launch, hitstun and hitstop must not be negative" % label)


static func _parse_moves(root: Dictionary, data: CombatData) -> void:
	var moves := _dict(root, "moves", data)
	for id in moves:
		var label := "moves.%s" % id
		if typeof(moves[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var move := _normalize_move(moves[id], label, data)
		_check_move(move, label, data)
		data.moves[str(id)] = move
	for id in data.moves:
		for chain in ["on_light", "on_heavy"]:
			var target: String = data.moves[id][chain]
			if not target.is_empty() and not data.moves.has(target):
				data.errors.append("moves.%s.%s points to unknown move '%s'" % [id, chain, target])


## Reads data/combat/ultimates.json: which imported skill pack (art/skills/) every weapon type's
## ultimate uses, and the facts of each pack (hit times, range in body lengths, dash window, when
## locomotion is released). The file is generated from the packs by tools/skills/sync_ultimates.py.
## A missing or broken file is not fatal: the weapons keep the plain template ultimate.
static func _parse_ultimates(text: String, data: CombatData) -> void:
	if text.is_empty():
		if not FileAccess.file_exists(ULTIMATES_PATH):
			return
		text = FileAccess.get_file_as_string(ULTIMATES_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		data.errors.append("ultimates.json: top level must be an object")
		return
	var root: Dictionary = parsed
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		data.errors.append("ultimates.json: unsupported version (expected %d)" % SUPPORTED_VERSION)
	var knobs := {
		"body_length_m": float(root.get("body_length_m", 1.7)),
		"min_active_ticks": int(root.get("min_active_ticks", 6)),
		"dash_front_body_lengths": float(root.get("dash_front_body_lengths", 0.35)),
	}
	if knobs["body_length_m"] <= 0.0 or knobs["min_active_ticks"] < 1 or knobs["dash_front_body_lengths"] < 0.0:
		data.errors.append("ultimates.json: body_length_m and min_active_ticks must be above 0, dash_front_body_lengths 0 or more")
	var skills := {}
	var raw_skills: Dictionary = root.get("skills", {}) if typeof(root.get("skills")) == TYPE_DICTIONARY else {}
	for id in raw_skills:
		var label := "ultimates.skills.%s" % id
		if typeof(raw_skills[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var skill: Dictionary = (raw_skills[id] as Dictionary).duplicate(true)
		skill["id"] = str(id)
		var events: Array = skill.get("events", []) if typeof(skill.get("events")) == TYPE_ARRAY else []
		if events.is_empty():
			data.errors.append("%s needs at least one gameplay event" % label)
			continue
		var previous := -1.0
		for event in events:
			if typeof(event) != TYPE_DICTIONARY or not event.has("time_s") or not event.has("range_factor"):
				data.errors.append("%s.events need time_s and range_factor" % label)
				continue
			if float(event["time_s"]) < previous:
				data.errors.append("%s.events must be in time order" % label)
			previous = float(event["time_s"])
			if float(event["range_factor"]) <= 0.0 or float(event["range_factor"]) > 1.0:
				data.errors.append("%s.events range_factor must be above 0 and at most 1" % label)
		if float(skill.get("range_body_lengths", 0.0)) <= 0.0 or float(skill.get("duration_s", 0.0)) <= 0.0:
			data.errors.append("%s needs range_body_lengths and duration_s above 0" % label)
		if previous > float(skill.get("duration_s", 0.0)):
			data.errors.append("%s has a hit event after the clip ends" % label)
		if str(skill.get("caster_motion", "in_place")) == "forward_dash" and typeof(skill.get("dash")) != TYPE_DICTIONARY:
			data.errors.append("%s moves the caster forward but has no dash window" % label)
		skills[str(id)] = skill
	var defaults := {}
	var raw_defaults: Dictionary = root.get("defaults", {}) if typeof(root.get("defaults")) == TYPE_DICTIONARY else {}
	for weapon_type in raw_defaults:
		var chosen := str(raw_defaults[weapon_type])
		if not skills.has(chosen):
			data.errors.append("ultimates.defaults.%s: no skill pack called '%s'" % [weapon_type, chosen])
		elif str(skills[chosen]["weapon_type"]) != str(weapon_type):
			data.errors.append("ultimates.defaults.%s: '%s' belongs to weapon type %s" % [weapon_type, chosen, skills[chosen]["weapon_type"]])
		else:
			defaults[str(weapon_type)] = chosen
	for weapon_type in root.get("by_element", {}):
		for element in root["by_element"][weapon_type]:
			var chosen := str(root["by_element"][weapon_type][element])
			if not skills.has(chosen) or str(skills[chosen]["weapon_type"]) != str(weapon_type):
				data.errors.append("ultimates.by_element.%s.%s: '%s' is not a skill of that weapon type" % [weapon_type, element, chosen])
	data.ultimates = {"knobs": knobs, "skills": skills, "defaults": defaults, "by_element": root.get("by_element", {})}


## The move numbers a skill pack dictates, as frames of the 60 Hz simulation and metres:
## when it hits (startup), how long its hit window lasts (active, the traveling wave grows over it),
## how long the fighter is held afterwards (recovery, from the pack's locomotion release and blend
## out), the forward box, and the dash window for packs that carry the caster forward.
static func ultimate_numbers(skill: Dictionary, knobs: Dictionary) -> Dictionary:
	var body := float(knobs.get("body_length_m", 1.7))
	var events: Array = skill["events"]
	var first: Dictionary = events[0]
	var last: Dictionary = events[events.size() - 1]
	var startup := maxi(1, roundi(float(first["time_s"]) * 60.0))
	var active := maxi(int(knobs.get("min_active_ticks", 6)), roundi((float(last["time_s"]) - float(first["time_s"])) * 60.0) + 1)
	# The fighter is held until the last hit has landed and the pack releases locomotion (plus its
	# blend out); the effect keeps playing on its own after that (vfx_end_s).
	var hold := maxf(float(last["time_s"]), float(skill.get("locomotion_resume_s", 0.0))) + float(skill.get("blend_out_s", 0.1))
	var recovery := maxi(2, roundi(hold * 60.0) - startup - active)
	var near_m := float(skill.get("near_body_lengths", 0.05)) * body
	var far_m := float(skill["range_body_lengths"]) * body
	var height := float(skill.get("height_body_lengths", 1.0)) * body
	var numbers := {
		"startup": startup,
		"active": active,
		"recovery": recovery,
		"hit_offset": Vector3((near_m + far_m) * 0.5, height * 0.5, 0.0),
		"hit_size": Vector3(far_m - near_m, height, float(skill.get("width_body_lengths", 1.1)) * body),
		"grow_from": clampf(float(first["range_factor"]), 0.01, 1.0),
		"invuln_from": 0,
		"invuln_to": startup + active,
		"fixed_reach": true,
		"dash_distance": 0.0,
		"dash_from": 0.0,
		"dash_to": 0.0,
	}
	if typeof(skill.get("dash")) == TYPE_DICTIONARY:
		# The caster crosses the ground instead of sending a wave: it hits what it ran through, from
		# the point it cast at to a little past where it lands (the box is written behind the body,
		# which is where the cast origin is once the dash is over).
		var dash: Dictionary = skill["dash"]
		var run_m := float(dash["distance_body_lengths"]) * body
		var front_m := float(knobs.get("dash_front_body_lengths", 0.35)) * body
		numbers["dash_distance"] = run_m
		numbers["dash_from"] = roundi(float(dash["start_time_s"]) * 60.0)
		numbers["dash_to"] = maxi(roundi(float(dash["start_time_s"]) * 60.0) + 1, roundi(float(dash["end_time_s"]) * 60.0))
		numbers["hit_offset"] = Vector3((front_m - run_m) * 0.5, height * 0.5, 0.0)
		numbers["hit_size"] = Vector3(run_m + front_m, height, float(skill.get("width_body_lengths", 1.1)) * body)
		numbers["grow_from"] = 1.0  # the whole trail is live: the box sweeps with the body
	return numbers


## Builds every weapon's moves and style from the shared templates and the weapon's numbers.
static func _parse_weapons(text: String, data: CombatData) -> void:
	if text.is_empty():
		if not FileAccess.file_exists(WEAPONS_PATH):
			data.errors.append("weapons file not found: %s" % WEAPONS_PATH)
			return
		text = FileAccess.get_file_as_string(WEAPONS_PATH)
	var json := JSON.new()
	if json.parse(text) != OK:
		data.errors.append("weapons.json: invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		data.errors.append("weapons.json: top level must be an object")
		return
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		data.errors.append("weapons.json: unsupported version (expected %d)" % SUPPORTED_VERSION)

	var templates: Dictionary = {}
	var raw_templates: Dictionary = root.get("templates", {}) if typeof(root.get("templates")) == TYPE_DICTIONARY else {}
	for key in TEMPLATE_KEYS:
		if typeof(raw_templates.get(key)) != TYPE_DICTIONARY:
			data.errors.append("weapons.templates.%s is missing" % key)
			continue
		var label := "weapons.templates.%s" % key
		var template := _normalize_move(raw_templates[key], label, data)
		_check_move(template, label, data)
		for chain in ["on_light", "on_heavy"]:
			if not template[chain].is_empty() and not TEMPLATE_KEYS.has(template[chain]):
				data.errors.append("%s.%s points to unknown template '%s'" % [label, chain, template[chain]])
		templates[key] = template

	var weapons: Dictionary = root.get("weapons", {}) if typeof(root.get("weapons")) == TYPE_DICTIONARY else {}
	if weapons.is_empty():
		data.errors.append("weapons.weapons must list at least one weapon")
	for weapon_id in weapons:
		var label := "weapons.%s" % weapon_id
		if typeof(weapons[weapon_id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var weapon: Dictionary = weapons[weapon_id]
		var params := {}
		for number in WEAPON_NUMBERS:
			params[number] = float(weapon.get(number, 0.0))
			if params[number] <= 0.0:
				data.errors.append("%s.%s must be above 0" % [label, number])
		var overrides: Dictionary = weapon.get("overrides", {}) if typeof(weapon.get("overrides")) == TYPE_DICTIONARY else {}
		for key in overrides:
			if not TEMPLATE_KEYS.has(str(key)):
				data.errors.append("%s.overrides.%s is not one of the weapon's moves" % [label, key])
			elif typeof(overrides[key]) != TYPE_DICTIONARY:
				data.errors.append("%s.overrides.%s must be an object" % [label, key])
		var color: Variant = weapon.get("color", [1.0, 1.0, 1.0])
		if typeof(color) != TYPE_ARRAY or color.size() != 3:
			data.errors.append("%s.color must be [r, g, b]" % label)
			color = [1.0, 1.0, 1.0]

		var style := {}
		# Which imported skill pack this weapon type's ultimate shows and is timed to ("" = none,
		# e.g. the fists: they keep the plain template ultimate).
		var ultimate_skill := str(data.ultimates.get("defaults", {}).get(str(weapon_id), ""))
		for key in TEMPLATE_KEYS:
			if not templates.has(key):
				continue
			var move_label := "%s.%s" % [label, key]
			var move := _scale_template(templates[key], params, str(weapon_id))
			if key == "ultimate" and ultimate_skill != "":
				# The imported skill pack decides when the ultimate hits and how far it reaches;
				# the weapon's own overrides below can still change any of it.
				var numbers := ultimate_numbers(data.ultimates["skills"][ultimate_skill], data.ultimates["knobs"])
				for field in numbers:
					move[field] = numbers[field]
			var changes: Dictionary = overrides.get(key, {}) if typeof(overrides.get(key)) == TYPE_DICTIONARY else {}
			_apply_overrides(move, changes, move_label, data)
			_check_move(move, move_label, data)
			var move_id := "%s_%s" % [weapon_id, key]
			if data.moves.has(move_id):
				data.errors.append("%s: a move named '%s' already exists" % [label, move_id])
			data.moves[move_id] = move
		for entry in STYLE_FROM_TEMPLATE:
			style[entry] = "%s_%s" % [weapon_id, STYLE_FROM_TEMPLATE[entry]]
		data.styles[str(weapon_id)] = style
		data.weapons[str(weapon_id)] = {
			"name": str(weapon.get("name", weapon_id)),
			"summary": str(weapon.get("summary", "")),
			"skill_names": _skill_names(weapon, str(weapon_id), label, data),
			"color": Color(float(color[0]), float(color[1]), float(color[2])),
			"params": params,
			"ultimate_skill": ultimate_skill,
			"grounded_shots_only": bool(weapon.get("grounded_shots_only",false)),
		}
		if not bool(weapon.get("class_only", false)):  # class weapons are fighting styles for the squad only: no loot, no gear
			data.weapon_ids.append(str(weapon_id))


## The names shown when the weapon's special skill and ultimate are used (a missing one gets a plain default).
static func _skill_names(weapon: Dictionary, weapon_id: String, label: String, data: CombatData) -> Dictionary:
	var raw: Dictionary = weapon.get("skill_names", {}) if typeof(weapon.get("skill_names")) == TYPE_DICTIONARY else {}
	var names := {}
	for kind in ["special", "ultimate"]:
		var text := str(raw.get(kind, "")).strip_edges()
		if text.is_empty():
			text = "%s %s" % [str(weapon.get("name", weapon_id)), kind.capitalize()]
		names[kind] = text
	return names


## A weapon's version of a template move: the weapon's numbers scale it.
static func _scale_template(template: Dictionary, params: Dictionary, weapon_id: String) -> Dictionary:
	var move := template.duplicate(true)
	move["startup"] = maxi(1, roundi(float(template["startup"]) * params["speed"]))
	move["recovery"] = maxi(0, roundi(float(template["recovery"]) * params["speed"]))
	move["power"] = float(template["power"]) * params["power"]
	var offset: Vector3 = template["hit_offset"]
	var size: Vector3 = template["hit_size"]
	if not template["fixed_reach"]:  # (the ultimates reach the same 2 body lengths with every weapon)
		move["hit_offset"] = Vector3(offset.x * params["reach"], offset.y, offset.z)
		move["hit_size"] = Vector3(size.x * params["reach"], size.y, size.z * params["width"])
	move["knockback"] = float(template["knockback"]) * params["knockback"]
	move["launch"] = float(template["launch"]) * params["launch"]
	move["hitstun"] = roundi(float(template["hitstun"]) * params["stun"])
	move["energy_cost"] = float(template["energy_cost"]) * params["stamina"]
	for chain in ["on_light", "on_heavy"]:
		if not String(template[chain]).is_empty():
			move[chain] = "%s_%s" % [weapon_id, template[chain]]
	return move


## Replaces single fields of a generated move with the weapon's own absolute values.
static func _apply_overrides(move: Dictionary, changes: Dictionary, label: String, data: CombatData) -> void:
	for field in changes:
		if str(field).begins_with("_"):
			continue  # a note for people ("_comment")
		if not OVERRIDE_FIELDS.has(str(field)):
			data.errors.append("%s.%s cannot be overridden" % [label, field])
		elif VECTOR_FIELDS.has(str(field)):
			move[field] = _vec3(changes[field], "%s.%s" % [label, field], data)
		elif str(field) == "spawns":
			move[field] = _normalize_spawns({"spawns":changes[field],"startup":move.startup},label,data)
		elif str(field) in ["on_light","on_heavy"]:
			move[field] = str(changes[field])
		elif str(field) == "effects":
			move[field] = _normalize_effect_entries(changes[field], label, data)
		elif INT_FIELDS.has(str(field)):
			move[field] = int(changes[field])
		elif FLOAT_FIELDS.has(str(field)):
			move[field] = float(changes[field])
		else:
			move[field] = bool(changes[field])


static func _parse_styles(root: Dictionary, data: CombatData) -> void:
	var styles := _dict(root, "styles", data)
	for id in styles:
		if data.styles.has(str(id)):
			data.errors.append("styles.%s clashes with a weapon of the same name" % id)
			continue
		if typeof(styles[id]) != TYPE_DICTIONARY:
			data.errors.append("styles.%s must be an object" % id)
			continue
		var entry := {}
		for key in STYLE_ENTRIES:
			var move_id := str(styles[id].get(key, ""))
			if not data.moves.has(move_id):
				data.errors.append("styles.%s.%s must name an existing move" % [id, key])
			entry[key] = move_id
		for key in OPTIONAL_STYLE_ENTRIES:
			if styles[id].has(key):
				var move_id := str(styles[id][key])
				if not data.moves.has(move_id):
					data.errors.append("styles.%s.%s must name an existing move" % [id, key])
				entry[key] = move_id
		data.styles[str(id)] = entry
	if data.styles.is_empty():
		data.errors.append("styles must list at least one style")


static func _parse_enemies(root: Dictionary, data: CombatData) -> void:
	var enemies := _dict(root, "enemies", data)
	for id in enemies:
		var label := "enemies.%s" % id
		if typeof(enemies[id]) != TYPE_DICTIONARY:
			data.errors.append("%s must be an object" % label)
			continue
		var raw: Dictionary = enemies[id]
		var style := str(raw.get("style", ""))
		if not data.styles.has(style):
			data.errors.append("%s.style '%s' is not a known style" % [label, style])
		var stats: Dictionary = raw.get("stats", {}) if typeof(raw.get("stats")) == TYPE_DICTIONARY else {}
		for stat in stats:
			if not STAT_NAMES.has(str(stat)):
				data.errors.append("%s.stats.%s is not a known stat" % [label, stat])
		var ai: Dictionary = raw.get("ai", {}) if typeof(raw.get("ai")) == TYPE_DICTIONARY else {}
		var cooldown_min := int(ai.get("cooldown_min", 60))
		var cooldown_max := int(ai.get("cooldown_max", 90))
		if cooldown_min < 1 or cooldown_max < cooldown_min:
			data.errors.append("%s.ai needs 1 <= cooldown_min <= cooldown_max" % label)
		var attack_input := str(ai.get("attack_input", "light"))
		if not ["light", "heavy", "special"].has(attack_input):
			data.errors.append("%s.ai.attack_input must be light, heavy or special" % label)
		var skill_chance := int(ai.get("skill_chance", 0))
		if skill_chance < 0 or skill_chance > 100:
			data.errors.append("%s.ai.skill_chance must be between 0 and 100" % label)
		elif skill_chance > 0 and data.styles.has(style) and not data.styles[style].has("special"):
			data.errors.append("%s.ai.skill_chance needs a style with a special skill" % label)
		var poise := float(raw.get("poise", 0.0))
		if poise < 0.0:
			data.errors.append("%s.poise must not be negative" % label)
		var color: Variant = raw.get("color", [0.75, 0.3, 0.3])
		if typeof(color) != TYPE_ARRAY or color.size() != 3:
			data.errors.append("%s.color must be [r, g, b]" % label)
			color = [0.75, 0.3, 0.3]
		var model := str(raw.get("model", ""))
		if model != "" and not (model.begins_with("res://") and model.ends_with(".glb")):
			data.errors.append("%s.model must be a res://....glb path" % label)
		var model_height := float(raw.get("model_height", 1.8))
		if model_height <= 0.0:
			data.errors.append("%s.model_height must be above 0" % label)
		var body_height := float(raw.get("body_height", SimBody.HEIGHT))
		if body_height <= 0.0:
			data.errors.append("%s.body_height must be above 0" % label)
		var tint: Variant = raw.get("model_tint", [1.0, 1.0, 1.0])
		if typeof(tint) != TYPE_ARRAY or tint.size() != 3:
			data.errors.append("%s.model_tint must be [r, g, b]" % label)
			tint = [1.0, 1.0, 1.0]
		var flee_hp := float(ai.get("flee_hp", 0.0))
		if flee_hp < 0.0 or flee_hp >= 1.0:
			data.errors.append("%s.ai.flee_hp must be a fraction from 0 to below 1" % label)
		var flee_ticks := int(ai.get("flee_ticks", 0))
		if flee_ticks < 0:
			data.errors.append("%s.ai.flee_ticks must not be negative" % label)
		var keep_range := float(ai.get("keep_range", 0.0))
		var escape_input := str(ai.get("escape_input", ""))
		if keep_range < 0.0 or float(ai.get("retreat_range", 0.0)) < 0.0 or float(ai.get("strafe", 0.0)) < 0.0:
			data.errors.append("%s.ai keep_range, retreat_range and strafe must not be negative" % label)
		if keep_range > 0.0 and float(ai.get("retreat_range", 0.0)) >= keep_range:
			data.errors.append("%s.ai.retreat_range must be below keep_range" % label)
		if not ["", "light", "heavy", "special"].has(escape_input):
			data.errors.append("%s.ai.escape_input must be light, heavy, special or empty" % label)
		var animations := str(raw.get("animations", ""))
		if animations != "" and not (animations.begins_with("res://") and animations.ends_with(".glb")):
			data.errors.append("%s.animations must be a res://....glb path" % label)
		var clips := {}
		if typeof(raw.get("clips", {})) != TYPE_DICTIONARY:
			data.errors.append("%s.clips must be an object (move id -> clip name)" % label)
		else:
			for move_id in raw.get("clips", {}):
				if not data.moves.has(str(move_id)):
					data.errors.append("%s.clips.%s is not a known move" % [label, move_id])
				clips[str(move_id)] = str(raw["clips"][move_id])
		var standin_clips := {}
		for move_id in raw.get("standin_clips", {}) if typeof(raw.get("standin_clips", {})) == TYPE_DICTIONARY else {}:
			if not data.moves.has(str(move_id)):
				data.errors.append("%s.standin_clips.%s is not a known move" % [label, move_id])
			standin_clips[str(move_id)] = str(raw["standin_clips"][move_id])
		var retreat_ticks := int(ai.get("retreat_ticks", 0))
		if retreat_ticks < 0:
			data.errors.append("%s.ai.retreat_ticks must not be negative" % label)
		# "looks": how it is drawn, best first ({"model", "animations", "clips", "model_tint"}). The first
		# whose model file exists replaces the plain fields, so a monster whose own model is still being
		# made shows a stand-in until the file lands, and switches by itself after. Only the picture
		# changes: its rules (body_height, moves) do not depend on which look is used.
		var looks: Variant = raw.get("looks", [])
		if typeof(looks) != TYPE_ARRAY:
			data.errors.append("%s.looks must be a list" % label)
			looks = []
		var look_label := ""
		for index in looks.size():
			var look = looks[index]
			var where := "%s.looks[%d]" % [label, index]
			if typeof(look) != TYPE_DICTIONARY or not str(look.get("model", "")).begins_with("res://") or not str(look.get("model", "")).ends_with(".glb"):
				data.errors.append("%s needs a res://....glb model" % where)
				continue
			for move_id in look.get("clips", {}):
				if not data.moves.has(str(move_id)):
					data.errors.append("%s.clips.%s is not a known move" % [where, move_id])
			if look_label == "" and ResourceLoader.exists(str(look["model"])):
				look_label = where
				model = str(look["model"])
				animations = str(look.get("animations", ""))
				clips = {}
				for move_id in look.get("clips", {}):
					clips[str(move_id)] = str(look["clips"][move_id])
				if look.has("model_tint") and typeof(look["model_tint"]) == TYPE_ARRAY and look["model_tint"].size() == 3:
					tint = look["model_tint"]
				else:
					tint = [1.0, 1.0, 1.0]
		var run_clip_speed := float(raw.get("run_clip_speed", 0.0))
		if run_clip_speed < 0.0:
			data.errors.append("%s.run_clip_speed must not be negative (0 = use the default monster run reference)" % label)
		data.enemies[str(id)] = {
			"role": str(raw.get("role", "")),
			"style": style,
			"color": Color(float(color[0]), float(color[1]), float(color[2])),
			"model": model,
			"model_height": model_height,
			"run_clip_speed": run_clip_speed,  ## m/s its run/walk clip looks natural at (rig size, before model scale); 0 = use the default monster run reference
			"animations": animations,
			"body_height": body_height if body_height > 0.0 else SimBody.HEIGHT,
			"model_tint": Color(float(tint[0]), float(tint[1]), float(tint[2])),
			"look": look_label,  ## which entry of "looks" is drawn ("" = the plain fields)
			"standin_clips": standin_clips,  ## move id -> clip played while the set lacks the move's own clip
			"nock_mesh": str(raw.get("nock_mesh", "")),  ## a model mesh shown only while a firing move winds up
			"clips": clips,
			"stats": data.full_stats(stats),
			"poise": poise,
			"ai": {
				"attack_range": float(ai.get("attack_range", 1.3)),
				"attack_min_range": float(ai.get("attack_min_range", 0.0)),
				"wait_range": float(ai.get("wait_range", 3.0)),
				"attack_input": attack_input,
				"cooldown_min": cooldown_min,
				"cooldown_max": cooldown_max,
				"skill_chance": skill_chance,
				"retreat_ticks": maxi(retreat_ticks, 0),
				"flee_hp": clampf(flee_hp, 0.0, 0.99),
				"flee_ticks": maxi(flee_ticks, 0),
				"keep_range": maxf(keep_range, 0.0),
				"retreat_range": float(ai.get("retreat_range", 0.0)),
				"strafe": float(ai.get("strafe", 0.0)),
				"escape_input": escape_input,
				"escape_range": float(ai.get("escape_range", 0.0)),
				"escape_cooldown": int(ai.get("escape_cooldown", 300)),
			},
		}


static func _parse_coop(root: Dictionary, data: CombatData) -> void:
	if not root.has("coop"):
		return  # old/custom solo data remains compatible
	if not root["coop"] is Dictionary:
		data.errors.append("coop must be an object")
		return
	var raw: Dictionary = root["coop"]
	var clean := {}
	for key in ["max_players", "spawn_spacing", "downed_ticks", "revive_ticks", "revive_radius", "revive_hp_fraction", "revive_invulnerable_ticks"]:
		var value = raw.get(key)
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0:
			data.errors.append("coop.%s must be a positive number" % key)
			return
		clean[key] = float(value)
	for key in ["max_players", "downed_ticks", "revive_ticks", "revive_invulnerable_ticks"]:
		if clean[key] != floorf(clean[key]):
			data.errors.append("coop.%s must be whole ticks/count" % key)
			return
		clean[key] = int(clean[key])
	if clean["max_players"] < 2 or clean["max_players"] > 4 or clean["revive_hp_fraction"] > 1.0 or clean["revive_ticks"] >= clean["downed_ticks"]:
		data.errors.append("coop count, HP fraction or revive/bleedout timing is invalid")
		return
	var multipliers = raw.get("hp_multiplier")
	if not multipliers is Array or multipliers.size() != clean["max_players"]:
		data.errors.append("coop.hp_multiplier must contain one entry per party size")
		return
	var previous := 1.0
	for value in multipliers:
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < previous:
			data.errors.append("coop.hp_multiplier must be finite, >=1 and nondecreasing")
			return
		previous = float(value)
	if float(multipliers[0]) != 1.0:
		data.errors.append("coop.hp_multiplier solo entry must be 1")
		return
	clean["hp_multiplier"] = multipliers.duplicate()
	data.coop = clean
