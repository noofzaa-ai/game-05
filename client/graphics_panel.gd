extends CanvasLayer
## Settings (graphics) overlay in the hub look: the carved board service panel of client/hub_service_panel.gd
## with the settings medallion and title, then four sections (Quality, Drawn look, Scene, Effects) of rows: a
## setting's name and its choice plates (the Tailor's parchment chips; the chosen one gets the dark ring and a check).
## Opened from the hub / character screen gear (card_deck_screen.gd `settings_pressed`) and the battle HUD
## (network_status.gd); the title screen shows contents() in its own window.
## Non-pausing: online combat continues while it is open. Display only: every choice is written through
## client/graphics_options.gd (device-local), which client/graphics_runtime.gd and draw_style.gd apply.
## Back / Esc / gamepad B / a tap on the dim closes it. Every colour, size and word comes from card_tokens.gd.

const Options := preload("res://client/graphics_options.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")

## The rows: [option key, word key, values, value word keys]. Sections are [title word key, rows].
const QUALITY := [["render_scale", "gfx_render_scale", [0.5, 0.75, 1.0], ["gfx_scale_normal", "gfx_scale_high", "gfx_scale_ultra"]],
	["antialiasing", "gfx_aa", [0, 2, 4], ["gfx_off", "gfx_aa_2", "gfx_aa_4"]]]
const DRAWN := [["drawn_style", "gfx_drawn_style", ["on", "lite", "off"], ["gfx_drawn_on", "gfx_drawn_lite", "gfx_off"]]]
const SCENE := [["shadows", "gfx_shadows"], ["decorative_lights", "gfx_lights"], ["fog", "gfx_fog"], ["glow", "gfx_glow"]]
const EFFECTS := [["outline", "gfx_outline"], ["ultimate_vfx", "gfx_ult_vfx"], ["combat_vfx", "gfx_combat_vfx"], ["ultimate_camera", "gfx_ult_camera"]]

var panel: Control  ## the hub panel (SettingsPanel), for tests and shot scripts


func _ready() -> void:
	layer = 30
	panel = SettingsPanel.new()
	panel.closed.connect(queue_free)
	add_child(panel)
	panel.open()


## The settings rows in the hub look. two_columns: Quality + Scene left, Drawn look + Effects right.
## `s` is the layout scale (CardTokens.scale_for), `phone` gives every plate the 96 px phone tap height.
## Returns the content; its first plate is in meta "first_focus".
static func contents(two_columns: bool = false, s: float = 0.8, phone: bool = false) -> Control:
	var sections := [["gfx_sec_quality", QUALITY, "gfx_scale_hint"], ["gfx_sec_drawn", DRAWN, "gfx_drawn_hint"],
		["gfx_sec_scene", SCENE, ""], ["gfx_sec_effects", EFFECTS, ""]]
	var root := HBoxContainer.new()
	root.name = "Settings"
	CardTokens.gap(root, CardTokens.SET_COLUMN_GAP, s)
	var left := VBoxContainer.new()
	var right := left
	var columns := [left]
	if two_columns:
		right = VBoxContainer.new()
		columns.append(right)
	for column in columns:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		CardTokens.gap(column, CardTokens.SET_ROW_GAP, s)
		root.add_child(column)
	var placed := {0: left, 1: right, 2: left, 3: right}
	for index in sections.size():
		var section: Array = sections[index]
		var column: VBoxContainer = placed[index]
		_header(column, CardTokens.t(section[0]), s, column.get_child_count() > 0)
		for row in section[1]:
			var b := _row(column, row, s, phone)
			if not root.has_meta("first_focus"):
				root.set_meta("first_focus", b)
		if not str(section[2]).is_empty():
			_note(column, CardTokens.t(section[2]), s)
	_note(right, CardTokens.t("gfx_note"), s)
	return root


## A section title: dark ink display text over a thin divider line.
static func _header(column: VBoxContainer, text: String, s: float, gap_above: bool) -> void:
	if gap_above:
		var space := Control.new()
		space.custom_minimum_size = Vector2(0.0, CardTokens.SET_SECTION_GAP * s)
		column.add_child(space)
	var title := CardTokens.label(text, CardTokens.FONT_CHAR_TAB, CardTokens.HUB_INK, s)
	column.add_child(title)
	column.add_child(CarvedLook.divider(maxf(6.0, round(CardTokens.SET_HEADER_LINE * s * 6.0))))  # carved wood bar


## A small hint under a row (muted ink, wraps).
static func _note(column: VBoxContainer, text: String, s: float) -> void:
	var hint := CardTokens.label(text, CardTokens.FONT_CHAR_STAT, CardTokens.HUB_TAB_IDLE, s, 0, "medium")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(CardTokens.SET_LABEL_W * s, 0.0)
	column.add_child(hint)


