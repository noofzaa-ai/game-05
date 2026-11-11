extends Node
## Owns the camera. The player's chosen angle is the baseline; camera triggers can override it
## (PvE only). Overrides stack: the most recent one wins, and releasing it falls back to the previous.

signal state_changed

const FOLLOW_SPEED := 6.0
const BLEND_SPEED := 4.0
## Angles the player can choose. offset = camera position relative to the followed x,
## look_y = height of the aimed point, fov = field of view in degrees.
## An override preset may also carry "look" (Vector3: the aimed point relative to the followed
## point, used instead of look_y) and "blend_speed" (how tightly the camera follows the preset while
## it is the active one; a skill camera that is keyed to its clip uses a high value). Releasing an
## override always blends back to the chosen angle at BLEND_SPEED.
const PRESETS := {
	KEY_6: {"name": "6: Side", "offset": Vector3(0.0, 2.0, 10.0), "look_y": 1.2, "fov": 50.0},
	KEY_7: {"name": "7: Angled", "offset": Vector3(0.0, 4.0, 9.0), "look_y": 1.0, "fov": 55.0},
	KEY_8: {"name": "8: High", "offset": Vector3(0.0, 7.0, 7.0), "look_y": 0.5, "fov": 55.0},
	KEY_9: {"name": "9: Top-down", "offset": Vector3(0.0, 17.0, 9.0), "look_y": 0.0, "fov": 40.0},
}

# Local view preference survives scene changes; never sent to the server.
static var remembered_view: Dictionary = {}
var input_allowed: Callable
var _orbit_drag := false
var _orbit_button := MOUSE_BUTTON_MIDDLE
var _orbit_touches: Dictionary = {}
var _pinch_latched := false
var _touch_started_ms := 0

var target: Node3D
var min_x := -8.0
var max_x := 8.0
## A wide arena: the camera follows the player in depth too (between min_z and max_z) instead of
## staying on a lane.
var follow_depth := false
var min_z := -8.0
var max_z := 8.0
## false = PvP rules: camera triggers are ignored and any active override is dropped.
var special_enabled := true:
	set(value):
		special_enabled = value
		if not value:
			_overrides.clear()
			if _environment_override != null:
				set_view_environment(null)
		state_changed.emit()
var chosen: Dictionary = PRESETS[KEY_8]

## Auto-battler board (map camera_style "arena", Boss 2026-11-10): the camera frames the whole board
## (ARENA_VIEW) and cannot zoom out past it; zooming in (wheel, pinch) closes on `target` (a fighter's
## 3D model up close) and the follow point slides from the board's centre to that fighter as it does.
const ARENA_VIEW := {"name": "Arena", "offset": Vector3(0.0, 16.5, 14.0), "look_y": -0.5, "fov": 40.0}
const ARENA_CLOSEST := 3.2  ## closest camera distance to the fighter (metres)
var arena := false
var _max_radius := 28.0

var _camera: Camera3D
var _shake_strength := 0.0
var _shake_left := 0.0
var _shake_total := 0.001
var _fov_kick := 0.0  ## degrees the field of view is pinched by a heavy hit (decays quickly)
var _overrides: Array[Dictionary] = []
var _x := 0.0
var _z := 0.0
var _offset: Vector3 = chosen["offset"]
var _look := Vector3(0.0, chosen["look_y"], 0.0)  ## aimed point relative to the followed point
var _fov: float = chosen["fov"]
var _environment_override: Environment  ## a view tone a skill camera lays over the world's (or null)


func _ready() -> void:
	if arena:
		chosen = ARENA_VIEW.duplicate(true)
		_max_radius = (chosen["offset"] - Vector3(0, chosen["look_y"], 0)).length()
	elif not remembered_view.is_empty(): chosen = remembered_view.duplicate(true)
	_offset = chosen["offset"]
	_look = chosen.get("look", Vector3(0, chosen.get("look_y", 1.0), 0))
	_fov = chosen["fov"]
	_camera = Camera3D.new()
	add_child(_camera)
	if target != null and not arena:
		_x = clampf(target.position.x, min_x, max_x)
		_z = clampf(target.position.z, min_z, max_z) if follow_depth else 0.0
	_update(1.0)


