extends Button
## Camp menu tiles reuse the project's plates, typography and brass symbol atlas.
const InkUi := preload("res://client/ink_ui.gd")
var card_title := ""
var caption := ""
var symbol := "camp"
var scenic := false
var scenery_seed := 0
const BACKGROUNDS := ["res://assets/ui/camp_menu/farm-v1.png", "res://assets/ui/camp_menu/journey-v1.png", "res://assets/ui/camp_menu/online-v1.png", "res://assets/ui/camp_menu/pvp-v1.png"]
var _background: Texture2D
var _symbol: TextureRect
var _title: Label
var _caption: Label
var _arrow: Label

func _ready() -> void:
	_background = load(BACKGROUNDS[scenery_seed % BACKGROUNDS.size()])
	InkUi.camp_menu_card(self)
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = card_title + (" · " + caption if not caption.is_empty() else "")
	_symbol = TextureRect.new()
	_symbol.texture = InkUi.icon(symbol, 64)
	_symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_symbol)
	_title = InkUi.label(card_title, InkUi.PAPER, InkUi.FONT_SECTION)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_caption = InkUi.label(caption, InkUi.MUTED, InkUi.FONT_CAPTION)
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_arrow = InkUi.label("›", InkUi.GOLD, InkUi.FONT_TITLE)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrow)
	resized.connect(_arrange)
	_arrange()

func _arrange() -> void:
	if _symbol == null: return
	var inset := 10.0 if size.y < 80.0 else 14.0
	var icon_size := minf(64.0, size.y * (0.30 if size.y < 100.0 else 0.38)) if scenic else minf(24.0 if size.y < 80.0 else 34.0, size.y * 0.5)
	_symbol.position = Vector2(inset + (12.0 if scenic else 0.0), (6.0 if size.y < 100.0 else 14.0) if scenic else (size.y - icon_size) * 0.5)
	_symbol.size = Vector2.ONE * icon_size
	var x := inset if scenic else inset + icon_size + 10.0
	var title_y := size.y - ((55.0 if size.y >= 100.0 else 47.0) if not caption.is_empty() else (38.0 if size.y >= 100.0 else 34.0)) if scenic else (size.y - (42.0 if not caption.is_empty() else 26.0)) * 0.5
	_title.position = Vector2(x, title_y)
	_title.size = Vector2(maxf(1.0, size.x - x - 27.0), 26.0)
	_caption.position = Vector2(x, title_y + (31.0 if scenic and size.y >= 100.0 else 24.0))
	_caption.size = Vector2(maxf(1.0, size.x - x - 27.0), 20.0)
	if not scenic and size.y < 80.0 and not caption.is_empty():
		_caption.position = Vector2(inset, size.y - 24.0)
		_caption.size.x = size.x - inset * 2.0
	_caption.visible = not caption.is_empty()
	_arrow.position = Vector2(size.x - 25.0, size.y - 37.0 if scenic else (size.y - 32.0) * 0.5)
	queue_redraw()

static func cover_region(texture: Texture2D, target: Vector2) -> Rect2:
	var source := texture.get_size()
	var ratio := target.x / maxf(target.y, 1.0)
	var crop := source
	if source.x / source.y > ratio: crop.x = source.y * ratio
	else: crop.y = source.x / ratio
	return Rect2((source - crop) * 0.5, crop)


func _draw() -> void:
	var surface := Rect2(Vector2.ONE * 8.0, size - Vector2.ONE * 16.0)
	if _background != null and surface.size.x > 0.0 and surface.size.y > 0.0:
		draw_texture_rect_region(_background, surface, cover_region(_background, surface.size), InkUi.PAPER)
		var shade := InkUi.INK
		shade.a = 0.13 if scenic else (0.74 if not caption.is_empty() else 0.88)
		draw_rect(surface, shade)
		var bottom := InkUi.INK
		bottom.a = 0.88
		var fade := Rect2(Vector2(surface.position.x, size.y * 0.52), Vector2(surface.size.x, surface.end.y - size.y * 0.52))
		draw_polygon(PackedVector2Array([fade.position, Vector2(fade.end.x,fade.position.y),fade.end,Vector2(fade.position.x,fade.end.y)]), PackedColorArray([InkUi.CLEAR,InkUi.CLEAR,bottom,bottom]))
	if scenic and _symbol != null:
		var center := _symbol.position + _symbol.size * 0.5
		var radius := _symbol.size.x * 0.70
		draw_arc(center, radius, 0.0, TAU, 64, InkUi.GOLD, 1.1, true)
		for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			var at: Vector2 = center + direction * radius
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-2.2),at+Vector2(2.2,0),at+Vector2(0,2.2),at+Vector2(-2.2,0)]), InkUi.GOLD)


class Section extends Control:
	const Ui := preload("res://client/ink_ui.gd")
	var title := ""
	var label: Label
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		label = Ui.label(title, Ui.GOLD, Ui.FONT_SECTION)
		Ui.camp_menu_section_text(label, Ui.FONT_SECTION)
		label.position = Vector2(28.0, 0.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		custom_minimum_size.y = label.get_minimum_size().y + 4.0
		resized.connect(queue_redraw)
	func _draw() -> void:
		if label == null: return
		var y := size.y * 0.5
		var diamond := PackedVector2Array([Vector2(10,y-4), Vector2(14,y), Vector2(10,y+4), Vector2(6,y), Vector2(10,y-4)])
		draw_polyline(diamond, Ui.GOLD, 1.0, true)
		draw_polyline(PackedVector2Array([Vector2(3,y-3),Vector2(0,y),Vector2(3,y+3)]), Ui.GOLD, 1.0, true)
		draw_polyline(PackedVector2Array([Vector2(17,y-3),Vector2(20,y),Vector2(17,y+3)]), Ui.GOLD, 1.0, true)
		var start := label.position.x + label.get_minimum_size().x + 12.0
		if start < size.x: draw_line(Vector2(start,y), Vector2(size.x-2,y), Ui.BORDER, 0.85, true)
