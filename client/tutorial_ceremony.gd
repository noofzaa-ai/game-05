extends Control
## The unlock ceremony (design/gdd/tutorial.md 4 unlock_ceremony): after the first goblin wave-12 clear, a full-screen
## reveal of the Magic card being unsealed (heroes are sealed in cards): the card shows at 40% colour behind a padlock
## medallion, the seal cracks (the lock scales up and fades), the colour returns with a gold glow, then the title,
## the step text and Next. Reduced motion: the unsealed card at once. Next / Enter / tap after the reveal = finished.
## Display only (the driver sends tutorial_step).

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")
const Marks := preload("res://client/tutorial_marks.gd")
const Overlay := preload("res://client/tutorial_overlay.gd")

signal finished()

const SEAL_SECONDS := 0.9
const BREAK_SECONDS := 0.6
const COLOUR_SECONDS := 0.7

var reduced_motion := false
var text := ""
var class_id := "magic"

var _shade: ColorRect
var _glow: Panel
var _card: TextureRect
var _lock: Control
var _title: Label
var _body: Label
var _next: Button
var _sat := 0.4


func _ready() -> void:
	name = "TutorialCeremony"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.color = Color(0.02, 0.02, 0.05, 0.85)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_glow = Panel.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate.a = 0.0
	add_child(_glow)
	_card = CardTokens.carved_rect(CardTokens.CARVED_FRAME_PREFIX + class_id, true)
	var window := CardTokens.carved_rect(CardTokens.CARVED_WINDOW_PREFIX + class_id, false)
	window.show_behind_parent = true
	window.name = "Window"
	_card.add_child(window)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float saturation = 0.4;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(vec3(g), c.rgb, saturation), c.a);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_card.material = mat
	window.use_parent_material = true
	add_child(_card)
	_lock = Marks.new(Marks.Kind.LOCK)
	add_child(_lock)
	_title = CardTokens.hub_label(Overlay.word("unlocked_title"), CardTokens.FONT_HUB_TITLE, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB)
	_title.modulate.a = 0.0
	add_child(_title)
	_body = CardTokens.hub_label(text, 30, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.modulate.a = 0.0
	add_child(_body)
	_next = Button.new()
	_next.name = "TutorialNext"
	_next.text = Overlay.word("next")
	_next.focus_mode = Control.FOCUS_ALL
	_next.visible = false
	_next.pressed.connect(func() -> void: finished.emit())
	add_child(_next)
	resized.connect(_layout)
	_layout()
	_play()


func _play() -> void:
	if reduced_motion:
		_set_sat(1.0)
		_lock.visible = false
		_glow.modulate.a = 1.0
		_title.modulate.a = 1.0
		_body.modulate.a = 1.0
		_reveal_next()
		return
	var t := create_tween()
	t.tween_interval(SEAL_SECONDS)
	t.tween_property(_lock, "scale", Vector2(1.6, 1.6), BREAK_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_lock, "modulate:a", 0.0, BREAK_SECONDS)
	t.tween_method(_set_sat, 0.4, 1.0, COLOUR_SECONDS)
	t.parallel().tween_property(_glow, "modulate:a", 1.0, COLOUR_SECONDS)
	t.tween_property(_title, "modulate:a", 1.0, 0.3)
	t.tween_property(_body, "modulate:a", 1.0, 0.3)
	t.tween_callback(_reveal_next)


## Skip: any tap during the reveal jumps to the end.
func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and not _next.visible:
		accept_event()
		for tw in get_tree().get_processed_tweens():
			tw.kill()
		reduced_motion = true
		_play()


func _reveal_next() -> void:
	_next.visible = true
	_layout()
	_next.grab_focus.call_deferred()


func _set_sat(v: float) -> void:
	_sat = v
	(_card.material as ShaderMaterial).set_shader_parameter("saturation", v)


func _layout() -> void:
	if _card == null or size.x <= 0.0:
		return
	var s := CardTokens.scale_for(size)
	var card_h := minf(size.y * 0.55, 560.0 * s)
	var card_w := card_h * CardTokens.HUB_CARD.x / CardTokens.HUB_CARD.y
	_card.size = Vector2(card_w, card_h)
	_card.position = Vector2((size.x - card_w) * 0.5, size.y * 0.08)
	var window: Control = _card.get_node("Window")
	var win := CardTokens.HUB_CARD_WINDOW
	window.position = Vector2(win.position.x * card_w, win.position.y * card_h)
	window.size = Vector2(win.size.x * card_w, win.size.y * card_h)
	_glow.position = _card.position - Vector2(24, 24) * s
	_glow.size = _card.size + Vector2(48, 48) * s
	CardTokens.panel(_glow, CardTokens.hub_glow(CarvedLook.GOLD_EDGE, 40.0, CardTokens.HUB_RADIUS, s))
	var edge := card_w * 0.38
	_lock.place(_card.position + (_card.size - Vector2(edge, edge)) * 0.5, edge)
	_lock.pivot_offset = Vector2(edge, edge) * 0.5
	var side := CardTokens.hub_safe_x(size, s)
	var y := _card.position.y + card_h + 18.0 * s
	_title.position = Vector2(side, y)
	_title.size = Vector2(size.x - side * 2.0, 64.0 * s)
	CardTokens.hub_fit(_title, _title.text, CardTokens.FONT_HUB_TITLE, _title.size.x, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB)
	y += _title.size.y
	_body.position = Vector2(side, y)
	_body.size = Vector2(size.x - side * 2.0, 0.0)
	CardTokens.style_text(_body, 30, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "medium", CardTokens.HUB_OUTLINE)
	_body.size.y = maxf(_body.get_minimum_size().y, 40.0 * s)
	y += _body.size.y + 12.0 * s
	var bh := CardTokens.tap(64.0, CardTokens.is_phone(size)) * s
	_next.size = Vector2(240.0 * s, bh)
	_next.position = Vector2((size.x - _next.size.x) * 0.5, minf(y, size.y - bh - CardTokens.HUB_SAFE.y * s))
	CarvedLook.plate_button(_next, s)
	CardTokens.hub_fit(_next, _next.text, 26, CarvedLook.plate_room(_next.size), CardTokens.HUB_INK, s)