func _process(delta: float) -> void:
	if not _can_orbit():
		_orbit_drag = false
		_orbit_touches.clear()
		_pinch_latched=false
	if _orbit_drag and not Input.is_mouse_button_pressed(_orbit_button): _orbit_drag = false
	if arena:
		var focus := Vector3.ZERO
		if target != null:
			focus = Vector3(clampf(target.position.x, min_x, max_x), 0.0, clampf(target.position.z, min_z, max_z))
		var look: Vector3 = chosen.get("look", Vector3(0, chosen.get("look_y", 1.0), 0))
		var radius: float = (chosen["offset"] - look).length()
		var closeness := smoothstep(0.0, 1.0, clampf((_max_radius - radius) / maxf(_max_radius - ARENA_CLOSEST * 2.0, 0.1), 0.0, 1.0))
		var aim := Vector3.ZERO.lerp(focus, closeness)
		_x = lerpf(_x, aim.x, minf(1.0, FOLLOW_SPEED * delta))
		_z = lerpf(_z, aim.z, minf(1.0, FOLLOW_SPEED * delta))
	elif target != null:
		_x = lerpf(_x, clampf(target.position.x, min_x, max_x), minf(1.0, FOLLOW_SPEED * delta))
		_z = lerpf(_z, clampf(target.position.z, min_z, max_z) if follow_depth else 0.0, minf(1.0, FOLLOW_SPEED * delta))
	_update(minf(1.0, float(_active_preset().get("blend_speed", BLEND_SPEED)) * delta))
	_apply_shake(delta)


## The point the camera follows (the player's feet, kept inside the stage's camera limits).
func follow_point() -> Vector3:
	return Vector3(_x, 0.0, _z)


## Where the camera actually is and aims right now (before shake): {"position", "look", "fov"}.
func view() -> Dictionary:
	return {"position": follow_point() + _offset, "look": follow_point() + _look, "fov": _fov}


## A view tone (a copy of the world's Environment with other adjustments) for this camera only,
## or null to go back to the world's own. Ignored under PvP rules, like every special camera.
func set_view_environment(environment: Environment) -> void:
	if environment != null and not special_enabled:
		return
	_environment_override = environment
	if _camera != null:
		_camera.environment = environment


## Shakes the screen: `strength` is the largest offset in world units, `seconds` how long it takes
## to fade out. A stronger shake replaces a weaker one that is still running.
func shake(strength: float, seconds: float) -> void:
	if strength >= _shake_strength * (_shake_left / _shake_total):
		_shake_strength = strength
		_shake_left = seconds
		_shake_total = maxf(seconds, 0.001)


## A quick zoom-in "punch" (degrees of field of view) that eases back out: used on heavy hits.
func punch(fov_degrees: float) -> void:
	_fov_kick = maxf(_fov_kick, fov_degrees)


func _apply_shake(delta: float) -> void:
	_shake_left = maxf(0.0, _shake_left - delta)
	var fade := _shake_left / _shake_total
	var amount := _shake_strength * fade
	_camera.h_offset = randf_range(-amount, amount)
	_camera.v_offset = randf_range(-amount, amount)
	_fov_kick = move_toward(_fov_kick, 0.0, delta * 40.0)
	_camera.fov = _fov - _fov_kick


func choose(preset: Dictionary) -> void:
	if arena or is_choice_locked():
		return
	chosen = preset.duplicate(true)
	remembered_view = chosen.duplicate(true)
	state_changed.emit()


func is_choice_locked() -> bool:
	return not _overrides.is_empty() and _overrides.back()["lock"]


func has_override() -> bool:
	return not _overrides.is_empty()


func override_name() -> String:
	return "" if _overrides.is_empty() else _overrides.back()["preset"]["name"]


func request_override(source: Object, preset: Dictionary, lock: bool) -> void:
	if not special_enabled:
		return
	release_override(source)
	_overrides.append({"source": source, "preset": preset, "lock": lock})
	state_changed.emit()


func release_override(source: Object) -> void:
	for i in range(_overrides.size() - 1, -1, -1):
		if _overrides[i]["source"] == source:
			_overrides.remove_at(i)
	state_changed.emit()


func _active_preset() -> Dictionary:
	return _overrides.back()["preset"] if not _overrides.is_empty() else chosen


