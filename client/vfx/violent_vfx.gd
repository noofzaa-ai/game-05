extends Node
## Plays the "violent" light-and-scatter look (client/vfx/violence.gd; Boss 2026-11-19: L3 light approved, no ground rings,
## no dimming, no hit-stop) on every race ultimate, every class skill and the mummy bosses' big moves, on top of what each
## already shows (its daiyooo bundle, its old layers). Display only: it reads the sim's events, never changes the fight.
## WHAT plays is data (data/combat/vfx.json "violence".skills: <key> -> preset, colour, scale, on, at, ahead); HOW a preset
## looks is the actions "violent/<preset>/<level>[_phone]" played by client/effects.gd (pooled, prewarmed for the active
## level only). Keys: "race_ult/<race>_<class>" (the ultimate's vfx key), "class_skill/<id>", "monster/<move|area|shot>".
## Where a blow lands:
##   race ultimates : where its first action lands (race_burst / race_zone / race_taunt pos), else on the caster
##   class skills   : on "release" at the caster (or the target: at = target), on "impact" at the burst point
##   monsters       : attack_active (on the attacker, `ahead` metres along its facing), area_detonated, projectile_ended,
##                    wave_arrived (under each summoner of the wave)
## The screen flash is soft and rate-limited (FLASH_GAP) so overlapping blows never pump the screen like a flicker.
## Debris / dust colours follow the map ("violence".map_colors by map id prefix): the dark mummy floor needs light sand.

const Violence := preload("res://client/vfx/violence.gd")
const Effects := preload("res://client/effects.gd")
const GraphicsOptions := preload("res://client/graphics_options.gd")
const FLASH_GAP := 0.9  ## seconds between two violent screen flashes
const WAVE_KEY := "monster/summon"
## Phones / slow devices: at most this many violent blows a second (a token bucket); in a boss wave the extra blows keep
## only their own look (bundle / old layers). Desktop has no cap.
const PHONE_BLOWS_PER_SECOND := 3.0
const ULT_EVENTS := ["race_burst", "race_zone", "race_taunt", "race_heal", "race_shield", "race_skill_refresh", "race_ult_resolved"]

var effects  ## client/effects.gd
var session  ## the stage's session (bodies, fighters)
var map_id := ""  ## picks the debris / dust colours
var specs: Dictionary = {}  ## key -> {preset, color: Color, scale, on, at, ahead}
var map_colors: Dictionary = {}  ## colour name ("rock", "dust", "smoke") -> Color for this map
var played: Array[String] = []  ## keys played (tests); the last 64
var _flash_clock := 99.0
var _phone_tokens := PHONE_BLOWS_PER_SECOND
var _ult_wait: Dictionary = {}  ## player id -> ult key, from ultimate_cast until its first action lands
var _summoners: Array = []  ## enemy types whose arrival plays WAVE_KEY


func _ready() -> void:
	load_data(Violence.DATA_PATH)


func load_data(path: String) -> void:
	var root = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var data: Dictionary = root.get("violence", {}) if root is Dictionary and root.get("violence") is Dictionary else {}
	specs.clear()
	for key in data.get("skills", {}):
		var raw: Dictionary = data["skills"][key]
		specs[str(key)] = {"preset": str(raw.get("preset", "skill")), "color": Color.html(str(raw.get("color", "#ffffff"))),
			"scale": float(raw.get("scale", 1.0)), "on": str(raw.get("on", "release")), "at": str(raw.get("at", "caster")),
			"ahead": float(raw.get("ahead", 0.0))}
	_summoners = Array(data.get("summoners", []))
	map_colors.clear()
	var best := ""
	for prefix in data.get("map_colors", {}):
		if map_id.begins_with(str(prefix)) and str(prefix).length() > best.length():
			best = str(prefix)
	if best != "":
		for name in data["map_colors"][best]:
			map_colors[str(name)] = Color.html(str(data["map_colors"][best][name]))


func _process(delta: float) -> void:
	_flash_clock += delta
	_phone_tokens = minf(PHONE_BLOWS_PER_SECOND, _phone_tokens + delta * PHONE_BLOWS_PER_SECOND)


