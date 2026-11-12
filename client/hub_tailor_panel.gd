extends "res://client/hub_service_panel.gd"
## Tailor (docs/ui/hub_layout_spec.md §2 / §4 Outfit tab), full screen: a card picker, the card's big live
## character, and the look and fashion choices of that card.
## - Hair, Eyes, Skin, Makeup and the base Outfit are the card's own looks: `card_look {class, part, choice}` with
##   the options of logic/card_deck.gd (hairs of the class file, data/cosmetics eye / skin lists, makeup, outfit).
## - Fashion and Back are Mall pieces (logic/mall.gd, counted: one copy dresses one card): `mall_buy {part, choice}`
##   buys a copy with diamonds, `card_fashion {class, part, choice}` dresses / undresses this card. Refusals
##   (no_free_copy, cosmetic_not_owned, not_enough_diamonds, already_owned) show their reason in the status line.
## Hats are deferred (CLAUDE.md 2026-10-23) and not offered. The character redraws from the profile after each answer.

const CardDeck := preload("res://logic/card_deck.gd")
const CardPortrait := preload("res://client/card_portrait.gd")
const Mall := preload("res://logic/mall.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const HubLook := preload("res://client/hub_look.gd")

## Category tab -> the profile part it changes ("look" = card_look parts, "mall" = Mall fashion parts).
const CATEGORIES: Array[Dictionary] = [
	{"id": "hair", "kind": "look", "part": "hair"},
	{"id": "eyes", "kind": "look", "part": "eye_color", "parts": ["iris_style", "eye_color"]},  ## iris style (Studio) then colour
	{"id": "skin", "kind": "look", "part": "skin"},
	{"id": "makeup", "kind": "look", "part": "makeup"},
	{"id": "base_outfit", "kind": "look", "part": "outfit"},
	{"id": "fashion", "kind": "mall", "part": "fashion"},
	{"id": "back", "kind": "mall", "part": "fashion_back"},
]

var card := ""
var category := "hair"
var picked := ""  ## the Mall piece shown in the fashion strip
var _card_row: HBoxContainer
var _cards := {}
var _window: Panel
var _portrait: CardPortrait
var _cat_row: HBoxContainer
var _cats := {}
var _scroll: ScrollContainer
var _flow: HFlowContainer
var _strip: Panel
var _strip_name: Label
var _strip_line: Label
var _strip_buttons: HBoxContainer


func _init() -> void:
	service = "tailor"
	full_screen = true


func build() -> void:
	_card_row = HBoxContainer.new()
	body.add_child(_card_row)
	for id in CardDeck.classes():
		var b := plate(CardTokens.class_name_of(id), select_card.bind(id))
		_card_row.add_child(b)
		_cards[id] = b
	_window = Panel.new()
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_window)
	_portrait = CardPortrait.new()
	_portrait.framing = "hub"
	_window.add_child(_portrait)
	_cat_row = HBoxContainer.new()
	body.add_child(_cat_row)
	for entry in CATEGORIES:
		var id := str(entry["id"])
		var b := plate(CardTokens.t("tailor_" + id), select_category.bind(id))
		_cat_row.add_child(b)
		_cats[id] = b
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_flow)
	_strip = Panel.new()
	body.add_child(_strip)
	_strip_name = CardTokens.label("", CardTokens.FONT_CHAR_ITEM, CardTokens.HUB_INK, 1.0)
	_strip_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip.add_child(_strip_name)
	_strip_line = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_strip_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip.add_child(_strip_line)
	_strip_buttons = HBoxContainer.new()
	_strip.add_child(_strip_buttons)
	if card.is_empty():
		card = CardDeck.classes()[0] if not CardDeck.classes().is_empty() else ""
	visibility_changed.connect(func() -> void:
		if _portrait != null:
			_portrait.set_render_mode(CardPortrait.Mode.LIVE if is_visible_in_tree() else CardPortrait.Mode.ONCE))


## Opens on class card `class_id` ("" keeps the last one).
func open_for(class_id: String) -> void:
	if not class_id.is_empty():
		card = class_id
	picked = ""
	open()


func select_card(id: String) -> void:
	card = id
	picked = ""
	refresh()


func select_category(id: String) -> void:
	category = id
	picked = ""
	_scroll.scroll_vertical = 0
	refresh()


func first_focus() -> Control:
	return _cats.get(category, _close)


func currency_text(p) -> String:
	return "%s  %d   ·   %s  %d" % [CardTokens.t("gold"), p.stash.gold, CardTokens.t("diamonds"), p.diamonds]


