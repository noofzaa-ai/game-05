extends Control
## The class-card hub (docs/ui/hub_layout_spec.md, Boss 2026-11-11): the home screen the player sees before a fight.
## Night ruins background, the 4 leather class cards with their live full-body characters, the service menu on the
## left, the squad tray (3 picks, fight order) and FIGHT. States: A hub, B look editor of one card, C summon, plus
## one "service" panel over the hub. Phones (CardTokens.is_phone) get the notch inset and 96 px tap targets.
## The screen draws the player's card deck (Profile.card_deck, rules in logic/card_deck.gd) and reports what the
## player wants through signals. It never changes the profile itself: the small controller at the bottom
## (auto_wire) turns the signals into the server commands `card_look` / `card_squad` on the session, then
## draws the deck the profile now holds (or calls refuse()).
## Every colour, size, string and art path comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const CardPortrait := preload("res://client/card_portrait.gd")
const TILT_SHADER := preload("res://client/card_tilt.gdshader")
const TILT_SHEEN_SHADER := preload("res://client/card_tilt_sheen.gdshader")
const TILT_CLIP_SHADER := preload("res://client/card_tilt_clip.gdshader")
const CardFrame := preload("res://client/card_frame.gd")
const CardSceneLayers := preload("res://client/card_scene_layers.gd")
const CardHolo := preload("res://client/card_holo.gd")
const CardCharacterScreen := preload("res://client/card_character_screen.gd")
const HubBlacksmithPanel := preload("res://client/hub_blacksmith_panel.gd")
const HubStoragePanel := preload("res://client/hub_storage_panel.gd")
const HubTailorPanel := preload("res://client/hub_tailor_panel.gd")
const HubShopPanel := preload("res://client/hub_shop_panel.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const CampScreen := preload("res://client/camp_screen.gd")
const GraphicsPanel := preload("res://client/graphics_panel.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const PackFetcher := preload("res://client/pack_fetcher.gd")  ## web: the battle packs FIGHT waits for
const TITLE_SCENE := "res://scenes/title.tscn"

signal card_selected(class_id: String)
signal look_changed(class_id: String, part: String, choice: String)  ## part: hair|outfit|eye_color|skin|makeup
signal squad_changed(squad: Array)  ## the full new order, 1..3 class ids
signal reset_card(class_id: String)
signal fight_pressed()
signal service_pressed(service: String)  ## a side-menu entry (blacksmith, shop, tailor, storage, quests, relics) or "account"
signal settings_pressed()
signal back_pressed()
signal summon_finished()

## true: the screen sends the commands itself (the game). Tests and shot scripts can set false.
var auto_wire := true
## Reduced motion (§9): no lift easing, pops or shakes; transitions become short fades. There is no game
## setting for it yet; whoever adds one sets this.
var reduced_motion := false
## Display-only state the rules will own (no logic exists yet: quests / unlocks / notifications). The game
## leaves them empty; whoever adds the rule fills them: locked side-menu services, locked class cards, badges.
var locked_services: Array = []
var locked_classes: Array = []
var service_badges := {}  ## service id -> "2" / "!"

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
var _bg_shade: Panel
var _deck_layer: Control
var _top_title: Label
var _gold_pill: Panel
var _gold_icon: TextureRect
var _gold_label: Label
var _settings_button: Button
var _account_button: Button
var _menu: Array = []  ## MenuEntry
var _row_scroll: ScrollContainer
var _row: Control
var _hint: Label
var _bar: Control  ## the squad tray
var _bar_art: TextureRect
var _slots: Array = []  ## TraySlot
var _slot_numbers: Array = []
var _fight: Button
var _fight_art: TextureRect
var _fight_label: Label
var _fight_progress: Label  ## web build: "Loading 42%" while the battle packs download (client/pack_fetcher.gd)
var _fight_waiting := false  ## FIGHT was pressed before the battle packs were in
var _fight_glow: Panel
var _stage_label: Label
var _cards := {}  ## class id -> HubCard
var _service_layer: Control
var _service_open := ""
var _character: CardCharacterScreen  ## the card character screen (spec §4), over the hub
var _panels := {}  ## service id -> the open-able service panel (hub_service_panel.gd), built on first use

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

	var _idle_mode := CardPortrait.Mode.LIVE  ## Boss 2026-11-13: every hub card animates at full frame rate (was 5 fps when not hovered)

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


# ================================================================== hub widgets (docs/ui/hub_layout_spec.md)
## One leather class card of the hub: the class-accent window with the live full-body portrait, the Boss frame
## art over it, the class name on the top plate and the squad plate at the foot (a button: add / remove).
class HubCard extends Control:
	signal pressed()
	signal squad_toggled()

	var class_id := ""
	var locked := false
	var portrait: Control
	var window_slot: Control
	var squad_button: Button
	var base_position := Vector2.ZERO
	var pop := 1.0  ## select / intro pop (scale)
	var lift := 0.0
	var hovered := false
	var in_squad := false
	var number := 0
	var s := 1.0
	var phone := false
	var _glow: Panel
	var _mask: Panel
	var _back: TextureRect
	var _frame: TextureRect
	var _name: Label
	var _squad_label: Label
	var _lock: Label
	var _focus: Panel
	var _back_glow: TextureRect  ## soft class light on the backdrop (slides with the backdrop: the depth cue)
	var _scene_back: CardSceneLayers  ## painted far + mid + contact shadow (replaces _back / _back_glow when the art exists)
	var _scene_front: CardSceneLayers  ## painted near layer, over the character's feet
	# Depth on hover / focus / tap (Boss 2026-11-12 option A): one perspective material shared by every layer of
	# this card (client/card_tilt.gdshader) and one for the frame art with the sheen. They are set only while the
	# card is tilted or easing back; an idle card has no material (nothing extra to draw).
	var _tilt_mat: ShaderMaterial
	var _sheen_mat: ShaderMaterial
	var _clip_mat: ShaderMaterial  ## window content while tilted (the mask's clip_children cannot be warped)
	var _tilt := Vector2.ZERO  ## smoothed, -1..1 (x right, y down)
	var _pointer := Vector2.ZERO  ## pointer from the card centre, -1..1
	var _has_pointer := false
	var _tap_left := 0.0  ## touch: seconds the tap tilt still holds
	var _sway := 0.0
	var _fx := 0.0  ## sheen fade 0..1
	var _warped := false

	func build(id: String) -> void:
		class_id = id
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		_glow = Panel.new()
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glow)
		_mask = Panel.new()  # rounded window shape: clips the backdrop and the character
		_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		add_child(_mask)
		_back = TextureRect.new()
		_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_back.stretch_mode = TextureRect.STRETCH_SCALE
		_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mask.add_child(_back)
		_back_glow = TextureRect.new()
		_back_glow.texture = CardTokens.hub_window_glow(id)
		_back_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_back_glow.stretch_mode = TextureRect.STRETCH_SCALE
		_back_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mask.add_child(_back_glow)
		_scene_back = CardSceneLayers.new()
		_mask.add_child(_scene_back)
		window_slot = Control.new()
		window_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mask.add_child(window_slot)
		portrait = CardPortrait.new()
		portrait.framing = "hub"
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		window_slot.add_child(portrait)
		portrait.set_render_mode(CardPortrait.Mode.LIVE)  # hub characters animate every frame from the start, not only after a hover (Boss 2026-11-13)
		_scene_front = CardSceneLayers.new()
		_mask.add_child(_scene_front)
		var painted := _scene_back.setup(id, CardSceneLayers.Part.BACK) and _scene_front.setup(id, CardSceneLayers.Part.FRONT)
		_scene_back.set_feet(CardTokens.PORTRAIT_HUB_BOTTOM)
		_back.visible = not painted
		_frame = CardTokens.art_rect(CardTokens.HUB_CARD_FRAME_PREFIX + id)
		add_child(_frame)
		_name = CardTokens.hub_label("", CardTokens.FONT_HUB_CARD_NAME, CardTokens.HUB_INK, 1.0)
		add_child(_name)
		_lock = CardTokens.hub_label(CardTokens.t("locked"), CardTokens.FONT_HUB_LOCKED, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB)
		_lock.visible = false
		add_child(_lock)
		_squad_label = CardTokens.hub_label("", CardTokens.FONT_HUB_SQUAD, CardTokens.HUB_INK, 1.0, 0, "medium")
		add_child(_squad_label)
		squad_button = Button.new()
		squad_button.focus_mode = Control.FOCUS_ALL
		squad_button.pressed.connect(func() -> void: squad_toggled.emit())
		add_child(squad_button)
		_focus = Panel.new()
		_focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus.visible = false
		add_child(_focus)
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))
		focus_entered.connect(func() -> void: _focus.visible = true)
		focus_exited.connect(func() -> void: _focus.visible = false)

	func _hover(on: bool) -> void:
		hovered = on
		if not on:
			_has_pointer = false
		portrait.set_hover(on)
		portrait.set_render_mode(CardPortrait.Mode.LIVE)  # hub cards always live (Boss 2026-11-13)

	func apply(look: Dictionary, p_in_squad: bool, p_number: int, p_locked: bool) -> void:
		in_squad = p_in_squad
		number = p_number
		locked = p_locked
		if portrait.class_id != class_id:
			portrait.set_class(class_id)
		portrait.set_look(look)
		_back.texture = CardTokens.window_gradient(class_id, locked)
		_back_glow.visible = not locked and not _scene_back.visible
		_scene_back.set_locked(locked)
		_scene_front.set_locked(locked)
		portrait.material = CardTokens.grey_material() if locked else null
		portrait.modulate = CardTokens.HUB_LOCKED if locked else CardTokens.HUB_WHITE
		_lock.visible = locked
		_name.text = CardTokens.class_name_of(class_id)
		_squad_label.text = "" if locked else (CardTokens.t("squad_n") % number if in_squad else CardTokens.t("squad_add"))
		squad_button.tooltip_text = CardTokens.t("remove_from_squad" if in_squad else "add_to_squad")
		squad_button.visible = not locked
		layout(size.x, s, phone)

	func layout(w: float, p_s: float, p_phone: bool) -> void:
		s = p_s
		phone = p_phone
		var h := w * CardTokens.HUB_CARD.y / CardTokens.HUB_CARD.x
		size = Vector2(w, h)
		custom_minimum_size = size
		pivot_offset = size * 0.5
		_frame.position = Vector2.ZERO
		_frame.size = size
		var win := CardTokens.HUB_CARD_WINDOW
		_mask.position = Vector2(win.position.x * w, win.position.y * h)
		_mask.size = Vector2(win.size.x * w, win.size.y * h)
		CardTokens.panel(_mask, CardTokens.flat(CardTokens.HUB_WINDOW_BOTTOM, CardTokens.HUB_WINDOW_BOTTOM, 0.0, CardTokens.HUB_CARD_WINDOW_RADIUS * w, 1.0))
		window_slot.size = _mask.size
		_place_depth()
		var pad := CardTokens.HUB_GLOW_PAD * s
		_glow.position = Vector2(pad, pad) * 0.5
		_glow.size = size - Vector2(pad, pad)
		CardTokens.panel(_glow, CardTokens.hub_glow(CardTokens.HUB_GLOW, CardTokens.HUB_GLOW_PAD * 1.4, CardTokens.HUB_RADIUS, s))
		_glow.visible = in_squad and not locked
		var unit := w / CardTokens.HUB_CARD.x
		var nr := CardTokens.HUB_CARD_NAME
		_name.position = Vector2(nr.position.x * w, nr.position.y * h)
		_name.size = Vector2(nr.size.x * w, nr.size.y * h)
		CardTokens.hub_fit(_name, _name.text, CardTokens.FONT_HUB_CARD_NAME, _name.size.x, CardTokens.HUB_SLOT_TEXT if locked else CardTokens.HUB_INK, unit)
		var sr := CardTokens.HUB_CARD_SQUAD
		_squad_label.position = Vector2(sr.position.x * w, sr.position.y * h)
		_squad_label.size = Vector2(sr.size.x * w, sr.size.y * h)
		CardTokens.hub_fit(_squad_label, _squad_label.text, CardTokens.FONT_HUB_SQUAD, _squad_label.size.x, CardTokens.HUB_INK, unit, 0, "medium")
		_lock.position = Vector2(0.0, CardTokens.HUB_CARD_LOCK_Y * h - 30.0 * unit)
		_lock.size = Vector2(w, 60.0 * unit)
		CardTokens.hub_text(_lock, CardTokens.FONT_HUB_LOCKED, CardTokens.HUB_CREAM, unit, CardTokens.OUTLINE_HUB)
		# squad plate: the whole foot of the card is the tap area (>= 96 reference px on phones)
		var tap_h := maxf(CardTokens.HUB_CARD_PLATE_TAP * h, CardTokens.tap(0.0, phone) * s)
		squad_button.position = Vector2(0.0, h - tap_h)
		squad_button.size = Vector2(w, tap_h)
		CardTokens.bare_button(squad_button, s, 12.0)
		_focus.position = Vector2(-4.0, -4.0) * s
		_focus.size = size + Vector2(8.0, 8.0) * s
		CardTokens.panel(_focus, CardTokens.hub_focus(s, CardTokens.HUB_RADIUS))

	func set_selected(_on: bool) -> void:
		pass

	func animate(delta: float, motion: bool) -> void:
		var target := 0.0
		if in_squad and not locked:
			target += CardTokens.HUB_CARD_LIFT
		if hovered or has_focus():
			target += CardTokens.HUB_CARD_FOCUS_LIFT
		lift = lerpf(lift, target, minf(1.0, delta * 12.0)) if motion else target
		position = base_position - Vector2(0.0, lift * s)
		scale = Vector2(pop, pop)
		_animate_depth(delta, motion)

	## Tilt toward the pointer (or the touch point for a moment after a tap, or a slow sway on keyboard / gamepad
	## focus), the depth layers and the frame sheen. Reduced motion or a locked card: flat, no material.
	func _animate_depth(delta: float, motion: bool) -> void:
		_tap_left = maxf(0.0, _tap_left - delta)
		var active := motion and not locked and (hovered or has_focus() or _tap_left > 0.0)
		var target := Vector2.ZERO
		if active:
			_sway += delta
			target = _pointer if (_has_pointer or _tap_left > 0.0) else Vector2(sin(_sway * CardTokens.HUB_TILT_SWAY_SPEED.x) * CardTokens.HUB_TILT_SWAY.x, cos(_sway * CardTokens.HUB_TILT_SWAY_SPEED.y) * CardTokens.HUB_TILT_SWAY.y)
		_tilt = _tilt.lerp(target, minf(1.0, delta * CardTokens.HUB_TILT_SMOOTH)) if motion else Vector2.ZERO
		_fx = move_toward(_fx, 1.0 if active else 0.0, delta / CardTokens.HUB_SHEEN_FADE_SECONDS) if motion else 0.0
		var live := active or _fx > 0.0 or _tilt.length_squared() > 0.00002
		if not live:
			_tilt = Vector2.ZERO
		if live != _warped:
			_set_warp(live)
			if not live:
				_place_depth()
		if live:
			_update_warp()
			_place_depth()

	## Backdrop (and its light) slide against the tilt, the character with it; the frame and plates stay.
	func _place_depth() -> void:
		var win := _mask.size
		var back := -_tilt * CardTokens.HUB_BACK_PARALLAX * win
		_back.size = win * CardTokens.HUB_BACK_ZOOM
		_back.position = (win - _back.size) * 0.5 + back
		_back_glow.size = win * CardTokens.HUB_BACK_GLOW_SIZE
		_back_glow.position = win * CardTokens.HUB_BACK_GLOW_AT - _back_glow.size * 0.5 + back
		window_slot.position = _tilt * CardTokens.HUB_FIGURE_PARALLAX * win
		_scene_back.set_depth(_tilt, window_slot.position)
		_scene_front.set_depth(_tilt, window_slot.position)

	func _set_warp(on: bool) -> void:
		_warped = on
		if on and _tilt_mat == null:
			_tilt_mat = ShaderMaterial.new()
			_tilt_mat.shader = TILT_SHADER
			_sheen_mat = ShaderMaterial.new()
			_sheen_mat.shader = TILT_SHEEN_SHADER
			_sheen_mat.set_shader_parameter("sheen_color", CardTokens.HUB_SHEEN_COLOR)
			_sheen_mat.set_shader_parameter("sheen_width", CardTokens.HUB_SHEEN_WIDTH)
			_clip_mat = ShaderMaterial.new()
			_clip_mat.shader = TILT_CLIP_SHADER
		var mat: ShaderMaterial = _tilt_mat if on else null
		for node in [_glow, _mask, _name, _lock, _squad_label, squad_button, _focus]:
			node.material = mat
		# While tilted the mask draws its own flat window (warped) and the content clips itself in the shader.
		_mask.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED if on else CanvasItem.CLIP_CHILDREN_ONLY
		var clip: ShaderMaterial = _clip_mat if on else null
		_back.material = clip
		_back_glow.material = clip
		_scene_back.set_clip(clip)
		_scene_front.set_clip(clip)
		portrait.set_view_material(clip)
		_frame.material = _sheen_mat if on else null

	func _update_warp() -> void:
		var g := get_global_transform()
		for m in [_tilt_mat, _sheen_mat, _clip_mat]:
			m.set_shader_parameter("card_size", size)
			m.set_shader_parameter("card_x", g.x)
			m.set_shader_parameter("card_y", g.y)
			m.set_shader_parameter("card_o", g.origin)
			m.set_shader_parameter("tilt", _tilt)
			m.set_shader_parameter("max_angle", CardTokens.HUB_TILT_ANGLE)
			m.set_shader_parameter("focal", CardTokens.HUB_TILT_FOCAL * size.x)
		_sheen_mat.set_shader_parameter("sheen_strength", CardTokens.HUB_SHEEN * _fx)
		_sheen_mat.set_shader_parameter("edge_strength", CardTokens.HUB_SHEEN_EDGE * _fx)
		_clip_mat.set_shader_parameter("clip_rect", Vector4(_mask.position.x, _mask.position.y, _mask.size.x, _mask.size.y))
		_clip_mat.set_shader_parameter("clip_radius", CardTokens.HUB_CARD_WINDOW_RADIUS * size.x)

	func _point_at(at: Vector2) -> void:
		_pointer = ((at / Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))) - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * 2.0

	func _gui_input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if touch != null and touch.pressed:  # touch has no hover: a tap tilts the card toward the touch point
			_point_at(touch.position)
			_tap_left = CardTokens.HUB_TILT_TAP_SECONDS
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_point_at(button.position)
			_tap_left = CardTokens.HUB_TILT_TAP_SECONDS
			pressed.emit()
			accept_event()
			return
		var motion := event as InputEventMouseMotion
		if motion != null:
			_point_at(motion.position)
			_has_pointer = true
			portrait.set_hover(true, Vector2(clampf(motion.position.x / maxf(size.x, 1.0), 0.0, 1.0), 0.5))
		if event.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if locked:
			return null
		var preview := CardTokens.hub_label(CardTokens.class_name_of(class_id), CardTokens.FONT_HUB_CARD_NAME, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB)
		set_drag_preview(preview)
		return {"deck_card": class_id}


