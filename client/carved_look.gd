extends RefCounted
## The carved ink-wash look of the My Cards hub (Boss target art_source/boss_refs/hub_inkwash_2026-11-14/
## hub_TARGET_carved.png) for every other screen: carved gilded-wood boards and plaques, parchment insets and
## ribbons, dark ink pills and round carved buttons, all drawn from art/ui/hub_carved/.
## The art is drawn by a CarvedSkin child behind its control (show_behind_parent), scaled with the layout (StyleBoxTexture
## draws its corners at 1:1 texture pixels and cannot). A CarvedSkin under a button follows the button's state (hover /
## focus brighter, pressed darker, disabled dimmed) so behaviour, focus and tap sizes stay the button's own.
## Display only. Shared tokens of this look live here (card_tokens.gd is shared with another agent).

const CardTokens := preload("res://client/card_tokens.gd")

# art (art/ui/hub_carved/<name>.png)
const BOARD := "panel_board"  ## a big parchment window in a carved gilded-wood frame (9-slice)
const PLAQUE := "button_plaque"  ## a symmetric carved plaque with a parchment face (action buttons, tabs)
const BOARD_SMALL := "panel_board_small"  ## half size: dialog windows drawn with StyleBoxTexture (1:1 margins)
const INSET_SMALL := "inset_box_small"  ## half size: dialog buttons and fields
const INSET := "inset_box"  ## a flat parchment box with a thin ink line (detail boxes, choice chips, tiles)
const PILL := "pill"  ## the dark ink pill of the hub's top bar (dark strips: stats, tree header, gold)
const ROUND := "round_button"
const MEDALLION := "medallion"
const TITLE := "title_ribbon"
const HINT := "hint_ribbon"
const COIN := "coin"
const ICON_PREFIX := "icon_"  ## + close | back | prev | next | settings | account | blacksmith | shop | tailor | storage
const DIVIDER := "divider"
const DIVIDER_CAP := 40.0
const DIVIDER_CENTRE := Vector2(380.0, 520.0)  ## the gold diamond and its leaves
const WOOD := "tray_board"  ## dark wood board in a carved gold rim (battle plates)
const WOOD_MARGIN := 60.0
const WOOD_K := 0.22  ## battle plates are small: thin rim, corners kept
const HUD_INSET_K := 0.3  ## the parchment inset on battle plates
const SLOT := "slot_tile"
const SLOT_SELECTED := "slot_tile_selected"

# slicing, in art px of each file
const BOARD_MARGIN := 112.0  ## corners keep the carved leaves
const BOARD_K := 0.6  ## board corner art px -> reference px (so the frame is about 22 px thick at 1080)
const BOARD_FRAME := 42.0  ## frame thickness in art px (content stays inside it)
const PLAQUE_CAP := 86.0
const PLAQUE_CENTRE := Vector2(225.0, 535.0)  ## the carved leaf crest (top and bottom) kept unstretched
const INSET_MARGIN := 34.0
const INSET_K := 0.6
const PILL_CAP := 110.0
const TITLE_CAP := 150.0
const HINT_CAP := 40.0
const SLOT_MARGIN := 70.0
const ROUND_ICON := 0.5  ## icon box, of the round button

# state tints (multiplied over the art)
const TINT_NORMAL := Color(1.0, 1.0, 1.0)
const TINT_HOVER := Color(1.1, 1.06, 0.97)
const TINT_PRESSED := Color(0.86, 0.84, 0.8)
const TINT_DISABLED := Color(0.62, 0.6, 0.58)
const TINT_IDLE := Color(0.78, 0.72, 0.64)  ## an idle tab / chip next to the chosen one
const TINT_CHOSEN := Color(1.06, 1.0, 0.86)

# colours of the look
const GOLD_EDGE := Color("C8913F")  ## carved gold rim drawn in code (portrait window, chosen chip ring)
const INK_EDGE := Color("2A1A0E")
const CHOSEN_RING := Color("8A4F12")  ## the chosen chip / tab: a thick dark-gold ring (shape cue besides the tint)
const SHADE := Color(0.03, 0.04, 0.07, 0.55)  ## the night dim behind a board over the hub

