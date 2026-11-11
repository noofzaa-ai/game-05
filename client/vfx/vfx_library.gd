extends RefCounted
## Reads data/combat/vfx.json: what every combat action LOOKS like. Pure data (no nodes), so it can
## be tested headless; client/effects.gd draws what this hands out. The rules never read this file.
## Also decides which effect keys an action plays (fallbacks from a move id to its kind to a default),
## which is presentation only: the simulation has already decided what happened.
## EXTENDING: a new layer type needs an entry in LAYER_TYPES here and a builder in client/effects.gd.

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")

const DATA_PATH := "res://data/combat/vfx.json"
const SUPPORTED_VERSION := 1
const LAYER_TYPES: Array[String] = ["trail", "sprite", "ground", "burst", "ghosts", "shake", "punch", "flash"]
const TRAIL_SHAPES: Array[String] = ["arc", "thrust", "ring"]
const SPRITE_MODES: Array[String] = ["glow", "star", "splat", "ring", "beam", "swirl", "ghost", "cross", "bolt", "flame"]  ## index = shader mode
const GROUND_MODES: Array[String] = ["ring", "crack", "stain", "glyph"]  ## index = shader mode
const BURST_STYLES: Array[String] = ["streak", "puff", "mote"]  ## index = shader style
const BURST_DIRS: Array[String] = ["up", "down", "forward", "back", "none"]
const BILLBOARDS: Array[String] = ["ground", "camera", "y", "axis"]  ## index = shader billboard (0 = as placed, 3 = turns round its own long axis)
const ANCHORS: Array[String] = ["at", "feet", "chest", "hitbox", "end"]
const MAX_BURST := 32  ## particles one burst mesh holds
## Keys the stage plays for things that are not moves (every one must exist in the data).
const EVENT_KEYS: Array[String] = [
	"hit", "hit/heavy", "hit/crit", "hit/launch", "hit/knockback", "hit/armored", "block", "guard_break",
	"poise_break", "dodge", "run_dust", "land", "knockdown", "getup", "death", "loot", "rest", "swing/default",
	"status/buff", "status/debuff",
	"skill_hit/1", "skill_hit/2", "skill_hit/3", "skill_hit/crit", "skill_hit/tick", "skill_dot",
	"skill_impact/1", "skill_impact/2", "skill_impact/3", "skill_impact/crit",
]
## Optional per-skill keys (client/stage_view.gd): 'skill_cast/<skill id>' on the caster when the cast starts,
## 'skill_burst/<skill id>' where the skill's own visual lands (a burst or a beam: ctx "end" = the beam's far end),
## 'skill_trail/<skill id>' sparks left behind a flying projectile or along a ground zone (client/skills/presenter.gd),
## 'skill_struck/<skill id>' on every target the skill hits.

var palette: Dictionary = {}  ## name -> Color
var hit_rules: Dictionary = {}
var skill_colors: Dictionary = {}  ## skill id -> Color (what 'weapon' means in skill_* keys)
var actions: Dictionary = {}  ## key -> Array of layer Dictionaries (with "base" already expanded)
var errors: Array[String] = []


static func load_default():
	if not FileAccess.file_exists(DATA_PATH):
		var missing = new()
		missing.errors.append("vfx file not found: %s" % DATA_PATH)
		return missing
	return parse(FileAccess.get_file_as_string(DATA_PATH))