## One side-menu entry (spec §2): leather plate + service medallion + parchment label. A Button, so it takes
## focus, keyboard / gamepad accept and touch. States: normal, hover / focus (glow, 6 px right), pressed
## (2 px back, darker, medallion 0.96), locked (grey + a reason line; a tap shows it as a toast), badge.
class MenuEntry extends Button:
	var service := ""
	var locked := false
	var locked_line := ""
	var badge := ""  ## "" none, "!" new, or a number
	var s := 1.0
	var _glow: Panel
	var _plate: TextureRect
	var _icon: TextureRect
	var _label: Label
	var _sub: Label
	var _badge: Panel
	var _badge_label: Label
	var _base_x := 0.0
	var _shift := 0.0

	func build(id: String, icon: String) -> void:
		service = id
		focus_mode = Control.FOCUS_ALL
		_glow = Panel.new()
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.visible = false
		add_child(_glow)
		_plate = CardTokens.art_rect(CardTokens.HUB_MENU_PLATE)
		add_child(_plate)
		_icon = CardTokens.art_rect(CardTokens.HUB_ICON_PREFIX + icon)
		add_child(_icon)
		_label = CardTokens.hub_label(CardTokens.t("svc_" + id), CardTokens.FONT_HUB_MENU, CardTokens.HUB_INK, 1.0)
		add_child(_label)
		_sub = CardTokens.hub_label("", CardTokens.FONT_HUB_MENU_SUB, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium")
		_sub.visible = false
		add_child(_sub)
		_badge = Panel.new()
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_badge)
		_badge_label = CardTokens.hub_label("", CardTokens.FONT_HUB_BADGE, CardTokens.HUB_BADGE_TEXT, 1.0, 0, "medium")
		_badge.add_child(_badge_label)
		mouse_entered.connect(_refresh_state)
		mouse_exited.connect(_refresh_state)
		focus_entered.connect(_refresh_state)
		focus_exited.connect(_refresh_state)
		button_down.connect(_refresh_state)
		button_up.connect(_refresh_state)

	func layout(at: Vector2, p_s: float, phone: bool) -> void:
		s = p_s
		var w := CardTokens.HUB_MENU_ENTRY.x * s
		var h := maxf(CardTokens.HUB_MENU_ENTRY.y, CardTokens.tap(0.0, phone)) * s
		_base_x = at.x
		position = at
		size = Vector2(w, h)
		CardTokens.bare_button(self, s, CardTokens.HUB_RADIUS)
		var plate_h := w * CardTokens.art_aspect(CardTokens.HUB_MENU_PLATE, 0.29)
		_plate.size = Vector2(w, plate_h)
		_plate.position = Vector2(0.0, (h - plate_h) * 0.5)
		var icon_h := plate_h * CardTokens.HUB_MENU_ICON_SCALE
		_icon.size = Vector2(icon_h, icon_h)
		_icon.pivot_offset = _icon.size * 0.5
		_icon.position = Vector2(w * CardTokens.HUB_MENU_ICON_X - icon_h * 0.5, (h - icon_h) * 0.5)
		_glow.position = _plate.position + Vector2(8.0, 8.0) * s
		_glow.size = _plate.size - Vector2(16.0, 16.0) * s
		CardTokens.panel(_glow, CardTokens.hub_glow(CardTokens.HUB_GLOW, 12.0, plate_h * 0.3 / maxf(s, 0.01), s))
		var lx := w * CardTokens.HUB_MENU_LABEL.x
		var lw := w * (CardTokens.HUB_MENU_LABEL.y - CardTokens.HUB_MENU_LABEL.x)
		_label.size = Vector2(lw, plate_h * (0.5 if locked else 0.8))
		_label.position = Vector2(lx, _plate.position.y + plate_h * (0.12 if locked else 0.1))
		CardTokens.hub_fit(_label, _label.text, CardTokens.FONT_HUB_MENU, lw * 0.92, CardTokens.HUB_CREAM if locked else CardTokens.HUB_INK, s, CardTokens.OUTLINE_HUB if locked else 0)
		_sub.text = locked_line
		_sub.visible = locked
		_sub.size = Vector2(lw, plate_h * 0.3)
		_sub.position = Vector2(lx, _plate.position.y + plate_h * 0.6)
		CardTokens.hub_fit(_sub, _sub.text, CardTokens.FONT_HUB_MENU_SUB, lw * 0.95, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "medium")
		var r := CardTokens.HUB_BADGE_R * s
		_badge.size = Vector2(r, r) * 2.0
		_badge.position = Vector2(w * CardTokens.HUB_BADGE_AT.x, _plate.position.y + plate_h * CardTokens.HUB_BADGE_AT.y) - Vector2(r, r)
		CardTokens.panel(_badge, CardTokens.hub_badge(s))
		_badge_label.size = _badge.size
		_badge_label.text = badge
		CardTokens.hub_text(_badge_label, CardTokens.FONT_HUB_BADGE, CardTokens.HUB_BADGE_TEXT, s, 0, "medium")
		_badge.visible = badge != "" and not locked
		_plate.material = CardTokens.grey_material() if locked else null
		_icon.material = _plate.material
		tooltip_text = locked_line if locked else CardTokens.t("svc_" + service)
		_refresh_state()

	func _refresh_state() -> void:
		if not is_inside_tree():
			return
		var hot := (is_hovered() or has_focus()) and not locked
		var down := button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		_glow.visible = hot
		_shift = CardTokens.HUB_MENU_HOVER_SHIFT if hot else 0.0
		if down and not locked:
			_shift -= CardTokens.HUB_MENU_PRESS_SHIFT
		position.x = _base_x + _shift * s
		var tint: Color = CardTokens.HUB_LOCKED if locked else (CardTokens.HUB_PRESSED if down else (CardTokens.HUB_HOVER if hot else CardTokens.HUB_WHITE))
		_plate.modulate = tint
		_icon.modulate = tint
		_icon.scale = Vector2.ONE * (CardTokens.HUB_MENU_PRESS_ICON if down and not locked else 1.0)