# sizes (reference px at 1080)
const CHOSEN_LINE := 4.0
const PLAQUE_TEXT_INSET := 0.55  ## text clear of the plaque caps, of the cap width
const HINT_H := 46.0
const HINT_PAD := 56.0
const TITLE_H_OF_TEXT := 1.55  ## title ribbon height, of the title text line
const TITLE_PAD := 0.62  ## text clear of the ribbon tails, of the cap width


## Key names in hint lines ("Q / E = switch card", "Esc / B = back"): hidden on touch devices.
const KEY_HINT_MARKS := ["Esc", "Q / E", "Enter", "R ="]


## True on a touch device or a phone-shaped screen: hint lines show touch words only.
static func touch_hints(screen: Vector2) -> bool:
	return DisplayServer.is_touchscreen_available() or CardTokens.is_phone(screen)


## A hint line ("a  ·  b  ·  c") without the parts that name keys, when `touch` is on.
static func hint_text(text: String, touch: bool) -> String:
	if not touch:
		return text
	var sep := "  ·  " if text.contains("  ·  ") else " · "
	var kept: Array = []
	for part in text.split(sep):
		var keys := false
		for mark in KEY_HINT_MARKS:
			keys = keys or part.contains(mark)
		if not keys:
			kept.append(part)
	return sep.join(kept) if not kept.is_empty() else text


static func tex(art: String) -> Texture2D:
	return CardTokens.carved(art)


## The CarvedSkin child of `control` (made on first use), drawn behind it.
static func skin_of(control: Control) -> CarvedSkin:
	var found := control.get_node_or_null("CarvedSkin") as CarvedSkin
	if found == null:
		found = CarvedSkin.new()
		found.name = "CarvedSkin"
		found.show_behind_parent = true
		found.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		control.add_child(found)
		control.move_child(found, 0)
		if control is BaseButton:
			control.draw.connect(found.queue_redraw)
			control.focus_entered.connect(found.queue_redraw)
			control.focus_exited.connect(found.queue_redraw)
	return found


static func clear(control: Control) -> void:
	if control is Panel or control is PanelContainer:
		CardTokens.panel(control, StyleBoxEmpty.new())


## A carved gilded-wood board with a parchment face (panels, dialogs).
static func board(control: Control, s: float) -> CarvedSkin:
	clear(control)
	var sk := skin_of(control)
	sk.set_nine(BOARD, BOARD_MARGIN, BOARD_K * s)
	return sk


## Inside width of the board frame in screen px (keep content inside it).
static func board_frame(s: float) -> float:
	return BOARD_FRAME * BOARD_K * s


## The dark carved wood board of the hub tray (battle squad plates): cheap, one 9-slice draw.
static func wood_plate(control: Control) -> CarvedSkin:
	clear(control)
	var sk := skin_of(control)
	sk.set_nine(WOOD, WOOD_MARGIN, WOOD_K)
	return sk


## A flat parchment inset (detail boxes, tiles).
static func inset(control: Control, s: float, tint: Color = TINT_NORMAL) -> CarvedSkin:
	clear(control)
	var sk := skin_of(control)
	sk.set_nine(INSET, INSET_MARGIN, INSET_K * s)
	sk.base = tint
	return sk


## A dark ink pill (stat strips, the tree header, the gold counter).
static func dark_pill(control: Control, _s: float) -> CarvedSkin:
	clear(control)
	var sk := skin_of(control)
	sk.set_strip(PILL, PILL_CAP)
	return sk


## A carved wood divider bar (scrolled ends, gold diamond in the middle) at `height` screen px.
static func divider(height: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0.0, height)
	var sk := skin_of(holder)
	sk.show_behind_parent = false
	sk.set_strip(DIVIDER, DIVIDER_CAP, DIVIDER_CENTRE)
	return holder


## A parchment title ribbon (screen titles over the scene).
static func ribbon(control: Control) -> CarvedSkin:
	clear(control)
	var sk := skin_of(control)
	sk.set_strip(TITLE, TITLE_CAP)
	return sk


