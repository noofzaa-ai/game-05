extends Control
## The plain class card frame, drawn in code (crisp at any size, no image files).
## Rounded corners, a light grey two-line border (thick outer, thinner inner) with a small notch at top centre,
## a shield-hexagon badge top left, a numeric badge slot top right and a thin name plate at the bottom
## whose class accent line is the only strong class colour.
## kind: "back" the dark backdrop (below the 3D window) | "front" border, plate, badges (above the window)
##       "solid" filled card with the border (summon faces) | "ring" a rounded outline (selection / focus).
## Depth layers of the live cards (bottom to top): "base" dark card | "art" backdrop art in the rounded window with
##       a vignette and a parallax shift | (holo) | "lines" the two border lines | (3D character, masked by "mask",
##       the outer card shape) | "ui" name plate, badge and number slot.
## All values come from client/card_tokens.gd. `unit` = card width / CARD_SIZE.x.

const CardTokens := preload("res://client/card_tokens.gd")

var kind := "back"
var class_id := ""
var unit := 1.0
var compact := false  ## small cards: no name plate
var numbered := false  ## the numeric badge slot holds a number
var tint: Color = CardTokens.BORDER_INNER  ## "ring" colour / "solid" fill
var line_width := 1.0  ## "ring" width in pixels
var _backdrop: Texture2D  ## loaded in configure(), never inside _draw (a texture first loaded while drawing renders white)
var art_shift := Vector2.ZERO  ## "art" parallax, UV fraction of the card


func set_art_shift(shift: Vector2) -> void:
	if not art_shift.is_equal_approx(shift):
		art_shift = shift
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(p_class: String, p_unit: float, p_compact: bool = false) -> void:
	class_id = p_class
	unit = p_unit
	compact = p_compact
	_backdrop = CardTokens.backdrop(p_class) if kind in ["back", "art"] else null
	queue_redraw()


func set_numbered(on: bool) -> void:
	if numbered != on:
		numbered = on
		queue_redraw()