static func parse(text: String):
	var lib = new()
	var json := JSON.new()
	if json.parse(text) != OK:
		lib.errors.append("vfx: invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return lib
	if typeof(json.data) != TYPE_DICTIONARY:
		lib.errors.append("vfx: top level must be an object")
		return lib
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		lib.errors.append("vfx: unsupported version (expected %d)" % SUPPORTED_VERSION)
	var raw_palette = root.get("palette", {})
	if typeof(raw_palette) == TYPE_DICTIONARY:
		for name in raw_palette:
			if typeof(raw_palette[name]) == TYPE_STRING and Color.html_is_valid(raw_palette[name]):
				lib.palette[name] = Color.html(raw_palette[name])
			else:
				lib.errors.append("vfx: palette '%s' is not a #rrggbb color" % name)
	if not lib.palette.has("ink"):
		lib.palette["ink"] = Color(0.06, 0.05, 0.08)
	lib.hit_rules = {"damage_reference": 120.0, "scale_min": 0.6, "scale_max": 2.4, "heavy_power": 1.8, "knockback_min": 9.0}
	var raw_rules = root.get("hit_rules", {})
	if typeof(raw_rules) == TYPE_DICTIONARY:
		for key in raw_rules:
			lib.hit_rules[key] = float(raw_rules[key])
	var raw_skill_colors = root.get("skill_colors", {})
	if typeof(raw_skill_colors) == TYPE_DICTIONARY:
		for skill in raw_skill_colors:
			var name := str(raw_skill_colors[skill])
			if lib.palette.has(name) or Color.html_is_valid(name):
				lib.skill_colors[skill] = lib.palette.get(name, Color.html(name) if Color.html_is_valid(name) else Color.WHITE)
			else:
				lib.errors.append("vfx: skill_colors '%s' is not a palette name or #rrggbb" % skill)
	var raw_actions = root.get("actions", {})
	if typeof(raw_actions) != TYPE_DICTIONARY:
		lib.errors.append("vfx: 'actions' must be an object")
		return lib
	for key in raw_actions:
		var layers := lib._expand(raw_actions, key, [])
		lib.actions[key] = layers
		for i in layers.size():
			lib._check_layer(key, i, layers[i])
	for key in EVENT_KEYS:
		if not lib.actions.has(key):
			lib.errors.append("vfx: the action '%s' is missing" % key)
	return lib


func is_valid() -> bool:
	return errors.is_empty()


func has(key: String) -> bool:
	return actions.has(key)


func layers(key: String) -> Array:
	return actions.get(key, [])


## The kind of a move id ("hammer_run_heavy" -> "run_heavy"), or "" for monsters' own moves.
## The longest kind wins, so "_run_heavy" is not taken for "_heavy".
static func move_kind(move_id: String) -> String:
	var found := ""
	for kind in CombatDataLoader.TEMPLATE_KEYS:
		if move_id.ends_with("_" + kind) and kind.length() > found.length():
			found = kind
	return found


## The key a move's swing plays: 'swing/<move id>', else 'swing/<kind>', else 'swing/default'.
func swing_key(move_id: String) -> String:
	var key := _specific("swing", move_id)
	return key if not key.is_empty() else "swing/default"


## The key played when a move starts (skills, telegraphed monster moves), or "" for none.
func windup_key(move_id: String) -> String:
	return _specific("windup", move_id)


## The key played when a diving move touches the ground, or "".
func land_key(move_id: String) -> String:
	return _specific("land", move_id)


## Every key a landed hit plays, in order (see hit_rules in the data).
## `knockback` is the move's knockback number from the combat data.
func hit_keys(move_id: String, power: float, crit: bool, launched: bool, armored: bool, knockback: float) -> Array[String]:
	var keys: Array[String] = ["hit"]
	if power >= float(hit_rules["heavy_power"]):
		keys.append("hit/heavy")
	if crit:
		keys.append("hit/crit")
	if armored:
		keys.append("hit/armored")
	elif launched:
		keys.append("hit/launch")
	elif knockback >= float(hit_rules["knockback_min"]):
		keys.append("hit/knockback")
	var own := _specific("hit", move_id)  # (a heavy attack's kind is "heavy": hit/heavy, already in)
	if not own.is_empty() and not own in keys:
		keys.append(own)
	return keys


## How much a hit's "scale": true layers grow: damage over the reference, clamped.
func hit_scale(damage: float) -> float:
	return clampf(damage / maxf(float(hit_rules["damage_reference"]), 1.0), float(hit_rules["scale_min"]), float(hit_rules["scale_max"]))


## Keys drawn on a target struck by a skill-tree skill. `tier` comes from the rules (0-3),
## `periodic` = ground-zone / totem ticks (small sparks only).
func skill_hit_keys(tier: int, crit: bool, periodic: bool) -> Array[String]:
	var keys: Array[String] = []
	if periodic:
		keys.append("skill_hit/tick")
	elif tier > 0:
		keys.append("skill_hit/%d" % clampi(tier, 1, 3))
	if crit and not periodic:
		keys.append("skill_hit/crit")
	return keys


## Camera-only keys (shake / punch / flash) for the strongest skill blow of a frame.
func skill_impact_keys(tier: int, crit: bool) -> Array[String]:
	var keys: Array[String] = []
	if tier > 0:
		keys.append("skill_impact/%d" % clampi(tier, 1, 3))
	if crit:
		keys.append("skill_impact/crit")
	return keys


## The color 'weapon' means for a skill's hit keys (falls back to `fallback`).
func skill_color(skill_id: String, fallback: Color) -> Color:
	return skill_colors.get(skill_id, fallback)


## The key a status effect plays: 'status/<control>' (stun, shock, sleep) else 'status/<kind>'.
func status_key(control: String, kind: String) -> String:
	if not control.is_empty() and actions.has("status/" + control):
		return "status/" + control
	return "status/" + kind if actions.has("status/" + kind) else ""


## A layer's color: a palette name, 'weapon' (= `weapon_color`), '#rrggbb' or [r, g, b(, a)].
func color_of(value, weapon_color: Color) -> Color:
	if typeof(value) == TYPE_ARRAY:
		var parts: Array = value
		return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
	var name := str(value)
	if name == "weapon":
		return weapon_color
	if palette.has(name):
		return palette[name]
	if name.begins_with("#") and Color.html_is_valid(name):
		return Color.html(name)
	return Color.WHITE


func _specific(prefix: String, move_id: String) -> String:
	if actions.has(prefix + "/" + move_id):
		return prefix + "/" + move_id
	var kind := move_kind(move_id)
	if not kind.is_empty() and actions.has(prefix + "/" + kind):
		return prefix + "/" + kind
	return ""


func _expand(raw: Dictionary, key: String, seen: Array) -> Array:
	var entry = raw.get(key)
	if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("layers")) != TYPE_ARRAY:
		errors.append("vfx: '%s' needs a 'layers' list" % key)
		return []
	var result: Array = []
	if entry.has("base"):
		var base := str(entry["base"])
		if base in seen or not raw.has(base):
			errors.append("vfx: '%s' has a bad base '%s'" % [key, base])
		else:
			result.append_array(_expand(raw, base, seen + [key]))
	for layer in entry["layers"]:
		if typeof(layer) == TYPE_DICTIONARY:
			result.append(layer)
		else:
			errors.append("vfx: '%s' has a layer that is not an object" % key)
	return result


