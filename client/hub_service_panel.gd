extends Control
## Base of the hub service panels (docs/ui/hub_layout_spec.md §2): a carved gilded-wood board with a parchment face centred over the
## dimmed hub with the service medallion + title, the gold counter, a Close button and a status line for outcome
## messages. Subclasses (hub_blacksmith_panel.gd, hub_storage_panel.gd) build their content in `body` and redraw
## it in refresh(). Display only: every change is a server command through `send` (the hub's _send, rules in
## logic/commands.gd); after each answer the panel redraws from GameState.profile.
## Back / Esc / gamepad B / a tap on the dim closes it. Every colour, size and word comes from card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const HubItemCell := preload("res://client/hub_item_cell.gd")
const HubItemDetails := preload("res://client/hub_item_details.gd")
const CarvedLook := preload("res://client/carved_look.gd")  ## the carved ink-wash look (Boss 2026-11-14)

signal closed()
signal changed()  ## the profile changed (the hub refreshes gold / cards)

## (request: Dictionary) -> Dictionary, may be a coroutine (the hub's _send).
var send: Callable
var service := ""
var full_screen := false  ## Tailor: the panel fills the safe area (spec §2: "Tailor may be full screen")
var reduced_motion := false
var s := 1.0
var phone := false
var body: Control  ## the content area (subclasses place their nodes in it)
var _shade: Panel
var _box: Panel
var _paper: Panel
var _icon: TextureRect
var _title: Label
var _gold: Label
var _status: Label
var _close: Button
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = Panel.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	CardTokens.panel(_shade, CardTokens.hub_shade(CardTokens.HUB_DIM))
	_shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_shade)
	_box = Panel.new()
	add_child(_box)
	_paper = Panel.new()
	_box.add_child(_paper)
	var icon_name := service
	for entry in CardTokens.HUB_SERVICES:
		if str(entry["id"]) == service:
			icon_name = str(entry["icon"])
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CarvedLook.medallion(_icon, icon_name)
	_paper.add_child(_icon)
	_title = CardTokens.label(CardTokens.t("svc_" + service), CardTokens.FONT_HUB_PANEL_TITLE, CardTokens.HUB_INK, 1.0)
	_paper.add_child(_title)
	_gold = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_paper.add_child(_gold)
	_close = Button.new()
	_close.tooltip_text = CardTokens.t("close")  # a round carved button with an X (the word is its tooltip)
	_close.focus_mode = Control.FOCUS_ALL
	_close.pressed.connect(close)
	_paper.add_child(_close)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.add_child(body)
	_status = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_paper.add_child(_status)
	build()
	resized.connect(_layout)
	_layout()


func open() -> void:
	visible = true
	_status.text = ""
	_layout()
	if reduced_motion:
		_box.modulate.a = 1.0
	else:
		_box.modulate.a = 0.0
		create_tween().tween_property(_box, "modulate:a", 1.0, CardTokens.FADE_SECONDS)
	first_focus().grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _layout() -> void:
	if _box == null:
		return
	s = CardTokens.scale_for(size)
	phone = CardTokens.is_phone(size)
	var side := CardTokens.hub_safe_x(size, s)
	var want := CardTokens.SVC_PANEL * s if not full_screen else size
	_box.size = Vector2(minf(want.x, size.x - side * 2.0), minf(want.y, size.y - CardTokens.HUB_SAFE.y * s * 2.0))
	_box.position = (size - _box.size) * 0.5
	CarvedLook.board(_box, s)  # carved gilded-wood board with the parchment face (the paper is the board's own)
	var m := CarvedLook.board_frame(s) + CardTokens.SVC_LEATHER * s * 0.35
	_paper.position = Vector2(m, m)
	_paper.size = _box.size - Vector2(m, m) * 2.0
	CardTokens.panel(_paper, CardTokens.clear_style())
	var pad := CardTokens.SVC_PAD * s
	var head := CardTokens.tap(CardTokens.SVC_HEAD, phone) * s
	_icon.size = Vector2(head, head)
	_icon.position = Vector2(pad, pad * 0.5)
	_title.position = Vector2(pad * 1.5 + head, pad * 0.5)
	_title.size = Vector2(_paper.size.x * 0.4, head)
	CardTokens.hub_text(_title, CardTokens.FONT_HUB_PANEL_TITLE, CardTokens.HUB_INK, s)
	var close_w := head
	_close.size = Vector2(close_w, head)
	_close.position = Vector2(_paper.size.x - pad * 0.5 - close_w, pad * 0.5)
	CarvedLook.round_button(_close, "close", s)
	# the money on a dark ink pill, cream text (the hub's gold pill)
	var pill_h := head * 0.72
	_gold.size = Vector2(_paper.size.x * CardTokens.SVC_GOLD_W, pill_h)
	_gold.position = Vector2(_close.position.x - pad - _gold.size.x, pad * 0.5 + (head - pill_h) * 0.5)
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CarvedLook.dark_pill(_gold, s)
	CardTokens.hub_text(_gold, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_CREAM, s, 0, "medium")
	# the outcome line sits in the header, between the title and the gold (always in view, never under buttons)
	var title_w := CardTokens.display_font().get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(round(CardTokens.FONT_HUB_PANEL_TITLE * s)), CardTokens.FONT_MIN)).x
	var status_x := _title.position.x + title_w + pad
	_status.position = Vector2(status_x, pad * 0.5)
	_status.size = Vector2(maxf(_gold.position.x - status_x - pad * 0.5, 0.0), head)
	_gold.visible = not _gold.text.is_empty()
	CardTokens.hub_text(_status, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_GOOD, s, 0, "medium")
	body.position = Vector2(pad, pad + head + pad * 0.4)
	body.size = Vector2(_paper.size.x - pad * 2.0, _paper.size.y - body.position.y - pad * 0.8)
	layout_body(body.size)
	refresh()


