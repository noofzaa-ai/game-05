extends Control
## The new-player tutorial spotlight (design/gdd/tutorial.md 3): a full-screen 60% dim with a rounded cut-out over the
## target's live global rect (+8 px), a bobbing arrow on the side with the most room and a 1-2 line parchment text box
## (art/ui/hub_carved through client/carved_look.gd). Every tap is eaten except inside the cut-out, which reaches the
## real control underneath (_has_point returns false there); a tap outside pulses the cut-out once.
## States: spotlight (a target rect) | text (no target: a centred box + Next) | hidden. The driver
## (client/tutorial_driver.gd) owns which step shows; this node only draws and reports taps.
## Recomputes every frame from the target's rect, so resize / rotation / scrolling follow at once.
## Display only: it never sends commands.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")

signal next_pressed()
signal skip_pressed()
signal blocked_tap()  ## a tap outside the cut-out (tests read this)

const DIM := 0.6
const PAD := 8.0  ## cut-out padding, screen px
const RADIUS := 14.0
const BOB_PX := 10.0
const BOB_SECONDS := 0.9
const PULSE_SECONDS := 0.35
const BOX_MAX_W := 620.0  ## reference px
const FONT_TEXT := 30  ## reference px at 1080 (never below CardTokens.FONT_MIN = 16)
const MARGIN := 16.0  ## gap between the cut-out, the arrow and the box, reference px

## UI words of the guide itself (step texts come from data/tutorial/steps.json).
const WORDS := {
	"next": ["ต่อไป", "Next"],
	"skip_tour": ["ข้ามทัวร์", "Skip tour"],
	"replay_tour": ["ดูทัวร์อีกครั้ง", "Replay tour"],
	"locked_wave": ["ผ่านเวฟ 12", "Clear wave 12"],
	"locked_full": ["ผ่านเวฟ 12 / Clear wave 12", "ผ่านเวฟ 12 / Clear wave 12"],
	"no_race": ["เลือกเผ่าให้การ์ดนี้ก่อน", "Give this card a race first"],
	"lost_tip": ["ลองอีกครั้ง ทีมเก่งขึ้นได้ด้วยอุปกรณ์", "Try again. Gear makes the squad stronger."],
	"unlocked_title": ["ผนึกถูกทำลาย!", "The seal breaks!"],
}

var reduced_motion := false
var prefer_top := false  ## battle on phones: the box sits at the top (tutorial.md 6)
var show_skip := false:
	set(v):
		show_skip = v
		if _skip != null:
			_skip.visible = v
## The cut-out in global (viewport) px; Rect2() = no cut-out (text mode).
var hole := Rect2()

var _dim: ColorRect
var _mat: ShaderMaterial
var _ring: Panel
var _arrow: TextureRect
var _box: Panel
var _text: Label
var _next: Button
var _skip: Button
var _clock := 0.0
var _pulse := 0.0
var _s := 1.0


func _ready() -> void:
	name = "TutorialOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec4 hole = vec4(0.0);
uniform float radius = 14.0;
uniform float alpha = 0.6;
void fragment() {
	vec2 p = UV * view_size;
	float a = alpha;
	if (hole.z > 0.0) {
		vec2 c = hole.xy + hole.zw * 0.5;
		vec2 q = abs(p - c) - hole.zw * 0.5 + vec2(radius);
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
		a *= smoothstep(-1.0, 1.0, d);
	}
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_dim.material = _mat
	add_child(_dim)
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	_arrow = CardTokens.carved_rect(CarvedLook.ICON_PREFIX + "next", true)
	add_child(_arrow)
	_box = Panel.new()
	_box.name = "TutorialBox"
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	_text = CardTokens.label("", FONT_TEXT, CardTokens.HUB_INK, 1.0, 0, "medium")
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_text)
	_next = Button.new()
	_next.name = "TutorialNext"
	_next.focus_mode = Control.FOCUS_ALL
	_next.text = word("next")
	_next.pressed.connect(func() -> void: next_pressed.emit())
	_box.add_child(_next)
	_skip = Button.new()
	_skip.name = "TutorialSkip"
	_skip.focus_mode = Control.FOCUS_ALL
	_skip.text = word("skip_tour")
	_skip.visible = show_skip
	_skip.pressed.connect(func() -> void: skip_pressed.emit())
	add_child(_skip)
	visible = false


