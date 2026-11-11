extends Control
## One square on the gear screen: an equipment slot around the paper-doll, or a cell of the bag grid
## (a piece of equipment, a stack of material, or an empty cell). Drawn by hand (no child nodes) so a
## big bag stays cheap.
## Input, the same for mouse and touch:
##   press / tap            -> `tapped`      (select it: the detail panel shows it)
##   double-click / double-tap, or right-click -> `activated` (wear it / take it off)
##   hold still ~0.45 s     -> `long_pressed` (details; on a phone this opens the detail sheet)
##   drag onto another cell -> the receiving cell's `drop_check` / `drop_handler` decide what happens
## The screen that owns the cell decides what all of these mean; the cell only reports them.
## Colour is never the only signal: the tier is also shown as 1-4 diamond pips, and a selected
## cell gets a thicker frame and corner marks, not only a different colour.

const InkUi := preload("res://client/ink_ui.gd")
const ItemIcon := preload("res://client/item_icon.gd")
const BrassIcons := preload("res://client/brass_icons.gd")

signal tapped(cell)
signal activated(cell)
signal long_pressed(cell)

const LONG_PRESS_SECONDS := 0.45
const LONG_PRESS_SLOP := 12.0  ## moving further than this (menu units) is a drag, not a hold

## "slot" (an equipment slot), "item" (equipment in the bag), "material" (a stack), "empty"
var kind := "empty"
var slot_id := ""  ## slots: which slot; items: the slot the piece fits
var slot_index := 0  ## slots: position in a paired slot (two rings...)
var item = null  ## the Item shown (slots: what is worn there, or null)
var item_index := -1  ## items: index in the bag's item list
var material_id := ""
var count := 0  ## materials: how many in this stack
var icon_shape := "pouch"
var icon_texture: Texture2D  ## the item's own picture (catalog items); null = draw icon_shape
var icon_fill := InkUi.ICON_FALLBACK
var frame_color := InkUi.BORDER
var tier := -1  ## -1: no tier (empty, material)
var level := 0  ## enhancement +N
var wear_warning := 0  ## 0 fine, 1 worn (stats reduced), 2 broken down
var worn_mark := false  ## an equipment slot with something in it shows a check mark

var selected := false:
	set(value):
		selected = value
		z_index = 1 if value else 0  # the ember ring is drawn outside the cell: over its neighbours
		queue_redraw()
var highlighted := false:  ## a valid target for what is selected / dragged
	set(value):
		highlighted = value
		queue_redraw()
var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()

## Drag and drop is decided by the owner: drop_check.call(target_cell, data) -> bool,
## drop_handler.call(target_cell, data).
var touch_scroll_owner: Control
var drop_check: Callable
var drop_handler: Callable

var _hold_time := -1.0  ## seconds the press has lasted, -1 when not pressed
var _hold_from := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	if is_instance_valid(touch_scroll_owner) and touch_scroll_owner._scroll_finger >= 0:
		return  # touch scrolling owns this gesture; ignore emulated mouse presses
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			activated.emit(self)
		elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if button.double_click:
				_hold_time = -1.0
				set_process(false)
				activated.emit(self)
			else:
				tapped.emit(self)
				_hold_time = 0.0
				_hold_from = button.position
				set_process(true)
		elif not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_hold_time = -1.0
			set_process(false)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _hold_time >= 0.0 and motion.position.distance_to(_hold_from) > LONG_PRESS_SLOP:
		_hold_time = -1.0  # it became a drag
		set_process(false)