func _profile():
	return GameState.profile if GameState.ensure_profile() else null


## Redraws from the profile; subclasses call super() first.
func refresh() -> void:
	var p = _profile()
	if p != null and _gold != null:
		_gold.text = currency_text(p)
		_gold.visible = not _gold.text.is_empty()
		_fit_gold()


## The gold pill grows to its text (Tailor adds diamonds), right-aligned against Close.
func _fit_gold() -> void:
	if _gold == null or _close == null:
		return
	var font: Font = _gold.get_theme_font("font")
	var px := _gold.get_theme_font_size("font_size")
	var want := (font.get_string_size(_gold.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if font != null else 0.0) + _gold.size.y * 1.2
	var right := _gold.position.x + _gold.size.x
	_gold.size.x = maxf(_paper.size.x * CardTokens.SVC_GOLD_W, want)
	_gold.position.x = right - _gold.size.x


func say(text: String, good: bool = true) -> void:
	_status.text = text
	CardTokens.hub_text(_status, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_GOOD if good else CardTokens.HUB_BAD, s, 0, "medium")


## Sends one command; a refusal shows its reason in the status line. Returns the result.
func run(request: Dictionary) -> Dictionary:
	if _busy or not send.is_valid():
		return {"ok": false}
	_busy = true
	var result: Dictionary = await send.call(request)
	_busy = false
	if not result.get("ok", false):
		say(CardTokens.error_text(str(result.get("error", result.get("reason", "")))), false)
	else:
		changed.emit()
	refresh()
	return result


## A small parchment plate button (source tabs, card picker).
func plate(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	b.pressed.connect(callback)
	return b


func style_plate(b: Button, on: bool) -> void:
	CarvedLook.chip_button(b, s, on, not on)
	var w := b.size.x if b.size.x > 0.0 else b.custom_minimum_size.x
	CardTokens.hub_fit(b, b.text, CardTokens.FONT_CHAR_LINE, maxf(w - 16.0 * s, 1.0), CardTokens.HUB_INK if on else CardTokens.HUB_TAB_IDLE, s, 0, "display" if on else "medium")


## A grid of item cells inside a scroll box; returns the GridContainer.
func make_grid(parent: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var grid := GridContainer.new()
	scroll.add_child(grid)
	return grid


## Places a grid's scroll box at `rect` and sets its columns from the cell size.
func place_grid(grid: GridContainer, rect: Rect2) -> void:
	var scroll := grid.get_parent() as ScrollContainer
	scroll.position = rect.position
	scroll.size = rect.size
	var cell := CardTokens.tap(CardTokens.CHAR_STORE_CELL, phone) * s
	var gap := CardTokens.CHAR_STORE_GAP * s
	grid.columns = maxi(1, int((rect.size.x + gap) / (cell + gap)))
	CardTokens.flow_gap(grid, CardTokens.CHAR_STORE_GAP, s)


## Fills `grid` with `items` (at least `min_cells` cells, whole rows). `cells` is the pool of HubItemCell nodes;
## a tap calls on_tap(item), a double-tap / right-click on_activate(item).
func fill_grid(grid: GridContainer, cells: Array, items: Array, min_cells: int, selected_id: String, on_tap: Callable, on_activate: Callable = Callable()) -> void:
	var rules = GameState.item_rules
	var columns := maxi(grid.columns, 1)
	var count := maxi(items.size(), min_cells)
	count = int(ceil(float(count) / float(columns))) * columns
	var cell_size := CardTokens.tap(CardTokens.CHAR_STORE_CELL, phone) * s
	while cells.size() < count:
		var c := HubItemCell.new()
		c.setup()
		c.pressed.connect(func() -> void:
			if c.item != null:
				on_tap.call(c.item))
		c.activated.connect(func() -> void:
			if c.item != null and c.get_meta("activate", Callable()).is_valid():
				c.get_meta("activate").call(c.item))
		grid.add_child(c)
		cells.append(c)
	for n in cells.size():
		var c: HubItemCell = cells[n]
		c.visible = n < count
		c.s = s
		c.custom_minimum_size = Vector2(cell_size, cell_size)
		var item = items[n] if n < items.size() else null
		c.slot_id = item.slot if item != null else ""
		c.show_item(item, rules, "")
		c.selected = item != null and item.id == selected_id
		c.fits = false
		c.set_meta("activate", on_activate)
		c.focus_mode = Control.FOCUS_ALL if item != null else Control.FOCUS_NONE
		c.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ for subclasses
func build() -> void:
	pass


func layout_body(_area: Vector2) -> void:
	pass


func first_focus() -> Control:
	return _close


## The header's money line (Tailor adds diamonds).
func currency_text(p) -> String:
	return "%s  %d" % [CardTokens.t("gold"), p.stash.gold]
