extends Control
## A virtual stick for touch screens in the camp hub: put a finger down on the left part of the screen
## and drag; `vector` is the walking direction (x right, y toward the camera), length 0..1. Drawn only
## while a finger is down. The stage has no touch controls yet; this one is the hub's own.

const InkUi := preload("res://client/ink_ui.gd")

const REACH := 70.0  ## pixels of drag for full speed
const AREA := 0.5  ## the left half of the screen starts the stick

var vector := Vector2.ZERO
var enabled := true

var _finger := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not enabled:
		release()
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _finger < 0 and touch.position.x < get_viewport_rect().size.x * AREA:
			_finger = touch.index
			_origin = touch.position
			_knob = touch.position
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif not touch.pressed and touch.index == _finger:
			release()
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _finger:
		var offset := (drag.position - _origin).limit_length(REACH)
		_knob = _origin + offset
		vector = offset / REACH
		get_viewport().set_input_as_handled()
		queue_redraw()


func release() -> void:
	if _finger < 0 and vector == Vector2.ZERO:
		return
	_finger = -1
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _finger < 0:
		return
	var ring := InkUi.ORNAMENT
	ring.a = 0.7
	var fill := InkUi.HUD_PANEL
	draw_circle(_origin, REACH, fill)
	draw_arc(_origin, REACH, 0.0, TAU, 48, ring, 3.0, true)
	draw_circle(_knob, REACH * 0.42, InkUi.ORNAMENT)
