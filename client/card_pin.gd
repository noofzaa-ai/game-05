extends Node3D
## Card pin, client side (Boss 2026-11-26, local fights and online rooms). Tap a squad card (client/squad_panel.gd) to select
## it, then tap/click the arena floor: the card is pinned there (logic/game_sim.gd set_pin via the session) and its
## auto-pilot walks to the pin and fights from it. Tapping the selected card again deselects it and clears its pin.
## This node only reads input and state and shows feedback (selection ring, pin marker, walk line, card badge);
## the rules (clamping, one pin per squad, release at wave end/death) live in logic/.

const MARKER_GOLD := Color("FFD36A")  ## our side: gold core ...
const MARKER_BLUE := Color("4FA8FF")  ## ... with a blue rim (never red: red is an enemy telegraph)
const SELECT_COLOR := Color("F0E2C4")  ## cream ring under the selected fighter (matches the card's cream ring)
const TAP_SLOP_PX := 14.0  ## a press that moves further than this is a camera drag, not a tap
const TAP_MAX_MS := 450
const REPEAT_MS := 250  ## touch + emulated mouse for one tap: count once
const LINE_MIN := 0.6  ## metres: closer than this to the pin, no walk line

var session  ## needs set_pin/clear_pin/get_pin (client/session/local_session.gd)
var camera_of: Callable  ## -> Camera3D
var squad_panel  ## client/squad_panel.gd
var hud  ## client/hud.gd (tap_block_rects)
var views: Dictionary = {}  ## fighter id -> Node3D (positions)
var owner_ids: Array = []  ## our squad's fighter ids

var _selected := -1
var _press_at := Vector2.INF
var _press_ms := 0
var _last_tap_ms := -REPEAT_MS
var _ring: MeshInstance3D
var _marker: Node3D
var _line: MeshInstance3D
var _pinned_id := -1
var _clock := 0.0


## Shown only for local solo fights: an online room (remote session) keeps fights 100% auto for now.
static func enabled_for(a_session) -> bool:
	if a_session == null or not a_session.has_method("set_pin"): return false
	# Online (Boss 2026-11-26): only fight sessions that send card_pin commands (online_session.gd), never the camp RPC session.
	return not a_session.has_method("is_remote") or a_session.has_method("pin_allowed")


func _ready() -> void:
	name = "CardPin"
	_ring = _flat_ring(0.62, 0.78, SELECT_COLOR, 0.85)
	add_child(_ring)
	_ring.visible = false
	_marker = Node3D.new()
	var outer := _flat_ring(0.30, 0.46, MARKER_BLUE, 0.95)
	var core := _flat_ring(0.0, 0.22, MARKER_GOLD, 1.0)
	core.position.y = 0.005
	_marker.add_child(outer)
	_marker.add_child(core)
	var stick := MeshInstance3D.new()  # a short gold post so the pin still reads under feet/effects
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 0.7
	stick.mesh = cyl
	stick.material_override = _unshaded(MARKER_GOLD, 1.0)
	stick.position.y = 0.35
	_marker.add_child(stick)
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.13
	ball.height = 0.26
	head.mesh = ball
	head.material_override = _unshaded(MARKER_BLUE, 1.0)
	head.position.y = 0.76
	_marker.add_child(head)
	add_child(_marker)
	_marker.visible = false
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	_line.material_override = _unshaded(MARKER_GOLD, 0.8)
	add_child(_line)
	if squad_panel != null:
		squad_panel.selected.connect(_on_selected)


func selected_id() -> int:
	return _selected


## Card tap result from the panel: -1 = the selected card was tapped again (deselect + unpin).
func _on_selected(id: int) -> void:
	if id < 0 and _selected >= 0:
		unpin(_selected)
	_selected = id if id < 0 or owner_ids.has(id) else -1  # a squad-mate's card is never selected for pinning


## This client's own squad cards: online rooms ask the session (meta.squads owners), local sessions take the player team.
static func own_cards(a_session) -> Array:
	if a_session == null: return []
	if a_session.has_method("own_cards"): return a_session.own_cards()
	var out: Array = []
	for id in a_session.fighters:
		if a_session.fighters[id].team == "player": out.append(id)
	return out


func unpin(id: int) -> void:
	if session != null:
		session.clear_pin(id)


## True when viewport point `at` lies on a HUD element or a squad card (never a pin there).
func on_hud(at: Vector2) -> bool:
	var rects: Array = []
	if hud != null and hud.has_method("tap_block_rects"):
		rects.append_array(hud.tap_block_rects())
	if squad_panel != null:
		rects.append_array(squad_panel.keep_out_rects())
	for r in rects:
		if (r as Rect2).has_point(at):
			return true
	return false


