extends RefCounted
## Placeholder item icons, drawn from a few shapes (there is no icon art yet): one silhouette per
## equipment slot (per weapon type for weapons) and per material, filled with a color and outlined in
## ink. Real icon art replaces draw_icon() later; the cells that call it stay the same.
## Shapes are written in a 0..1 square (x right, y down).
## EXTENDING: a new slot or weapon type is one more entry in SHAPES (a list of polygons) or a case
## in _extra().

const InkUi := preload("res://client/ink_ui.gd")

const MaterialIcons := preload("res://client/material_icons.gd")

## shape name -> list of polygons (each a list of [x, y] points in the unit square)
const SHAPES := {
	"blade": [[[0.18, 0.86], [0.12, 0.80], [0.30, 0.66], [0.26, 0.60], [0.33, 0.56], [0.40, 0.63], [0.80, 0.14], [0.90, 0.10], [0.86, 0.20], [0.44, 0.67], [0.50, 0.74], [0.45, 0.80], [0.38, 0.72]]],
	"dagger": [[[0.25, 0.80], [0.20, 0.74], [0.34, 0.62], [0.30, 0.56], [0.36, 0.52], [0.43, 0.58], [0.70, 0.30], [0.78, 0.26], [0.74, 0.34], [0.48, 0.63], [0.52, 0.69], [0.47, 0.73], [0.40, 0.66]]],
	"spear": [[[0.12, 0.92], [0.08, 0.88], [0.66, 0.30], [0.62, 0.22], [0.90, 0.08], [0.76, 0.36], [0.70, 0.34]]],
	"hammer": [[[0.20, 0.90], [0.14, 0.84], [0.50, 0.46], [0.56, 0.52]], [[0.40, 0.30], [0.62, 0.10], [0.90, 0.38], [0.68, 0.60]]],
	"fists": [[[0.26, 0.40], [0.34, 0.26], [0.74, 0.26], [0.80, 0.40], [0.78, 0.62], [0.64, 0.80], [0.36, 0.80], [0.24, 0.62]]],
	"hat": [[[0.06, 0.66], [0.50, 0.18], [0.94, 0.66], [0.80, 0.72], [0.20, 0.72]]],
	"shirt": [[[0.30, 0.14], [0.42, 0.20], [0.50, 0.34], [0.58, 0.20], [0.70, 0.14], [0.92, 0.36], [0.80, 0.48], [0.72, 0.42], [0.72, 0.88], [0.28, 0.88], [0.28, 0.42], [0.20, 0.48], [0.08, 0.36]]],
	"pants": [[[0.28, 0.14], [0.72, 0.14], [0.80, 0.88], [0.58, 0.88], [0.50, 0.42], [0.42, 0.88], [0.20, 0.88]]],
	"armband": [[[0.30, 0.20], [0.70, 0.16], [0.76, 0.82], [0.24, 0.84]]],
	"shoes": [[[0.30, 0.16], [0.52, 0.16], [0.54, 0.58], [0.86, 0.68], [0.90, 0.84], [0.22, 0.84], [0.24, 0.60]]],
	"necklace": [[[0.44, 0.62], [0.56, 0.62], [0.62, 0.74], [0.50, 0.90], [0.38, 0.74]]],
	"earring": [[[0.42, 0.50], [0.58, 0.50], [0.64, 0.66], [0.50, 0.88], [0.36, 0.66]]],
	"bracelet": [],
	"ring": [[[0.40, 0.14], [0.60, 0.14], [0.68, 0.26], [0.50, 0.38], [0.32, 0.26]]],
	"back": [[[0.30, 0.12], [0.70, 0.12], [0.88, 0.88], [0.66, 0.80], [0.50, 0.90], [0.34, 0.80], [0.12, 0.88]]],
	"ore": [[[0.20, 0.70], [0.24, 0.40], [0.44, 0.22], [0.70, 0.28], [0.84, 0.52], [0.76, 0.78], [0.42, 0.84]]],
	"leather": [[[0.18, 0.24], [0.40, 0.16], [0.62, 0.22], [0.84, 0.18], [0.80, 0.50], [0.86, 0.80], [0.56, 0.86], [0.30, 0.82], [0.14, 0.56]]],
	"essence": [[[0.50, 0.12], [0.78, 0.50], [0.50, 0.90], [0.22, 0.50]]],
	"herb": [[[0.50, 0.90], [0.46, 0.60], [0.20, 0.44], [0.30, 0.26], [0.48, 0.40], [0.50, 0.12], [0.56, 0.40], [0.76, 0.24], [0.82, 0.46], [0.56, 0.62]]],
	"pouch": [[[0.36, 0.20], [0.64, 0.20], [0.58, 0.32], [0.82, 0.56], [0.74, 0.86], [0.26, 0.86], [0.18, 0.56], [0.42, 0.32]]],
}