static func word(key: String) -> String:
	var pair: Array = WORDS.get(key, [key, key])
	return str(pair[0 if CardTokens.language == "th" else 1])


## Shows `text`; `with_next` adds the Next button (text steps, the fallback).
func show_step(text: String, with_next: bool) -> void:
	_text.text = text
	_next.visible = with_next
	visible = true
	if with_next:
		_next.grab_focus.call_deferred()
	_place()


## The cut-out over `rect` (global px). Rect2() = text mode (no cut-out, centred box).
func set_hole(rect: Rect2) -> void:
	hole = rect.grow(PAD) if rect.size != Vector2.ZERO else Rect2()
	_place()


func hide_step() -> void:
	visible = false


## Tap rule (tutorial.md 3): inside the cut-out the overlay is not there, so the control under it gets the tap.
func _has_point(point: Vector2) -> bool:
	if hole.size == Vector2.ZERO:
		return true
	return not _local_hole().has_point(point)


func _gui_input(event: InputEvent) -> void:
	var tap := false
	if event is InputEventMouseButton:
		tap = event.pressed
	elif event is InputEventScreenTouch:
		tap = event.pressed
	if tap:
		accept_event()
		blocked_tap.emit()
		pulse()


func pulse() -> void:
	_pulse = PULSE_SECONDS


func _local_hole() -> Rect2:
	return get_global_transform().affine_inverse() * hole if hole.size != Vector2.ZERO else Rect2()


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_pulse = maxf(_pulse - delta, 0.0)
	_place()