## One setting: its name, then a plate per value (On / Off for a switch). Returns the first plate.
static func _row(column: VBoxContainer, row: Array, s: float, phone: bool) -> Button:
	var key: String = row[0]
	var values: Array = row[2] if row.size() > 2 else [true, false]
	var words: Array = row[3] if row.size() > 3 else ["gfx_on", "gfx_off"]
	var line := HBoxContainer.new()
	line.name = "Row_" + key
	CardTokens.gap(line, CardTokens.SET_CHIP_GAP, s)
	var h := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s
	var name_label := CardTokens.label(CardTokens.t(row[1]), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CardTokens.SET_LABEL_W * s, h)
	line.add_child(name_label)
	var chips: Array[Button] = []
	for index in values.size():
		var b := Button.new()
		b.name = "%s_%s" % [key, str(values[index])]
		if key == "drawn_style":
			b.name = "Drawn_" + str(values[index])  # (the name draw_style.gd's control used; shot scripts find it)
		b.text = CardTokens.t(words[index])
		b.focus_mode = Control.FOCUS_ALL
		b.clip_text = true
		b.custom_minimum_size = Vector2(CardTokens.SET_CHIP_W * s, h)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.set_meta("value", values[index])
		CarvedLook.chip_button(b, s)
		var ring := Panel.new()
		ring.name = "Ring"
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		CardTokens.panel(ring, CardTokens.ring(CardTokens.HUB_UNDERLINE, 4.0, 14.0, s))
		b.add_child(ring)
		chips.append(b)
		line.add_child(b)
	for b in chips:
		b.pressed.connect(func() -> void:
			Options.set_value(key, b.get_meta("value"))
			_mark(chips, key, words, s))
	_mark(chips, key, words, s)
	column.add_child(line)
	return chips[0]


## Shows which plate holds the saved value: a check mark, the display face and the dark ring (shape, not colour).
static func _mark(chips: Array[Button], key: String, words: Array, s: float) -> void:
	var current: Variant = Options.value(key)
	for index in chips.size():
		var b := chips[index]
		var value: Variant = b.get_meta("value")
		var on: bool = typeof(value) == typeof(current) and value == current
		b.text = ("✓ " if on else "") + CardTokens.t(words[index])
		(b.get_node("Ring") as Control).visible = on
		CarvedLook.skin_of(b).base = CarvedLook.TINT_CHOSEN if on else CarvedLook.TINT_NORMAL
		CarvedLook.skin_of(b).queue_redraw()
		CardTokens.hub_fit(b, b.text, CardTokens.FONT_CHAR_LINE, b.custom_minimum_size.x - 14.0 * s, CardTokens.HUB_INK, s, 0, "display" if on else "medium")


## The hub service panel holding the rows (in a scroll box when they don't fit, e.g. a phone).
class SettingsPanel extends "res://client/hub_service_panel.gd":
	var _scroll: ScrollContainer
	var _first: Control
	var _built := ""  ## the layout the rows were built for

	func _init() -> void:
		service = "settings"

	func build() -> void:
		CarvedLook.medallion(_icon, "settings")
		_scroll = ScrollContainer.new()
		_scroll.name = "Scroll"
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.follow_focus = true
		body.add_child(_scroll)
		body.mouse_filter = Control.MOUSE_FILTER_PASS

	func layout_body(area: Vector2) -> void:
		_scroll.position = Vector2.ZERO
		_scroll.size = area
		var row_w := CardTokens.SET_LABEL_W + CardTokens.SET_CHIP_W * 3.0 + CardTokens.SET_CHIP_GAP * 3.0
		var two := area.x >= (row_w * 2.0 + CardTokens.SET_COLUMN_GAP) * s
		var key := "%s|%.3f|%s" % [two, s, phone]
		if key == _built:
			return
		_built = key
		# the rows are rebuilt only when the columns, the scale or the phone sizes change; focus stays on a plate
		var viewport := get_viewport()
		var owner: Control = viewport.gui_get_focus_owner() if viewport != null else null
		var refocus := owner == null or owner == _close or (_scroll.is_ancestor_of(owner))
		for child in _scroll.get_children():
			_scroll.remove_child(child)
			child.queue_free()
		var content: Control = load("res://client/graphics_panel.gd").contents(two, s, phone)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(content)
		_first = content.get_meta("first_focus")
		if refocus and visible and owner != _close:
			_focus_first.call_deferred()

	func open() -> void:
		super()
		_focus_first.call_deferred()

	## Gives the first plate the focus once it is in the tree (keyboard / gamepad start here).
	func _focus_first() -> void:
		var target := first_focus()
		if is_instance_valid(target) and target.is_inside_tree() and visible:
			target.grab_focus()

	func first_focus() -> Control:
		return _first if _first != null and is_instance_valid(_first) and _first.is_inside_tree() else _close

	func currency_text(_p) -> String:
		return ""

	func refresh() -> void:
		if _gold != null:
			_gold.text = ""
