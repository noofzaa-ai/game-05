extends ColorRect
## Holographic foil + sparkles drawn over one class card (the one the pointer or focus is on).
## Cost: nothing is built until a card is first activated; when inactive it is hidden and its particles stop.
## API: setup(card_size, corner_radius), set_active(on, motion), set_tilt(tilt: Vector2 -1..1).
## Values come from client/card_tokens.gd; the look is client/card_holo.gdshader.

const CardTokens := preload("res://client/card_tokens.gd")
const SHADER := preload("res://client/card_holo.gdshader")

var _material: ShaderMaterial
var _sparkles: CPUParticles2D
var _fade := 0.0
var _active := false
var _motion := true
var _time := 0.0


var strength_scale := 1.0  ## multiplies the foil layers (editor card uses a weaker foil)


func set_strength(k: float) -> void:
	strength_scale = k
	if _material == null:
		return
	_material.set_shader_parameter("sheen_strength", CardTokens.HOLO_SHEEN * k)
	_material.set_shader_parameter("rainbow_strength", CardTokens.HOLO_RAINBOW * k)
	_material.set_shader_parameter("streak_strength", CardTokens.HOLO_STREAK * k)
	_material.set_shader_parameter("edge_strength", CardTokens.HOLO_EDGE * k)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = CardTokens.HOLO_DOT_COLOR  # the quad the shader paints on
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	set_strength(strength_scale)
	_sparkles = CPUParticles2D.new()
	_sparkles.amount = CardTokens.HOLO_SPARKLES
	_sparkles.lifetime = CardTokens.HOLO_SPARKLE_SECONDS
	_sparkles.local_coords = true
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.gravity = Vector2(0.0, -12.0)
	_sparkles.initial_velocity_min = 2.0
	_sparkles.initial_velocity_max = 10.0
	_sparkles.spread = 180.0
	_sparkles.angular_velocity_min = -60.0
	_sparkles.angular_velocity_max = 60.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CardTokens.HOLO_SPARKLE_COLOR, 0.0))
	ramp.set_color(1, Color(CardTokens.HOLO_SPARKLE_COLOR, 0.0))
	ramp.add_point(0.3, CardTokens.HOLO_SPARKLE_COLOR)
	_sparkles.color_ramp = ramp
	var star := GradientTexture2D.new()  # a soft round dot; cheap and needs no art
	star.fill = GradientTexture2D.FILL_RADIAL
	star.fill_from = Vector2(0.5, 0.5)
	star.fill_to = Vector2(0.5, 0.0)
	var dot := Gradient.new()
	dot.set_color(0, CardTokens.HOLO_DOT_COLOR)
	dot.set_color(1, CardTokens.HOLO_DOT_CLEAR)
	star.gradient = dot
	star.width = 16
	star.height = 16
	_sparkles.texture = star
	_sparkles.material = CanvasItemMaterial.new()
	(_sparkles.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparkles.emitting = false
	add_child(_sparkles)
	visible = false
	set_process(false)
	_apply_size()


func setup(card_size: Vector2, corner_radius: float) -> void:
	size = card_size
	set_meta("radius", corner_radius)
	_apply_size()


func _apply_size() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("rect_size", size)
	_material.set_shader_parameter("corner_radius", float(get_meta("radius", CardTokens.CARD_RADIUS)))
	var unit := size.x / CardTokens.CARD_SIZE.x
	_sparkles.position = size * 0.5
	_sparkles.emission_rect_extents = size * 0.42
	_sparkles.scale_amount_min = CardTokens.HOLO_SPARKLE_SIZE * unit / 16.0 * 0.5
	_sparkles.scale_amount_max = CardTokens.HOLO_SPARKLE_SIZE * unit / 16.0


## `motion` false (reduced motion): no sparkles and no moving sheen, just a still foil while active.
func set_active(on: bool, motion: bool) -> void:
	_active = on
	_motion = motion
	if on:
		visible = true
	if _sparkles != null:
		_sparkles.emitting = on and motion
	set_process(on or _fade > 0.0)


func set_tilt(tilt: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("tilt", tilt if _motion else Vector2.ZERO)


func _process(delta: float) -> void:
	_time += delta
	_fade = move_toward(_fade, 1.0 if _active else 0.0, delta / CardTokens.HOLO_FADE_SECONDS)
	_material.set_shader_parameter("intensity", _fade)
	_material.set_shader_parameter("time", _time if _motion else 0.0)
	if _fade <= 0.0 and not _active:
		visible = false
		set_process(false)
