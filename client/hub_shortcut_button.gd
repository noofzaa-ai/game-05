extends Button
## User-provided transparent sprite atlas. Full rectangular touch targets, independent of art alpha.
const Ink := preload("res://client/ink_ui.gd")
const SHEET := preload("res://assets/ui/hub_shortcuts/controls.png")
const REGIONS := {
	"menu_bold": Rect2(85, 126, 550, 522),
	"player_info": Rect2(804, 78, 548, 606),
	"bag": Rect2(1508, 36, 638, 650),
}
var symbol := "menu_bold"
var caption := "Menu"
var custom_texture: Texture2D
var _caption: Label
var _art: AtlasTexture

func _ready() -> void:
	text = caption
	clip_text = true
	add_theme_font_size_override("font_size", 1)
	tooltip_text = caption
	clip_text = true
	add_theme_font_size_override("font_size", 1)
	custom_minimum_size = Vector2(60, 60)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	for state in ["hover", "pressed", "focus"]:
		var bg := Color(Ink.INK, 0.45 if state != "pressed" else 0.7)
		add_theme_stylebox_override(state, Ink.flat(bg, Color(Ink.GOLD, 0.75), 1, 8, 0))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	_art = AtlasTexture.new()
	_art.atlas = custom_texture if custom_texture != null else SHEET
	var region: Rect2 = REGIONS.get(symbol, REGIONS.menu_bold)
	var ratio := SHEET.get_size() / Vector2(2172, 724)
	_art.region = Rect2(region.position * ratio, region.size * ratio)
	if custom_texture != null:
		var custom_ratio := custom_texture.get_size() / Vector2(1536, 1024)
		_art.region = Rect2(Vector2(70, 210) * custom_ratio, Vector2(1390, 620) * custom_ratio)
	_art.filter_clip = true
	_caption = Ink.label(caption, Ink.PAPER, 10)
	_caption.add_theme_constant_override("outline_size", 2)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	resized.connect(_arrange)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	_arrange()

func _arrange() -> void:
	if _caption == null: return
	_caption.position = Vector2(0, size.y - 14)
	_caption.size = Vector2(size.x, 14)
	queue_redraw()

func _draw() -> void:
	if _art == null: return
	var available := size - Vector2(6, 6)
	var fit := minf(available.x / _art.get_width(), available.y / _art.get_height())
	var drawn := _art.get_size() * fit * (0.92 if button_pressed else 1.0)
	var rect := Rect2((size - drawn) * 0.5, drawn)
	draw_texture_rect(_art, rect, false, Color(Color.WHITE, 0.45 if disabled else 1.0))