func _process(delta: float) -> void:
	if _hold_time < 0.0:
		set_process(false)
		return
	_hold_time += delta
	if _hold_time >= LONG_PRESS_SECONDS:
		_hold_time = -1.0
		set_process(false)
		long_pressed.emit(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_hold_time = -1.0
		set_process(false)


func has_thing() -> bool:
	return item != null or kind == "material"


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null or (is_instance_valid(touch_scroll_owner) and touch_scroll_owner._scroll_finger >= 0):
		return null
	var preview := Control.new()
	var ghost: Control = get_script().new()
	ghost.copy_look(self)
	ghost.size = size
	ghost.position = -size * 0.5
	ghost.modulate.a = 0.8
	preview.add_child(ghost)
	preview.scale = get_global_transform().get_scale()
	set_drag_preview(preview)
	return {"cell": self}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return drop_check.is_valid() and typeof(data) == TYPE_DICTIONARY and data.has("cell") and bool(drop_check.call(self, data))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if drop_handler.is_valid():
		drop_handler.call(self, data)


## Makes this cell look like `other` (for the drag preview).
func copy_look(other) -> void:
	kind = other.kind
	item = other.item
	icon_shape = other.icon_shape
	icon_texture = other.icon_texture
	icon_fill = other.icon_fill
	frame_color = other.frame_color
	tier = other.tier
	level = other.level
	count = other.count


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var alpha := 0.35 if dimmed else 1.0
	var back := InkUi.PANEL_LIGHT if kind != "slot" else InkUi.SLOT_BG
	draw_rect(rect, Color(back, alpha))
	var brass := InkUi.FRAME_STYLE == "engraved"
	if has_thing() and tier >= 0 and brass:  # a gem-like inner glow rising from the bottom, in the tier's color
		var glow := Color(frame_color, 0.34 * alpha)
		draw_polygon(PackedVector2Array([Vector2(0, size.y * 0.25), Vector2(size.x, size.y * 0.25), size, Vector2(0, size.y)]),
			PackedColorArray([Color(glow, 0.0), Color(glow, 0.0), glow, glow]))
	if has_thing():  # a soft inner wash behind the icon
		draw_circle(size * 0.5, size.x * 0.36, Color(frame_color, 0.10 * alpha))
	var icon_rect := rect.grow(-size.x * 0.16)
	if has_thing() and icon_texture != null:
		var bounds := rect.grow(-minf(size.x, size.y) * 0.08)
		var picture_size := icon_texture.get_size()
		var fit := minf(bounds.size.x / picture_size.x, bounds.size.y / picture_size.y)
		var fitted := picture_size * fit
		var icon_bounds := Rect2(bounds.get_center() - fitted * 0.5, fitted)
		draw_texture_rect(icon_texture, icon_bounds, false, Color(Color.WHITE, alpha))
	elif has_thing():
		ItemIcon.draw_icon(self, icon_rect, icon_shape, icon_fill, alpha)
	elif kind == "slot" and InkUi.ICON_STYLE != "plain" and BrassIcons.has(slot_id):  # what goes here, as a brass line icon
		BrassIcons.draw(self, slot_id, rect.grow(-size.x * 0.22), Color(InkUi.ICON_TINT, 0.42))
	elif kind == "slot":
		ItemIcon.draw_icon(self, icon_rect, icon_shape, Color(InkUi.MUTED, 0.5), 0.35)  # what goes here

	# Frame: the tier's colour AND shape: Normal one line, Rare two lines, Epic two lines with corner
	# brackets, Legendary two lines, studded corners and a halo. A plain dark edge when empty.
	var width := 1.0
	if tier >= 0:
		width = 2.0 + float(tier) * 0.75 if not brass else 2.0
	var edge := Color(frame_color if has_thing() else InkUi.BORDER, alpha)
	if brass and tier >= 3 and has_thing():  # Legendary: a soft halo outside the cell
		draw_rect(rect.grow(1.5), Color(frame_color, 0.45 * alpha), false, 1.5)
		draw_rect(rect.grow(3.5), Color(frame_color, 0.18 * alpha), false, 2.0)
	draw_rect(rect.grow(-width * 0.5), edge, false, width)
	if brass and tier >= 1 and has_thing():
		draw_rect(rect.grow(-4.5), Color(frame_color, 0.55 * alpha), false, 1.0)
	if brass and tier >= 2 and has_thing():
		var k := size.x * (0.2 if tier == 2 else 0.26)
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var at := Vector2(corner.x * size.x, corner.y * size.y)
			var into := Vector2(1.0 if corner.x == 0 else -1.0, 1.0 if corner.y == 0 else -1.0)
			draw_polyline(PackedVector2Array([at + Vector2(into.x * k, into.y * 1.5), at + into * 1.5, at + Vector2(into.x * 1.5, into.y * k)]), edge, 3.5, true)
			if tier >= 3:  # studs at the corners
				_gem(at + into * 6.5, 3.0, frame_color, alpha)

	var font := get_theme_default_font()
	var small := int(maxf(11.0, size.x * 0.22))
	if tier >= 0:  # tier gems (colour-blind safe): 1-4 cut gems along the bottom left
		for i in tier + 1:
			if brass:
				_gem(Vector2(8.0 + i * 9.0, size.y - 8.0), 4.2, frame_color, alpha)
			else:
				var c := Vector2(7.0 + i * 8.0, size.y - 7.0)
				var d := PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(3.5, 0), c + Vector2(0, 3.5), c + Vector2(-3.5, 0)])
				draw_colored_polygon(d, Color(InkUi.INK, alpha))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -2.5), c + Vector2(2.5, 0), c + Vector2(0, 2.5), c + Vector2(-2.5, 0)]), Color(frame_color, alpha))
	if level > 0:
		_text(font, "+%d" % level, Vector2(4.0, small + 1.0), small, Color(InkUi.GOLD, alpha))
	if kind == "material" and count > 0:
		var text := str(count)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		_text(font, text, Vector2(size.x - w - 4.0, size.y - 4.0), small, Color(InkUi.PAPER, alpha))
	if wear_warning > 0:  # a worn-down piece: a mark in the top right corner ("!" plus colour)
		var warn := InkUi.BAD if wear_warning == 2 else InkUi.WARN
		var r := maxf(7.0, size.x * 0.15)
		var c2 := Vector2(size.x - r - 2.0, r + 2.0)
		draw_circle(c2, r + 1.5, Color(InkUi.INK, alpha))
		draw_circle(c2, r, Color(warn, alpha))
		var mark_size := int(r * 1.9)
		var mark_w := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, mark_size).x
		draw_string(font, c2 + Vector2(-mark_w * 0.5, mark_size * 0.36), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, mark_size, Color(InkUi.INK, alpha))
	elif worn_mark and item != null:  # worn: a brushed check mark
		var a := Vector2(size.x - 16.0, 9.0)
		draw_polyline(PackedVector2Array([a, a + Vector2(4.0, 4.0), a + Vector2(11.0, -4.0)]), Color(InkUi.INK, alpha), 4.0, true)
		draw_polyline(PackedVector2Array([a, a + Vector2(4.0, 4.0), a + Vector2(11.0, -4.0)]), Color(InkUi.GOOD, alpha), 2.0, true)

	if highlighted:
		draw_rect(rect.grow(-1.0), InkUi.GOLD, false, 2.0)
		draw_rect(rect.grow(-4.0), Color(InkUi.GOLD, 0.35), false, 2.0)
	if selected:  # an ember ring outside the cell plus white corner brackets: never mistaken for a tier frame
		var ring := rect.grow(3.0) if brass else rect.grow(-1.5)
		draw_rect(ring, InkUi.SEAL, false, 3.0)
		var k := size.x * 0.28
		var o := 3.0 if brass else 0.0
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var sx := 1.0 if corner.x == 0 else -1.0
			var sy := 1.0 if corner.y == 0 else -1.0
			var at := Vector2(corner.x * size.x, corner.y * size.y) - Vector2(sx, sy) * o
			draw_line(at, at + Vector2(k * sx, 0.0), InkUi.SELECT_MARK, 3.0)
			draw_line(at, at + Vector2(0.0, k * sy), InkUi.SELECT_MARK, 3.0)
		if brass:  # an ember pointer on the top edge: a shape no tier frame has
			var tip := Vector2(size.x * 0.5, -3.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-7.0, -6.0), tip + Vector2(7.0, -6.0), tip + Vector2(0.0, 5.0)]), InkUi.SEAL)
			draw_polyline(PackedVector2Array([tip + Vector2(-7.0, -6.0), tip + Vector2(7.0, -6.0), tip + Vector2(0.0, 5.0), tip + Vector2(-7.0, -6.0)]), InkUi.SELECT_MARK, 1.5, true)


## A small cut gem: a dark rim, the color, and a light facet on its upper left.
func _gem(at: Vector2, r: float, color: Color, alpha: float) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r - 1.2), at + Vector2(r + 1.2, 0), at + Vector2(0, r + 1.2), at + Vector2(-r - 1.2, 0)]), Color(InkUi.INK, alpha))
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), Color(color, alpha))
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(-r, 0), at + Vector2(-r * 0.2, -r * 0.2)]), Color(InkUi.TEXT_STRONG, 0.55 * alpha))


func _text(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(InkUi.INK, color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