## Lays out the dim hole, the pulse ring, the arrow and the box for the current screen size.
func _place() -> void:
	if _box == null or size.x <= 0.0:
		return
	_s = CardTokens.scale_for(size)
	var s := _s
	var local := _local_hole()
	_mat.set_shader_parameter("view_size", size)
	_mat.set_shader_parameter("hole", Vector4(local.position.x, local.position.y, local.size.x, local.size.y))
	_mat.set_shader_parameter("radius", minf(RADIUS * s, minf(local.size.x, local.size.y) * 0.5))
	_mat.set_shader_parameter("alpha", DIM)
	# the pulse ring (a tap outside): grows a few px and fades
	var t := _pulse / PULSE_SECONDS if not reduced_motion else (1.0 if _pulse > 0.0 else 0.0)
	_ring.visible = local.size != Vector2.ZERO
	var grow := (1.0 - t) * 10.0 * s if not reduced_motion else 0.0
	_ring.position = local.position - Vector2(grow, grow)
	_ring.size = local.size + Vector2(grow, grow) * 2.0
	CardTokens.panel(_ring, CardTokens.ring(CarvedLook.GOLD_EDGE, 3.0 + 3.0 * t, RADIUS + grow / maxf(s, 0.01), s))
	_ring.modulate.a = 0.55 + 0.45 * t
	# safe area (keep text inside it)
	var safe := Rect2(Vector2(CardTokens.hub_safe_x(size, s), CardTokens.HUB_SAFE.y * s), Vector2.ZERO)
	safe.size = size - safe.position * 2.0
	# the box: 1-2 lines, width capped
	var box_w := minf(BOX_MAX_W * s, safe.size.x)
	var pad := 18.0 * s
	var tap := CardTokens.tap(56.0, CardTokens.is_phone(size)) * s
	var font_px := maxi(int(round(FONT_TEXT * s)), CardTokens.FONT_MIN)
	CardTokens.style_text(_text, FONT_TEXT, CardTokens.HUB_INK, s, 0, "medium")
	_text.size = Vector2(box_w - pad * 2.0, 0.0)
	_text.custom_minimum_size = Vector2(box_w - pad * 2.0, 0.0)
	var text_h := maxf(_text.get_minimum_size().y, font_px * 1.3)
	var next_h := tap if _next.visible else 0.0
	var box_h := pad * 2.0 + text_h + (next_h + pad * 0.5 if _next.visible else 0.0)
	_box.size = Vector2(box_w, box_h)
	CarvedLook.inset(_box, s)
	_text.position = Vector2(pad, pad)
	_text.size = Vector2(box_w - pad * 2.0, text_h)
	if _next.visible:
		_next.size = Vector2(minf(240.0 * s, box_w - pad * 2.0), next_h)
		_next.position = Vector2((box_w - _next.size.x) * 0.5, box_h - pad - next_h)
		CarvedLook.plate_button(_next, s)
		CardTokens.hub_fit(_next, _next.text, 26, CarvedLook.plate_room(_next.size), CardTokens.HUB_INK, s)
	# skip (top right, tour only)
	_skip.size = Vector2(220.0 * s, tap)
	_skip.position = Vector2(safe.end.x - _skip.size.x, safe.position.y)
	CarvedLook.plate_button(_skip, s)
	CardTokens.hub_fit(_skip, _skip.text, 24, CarvedLook.plate_room(_skip.size), CardTokens.HUB_INK, s)
	var arrow_edge := 64.0 * s
	_arrow.size = Vector2(arrow_edge, arrow_edge)
	_arrow.pivot_offset = _arrow.size * 0.5
	var gap := MARGIN * s
	var bob := 0.0 if reduced_motion else sin(_clock * TAU / BOB_SECONDS) * BOB_PX * s
	if local.size == Vector2.ZERO:
		_arrow.visible = false
		_box.position = ((size - _box.size) * 0.5).clamp(safe.position, (safe.end - _box.size).max(safe.position))
		return
	_arrow.visible = true
	# side with the most room: below / above (left / right when the target is tall)
	var room := {"below": safe.end.y - local.end.y, "above": local.position.y - safe.position.y,
		"right": safe.end.x - local.end.x, "left": local.position.x - safe.position.x}
	var need_v := box_h + arrow_edge + gap * 2.0
	var side := "above" if prefer_top and room["above"] >= need_v else ("below" if room["below"] >= room["above"] else "above")
	if room[side] < need_v:
		side = "right" if room["right"] >= room["left"] else "left"
	var centre := local.get_center()
	var at := Vector2.ZERO
	match side:
		"below":
			_arrow.rotation = PI * 0.5 * -1.0  # points up
			_arrow.position = Vector2(centre.x - arrow_edge * 0.5, local.end.y + gap + absf(bob))
			at = Vector2(centre.x - box_w * 0.5, local.end.y + gap * 2.0 + arrow_edge)
		"above":
			_arrow.rotation = PI * 0.5  # points down
			_arrow.position = Vector2(centre.x - arrow_edge * 0.5, local.position.y - gap - arrow_edge - absf(bob))
			at = Vector2(centre.x - box_w * 0.5, local.position.y - gap * 2.0 - arrow_edge - box_h)
		"right":
			_arrow.rotation = PI  # points left
			_arrow.position = Vector2(local.end.x + gap + absf(bob), centre.y - arrow_edge * 0.5)
			at = Vector2(local.end.x + gap * 2.0 + arrow_edge, centre.y - box_h * 0.5)
		_:
			_arrow.rotation = 0.0  # points right
			_arrow.position = Vector2(local.position.x - gap - arrow_edge - absf(bob), centre.y - arrow_edge * 0.5)
			at = Vector2(local.position.x - gap * 2.0 - arrow_edge - box_w, centre.y - box_h * 0.5)
	_box.position = at.clamp(safe.position, (safe.end - _box.size).max(safe.position))
