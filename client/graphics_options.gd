extends RefCounted
## Device-local presentation preferences; never affects authoritative combat rules.
##
## Defaults per device class (Boss 2026-11-18, iPhone 27-30 fps in a goblin solo fight): a PHONE starts with the sun
## shadow off, MSAA off and drawn style "lite" (stage ink materials, no screen pass; client/draw_style/draw_style.gd
## also drops the hero ink hulls while that "lite" is the automatic phone default). Desktop and tablets keep
## DESKTOP_DEFAULTS. A value the player picks in the graphics panel is remembered as the player's choice (CHOSEN_KEY)
## and always wins over the device default; a value never picked follows the device class.
## Slow device (draw_style.gd begin_battle, a remembered battle median below SLOW_FPS): shadows and MSAA are off too
## (SLOW_OFF), unless the player chose them.
## Frame cap (Boss 2026-11-19, the iPhone ran 20-30 fps while charging, with stalls that grew as it warmed up): a phone
## renders at most PHONE_DEFAULTS.frame_cap (30) frames a second (Engine.max_fps, applied by client/graphics_runtime.gd). The fight's
## rules do not depend on it: physics and netfox tick at their own fixed 60 Hz and catch up (2 ticks per 30 fps frame).
const PATH := "user://graphics.cfg"
const PRESET_VERSION := 4  ## 4: only the player's choices count as fixed (CHOSEN_KEY); older files are migrated
const CHOSEN_KEY := "chosen"  ## [graphics] chosen = the option ids the player picked (the rest follow the device)
const SCALES := [0.5, 0.75, 1.0]
const DESKTOP_DEFAULTS := {"ultimate_vfx": true, "combat_vfx": true, "ultimate_camera": true,
	"outline": true, "metal_glint": true, "shadows": true, "decorative_lights": true, "fog": true, "glow": true,
	"render_scale": 0.5, "antialiasing": 2, "drawn_style": "on", "frame_cap": 0}
const PHONE_DEFAULTS := {"shadows": false, "antialiasing": 0, "drawn_style": "lite", "frame_cap": 30}  ## over DESKTOP_DEFAULTS
const FRAME_CAPS := [30, 0]  ## frames per second; 0 = unlimited (the display's own rate)
const SLOW_OFF := {"shadows": false, "antialiasing": 0}  ## a slow device, for the options the player did not pick
## A phone: a mobile platform whose screen's short side is under this many CSS pixels, or whose screen is at least
## as wide as client/card_tokens.gd PHONE_ASPECT (2.0, a phone in landscape). Tablets keep the desktop defaults.
const PHONE_MAX_SHORT_SIDE := 600.0
const PHONE_ASPECT := 2.0
static var revision := 0
static var _loaded := false
static var _values := DESKTOP_DEFAULTS.duplicate()
static var _chosen: Array = []  ## option ids the player picked (survive a device-default change)
static var _slow := false  ## set by draw_style.gd begin_battle (the slow-device verdict for this battle)
static var device_override := ""  ## "phone" / "desktop" for tests and tools; native `-- --device=phone|desktop`
static var _device := ""
## Drawn (ink-and-wash) battle look, client/draw_style/draw_style.gd (Boss 2026-11-13 picked ink_c):
## "on" = materials + screen pass (screen pass only at render scale 0.5 and not on a slow device), "lite" = materials
## only, "off" = the old look.
const DRAWN_STYLES := ["off", "lite", "on"]

static func enabled(key: String) -> bool:
	return bool(effective(key))

## The value as saved / defaulted (what the graphics panel marks).
static func value(key: String) -> Variant:
	_load_once()
	return _values.get(key)

## The value that is applied: value(), except that a slow device turns off what SLOW_OFF lists unless the player
## picked it.
static func effective(key: String) -> Variant:
	_load_once()
	if _slow and SLOW_OFF.has(key) and not _chosen.has(key):
		return SLOW_OFF[key]
	return _values.get(key, true)

static func set_enabled(key: String, on: bool) -> void:
	set_value(key, on)

## The player's choice (graphics panel, tools): remembered as chosen, so a device default never replaces it.
static func set_value(key: String, new_value: Variant) -> void:
	_load_once()
	if not _valid(key, new_value): return
	_values[key] = new_value
	if not _chosen.has(key): _chosen.append(key)
	revision += 1
	_save()

## True when the player picked this option (it no longer follows the device default).
static func is_chosen(key: String) -> bool:
	_load_once()
	return _chosen.has(key)

## Forgets the player's choice: the option follows the device default again.
static func clear_choice(key: String) -> void:
	_load_once()
	if not _values.has(key): return
	_chosen.erase(key)
	_values[key] = device_defaults()[key]
	revision += 1
	_save()

## The options the graphics panel shows (frame_cap has no panel row yet: it is only in the lag report).
static func snapshot() -> Dictionary:
	_load_once()
	var shown := _values.duplicate()
	shown.erase("frame_cap")
	return shown

## Tests / tools: pretend this device class ("phone", "desktop", "" = detect). Reloads the saved file.
static func force_device(device: String) -> void:
	device_override = device
	reload_settings()

