extends Button
## One node of the card skill tree (design/gdd/skill-tree.md 9.2). Boss 2026-11-23 ("pictures too small, too many
## frames"): the icon is the node. It is clipped to a circle that fills the node, with ONE drawn ring around it; the state
## is that ring's colour / thickness / dash plus the icon's brightness (no frame art, no lock / tick / OR badges):
##   locked    dark ink ring, darkened icon, cost shown
##   available light parchment ring, icon slightly dim, cost shown (red ink when the points are short)
##   taken     thick gold ring, full-colour icon, no cost
##   draft     gold ring drawn dashed, full-colour icon, no cost
##   selected  a soft glow outside the ring (not another frame)
## Display only: the Skills tab (client/skill_tree_tab.gd) sets the fields and listens to pressed / activated.
## Every colour and size comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")

signal activated()  ## double-tap / right-click = learn (same as gear, po_defaults 2026-11-12)

enum State { LOCKED, AVAILABLE, NO_POINTS, TAKEN, DRAFT }

var node_id := ""
var kind := "minor"  ## minor | major | capstone | combo (only the size differs)
var cost := 1
var state: State = State.LOCKED
var exclusive := false  ## part of an OR pair (the tab draws one "or" between the pair)
var selected := false
var s := 1.0
var art: Texture2D  ## the node icon (Button.icon is not used)

const CIRCLE_POINTS := 48
const DASHES := 12


func setup() -> void:
	focus_mode = Control.FOCUS_ALL
	flat = true
	CardTokens.bare_button(self, s, 999.0)
	gui_input.connect(_on_input)


func _on_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and (button.double_click or button.button_index == MOUSE_BUTTON_RIGHT):
		activated.emit()
		accept_event()


## Width of the one ring (screen px).
func ring_width() -> float:
	var side := minf(size.x, size.y)
	var w := side * CardTokens.TREE_RING
	if state == State.TAKEN:
		w *= CardTokens.TREE_RING_TAKEN_X
	return maxf(w, CardTokens.TREE_RING_MIN * s)


## Diameter of the icon picture (screen px): the node minus its ring.
func icon_side() -> float:
	return maxf(0.0, minf(size.x, size.y) - ring_width() * 2.0)


func _ring_color() -> Color:
	match state:
		State.AVAILABLE, State.NO_POINTS: return CardTokens.TREE_RING_OPEN
		State.TAKEN, State.DRAFT: return CardTokens.TREE_RING_TAKEN
	return CardTokens.TREE_RING_LOCKED


func _icon_tint() -> Color:
	match state:
		State.AVAILABLE, State.NO_POINTS: return CardTokens.TREE_AVAILABLE
		State.TAKEN: return CardTokens.TREE_TAKEN
		State.DRAFT: return CardTokens.TREE_DRAFT
	return CardTokens.TREE_LOCKED


## What _draw paints, in order (tests read it): [{"layer": "shadow" | "icon" | "ring" | "glow" | "cost", ...}].
## "ring" is the only frame; "glow" is the selection light outside it.
func draw_plan() -> Array:
	var side := minf(size.x, size.y)
	var centre := size * 0.5
	var ring := ring_width()
	var plan: Array = []
	plan.append({"layer": "shadow", "centre": centre + Vector2(0.0, ring * 0.6), "radius": side * 0.5, "color": CardTokens.TREE_SHADOW})
	if art != null:
		plan.append({"layer": "icon", "centre": centre, "radius": icon_side() * 0.5, "color": _icon_tint()})
	plan.append({"layer": "ring", "centre": centre, "radius": side * 0.5 - ring * 0.5, "width": ring, "color": _ring_color(), "dashed": state == State.DRAFT})
	if selected or has_focus():
		var glow := maxf(ring * 1.3, CardTokens.TREE_RING_MIN * s * 1.5)
		plan.append({"layer": "glow", "centre": centre, "radius": side * 0.5 + glow * 0.5, "width": glow, "color": CardTokens.TREE_SELECT})
	if state != State.TAKEN and state != State.DRAFT:
		plan.append({"layer": "cost", "text": str(cost), "color": CardTokens.TREE_COST_NO if state == State.NO_POINTS else CardTokens.HUB_CREAM})
	return plan


func _draw() -> void:
	for step in draw_plan():
		match str(step["layer"]):
			"shadow":
				draw_circle(step["centre"], step["radius"], step["color"], true, -1.0, true)
			"icon":
				_draw_icon(step["centre"], step["radius"], step["color"])
			"ring":
				if step["dashed"]:
					var arc := TAU / float(DASHES)
					for i in DASHES:
						draw_arc(step["centre"], step["radius"], arc * i, arc * (i + 0.62), 6, step["color"], step["width"], true)
				else:
					draw_arc(step["centre"], step["radius"], 0.0, TAU, CIRCLE_POINTS, step["color"], step["width"], true)
			"glow":
				var faded: Color = step["color"]
				faded.a *= 0.35
				draw_arc(step["centre"], float(step["radius"]) + float(step["width"]) * 0.6, 0.0, TAU, CIRCLE_POINTS, faded, float(step["width"]) * 0.8, true)
				draw_arc(step["centre"], step["radius"], 0.0, TAU, CIRCLE_POINTS, step["color"], step["width"], true)
			"cost":
				_draw_cost(step["text"], step["color"])


func _draw_icon(centre: Vector2, r: float, tint: Color) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in CIRCLE_POINTS:
		var a := TAU * float(i) / float(CIRCLE_POINTS)
		var unit := Vector2(cos(a), sin(a))
		points.append(centre + unit * r)
		uvs.append(Vector2(0.5, 0.5) + unit * 0.5)
	draw_colored_polygon(points, tint, uvs, art)


## The cost numeral, small, in outlined ink over the top of the ring (no box of its own).
func _draw_cost(text: String, color: Color) -> void:
	var font := CardTokens.display_font()
	var font_size := maxi(int(round(CardTokens.TREE_FONT_COST * s)), CardTokens.FONT_MIN)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(size.x * 0.5 - w * 0.5, font_size * 0.8)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, int(4.0 * s)), CardTokens.HUB_OUTLINE)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
