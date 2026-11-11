extends CanvasLayer
## Owner-local touchscreen input. Does not decide combat rules or mutate keyboard Input actions.
## Portrait blocks the entire app; browsers that refuse orientation lock use this rotation gate.
const CombatArt := preload("res://client/mobile_combat_art.gd")
const SimInput := preload("res://logic/sim_input.gd")
const InkUi := preload("res://client/ink_ui.gd")
const CombatLayout := preload("res://client/mobile_combat_layout.gd")
const ACTIONS := ["light", "heavy", "dodge", "guard", "special", "ultimate"]
var enabled := false
var force_mobile := false
var vector := Vector2.ZERO
var _finger := -1
var _origin := Vector2.ZERO
var _held := {} # finger index -> action, independent simultaneous touches
var _taps := {}
var _skill_queued := -1

func queue_skill(slot: int) -> void:
	if slot >= 0 and slot < 4: _skill_queued = slot

func combat_button_rect(action: String) -> Rect2:
	return _buttons.get(action,Rect2())

func skill_button_rect(slot:int) -> Rect2:
	if slot<0 or slot>3:return Rect2()
	var density:=_screen_unit()
	var fit:=minf(1.0,minf(_size.y/density/370.0,_size.x/density/820.0))
	return CombatLayout.regions(_size,density*fit,44.0*density).skills[slot]

var _glyphs := {}
var _feedback := {}
var _buttons := {} # action -> Rect2, in viewport coordinates
var _root: Control
var _stick: Control
var _gate_layer: CanvasLayer
var _gate: ColorRect
var _label: Label
var _use: Button
var _back: Button
var _retry: Button
var _combat := false
var _owns_pause := false
var _scene_id := 0
var _css_pixel_ratio := 1.0
var _css_canvas_size := Vector2.ZERO
var _viewport_check_left := 0.0
var _running := false
var _reach := 64.0
var _size := Vector2.ZERO

static func needs_rotation(size: Vector2) -> bool:
	return size.x < size.y

static func device_is_mobile() -> bool:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0", true))
	return false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	enabled = force_mobile or device_is_mobile()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = InkUi.make_theme(InkUi.FONT_SECTION)
	add_child(_root)
	_stick = Control.new()
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick.draw.connect(_draw_stick)
	_root.add_child(_stick)
	for action in ACTIONS:
		_glyphs[action] = CombatArt.texture(action)
		var control := Control.new()
		control.name = action
		control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.draw.connect(_draw_button.bind(control, action))
		_root.add_child(control)
	_use = _utility("ใช้งาน / พัก", _interact)
	_back = _utility("", _key.bind(KEY_ESCAPE))
	_back.tooltip_text = "กลับ"
	InkUi.art_button(_back, CombatArt.UiArt.texture("back"))
	_retry = _utility("ลองใหม่", _key.bind(KEY_R))
	# Separate from combat controls: above creator (25), menus (20), and FPS (100).
	_gate_layer = CanvasLayer.new()
	_gate_layer.layer = 128
	add_child(_gate_layer)
	_gate = ColorRect.new()
	_gate.color = InkUi.INK
	_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gate.mouse_filter = Control.MOUSE_FILTER_STOP
	_gate_layer.add_child(_gate)
	_label = Label.new()
	_label.text = "หมุนมือถือเป็นแนวนอนเพื่อเล่น\nRotate your phone to landscape"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InkUi.text_size(_label, InkUi.FONT_TITLE * 2)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate.add_child(_label)
	get_tree().root.focus_exited.connect(release)
	_update_context()

func _process(delta: float) -> void:
	_viewport_check_left -= delta
	if enabled and OS.has_feature("web") and _viewport_check_left <= 0.0:
		_viewport_check_left = 0.5
		if _sync_web_geometry() and _root != null:
			release()
			_layout()
	_update_context()

