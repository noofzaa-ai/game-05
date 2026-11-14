extends Control
## Tutorial gate marks (design/gdd/tutorial.md 5): a carved medallion (art/ui/hub_carved/medallion.png) holding a
## padlock (a locked class / race) or a "?" (a card with no race yet). Sits where the race badge goes.
## The padlock is a simple vector glyph drawn in code until a Codex padlock icon is approved (OPEN, see report).
## Display only; never takes taps.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")

const SATURATION := 0.4  ## locked art keeps 40% of its colour (tutorial.md 5)

enum Kind { LOCK, UNKNOWN }

var kind := Kind.LOCK
var _medal: TextureRect
var _mark: Label

static var _locked_mat: ShaderMaterial


func _init(p_kind: Kind = Kind.LOCK) -> void:
	kind = p_kind
	name = "LockMark" if kind == Kind.LOCK else "RacelessMark"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal = TextureRect.new()
	_medal.texture = CarvedLook.tex(CarvedLook.MEDALLION)
	_medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_medal)
	_mark = Label.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mark.text = "?" if kind == Kind.UNKNOWN else ""
	add_child(_mark)
	resized.connect(_restyle)


func place(at: Vector2, edge: float) -> void:
	position = at
	size = Vector2(edge, edge)
	_restyle()


func _restyle() -> void:
	CardTokens.style_text(_mark, int(maxf(size.y * 0.55, 8.0)), CardTokens.HUB_INK, 1.0)
	queue_redraw()


func _draw() -> void:
	if kind != Kind.LOCK:
		return
	var e := minf(size.x, size.y)
	var c := size * 0.5
	var ink := CardTokens.HUB_INK
	var body := Rect2(c + Vector2(-e * 0.17, -e * 0.02), Vector2(e * 0.34, e * 0.26))
	draw_arc(c + Vector2(0.0, -e * 0.04), e * 0.11, PI, TAU, 16, ink, maxf(e * 0.06, 2.0), true)
	draw_rect(body, ink)
	draw_circle(body.get_center() - Vector2(0.0, e * 0.02), e * 0.035, CardTokens.HUB_CREAM)


## Canvas material: keeps SATURATION of the colour (the locked Magic card, the locked Runeborn tile).
static func locked_material() -> ShaderMaterial:
	if _locked_mat == null:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nuniform float saturation = %.2f;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(vec3(g), c.rgb, saturation), c.a);\n}\n" % SATURATION
		_locked_mat = ShaderMaterial.new()
		_locked_mat.shader = shader
	return _locked_mat