## The thin parchment hint ribbon (key / touch hints at the bottom).
static func hint_ribbon(control: Control) -> CarvedSkin:
	clear(control)
	var sk := skin_of(control)
	sk.set_strip(HINT, HINT_CAP)
	return sk


## Width in screen px the ribbon's tails take at height `h` (text stays clear of them).
static func ribbon_tail(h: float) -> float:
	var art := tex(TITLE)
	return TITLE_CAP * h / float(art.get_height()) * TITLE_PAD if art != null else 0.0


## An action button on a carved plaque; `chosen` / `idle` tint it (tabs). Text margins clear the caps.
static func plate_button(b: Button, s: float, state: String = "") -> void:
	var sk := skin_of(b)
	sk.set_strip(PLAQUE, PLAQUE_CAP, PLAQUE_CENTRE)
	sk.follow_button = true
	sk.base = TINT_CHOSEN if state == "chosen" else (TINT_IDLE if state == "idle" else TINT_NORMAL)
	var art := tex(PLAQUE)
	var h := b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y
	var k := h / float(art.get_height()) if art != null and h > 0.0 else 0.5
	_text_margins(b, PLAQUE_CAP * k * PLAQUE_TEXT_INSET, 0.0)
	var focus := CardTokens.hub_focus(s, 14.0)
	b.add_theme_stylebox_override("focus", focus)


## The text room on a plaque button `size` (screen px): its width minus the carved caps.
static func plate_room(size: Vector2) -> float:
	var art := tex(PLAQUE)
	var k := size.y / float(art.get_height()) if art != null else 0.5
	return maxf(size.x - PLAQUE_CAP * k * PLAQUE_TEXT_INSET * 2.0 - 8.0, 1.0)


## A choice chip on a parchment inset (settings choices, source tabs, shop offers, tailor options). The chosen one
## gets a thick dark-gold ring as well as a warmer tint (not colour only).
static func chip_button(b: Button, s: float, chosen: bool = false, idle: bool = false) -> void:
	var sk := skin_of(b)
	sk.set_nine(INSET, INSET_MARGIN, INSET_K * s)
	sk.follow_button = true
	sk.base = TINT_CHOSEN if chosen else (TINT_IDLE if idle else TINT_NORMAL)
	_text_margins(b, 10.0 * s, 4.0 * s)
	if chosen:
		var ring := CardTokens.ring(CHOSEN_RING, CHOSEN_LINE, 12.0, s)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := ring.duplicate() as StyleBoxFlat
			box.content_margin_left = 10.0 * s
			box.content_margin_right = 10.0 * s
			b.add_theme_stylebox_override(state, box)
	b.add_theme_stylebox_override("focus", CardTokens.hub_focus(s, 14.0))


## A round carved button with an icon (Back, Close, Settings, Account); keeps the round focus ring.
static func round_button(b: Button, icon: String, s: float) -> void:
	var sk := skin_of(b)
	sk.set_fit(ROUND)
	sk.follow_button = true
	var picture := b.get_node_or_null("CarvedIcon") as TextureRect
	if picture == null:
		picture = CardTokens.carved_rect(ICON_PREFIX + icon, true)
		picture.name = "CarvedIcon"
		var inset_f := (1.0 - ROUND_ICON) * 0.5
		picture.anchor_left = inset_f
		picture.anchor_top = inset_f
		picture.anchor_right = 1.0 - inset_f
		picture.anchor_bottom = 1.0 - inset_f
		b.add_child(picture)
	else:
		picture.texture = tex(ICON_PREFIX + icon)
	CardTokens.bare_button(b, s, minf(b.size.x, b.size.y) * 0.5 / maxf(s, 0.01))


## A medallion picture (TextureRect) with a service / system icon on it.
static func medallion(rect: TextureRect, icon: String) -> void:
	rect.texture = tex(MEDALLION)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var picture := rect.get_node_or_null("CarvedIcon") as TextureRect
	if picture == null:
		picture = CardTokens.carved_rect(ICON_PREFIX + icon, true)
		picture.name = "CarvedIcon"
		picture.anchor_left = 0.2
		picture.anchor_top = 0.2
		picture.anchor_right = 0.8
		picture.anchor_bottom = 0.8
		rect.add_child(picture)
	else:
		picture.texture = tex(ICON_PREFIX + icon)