func _update_context() -> void:
	if _root == null:
		return
	enabled = force_mobile or device_is_mobile()
	var size := get_viewport().get_visible_rect().size
	var portrait := enabled and needs_rotation(size)
	_gate.visible = portrait
	_root.visible = enabled
	if portrait and not get_tree().paused:
		get_tree().paused = true
		_owns_pause = true
	elif not portrait and _owns_pause:
		get_tree().paused = false
		_owns_pause = false
	var scene := get_tree().current_scene
	var scene_id := scene.get_instance_id() if is_instance_valid(scene) else 0
	var combat: bool = enabled and not portrait and not get_tree().paused and is_instance_valid(scene) and scene.get_script() != null and scene.get_script().resource_path == "res://client/stage_view.gd"
	if combat:
		combat = scene.get("_screen") == null and scene.get("_session") != null
	var training:bool=is_instance_valid(scene) and scene.has_method("training_combat_active") and scene.training_combat_active()
	if training:combat=enabled and not portrait and not get_tree().paused
	if portrait and is_instance_valid(scene) and scene.get_script() != null and scene.get_script().resource_path == "res://client/hub.gd":
		var hub_stick = scene.get("_touch")
		if is_instance_valid(hub_stick):
			hub_stick.release()
	if combat != _combat or scene_id != _scene_id or size != _size:
		release()
	_combat = combat
	_scene_id = scene_id
	if size != _size:
		_size = size
		_layout()
	for child in _root.get_children():
		if child != _gate:
			child.visible = _combat
	if _combat:
		if training:
			_feedback={}
			for action in ACTIONS:
				_root.get_node(action).visible=not action in ["special","ultimate"]
				_root.get_node(action).queue_redraw()
			_use.hide();_retry.hide();_back.hide()
			return
		var hud = scene.get("_hud")
		_feedback = hud.mobile_feedback() if is_instance_valid(hud) else {}
		for action in ACTIONS:
			_root.get_node(action).visible = not (preload("res://logic/skill_build.gd").enabled() and action in ["special","ultimate"]) and not (scene.get("_session").has_method("is_lobby") and scene.get("_session").is_lobby())
			_root.get_node(action).queue_redraw()
		var session = scene.get("_session")
		if GameState.auto_battle and session != null and not session.has_method("is_remote") and not (session.has_method("is_lobby") and session.is_lobby()):
			_stick.visible = false  # auto-battler: the squad fights by itself, no stick or attack buttons
			for action in ACTIONS:
				_root.get_node(action).visible = false
		_use.visible = bool(scene.get("_near_campfire")) or not str(scene.get("_near_rest")).is_empty()
		_retry.visible = scene.get("_journey") == null and not str(scene.get("_result")).is_empty()
		_back.visible = scene.get("_journey") == null or bool(scene.get("_camp_mode")) or not str(scene.get("_result")).is_empty()

func _layout() -> void:
	_sync_web_geometry()
	# Reference: i14 Pro Max capture, ~370 CSS px of usable landscape game height.
	var density := _screen_unit()
	var fit := minf(1.0, minf(_size.y / density / 370.0, _size.x / density / 820.0))
	_reach = 96.0 * density * fit
	_stick.position = Vector2.ZERO
	_stick.size = Vector2(_size.x * 0.45, _size.y)
	var regions: Dictionary = CombatLayout.regions(_size,density*fit,44.0*density)
	for action in ACTIONS:
		var rect: Rect2 = regions[action]
		_buttons[action] = Rect2() if preload("res://logic/skill_build.gd").enabled() and action in ["special","ultimate"] else rect
		var control: Control = _root.get_node(action)
		control.position = rect.position
		control.size = rect.size
		control.queue_redraw()
	_stick.queue_redraw()
	var screen_unit := density * fit
	for i in 3:
		var button: Button = [_back, _use, _retry][i]
		button.position = Vector2(16 + i * 96 * screen_unit, 100)
		button.custom_minimum_size = Vector2.ZERO
		button.size = Vector2(88, 40) * screen_unit
		InkUi.text_size(button, int(14 * screen_unit))

