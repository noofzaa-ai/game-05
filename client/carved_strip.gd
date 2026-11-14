extends Control
## A carved hub strip (pill, ribbon, plate) drawn from one art file in art/ui/hub_carved/ as a horizontal 3-slice: the
## end caps keep their shape and scale with the strip height, the middle stretches. Display only, never takes clicks.
## Used by the My Cards hub (card_deck_screen.gd) and the online status pill (online/online_account.gd).

const CardTokens := preload("res://client/card_tokens.gd")

var texture: Texture2D
var cap := 40.0  ## end cap width in art px


func _init(art: String = "", p_cap: float = 40.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = CardTokens.carved(art) if not art.is_empty() else null
	cap = p_cap
	resized.connect(queue_redraw)


func _draw() -> void:
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var k := size.y / th
	var c := minf(cap * k, size.x * 0.5)
	var src := minf(c / k, tw * 0.5)
	draw_texture_rect_region(texture, Rect2(0.0, 0.0, c, size.y), Rect2(0.0, 0.0, src, th))
	draw_texture_rect_region(texture, Rect2(c, 0.0, size.x - c * 2.0, size.y), Rect2(src, 0.0, tw - src * 2.0, th))
	draw_texture_rect_region(texture, Rect2(size.x - c, 0.0, c, size.y), Rect2(tw - src, 0.0, src, th))