func handle_events(events: Array) -> void:
	for event in events:
		var type := str(event.get("type", ""))
		if type == "ultimate_cast":
			_ult_wait[int(event.get("player", -1))] = str(event.get("vfx", ""))
		elif type in ULT_EVENTS:
			var id := int(event.get("player", -1))
			if _ult_wait.has(id) and bool(event.get("ultimate", false)):
				var key: String = _ult_wait[id]
				_ult_wait.erase(id)
				var at = event.get("pos") if event.get("pos") is Vector3 else _feet(id)
				if at != null and GraphicsOptions.enabled("ultimate_vfx"):
					play(key, at, _facing(id))
		elif type == "class_skill_release":
			var key := "class_skill/" + str(event.get("skill", ""))
			var spec: Dictionary = specs.get(key, {})
			if spec.is_empty() or spec["on"] != "release" or int(event.get("index", 0)) != 0:
				continue
			var id := int(event.get("player", -1))
			var at = _feet(id)
			if at == null and event.get("pos") is Vector3:
				at = event["pos"]
			if spec["at"] == "target":
				var target := int(event.get("target", -1))
				if _alive(target):
					at = _feet(target)
				elif event.get("aim") is Vector3:
					at = event["aim"]
			if at != null:
				var dir := _facing(id)
				play(key, at + Vector3(dir.x, 0.0, dir.y) * float(spec["ahead"]), dir)
		elif type == "class_skill_impact":
			var key := "class_skill/" + str(event.get("skill", ""))
			if specs.has(key) and specs[key]["on"] == "impact":
				play(key, event["pos"], Vector2.RIGHT)
		elif type == "attack_active":
			var key := "monster/" + str(event.get("move", ""))
			if specs.has(key) and specs[key]["on"] == "active":
				var id := int(event.get("player", -1))
				var at = _feet(id)
				if at != null:
					var dir := _facing(id)
					play(key, at + Vector3(dir.x, 0.0, dir.y) * float(specs[key]["ahead"]), dir)
		elif type == "area_detonated":
			var key := "monster/" + str(event.get("kind", ""))
			if specs.has(key):
				play(key, event["pos"], Vector2.RIGHT)
		elif type == "projectile_ended":
			var key := "monster/" + str(event.get("projectile", ""))
			if specs.has(key) and str(event.get("reason", "")) != "gone":
				play(key, event["pos"], Vector2.RIGHT)
		elif type == "wave_arrived":
			_on_wave(event)


func _on_wave(event: Dictionary) -> void:
	if session == null or not specs.has(WAVE_KEY):
		return
	for id in event.get("enemies", []):
		var fighter = session.fighters.get(int(id))
		if fighter != null and str(fighter.enemy_type) in _summoners and session.bodies.has(int(id)):
			play(WAVE_KEY, session.bodies[int(id)].position, Vector2.RIGHT)


## Plays the violent look of `key` on the ground point `pos` (nothing at level "current" or for an unknown key).
## Returns the action played.
func play(key: String, pos: Vector3, facing: Vector2) -> String:
	var spec: Dictionary = specs.get(key, {})
	if spec.is_empty() or effects == null:
		return ""
	var action := Violence.key(str(spec["preset"]))
	if action.is_empty() or not effects.library.has(action):
		return ""
	if action.ends_with("_phone"):
		if _phone_tokens < 1.0:
			return ""
		_phone_tokens -= 1.0
	var feet := Vector3(pos.x, 0.0 if pos.y < 1.5 else pos.y - 1.1, pos.z)  # (an orb's job flies at chest height)
	var flash := _flash_clock >= FLASH_GAP
	if flash:
		_flash_clock = 0.0
	var ctx: Dictionary = Effects.context(feet + Vector3(0.0, 0.6, 0.0), feet, facing, spec["color"],
		{"violent": true, "flash": flash, "scale": float(spec["scale"]), "colors": map_colors})
	effects.play(action, ctx)
	played.append(key)
	if played.size() > 64:
		played.remove_at(0)
	return action


func _alive(id: int) -> bool:
	return session != null and session.bodies.has(id) and (not session.fighters.has(id) or session.fighters[id].is_alive())


func _feet(id: int):
	if session == null or not session.bodies.has(id):
		return null
	var p: Vector3 = session.bodies[id].position
	return Vector3(p.x, 0.0, p.z)


func _facing(id: int) -> Vector2:
	if session != null and session.fighters.has(id):
		var d = session.fighters[id].get("direction")
		if d is Vector2 and d.length() > 0.01:
			return d.normalized()
	return Vector2.RIGHT