## A race tile of the race picker: a parchment inset; the current race ringed in its colour, the pending one in amber.
static func race_tile(b: Button, race: String, current: bool, pending: bool, s: float) -> void:
	var sk := skin_of(b)
	sk.set_nine(INSET, INSET_MARGIN, INSET_K * s)
	sk.follow_button = true
	sk.base = TINT_NORMAL
	var edge: Color = CardTokens.race_plate(race) if current else (CardTokens.RACE_PICK_RING if pending else Color(0, 0, 0, 0))
	var ring := CardTokens.ring(edge, CardTokens.RACE_TILE_LINE_ON, CardTokens.RACE_TILE_RADIUS, s)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(state, ring.duplicate())
	b.add_theme_stylebox_override("focus", CardTokens.hub_focus(s, CardTokens.RACE_TILE_RADIUS))


## A Theme for the older dialogs built from containers (online room, friends): ink text on parchment, plain Buttons
## and LineEdits as parchment insets with an ink line, and every PanelContainer the carved board (its content
## margins clear the frame). Uses StyleBoxTexture at a fixed art scale, so it needs no layout calls.
static var _dialog_themes := {}


static func dialog_theme(font_size: int = 22) -> Theme:
	if _dialog_themes.has(font_size):
		return _dialog_themes[font_size]
	var theme := Theme.new()
	_dialog_themes[font_size] = theme
	theme.default_font_size = font_size
	var body := CardTokens.medium_font()
	if body != null:
		theme.default_font = body
	var ink := CardTokens.HUB_INK
	theme.set_color("font_color", "Label", ink)
	var tints := {"normal": TINT_NORMAL, "hover": TINT_HOVER, "pressed": TINT_PRESSED, "hover_pressed": TINT_PRESSED, "disabled": TINT_DISABLED}
	for state in tints:
		theme.set_stylebox(state, "Button", _tex_box(INSET_SMALL, INSET_MARGIN * 0.5, 0.5, tints[state], 12.0))
	theme.set_stylebox("focus", "Button", CardTokens.hub_focus(1.0, 12.0))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", ink)
	theme.set_color("font_disabled_color", "Button", Color(ink, 0.5))
	for type in ["OptionButton"]:
		for state in tints:
			theme.set_stylebox(state, type, _tex_box(INSET_SMALL, INSET_MARGIN * 0.5, 0.5, tints[state], 12.0))
		theme.set_color("font_color", type, ink)
	theme.set_stylebox("normal", "LineEdit", _tex_box(INSET_SMALL, INSET_MARGIN * 0.5, 0.5, TINT_IDLE, 12.0))
	theme.set_stylebox("focus", "LineEdit", CardTokens.hub_focus(1.0, 12.0))
	theme.set_color("font_color", "LineEdit", ink)
	theme.set_color("font_placeholder_color", "LineEdit", Color(CardTokens.HUB_TAB_IDLE, 0.85))
	theme.set_color("caret_color", "LineEdit", ink)
	theme.set_stylebox("panel", "PanelContainer", _tex_box(INSET_SMALL, INSET_MARGIN * 0.5, 0.5, TINT_NORMAL, 10.0))
	return theme


## The carved board as a StyleBoxTexture at `k` screen px per art px (dialog windows built from containers).
static func board_box(k: float = 0.5) -> StyleBoxTexture:
	return _tex_box(BOARD_SMALL, BOARD_MARGIN * 0.5, k, TINT_NORMAL, BOARD_FRAME * 0.5 + 18.0)


static func _tex_box(art: String, margin: float, _k: float, tint: Color, content: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = tex(art)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, margin)
		box.set_content_margin(side, content)
	box.modulate_color = tint
	return box


## The portrait window's rim: the class colour inside a carved gold line with an ink edge.
static func window_box(fill: Color, s: float) -> StyleBoxFlat:
	var box := CardTokens.flat(fill, GOLD_EDGE, CardTokens.CHAR_WINDOW_LINE, CardTokens.CHAR_WINDOW_RADIUS, s)
	box.shadow_color = INK_EDGE
	box.shadow_size = maxi(1, int(round(2.0 * s)))
	return box


