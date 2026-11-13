extends RefCounted
## Device-local presentation preferences; never affects authoritative combat rules.
const PATH := "user://graphics.cfg"
const SCALES := [0.5, 0.75, 1.0]
static var revision := 0
static var _loaded := false
static var _values := {"ultimate_vfx": true, "combat_vfx": true, "ultimate_camera": true,
	"outline": true, "shadows": true, "decorative_lights": true, "fog": true, "glow": true,
	"render_scale": 0.5, "antialiasing": 2, "drawn_style": "on"}
## Drawn (ink-and-wash) battle look, client/draw_style/draw_style.gd (Boss 2026-11-13 picked ink_c):
## "on" = materials + screen pass (screen pass only at render scale 0.5 and not on a slow device), "lite" = materials
## only, "off" = the old look.
const DRAWN_STYLES := ["off", "lite", "on"]

static func enabled(key: String) -> bool:
	_load_once()
	return bool(_values.get(key, true))

static func value(key: String) -> Variant:
	_load_once()
	return _values.get(key)

static func set_enabled(key: String, on: bool) -> void:
	set_value(key, on)

static func set_value(key: String, new_value: Variant) -> void:
	_load_once()
	if not _valid(key, new_value): return
	_values[key] = new_value
	revision += 1
	var config := ConfigFile.new()
	for id in _values: config.set_value("graphics", id, _values[id])
	config.set_value("graphics", "preset_version", 3)
	config.save(PATH)

static func snapshot() -> Dictionary:
	_load_once()
	return _values.duplicate()

static func _valid(key: String, candidate: Variant) -> bool:
	if not _values.has(key): return false
	if key == "render_scale": return candidate is float and candidate in SCALES
	if key == "antialiasing": return candidate is int and candidate in [0, 2, 4]
	if key == "drawn_style": return candidate is String and candidate in DRAWN_STYLES
	return candidate is bool

static func _load_once() -> void:
	if _loaded: return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	var preset_version := int(config.get_value("graphics", "preset_version", 0))
	var saved_scale: Variant = config.get_value("graphics", "render_scale", 0.5)
	for id in _values:
		var saved: Variant = config.get_value("graphics", id, _values[id])
		if _valid(id, saved): _values[id] = saved
	# Preserve the selected tier while migrating its approved resolution percentage.
	if preset_version < 3:
		if preset_version == 2 and saved_scale is float:
			if is_equal_approx(saved_scale, 0.85): _values["render_scale"] = 0.75
			elif is_equal_approx(saved_scale, 1.0): _values["render_scale"] = 1.0
			else: _values["render_scale"] = 0.5
		else:
			_values["render_scale"] = 0.5
		for id in _values: config.set_value("graphics", id, _values[id])
		config.set_value("graphics", "preset_version", 3)
		config.save(PATH)