## One window of the squad tray (number medallion = fight order): the picked card's head, or an empty "+".
## Tap a filled slot = take that card out; drag between slots = reorder; drop a deck card = put it here.
class TraySlot extends Button:
	var index := 0
	var class_id := ""
	var drop_callback: Callable  ## (from_slot: int, to_slot: int)
	var card_drop_callback: Callable  ## (class_id: String, to_slot: int)
	var portrait: Control
	var _plus: Label

	func build() -> void:
		focus_mode = Control.FOCUS_ALL
		portrait = CardPortrait.new()
		portrait.framing = "bust"
		# Inside the slot's parchment window only (not over its frame border).
		var inset := CardTokens.HUB_TRAY_WINDOW_INSET
		portrait.anchor_left = inset.x
		portrait.anchor_top = inset.y
		portrait.anchor_right = 1.0 - inset.z
		portrait.anchor_bottom = 1.0 - inset.w
		portrait.visible = false
		add_child(portrait)
		_plus = CardTokens.hub_label("+", CardTokens.FONT_HUB_TITLE, CardTokens.HUB_SLOT_TEXT, 1.0)
		_plus.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_plus)

	func show_card(id: String, look: Dictionary, s: float) -> void:
		class_id = id
		CardTokens.bare_button(self, s, 10.0)
		portrait.visible = not id.is_empty()
		_plus.visible = id.is_empty()
		CardTokens.hub_text(_plus, CardTokens.FONT_HUB_TITLE, CardTokens.HUB_SLOT_TEXT, s)
		tooltip_text = CardTokens.t("tray_add") if id.is_empty() else CardTokens.t("remove_from_squad")
		if not id.is_empty():
			portrait.set_render_mode(CardPortrait.Mode.ONCE)
			portrait.set_class(id)
			portrait.set_look(look)

	func _get_drag_data(_at: Vector2) -> Variant:
		if class_id.is_empty():
			return null
		var preview := CardTokens.hub_label(CardTokens.class_name_of(class_id), CardTokens.FONT_HUB_CARD_NAME, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB)
		set_drag_preview(preview)
		return {"squad_slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and ((data.has("squad_slot") and int(data["squad_slot"]) != index) or data.has("deck_card"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("squad_slot"):
			drop_callback.call(int(data["squad_slot"]), index)
		else:
			card_drop_callback.call(str(data["deck_card"]), index)

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
	_build_service_layer()
	_build_character_screen()
	resized.connect(_layout)
	_layout()
	if auto_wire:
		_wire_game()


func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.texture = CardTokens.tex(CardTokens.HUB_BG) if CardTokens.tex(CardTokens.HUB_BG) != null else CardTokens.sky_gradient()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg_shade = Panel.new()
	_bg_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardTokens.panel(_bg_shade, CardTokens.hub_shade(CardTokens.HUB_SCENE_DIM))
	add_child(_bg_shade)


## The hub (state A): top bar, side menu, the card row, the squad tray and FIGHT.
func _build_deck_layer() -> void:
	_deck_layer = Control.new()
	_deck_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deck_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deck_layer)
	_top_title = CardTokens.label(CardTokens.t("hub_title"), CardTokens.FONT_HUB_TITLE, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
	_deck_layer.add_child(_top_title)
	_gold_pill = Panel.new()
	_gold_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_layer.add_child(_gold_pill)
	_gold_icon = CardTokens.art_rect(CardTokens.HUB_SYS_PREFIX + "gold")
	_deck_layer.add_child(_gold_icon)
	_gold_label = CardTokens.hub_label("0", CardTokens.FONT_HUB_GOLD, CardTokens.HUB_CREAM, 1.0, 0, "medium")
	_gold_pill.add_child(_gold_label)
	_settings_button = _sys_button("settings", func() -> void: settings_pressed.emit())
	_account_button = _sys_button("account", func() -> void: service_pressed.emit("account"))
	for service in CardTokens.HUB_SERVICES:
		var entry := MenuEntry.new()
		entry.build(str(service["id"]), str(service["icon"]))
		entry.pressed.connect(_on_menu.bind(entry))
		_deck_layer.add_child(entry)
		_menu.append(entry)
	_row_scroll = ScrollContainer.new()
	_row_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_row_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_row_scroll.follow_focus = true
	_row_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_deck_layer.add_child(_row_scroll)
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row_scroll.add_child(_row)
	_hint = CardTokens.hub_label(CardTokens.t("hub_hint"), CardTokens.FONT_HUB_HINT, CardTokens.HUB_MUTED, 1.0, CardTokens.OUTLINE_HUB, "medium")
	_deck_layer.add_child(_hint)
	_bar = Control.new()  # the squad tray
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_deck_layer.add_child(_bar)
	_bar_art = CardTokens.art_rect(CardTokens.HUB_TRAY)
	_bar.add_child(_bar_art)
	for i in CardDeck.SQUAD_MAX:
		var slot := TraySlot.new()
		slot.index = i
		slot.build()
		slot.drop_callback = _on_slot_drop
		slot.card_drop_callback = _on_card_drop
		slot.pressed.connect(_on_tray_pressed.bind(slot))
		_bar.add_child(slot)
		_slots.append(slot)
		var number := CardTokens.hub_label(str(i + 1), CardTokens.FONT_HUB_TRAY_NUM, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB)
		_bar.add_child(number)
		_slot_numbers.append(number)
	_fight_glow = Panel.new()
	_fight_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_layer.add_child(_fight_glow)
	_fight = Button.new()
	_fight.focus_mode = Control.FOCUS_ALL
	_fight.tooltip_text = CardTokens.t("fight")
	_fight.pressed.connect(func() -> void: fight_pressed.emit())
	_fight.button_down.connect(func() -> void: _fight_art.modulate = CardTokens.HUB_PRESSED)
	_fight.button_up.connect(func() -> void: _fight_art.modulate = CardTokens.HUB_WHITE)
	_deck_layer.add_child(_fight)
	_fight_art = CardTokens.art_rect(CardTokens.HUB_FIGHT)
	_fight.add_child(_fight_art)
	_fight_label = CardTokens.hub_label(CardTokens.t("fight"), CardTokens.FONT_HUB_FIGHT, CardTokens.HUB_INK, 1.0)
	_fight.add_child(_fight_label)
	_fight_progress = CardTokens.hub_label("", CardTokens.FONT_HUB_STAGE, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium")
	_fight_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fight_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fight_progress.visible = false
	_fight.add_child(_fight_progress)
	_stage_label = CardTokens.hub_label(CardTokens.stage_name(), CardTokens.FONT_HUB_STAGE, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium")
	_deck_layer.add_child(_stage_label)


## A round system button (settings / account / back) drawn from the hub art.
func _sys_button(art: String, callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = CardTokens.t(art)
	var picture := CardTokens.art_rect(CardTokens.HUB_SYS_PREFIX + art)
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(picture)
	b.pressed.connect(callback)
	b.button_down.connect(func() -> void: picture.modulate = CardTokens.HUB_PRESSED)
	b.button_up.connect(func() -> void: picture.modulate = CardTokens.HUB_WHITE)
	_deck_layer.add_child(b)
	return b


## The panel a side-menu service opens over the hub (spec §2). For now a "Coming soon" panel.
func _build_service_layer() -> void:
	_service_layer = Control.new()
	_service_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_service_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_service_layer.visible = false
	add_child(_service_layer)
	move_child(_service_layer, _toast.get_index())  # under the toast


## The full-screen card character screen (Equipment / Outfit / Skills), opened by tapping a hub card.
func _build_character_screen() -> void:
	_character = CardCharacterScreen.new()
	_character.visible = false
	_character.reduced_motion = reduced_motion
	add_child(_character)
	move_child(_character, _service_layer.get_index())  # under the service panels and the toast
	_character.send = _send
	_character.notify = _character_toast
	_character.closed.connect(_on_character_closed)
	_character.settings_pressed.connect(func() -> void: settings_pressed.emit())
	_character.account_pressed.connect(func() -> void: service_pressed.emit("account"))
	_character.outfit_requested.connect(open_tailor)
	_character.blacksmith_requested.connect(open_blacksmith_on)
	_character.changed.connect(func() -> void:
		if GameState.profile != null:
			set_gold(GameState.profile.stash.gold))


## A status line of the character screen: the toast, at the foot of the screen (its top bar holds the switcher).
func _character_toast(text: String) -> void:
	toast(text)
	_toast.position.y = size.y - _toast.size.y - CardTokens.CHAR_TOAST_BOTTOM * _s


## Opens the character screen of `class_id` (the hub stays under it, hidden).
func open_character(class_id: String) -> void:
	if _mode != "deck" or not _class_ids.has(class_id):
		return
	_mode = "character"
	_deck_layer.visible = false
	_character.open(class_id, _class_ids, _deck)


func _on_character_closed() -> void:
	if _mode == "character":
		_mode = "deck"
	_deck_layer.visible = true
	_sync_from_profile_if_wired()


func _sync_from_profile_if_wired() -> void:
	if auto_wire:
		_sync_from_profile()


# ================================================================== layout
func _layout() -> void:
	_s = CardTokens.scale_for(size)
	_phone = CardTokens.is_phone(size)
	var s := _s
	var device := _device_safe_x()
	var side := CardTokens.hub_safe_x(size, s, device)
	var phone_extra := side - CardTokens.HUB_SAFE.x * s  # the extra phone / notch inset, 0 on a desktop
	# top bar: title left, gold + settings + account right
	var title_h := CardTokens.FONT_HUB_TITLE * 1.6 * s
	_top_title.position = Vector2(side, CardTokens.HUB_TITLE_Y * s - title_h * 0.5)
	_top_title.size = Vector2(size.x * 0.4, title_h)
	CardTokens.style_text(_top_title, CardTokens.FONT_HUB_TITLE, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
	var sys := CardTokens.tap(CardTokens.HUB_SYS_SIZE, _phone) * s
	var x := size.x - side
	for b in [_account_button, _settings_button]:
		x -= sys
		b.position = Vector2(x, CardTokens.HUB_SYS_Y * s)
		b.size = Vector2(sys, sys)
		CardTokens.bare_button(b, s, CardTokens.HUB_SYS_SIZE * 0.5)
		x -= CardTokens.HUB_SYS_GAP * s
	var pill := CardTokens.HUB_GOLD_SIZE * s
	x -= CardTokens.HUB_GOLD_GAP * s - CardTokens.HUB_SYS_GAP * s + pill.x
	_gold_pill.position = Vector2(x, CardTokens.HUB_SYS_Y * s + (sys - pill.y) * 0.5)
	_gold_pill.size = pill
	CardTokens.panel(_gold_pill, CardTokens.hub_pill(s))
	var coin := pill.y * 1.15
	_gold_icon.size = Vector2(coin, coin)
	_gold_icon.position = _gold_pill.position - Vector2(pill.y * 0.15, pill.y * 0.075)
	_gold_label.position = Vector2(coin * 0.8, 0.0)
	_gold_label.size = Vector2(pill.x - coin * 0.9, pill.y)
	CardTokens.hub_text(_gold_label, CardTokens.FONT_HUB_GOLD, CardTokens.HUB_CREAM, s, 0, "medium")
	# side menu (left)
	var menu_x := CardTokens.HUB_MENU_X * s + phone_extra
	for i in _menu.size():
		var entry: MenuEntry = _menu[i]
		entry.locked = locked_services.has(entry.service)
		entry.locked_line = CardTokens.t("svc_locked_line") if entry.locked else ""
		entry.badge = str(service_badges.get(entry.service, ""))
		entry.layout(Vector2(menu_x, (CardTokens.HUB_MENU_Y + float(i) * CardTokens.HUB_MENU_STEP) * s), s, _phone)
	# card row: right of the menu; cards shrink to HUB_CARD_MIN_W, then the row scrolls (never two rows)
	var row_left := CardTokens.HUB_CARD_AREA_X * s + phone_extra
	var row_right := size.x - side
	var avail := maxf(row_right - row_left, 1.0)
	var count := maxi(_class_ids.size(), 1)
	var gap := CardTokens.HUB_CARD_GAP * s
	var card_w := CardTokens.HUB_CARD.x * s
	if _phone:
		card_w = minf(card_w * CardTokens.HUB_PHONE_CARD_GROW, (avail - gap * (count - 1)) / count)
		card_w = maxf(card_w, CardTokens.HUB_CARD.x * s)
	var need := card_w * count + gap * (count - 1)
	if need > avail:
		card_w = maxf((avail - gap * (count - 1)) / count, CardTokens.HUB_CARD_MIN_W * s)
		need = card_w * count + gap * (count - 1)
	var card_h := card_w * CardTokens.HUB_CARD.y / CardTokens.HUB_CARD.x
	var pad := (CardTokens.HUB_CARD_LIFT + CardTokens.HUB_CARD_FOCUS_LIFT + CardTokens.HUB_GLOW_PAD) * s
	_row_scroll.position = Vector2(row_left, CardTokens.HUB_CARD_TOP * s - pad)
	_row_scroll.size = Vector2(avail, card_h + pad * 2.0)
	_row.custom_minimum_size = Vector2(maxf(need, avail), card_h + pad * 2.0)
	var start_x := (maxf(need, avail) - need) * 0.5
	var index := 0
	for id in _class_ids:
		var card: HubCard = _cards.get(id)
		if card == null:
			continue
		card.layout(card_w, s, _phone)
		card.base_position = Vector2(start_x + float(index) * (card_w + gap), pad)
		card.position = card.base_position
		index += 1
	_hint.position = Vector2(row_left, maxf(CardTokens.HUB_HINT_Y * s, _row_scroll.position.y + _row_scroll.size.y - pad * 0.5))
	_hint.size = Vector2(avail, CardTokens.FONT_HUB_HINT * 1.6 * s)
	CardTokens.hub_fit(_hint, _hint.text, CardTokens.FONT_HUB_HINT, avail, CardTokens.HUB_MUTED, s, CardTokens.OUTLINE_HUB, "medium")
	# FIGHT (bottom right) and the squad tray (bottom, right of the menu column); the tray never runs under FIGHT
	var fight_w := CardTokens.HUB_FIGHT_W * s
	var tray_x := CardTokens.HUB_TRAY_X * s + phone_extra
	var tray_w := CardTokens.HUB_TRAY_W * s
	var fight_x := size.x - side - fight_w
	if tray_x + tray_w + gap > fight_x:  # narrow screens: shrink FIGHT first, then the tray
		fight_w = maxf(CardTokens.HUB_FIGHT_MIN_W * s, size.x - side - (tray_x + tray_w + gap))
		fight_x = size.x - side - fight_w
		tray_w = minf(tray_w, fight_x - gap - tray_x)
	var fight_h := fight_w * CardTokens.art_aspect(CardTokens.HUB_FIGHT, 0.45)
	_fight.size = Vector2(fight_w, fight_h)
	_fight.position = Vector2(fight_x, size.y - CardTokens.HUB_TRAY_BOTTOM * s - fight_h)
	CardTokens.bare_button(_fight, s, CardTokens.HUB_RADIUS)
	_fight_art.size = _fight.size
	_fight_glow.position = _fight.position + _fight.size * Vector2(0.06, 0.25)
	_fight_glow.size = _fight.size * Vector2(0.88, 0.5)
	CardTokens.panel(_fight_glow, CardTokens.hub_glow(CardTokens.HUB_FIGHT_GLOW, CardTokens.HUB_GLOW_PAD * 1.5, CardTokens.HUB_RADIUS, s))
	var text_w := fight_w * CardTokens.HUB_FIGHT_TEXT_W
	_fight_label.size = Vector2(text_w, fight_h * 0.5)
	_fight_label.position = Vector2(fight_w * CardTokens.HUB_FIGHT_TEXT.x - text_w * 0.5, fight_h * CardTokens.HUB_FIGHT_TEXT.y - fight_h * 0.25)
	CardTokens.hub_fit(_fight_label, _fight_label.text, CardTokens.FONT_HUB_FIGHT, text_w, CardTokens.HUB_INK if not _fight.disabled else CardTokens.HUB_SLOT_TEXT, s)
	_fight_progress.size = Vector2(fight_w, CardTokens.FONT_HUB_STAGE * 1.6 * s)
	_fight_progress.position = Vector2(0.0, fight_h - _fight_progress.size.y * 1.05)
	_fit_fight_progress()
	_stage_label.size = Vector2(fight_w, CardTokens.FONT_HUB_STAGE * 1.6 * s)
	_stage_label.position = Vector2(fight_x, _fight.position.y - _stage_label.size.y)
	CardTokens.hub_fit(_stage_label, _stage_label.text, CardTokens.FONT_HUB_STAGE, fight_w, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "medium")
	var tray_h := tray_w * CardTokens.art_aspect(CardTokens.HUB_TRAY, 0.27)
	_bar.position = Vector2(tray_x, size.y - CardTokens.HUB_TRAY_BOTTOM * s - tray_h)
	_bar.size = Vector2(tray_w, tray_h)
	_bar_art.size = _bar.size
	for i in _slots.size():
		var r: Rect2 = CardTokens.HUB_TRAY_SLOTS[i]
		var slot: TraySlot = _slots[i]
		slot.position = Vector2(r.position.x * tray_w, r.position.y * tray_h)
		slot.size = Vector2(r.size.x * tray_w, r.size.y * tray_h)
		var number: Label = _slot_numbers[i]
		number.size = Vector2(r.size.x * tray_w, CardTokens.FONT_HUB_TRAY_NUM * 1.4 * s)
		number.position = Vector2(r.position.x * tray_w, CardTokens.HUB_TRAY_NUM_Y * tray_h - number.size.y * 0.5)
		CardTokens.hub_text(number, CardTokens.FONT_HUB_TRAY_NUM, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB)
	_refresh_squad_bar()
	_layout_editor()
	_layout_toast()
	_layout_service()


## The device's own safe area (notch / rounded corners) as a side inset, in this control's pixels.
func _device_safe_x() -> float:
	if OS.has_feature("headless") or not is_inside_tree():
		return 0.0
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or screen.x <= 0:
		return 0.0
	var inset := float(maxi(safe.position.x, screen.x - safe.end.x))
	return inset * size.x / float(screen.x) if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else 0.0


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


## The gold counter of the top bar (the profile's stash gold).
func set_gold(amount: int) -> void:
	_gold_label.text = str(amount)


func _rebuild_cards() -> void:
	for card in _cards.values():
		card.queue_free()
	_cards.clear()
	for id in _class_ids:
		var card := HubCard.new()
		_row.add_child(card)
		card.build(id)
		card.portrait.set_idle_variants(not reduced_motion)  # idle variants (Boss 2026-11-12), off for reduced motion
		card.layout(CardTokens.HUB_CARD.x * _s, _s, _phone)
		card.pressed.connect(_on_card_pressed.bind(id))
		card.squad_toggled.connect(_toggle_squad.bind(id))
		_cards[id] = card


func _squad() -> Array:
	return (_deck.get("squad", []) as Array).duplicate()


func _refresh_all() -> void:
	var squad := _squad()
	for id in _class_ids:
		var card: HubCard = _cards.get(id)
		if card == null:
			continue
		var at := squad.find(id)
		card.apply(CardDeck.look_of(_deck, id), at >= 0, at + 1, locked_classes.has(id))
		if at >= 0 and squad.size() <= 1:
			card.squad_button.tooltip_text = CardTokens.t("squad_need_one")
	_refresh_squad_bar()
	_fight.disabled = squad.is_empty()
	_fight_glow.visible = not squad.is_empty()
	_fight_art.material = CardTokens.grey_material() if squad.is_empty() else null
	_stage_label.text = CardTokens.t("fight_need") if squad.is_empty() else CardTokens.stage_name()
	if _mode == "editor":
		_refresh_editor()


func _refresh_squad_bar() -> void:
	if _slots.is_empty() or _deck.is_empty():
		return
	var squad := _squad()
	for i in _slots.size():
		var slot: TraySlot = _slots[i]
		var id := str(squad[i]) if i < squad.size() else ""
		slot.show_card(id, CardDeck.look_of(_deck, id) if not id.is_empty() else {}, _s)


# ================================================================== squad
func _toggle_squad(class_id: String) -> void:
	if locked_classes.has(class_id):
		toast(CardTokens.t("locked_toast") % CardTokens.class_name_of(class_id))
		return
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


## Tap a tray slot: a filled one takes that card out; an empty one explains how to add.
func _on_tray_pressed(slot: TraySlot) -> void:
	if slot.class_id.is_empty():
		toast(CardTokens.t("hub_hint"))
	else:
		_toggle_squad(slot.class_id)


func _on_slot_drop(from: int, to: int) -> void:
	var squad := _squad()
	if from < 0 or from >= squad.size():
		return
	var moved = squad.pop_at(from)
	squad.insert(mini(to, squad.size()), moved)
	_set_squad(squad)


## A deck card dropped on tray slot `to`: it goes there (moving if already in, replacing when the tray is full).
func _on_card_drop(class_id: String, to: int) -> void:
	if locked_classes.has(class_id):
		toast(CardTokens.t("locked_toast") % CardTokens.class_name_of(class_id))
		return
	var squad := _squad()
	var at := squad.find(class_id)
	if at >= 0:
		squad.remove_at(at)
	elif squad.size() >= CardDeck.SQUAD_MAX:
		squad.remove_at(mini(to, squad.size() - 1))
	squad.insert(mini(to, squad.size()), class_id)
	_set_squad(squad)


func _set_squad(squad: Array) -> void:
	_previous = {"kind": "squad", "value": _squad()}
	_deck["squad"] = squad
	_refresh_all()
	squad_changed.emit(squad)


## A change the rules do not allow: shake the squad tray and say why (§9).
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


# ================================================================== side menu and its panels
func _on_menu(entry: MenuEntry) -> void:
	if entry.locked:
		toast(entry.locked_line)
		return
	service_pressed.emit(entry.service)


## Opens what a service shows. Tailor = the look editor of the first squad card; Storage = the backpack
## window the old Bag button opened; the rest are "Coming soon" for now.
func open_service(service: String) -> void:
	match service:
		"blacksmith", "storage", "shop":
			_service_panel(service).open()
		"tailor":
			var squad := _squad()
			var id := str(squad[0]) if not squad.is_empty() else (str(_class_ids[0]) if not _class_ids.is_empty() else "")
			open_tailor(id)
		_:
			_show_soon(service)


## The Blacksmith / Storage panel (built once, over the hub and the character screen, under the toast).
func _service_panel(service: String) -> Control:
	if not _panels.has(service):
		var panel: Control
		match service:
			"blacksmith": panel = HubBlacksmithPanel.new()
			"tailor": panel = HubTailorPanel.new()
			"shop": panel = HubShopPanel.new()
			_: panel = HubStoragePanel.new()
		panel.visible = false
		panel.reduced_motion = reduced_motion
		panel.send = _send
		add_child(panel)
		move_child(panel, _toast.get_index())
		panel.changed.connect(func() -> void:
			if GameState.profile != null:
				set_gold(GameState.profile.stash.gold))
		panel.closed.connect(func() -> void:
			if _mode == "character":
				if GameState.profile != null:
					_deck = GameState.profile.card_deck.duplicate(true)
					_character.set_deck(_deck)
				_character.refresh()
			else:
				_sync_from_profile_if_wired())
		_panels[service] = panel
	return _panels[service]


## Tailor (full screen) on class card `class_id`; from the character screen's Outfit tab it opens over it.
func open_tailor(class_id: String) -> void:
	_service_panel("tailor").open_for(class_id)


## The character screen's Blacksmith button: the Blacksmith panel over it, opened on that piece (spec §5 depth 2).
func open_blacksmith_on(item_id: String) -> void:
	_service_panel("blacksmith").open_on(item_id)


func _show_soon(service: String) -> void:
	_service_open = service
	_service_layer.visible = true
	_layout_service()


func _close_service() -> void:
	_service_open = ""
	_service_layer.visible = false


func _layout_service() -> void:
	if _service_layer == null:
		return
	for child in _service_layer.get_children():
		_service_layer.remove_child(child)
		child.queue_free()
	if _service_open.is_empty():
		return
	var s := _s
	var shade := Panel.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.panel(shade, CardTokens.hub_shade(CardTokens.HUB_DIM))
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_service())
	_service_layer.add_child(shade)
	var box := Panel.new()
	box.size = CardTokens.HUB_PANEL_SIZE * s
	box.position = (size - box.size) * 0.5
	CardTokens.panel(box, CardTokens.hub_leather(s))
	_service_layer.add_child(box)
	var paper := Panel.new()
	var m := CardTokens.HUB_PANEL_MARGIN * s * 0.5
	paper.position = Vector2(m, m)
	paper.size = box.size - Vector2(m, m) * 2.0
	CardTokens.panel(paper, CardTokens.hub_paper(s))
	box.add_child(paper)
	var service := _service_open
	var icon_name := service
	for entry in CardTokens.HUB_SERVICES:
		if str(entry["id"]) == service:
			icon_name = str(entry["icon"])
	var icon := CardTokens.art_rect(CardTokens.HUB_ICON_PREFIX + icon_name)
	var icon_size := CardTokens.HUB_MENU_ENTRY.y * 1.6 * s
	icon.size = Vector2(icon_size, icon_size)
	icon.position = Vector2((paper.size.x - icon_size) * 0.5, CardTokens.HUB_PANEL_MARGIN * s * 0.5)
	paper.add_child(icon)
	var title_key := "svc_" + service if CardTokens.STRINGS.has("svc_" + service) else service
	var title := CardTokens.hub_label(CardTokens.t(title_key), CardTokens.FONT_HUB_PANEL_TITLE, CardTokens.HUB_INK, s)
	title.position = Vector2(0.0, icon.position.y + icon_size + 8.0 * s)
	title.size = Vector2(paper.size.x, CardTokens.FONT_HUB_PANEL_TITLE * 1.5 * s)
	paper.add_child(title)
	var body := CardTokens.hub_label(CardTokens.t("coming_soon") + "\n" + CardTokens.t("soon_body"), CardTokens.FONT_HUB_BODY, CardTokens.HUB_INK, s, 0, "medium")
	body.position = Vector2(0.0, title.position.y + title.size.y)
	body.size = Vector2(paper.size.x, CardTokens.FONT_HUB_BODY * 3.2 * s)
	paper.add_child(body)
	var close := Button.new()
	close.text = CardTokens.t("close")
	close.size = Vector2(CardTokens.HUB_BUTTON.x, CardTokens.tap(CardTokens.HUB_BUTTON.y, _phone)) * s
	close.position = Vector2((paper.size.x - close.size.x) * 0.5, paper.size.y - close.size.y - CardTokens.HUB_PANEL_MARGIN * s * 0.5)
	CardTokens.hub_button(close, s)
	CardTokens.hub_text(close, CardTokens.FONT_CHAR_BUTTON, CardTokens.HUB_INK, s)
	close.pressed.connect(_close_service)
	paper.add_child(close)
	close.grab_focus.call_deferred()

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
	var card: HubCard = _cards.get(class_id)
	if card != null and not reduced_motion:
		var tween := create_tween()
		tween.tween_property(card, "pop", CardTokens.SELECT_SCALE, CardTokens.SELECT_SECONDS * 0.5)
		tween.tween_property(card, "pop", CardTokens.SELECT_SETTLE, CardTokens.SELECT_SECONDS * 0.5)
		card.set_selected(true)
		await tween.finished
		card.set_selected(false)
		card.pop = 1.0
	open_character(class_id)


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
		var from_card: Control = _cards.get(id)
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
	_update_fight_progress()
	if _mode == "deck":
		for card in _cards.values():
			card.animate(delta, not reduced_motion)
	elif _mode == "editor" and _editor_card != null:
		_editor_card.animate(_time, delta, not reduced_motion)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _service_layer.visible:
		_close_service()
	elif _mode == "character":
		return  # the character screen handles its own Back
	elif _picker_layer.visible:
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
	service_pressed.connect(open_service)
	settings_pressed.connect(func() -> void: add_child(GraphicsPanel.new()))
	back_pressed.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	if GameState.ensure_profile():
		show_deck(GameState.profile.card_deck, ItemAssets.cosmetics())
		set_gold(GameState.profile.stash.gold)
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
		set_gold(GameState.profile.stash.gold)


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


## Web build: the battle packs (maps, monsters, skill VFX) download in the background while the player is here.
## FIGHT waits for them with a small readout on the button; when they are in (or on desktop) it starts at once.
func _update_fight_progress() -> void:
	if _fight_progress == null:
		return
	var ready := PackFetcher.battle_ready(get_tree())
	var text := "" if ready else CardTokens.t("fight_loading") % int(PackFetcher.battle_fraction(get_tree()) * 100.0)
	var node := get_tree().root.get_node_or_null(PackFetcher.BATTLE_NODE)
	if node != null and node.state == node.State.FAILED:
		text = CardTokens.t("fight_load_failed")
	if text != _fight_progress.text:
		_fight_progress.text = text
		_fight_progress.visible = text != ""
		_fit_fight_progress()
	if _fight_waiting and ready:
		_fight_waiting = false
		_start_fight()


func _fit_fight_progress() -> void:
	if _fight_progress != null and _fight_progress.visible:
		CardTokens.hub_fit(_fight_progress, _fight_progress.text, CardTokens.FONT_HUB_STAGE, _fight_progress.size.x, CardTokens.HUB_CREAM, _s, CardTokens.OUTLINE_HUB, "medium")


func _start_fight() -> void:
	if _busy or _mode == "summon":
		return
	if not PackFetcher.battle_ready(get_tree()):
		var node := get_tree().root.get_node_or_null(PackFetcher.BATTLE_NODE)
		if node != null and node.state == node.State.FAILED:
			node.retry()
		_fight_waiting = true
		toast(CardTokens.t("fight_wait"))
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