## The floor point (y = 0) under viewport point `at`, or null.
func ground_point(at: Vector2):
	var cam: Camera3D = camera_of.call() if camera_of.is_valid() else null
	if cam == null:
		return null
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(at), cam.project_ray_normal(at))
	return hit


## A ground tap at viewport point `at`: pins the selected card there. Returns the stored pin ({} = nothing done).
func tap(at: Vector2) -> Dictionary:
	if _selected < 0 or session == null or on_hud(at):
		return {}
	var point = ground_point(at)
	if point == null:
		return {}
	return pin_at(_selected, point)


## The one call site into logic (via the session).
func pin_at(id: int, point: Vector3) -> Dictionary:
	var pin: Dictionary = session.set_pin(id, point.x, point.z, owner_ids)
	if not pin.is_empty():
		_show_marker(Vector3(float(pin["x"]), 0.0, float(pin["z"])))  # immediately, before the next frame
		_pinned_id = id
	return pin


func _unhandled_input(event: InputEvent) -> void:
	if _selected < 0:
		return
	var pressed := false
	var released := false
	var at := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed:
		pressed = event.pressed
		released = not event.pressed
		at = event.position
	elif event is InputEventScreenTouch and event.index == 0:
		pressed = event.pressed
		released = not event.pressed and not event.canceled
		at = event.position
	else:
		return
	if pressed:
		_press_at = at
		_press_ms = Time.get_ticks_msec()
		return  # the press stays free for the camera's drag/pinch
	if not released or _press_at == Vector2.INF:
		return
	var now := Time.get_ticks_msec()
	var is_tap := at.distance_to(_press_at) <= TAP_SLOP_PX and now - _press_ms <= TAP_MAX_MS
	_press_at = Vector2.INF
	if not is_tap or now - _last_tap_ms < REPEAT_MS:
		return
	if not tap(at).is_empty():
		_last_tap_ms = now
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_clock += delta
	if session == null:
		return
	var fighters: Dictionary = session.fighters
	if session.has_method("own_cards"): owner_ids = session.own_cards()  # room ownership can arrive after the view
	if _selected >= 0 and not owner_ids.has(_selected): _selected = -1
	if _selected >= 0 and (not fighters.has(_selected) or not fighters[_selected].is_alive()):
		_selected = -1
	_ring.visible = _selected >= 0 and views.has(_selected)
	if _ring.visible:
		_ring.position = (views[_selected] as Node3D).position + Vector3(0.0, 0.03, 0.0)
	var pinned := -1
	var pin := {}
	for id in owner_ids:
		var p: Dictionary = session.get_pin(id)
		if not p.is_empty():
			pinned = id
			pin = p
		if squad_panel != null and squad_panel.has_method("set_pinned"):
			squad_panel.set_pinned(id, not p.is_empty())
	_pinned_id = pinned
	if pinned < 0:
		_marker.visible = false
		(_line.mesh as ImmediateMesh).clear_surfaces()
		return
	var at := Vector3(float(pin["x"]), 0.0, float(pin["z"]))
	_show_marker(at)
	_marker.get_child(0).scale = Vector3.ONE * (1.0 + 0.08 * sin(_clock * 5.0))
	var mesh := _line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if views.has(pinned):
		var from: Vector3 = (views[pinned] as Node3D).position
		from.y = 0.06
		var to := at + Vector3(0.0, 0.06, 0.0)
		if from.distance_to(to) > LINE_MIN:
			_ribbon(mesh, from, to, 0.06)


func marker_shown() -> bool:
	return _marker != null and _marker.visible


func marker_position() -> Vector3:
	return _marker.position


func _show_marker(at: Vector3) -> void:
	_marker.position = at + Vector3(0.0, 0.02, 0.0)
	_marker.visible = true


## A thin flat ribbon on the floor (lines are 1 px in Godot: unreadable on phones).
func _ribbon(mesh: ImmediateMesh, from: Vector3, to: Vector3, half: float) -> void:
	var dir := (to - from)
	dir.y = 0.0
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * half
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [from - side, from + side, to + side, from - side, to + side, to - side]:
		mesh.surface_add_vertex(v)
	mesh.surface_end()


func _flat_ring(inner: float, outer: float, color: Color, alpha: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 32
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for v in [d0 * inner, d0 * outer, d1 * outer, d0 * inner, d1 * outer, d1 * inner]:
			mesh.surface_add_vertex(v)
	mesh.surface_end()
	node.mesh = mesh
	node.material_override = _unshaded(color, alpha)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _unshaded(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m