func layout_body(area: Vector2) -> void:
	var gap := CardTokens.CHAR_GAP * s
	var row_h := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s
	var left_w := area.x * CardTokens.TAILOR_SPLIT
	_card_row.position = Vector2.ZERO
	_card_row.size = Vector2(left_w, row_h)
	CardTokens.gap(_card_row, 6.0, s)
	for id in _cards:
		(_cards[id] as Button).custom_minimum_size = Vector2(0.0, row_h)
		(_cards[id] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window.position = Vector2(0.0, row_h + gap * 0.5)
	_window.size = Vector2(left_w, area.y - _window.position.y)
	CardTokens.panel(_window, CardTokens.hub_box(CardTokens.palette(card)["shadow"], CardTokens.HUB_WINDOW_EDGE, CardTokens.CHAR_WINDOW_LINE, CardTokens.CHAR_WINDOW_RADIUS, s))
	_portrait.position = Vector2.ZERO
	_portrait.size = _window.size
	var rx := left_w + gap * 2.0
	var rw := area.x - rx
	_cat_row.position = Vector2(rx, 0.0)
	_cat_row.size = Vector2(rw, row_h)
	CardTokens.gap(_cat_row, 6.0, s)
	for id in _cats:
		(_cats[id] as Button).custom_minimum_size = Vector2(0.0, row_h)
		(_cats[id] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	var strip_h := CardTokens.FONT_CHAR_ITEM * 1.5 * s + CardTokens.FONT_CHAR_LINE * 1.5 * s + button_h + gap * 1.5
	_strip.position = Vector2(rx, area.y - strip_h)
	_strip.size = Vector2(rw, strip_h)
	CardTokens.panel(_strip, CardTokens.hub_box(CardTokens.HUB_DETAIL_BACK, CardTokens.HUB_DETAIL_EDGE, 3.0, 18.0, s))
	var pad := gap
	_strip_name.position = Vector2(pad, gap * 0.3)
	_strip_name.size = Vector2(rw - pad * 2.0, CardTokens.FONT_CHAR_ITEM * 1.5 * s)
	CardTokens.hub_text(_strip_name, CardTokens.FONT_CHAR_ITEM, CardTokens.HUB_INK, s)
	_strip_line.position = Vector2(pad, _strip_name.position.y + _strip_name.size.y)
	_strip_line.size = Vector2(rw - pad * 2.0, CardTokens.FONT_CHAR_LINE * 1.5 * s)
	CardTokens.hub_text(_strip_line, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
	_strip_buttons.position = Vector2(pad, strip_h - button_h - gap * 0.5)
	_strip_buttons.size = Vector2(rw - pad * 2.0, button_h)
	CardTokens.gap(_strip_buttons, 18.0, s)
	_scroll.position = Vector2(rx, row_h + gap * 0.75)
	_scroll.size = Vector2(rw, _strip.position.y - _scroll.position.y - gap * 0.75)
	CardTokens.flow_gap(_flow, CardTokens.CHAR_STORE_GAP, s)
	_flow.custom_minimum_size = Vector2(rw - 4.0 * s, 0.0)


func _category() -> Dictionary:
	for entry in CATEGORIES:
		if str(entry["id"]) == category:
			return entry
	return CATEGORIES[0]


func refresh() -> void:
	super()
	var p = _profile()
	if p == null or _flow == null or card.is_empty():
		return
	for id in _cards:
		style_plate(_cards[id], id == card)
	for id in _cats:
		style_plate(_cats[id], id == category)
	CardTokens.panel(_window, CardTokens.hub_box(CardTokens.palette(card)["shadow"], CardTokens.HUB_WINDOW_EDGE, CardTokens.CHAR_WINDOW_LINE, CardTokens.CHAR_WINDOW_RADIUS, s))
	if _portrait.class_id != card:
		_portrait.set_class(card)
	_portrait.set_look(CardDeck.look_of(p.card_deck, card))
	_portrait.set_render_mode(CardPortrait.Mode.LIVE)
	for child in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()
	var entry := _category()
	var part := str(entry["part"])
	if str(entry["kind"]) == "look":
		var parts: Array = entry.get("parts", [part])
		for each in parts:
			if parts.size() > 1:
				_section(CardTokens.t("tailor_part_" + str(each)))
			_fill_looks(p, str(each))
		if parts.size() > 1:
			var now := []
			for each in parts:
				now.append(_look_name(str(each), str(p.card_deck.get("cards", {}).get(card, {}).get(str(each), CardDeck.LATER_PARTS.get(str(each), "")))))
			_strip_line.text = CardTokens.t("tailor_look_line") % " + ".join(now)
	else:
		_fill_mall(p, part)


# ------------------------------------------------------------------ card looks (card_look)
func _fill_looks(p, part: String) -> void:
	var cosmetics = ItemAssets.cosmetics()
	var current := str(p.card_deck.get("cards", {}).get(card, {}).get(part, CardDeck.LATER_PARTS.get(part, "")))
	for id in CardDeck.options(card, part, cosmetics):
		var choice := str(id)
		var swatch := ""
		if part in ["eye_color", "skin", "iris_style"]:
			swatch = str(cosmetics.entry(part, choice).get("color", ""))
		_option(_look_name(part, choice), null, swatch, choice == current, _set_look.bind(part, choice))
	_strip_name.text = CardTokens.t("tailor_" + category)
	_strip_line.text = CardTokens.t("tailor_look_line") % _look_name(part, current)
	_clear_strip_buttons()


static func _look_name(part: String, choice: String) -> String:
	match part:
		"hair": return CardTokens.hair_name(choice)
		"outfit": return CardTokens.choice_name("outfit", choice)
		"makeup": return CardTokens.choice_name("makeup", choice)
		"iris_style": return CardTokens.choice_name("iris_style", choice)
	if choice.begins_with("#"):
		return CardTokens.t("custom")
	return CardTokens.choice_name(part, choice)


# ------------------------------------------------------------------ Mall fashion (mall_buy, card_fashion)
func _fill_mall(p, part: String) -> void:
	var cosmetics = ItemAssets.cosmetics()
	var wearing := str(Mall.card_look(p, card).get(part, "none"))
	for entry in cosmetics.choices.get(part, []):
		var id := str(entry["id"])
		if id == "none":
			continue
		var owned := Mall.owned_count(p, part, id)
		var mark := ""
		if owned > 0:
			mark = CardTokens.t("tailor_owned_mark") % owned
		_option(fashion_name(id, part) + ("\n" + mark if not mark.is_empty() else ""), _fashion_icon(part, id), "", id == wearing, select_piece.bind(id), id == picked)
	if picked.is_empty():
		picked = wearing if wearing != "none" else ""
	_fill_strip(p, part, wearing)


func select_piece(id: String) -> void:
	picked = id
	refresh()


func _fill_strip(p, part: String, wearing: String) -> void:
	_clear_strip_buttons()
	if picked.is_empty():
		_strip_name.text = CardTokens.t("tailor_" + category)
		_strip_line.text = CardTokens.t("tailor_pick_piece")
		if wearing == "none":
			return
	var id := picked if not picked.is_empty() else wearing
	var owned := Mall.owned_count(p, part, id)
	var free := Mall.free_copies(p, part, id)
	var on: Array = Mall.cards_wearing(p, part, id)
	var names: Array = on.map(func(c) -> String: return CardTokens.class_name_of(str(c)))
	var price := int(Mall.config().get("prices", {}).get(part, 0))
	_strip_name.text = fashion_name(id, part)
	var line := CardTokens.t("tailor_copies") % [owned, free]
	if not names.is_empty():
		line += "   ·   " + CardTokens.t("tailor_worn_by") % ", ".join(names)
	_strip_line.text = line
	var buy := _strip_button(CardTokens.t("tailor_buy") % price, _buy.bind(part, id))
	buy.disabled = owned >= Mall.max_copies(part)
	if buy.disabled:
		buy.tooltip_text = CardTokens.error_text("already_owned")
	if id == wearing:
		_strip_button(CardTokens.t("tailor_take_off"), _wear.bind(part, "none"))
	else:
		var wear := _strip_button(CardTokens.t("tailor_wear"), _wear.bind(part, id))
		wear.disabled = owned < 1
		if owned < 1:
			wear.tooltip_text = CardTokens.error_text("cosmetic_not_owned")
	HubItemDetails.fit_buttons(_strip_buttons, s)


## The fashion piece's display name: the English `name` of its data/cosmetics choice (Thai is kept in `name_th`,
## tools/items/cosmetic_names.py). Fashion and Back share some ids (bat_club ...), so the part picks the list.
static func fashion_name(id: String, part := "fashion") -> String:
	var choice: Dictionary = ItemAssets.cosmetics().entry(part, id)
	if not choice.is_empty() and not str(choice.get("name", "")).is_empty():
		return str(choice["name"])
	return id.replace("_", " ").capitalize()


static func _fashion_icon(part: String, id: String) -> Texture2D:
	var kind := "outfit" if part == "fashion" else "back"
	for file in ["res://art/fashion/icons/%s_%s.png" % [part, id], "res://art/fashion/studio_icons/%s-%s.svg" % [kind, id]]:
		if ResourceLoader.exists(file):
			return load(file) as Texture2D
	return null


# ------------------------------------------------------------------ widgets
## One choice: a parchment tile with an icon (fashion), a colour disc (eyes / skin) or just its name.
## The worn / chosen one gets a dark ring and a check mark (shape, not colour alone).
func _option(text: String, picture: Texture2D, swatch: String, chosen: bool, callback: Callable, highlighted: bool = false) -> Button:
	var b := Button.new()
	var big := picture != null
	var w := CardTokens.TAILOR_TILE.x if big else CardTokens.TAILOR_CHIP.x
	var h := CardTokens.TAILOR_TILE.y if big else CardTokens.TAILOR_CHIP.y
	b.custom_minimum_size = Vector2(w, CardTokens.tap(h, phone)) * s
	b.focus_mode = Control.FOCUS_ALL
	b.text = ("✓ " if chosen else "") + text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = true
	b.toggle_mode = false
	CardTokens.hub_button(b, s)
	CardTokens.hub_text(b, CardTokens.FONT_CHAR_SLOT if big else CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "display" if chosen else "medium")
	# long names: shrink, then two lines, then "…"; a second line of `text` ("Owned 1") stays its own line
	var name_part := text.get_slice("
", 0)
	var extra := text.substr(name_part.length() + 1) if text.contains("
") else ""
	var room := w * s - 12.0 * s - (CardTokens.TAILOR_SWATCH * s + CardTokens.CHAR_PAD * s if not swatch.is_empty() else 0.0)
	HubLook.fit(b, ("✓ " if chosen else "") + name_part, CardTokens.FONT_CHAR_SLOT if big else CardTokens.FONT_CHAR_LINE, room, CardTokens.HUB_INK, s,
		CardTokens.FIT_MAX_LINES, "display" if chosen else "medium", 0, extra)
	if big:
		b.icon = picture
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	if not swatch.is_empty() and Color.html_is_valid(swatch):
		var disc := Panel.new()
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := CardTokens.TAILOR_SWATCH * s
		disc.size = Vector2(d, d)
		disc.position = Vector2(CardTokens.CHAR_PAD * s * 0.5, (b.custom_minimum_size.y - d) * 0.5)
		CardTokens.panel(disc, CardTokens.hub_box(Color(swatch), CardTokens.HUB_LEATHER_EDGE, 2.0, d * 0.5 / s, s))
		b.add_child(disc)
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if chosen or highlighted:
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		CardTokens.panel(ring, CardTokens.ring(CardTokens.HUB_UNDERLINE if chosen else CardTokens.HUB_FIT_MARK, 4.0, 14.0, s))
		b.add_child(ring)
	b.pressed.connect(callback)
	_flow.add_child(b)
	return b


## A full-width caption in the choice list (a tab that shows more than one part, e.g. Eyes: iris style + colour).
func _section(text: String) -> void:
	var caption := CardTokens.label(text, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "display")
	CardTokens.hub_text(caption, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "display")
	caption.custom_minimum_size = Vector2(_flow.custom_minimum_size.x, CardTokens.FONT_CHAR_LINE * 1.6 * s)
	_flow.add_child(caption)


func _clear_strip_buttons() -> void:
	for child in _strip_buttons.get_children():
		_strip_buttons.remove_child(child)
		child.queue_free()


func _strip_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, _strip_buttons.size.y)
	b.clip_text = true
	CardTokens.hub_plate_button(b, s)
	b.pressed.connect(callback)
	_strip_buttons.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	var pad := event as InputEventJoypadButton
	var step := 0
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_Q, KEY_E]:
		step = -1 if key.keycode == KEY_Q else 1
	elif pad != null and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		step = -1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
	if step != 0:
		var ids := CardDeck.classes()
		select_card(ids[posmod(ids.find(card) + step, ids.size())])
		get_viewport().set_input_as_handled()
		return
	super(event)


# ------------------------------------------------------------------ commands (rules in logic/commands.gd)
func _set_look(part: String, choice: String) -> void:
	var result := await run({"type": "card_look", "class": card, "part": part, "choice": choice})
	if result.get("ok", false):
		say(CardTokens.t("tailor_changed") % _look_name(part, choice))
		if not reduced_motion:
			_portrait.pulse()


func _buy(part: String, id: String) -> void:
	var result := await run({"type": "mall_buy", "part": part, "choice": id})
	if result.get("ok", false):
		say(CardTokens.t("tailor_bought") % [fashion_name(id, part), int(result.get("owned", 1))])


func _wear(part: String, id: String) -> void:
	var old := str(Mall.card_look(_profile(), card).get(part, "none"))
	var result := await run({"type": "card_fashion", "class": card, "part": part, "choice": id})
	if result.get("ok", false):
		say(CardTokens.t("tailor_took_off") % fashion_name(old, part) if id == "none" else CardTokens.t("tailor_wearing") % [CardTokens.class_name_of(card), fashion_name(id, part)])
