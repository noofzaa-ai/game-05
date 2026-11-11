extends Node
## Plays an ultimate's own camera while the local player casts it: the "camera" block of the skill in
## data/combat/ultimates.json (made from the pack by tools/skills/sync_ultimates.py). The shots run
## on the move's frames, as client/vfx/skill_vfx.gd does (move_frame / 60 = seconds into the clip),
## so hit-stop and attack speed keep camera, picture and rules together.
## It goes through the camera rig like any special camera: a MANUAL client/camera_trigger.gd override
## whose preset this node rewrites every tick. So it is PvE-only (the rig ignores overrides under PvP
## rules), it never changes the player's chosen angle, and when the cast ends - the move finishes,
## the caster is hit, dies, or the stage goes away - the override is released and the rig blends back
## to the chosen angle (and the trigger's max_duration releases it even if nobody calls stop()).
## The shakes play under both rules (they are hit feedback, like effects.gd's).
## Display only: logic/ never reads the camera block.
##
## Key shots (positions are metres of the pack's body in the caster's frame [right, up, forward],
## scaled by body_scale): "game" = the player's chosen angle; "frame" = camera at position_m aiming
## at look_m with fov_deg; "orbit" = the chosen angle turned yaw_deg round the caster (distance and
## height scaled) aiming at look_m, fov = chosen fov x fov_scale. Between two keys the shot eases
## (smoothstep); before the first and after the last key it is the chosen angle.
## Two safety rules the packs do not have (they were made for a free arena): a shot never puts the
## camera behind the caster as seen from the player's side (its depth is mirrored to the viewer's
## side, so it never looks at the back of the stage set), and the caster's body always stays inside
## the frame (otherwise the shot is pulled toward the chosen angle until it is).

const CameraTrigger := preload("res://client/camera_trigger.gd")
const Fighter := preload("res://logic/fighter.gd")
const SkillVfx := preload("res://client/vfx/skill_vfx.gd")

const BLEND_SPEED := 18.0  ## how tightly the rig follows the keyed shot (the rig's own return uses its BLEND_SPEED)
const SAFE_FRACTION := 0.85  ## the body must sit inside this fraction of the half field of view
const SAFE_ASPECT := 4.0 / 3.0  ## narrowest screen shape the horizontal check assumes (fov is vertical)
const SHOTS := ["game", "frame", "orbit"]

var rig: Node  ## client/camera_rig.gd

var _trigger: Node
var _preset := {"name": "Ultimate", "offset": Vector3.ZERO, "look_y": 0.0, "look": Vector3.ZERO, "fov": 55.0, "blend_speed": BLEND_SPEED}
var _move := ""
var _camera: Dictionary = {}  ## the parsed block of the skill being cast
var _basis := Basis.IDENTITY  ## the caster's frame when the cast began (x right, z forward)
var _scale := 1.0
var _last_time := -1.0
var _shakes_done := 0
var _tone_base: Environment
var _tone_view: Environment
var guard_pulls := 0  ## ticks the on-screen rule had to pull a shot toward the chosen angle (for tests/tuning)


func _ready() -> void:
	_trigger = CameraTrigger.new()
	_trigger.rig = rig
	_trigger.preset = _preset
	_trigger.mode = CameraTrigger.Mode.MANUAL
	_trigger.lock_choice = false  # the player can still pick 6-9; it is used after the cast
	add_child(_trigger)


