extends Control
## Compact HUD skin: live fills under the new empty brass-frame artwork.
const InkUi := preload("res://client/ink_ui.gd")
const UiArt := preload("res://client/mobile_ui_art.gd")
var source := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if not visible or source.is_empty():
		return
	position = source["back"].position
	size = source["back"].size
	queue_redraw()

func _draw() -> void:
	if source.is_empty() or size.x <= 0:
		return
	var role: String = source.get("font_role", "hp")
	var key := "hp" if role == "hp" else ("stamina" if role == "bar" else "gauge")
	UiArt.draw_frame(self, key, Rect2(Vector2.ZERO, size))
	if source["trail"].get_meta("with_trail", false):
		_draw_fill(source["trail"].size.x / maxf(source["width"], 1), source["trail"].color)
	_draw_fill(source["fill"].size.x / maxf(source["width"], 1), source["fill"].color)
	if float(source.get("low", 0)) > 0:
		draw_line(Vector2(size.y * 1.1, size.y * .81), Vector2(size.x-size.y*.6,size.y*.81), InkUi.HP_LOW, 1.0, true)

func _draw_fill(ratio: float, color: Color) -> void:
	if ratio <= 0:
		return
	var left := size.y * 1.12
	var width := (size.x-left-size.y*.65) * clampf(ratio,0,1)
	var top := size.y * .32
	var bottom := size.y * .67
	var tip := minf(size.y * .2, width*.5)
	var points := PackedVector2Array([Vector2(left,top),Vector2(left+width-tip,top),Vector2(left+width,(top+bottom)*.5),Vector2(left+width-tip,bottom),Vector2(left,bottom)])
	draw_colored_polygon(points,color)
	draw_line(points[0],points[1],color.lightened(.25),1.0,true)