## "phone" or "desktop" (desktop also covers tablets and large screens).
static func device_class() -> String:
	if device_override in ["phone", "desktop"]: return device_override
	if _device.is_empty():
		_device = "desktop"
		for arg in OS.get_cmdline_user_args():
			if arg in ["--device=phone", "--device=desktop"]:
				_device = arg.substr(9)
				return _device
		var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		if mobile and is_phone_screen(true, _screen_css()):
			_device = "phone"
	return _device

## Pure: a mobile platform with a phone-sized screen (CSS pixels). Tests walk real device sizes through it.
static func is_phone_screen(mobile: bool, css_screen: Vector2) -> bool:
	if not mobile: return false
	var short_side := minf(css_screen.x, css_screen.y)
	var long_side := maxf(css_screen.x, css_screen.y)
	return short_side < PHONE_MAX_SHORT_SIDE or long_side / maxf(short_side, 1.0) >= PHONE_ASPECT

static func _screen_css() -> Vector2:
	if OS.has_feature("web"):
		var text = JavaScriptBridge.eval("screen.width + 'x' + screen.height", true)
		var parts := str(text).split("x")
		if parts.size() == 2 and float(parts[0]) > 0.0: return Vector2(float(parts[0]), float(parts[1]))
	var size := Vector2(DisplayServer.screen_get_size())
	return size / maxf(DisplayServer.screen_get_scale(), 1.0)

static func device_defaults() -> Dictionary:
	var defaults := DESKTOP_DEFAULTS.duplicate()
	if device_class() == "phone": defaults.merge(PHONE_DEFAULTS, true)
	return defaults

## The automatic phone look is on for this option (phone, and the player has not picked it).
static func phone_auto(key: String) -> bool:
	return device_class() == "phone" and not is_chosen(key)

## draw_style.gd begin_battle / forget_slow: the slow-device verdict for this battle.
static func set_slow(slow: bool) -> void:
	if slow == _slow: return
	_slow = slow
	revision += 1

static func is_slow() -> bool:
	return _slow

## "phone", "desktop" or "slow" (the slow device's extra cuts apply), with "+custom" when the player picked anything.
static func preset_name() -> String:
	_load_once()
	return ("slow" if _slow else device_class()) + ("+custom" if not _chosen.is_empty() else "")

## The graphics section of the lag report (runtime/diagnostics/session_probe.gd): the saved values plus which preset
## is active and what is actually applied. Small (a few hundred bytes).
static func report() -> Dictionary:
	_load_once()
	var section := _values.duplicate()
	section["preset"] = preset_name()
	section["device_class"] = device_class()
	section["slow_device"] = _slow
	section["chosen"] = _chosen.duplicate()
	section["applied"] = {"shadows": enabled("shadows"), "antialiasing": int(effective("antialiasing")), "drawn_style": str(effective("drawn_style")),
		"frame_cap": int(effective("frame_cap")), "max_fps": Engine.max_fps}
	return section

static func _valid(key: String, candidate: Variant) -> bool:
	if not _values.has(key): return false
	if key == "render_scale": return candidate is float and candidate in SCALES
	if key == "antialiasing": return candidate is int and candidate in [0, 2, 4]
	if key == "drawn_style": return candidate is String and candidate in DRAWN_STYLES
	if key == "frame_cap": return candidate is int and candidate in FRAME_CAPS
	return candidate is bool

static func _save() -> void:
	var config := ConfigFile.new()
	for id in _values: config.set_value("graphics", id, _values[id])
	config.set_value("graphics", CHOSEN_KEY, _chosen.duplicate())
	config.set_value("graphics", "preset_version", PRESET_VERSION)
	config.save(PATH)

## Test hook: forget what was loaded (the next read loads PATH again with the current device class).
static func reload_settings() -> void:
	_loaded = false
	_device = ""
	revision += 1

static func _load_once() -> void:
	if _loaded: return
	_loaded = true
	_values = device_defaults()
	_chosen = []
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return
	var preset_version := int(config.get_value("graphics", "preset_version", 0))
	var saved_scale: Variant = config.get_value("graphics", "render_scale", 0.5)
	if preset_version >= 4:
		var chosen: Variant = config.get_value("graphics", CHOSEN_KEY, [])
		for id in (chosen if chosen is Array else []):
			var saved: Variant = config.get_value("graphics", str(id), null)
			if _valid(str(id), saved):
				_values[str(id)] = saved
				_chosen.append(str(id))
		return
	# Before version 4 every value was written whenever any one changed: a value that differs from the old (desktop)
	# default was the player's choice, a value equal to it is treated as never picked (it follows the device).
	for id in _values:
		var saved: Variant = config.get_value("graphics", id, null)
		if _valid(id, saved) and saved != DESKTOP_DEFAULTS[id]:
			_values[id] = saved
			_chosen.append(id)
	# Preserve the selected tier while migrating its approved resolution percentage.
	if preset_version < 3:
		_chosen.erase("render_scale")
		_values["render_scale"] = 0.5
		if preset_version == 2 and saved_scale is float:
			if is_equal_approx(saved_scale, 0.85): _values["render_scale"] = 0.75
			elif is_equal_approx(saved_scale, 1.0): _values["render_scale"] = 1.0
		if not is_equal_approx(float(_values["render_scale"]), 0.5): _chosen.append("render_scale")
	_save()