## Reads a camera block: {"errors": [..], "source", "keys", "shakes", "tone"} (keys and shakes in time order).
static func parse(block: Variant, label: String = "camera") -> Dictionary:
	var out := {"errors": [], "source": "default", "keys": [], "shakes": [], "tone": {}}
	if typeof(block) != TYPE_DICTIONARY:
		out["errors"].append("%s must be an object" % label)
		return out
	out["source"] = str(block.get("source", "default"))
	out["hammer_drag"] = block.get("hammer_drag", {})
	var previous := -1.0
	for key in block.get("keys", []):
		if typeof(key) != TYPE_DICTIONARY or not key.has("time_s") or not SHOTS.has(str(key.get("shot", ""))):
			out["errors"].append("%s.keys need time_s and a shot (%s)" % [label, ", ".join(SHOTS)])
			continue
		var t := float(key["time_s"])
		if t < previous:
			out["errors"].append("%s.keys must be in time order" % label)
		previous = t
		var shot := {"time_s": t, "shot": str(key["shot"])}
		match shot["shot"]:
			"frame":
				shot["position"] = _vec(key.get("position_m"), label + ".position_m", out)
				shot["look"] = _vec(key.get("look_m"), label + ".look_m", out)
				shot["fov"] = float(key.get("fov_deg", 0.0))
				if shot["fov"] < 10.0 or shot["fov"] > 120.0:
					out["errors"].append("%s.fov_deg must be 10..120" % label)
				if shot["position"].y <= 0.0:
					out["errors"].append("%s.position_m must be above the ground" % label)
			"orbit":
				shot["look"] = _vec(key.get("look_m"), label + ".look_m", out)
				shot["yaw"] = deg_to_rad(float(key.get("yaw_deg", 0.0)))
				shot["distance"] = float(key.get("distance_scale", 1.0))
				shot["height"] = float(key.get("height_scale", 1.0))
				shot["fov_scale"] = float(key.get("fov_scale", 1.0))
				if shot["distance"] <= 0.0 or shot["height"] <= 0.0 or shot["fov_scale"] <= 0.0:
					out["errors"].append("%s orbit scales must be above 0" % label)
		out["keys"].append(shot)
	previous = -1.0
	for shake in block.get("shakes", []):
		if typeof(shake) != TYPE_DICTIONARY or not shake.has("time_s"):
			out["errors"].append("%s.shakes need time_s" % label)
			continue
		var strength := float(shake.get("strength_m", 0.0))
		var seconds := float(shake.get("seconds", 0.0))
		if strength <= 0.0 or strength > 0.3 or seconds <= 0.0 or seconds > 2.0:
			out["errors"].append("%s.shakes: strength_m must be 0..0.3 and seconds 0..2" % label)
		if float(shake["time_s"]) < previous:
			out["errors"].append("%s.shakes must be in time order" % label)
		previous = float(shake["time_s"])
		out["shakes"].append({"time_s": float(shake["time_s"]), "strength": strength, "seconds": seconds})
	if typeof(block.get("tone")) == TYPE_DICTIONARY:
		var tone: Dictionary = block["tone"]
		for k in ["brightness", "saturation", "contrast", "ambient"]:
			if float(tone.get(k, 1.0)) <= 0.0:
				out["errors"].append("%s.tone.%s must be above 0" % [label, k])
		out["tone"] = tone.duplicate()
	return out


static func _vec(value: Variant, label: String, out: Dictionary) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		out["errors"].append("%s must be [right, up, forward]" % label)
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


## The caster's frame for a facing on the ground (x, z): x = its right, z = forward.
static func frame_for(forward: Vector2) -> Basis:
	var ahead := Vector3(forward.x, 0.0, forward.y).normalized()
	if ahead.is_zero_approx():
		ahead = Vector3(0.0, 0.0, 1.0)
	return Basis(Vector3.UP.cross(ahead).normalized(), Vector3.UP, ahead)


## The shot at `time`: {"offset", "look", "fov", "special"}, offset and look relative to the rig's
## follow point. `caster` = the caster's feet relative to the follow point; `chosen` = the player's preset.
static func sample(camera: Dictionary, time: float, chosen: Dictionary, frame: Basis, body_scale: float, caster: Vector3) -> Dictionary:
	var game := _game_shot(chosen)
	var keys: Array = camera.get("keys", [])
	if keys.is_empty() or time < float(keys[0]["time_s"]) or time >= float(keys[keys.size() - 1]["time_s"]):
		return game
	var i := 0
	while i < keys.size() - 2 and time >= float(keys[i + 1]["time_s"]):
		i += 1
	var a := _eval(keys[i], chosen, frame, body_scale, caster)
	var b := _eval(keys[i + 1], chosen, frame, body_scale, caster)
	var u := smoothstep(float(keys[i]["time_s"]), float(keys[i + 1]["time_s"]), time)
	return {"offset": a["offset"].lerp(b["offset"], u), "look": a["look"].lerp(b["look"], u),
		"fov": lerpf(a["fov"], b["fov"], u), "special": a["special"] or b["special"]}


static func _game_shot(chosen: Dictionary) -> Dictionary:
	return {"offset": chosen["offset"], "look": Vector3(0.0, chosen["look_y"], 0.0), "fov": float(chosen["fov"]), "special": false}