func _check_layer(key: String, index: int, layer: Dictionary) -> void:
	var where := "vfx: '%s' layer %d" % [key, index]
	var type := str(layer.get("type", ""))
	if not type in LAYER_TYPES:
		errors.append("%s has an unknown type '%s'" % [where, type])
		return
	if layer.has("anchor") and not str(layer["anchor"]) in ANCHORS:
		errors.append("%s has an unknown anchor '%s'" % [where, layer["anchor"]])
	if layer.has("color") and not _color_ok(layer["color"]):
		errors.append("%s has an unknown color '%s'" % [where, layer["color"]])
	if type in ["trail", "sprite", "ground", "burst", "ghosts", "flash"] and float(layer.get("seconds", 0.0)) <= 0.0:
		errors.append("%s needs seconds > 0" % where)
	match type:
		"trail":
			if not str(layer.get("shape", "")) in TRAIL_SHAPES:
				errors.append("%s has an unknown shape '%s'" % [where, layer.get("shape")])
		"sprite":
			if not str(layer.get("mode", "")) in SPRITE_MODES:
				errors.append("%s has an unknown mode '%s'" % [where, layer.get("mode")])
			if layer.has("billboard") and not str(layer["billboard"]) in BILLBOARDS:
				errors.append("%s has an unknown billboard '%s'" % [where, layer["billboard"]])
			if bool(layer.get("link", false)) and str(layer.get("billboard", "axis")) != "axis":
				errors.append("%s: a link sprite turns round its own axis (billboard 'axis')" % where)
		"ground":
			if not str(layer.get("mode", "")) in GROUND_MODES:
				errors.append("%s has an unknown mode '%s'" % [where, layer.get("mode")])
		"burst":
			if not str(layer.get("style", "")) in BURST_STYLES:
				errors.append("%s has an unknown style '%s'" % [where, layer.get("style")])
			if not str(layer.get("dir", "up")) in BURST_DIRS:
				errors.append("%s has an unknown dir '%s'" % [where, layer.get("dir")])
			if int(layer.get("count", 0)) < 1 or int(layer.get("count", 0)) > MAX_BURST:
				errors.append("%s needs a count of 1-%d" % [where, MAX_BURST])
		"flash":
			if not layer.has("color"):
				errors.append("%s needs a color" % where)
	for field in ["size", "rise"]:
		if field == "size" and not type in ["sprite", "ground"]:
			continue  # (a burst's or afterimage's size is one number)
		if layer.has(field) and (typeof(layer[field]) != TYPE_ARRAY or (layer[field] as Array).size() != 2):
			errors.append("%s: '%s' must be [from, to]" % [where, field])


func _color_ok(value) -> bool:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).size() >= 3
	var name := str(value)
	return name == "weapon" or palette.has(name) or (name.begins_with("#") and Color.html_is_valid(name))
