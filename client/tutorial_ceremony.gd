extends Control
## The unlock ceremony (design/gdd/tutorial.md 4 unlock_ceremony): after the first goblin wave-12 clear, a full-screen
## reveal of the Magic card being unsealed (heroes are sealed in cards): the card frame + backdrop with the LIVE Magic
## character (client/card_portrait.gd, the player's own look) inside, hidden behind a dark seal at 40% colour with a
## padlock medallion. Beat: the card glows, the seal cracks (gold rays burst out, the lock pops and fades), the seal
## lifts and the hero shows in full colour, then the title, the step text and Next.
## Cheap and phone-safe: one portrait viewport (as a hub card), code-drawn rays, a few tweens.
## Reduced motion / a tap during the reveal: the end state at once. Next / Enter = finished. Display only.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")
const Marks := preload("res://client/tutorial_marks.gd")
const Overlay := preload("res://client/tutorial_overlay.gd")
const CardPortrait := preload("res://client/card_portrait.gd")

signal finished()

const GLOW_SECONDS := 0.8
const BREAK_SECONDS := 0.6
const REVEAL_SECONDS := 0.8
const RAYS := 12

var reduced_motion := false
var text := ""
var class_id := "magic"
var look := {}  ## CardDeck.look_of(deck, "magic"); {} = the class default

var _shade: ColorRect
var _glow: Panel
var _window: Panel  ## rounded window clipping the backdrop and the portrait
var _portrait: Control
var _seal: ColorRect
var _card: TextureRect  ## the carved frame, over the window
var _burst: Control
var _burst_t := 0.0
var _lock: Control
var _title: Label
var _body: Label
var _next: Button
var _tween: Tween


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
	_window = Panel.new()
	_window.name = "Window"
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(_window)
	var back := CardTokens.carved_rect(CardTokens.CARVED_WINDOW_PREFIX + class_id, false)
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.material = Marks.locked_material().duplicate()
	_window.add_child(back)
	_portrait = CardPortrait.new()
	_portrait.name = "Portrait"
	_portrait.framing = "hub"
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(_portrait)
	_portrait.set_class(class_id)
	if not look.is_empty():
		_portrait.set_look(look)
	_portrait.set_render_mode(CardPortrait.Mode.LIVE)
	_portrait.material = back.material
	_seal = ColorRect.new()
	_seal.color = Color(0.05, 0.03, 0.09, 0.8)
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(_seal)
	_card = CardTokens.carved_rect(CardTokens.CARVED_FRAME_PREFIX + class_id, false)
	add_child(_card)
	_burst = Control.new()
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.draw.connect(_draw_burst)
	add_child(_burst)
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
		_end_state()
		return
	_tween = create_tween()
	_tween.tween_property(_glow, "modulate:a", 0.6, GLOW_SECONDS)  # 1. the card glows
	_tween.tween_method(_set_burst, 0.0, 1.0, BREAK_SECONDS)  # 2. the seal cracks
	_tween.parallel().tween_property(_lock, "scale", Vector2(1.6, 1.6), BREAK_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_lock, "modulate:a", 0.0, BREAK_SECONDS)
	_tween.tween_property(_seal, "modulate:a", 0.0, REVEAL_SECONDS)  # 3. the hero shows
	_tween.parallel().tween_method(_set_sat, 0.4, 1.0, REVEAL_SECONDS)
	_tween.parallel().tween_property(_glow, "modulate:a", 1.0, REVEAL_SECONDS)
	_tween.parallel().tween_method(_set_burst, 1.0, 0.0, REVEAL_SECONDS)
	_tween.tween_property(_title, "modulate:a", 1.0, 0.3)
	_tween.tween_property(_body, "modulate:a", 1.0, 0.3)
	_tween.tween_callback(_reveal_next)


func _end_state() -> void:
	if _tween != null:
		_tween.kill()
	_set_sat(1.0)
	_set_burst(0.0)
	_seal.modulate.a = 0.0
	_lock.visible = false
	_glow.modulate.a = 1.0
	_title.modulate.a = 1.0
	_body.modulate.a = 1.0
	_reveal_next()


## A tap during the reveal skips to the end.
func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and not _next.visible:
		accept_event()
		_end_state()


func _reveal_next() -> void:
	_next.visible = true
	_layout()
	_next.grab_focus.call_deferred()


func _set_sat(v: float) -> void:
	(_portrait.material as ShaderMaterial).set_shader_parameter("saturation", v)


func _set_burst(v: float) -> void:
	_burst_t = v
	_burst.queue_redraw()


## The crack: gold rays from the card centre, longer and brighter as _burst_t grows.
func _draw_burst() -> void:
	if _burst_t <= 0.0:
		return
	var c := _card.position + _card.size * 0.5
	var r := _card.size.y * 0.75 * _burst_t
	for i in RAYS:
		var a := TAU * float(i) / float(RAYS) + 0.13
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal() * _card.size.x * 0.03
		_burst.draw_colored_polygon(PackedVector2Array([c + side, c + dir * r, c - side]), Color(CarvedLook.GOLD_EDGE, 0.55 * _burst_t))
	_burst.draw_circle(c, _card.size.x * 0.18 * _burst_t, Color(CardTokens.HUB_CREAM, 0.7 * _burst_t))


func _layout() -> void:
	if _card == null or size.x <= 0.0:
		return
	var s := CardTokens.scale_for(size)
	var card_h := minf(size.y * 0.55, 560.0 * s)
	var card_w := card_h * CardTokens.HUB_CARD.x / CardTokens.HUB_CARD.y
	card_w = minf(card_w, size.x * 0.8)
	card_h = card_w * CardTokens.HUB_CARD.y / CardTokens.HUB_CARD.x
	_card.size = Vector2(card_w, card_h)
	_card.position = Vector2((size.x - card_w) * 0.5, size.y * 0.08)
	var win := CardTokens.HUB_CARD_WINDOW
	_window.position = _card.position + Vector2(win.position.x * card_w, win.position.y * card_h)
	_window.size = Vector2(win.size.x * card_w, win.size.y * card_h)
	CardTokens.panel(_window, CardTokens.flat(CardTokens.HUB_WINDOW_BOTTOM, CardTokens.HUB_WINDOW_BOTTOM, 0.0, CardTokens.HUB_CARD_WINDOW_RADIUS * card_w, 1.0))
	_burst.position = Vector2.ZERO
	_burst.size = size
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