static func _eval(key: Dictionary, chosen: Dictionary, frame: Basis, body_scale: float, caster: Vector3) -> Dictionary:
	match key["shot"]:
		"frame":
			var at: Vector3 = frame * (key["position"] * body_scale)
			at.z = absf(at.z)  # stay on the viewer's side of the caster (see the header)
			return {"offset": caster + at, "look": caster + frame * (key["look"] * body_scale), "fov": key["fov"], "special": true}
		"orbit":
			var game := _game_shot(chosen)
			var look: Vector3 = caster + frame * (key["look"] * body_scale)
			var arm: Vector3 = (game["offset"] - game["look"]).rotated(Vector3.UP, key["yaw"]) * key["distance"]
			arm.y *= key["height"]
			arm.z = absf(arm.z)
			return {"offset": look + arm, "look": look, "fov": float(chosen["fov"]) * key["fov_scale"], "special": true}
	return _game_shot(chosen)


## Whether `point` is inside the view from `position` aiming at `look` with a vertical `fov`.
static func in_view(position: Vector3, look: Vector3, fov: float, point: Vector3) -> bool:
	var ahead := (look - position).normalized()
	var to := point - position
	var depth := to.dot(ahead)
	if depth <= 0.05:
		return false
	var side := ahead.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.000001 else Vector3.RIGHT
	var up := side.cross(ahead)
	var limit := tan(deg_to_rad(fov) * 0.5) * SAFE_FRACTION
	return absf(to.dot(up)) / depth <= limit and absf(to.dot(side)) / depth <= limit * SAFE_ASPECT


## `shot` pulled toward the chosen angle until every point (relative to the follow point) is in view.
static func keep_in_view(shot: Dictionary, chosen: Dictionary, points: Array) -> Dictionary:
	if _sees_all(shot, points):
		return shot
	var game := _game_shot(chosen)
	var lo := 0.0  # blend toward the shot that is known to work (0 = the chosen angle)
	var hi := 1.0
	for i in 10:
		var mid := (lo + hi) * 0.5
		if _sees_all(_blend(game, shot, mid), points):
			lo = mid
		else:
			hi = mid
	var kept := _blend(game, shot, lo)
	kept["pulled"] = true
	return kept


