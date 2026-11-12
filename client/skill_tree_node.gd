extends Button
## One node of the card skill tree (design/gdd/skill-tree.md 9.2): the round frame art, the icon clipped to a circle under
## it, the state look (locked / available / no points / taken / draft), the cost numeral and the OR / lock / tick badges.
## Display only: the Skills tab (client/skill_tree_tab.gd) sets the fields and listens to pressed / activated.
## Every colour and size comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")

signal activated()  ## double-tap / right-click = learn (same as gear, po_defaults 2026-11-12)

enum State { LOCKED, AVAILABLE, NO_POINTS, TAKEN, DRAFT }

var node_id := ""
var kind := "minor"  ## minor | major | capstone | combo (the draw size and icon hole)
var cost := 1
var state: State = State.LOCKED
var exclusive := false  ## part of an OR pair: draws the OR seal
var selected := false
var s := 1.0
var frame: Texture2D
var art: Texture2D  ## the node icon (Button.icon is not used)
var badges := {}  ## "locked_seal" | "or_seal" | "taken_tick" -> Texture2D

const CIRCLE_POINTS := 40


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


func _draw() -> void:
	var side := minf(size.x, size.y)
	var centre := size * 0.5
	var tint: Color = CardTokens.TREE_LOCKED
	match state:
		State.AVAILABLE, State.NO_POINTS: tint = CardTokens.TREE_AVAILABLE
		State.TAKEN: tint = CardTokens.TREE_TAKEN
		State.DRAFT: tint = CardTokens.TREE_DRAFT
	if art != null:
		var r: float = side * 0.5 * float(CardTokens.TREE_ICON_HOLE.get(kind, 0.7))
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in CIRCLE_POINTS:
			var a := TAU * float(i) / float(CIRCLE_POINTS)
			var unit := Vector2(cos(a), sin(a))
			points.append(centre + unit * r)
			uvs.append(Vector2(0.5, 0.5) + unit * 0.5)
		draw_colored_polygon(points, tint, uvs, art)
	if frame != null:
		draw_texture_rect(frame, Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint if state == State.LOCKED else CardTokens.HUB_WHITE)
	if selected or has_focus():
		draw_arc(centre, side * 0.5, 0.0, TAU, 48, CardTokens.TREE_SELECT, 4.0 * s, true)
	if state == State.DRAFT:
		draw_arc(centre, side * 0.46, 0.0, TAU, 32, CardTokens.TREE_SELECT, 2.0 * s, true)
	var badge := side * CardTokens.TREE_BADGE
	var corner := Vector2(size.x - badge * 0.9, size.y - badge * 0.9)
	match state:
		State.LOCKED:
			_badge("locked_seal", corner, badge)
		State.TAKEN, State.DRAFT:
			_badge("taken_tick", corner, badge)
	if exclusive and state != State.TAKEN and state != State.DRAFT:
		_badge("or_seal", Vector2(-badge * 0.1, size.y - badge * 0.9), badge)
	if state != State.TAKEN and state != State.DRAFT:
		var font := CardTokens.display_font()
		var font_size := maxi(int(round(CardTokens.TREE_FONT_COST * s)), CardTokens.FONT_MIN)
		var text := str(cost)
		var at := Vector2(size.x * 0.5 - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, font_size * 0.95)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(1, int(3.0 * s)), CardTokens.HUB_OUTLINE)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CardTokens.TREE_COST_NO if state == State.NO_POINTS else CardTokens.HUB_CREAM)


func _badge(name: String, at: Vector2, side: float) -> void:
	var texture: Texture2D = badges.get(name)
	if texture != null:
		draw_texture_rect(texture, Rect2(at, Vector2(side, side)), false)