func _utility(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	_root.add_child(button)
	return button

func _key(code: Key) -> void:
	var scene := get_tree().current_scene
	if not _combat or not is_instance_valid(scene):
		return
	release()
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	scene.call("_unhandled_key_input", event)

func _interact() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	_key(KEY_E if bool(scene.get("_near_campfire")) else KEY_Q)

func _input(event: InputEvent) -> void:
	if not _combat:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			for action in ACTIONS:
				if hit_action(action, event.position):
					_held[event.index] = action
					_taps[action] = true
					_root.get_node(action).queue_redraw()
					get_viewport().set_input_as_handled()
					return
			if _finger < 0 and movement_zone_contains(event.position):
				_finger = event.index
				_origin = event.position
				_stick.queue_redraw()
				get_viewport().set_input_as_handled()
		else:
			if _held.has(event.index):
				var action: String = _held[event.index]
				_held.erase(event.index)
				_root.get_node(action).queue_redraw()
				get_viewport().set_input_as_handled()
			if event.index == _finger:
				_finger = -1
				vector = Vector2.ZERO
				_running = false
				_stick.queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _finger:
			var offset: Vector2 = event.position - _origin
			vector = (offset / _reach).limit_length(1)
			var distance: float = offset.length() / _reach
			# Shorter drag enters sprint; hysteresis prevents flickering near the boundary.
			_running = distance >= (.85 if _running else 1.05)
			if distance < 0.12:
				vector = Vector2.ZERO
			_stick.queue_redraw()
			get_viewport().set_input_as_handled()
		elif _held.has(event.index):
			var action: String = _held[event.index]
			if not hit_action(action, event.position):
				_held.erase(event.index)
				_root.get_node(action).queue_redraw()
			get_viewport().set_input_as_handled()

func merge(input: RefCounted) -> RefCounted:
	if _skill_queued >= 0:
		input.skill_slot = _skill_queued
		_skill_queued = -1
	if not _combat:
		return input
	if vector != Vector2.ZERO:
		input.move = vector
	input.run = input.run or _running
	for action in ACTIONS:
		if action == "guard":
			input.set(action, input.get(action) or _held.values().has(action))
		else:
			input.set(action, input.get(action) or _taps.has(action))
	if preload("res://logic/skill_build.gd").enabled():
		if input.special: input.skill_slot = 0
		elif input.ultimate: input.skill_slot = 1
		input.special = false
		input.ultimate = false
	_taps.clear()
	return input

func release() -> void:
	_skill_queued = -1
	_running = false
	_finger = -1
	vector = Vector2.ZERO
	_held.clear()
	_taps.clear()
	if _root != null:
		for child in _root.get_children():
			child.queue_redraw()

static func screen_units_for(viewport_height: float, window_height: float, pixel_ratio: float) -> float:
	return viewport_height * pixel_ratio / window_height if window_height > 0 else 1.0

func _sync_web_geometry() -> bool:
	if not OS.has_feature("web"): return false
	var raw = JavaScriptBridge.eval("(() => { const c = document.getElementById('canvas'); if (!c) return '[]'; const r = c.getBoundingClientRect(); return JSON.stringify([r.width, r.height]); })()", true)
	var dimensions = JSON.parse_string(str(raw))
	if not dimensions is Array or dimensions.size() != 2: return false
	var next := Vector2(float(dimensions[0]), float(dimensions[1]))
	if not next.is_finite() or next.x <= 0 or next.y <= 0: return false
	var changed := next.distance_to(_css_canvas_size) > 1.0
	_css_canvas_size = next
	return changed

func _screen_unit() -> float:
	# Direct logical/CSS mapping avoids device-dependent backing-pixel/DPR assumptions.
	if OS.has_feature("web") and _css_canvas_size.y > 0:
		return _size.y / _css_canvas_size.y
	return screen_units_for(_size.y, float(DisplayServer.window_get_size().y), _css_pixel_ratio)

func movement_zone_contains(point: Vector2) -> bool:
	if not _stick.get_global_rect().has_point(point):
		return false
	# HUD and menu taps must never start a walking finger.
	if point.y < 96:
		return false
	for button in [_use, _back, _retry]:
		if button.visible and button.get_global_rect().has_point(point):
			return false
	return true

func _draw_stick() -> void:
	if _finger < 0:
		return
	var center := _origin - _stick.position
	_stick.draw_circle(center, _reach, InkUi.HUD_PANEL)
	_stick.draw_arc(center, _reach, 0, TAU, 40, InkUi.ORNAMENT, 2, true)
	_stick.draw_circle(center + vector * _reach, _reach * 0.38, InkUi.ORNAMENT)

func hit_action(action: String, point: Vector2) -> bool:
	if preload("res://logic/skill_build.gd").enabled() and action in ["special","ultimate"]: return false
	if not _buttons.has(action):
		return false
	var rect: Rect2 = _buttons[action]
	var target_size := rect.size.max(Vector2.ONE * 44.0 * _screen_unit())
	var normalized := (point - rect.get_center()) / (target_size * .5)
	return normalized.length_squared() <= 1.0

func _draw_button(control: Control, action: String) -> void:
	var pressed := _held.values().has(action)
	var center := control.size * .5
	var radius := control.size.x * .5 - 3
	var feedback: Dictionary = _feedback.get(action, {})
	var art: Texture2D = _glyphs.get(action)
	if art != null:
		control.draw_texture_rect(art, CombatArt.texture_rect(action, control.size), false, InkUi.MUTED if pressed or not feedback.get("usable", true) else control.self_modulate)
	var cooldown := clampf(float(feedback.get("ratio", 0)), 0, 1)
	if action == "ultimate":
		var charge := clampf(float(feedback.get("gauge", 0)), 0, 1)
		if charge > 0:
			control.draw_arc(center, radius - 2, -.5 * PI, -.5 * PI + TAU * charge, 64, InkUi.ULT, 4, true)
	if cooldown > 0:
		control.draw_arc(center, radius - 2, -.5 * PI, -.5 * PI + TAU * cooldown, 64, InkUi.MUTED, 5, true)
	# Labels are already in the supplied artwork; only draw a live cooldown value.
	var time: String = str(feedback.get("time", ""))
	if not time.is_empty():
		var font := control.get_theme_font("font")
		var font_size := maxi(12, roundi(control.size.x * .23))
		var width := font.get_string_size(time, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var plate := Rect2(Vector2(center.x - width * .5 - 5, control.size.y * .37), Vector2(width + 10, font_size * 1.4))
		control.draw_style_box(InkUi.capsule_style(InkUi.HUD_PANEL, plate.size.y), plate)
		control.draw_string(font, Vector2(center.x - width * .5, plate.position.y + font_size), time, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, InkUi.HUD_TEXT)

func _exit_tree() -> void:
	if _owns_pause and get_tree() != null:
		get_tree().paused = false
