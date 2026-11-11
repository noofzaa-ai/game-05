extends RefCounted
## One transparent atlas, with live-value HUD frames prepared from the user's new reference.
const REGIONS := {
	"light": Rect2(760, 578, 352, 334),
	"heavy": Rect2(792, 314, 264, 254),
	"guard": Rect2(108, 623, 252, 248),
	"dodge": Rect2(431, 623, 253, 248),
	"special": Rect2(1163, 623, 253, 248),
	"ultimate": Rect2(1120, 314, 258, 254),
	"hp": Rect2(94, 125, 493, 73),
	"stamina": Rect2(94, 186, 419, 73),
	"gauge": Rect2(94, 247, 400, 73),
	"trip": Rect2(699, 117, 768, 134),
	"back": Rect2(126, 387, 518, 166),
}
const BODIES := {
	"light": Rect2(782, 591, 307, 306),
	"heavy": Rect2(809, 327, 232, 231),
	"guard": Rect2(118, 635, 231, 224),
	"dodge": Rect2(441, 635, 232, 224),
	"special": Rect2(1174, 635, 232, 224),
	"ultimate": Rect2(1134, 327, 231, 231),
}
static var _cache := {}

static func texture(key: String) -> Texture2D:
	if not _cache.has(key):
		var part := AtlasTexture.new()
		part.atlas = load("res://art/ui/mobile_combat/v2/atlas.png")
		var ratio: Vector2 = part.atlas.get_size() / Vector2(1536, 1024)
		part.region = Rect2(REGIONS[key].position * ratio, REGIONS[key].size * ratio)
		part.filter_clip = true
		_cache[key] = part
	return _cache[key]

static func draw_frame(canvas: CanvasItem, key: String, rect: Rect2) -> void:
	var tex := texture(key)
	var full := Vector2(tex.get_width(), tex.get_height())
	var cap := 78.0 if key in ["hp", "stamina", "gauge"] else 110.0
	var right := 30.0 if key in ["hp", "stamina", "gauge"] else 110.0
	# Slice coordinates are authored on the1536px source; runtime UI imports may be smaller.
	var source_scale: float = full.x / REGIONS[key].size.x
	cap *= source_scale
	right *= source_scale
	var scale := rect.size.y / full.y
	var left_width := minf(cap * scale, rect.size.x * .35)
	var right_width := minf(right * scale, rect.size.x * .35)
	canvas.draw_texture_rect_region(tex, Rect2(rect.position, Vector2(left_width, rect.size.y)), Rect2(Vector2.ZERO, Vector2(cap, full.y)))
	canvas.draw_texture_rect_region(tex, Rect2(rect.position + Vector2(left_width, 0), Vector2(rect.size.x-left_width-right_width, rect.size.y)), Rect2(cap,0,full.x-cap-right,full.y))
	canvas.draw_texture_rect_region(tex, Rect2(rect.end.x-right_width, rect.position.y, right_width, rect.size.y), Rect2(full.x-right,0,right,full.y))