static func _text_margins(b: Button, side: float, vertical: float) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = side
		box.content_margin_right = side
		box.content_margin_top = vertical
		box.content_margin_bottom = vertical
		b.add_theme_stylebox_override(state, box)


## Draws one hub_carved art file behind its parent: a 9-slice (corners scaled by `k`), a horizontal strip
## (caps scaled to the height, an optional unstretched centre crest) or the whole picture fitted.
class CarvedSkin extends Control:
	enum Mode { NINE, STRIP, FIT }
	var texture: Texture2D
	var mode := Mode.NINE
	var margin := 0.0  ## NINE: corner size in art px
	var k := 1.0  ## NINE: screen px per art px of the corners
	var cap := 0.0  ## STRIP: end cap in art px
	var centre := Vector2.ZERO  ## STRIP: art x-range kept unstretched (zero: none)
	var base := Color(1, 1, 1)  ## tint before the button state
	var follow_button := false  ## tint with the parent button's state

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func set_nine(art: String, p_margin: float, p_k: float) -> void:
		texture = CardTokens.carved(art)
		mode = Mode.NINE
		margin = p_margin
		k = p_k
		queue_redraw()

	func set_strip(art: String, p_cap: float, p_centre: Vector2 = Vector2.ZERO) -> void:
		texture = CardTokens.carved(art)
		mode = Mode.STRIP
		cap = p_cap
		centre = p_centre
		queue_redraw()

	func set_fit(art: String) -> void:
		texture = CardTokens.carved(art)
		mode = Mode.FIT
		queue_redraw()

	func _tint() -> Color:
		var c := base
		var b := get_parent() as BaseButton
		if not follow_button or b == null:
			return c
		match b.get_draw_mode():
			BaseButton.DRAW_DISABLED:
				return c * TINT_DISABLED
			BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED:
				return c * TINT_PRESSED
			BaseButton.DRAW_HOVER:
				return c * TINT_HOVER
		return c * (TINT_HOVER if b.has_focus() else TINT_NORMAL)

	func _draw() -> void:
		if texture == null or size.x <= 0.0 or size.y <= 0.0:
			return
		var tint := _tint()
		var tw := float(texture.get_width())
		var th := float(texture.get_height())
		match mode:
			Mode.FIT:
				var f := minf(size.x / tw, size.y / th)
				var fitted := Vector2(tw, th) * f
				draw_texture_rect(texture, Rect2((size - fitted) * 0.5, fitted), false, tint)
			Mode.STRIP:
				var kk := size.y / th
				var c := minf(cap * kk, size.x * 0.5)
				var src := minf(c / kk, tw * 0.5)
				var keep := (centre.y - centre.x) * kk
				if centre != Vector2.ZERO and size.x - c * 2.0 >= keep + 4.0:
					var rest := (size.x - c * 2.0 - keep) * 0.5
					_grid([0.0, src, centre.x, centre.y, tw - src, tw], [0.0, c, c + rest, c + rest + keep, size.x - c, size.x], [0.0, th], [0.0, size.y], tint)
				else:
					_grid([0.0, src, tw - src, tw], [0.0, c, size.x - c, size.x], [0.0, th], [0.0, size.y], tint)
			_:
				var m := minf(margin * k, minf(size.x, size.y) * 0.5)
				var sm := minf(m / maxf(k, 0.0001), minf(tw, th) * 0.5)
				_grid([0.0, sm, tw - sm, tw], [0.0, m, size.x - m, size.x], [0.0, sm, th - sm, th], [0.0, m, size.y - m, size.y], tint)

	func _grid(sx: Array, dx: Array, sy: Array, dy: Array, tint: Color) -> void:
		for j in sy.size() - 1:
			for i in sx.size() - 1:
				var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
				if dst.size.x <= 0.0 or dst.size.y <= 0.0:
					continue
				draw_texture_rect_region(texture, dst, Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j]), tint)