static func _blend(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	return {"offset": a["offset"].lerp(b["offset"], u), "look": a["look"].lerp(b["look"], u), "fov": lerpf(a["fov"], b["fov"], u), "special": b["special"]}


static func _sees_all(shot: Dictionary, points: Array) -> bool:
	for p in points:
		if not in_view(shot["offset"], shot["look"], shot["fov"], p):
			return false
	return true


## The points of the shown body that must stay in frame, from its middle (the hips; the packs lift
## the body with the hips bone, so this follows a leap): about the feet, the hips and the head.
static func body_points(hips: Vector3) -> Array:
	return [Vector3(hips.x, maxf(0.1, hips.y - 0.6), hips.z), hips, hips + Vector3(0.0, 0.85, 0.0)]


func is_playing() -> bool:
	return _move != ""


## Called every simulation tick for the local player. `fighter` = its logic Fighter, `feet` = where
## its body stands (world), `body_center` = the middle of its shown body (world; it rises with a
## leaping clip).
func update(fighter, feet: Vector3, body_center: Vector3, weapon_point: Vector3 = Vector3.INF) -> void:
	if not preload("res://client/graphics_options.gd").enabled("ultimate_camera"):
		stop()
		return
	var casting: bool = fighter != null and fighter.is_alive() and fighter.state == Fighter.State.ATTACK
	var pack := SkillVfx.pack_for(fighter.move_id) if casting else {}
	if pack.is_empty() or typeof(pack.get("camera")) != TYPE_DICTIONARY:
		stop()
		return
	var time: float = fighter.move_frame / 60.0
	if _move != fighter.move_id or time < _last_time:
		_begin(pack, Vector2(fighter.direction))
		_move = fighter.move_id
	_last_time = time
	for i in range(_shakes_done, _camera["shakes"].size()):
		var shake: Dictionary = _camera["shakes"][i]
		if time < shake["time_s"]:
			break
		rig.shake(shake["strength"], shake["seconds"])
		_shakes_done = i + 1
	_show_tone(time)
	var follow: Vector3 = rig.follow_point()
	var shot := sample(_camera, time, rig.chosen, _basis, _scale, feet - follow)
	var drag: Dictionary = _camera.get("hammer_drag", {})
	if not drag.is_empty():
		var point := weapon_point if weapon_point.is_finite() else feet
		shot = _drag_shot(drag, time, feet - follow, point - follow)
	if not shot["special"] or not rig.special_enabled:
		_trigger.deactivate()
		return
	if drag.is_empty() or time >= float(drag["reframe_end_s"]):
		shot = keep_in_view(shot, rig.chosen, body_points(body_center - follow))
	if shot.get("pulled", false):
		guard_pulls += 1
	_preset["offset"] = shot["offset"]
	_preset["look"] = shot["look"]
	_preset["look_y"] = shot["look"].y
	_preset["fov"] = shot["fov"]
	_trigger.activate()


func _drag_shot(cam: Dictionary, time: float, feet: Vector3, head: Vector3) -> Dictionary:
	var game := _game_shot(rig.chosen)
	var entry := smoothstep(0.0, float(cam["entry_end_s"]), time)
	var reveal := smoothstep(float(cam["reframe_start_s"]), float(cam["reframe_end_s"]), time)
	var leave := smoothstep(float(cam["return_start_s"]), float(cam["return_end_s"]), time)
	var low := head + _basis * Vector3(-float(cam["side_offset_m"]), 0, float(cam["forward_offset_m"])) * _scale
	low.y = feet.y + float(cam["height_m"]) * _scale
	var raised := feet + _basis * Vector3(-float(cam["reframe_side_m"]), float(cam["reframe_height_m"]), float(cam["reframe_forward_m"])) * _scale
	var target := (head + Vector3.UP * float(cam["focus_lift_m"]) * _scale).lerp(feet + _basis * Vector3(0, 0.95, 0.15) * _scale, reveal)
	var close := {"offset": low.lerp(raised, reveal), "look": target, "fov": float(cam["fov"]), "special": time > 0 and leave < 1}
	return _blend(game, close, entry * (1.0 - leave))


func _begin(pack: Dictionary, direction: Vector2) -> void:
	stop()
	_camera = parse(pack["camera"], pack["id"] + ".camera")
	_basis = frame_for(direction)
	_scale = float(pack.get("body_m", 1.7)) / maxf(0.01, float(pack.get("height", 1.0)))
	_shakes_done = 0
	_last_time = -1.0
	_trigger.max_duration = float(pack.get("duration_s", 5.0)) + 1.0  # a last safety net


## Ends the cast's camera: back to the player's chosen angle (the rig blends there).
func stop() -> void:
	_move = ""
	_camera = {}
	if _trigger != null:
		_trigger.deactivate()
	if _tone_view != null and rig != null:
		rig.set_view_environment(null)
	_tone_view = null
	_tone_base = null


func _show_tone(time: float) -> void:
	var tone: Dictionary = _camera.get("tone", {})
	var weight := 0.0
	if not tone.is_empty() and rig.special_enabled:
		weight = smoothstep(float(tone.get("in_start_s", 0.0)), float(tone.get("in_end_s", 0.0)) + 0.0001, time)
		weight *= 1.0 - smoothstep(float(tone.get("out_start_s", 0.0)), float(tone.get("out_end_s", 0.0)) + 0.0001, time)
	if weight <= 0.0:
		if _tone_view != null:
			rig.set_view_environment(null)
			_tone_view = null
		return
	if _tone_view == null:
		var world := get_viewport().find_world_3d() if get_viewport() != null else null
		_tone_base = world.environment if world != null else null
		if _tone_base == null:
			return
		_tone_view = _tone_base.duplicate()
		rig.set_view_environment(_tone_view)
	_tone_view.fog_enabled = _tone_base.fog_enabled and preload("res://client/graphics_options.gd").enabled("fog")
	_tone_view.glow_enabled = _tone_base.glow_enabled and preload("res://client/graphics_options.gd").enabled("glow")
	var base_on := _tone_base.adjustment_enabled
	_tone_view.adjustment_enabled = true
	_tone_view.adjustment_brightness = (_tone_base.adjustment_brightness if base_on else 1.0) * lerpf(1.0, float(tone.get("brightness", 1.0)), weight)
	_tone_view.adjustment_saturation = (_tone_base.adjustment_saturation if base_on else 1.0) * lerpf(1.0, float(tone.get("saturation", 1.0)), weight)
	_tone_view.adjustment_contrast = (_tone_base.adjustment_contrast if base_on else 1.0) * lerpf(1.0, float(tone.get("contrast", 1.0)), weight)
	_tone_view.ambient_light_energy = _tone_base.ambient_light_energy * lerpf(1.0, float(tone.get("ambient", 1.0)), weight)


func _exit_tree() -> void:
	stop()
