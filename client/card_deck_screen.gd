extends Control
## The Class Card screen (docs/ui/class_card_ui_handoff.md): the home screen the player sees before a fight.
## It replaces the campfire hub (the hub code stays, hidden). States: A deck, B editor of one card, C summon.
## The screen draws the player's card deck (Profile.card_deck, rules in logic/card_deck.gd) and reports what the
## player wants through signals (§13). It never changes the profile itself: the small controller at the bottom
## (auto_wire) turns the signals into the server commands `card_look` / `card_squad` on the session, then
## draws the deck the profile now holds (or calls refuse()).
## Every colour, size, string and art path comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const CardPortrait := preload("res://client/card_portrait.gd")
const CardFrame := preload("res://client/card_frame.gd")
const CardHolo := preload("res://client/card_holo.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const CampScreen := preload("res://client/camp_screen.gd")
const GraphicsPanel := preload("res://client/graphics_panel.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const TITLE_SCENE := "res://scenes/title.tscn"

signal card_selected(class_id: String)
signal look_changed(class_id: String, part: String, choice: String)  ## part: hair|outfit|eye_color|skin|makeup
signal squad_changed(squad: Array)  ## the full new order, 1..3 class ids
signal reset_card(class_id: String)
signal fight_pressed()
signal bag_pressed()
signal settings_pressed()
signal back_pressed()
signal summon_finished()

## true: the screen sends the commands itself (the game). Tests and shot scripts can set false.
var auto_wire := true
## Reduced motion (§9): no bob, shine, tilt or wiggle; transitions become short fades. There is no game
## setting for it yet; whoever adds one sets this.
var reduced_motion := false

var _deck := {}
var _cosmetics
var _s := 1.0
var _phone := false
var _mode := "deck"  ## deck | editor | summon
var _edit_class := ""
var _tab := "hair"
var _previous := {}
var _class_ids: Array = []
var _time := 0.0
var _busy := false
var _summon_done := false
var _summon_tweens: Array[Tween] = []
var _toast_tween: Tween
var _camp: CanvasLayer

var _bg: TextureRect
var _clouds: Array[Panel] = []
var _deck_layer: Control
var _top_title: Label
var _bag_button: Button
var _settings_button: Button
var _back_button: Button
var _row_scroll: ScrollContainer
var _row: Control
var _hint: Label
var _bar: Panel
var _bar_label: Label
var _ready_label: Label
var _slots: Array = []
var _fight: Button
var _cards := {}  ## class id -> CardView (deck)

var _editor_layer: Control
var _editor_back: Button
var _editor_title: Label
var _editor_reset: Button
var _editor_card: CardView
var _strip: Control
var _strip_cards := {}
var _sheet: Panel
var _sheet_tabs: HBoxContainer
var _sheet_body: VBoxContainer
var _tab_buttons := {}

var _summon_layer: Control
var _picker_layer: Control
var _picker: ColorPicker
var _confirm_layer: Control
var _toast: Panel
var _toast_label: Label


# ================================================================== card widget
## One class card: frame, window (the live 3D portrait), emblem, ribbon, sockets, squad sticker, select ring.
## Depth layers, bottom to top (Boss 2026-11-11): dark base, backdrop art (parallax against the tilt), holo foil,
## border lines, the 3D character (shadow + halo under it, parallax with the tilt, masked by the outer card shape
## only so it may cross the inner lines), then badge, number slot and name plate.
class CardView extends Control:
	signal pressed()
	signal squad_toggled()
	signal hover_changed(on: bool)

	var class_id := ""
	var compact := false
	var portrait: Control
	var window_slot: Control
	var squad_button: Button
	var base_position := Vector2.ZERO
	var base_rotation := 0.0
	var lift := 0.0
	var tilt := 0.0
	var tilt_target := 0.0
	var pop := 1.0
	var phase := 0.0
	var screen_scale := 1.0
	var unit := 1.0
	var plate_top := 0.0  ## y where the name plate starts
	var hovered := false
	var _back: CardFrame  ## dark card base
	var _art: CardFrame  ## backdrop art in the rounded window
	var _lines: CardFrame  ## the two border lines
	var _figure: CardFrame  ## outer card shape: clips the character layer (shadow, halo, portrait)
	var _halo: TextureRect
	var _shadow: TextureRect
	var _front: CardFrame  ## plate, badge, number slot (above the character)
	var _emblem: Panel
	var _emblem_label: Label
	var _sticker: Panel
	var _sticker_label: Label
	var _ribbon: Panel
	var _ribbon_label: Label
	var _ring: CardFrame
	var _focus: CardFrame
	var _squad_state := [false, false]
	var _holo: Control  ## CardHolo overlay, built the first time this card is active (hover or focus)
	var _holo_pointer := Vector2.ZERO  ## pointer offset from the card centre, -1..1
	var _holo_tilt := Vector2.ZERO  ## smoothed copy that drives the shader and the portrait parallax
	var _holo_has_pointer := false
	var _holo_clock := 0.0

	var deck_card := false

	func build(id: String, is_compact: bool, with_button: bool) -> void:
		class_id = id
		compact = is_compact
		deck_card = with_button  # deck cards (with the select button) use the smaller figure framing
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		_back = _new_frame("base")
		_art = _new_frame("art")
		_lines = _new_frame("lines")
		_figure = _new_frame("mask")
		_figure.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		_halo = TextureRect.new()
		_halo.texture = CardTokens.figure_halo()
		_halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_halo.stretch_mode = TextureRect.STRETCH_SCALE
		_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_halo.visible = not compact
		_figure.add_child(_halo)
		window_slot = Control.new()
		window_slot.clip_contents = compact
		window_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait = CardPortrait.new()
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		if not compact:
			portrait.framing = "card_deck" if deck_card else "card"
		_shadow = portrait.shadow_rect()
		_shadow.visible = not compact
		_figure.add_child(_shadow)
		_figure.add_child(window_slot)
		window_slot.add_child(portrait)
		_front = _new_frame("ui")
		_ribbon = _new_panel()
		_ribbon_label = CardTokens.label("", CardTokens.FONT_CARD_NAME, CardTokens.TEXT_LIGHT, 1.0)
		_ribbon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ribbon_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_ribbon.add_child(_ribbon_label)
		_emblem = _new_panel()
		_emblem_label = CardTokens.label("", CardTokens.FONT_CARD_NAME, CardTokens.TEXT_LIGHT, 1.0)
		_emblem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_emblem.add_child(_emblem_label)
		_sticker = _new_panel()
		_sticker_label = CardTokens.label("", CardTokens.FONT_STICKER, CardTokens.TEXT_LIGHT, 1.0)
		_sticker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sticker.add_child(_sticker_label)
		_sticker.visible = false
		_ring = _new_frame("ring")
		_ring.visible = false
		_focus = _new_frame("ring")
		_focus.visible = false
		if with_button:
			squad_button = Button.new()
			squad_button.focus_mode = Control.FOCUS_ALL
			squad_button.pressed.connect(func() -> void: squad_toggled.emit())
			add_child(squad_button)
		mouse_entered.connect(func() -> void: _hover(true))
		mouse_exited.connect(func() -> void: _hover(false))
		focus_entered.connect(func() -> void:
			_focus.visible = true
			_update_holo())
		focus_exited.connect(func() -> void:
			_focus.visible = false
			_update_holo())

	func _new_frame(frame_kind: String) -> CardFrame:
		var f := CardFrame.new()
		f.kind = frame_kind
		add_child(f)
		return f

	func _new_panel() -> Panel:
		var p := Panel.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
		return p

	func _hover(on: bool) -> void:
		hovered = on
		if not on:
			tilt_target = 0.0
			_holo_has_pointer = false
			_holo_pointer = Vector2.ZERO
		_update_holo()
		if portrait != null:
			portrait.set_hover(on)
			portrait.set_render_mode(CardPortrait.Mode.LIVE if on else _idle_mode)
		hover_changed.emit(on)

	var _idle_mode := CardPortrait.Mode.THROTTLED

	## The holo foil, tilt parallax and sparkles run only on the card the pointer or focus is on (and the
	## editor card, which is always active). Other cards pay nothing: no overlay node exists for them.
	func _update_holo() -> void:
		if compact:
			return
		var on := hovered or has_focus() or always_holo
		if on and _holo == null:
			_holo = CardHolo.new()
			if always_holo:
				_holo.strength_scale = CardTokens.HOLO_EDITOR_SCALE
			add_child(_holo)
			move_child(_holo, _lines.get_index())  # over the backdrop and under the lines and the character
			_layout_holo()
		if _holo != null:
			_holo.set_active(on, holo_motion)

	var always_holo := false
	var holo_motion := true

	func _layout_holo() -> void:
		if _holo != null:
			_holo.position = Vector2.ZERO
			_holo.setup(size, CardTokens.CARD_RADIUS * unit)

	func set_idle_mode(mode: CardPortrait.Mode) -> void:
		_idle_mode = mode
		portrait.set_render_mode(CardPortrait.Mode.LIVE if hovered else mode)

	## Re-dresses this card for a class (colours, name, emblem, the 3D character).
	func apply_class(id: String, look: Dictionary) -> void:
		class_id = id
		var pal := CardTokens.palette(id)
		var u := unit
		_back.configure(id, u, compact)
		_front.configure(id, u, compact)
		for f in [_art, _lines, _figure]:
			f.configure(id, u, compact)
		CardTokens.panel(_ribbon, CardTokens.clear_style())
		CardTokens.panel(_emblem, CardTokens.clear_style())
		CardTokens.panel(_sticker, CardTokens.clear_style())
		_emblem_label.text = str(pal["emblem"])
		_ribbon_label.text = CardTokens.class_name_of(id)
		portrait.set_class(id)
		portrait.set_look(look)

	func set_look(look: Dictionary) -> void:
		portrait.set_look(look)

	func set_number(n: int) -> void:
		_sticker.visible = n > 0
		_sticker_label.text = str(n)
		_front.set_numbered(n > 0)

	func set_selected(on: bool) -> void:
		_ring.visible = on

	## in_squad: shows "-" else "+"; `soft_disabled` greys it but keeps it clickable (the tap explains why).
	func set_squad_state(in_squad: bool, soft_disabled: bool) -> void:
		if squad_button == null:
			return
		_squad_state = [in_squad, soft_disabled]
		squad_button.text = "-" if in_squad else "+"
		var tint: Color = CardTokens.DISABLED if soft_disabled else (CardTokens.ACTION if in_squad else CardTokens.ADD_GREEN)
		CardTokens.button_skin(squad_button, "sticker", unit, tint)
		CardTokens.style_text(squad_button, CardTokens.FONT_STICKER, CardTokens.TEXT_LIGHT, unit, CardTokens.OUTLINE_TEXT_SMALL)
		squad_button.tooltip_text = CardTokens.t("remove_from_squad" if in_squad else "add_to_squad")

	func layout(w: float, p_screen_scale: float) -> void:
		screen_scale = p_screen_scale
		unit = w / CardTokens.CARD_SIZE.x
		var u := unit
		var h := w * CardTokens.CARD_SIZE.y / CardTokens.CARD_SIZE.x
		size = Vector2(w, h)
		custom_minimum_size = size
		pivot_offset = size * 0.5
		for f in [_back, _art, _lines, _figure, _front]:
			f.position = Vector2.ZERO
			f.size = size
			f.configure(class_id, u, compact)
		var inset := CardTokens.CARD_WINDOW_INSET * u
		var plate_h := 0.0 if compact else CardTokens.CARD_PLATE_H * u
		var window := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0 - plate_h)
		plate_top = window.end.y
		if compact:  # mini cards: the bust stays inside its window
			window_slot.position = window.position
			window_slot.size = window.size
		else:  # the character covers the whole card; the outer card mask clips it
			window_slot.position = Vector2.ZERO
			window_slot.size = size
			_halo.size = size * CardTokens.FIGURE_HALO_SIZE
			_shadow.size = size
		_place_figure(Vector2.ZERO)
		var badge := CardFrame.badge_rect(u)
		_emblem.position = badge.position
		_emblem.size = badge.size
		_emblem_label.size = badge.size
		_emblem_label.position = Vector2(0.0, badge.size.y * 0.04)
		_emblem_label.visible = not compact or u >= CardTokens.CARD_EMBLEM_TEXT_MIN_UNIT
		CardTokens.style_text(_emblem_label, CardTokens.FONT_CARD_NAME, CardTokens.TEXT_LIGHT, u)
		var slot := CardFrame.number_rect(w, u)
		_sticker.position = slot.position
		_sticker.size = slot.size
		_sticker_label.size = slot.size
		CardTokens.style_text(_sticker_label, CardTokens.FONT_STICKER, CardTokens.TEXT_LIGHT, u)
		_ribbon.visible = not compact
		if not compact:
			_ribbon.position = Vector2(inset, window.end.y)
			_ribbon.size = Vector2(w - inset * 2.0, plate_h)
			_ribbon_label.size = _ribbon.size
			CardTokens.style_text(_ribbon_label, CardTokens.FONT_CARD_NAME, CardTokens.TEXT_LIGHT, u)
		var pad := CardTokens.CARD_RING_PAD * u
		_ring.unit = u
		_ring.tint = CardTokens.ACTION
		_ring.line_width = CardTokens.CARD_RING_WIDTH * u
		_ring.position = Vector2(-pad, -pad)
		_ring.size = size + Vector2(pad, pad) * 2.0
		_ring.queue_redraw()
		_focus.unit = u
		_focus.tint = CardTokens.FOCUS
		_focus.line_width = CardTokens.FOCUS_WIDTH * u
		_focus.position = Vector2(-pad * 2.0, -pad * 2.0)
		_focus.size = size + Vector2(pad, pad) * 4.0
		_focus.queue_redraw()
		_layout_holo()
		if squad_button != null:
			var b := CardTokens.STICKER_BUTTON * u
			squad_button.size = Vector2(b, b)
			squad_button.custom_minimum_size = squad_button.size
			squad_button.position = Vector2(w - b - inset - 4.0 * u, plate_top - b - 4.0 * u)
			set_squad_state(_squad_state[0], _squad_state[1])

	func animate(time: float, delta: float, motion: bool) -> void:
		var bob := 0.0
		var squash := 0.0
		if motion:
			var wave := sin((time + phase) / CardTokens.BOB_SECONDS * TAU)
			bob = wave * CardTokens.BOB_PIXELS * screen_scale
			squash = CardTokens.SQUASH * maxf(0.0, -wave)
			tilt = lerpf(tilt, tilt_target, minf(1.0, delta * 12.0))
		else:
			tilt = 0.0
		_animate_holo(delta, motion)
		position = base_position + Vector2(0.0, bob - lift)
		rotation_degrees = base_rotation + tilt
		scale = Vector2(pop, pop * (1.0 - squash))

	## Smooths the tilt (pointer, or a slow sway when focused without a pointer), feeds the foil shader and the
	## depth parallax (_place_figure). Reduced motion: the tilt target is zero, so all of it stays still.
	func _animate_holo(delta: float, motion: bool) -> void:
		if _holo == null:
			return
		if holo_motion != motion:
			holo_motion = motion
			_holo.set_active(hovered or has_focus() or always_holo, motion)
		var active := hovered or has_focus() or always_holo
		var target := Vector2.ZERO
		if active and motion:
			_holo_clock += delta
			target = _holo_pointer if _holo_has_pointer else Vector2(sin(_holo_clock * CardTokens.HOLO_SWAY_SPEED.x) * CardTokens.HOLO_SWAY.x, cos(_holo_clock * CardTokens.HOLO_SWAY_SPEED.y) * CardTokens.HOLO_SWAY.y)
		var moving := _holo_tilt.distance_squared_to(target) > 0.00001
		_holo_tilt = _holo_tilt.lerp(target, minf(1.0, delta * CardTokens.HOLO_SMOOTH))
		if moving:
			_holo.set_tilt(_holo_tilt)
			_place_figure(_holo_tilt)

	## Depth parallax: the backdrop moves against the tilt, the character with it and further, its shadow between.
	func _place_figure(p_tilt: Vector2) -> void:
		_art.set_art_shift(-p_tilt * CardTokens.BACKDROP_PARALLAX)
		if compact:
			return
		var fig := p_tilt * CardTokens.FIGURE_PARALLAX * size
		portrait.position = fig
		_shadow.position = fig * CardTokens.FIGURE_SHADOW_FOLLOW + CardTokens.FIGURE_SHADOW_DROP * unit
		_halo.position = size * CardTokens.FIGURE_HALO_CENTER - _halo.size * 0.5 + fig * CardTokens.FIGURE_SHADOW_FOLLOW * 0.5

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			pressed.emit()
			accept_event()
			return
		var motion := event as InputEventMouseMotion
		if motion != null:
			var across := clampf(motion.position.x / maxf(size.x, 1.0), 0.0, 1.0)
			tilt_target = (across - 0.5) * 2.0 * CardTokens.TILT_MAX
			_holo_has_pointer = true
			_holo_pointer = Vector2(across - 0.5, clampf(motion.position.y / maxf(size.y, 1.0), 0.0, 1.0) - 0.5).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * 2.0
			portrait.set_hover(true, Vector2(across, 0.5))
		if event.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()


## One slot of the squad bar: empty (+) or a mini card with a remove button. Drag a filled slot onto another to reorder.
class SquadSlot extends Panel:
	var index := 0
	var class_id := ""
	var drop_callback: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
		if class_id.is_empty():
			return null
		var preview := Label.new()
		preview.text = CardTokens.class_name_of(class_id)
		set_drag_preview(preview)
		return {"squad_slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("squad_slot") and int(data["squad_slot"]) != index

	func _drop_data(_at: Vector2, data: Variant) -> void:
		drop_callback.call(int(data["squad_slot"]), index)


## The comic burst of the summon: a star shaped polygon, no letters (§10).
class BurstView extends Control:
	var radius := 100.0

	func _draw() -> void:
		var points := PackedVector2Array()
		var count: int = CardTokens.BURST_POINTS * 2
		for i in count:
			var r := radius if i % 2 == 0 else radius * CardTokens.BURST_INNER
			var angle := float(i) / float(count) * TAU
			points.append(Vector2(cos(angle), sin(angle)) * r)
		draw_set_transform(size * 0.5)
		draw_colored_polygon(points, CardTokens.INK)
		var inner := PackedVector2Array()
		for p in points:
			inner.append(p * 0.88)
		draw_colored_polygon(inner, CardTokens.FRAME)
		var core := PackedVector2Array()
		for p in points:
			core.append(p * 0.55)
		draw_colored_polygon(core, CardTokens.ACTION_LIGHT)


# ================================================================== build
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_background()
	_build_deck_layer()
	_build_editor_layer()
	_build_overlays()
	resized.connect(_layout)
	_layout()
	if auto_wire:
		_wire_game()


func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.texture = CardTokens.tex("bg_sky") if CardTokens.tex("bg_sky") != null else CardTokens.sky_gradient()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	for i in CardTokens.CLOUD_Y.size():
		var cloud := Panel.new()
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.modulate.a = CardTokens.CLOUD_FADE
		add_child(cloud)
		_clouds.append(cloud)


func _build_deck_layer() -> void:
	_deck_layer = Control.new()
	_deck_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deck_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deck_layer)
	_top_title = CardTokens.label(CardTokens.t("deck_title"), CardTokens.FONT_SCREEN_TITLE, CardTokens.TEXT_LIGHT, 1.0, CardTokens.OUTLINE_TEXT)
	_deck_layer.add_child(_top_title)
	_bag_button = _pill(CardTokens.t("bag"), func() -> void: bag_pressed.emit())
	_settings_button = _pill(CardTokens.t("settings"), func() -> void: settings_pressed.emit())
	_back_button = _pill(CardTokens.t("back"), func() -> void: back_pressed.emit())
	for b in [_bag_button, _settings_button, _back_button]:
		_deck_layer.add_child(b)
	_row_scroll = ScrollContainer.new()
	_row_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_row_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_row_scroll.follow_focus = true
	_deck_layer.add_child(_row_scroll)
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row_scroll.add_child(_row)
	_hint = CardTokens.label(CardTokens.t("deck_hint"), CardTokens.FONT_HINT, CardTokens.TEXT_DARK, 1.0, 0, "body")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_layer.add_child(_hint)
	_bar = Panel.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_deck_layer.add_child(_bar)
	_bar_label = CardTokens.label(CardTokens.t("squad"), CardTokens.FONT_TAB, CardTokens.TEXT_DARK, 1.0)
	_bar.add_child(_bar_label)
	_ready_label = CardTokens.label(CardTokens.t("squad_ready"), CardTokens.FONT_OPTION, CardTokens.TEXT_DARK, 1.0, 0, "medium")
	_ready_label.visible = false
	_bar.add_child(_ready_label)
	for i in CardDeck.SQUAD_MAX:
		var slot := SquadSlot.new()
		slot.index = i
		slot.drop_callback = _on_slot_drop
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		_bar.add_child(slot)
		_slots.append(slot)
	_fight = Button.new()
	_fight.text = CardTokens.t("fight")
	_fight.pressed.connect(func() -> void: fight_pressed.emit())
	_deck_layer.add_child(_fight)


func _build_editor_layer() -> void:
	_editor_layer = Control.new()
	_editor_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_editor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor_layer.visible = false
	add_child(_editor_layer)
	_editor_back = _pill(CardTokens.t("back"), _close_editor)
	_editor_layer.add_child(_editor_back)
	_editor_title = CardTokens.label("", CardTokens.FONT_EDITOR_NAME, CardTokens.TEXT_LIGHT, 1.0, CardTokens.OUTLINE_TEXT)
	_editor_layer.add_child(_editor_title)
	_editor_reset = _pill(CardTokens.t("reset_card"), _ask_reset)
	_editor_layer.add_child(_editor_reset)
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor_layer.add_child(_strip)
	_sheet = Panel.new()
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor_layer.add_child(_sheet)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.name = "Margin"
	_sheet.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	margin.add_child(column)
	_sheet_tabs = HBoxContainer.new()
	column.add_child(_sheet_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_sheet_body = VBoxContainer.new()
	_sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sheet_body)
	for tab in ["hair", "eyes", "outfit", "body", "skills"]:
		var b := Button.new()
		b.toggle_mode = false
		b.pressed.connect(_select_tab.bind(tab))
		_sheet_tabs.add_child(b)
		_tab_buttons[tab] = b


func _build_overlays() -> void:
	_picker_layer = _overlay()
	_confirm_layer = _overlay()
	_summon_layer = Control.new()
	_summon_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summon_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_summon_layer.visible = false
	_summon_layer.gui_input.connect(_on_summon_input)
	add_child(_summon_layer)
	_toast = Panel.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = CardTokens.label("", CardTokens.FONT_HINT, CardTokens.TEXT_DARK, 1.0, 0, "body")
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	add_child(_toast)


func _overlay() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.visible = false
	add_child(layer)
	return layer


func _pill(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b


# ================================================================== layout
func _layout() -> void:
	_s = CardTokens.scale_for(size)
	_phone = CardTokens.is_phone(size)
	var s := _s
	var safe := CardTokens.SAFE * s
	for i in _clouds.size():
		var w: float = CardTokens.CLOUD_WIDTH[i] * s
		CardTokens.panel(_clouds[i], CardTokens.skin("bg_cloud_%d" % (i % 3 + 1), [0, 0, 0, 0], CardTokens.flat(CardTokens.CLOUD, CardTokens.CLOUD_SHADOW, 4.0, CardTokens.CLOUD_HEIGHT * 0.5, s)))
		_clouds[i].size = Vector2(w, CardTokens.CLOUD_HEIGHT * s)
		_clouds[i].position = Vector2(fmod(float(i) * size.x * 0.37, size.x + w) - w, size.y * CardTokens.CLOUD_Y[i])
	# top bar
	var pill_h := CardTokens.PILL_H * s
	_top_title.position = Vector2(safe.x, safe.y)
	_top_title.size = Vector2(size.x * 0.4, CardTokens.TOP_BAR_H * s)
	CardTokens.style_text(_top_title, CardTokens.FONT_SCREEN_TITLE, CardTokens.TEXT_LIGHT, s, CardTokens.OUTLINE_TEXT)
	var x := size.x - safe.x
	for b in [_back_button, _settings_button, _bag_button]:
		CardTokens.button_skin(b, "secondary", s)
		CardTokens.style_text(b, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s, 0, "medium")
		var w := maxf(b.get_minimum_size().x + 24.0 * s, 120.0 * s)
		b.size = Vector2(w, pill_h)
		x -= w
		b.position = Vector2(x, safe.y + (CardTokens.TOP_BAR_H * s - pill_h) * 0.5)
		x -= CardTokens.ICON_GAP * s
	# card row (§7.1; scrolls when more cards than fit, §15)
	var count := maxi(_class_ids.size(), 1)
	var card_w: float = (CardTokens.PHONE_CARD.x if _phone else CardTokens.CARD_SIZE.x) * s
	var gap: float = (CardTokens.PHONE_CARD_GAP if _phone else CardTokens.CARD_GAP) * s
	var avail := size.x - safe.x * 2.0
	var need := card_w * count + gap * (count - 1)
	if need > avail:
		card_w = maxf((avail - gap * (count - 1)) / count, CardTokens.CARD_MIN_WIDTH * s)
		need = card_w * count + gap * (count - 1)
	var card_h := card_w * CardTokens.CARD_SIZE.y / CardTokens.CARD_SIZE.x
	var pad := 40.0 * s
	_row_scroll.position = Vector2(safe.x, CardTokens.CARD_TOP * s - pad)
	_row_scroll.size = Vector2(avail, card_h + pad * 2.0 + 24.0 * s)
	_row.custom_minimum_size = Vector2(maxf(need, avail), card_h + pad * 2.0)
	var start_x := (maxf(need, avail) - need) * 0.5
	var index := 0
	for id in _class_ids:
		var card: CardView = _cards.get(id)
		if card == null:
			continue
		card.layout(card_w, s)
		card.base_position = Vector2(start_x + float(index) * (card_w + gap), pad + CardTokens.CARD_FAN_DROP[index % 4] * s)
		card.base_rotation = CardTokens.CARD_FAN_ROTATION[index % 4]
		card.phase = float(index) * CardTokens.BOB_OFFSET
		card.position = card.base_position
		index += 1
	_hint.visible = not _phone
	_hint.position = Vector2(safe.x, _row_scroll.position.y + _row_scroll.size.y + 8.0 * s)
	_hint.size = Vector2(avail, 32.0 * s)
	CardTokens.style_text(_hint, CardTokens.FONT_HINT, CardTokens.TEXT_DARK, s, 0, "body")
	# squad bar and the fight button, along the bottom
	var bar_w: float = (CardTokens.PHONE_SQUAD_W if _phone else CardTokens.SQUAD_BAR.x) * s
	var bar_h: float = CardTokens.SQUAD_BAR.y * s
	var bar_y := size.y - safe.y - bar_h - 48.0 * s
	_bar.position = Vector2(safe.x, bar_y)
	_bar.size = Vector2(bar_w, bar_h)
	CardTokens.panel(_bar, CardTokens.panel_paper(s))
	_bar_label.position = Vector2(24.0 * s, 16.0 * s)
	_bar_label.size = Vector2(CardTokens.SQUAD_BAR_LABEL_W * s, 40.0 * s)
	CardTokens.style_text(_bar_label, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s)
	_ready_label.position = Vector2(24.0 * s, 64.0 * s)
	_ready_label.size = Vector2(CardTokens.SQUAD_BAR_LABEL_W * s * 1.4, 36.0 * s)
	CardTokens.style_text(_ready_label, CardTokens.FONT_OPTION, CardTokens.TEXT_DARK, s, 0, "medium")
	var slot_w := CardTokens.SQUAD_SLOT.x * s
	var slot_h := CardTokens.SQUAD_SLOT.y * s
	var slot_x := (CardTokens.SQUAD_BAR_LABEL_W + 48.0) * s
	for i in _slots.size():
		var slot: SquadSlot = _slots[i]
		slot.position = Vector2(slot_x + float(i) * (slot_w + CardTokens.SQUAD_SLOT_GAP * s), (bar_h - slot_h) * 0.5)
		slot.size = Vector2(slot_w, slot_h)
	var fight_size: Vector2 = (CardTokens.PHONE_FIGHT if _phone else CardTokens.FIGHT_SIZE) * s
	_fight.size = fight_size
	_fight.position = Vector2(size.x - safe.x - fight_size.x, bar_y + (bar_h - fight_size.y) * 0.5)
	CardTokens.button_skin(_fight, "primary", s)
	CardTokens.style_text(_fight, CardTokens.FONT_FIGHT, CardTokens.TEXT_LIGHT, s, CardTokens.OUTLINE_TEXT)
	_refresh_squad_bar()
	_layout_editor()
	_layout_toast()


func _layout_toast() -> void:
	var s := _s
	CardTokens.panel(_toast, CardTokens.panel_paper(s, 20.0))
	var w := minf(size.x - 96.0 * s, 700.0 * s)
	_toast.size = Vector2(w, CardTokens.TOAST_H * s)
	_toast.position = Vector2((size.x - w) * 0.5, CardTokens.SAFE.y * s)
	_toast_label.size = _toast.size
	CardTokens.style_text(_toast_label, CardTokens.FONT_HINT, CardTokens.TEXT_DARK, s, 0, "body")


func _layout_editor() -> void:
	var s := _s
	var safe := CardTokens.SAFE * s
	CardTokens.button_skin(_editor_back, "secondary", s)
	CardTokens.style_text(_editor_back, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s, 0, "medium")
	_editor_back.size = Vector2(maxf(_editor_back.get_minimum_size().x + 24.0 * s, 120.0 * s), CardTokens.PILL_H * s)
	_editor_back.position = safe
	_editor_title.position = Vector2(safe.x + _editor_back.size.x + 24.0 * s, safe.y)
	_editor_title.size = Vector2(size.x * 0.5, CardTokens.PILL_H * s)
	CardTokens.style_text(_editor_title, CardTokens.FONT_EDITOR_NAME, CardTokens.TEXT_LIGHT, s, CardTokens.OUTLINE_TEXT)
	CardTokens.button_skin(_editor_reset, "secondary", s)
	CardTokens.style_text(_editor_reset, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s, 0, "medium")
	_editor_reset.size = Vector2(maxf(_editor_reset.get_minimum_size().x + 24.0 * s, 160.0 * s), CardTokens.PILL_H * s)
	_editor_reset.position = Vector2(size.x - safe.x - _editor_reset.size.x, safe.y)
	var card_size: Vector2 = (CardTokens.PHONE_EDITOR_CARD if _phone else CardTokens.EDITOR_CARD) * s
	var card_pos: Vector2 = CardTokens.EDITOR_CARD_POS * s
	card_pos.x = maxf(card_pos.x, safe.x)
	if _editor_card != null:
		_editor_card.layout(card_size.x, s)
		_editor_card.base_position = card_pos
		_editor_card.position = card_pos
	var strip_y := card_pos.y + card_size.y + 28.0 * s
	var strip_w := CardTokens.STRIP_CARD.x * s
	var strip_total := strip_w * _class_ids.size() + CardTokens.STRIP_GAP * s * maxf(_class_ids.size() - 1, 0)
	_strip.position = Vector2(card_pos.x + (card_size.x - strip_total) * 0.5, strip_y)
	var i := 0
	for id in _class_ids:
		var mini: CardView = _strip_cards.get(id)
		if mini != null:
			mini.layout(strip_w, s)
			mini.position = Vector2(float(i) * (strip_w + CardTokens.STRIP_GAP * s), -(10.0 * s if id == _edit_class else 0.0))
		i += 1
	var sheet_x := card_pos.x + card_size.x + 80.0 * s
	var sheet_size: Vector2 = CardTokens.EDITOR_SHEET_SIZE * s
	sheet_size.x = minf(sheet_size.x, size.x - sheet_x - safe.x)
	sheet_size.y = minf(sheet_size.y, size.y - card_pos.y - safe.y)
	_sheet.position = Vector2(sheet_x, card_pos.y)
	_sheet.size = sheet_size
	CardTokens.panel(_sheet, CardTokens.panel_paper(s, 32.0))
	CardTokens.margin(_sheet.get_node("Margin"), 24.0, s)
	CardTokens.gap(_sheet.get_node("Margin/Column"), 16.0, s)
	CardTokens.gap(_sheet_tabs, 12.0, s)
	if _mode == "editor":
		_refresh_editor()


# ================================================================== data
## Draws everything from `deck` (Profile.card_deck). Called again after each change.
func show_deck(deck: Dictionary, cosmetics) -> void:
	_deck = deck.duplicate(true)
	_cosmetics = cosmetics
	var ids: Array = []
	for id in CardDeck.classes():
		if _deck.get("cards", {}).has(id):
			ids.append(id)
	if ids != _class_ids:
		_class_ids = ids
		_rebuild_cards()
		_layout()
	_refresh_all()


func _rebuild_cards() -> void:
	for card in _cards.values():
		card.queue_free()
	_cards.clear()
	for id in _class_ids:
		var card := CardView.new()
		_row.add_child(card)
		card.build(id, false, true)
		card.layout(CardTokens.CARD_SIZE.x * _s, _s)
		card.apply_class(id, CardDeck.look_of(_deck, id))
		card.pressed.connect(_on_card_pressed.bind(id))
		card.squad_toggled.connect(_toggle_squad.bind(id))
		_cards[id] = card


func _squad() -> Array:
	return (_deck.get("squad", []) as Array).duplicate()


func _refresh_all() -> void:
	var squad := _squad()
	for id in _class_ids:
		var card: CardView = _cards.get(id)
		if card == null:
			continue
		card.set_look(CardDeck.look_of(_deck, id))
		var at := squad.find(id)
		card.set_number(at + 1 if at >= 0 else 0)
		var full := squad.size() >= CardDeck.SQUAD_MAX and at < 0
		var last := squad.size() <= 1 and at >= 0
		card.set_squad_state(at >= 0, full or last)
		card.squad_button.tooltip_text = CardTokens.t("squad_need_one") if last else card.squad_button.tooltip_text
	_refresh_squad_bar()
	_fight.disabled = squad.is_empty()
	if _mode == "editor":
		_refresh_editor()


func _refresh_squad_bar() -> void:
	if _slots.is_empty() or _deck.is_empty():
		return
	var s := _s
	var squad := _squad()
	for i in _slots.size():
		var slot: SquadSlot = _slots[i]
		for child in slot.get_children():
			child.queue_free()
		slot.class_id = str(squad[i]) if i < squad.size() else ""
		if slot.class_id.is_empty():
			CardTokens.panel(slot, CardTokens.skin("squad_slot_empty", [40, 40, 40, 40], CardTokens.flat(CardTokens.PAPER_SHADOW, CardTokens.DISABLED_SHADOW, CardTokens.OUTLINE_ICON, 24.0, s)))
			var plus := CardTokens.label("+", CardTokens.FONT_FIGHT, CardTokens.DISABLED_SHADOW, s)
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.size = slot.size
			slot.add_child(plus)
			continue
		var pal := CardTokens.palette(slot.class_id)
		CardTokens.panel(slot, CardTokens.skin("squad_slot_filled", [40, 40, 40, 40], CardTokens.flat(pal["light"], pal["shadow"], CardTokens.OUTLINE_BUTTON, 24.0, s)))
		var mini := CardView.new()
		slot.add_child(mini)
		mini.build(slot.class_id, true, false)
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini.focus_mode = Control.FOCUS_NONE
		var mini_w := slot.size.x * 0.8
		mini.layout(mini_w, s)
		mini.position = Vector2((slot.size.x - mini_w) * 0.5, 8.0 * s)
		mini.apply_class(slot.class_id, CardDeck.look_of(_deck, slot.class_id))
		mini.portrait.set_framing("bust")
		mini.set_idle_mode(CardPortrait.Mode.ONCE)
		mini.set_number(i + 1)
		var remove := Button.new()
		remove.text = "x"
		remove.tooltip_text = CardTokens.t("squad_need_one") if squad.size() <= 1 else CardTokens.t("remove_from_squad")
		var cls: String = slot.class_id
		remove.pressed.connect(_toggle_squad.bind(cls))
		CardTokens.button_skin(remove, "sticker", s, CardTokens.DISABLED if squad.size() <= 1 else CardTokens.ACTION)
		CardTokens.style_text(remove, CardTokens.FONT_OPTION, CardTokens.TEXT_LIGHT, s, CardTokens.OUTLINE_TEXT_SMALL)
		var rs := CardTokens.SLOT_REMOVE * s
		remove.size = Vector2(rs, rs)
		remove.position = Vector2(slot.size.x - rs - 2.0 * s, 2.0 * s)
		slot.add_child(remove)
	_ready_label.visible = squad.size() >= CardDeck.SQUAD_MAX


# ================================================================== squad
func _toggle_squad(class_id: String) -> void:
	var squad := _squad()
	var at := squad.find(class_id)
	if at >= 0:
		if squad.size() <= 1:
			_blocked("squad_need_one")
			return
		squad.remove_at(at)
	else:
		if squad.size() >= CardDeck.SQUAD_MAX:
			_blocked("squad_full")
			return
		squad.append(class_id)
	_set_squad(squad)


func _on_slot_drop(from: int, to: int) -> void:
	var squad := _squad()
	if from < 0 or from >= squad.size():
		return
	var moved = squad.pop_at(from)
	squad.insert(mini(to, squad.size()), moved)
	_set_squad(squad)


func _set_squad(squad: Array) -> void:
	_previous = {"kind": "squad", "value": _squad()}
	_deck["squad"] = squad
	_refresh_all()
	squad_changed.emit(squad)


## A change the rules do not allow: shake the squad bar, flash it red and say why (§9).
func _blocked(message_key: String) -> void:
	toast(CardTokens.t(message_key))
	if reduced_motion:
		return
	var home := _bar.position
	var tween := create_tween()
	for i in 3:
		tween.tween_property(_bar, "position:x", home.x + CardTokens.SHAKE_PIXELS * _s, CardTokens.SHAKE_SECONDS / 6.0)
		tween.tween_property(_bar, "position:x", home.x - CardTokens.SHAKE_PIXELS * _s, CardTokens.SHAKE_SECONDS / 6.0)
	tween.tween_property(_bar, "position:x", home.x, 0.02)
	CardTokens.panel(_bar, CardTokens.flat(CardTokens.PAPER, CardTokens.ERROR, CardTokens.OUTLINE_PRIMARY, 28.0, _s, true))
	tween.finished.connect(func() -> void: CardTokens.panel(_bar, CardTokens.panel_paper(_s)))


func toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(CardTokens.TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, CardTokens.FADE_SECONDS)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


## The server (or the rules) refused the last change: put the picture back and say so (§4).
func refuse(message_key: String) -> void:
	if _previous.get("kind", "") == "look":
		var cls := str(_previous["class"])
		if _deck.get("cards", {}).has(cls):
			_deck["cards"][cls][str(_previous["part"])] = _previous["value"]
	elif _previous.get("kind", "") == "squad":
		_deck["squad"] = _previous["value"]
	_previous = {}
	_refresh_all()
	toast(CardTokens.t(message_key))


# ================================================================== state A to B: the editor
func _on_card_pressed(class_id: String) -> void:
	card_selected.emit(class_id)
	var card: CardView = _cards.get(class_id)
	if card != null and not reduced_motion:
		var tween := create_tween()
		tween.tween_property(card, "pop", CardTokens.SELECT_SCALE, CardTokens.SELECT_SECONDS * 0.5)
		tween.tween_property(card, "pop", CardTokens.SELECT_SETTLE, CardTokens.SELECT_SECONDS * 0.5)
		card.set_selected(true)
		await tween.finished
		card.set_selected(false)
		card.pop = 1.0
	_open_editor(class_id)


func _open_editor(class_id: String) -> void:
	if _mode != "deck":
		return
	_mode = "editor"
	_edit_class = class_id
	_tab = "hair"
	_ensure_editor_cards()
	_deck_layer.visible = false
	_editor_layer.visible = true
	_layout_editor()
	_refresh_editor()
	var home := _sheet.position.x
	if reduced_motion:
		_editor_layer.modulate.a = 0.0
		create_tween().tween_property(_editor_layer, "modulate:a", 1.0, CardTokens.FADE_SECONDS)
	else:
		_sheet.position.x = size.x
		create_tween().tween_property(_sheet, "position:x", home, CardTokens.EDITOR_SHEET_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_editor() -> void:
	if _mode != "editor":
		return
	_mode = "deck"
	_editor_layer.visible = false
	_deck_layer.visible = true
	_close_picker(true)


func _ensure_editor_cards() -> void:
	if _editor_card == null:
		_editor_card = CardView.new()
		_editor_layer.add_child(_editor_card)
		_editor_card.build(_edit_class, false, false)
		_editor_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_editor_card.focus_mode = Control.FOCUS_NONE
		_editor_card.layout(CardTokens.EDITOR_CARD.x * _s, _s)
		_editor_card.set_idle_mode(CardPortrait.Mode.LIVE)
		_editor_card.always_holo = true
		_editor_card.holo_motion = not reduced_motion
		_editor_card._update_holo()
	for id in _class_ids:
		if not _strip_cards.has(id):
			var mini := CardView.new()
			_strip.add_child(mini)
			mini.build(id, true, false)
			mini.layout(CardTokens.STRIP_CARD.x * _s, _s)
			mini.apply_class(id, CardDeck.look_of(_deck, id))
			mini.set_idle_mode(CardPortrait.Mode.ONCE)
			mini.pressed.connect(_switch_editor_class.bind(id))
			_strip_cards[id] = mini


func _switch_editor_class(id: String) -> void:
	if id == _edit_class:
		return
	_edit_class = id
	if not CardDeck.options(id, "hair", _cosmetics).has(_tab) and _tab == "hair":
		pass
	_layout_editor()
	_refresh_editor()


func _refresh_editor() -> void:
	if _editor_card == null or _edit_class.is_empty():
		return
	var look := CardDeck.look_of(_deck, _edit_class)
	if _editor_card.class_id != _edit_class or _editor_card.portrait.class_id != _edit_class:
		_editor_card.apply_class(_edit_class, look)
	else:
		_editor_card.set_look(look)
	var squad := _squad()
	var at := squad.find(_edit_class)
	_editor_card.set_number(at + 1 if at >= 0 else 0)
	_editor_title.text = CardTokens.class_name_of(_edit_class)
	for id in _class_ids:
		var mini: CardView = _strip_cards.get(id)
		if mini != null:
			mini.set_look(CardDeck.look_of(_deck, id))
			mini.set_selected(id == _edit_class)
			mini.position.y = -(10.0 * _s if id == _edit_class else 0.0)
	var pal := CardTokens.palette(_edit_class)
	for tab in _tab_buttons:
		var b: Button = _tab_buttons[tab]
		b.text = CardTokens.t("tab_" + tab)
		var open: bool = tab == _tab
		CardTokens.button_skin(b, "tab_open" if open else "tab", _s, pal["base"])
		CardTokens.style_text(b, CardTokens.FONT_TAB, CardTokens.TEXT_LIGHT if open else CardTokens.TEXT_DARK, _s, CardTokens.OUTLINE_TEXT_SMALL if open else 0, "medium")
		b.custom_minimum_size = Vector2(0.0, CardTokens.PILL_H * _s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = tab == "skills" and false
	_build_tab()


func _select_tab(tab: String) -> void:
	_tab = tab
	_refresh_editor()


# ================================================================== editor tabs
func _build_tab() -> void:
	for child in _sheet_body.get_children():
		_sheet_body.remove_child(child)
		child.queue_free()
	CardTokens.gap(_sheet_body, 20.0, _s)
	match _tab:
		"hair":
			var flow := _flow()
			for id in CardDeck.options(_edit_class, "hair", _cosmetics):
				flow.add_child(_bubble_cell(CardTokens.hair_name(str(id)), str(id).to_upper(), str(id) == CardDeck.look_of(_deck, _edit_class)["hair"], "hair", str(id)))
		"eyes":
			_section("eye_color")
			_color_row("eye_color")
			_section("eye_makeup")
			var flow := _flow()
			for id in CardDeck.options(_edit_class, "makeup", _cosmetics):
				flow.add_child(_bubble_cell(CardTokens.choice_name("makeup", str(id)), "", str(id) == _card_value("makeup"), "makeup", str(id)))
		"outfit":
			var flow := _flow()
			for id in CardDeck.options(_edit_class, "outfit", _cosmetics):
				flow.add_child(_tile_cell(CardTokens.choice_name("outfit", str(id)), str(id) == _card_value("outfit"), str(id)))
		"body":
			_section("skin_tone")
			_color_row("skin")
		"skills":
			var flow := _flow()
			for i in 4:
				var socket := Panel.new()
				socket.custom_minimum_size = Vector2.ONE * CardTokens.SKILL_SOCKET * _s
				CardTokens.panel(socket, CardTokens.flat(CardTokens.DISABLED, CardTokens.INK, CardTokens.OUTLINE_BUTTON, CardTokens.SKILL_SOCKET * 0.5, _s))
				flow.add_child(socket)
			var soon := CardTokens.label(CardTokens.t("coming_soon"), CardTokens.FONT_EDITOR_NAME, CardTokens.TEXT_DARK, _s)
			soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_sheet_body.add_child(soon)


func _card_value(part: String) -> String:
	return str(_deck.get("cards", {}).get(_edit_class, {}).get(part, ""))


func _flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CardTokens.flow_gap(flow, CardTokens.BUBBLE_GAP, _s)
	_sheet_body.add_child(flow)
	return flow


func _section(key: String) -> void:
	_sheet_body.add_child(CardTokens.label(CardTokens.t(key), CardTokens.FONT_TAB, CardTokens.TEXT_DARK, _s))


func _cell_size() -> float:
	return (CardTokens.PHONE_BUBBLE if _phone else CardTokens.BUBBLE) * _s


## A round option bubble with a caption under it (§7.2). Selected: an orange ring.
func _bubble_cell(caption: String, glyph: String, selected: bool, part: String, choice: String) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2.ONE * _cell_size()
	CardTokens.button_skin(b, "bubble", _s)
	CardTokens.style_text(b, CardTokens.FONT_EDITOR_NAME, CardTokens.TEXT_DARK, _s)
	b.pressed.connect(_pick.bind(part, choice))
	column.add_child(b)
	if selected:
		_add_ring(b, _cell_size() * 0.5)
	column.add_child(_caption(caption))
	return column


func _tile_cell(caption: String, selected: bool, choice: String) -> Control:
	var column := VBoxContainer.new()
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = CardTokens.OUTFIT_TILE * _s
	CardTokens.button_skin(b, "secondary", _s)
	CardTokens.style_text(b, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, _s, 0, "medium")
	b.pressed.connect(_pick.bind("outfit", choice))
	column.add_child(b)
	if selected:
		_add_ring(b, 32.0 * _s)
	return column


func _caption(text: String) -> Label:
	var l := CardTokens.label(text, CardTokens.FONT_OPTION, CardTokens.TEXT_DARK, _s, 0, "medium")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _add_ring(target: Control, radius: float) -> void:
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.panel(ring, CardTokens.selected_ring(1.0, radius))
	target.add_child(ring)


## Paint blobs of eye colour / skin tone (names and colours from data/cosmetics) plus a Custom blob.
func _color_row(part: String) -> void:
	var flow := _flow()
	var current := _card_value(part)
	var entries: Array = _cosmetics.choices.get(part, []) if _cosmetics != null else []
	for entry in entries:
		var column := VBoxContainer.new()
		var b := Button.new()
		b.custom_minimum_size = Vector2.ONE * CardTokens.BLOB * _s
		CardTokens.button_skin(b, "blob", _s, Color(str(entry["color"])))
		b.tooltip_text = str(entry["name"])
		b.pressed.connect(_pick.bind(part, str(entry["id"])))
		column.add_child(b)
		if str(entry["id"]) == current:
			_add_ring(b, CardTokens.BLOB * _s * 0.5)
		column.add_child(_caption(str(entry["name"])))
		flow.add_child(column)
	if CardDeck.allows_custom_color(part, _cosmetics):
		var column := VBoxContainer.new()
		var custom := Button.new()
		custom.custom_minimum_size = Vector2.ONE * CardTokens.BLOB * _s
		CardTokens.button_skin(custom, "blob", _s, CardTokens.FRAME if not current.begins_with("#") else Color(current))
		CardTokens.style_text(custom, CardTokens.FONT_OPTION, CardTokens.TEXT_DARK, _s)
		custom.text = "+"
		custom.pressed.connect(_open_picker.bind(part))
		column.add_child(custom)
		if current.begins_with("#"):
			_add_ring(custom, CardTokens.BLOB * _s * 0.5)
		column.add_child(_caption(CardTokens.t("custom")))
		flow.add_child(column)


## The player picked an option: draw it at once, report it, and let refuse() undo it (§4, §15).
func _pick(part: String, choice: String) -> void:
	var cards: Dictionary = _deck.get("cards", {})
	if not cards.has(_edit_class) or str(cards[_edit_class].get(part, "")) == choice:
		return
	_previous = {"kind": "look", "class": _edit_class, "part": part, "value": cards[_edit_class].get(part, "")}
	cards[_edit_class][part] = choice
	_refresh_all()
	_wiggle()
	look_changed.emit(_edit_class, part, choice)


func _wiggle() -> void:
	if _editor_card == null:
		return
	_editor_card.portrait.pulse()
	if reduced_motion:
		return
	var tween := create_tween()
	var d := CardTokens.WIGGLE_SECONDS * 0.25
	tween.tween_property(_editor_card, "base_rotation", CardTokens.WIGGLE_DEGREES, d)
	tween.tween_property(_editor_card, "base_rotation", -CardTokens.WIGGLE_DEGREES, d * 2.0)
	tween.tween_property(_editor_card, "base_rotation", 0.0, d)


# ------------------------------------------------------------------ colour picker (§7.2)
var _picker_part := ""
var _picker_before := ""


func _open_picker(part: String) -> void:
	_picker_part = part
	_picker_before = _card_value(part)
	for child in _picker_layer.get_children():
		child.queue_free()
	var s := _s
	var shade := ColorRect.new()
	shade.color = CardTokens.STICKER_SHADOW
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_layer.add_child(shade)
	var box := Panel.new()
	CardTokens.panel(box, CardTokens.panel_paper(s, 32.0))
	var box_size: Vector2 = CardTokens.PICKER_SIZE * s
	box.size = box_size
	box.position = (size - box_size) * 0.5
	_picker_layer.add_child(box)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.margin(margin, 16.0, s)
	box.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_picker = ColorPicker.new()
	CardTokens.simple_picker(_picker)
	_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var start := _picker_before
	_picker.color = Color(start) if start.begins_with("#") else _current_color(part, start)
	_picker.color_changed.connect(_preview_color)
	column.add_child(_picker)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	CardTokens.gap(buttons, 16.0, s)
	column.add_child(buttons)
	var cancel := _pill(CardTokens.t("cancel"), _close_picker.bind(true))
	var done := _pill(CardTokens.t("done"), _close_picker.bind(false))
	for b in [cancel, done]:
		b.custom_minimum_size = Vector2(120.0 * s, CardTokens.PILL_H * s)
		CardTokens.button_skin(b, "secondary", s)
		CardTokens.style_text(b, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s, 0, "medium")
		buttons.add_child(b)
	_picker_layer.visible = true


func _current_color(part: String, id: String) -> Color:
	for entry in (_cosmetics.choices.get(part, []) if _cosmetics != null else []):
		if str(entry["id"]) == id:
			return Color(str(entry["color"]))
	return CardTokens.FRAME


func _preview_color(color: Color) -> void:
	var look := CardDeck.look_of(_deck, _edit_class)
	look[_picker_part] = "#" + color.to_html(false)
	if _editor_card != null:
		_editor_card.set_look(look)


func _close_picker(cancelled: bool) -> void:
	if not _picker_layer.visible:
		return
	_picker_layer.visible = false
	if cancelled:
		if _editor_card != null:
			_editor_card.set_look(CardDeck.look_of(_deck, _edit_class))
		return
	_pick(_picker_part, "#" + _picker.color.to_html(false))


# ------------------------------------------------------------------ reset
func _ask_reset() -> void:
	for child in _confirm_layer.get_children():
		child.queue_free()
	var s := _s
	var box := Panel.new()
	CardTokens.panel(box, CardTokens.panel_paper(s, 32.0))
	var box_size := Vector2(560.0, 240.0) * s
	box.size = box_size
	box.position = (size - box_size) * 0.5
	_confirm_layer.add_child(box)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.gap(column, 24.0, s)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.margin(margin, 24.0, s)
	box.add_child(margin)
	margin.add_child(column)
	var question := CardTokens.label(CardTokens.t("reset_confirm"), CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s, 0, "medium")
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	CardTokens.gap(row, 16.0, s)
	column.add_child(row)
	var no := _pill(CardTokens.t("no"), func() -> void: _confirm_layer.visible = false)
	var yes := _pill(CardTokens.t("yes"), func() -> void:
		_confirm_layer.visible = false
		reset_card.emit(_edit_class))
	for b in [no, yes]:
		b.custom_minimum_size = Vector2(120.0 * s, CardTokens.PILL_H * s)
		CardTokens.button_skin(b, "secondary", s)
		CardTokens.style_text(b, CardTokens.FONT_TAB, CardTokens.TEXT_DARK, s, 0, "medium")
		row.add_child(b)
	_confirm_layer.visible = true


# ================================================================== state C: summon (§10)
## Runs the summon of the squad cards; summon_finished fires at SUMMON_TOTAL (or at once on a tap).
func play_summon(squad: Array) -> void:
	if _mode == "summon":
		return
	_mode = "summon"
	_summon_done = false
	for child in _summon_layer.get_children():
		child.queue_free()
	_summon_layer.visible = true
	if reduced_motion:
		var fade := ColorRect.new()
		fade.color = CardTokens.FLASH
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.modulate.a = 0.0
		_summon_layer.add_child(fade)
		var t := create_tween()
		t.tween_property(fade, "modulate:a", 1.0, CardTokens.FADE_SECONDS)
		t.tween_callback(_finish_summon)
		_summon_tweens.append(t)
		return
	var centre := size * 0.5
	var card_size: Vector2 = CardTokens.CARD_SIZE * _s
	var stack: Array = []
	var index := 0
	for id in squad:
		var holder := Control.new()
		holder.size = card_size
		holder.pivot_offset = card_size * 0.5
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pal := CardTokens.palette(str(id))
		var front := CardFrame.new()
		front.kind = "solid"
		front.tint = CardTokens.SLATE_PLATE
		front.configure(str(id), _s, true)
		front.size = card_size
		var back := CardFrame.new()
		back.kind = "solid"
		back.tint = pal["shadow"]
		back.configure(str(id), _s, true)
		back.size = card_size
		back.visible = false
		var emblem := CardTokens.label(str(pal["emblem"]), CardTokens.FONT_FIGHT, CardTokens.TEXT_LIGHT, _s * 2.0, CardTokens.OUTLINE_TEXT)
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.size = card_size
		emblem.pivot_offset = card_size * 0.5
		back.add_child(emblem)
		holder.add_child(front)
		holder.add_child(back)
		var from_card: CardView = _cards.get(id)
		holder.position = (from_card.get_global_rect().position - _summon_layer.get_global_rect().position) if from_card != null else centre
		_summon_layer.add_child(holder)
		var target := centre - card_size * 0.5 + Vector2(float(index) * CardTokens.SUMMON_STACK_OFFSET * _s, -float(index) * CardTokens.SUMMON_STACK_OFFSET * _s)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(holder, "position", target, CardTokens.SUMMON_HOP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(holder, "scale:x", 0.0, CardTokens.SUMMON_FLIP * 0.5)
		tween.chain().tween_callback(func() -> void:
			front.visible = false
			back.visible = true)
		tween.chain().tween_property(holder, "scale:x", 1.0, CardTokens.SUMMON_FLIP * 0.5)
		tween.parallel().tween_property(emblem, "rotation", TAU, CardTokens.STAR_SPIN_SECONDS)
		_summon_tweens.append(tween)
		stack.append(holder)
		index += 1
	var fade_ui := create_tween()
	fade_ui.tween_property(_deck_layer, "modulate:a", 0.0, CardTokens.SUMMON_HOP)
	_summon_tweens.append(fade_ui)
	var burst := BurstView.new()
	burst.radius = CardTokens.BURST_RADIUS * _s
	burst.size = Vector2.ONE * burst.radius * 2.0
	burst.position = centre - burst.size * 0.5
	burst.pivot_offset = burst.size * 0.5
	burst.scale = Vector2.ZERO
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summon_layer.add_child(burst)
	var flash := ColorRect.new()
	flash.color = CardTokens.FLASH
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summon_layer.add_child(flash)
	var seq := create_tween()
	seq.tween_interval(CardTokens.SUMMON_HOP + CardTokens.SUMMON_FLIP)
	seq.tween_property(burst, "scale", Vector2.ONE, CardTokens.SUMMON_BURST).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	seq.tween_property(flash, "modulate:a", 1.0, CardTokens.SUMMON_FLASH * 0.5)
	seq.tween_interval(CardTokens.SUMMON_TOTAL - CardTokens.SUMMON_HOP - CardTokens.SUMMON_FLIP - CardTokens.SUMMON_BURST - CardTokens.SUMMON_FLASH * 0.5)
	seq.tween_callback(_finish_summon)
	_summon_tweens.append(seq)


func _on_summon_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		_finish_summon()


func _finish_summon() -> void:
	if _summon_done:
		return
	_summon_done = true
	for t in _summon_tweens:
		if t != null and t.is_valid():
			t.kill()
	_summon_tweens.clear()
	summon_finished.emit()


## Brings the deck back after a summon (the screen is usually replaced by the battle scene instead).
func reset_summon() -> void:
	_mode = "deck"
	_summon_layer.visible = false
	_deck_layer.modulate.a = 1.0


## An empty Control inside the card window where the 3D view lives: "deck" | "editor" | "mini".
func portrait_slot(class_id: String, kind: String) -> Control:
	match kind:
		"deck":
			var card: CardView = _cards.get(class_id)
			return card.window_slot if card != null else null
		"editor":
			return _editor_card.window_slot if _editor_card != null else null
		"mini":
			var mini: CardView = _strip_cards.get(class_id)
			return mini.window_slot if mini != null else null
	return null


# ================================================================== motion and input
func _process(delta: float) -> void:
	_time += delta
	if _mode == "deck":
		for card in _cards.values():
			card.animate(_time, delta, not reduced_motion)
	elif _mode == "editor" and _editor_card != null:
		_editor_card.animate(_time, delta, not reduced_motion)
	if not reduced_motion:
		for cloud in _clouds:
			cloud.position.x += CardTokens.CLOUD_SPEED * _s * delta
			if cloud.position.x > size.x:
				cloud.position.x = -cloud.size.x


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _picker_layer.visible:
		_close_picker(true)
	elif _confirm_layer.visible:
		_confirm_layer.visible = false
	elif _mode == "editor":
		_close_editor()
	elif _mode == "deck":
		back_pressed.emit()
	get_viewport().set_input_as_handled()


# ================================================================== the game wiring (§14)
func _wire_game() -> void:
	look_changed.connect(_send_look)
	squad_changed.connect(_send_squad)
	reset_card.connect(_send_reset)
	fight_pressed.connect(_start_fight)
	bag_pressed.connect(_open_bag)
	settings_pressed.connect(func() -> void: add_child(GraphicsPanel.new()))
	back_pressed.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	if GameState.ensure_profile():
		show_deck(GameState.profile.card_deck, ItemAssets.cosmetics())
		_intro()


## Coming back from a fight: the cards bob in, no other intro (§15).
func _intro() -> void:
	if reduced_motion:
		return
	for card in _cards.values():
		card.pop = 0.9
		card.modulate.a = 0.0
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "pop", 1.0, CardTokens.INTRO_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "modulate:a", 1.0, CardTokens.INTRO_SECONDS)


## Sends a command through the session (rules and validation are in logic/commands.gd) and waits for an
## online answer when there is one. Returns {"ok": bool, ...}.
func _send(request: Dictionary) -> Dictionary:
	var session = GameState.get_session()
	if session == null:
		return {"ok": false, "error": "no_session"}
	var result: Dictionary = session.command(request)
	if result.get("pending", false) and session.has_signal("command_completed"):
		var id: int = int(result.get("id", -1))
		while true:
			var done: Array = await session.command_completed
			if int(done[0]) == id:
				result = done[1]
				break
	return result


func _sync_from_profile() -> void:
	if GameState.profile != null:
		show_deck(GameState.profile.card_deck, ItemAssets.cosmetics())


func _send_look(class_id: String, part: String, choice: String) -> void:
	var result := await _send({"type": "card_look", "class": class_id, "part": part, "choice": choice})
	if result.get("ok", false):
		_sync_from_profile()
	else:
		refuse("change_failed")


func _send_squad(squad: Array) -> void:
	var result := await _send({"type": "card_squad", "squad": squad})
	if result.get("ok", false):
		_sync_from_profile()
	else:
		refuse("change_failed")


func _send_reset(class_id: String) -> void:
	var start := CardDeck.starter_card(class_id, ItemAssets.cosmetics())
	for part in CardDeck.PARTS:
		if str(_deck["cards"][class_id].get(part, "")) == str(start[part]):
			continue
		var result := await _send({"type": "card_look", "class": class_id, "part": part, "choice": str(start[part])})
		if not result.get("ok", false):
			_sync_from_profile()
			toast(CardTokens.t("change_failed"))
			return
	_sync_from_profile()


func _start_fight() -> void:
	if _busy or _mode == "summon":
		return
	_busy = true
	play_summon(_squad())
	await summon_finished
	GameState.start_journey()  # (leaves this scene)
	_busy = false
	reset_summon()


func _open_bag() -> void:
	if not GameState.ensure_profile() or is_instance_valid(_camp):
		return
	_camp = CampScreen.new()
	_camp.backpack_mode = true
	add_child(_camp)
	_camp.setup(GameState.profile, GameState.camp_data, GameState.item_rules, CombatDataLoader.load_default(), null, "", null, GameState.get_session())
	_camp.show_tab(0)
	_camp.closed.connect(func() -> void:
		_camp = null
		_sync_from_profile())