# ------------------------------------------------------------------ geometry (static)
## Rounded rectangle as a polygon (clockwise from the top edge's left end), optionally with a V notch in the top edge.
static func rounded(r: Rect2, radius: float, notch_half: float = 0.0, notch_depth: float = 0.0) -> PackedVector2Array:
	var rad := clampf(radius, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var out := PackedVector2Array()
	var cx := r.position.x + r.size.x * 0.5
	if notch_half > 0.0:
		out.append(Vector2(cx - notch_half, r.position.y))
		out.append(Vector2(cx, r.position.y + notch_depth))
		out.append(Vector2(cx + notch_half, r.position.y))
	# corners: top right, bottom right, bottom left, top left
	var centres := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	var steps: int = CardTokens.CARD_ARC_STEPS
	for corner in 4:
		for i in steps + 1:
			var angle := (float(corner) - 1.0) * PI * 0.5 + float(i) / float(steps) * PI * 0.5
			out.append(centres[corner] + Vector2(cos(angle), sin(angle)) * rad)
	if notch_half > 0.0:
		out.append(Vector2(cx - notch_half, r.position.y))
	return out


static func shield(r: Rect2, shoulder: float, waist: float) -> PackedVector2Array:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	return PackedVector2Array([Vector2(x, y + h * shoulder), Vector2(x + w * 0.5, y), Vector2(x + w, y + h * shoulder),
		Vector2(x + w, y + h * waist), Vector2(x + w * 0.5, y + h), Vector2(x, y + h * waist)])


## Rectangle where the badge sits (the screen puts its emblem letters in it).
static func badge_rect(u: float) -> Rect2:
	return Rect2(Vector2.ONE * CardTokens.CARD_BADGE_MARGIN * u, CardTokens.CARD_BADGE * u)


static func number_rect(card_width: float, u: float) -> Rect2:
	var s := CardTokens.CARD_NUMBER * u
	return Rect2(Vector2(card_width - CardTokens.CARD_BADGE_MARGIN * u - s, CardTokens.CARD_BADGE_MARGIN * u), Vector2(s, s))


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var u := unit
	var radius := CardTokens.CARD_RADIUS * u
	var full := Rect2(Vector2.ZERO, size)
	match kind:
		"ring":
			var half := line_width * 0.5
			draw_polyline(rounded(full.grow(-half), radius - half), tint, line_width, true)
		"back":
			_draw_backdrop(full, radius)
		"base", "mask":
			draw_colored_polygon(rounded(full, radius), CardTokens.NAVY)
		"art":
			_draw_art(radius)
		"lines":
			_draw_lines(radius)
		"ui":
			if not compact:
				_draw_plate(radius)
			_draw_badge()
			_draw_number()
		"solid":
			draw_colored_polygon(rounded(full, radius), tint)
			_draw_lines(radius)
		_:
			_draw_lines(radius)
			if not compact:
				_draw_plate(radius)
			_draw_badge()
			_draw_number()


func _draw_backdrop(full: Rect2, radius: float) -> void:
	var pts := rounded(full, radius)
	var art := _backdrop
	if art != null:
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append(Vector2(p.x / maxf(size.x, 1.0), p.y / maxf(size.y, 1.0)))
		draw_colored_polygon(pts, CardTokens.TEXT_LIGHT, uvs, art)
		return
	var top := CardTokens.backdrop_top(class_id)
	var bottom := CardTokens.backdrop_bottom(class_id)
	var colors := PackedColorArray()
	for p in pts:
		colors.append(top.lerp(bottom, p.y / maxf(size.y, 1.0)))
	draw_polygon(pts, colors)


## Backdrop art inside the rounded window (inside the inner line), zoomed a little and shifted by art_shift,
## then the vignette. Without art: the flat class gradient.
func _draw_art(radius: float) -> void:
	var inset := CardTokens.CARD_WINDOW_INSET * unit
	var window := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
	var pts := rounded(window, maxf(radius - inset, 0.0))
	var card := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var art := _backdrop
	if art != null:
		var uvs := PackedVector2Array()
		for p in pts:
			uvs.append(Vector2(0.5, 0.5) + (p / card - Vector2(0.5, 0.5)) / CardTokens.BACKDROP_ART_ZOOM + art_shift)
		draw_polygon(pts, _flat(pts.size()), uvs, art)
	else:
		var colors := PackedColorArray()
		for p in pts:
			colors.append(CardTokens.backdrop_top(class_id).lerp(CardTokens.backdrop_bottom(class_id), p.y / card.y))
		draw_polygon(pts, colors)
	var vuv := PackedVector2Array()
	for p in pts:
		vuv.append((p - window.position) / window.size)
	draw_polygon(pts, _flat(pts.size()), vuv, CardTokens.vignette())


## Thick outer line and thinner inner line, both light grey, both with the notch.
func _draw_lines(radius: float) -> void:
	var u := unit
	var outer_w := maxf(CardTokens.CARD_LINE_OUTER * u, 1.5)
	var inner_w := maxf(CardTokens.CARD_LINE_INNER * u, 1.0)
	var half := outer_w * 0.5
	var outer_rect := Rect2(Vector2.ONE * half, size - Vector2.ONE * outer_w)
	var notch_h := CardTokens.CARD_NOTCH_HALF * u
	var notch_d := CardTokens.CARD_NOTCH_DEPTH * u
	draw_polyline(rounded(outer_rect, radius - half, notch_h, notch_d), CardTokens.BORDER_OUTER, outer_w, true)
	var step := half + CardTokens.CARD_LINE_GAP * u + inner_w * 0.5  # centre line to centre line
	draw_polyline(rounded(outer_rect.grow(-step), radius - half - step, notch_h * 0.7, notch_d * 0.7), CardTokens.BORDER_INNER, inner_w, true)


## Where the name plate starts (card pixels); the screen puts the 3D window above it.
func plate_top() -> float:
	return size.y - (CardTokens.CARD_WINDOW_INSET + CardTokens.CARD_PLATE_H) * unit


func _draw_plate(radius: float) -> void:
	var u := unit
	var inset := CardTokens.CARD_WINDOW_INSET * u
	var rad := maxf(radius - inset, 0.0)
	var top := plate_top()
	var l := inset
	var r := size.x - inset
	var b := size.y - inset
	var plate := PackedVector2Array([Vector2(r, top), Vector2(r, b - rad)])
	for i in CardTokens.CARD_ARC_STEPS + 1:
		var a := float(i) / float(CardTokens.CARD_ARC_STEPS) * PI * 0.5
		plate.append(Vector2(r - rad, b - rad) + Vector2(cos(a), sin(a)) * rad)
	for i in CardTokens.CARD_ARC_STEPS + 1:
		var a := PI * 0.5 + float(i) / float(CardTokens.CARD_ARC_STEPS) * PI * 0.5
		plate.append(Vector2(l + rad, b - rad) + Vector2(cos(a), sin(a)) * rad)
	plate.append(Vector2(l, top))
	draw_colored_polygon(plate, CardTokens.SLATE_PLATE)
	var accent: Color = CardTokens.palette(class_id)["base"]
	var line := maxf(CardTokens.CARD_PLATE_LINE * u, 1.0)
	draw_line(Vector2(l, top + line * 0.5), Vector2(r, top + line * 0.5), accent, line)


func _draw_badge() -> void:
	var u := unit
	var accent: Color = CardTokens.palette(class_id)["base"]
	var pts := shield(badge_rect(u), CardTokens.CARD_BADGE_SHOULDER, CardTokens.CARD_BADGE_WAIST)
	draw_colored_polygon(pts, CardTokens.SLATE_PLATE)
	draw_polyline(_closed(pts), accent, maxf(CardTokens.CARD_BADGE_LINE * u, 1.0), true)


func _draw_number() -> void:
	var u := unit
	var accent: Color = CardTokens.palette(class_id)["base"]
	var r := number_rect(size.x, u)
	var pts := rounded(r, r.size.x * CardTokens.CARD_NUMBER_RADIUS)
	draw_colored_polygon(pts, accent if numbered else Color(CardTokens.NAVY, CardTokens.CARD_NUMBER_FILL_ALPHA))
	draw_polyline(_closed(pts), CardTokens.BORDER_INNER, maxf(CardTokens.CARD_LINE_INNER * u, 1.0), true)


static func _flat(count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(CardTokens.TEXT_LIGHT)
	return colors


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