func _update(blend: float) -> void:
	var preset := _active_preset()
	_offset = _offset.lerp(preset["offset"], blend)
	_look = _look.lerp(preset.get("look", Vector3(0.0, preset["look_y"], 0.0)), blend)
	_fov = lerpf(_fov, preset["fov"], blend)
	_camera.position = follow_point() + _offset
	var aim := follow_point() + _look
	if not _camera.position.is_equal_approx(aim):
		var up := Vector3.UP if absf((aim - _camera.position).normalized().y) < 0.999 else Vector3.FORWARD
		_camera.look_at(aim, up)
	_camera.fov = _fov


## Camera gestures start anywhere gameplay/UI has not claimed the touch; no fixed pad.
func _can_orbit() -> bool:
	return not get_tree().paused and not has_override() and (not input_allowed.is_valid() or input_allowed.call())

func _input(event: InputEvent) -> void:
	# Always release even when a GUI button consumes the pointer-up event.
	if event is InputEventMouseButton and event.button_index == _orbit_button and not event.pressed:
		_orbit_drag = false
	if event is InputEventScreenTouch and (not event.pressed or event.canceled):
		_orbit_touches.erase(event.index)
		# Once pinching, never turn the remaining finger into a rotation gesture.
		if _orbit_touches.is_empty(): _pinch_latched=false
	if event is InputEventScreenDrag and _orbit_touches.has(event.index) and _can_orbit():
		var previous: Vector2=_orbit_touches[event.index]
		_orbit_touches[event.index]=event.position
		if _orbit_touches.size()==2:
			var keys := _orbit_touches.keys()
			var other: Vector2=_orbit_touches[keys[0] if keys[1]==event.index else keys[1]]
			var old_distance := previous.distance_to(other)
			var new_distance: float=event.position.distance_to(other)
			if old_distance>16 and new_distance>16: _orbit(Vector2.ZERO,old_distance/new_distance)
		elif not _pinch_latched and Time.get_ticks_msec()-_touch_started_ms>=80:
			_orbit(event.position-previous)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _can_orbit(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed):
			_orbit_button = event.button_index
			_orbit_drag = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_orbit(Vector2.ZERO, .9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/.9)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbit_drag:
		_orbit(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		if _orbit_touches.size()<2:
			_orbit_touches[event.index]=event.position
			if _orbit_touches.size()==1: _touch_started_ms=Time.get_ticks_msec()
			if _orbit_touches.size()==2: _pinch_latched=true
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture and _orbit_touches.is_empty():
		_orbit(Vector2.ZERO,1.0/maxf(event.factor,.01))
		get_viewport().set_input_as_handled()

func _orbit(drag: Vector2, zoom: float = 1.0) -> void:
	var look: Vector3 = chosen.get("look",Vector3(0,chosen.get("look_y",1.0),0))
	var arm: Vector3 = chosen["offset"]-look
	var radius := clampf(arm.length()*zoom,ARENA_CLOSEST if arena else 2.5,_max_radius)
	var size := get_viewport().get_visible_rect().size
	var yaw := atan2(arm.x,arm.z)-drag.x*TAU/maxf(size.x,1)
	var pitch := clampf(asin(clampf(arm.normalized().y,-1,1))+drag.y*PI/maxf(size.y,1),deg_to_rad(5),deg_to_rad(85))
	if arena:  # zooming in also lowers the camera: from the board's overview angle to a closer, lower look at the fighter
		var overview: Vector3 = ARENA_VIEW["offset"]
		var t := clampf((radius - ARENA_CLOSEST) / maxf(_max_radius - ARENA_CLOSEST, 0.1), 0.0, 1.0)
		pitch = lerpf(deg_to_rad(24.0), asin(overview.normalized().y), t)
	chosen = {"name":"Free", "offset":look+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*radius,"look":look,"look_y":look.y,"fov":chosen["fov"]}
	remembered_view = chosen.duplicate(true)
	state_changed.emit()

## Screen-relative walking after orbit; send ordinary world-space input to the authority.
func movement_from_screen(value: Vector2) -> Vector2:
	var arm: Vector3 = chosen["offset"]-chosen.get("look",Vector3(0,chosen.get("look_y",1.0),0))
	var down := Vector2(arm.x,arm.z).normalized()
	return Vector2(down.y,-down.x)*value.x+down*value.y
