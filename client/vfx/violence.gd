extends RefCounted
## "Violent" skill look switch (Boss 2026-11-19): our skills read as single patches; he wants light and scatter (a white-hot
## additive core, coloured glow, radiating rays, a light pillar, sparks and embers, debris, dust and a punchy shake). He
## approved the L3 light, dropped the ground rings / scorch decals, the lighting dim and hit-stop, and rolled it out to every
## race ultimate, class skill and the mummy bosses' big moves (client/vfx/violent_vfx.gd).
##
## ONE token picks the look: data/combat/vfx.json "violence".level = "current" (off: nothing new plays) | "L1" | "L2" | "L3"
## (shipped). The layers are data: actions "violent/<preset>/<level>" and the lighter "violent/<preset>/<level>_phone"
## played on phones and slow devices (fewer and smaller particles, the same light / debris / shake).
## Overrides for tools and A/B runs (never shown to players): env ZORX_VFX_VIOLENCE=L2, or `override_level`.

const GraphicsOptions := preload("res://client/graphics_options.gd")
const LEVELS: Array[String] = ["current", "L1", "L2", "L3"]
const DATA_PATH := "res://data/combat/vfx.json"

static var override_level := ""  ## tools: "" = data / env
static var override_phone := -1  ## tools: -1 = device, 0 = full, 1 = phone variant
static var override_reduced := -1  ## tools/tests: -1 = device, 0 / 1
static var _data_level := ""
static var _reduced := -1


## The chosen level: the override, else env ZORX_VFX_VIOLENCE, else the data's "violence".level, else "current".
static func level() -> String:
	if override_level in LEVELS:
		return override_level
	var env := OS.get_environment("ZORX_VFX_VIOLENCE")
	if env in LEVELS:
		return env
	if _data_level.is_empty():
		_data_level = "current"
		var root = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		if root is Dictionary and root.get("violence") is Dictionary and str(root["violence"].get("level", "")) in LEVELS:
			_data_level = str(root["violence"]["level"])
	return _data_level


## True when the lighter phone layers play (a phone, or a device the battle marked slow).
static func phone() -> bool:
	if override_phone >= 0:
		return override_phone == 1
	return GraphicsOptions.device_class() == "phone" or GraphicsOptions.is_slow()


## The action key for `preset` at `lvl` ("" for the current look: nothing extra plays).
static func key_for(preset: String, lvl: String, phone_variant: bool) -> String:
	if lvl == "current" or not lvl in LEVELS:
		return ""
	return "violent/%s/%s%s" % [preset, lvl, "_phone" if phone_variant else ""]


## The action to play now for `preset`, or "" (current look).
static func key(preset: String) -> String:
	return key_for(preset, level(), phone())


## Reduced motion (accessibility): no camera shake or zoom punch, screen flashes at a third. The browser's
## prefers-reduced-motion on the web; env ZORX_REDUCED_MOTION=1 natively. There is no in-game setting yet.
static func reduced_motion() -> bool:
	if override_reduced >= 0:
		return override_reduced == 1
	if _reduced < 0:
		_reduced = 0
		if OS.get_environment("ZORX_REDUCED_MOTION") == "1":
			_reduced = 1
		elif OS.has_feature("web"):
			var answer = JavaScriptBridge.eval("window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches", true)
			_reduced = 1 if bool(answer) else 0
	return _reduced == 1


## Tests / tools: forget the cached data level (read the file again).
static func reload() -> void:
	_data_level = ""
	_reduced = -1
