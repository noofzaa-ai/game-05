extends RefCounted
## Loads the enemy health-bar styles (data/ui/enemy_bars.json) and resolves a map + enemy tier to a
## concrete style the floating bar (fighter_view.gd) and the HUD boss bar (hud.gd) draw. The styles
## are data (frame shape, colours, the notch mark); the only code decision is "which style this map
## uses" and "which tier this enemy is", both read from the file. A null colour in the file means
## "use the matching InkUi token", so an unthemed map keeps the live look and a chosen theme still
## drives the frame.
## It is pure presentation, so it lives in client/ (logic/ never decides how a bar looks).
## EXTENDING: a new map's look is one entry in `by_map` (or a new named style); a new enemy tier is
## one entry in `tiers` plus a `base`/`elite`/`boss` block.

const InkUi := preload("res://client/ink_ui.gd")

const PATH := "res://data/ui/enemy_bars.json"
## Which InkUi token stands in for each null colour in the file (so themes drive the default brass).
const TOKEN_FALLBACK := {
	"frame": "ORNAMENT", "back": "HUD_PANEL", "fill": "HP", "fill_low": "HP_LOW",
	"trail": "HP_TRAIL", "outline": "HUD_OUTLINE", "low_flash": "HP_LOW",
}
## Every key a resolved style has, so callers can trust the shape.
const KEYS := ["frame_shape", "frame", "back", "fill", "fill_low", "trail", "outline", "low_flash", "mark"]

var errors: Array[String] = []
var _styles: Dictionary = {}  ## name -> raw style dict (with base + optional elite/boss blocks)
var _by_map: Dictionary = {}
var _by_atmosphere: Dictionary = {}
var _tiers: Dictionary = {}  ## enemy type -> "elite" / "boss"
var _default := "brass"


## Loads the default file and returns self. A broken file leaves `errors` filled in and resolve()
## still returns a safe brass fallback. Use `EnemyBars.new().load_default()`.
func load_default() -> RefCounted:
	_load(PATH)
	return self


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		errors.append("enemy bar file not found: %s" % path)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("enemy bars: invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("enemy bars: top level must be an object")
		return
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != 1:
		errors.append("enemy bars: unsupported version (expected 1)")
	var styles: Variant = root.get("styles", {})
	if typeof(styles) != TYPE_DICTIONARY or styles.is_empty():
		errors.append("enemy bars: 'styles' must be a non-empty object")
	else:
		_styles = styles
	_by_map = root.get("by_map", {}) if typeof(root.get("by_map")) == TYPE_DICTIONARY else {}
	_by_atmosphere = root.get("by_atmosphere", {}) if typeof(root.get("by_atmosphere")) == TYPE_DICTIONARY else {}
	_tiers = root.get("tiers", {}) if typeof(root.get("tiers")) == TYPE_DICTIONARY else {}
	_default = str(root.get("default", "brass"))
	if not _styles.has(_default):
		errors.append("enemy bars: default style '%s' is not defined" % _default)
	# Every mapping must point at a real style (caught early, not at draw time).
	for table_name in [["by_map", _by_map], ["by_atmosphere", _by_atmosphere]]:
		for key in table_name[1]:
			if not _styles.has(str(table_name[1][key])):
				errors.append("enemy bars: %s['%s'] -> unknown style '%s'" % [table_name[0], key, table_name[1][key]])


func is_valid() -> bool:
	return errors.is_empty()


## The style name a map uses: its id first, then its atmosphere, then the default.
func style_name_for(map_id: String, atmosphere: String) -> String:
	if _by_map.has(map_id):
		return str(_by_map[map_id])
	if _by_atmosphere.has(atmosphere):
		return str(_by_atmosphere[atmosphere])
	return _default


## The bar tier an enemy type draws in: "base", "elite" or "boss".
func tier_for(enemy_type: String, is_boss: bool = false) -> String:
	if is_boss:
		return "boss"
	return str(_tiers.get(enemy_type, "base"))


## A concrete style for a map + tier: every KEY present, colours resolved (null -> InkUi token),
## the elite/boss block merged over the base. `tier` is "base", "elite" or "boss".
func resolve(map_id: String, atmosphere: String, tier: String = "base") -> Dictionary:
	var raw: Dictionary = _styles.get(style_name_for(map_id, atmosphere), {})
	var merged := {}
	for key in raw:
		if key != "elite" and key != "boss" and not str(key).begins_with("_"):
			merged[key] = raw[key]
	if tier != "base" and typeof(raw.get(tier)) == TYPE_DICTIONARY:
		for key in raw[tier]:
			if not str(key).begins_with("_"):
				merged[key] = raw[tier][key]
	var out := {}
	out["frame_shape"] = str(merged.get("frame_shape", "plain"))
	out["mark"] = str(merged.get("mark", "none"))
	for key in TOKEN_FALLBACK:
		out[key] = _color(merged.get(key), TOKEN_FALLBACK[key])
	return out


## An RGBA array -> Color; null (or missing) -> the named InkUi token (read from the script, since
## the tokens are static vars a theme can swap).
static func _color(value: Variant, token: String) -> Color:
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
	var script: Script = load("res://client/ink_ui.gd")
	return script.get(token)