## The shape for an item: weapons by weapon type, everything else by slot.
static func shape_for(slot_id: String, weapon_type: String = "") -> String:
	if slot_id == "weapon":
		return weapon_type if SHAPES.has(weapon_type) else "blade"
	return slot_id if SHAPES.has(slot_id) or MaterialIcons.TEXTURES.has(slot_id) else "pouch"


## Draws icon `shape` into `rect` on `canvas` (call from a _draw()). `fill` colors the body;
## `alpha` fades the whole thing (empty slots show a faint silhouette).
static func draw_icon(canvas: CanvasItem, rect: Rect2, shape: String, fill: Color, alpha: float = 1.0) -> void:
	if MaterialIcons.TEXTURES.has(shape):
		canvas.draw_texture_rect(MaterialIcons.TEXTURES[shape], rect, false, Color(1.0, 1.0, 1.0, alpha))
		return
	var ink := Color(InkUi.ICON_INK, alpha)
	var body := Color(fill, fill.a * alpha)
	var line_width := maxf(1.5, rect.size.x * 0.045)
	for polygon in SHAPES.get(shape, SHAPES["pouch"]):
		var points := PackedVector2Array()
		for p in polygon:
			points.append(rect.position + Vector2(p[0], p[1]) * rect.size)
		if points.size() >= 3:
			canvas.draw_colored_polygon(points, body)
			var outline := points.duplicate()
			outline.append(points[0])
			canvas.draw_polyline(outline, ink, line_width, true)
	_extra(canvas, rect, shape, ink, body, line_width)


## Shapes that are rings and lines rather than filled polygons.
static func _extra(canvas: CanvasItem, rect: Rect2, shape: String, ink: Color, body: Color, width: float) -> void:
	var center := rect.position + rect.size * 0.5
	var r := rect.size.x
	match shape:
		"ring":
			canvas.draw_arc(center + Vector2(0.0, r * 0.12), r * 0.26, 0.0, TAU, 28, ink, width * 2.6, true)
			canvas.draw_arc(center + Vector2(0.0, r * 0.12), r * 0.26, 0.0, TAU, 28, body, width * 1.2, true)
		"bracelet":
			canvas.draw_arc(center, r * 0.32, 0.0, TAU, 32, ink, width * 3.0, true)
			canvas.draw_arc(center, r * 0.32, 0.0, TAU, 32, body, width * 1.4, true)
			for i in 6:
				var at := center + Vector2.from_angle(TAU * i / 6.0) * r * 0.32
				canvas.draw_circle(at, r * 0.06, ink)
				canvas.draw_circle(at, r * 0.04, body)
		"necklace":
			canvas.draw_arc(center + Vector2(0.0, -r * 0.12), r * 0.30, 0.15, PI - 0.15, 24, ink, width * 2.2, true)
			canvas.draw_arc(center + Vector2(0.0, -r * 0.12), r * 0.30, 0.15, PI - 0.15, 24, body, width * 0.9, true)
		"earring":
			canvas.draw_arc(center + Vector2(0.0, -r * 0.18), r * 0.13, 0.0, TAU, 20, ink, width * 2.0, true)
			canvas.draw_arc(center + Vector2(0.0, -r * 0.18), r * 0.13, 0.0, TAU, 20, body, width * 0.8, true)
		"armband":
			for y in [0.38, 0.62]:
				canvas.draw_line(rect.position + Vector2(0.28, y) * rect.size, rect.position + Vector2(0.73, y - 0.02) * rect.size, ink, width)
		"hat":
			canvas.draw_line(rect.position + Vector2(0.5, 0.18) * rect.size, rect.position + Vector2(0.5, 0.72) * rect.size, Color(ink, ink.a * 0.5), width * 0.7)
