extends Control
## The card character screen (docs/ui/hub_layout_spec.md §4, mock art_source/ui/class_cards/v10/hub/_mock_character_1080.png):
## opened from a class card on the hub. Full screen over the dimmed ruins: top bar (Back, card name, card switcher, gold),
## the leather panel with the Equipment / Outfit / Skills bookmarks.
## Equipment tab: the 15-slot paper-doll around the live full-body character (the off-hand slot is open only for the
## classes data/items/rules.json lists, else drawn locked), the card's stats on a strip under the character, the pinned
## item details with Equip / Unequip / Refine / Repair, and the shared Storage grid with filters.
## Touch first: tap = select + details, double-tap / right-click = wear or take off; every action is also a button
## (>= 96 px on phones), nothing needs hover or drag. Q / E (LB / RB) or the switcher change the card, Esc / B goes back.
## Display only: the screen reads GameState.profile (profile.loadout_of(card), the shared stash) and asks for changes
## with `send` (the hub's command sender: equip / unequip / refine / repair in logic/commands.gd), then redraws from
## the profile. Refused commands show a short line (CardTokens.error_text).
## Every colour, size and word comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const CardPortrait := preload("res://client/card_portrait.gd")
const CardSceneLayers := preload("res://client/card_scene_layers.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemIcon := preload("res://client/item_icon.gd")
const ItemText := preload("res://client/item_text.gd")
const Stats := preload("res://logic/stats.gd")
const Refine := preload("res://logic/refine.gd")
const Repair := preload("res://logic/repair.gd")
const Camp := preload("res://logic/camp.gd")
const SlotCell := preload("res://client/hub_item_cell.gd")
const HubItemDetails := preload("res://client/hub_item_details.gd")
const SkillTreeTab := preload("res://client/skill_tree_tab.gd")  ## the Skills tab (design/gdd/skill-tree.md 9.1)

signal closed()
signal settings_pressed()
signal account_pressed()
signal outfit_requested(class_id: String)  ## the Outfit tab: the hub opens its Tailor for this card
signal blacksmith_requested(item_id: String)  ## the details' Blacksmith button: the hub opens its Blacksmith panel on this piece
signal changed()  ## the profile changed (the hub refreshes gold / cards)

## (request: Dictionary) -> Dictionary, may be a coroutine (the hub's _send). Unset: commands go nowhere.
var send: Callable
## (text: String) -> void: a short status line (the hub's toast).
var notify: Callable
var reduced_motion := false

var card := ""
var _ids: Array = []
var _deck := {}
var _tab := "equipment"
var _filter := "all"
var _sel_slot := ""  ## "slot:index" of the selected paper-doll slot ("" none)
var _sel_item := ""  ## id of the selected stash piece ("" none)
var _busy := false
var _s := 1.0
var _phone := false
var _swipe_from := -1.0

var _shade: Panel
var _back: Button
var _title: Label
var _prev: Button
var _next: Button
var _count: Label
var _gold_pill: Panel
var _gold_icon: TextureRect
var _gold_label: Label
var _settings: Button
var _account: Button
var _panel: Control
var _panel_art: TextureRect
var _tabs := {}  ## tab id -> Button
var _tab_tints := {}  ## tab id -> Panel
var _underline: Panel
var _equip_page: Control
var _other_page: Control
var _other_text: Label
var _other_button: Button
var _window: Panel
var _scene_back: CardSceneLayers  ## the card's painted far + mid + contact shadow behind the character (static here)
var _scene_front: CardSceneLayers  ## its near layer over the feet
var _scene_masks: Array[Panel] = []  ## rounded window shapes (inside the window line) clipping the two scene parts
var _portrait: Control
var _strip: Panel
var _stat_keys: Array = []
var _stat_values: Array = []
var _slots := {}  ## "slot:index" -> SlotCell
var _divider: Panel
var _detail: HubItemDetails
var _store_title: Label
var _filters: HBoxContainer
var _filter_buttons := {}
var _store_scroll: ScrollContainer
var _store_grid: GridContainer
var _store_cells: Array = []
var _hint: Label
var _skills: SkillTreeTab


# ================================================================== build
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = Panel.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardTokens.panel(_shade, CardTokens.hub_shade(CardTokens.HUB_CHAR_DIM))
	add_child(_shade)
	_build_top()
	_build_panel()
	_hint = CardTokens.hub_label(CardTokens.t("char_hint_touch"), CardTokens.FONT_HUB_HINT, CardTokens.HUB_MUTED, 1.0, CardTokens.OUTLINE_HUB, "medium")
	add_child(_hint)
	resized.connect(_layout)
	visibility_changed.connect(func() -> void:
		if _portrait != null:
			_portrait.set_render_mode(CardPortrait.Mode.LIVE if is_visible_in_tree() else CardPortrait.Mode.ONCE))
	_layout()


func _build_top() -> void:
	_back = _round_button("back", func() -> void: close())
	_title = CardTokens.label("", CardTokens.FONT_CHAR_TITLE, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
	add_child(_title)
	_prev = Button.new()
	_prev.focus_mode = Control.FOCUS_ALL
	_prev.pressed.connect(func() -> void: switch_card(-1))
	add_child(_prev)
	_count = CardTokens.hub_label("", CardTokens.FONT_CHAR_SWITCH, CardTokens.HUB_MUTED, 1.0, CardTokens.OUTLINE_HUB, "medium")
	add_child(_count)
	_next = Button.new()
	_next.focus_mode = Control.FOCUS_ALL
	_next.pressed.connect(func() -> void: switch_card(1))
	add_child(_next)
	_gold_pill = Panel.new()
	_gold_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gold_pill)
	_gold_icon = CardTokens.art_rect(CardTokens.HUB_SYS_PREFIX + "gold")
	add_child(_gold_icon)
	_gold_label = CardTokens.hub_label("0", CardTokens.FONT_HUB_GOLD, CardTokens.HUB_CREAM, 1.0, 0, "medium")
	_gold_pill.add_child(_gold_label)
	_settings = _round_button("settings", func() -> void: settings_pressed.emit())
	_account = _round_button("account", func() -> void: account_pressed.emit())


func _round_button(art: String, callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = CardTokens.t(art)
	var picture := CardTokens.art_rect(CardTokens.HUB_SYS_PREFIX + art)
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(picture)
	b.pressed.connect(callback)
	b.button_down.connect(func() -> void: picture.modulate = CardTokens.HUB_PRESSED)
	b.button_up.connect(func() -> void: picture.modulate = CardTokens.HUB_WHITE)
	add_child(b)
	return b


func _build_panel() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	_panel_art = CardTokens.art_rect(CardTokens.HUB_PANEL)
	_panel.add_child(_panel_art)
	for tab in ["equipment", "outfit", "skills"]:
		var tint := Panel.new()
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(tint)
		_tab_tints[tab] = tint
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.text = CardTokens.t("tab_" + tab)
		b.pressed.connect(select_tab.bind(tab))
		_panel.add_child(b)
		_tabs[tab] = b
	_underline = Panel.new()
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_underline)
	# Equipment page
	_equip_page = Control.new()
	_equip_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_equip_page)
	_window = Panel.new()
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.clip_contents = true
	_window.gui_input.connect(_on_window_input)
	_equip_page.add_child(_window)
	_scene_back = CardSceneLayers.new()
	_window.add_child(_scene_mask(_scene_back))
	_portrait = CardPortrait.new()
	_portrait.framing = "stage"
	_window.add_child(_portrait)
	_scene_front = CardSceneLayers.new()
	_window.add_child(_scene_mask(_scene_front))
	_strip = Panel.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_strip)
	for stat in CardTokens.CHAR_STATS:
		var k := CardTokens.hub_label(CardTokens.t("stat_" + stat), CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_STAT_KEY, 1.0, 0, "medium")
		var v := CardTokens.hub_label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_CREAM, 1.0, 0, "medium")
		_strip.add_child(k)
		_strip.add_child(v)
		_stat_keys.append(k)
		_stat_values.append(v)
	for key in CardTokens.CHAR_SLOT_PLACES:
		var cell := SlotCell.new()
		cell.key = key
		cell.slot_id = key.split(":")[0]
		cell.index = int(key.split(":")[1])
		cell.setup()
		cell.pressed.connect(_on_slot_tapped.bind(key))
		cell.activated.connect(_on_slot_activated.bind(key))
		_equip_page.add_child(cell)
		_slots[key] = cell
	_divider = Panel.new()
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_page.add_child(_divider)
	_build_detail()
	_store_title = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_equip_page.add_child(_store_title)
	_filters = HBoxContainer.new()
	_filters.alignment = BoxContainer.ALIGNMENT_END
	_equip_page.add_child(_filters)
	for entry in CardTokens.CHAR_FILTERS:
		var id := str(entry["id"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.text = CardTokens.t("filter_" + id)
		b.pressed.connect(_set_filter.bind(id))
		_filters.add_child(b)
		_filter_buttons[id] = b
	_store_scroll = ScrollContainer.new()
	_store_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_store_scroll.follow_focus = true
	_equip_page.add_child(_store_scroll)
	_store_grid = GridContainer.new()
	_store_scroll.add_child(_store_grid)
	# Outfit / Skills placeholder page
	_other_page = Control.new()
	_other_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_other_page.visible = false
	_panel.add_child(_other_page)
	_other_text = CardTokens.hub_label("", CardTokens.FONT_HUB_BODY, CardTokens.HUB_INK, 1.0, 0, "medium")
	_other_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_other_page.add_child(_other_text)
	_other_button = Button.new()
	_other_button.focus_mode = Control.FOCUS_ALL
	_other_button.text = CardTokens.t("open_editor")
	_other_button.pressed.connect(func() -> void: outfit_requested.emit(card))
	_other_page.add_child(_other_button)
	# Skills page: the card's skill tree
	_skills = SkillTreeTab.new()
	_skills.visible = false
	_skills.send = _send_tree
	_skills.notify = _say
	_skills.changed.connect(func() -> void:
		changed.emit()
		_refresh_skills())
	_panel.add_child(_skills)


func _build_detail() -> void:
	_detail = HubItemDetails.new()
	_equip_page.add_child(_detail)


# ================================================================== API
## Shows card `class_id`; `ids` are the deck's class ids in card order (for the switcher), `deck` the card deck.
func open(class_id: String, ids: Array, deck: Dictionary) -> void:
	_ids = ids.duplicate()
	_deck = deck
	_tab = "equipment"
	visible = true
	_show_card(class_id)
	if not reduced_motion:
		_panel.modulate.a = 0.0
		create_tween().tween_property(_panel, "modulate:a", 1.0, CardTokens.FADE_SECONDS)
	(_slots.get("weapon:0") as Control).grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func set_deck(deck: Dictionary) -> void:
	_deck = deck
	if visible and not card.is_empty():
		_portrait.set_look(CardDeck.look_of(_deck, card))


## -1 previous card, +1 next card (wraps).
func switch_card(step: int) -> void:
	if _ids.is_empty():
		return
	var at := _ids.find(card)
	_show_card(str(_ids[posmod(at + step, _ids.size())]))


func select_tab(tab: String) -> void:
	if tab == "outfit":  # the Outfit tab is the Tailor for this card (hub_tailor_panel.gd, over this screen)
		outfit_requested.emit(card)
		return
	_tab = tab
	_refresh_tabs()


## Selects a paper-doll slot ("weapon:0") or a stash piece by id (the shot scripts use these too).
func select_slot(key: String) -> void:
	_sel_slot = key
	_sel_item = ""
	refresh()


func select_stash_item(id: String) -> void:
	_sel_item = id
	refresh()


func _show_card(class_id: String) -> void:
	card = class_id
	_sel_slot = "weapon:0"
	_sel_item = ""
	_portrait.set_class(class_id)
	_portrait.set_look(CardDeck.look_of(_deck, class_id))
	_scene_back.setup(class_id, CardSceneLayers.Part.BACK)
	_scene_front.setup(class_id, CardSceneLayers.Part.FRONT)
	_scene_back.set_feet(CardTokens.PORTRAIT_STAGE_BOTTOM)
	_portrait.set_idle_variants(not reduced_motion)  # idle variants (Boss 2026-11-12), off for reduced motion
	_portrait.set_render_mode(CardPortrait.Mode.LIVE)
	_layout()


# ================================================================== layout
## A rounded window-shaped mask (sized in _layout_equipment) that clips `layer` inside the window line.
func _scene_mask(layer: Control) -> Panel:
	var mask := Panel.new()
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.add_child(layer)
	_scene_masks.append(mask)
	return mask


func _layout() -> void:
	if _panel == null:
		return
	_s = CardTokens.scale_for(size)
	_phone = CardTokens.is_phone(size)
	var s := _s
	var side := CardTokens.hub_safe_x(size, s)
	# top bar
	var sys := CardTokens.tap(CardTokens.HUB_SYS_SIZE, _phone) * s
	_back.position = Vector2(side, CardTokens.HUB_SYS_Y * s)
	_back.size = Vector2(sys, sys)
	CardTokens.bare_button(_back, s, CardTokens.HUB_SYS_SIZE * 0.5)
	var title_h := CardTokens.FONT_CHAR_TITLE * 1.5 * s
	_title.position = Vector2(side + sys + CardTokens.HUB_SYS_GAP * s, CardTokens.HUB_TITLE_Y * s - title_h * 0.5)
	_title.size = Vector2(size.x * 0.45, title_h)
	CardTokens.style_text(_title, CardTokens.FONT_CHAR_TITLE, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
	var x := size.x - side
	for b in [_account, _settings]:
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
	# panel: fixed reference size, centred, never wider than the safe width
	var pw := minf(CardTokens.CHAR_PANEL_W * s, size.x - side * 2.0)
	var ph := minf(CardTokens.CHAR_PANEL_H * s, size.y - CardTokens.CHAR_PANEL_Y * s - CardTokens.HUB_SAFE.y * s * 0.25)
	_panel.position = Vector2((size.x - pw) * 0.5, CardTokens.CHAR_PANEL_Y * s)
	_panel.size = Vector2(pw, ph)
	_panel_art.size = _panel.size
	# card switcher under the title: < prev | Card n of N | next >
	var sw_h := CardTokens.tap(CardTokens.CHAR_SWITCH_H, _phone) * s
	var sw_w := CardTokens.CHAR_SWITCH_W * s
	var sw_y := CardTokens.CHAR_SWITCH_Y * s - sw_h * 0.5
	var sw_x := _title.position.x
	if _panel.position.y - sw_h < _title.position.y + title_h * 0.8:  # no room under the title: the switcher goes right of it
		var title_w := CardTokens.display_font().get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(round(CardTokens.FONT_CHAR_TITLE * s)), CardTokens.FONT_MIN)).x
		sw_x = _title.position.x + title_w + CardTokens.CHAR_GAP * s * 2.0
		sw_y = _title.position.y + (title_h - sw_h) * 0.5
	_prev.position = Vector2(sw_x, sw_y)
	_prev.size = Vector2(sw_w, sw_h)
	_count.position = Vector2(sw_x + sw_w, sw_y)
	_count.size = Vector2(sw_w * 0.8, sw_h)
	_next.position = Vector2(sw_x + sw_w * 1.8, sw_y)
	_next.size = Vector2(sw_w, sw_h)
	for b in [_prev, _next]:
		CardTokens.hub_button(b, s, true)
		CardTokens.hub_text(b, CardTokens.FONT_CHAR_SWITCH, CardTokens.HUB_MUTED, s, CardTokens.OUTLINE_HUB, "medium")
	_prev.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_next.alignment = HORIZONTAL_ALIGNMENT_LEFT
	CardTokens.hub_text(_count, CardTokens.FONT_CHAR_SWITCH, CardTokens.HUB_MUTED, s, CardTokens.OUTLINE_HUB, "medium")
	# tabs on the bookmark plates of the art
	var sx := pw / CardTokens.CHAR_PANEL_ART.x
	var sy := ph / CardTokens.CHAR_PANEL_ART.y
	var i := 0
	for tab in ["equipment", "outfit", "skills"]:
		var plate: Vector3 = CardTokens.CHAR_TABS[i]
		var b: Button = _tabs[tab]
		b.position = Vector2(plate.x * sx, 0.0)
		b.size = Vector2((plate.y - plate.x) * sx, maxf(CardTokens.CHAR_TAB_H * sy, CardTokens.tap(0.0, _phone) * s))
		var tint: Panel = _tab_tints[tab]
		tint.position = Vector2(plate.x * sx + 14.0 * sx, 26.0 * sy)
		tint.size = Vector2((plate.y - plate.x - 28.0) * sx, 70.0 * sy)
		i += 1
	_hint.position = Vector2(side, CardTokens.CHAR_HINT_Y * s - CardTokens.FONT_HUB_HINT * 0.8 * s)
	_hint.size = Vector2(size.x - side * 2.0, CardTokens.FONT_HUB_HINT * 1.6 * s)
	_hint.position.y = minf(_hint.position.y, size.y - _hint.size.y)
	CardTokens.hub_fit(_hint, _hint.text, CardTokens.FONT_HUB_HINT, size.x - side * 2.0, CardTokens.HUB_MUTED, s, CardTokens.OUTLINE_HUB, "medium")
	_layout_equipment(pw, ph)
	_layout_other(pw, ph)
	_layout_skills(pw, ph)
	_refresh_tabs()


func _layout_equipment(pw: float, ph: float) -> void:
	var s := _s
	var inner := Rect2(CardTokens.CHAR_CONTENT.position.x * s, CardTokens.CHAR_CONTENT.position.y * s, pw - (CardTokens.CHAR_CONTENT.position.x + CardTokens.CHAR_CONTENT.size.x) * s, ph - (CardTokens.CHAR_CONTENT.position.y + CardTokens.CHAR_CONTENT.size.y) * s)
	_equip_page.position = Vector2.ZERO
	_equip_page.size = Vector2(pw, ph)
	# the paper-doll: 5 x 6 cells of CHAR_SLOT, fitted to the inner height
	var gap := CardTokens.CHAR_SLOT_GAP * s
	var cell := minf(CardTokens.CHAR_SLOT * s, (inner.size.y - CardTokens.CHAR_DOLL_OFFSET.y * s - gap * 5.0) / 6.0)
	var origin := inner.position + CardTokens.CHAR_DOLL_OFFSET * s
	for key in _slots:
		var place: Array = CardTokens.CHAR_SLOT_PLACES[key]
		var c: SlotCell = _slots[key]
		c.s = s
		c.position = origin + Vector2(float(place[0]), float(place[1])) * (cell + gap)
		c.size = Vector2(cell, cell)
	_window.position = origin + Vector2(cell + gap, cell + gap)
	_window.size = Vector2(cell * 3.0 + gap * 2.0, cell * 4.0 + gap * 3.0)
	CardTokens.panel(_window, CardTokens.hub_box(CardTokens.palette(card)["shadow"], CardTokens.HUB_WINDOW_EDGE, CardTokens.CHAR_WINDOW_LINE, CardTokens.CHAR_WINDOW_RADIUS, s))
	_portrait.position = Vector2.ZERO
	_portrait.size = _window.size
	var line := CardTokens.CHAR_WINDOW_LINE * s
	for mask in _scene_masks:
		mask.position = Vector2(line, line)
		mask.size = _window.size - Vector2(line, line) * 2.0
		CardTokens.panel(mask, CardTokens.hub_box(CardTokens.HUB_WINDOW_BOTTOM, CardTokens.HUB_WINDOW_BOTTOM, 0.0, CardTokens.CHAR_WINDOW_RADIUS - CardTokens.CHAR_WINDOW_LINE, s))
	var strip_h := CardTokens.CHAR_STAT_STRIP_H * s
	_strip.position = Vector2(6.0 * s, _window.size.y - strip_h - 6.0 * s)
	_strip.size = Vector2(_window.size.x - 12.0 * s, strip_h)
	CardTokens.panel(_strip, CardTokens.hub_strip(s))
	var col := _strip.size.x / float(_stat_keys.size())
	for n in _stat_keys.size():
		var k: Label = _stat_keys[n]
		var v: Label = _stat_values[n]
		k.position = Vector2(col * n, 0.0)
		k.size = Vector2(col, strip_h * 0.45)
		v.position = Vector2(col * n, strip_h * 0.38)
		v.size = Vector2(col, strip_h * 0.6)
		CardTokens.hub_text(k, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_STAT_KEY, s, 0, "medium")
		CardTokens.hub_text(v, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_CREAM, s, 0, "medium")
	# right column: details, then Storage
	var rx := origin.x + cell * 5.0 + gap * 4.0 + CardTokens.CHAR_RIGHT_GAP * s
	var rw := inner.end.x - rx
	_divider.position = Vector2(rx - CardTokens.CHAR_RIGHT_GAP * s * 0.55, inner.position.y)
	_divider.size = Vector2(CardTokens.CHAR_DIVIDER * s, inner.size.y)
	CardTokens.panel(_divider, CardTokens.hub_line(CardTokens.HUB_DIVIDER))
	var button_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, _phone) * s
	var detail_h := CardTokens.CHAR_DETAIL_BOX_H * s + (button_h - CardTokens.CHAR_ACTION_H * s)
	_detail.position = Vector2(rx, inner.position.y)
	_detail.size = Vector2(rw, detail_h)
	_detail.layout_box(rw, detail_h, button_h, s)
	var filter_h := CardTokens.tap(CardTokens.CHAR_FILTER_H, _phone) * s
	var head_y := _detail.position.y + detail_h + CardTokens.CHAR_GAP * s * 0.6
	_store_title.position = Vector2(rx, head_y)
	_store_title.size = Vector2(rw * 0.5, filter_h)
	CardTokens.hub_text(_store_title, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
	_filters.position = Vector2(rx + rw * 0.45, head_y)
	_filters.size = Vector2(rw * 0.55, filter_h)
	CardTokens.gap(_filters, 4.0, s)
	for id in _filter_buttons:
		var b: Button = _filter_buttons[id]
		b.custom_minimum_size = Vector2(CardTokens.tap(CardTokens.CHAR_FILTER_W, _phone) * s * (0.8 if _phone else 1.0), filter_h)
		CardTokens.hub_button(b, s, true)
	var store_cell := CardTokens.tap(CardTokens.CHAR_STORE_CELL, _phone) * s
	var store_gap := CardTokens.CHAR_STORE_GAP * s
	_store_scroll.position = Vector2(rx, head_y + filter_h + CardTokens.CHAR_GAP * s * 0.3)
	_store_scroll.size = Vector2(rw + store_gap, maxf(store_cell, inner.end.y - _store_scroll.position.y + CardTokens.CHAR_GAP * s))
	_store_grid.columns = maxi(1, int((rw + store_gap) / (store_cell + store_gap)))
	CardTokens.flow_gap(_store_grid, CardTokens.CHAR_STORE_GAP, s)
	refresh()


func _layout_other(pw: float, ph: float) -> void:
	var s := _s
	_other_page.position = Vector2.ZERO
	_other_page.size = Vector2(pw, ph)
	_other_text.position = Vector2(pw * 0.15, ph * 0.3)
	_other_text.size = Vector2(pw * 0.7, ph * 0.2)
	CardTokens.hub_text(_other_text, CardTokens.FONT_HUB_BODY, CardTokens.HUB_INK, s, 0, "medium")
	var bh := CardTokens.tap(CardTokens.CHAR_ACTION_H, _phone) * s
	_other_button.size = Vector2(420.0 * s, bh)
	_other_button.position = Vector2((pw - _other_button.size.x) * 0.5, ph * 0.55)
	CardTokens.hub_plate_button(_other_button, s)
	CardTokens.hub_text(_other_button, CardTokens.FONT_CHAR_BUTTON, CardTokens.HUB_INK, s)


func _layout_skills(pw: float, ph: float) -> void:
	var s := _s
	_skills.position = Vector2(CardTokens.CHAR_CONTENT.position.x * s, CardTokens.CHAR_CONTENT.position.y * s)
	_skills.size = Vector2(pw - (CardTokens.CHAR_CONTENT.position.x + CardTokens.CHAR_CONTENT.size.x) * s, ph - (CardTokens.CHAR_CONTENT.position.y + CardTokens.CHAR_CONTENT.size.y) * s)
	_skills.s = s
	_skills.phone = _phone
	_refresh_skills()


## The Skills tab's commands go through the hub's sender like the gear commands.
func _send_tree(request: Dictionary) -> Dictionary:
	if not send.is_valid():
		return {"ok": false, "error": "no_session"}
	return await send.call(request)


## Redraws the Skills tab from the profile (its card deck and gold).
func _refresh_skills() -> void:
	var p = _profile()
	if _skills == null or p == null or card.is_empty():
		return
	_skills.show_card(card, p.card_deck, p.stash.gold)
	if _gold_label != null:
		_gold_label.text = str(p.stash.gold)


func _refresh_tabs() -> void:
	var s := _s
	var sy := _panel.size.y / CardTokens.CHAR_PANEL_ART.y
	for tab in _tabs:
		var b: Button = _tabs[tab]
		var on: bool = tab == _tab
		CardTokens.hub_button(b, s, true)
		CardTokens.hub_fit(b, b.text, CardTokens.FONT_CHAR_TAB, b.size.x * 0.8, CardTokens.HUB_INK if on else CardTokens.HUB_TAB_IDLE, s)
		var tint: Panel = _tab_tints[tab]
		CardTokens.panel(tint, CardTokens.hub_box(CardTokens.HUB_TAB_LIT if on else CardTokens.HUB_TAB_DIM, CardTokens.HUB_CLEAR, 0.0, 10.0, s))
		if on:
			var w := b.size.x * CardTokens.CHAR_UNDERLINE.x
			_underline.position = Vector2(b.position.x + (b.size.x - w) * 0.5, CardTokens.CHAR_UNDERLINE.y * sy)
			_underline.size = Vector2(w, 4.0 * s)
	CardTokens.panel(_underline, CardTokens.hub_line(CardTokens.HUB_UNDERLINE))
	_equip_page.visible = _tab == "equipment"
	_other_page.visible = _tab == "outfit"
	_skills.visible = _tab == "skills"
	var hint := CardTokens.tt("tree_hint") if _tab == "skills" else CardTokens.t("char_hint_touch")
	if _hint.text != hint:
		_hint.text = hint
		CardTokens.hub_fit(_hint, hint, CardTokens.FONT_HUB_HINT, _hint.size.x, CardTokens.HUB_MUTED, s, CardTokens.OUTLINE_HUB, "medium")
	_other_button.visible = _tab == "outfit"
	_other_text.text = CardTokens.t("outfit_body") if _tab == "outfit" else CardTokens.t("skills_soon")


# ================================================================== data -> picture
func _profile():
	return GameState.profile if GameState.ensure_profile() else null


## Redraws everything from the profile (call after every command).
func refresh() -> void:
	var p = _profile()
	if p == null or card.is_empty() or _panel == null:
		return
	var rules = GameState.item_rules
	if _title.text != CardTokens.class_name_of(card):
		_title.text = CardTokens.class_name_of(card)
		_layout.call_deferred()
	var at := maxi(_ids.find(card), 0)
	var count := maxi(_ids.size(), 1)
	_prev.text = CardTokens.t("prev_card") % CardTokens.class_name_of(str(_ids[posmod(at - 1, count)])) if not _ids.is_empty() else ""
	_next.text = CardTokens.t("next_card") % CardTokens.class_name_of(str(_ids[posmod(at + 1, count)])) if not _ids.is_empty() else ""
	_count.text = CardTokens.t("card_of") % [at + 1, count]
	_gold_label.text = str(p.stash.gold)
	var worn = p.loadout_of(card)
	if worn == null:
		return
	# stats
	var totals: Dictionary = Stats.totals(rules, worn.items())
	for n in CardTokens.CHAR_STATS.size():
		var stat: String = CardTokens.CHAR_STATS[n]
		var value := float(totals.get(stat, 0.0))
		(_stat_values[n] as Label).text = ("%d%%" % int(round(value))) if stat == "CRIRATE" else str(int(round(value)))
	# the selected piece
	var selected_item = _find_stash(p, _sel_item)
	if selected_item == null:
		_sel_item = ""
	var sel_slot_id := _sel_slot.split(":")[0] if not _sel_slot.is_empty() else ""
	# paper-doll
	for key in _slots:
		var c: SlotCell = _slots[key]
		var open: bool = rules.slot_open_for(c.slot_id, card) and not rules.slot(c.slot_id).is_empty()
		c.locked = not open
		c.show_item(worn.item_at(c.slot_id, c.index) if open else null, rules, CardTokens.t("slot_locked") if not open else CardTokens.slot_name(c.slot_id))
		c.selected = key == _sel_slot and _sel_item.is_empty()
		c.fits = selected_item != null and selected_item.slot == c.slot_id and open
		c.queue_redraw()
	# storage
	var filter_slots: Array = []
	for entry in CardTokens.CHAR_FILTERS:
		if str(entry["id"]) == _filter:
			filter_slots = entry["slots"]
	var shown: Array = []
	for item in p.stash.items:
		if filter_slots.is_empty() or filter_slots.has(item.slot):
			shown.append(item)
	var columns := _store_grid.columns
	var cells := shown.size()
	if _filter == "all":
		cells = maxi(cells, p.stash.capacity)
	cells = maxi(columns * 3, int(ceil(float(cells) / float(columns))) * columns)
	var store_size := CardTokens.tap(CardTokens.CHAR_STORE_CELL, _phone) * _s
	while _store_cells.size() < cells:
		var c := SlotCell.new()
		c.setup()
		c.pressed.connect(_on_store_tapped.bind(c))
		c.activated.connect(_on_store_activated.bind(c))
		_store_grid.add_child(c)
		_store_cells.append(c)
	var fits_count := 0
	for n in _store_cells.size():
		var c: SlotCell = _store_cells[n]
		c.visible = n < cells
		c.s = _s
		c.custom_minimum_size = Vector2(store_size, store_size)
		var item = shown[n] if n < shown.size() else null
		c.slot_id = item.slot if item != null else ""
		c.show_item(item, rules, "")
		c.selected = item != null and item.id == _sel_item
		c.fits = item != null and _sel_item.is_empty() and item.slot == sel_slot_id and _can_wear(item, rules)
		if c.fits:
			fits_count += 1
		c.focus_mode = Control.FOCUS_ALL if item != null else Control.FOCUS_NONE
		c.queue_redraw()
	_store_title.text = "%s   %d / %d" % [CardTokens.t("storage_title"), p.stash.items.size(), p.stash.capacity]
	for id in _filter_buttons:
		var b: Button = _filter_buttons[id]
		var on: bool = id == _filter
		CardTokens.hub_text(b, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK if on else CardTokens.HUB_TAB_IDLE, _s, 0, "display" if on else "medium")
		b.flat = true
		b.button_pressed = on
	_refresh_detail(p, rules, worn, selected_item, fits_count)


func _can_wear(item, rules) -> bool:
	return preload("res://logic/profile.gd").slot_problem(card, item, rules).is_empty()


func _find_stash(p, id: String):
	if id.is_empty():
		return null
	for item in p.stash.items:
		if item.id == id:
			return item
	return null


func _refresh_detail(p, rules, worn, stash_item, fits_count: int) -> void:
	var item = stash_item
	var from_stash: bool = stash_item != null
	var slot_id := _sel_slot.split(":")[0] if not _sel_slot.is_empty() else ""
	var slot_index := int(_sel_slot.split(":")[1]) if not _sel_slot.is_empty() else 0
	var slot_open: bool = slot_id.is_empty() or rules.slot_open_for(slot_id, card)
	if item == null and not slot_id.is_empty() and slot_open:
		item = worn.item_at(slot_id, slot_index)
	if item == null:
		var heading := CardTokens.slot_name(slot_id) if not slot_id.is_empty() else CardTokens.t("pick_piece")
		var caption := CardTokens.slot_name(slot_id) if slot_open else CardTokens.t("slot_locked")
		if not slot_open:
			var names: Array = []
			for id in rules.slot(slot_id).get("classes", []):
				names.append(CardTokens.class_name_of(str(id)))
			_detail.show_empty(heading, CardTokens.t("slot_locked"), CardTokens.t("slot_closed_line") % ", ".join(names), "", caption, true)
		elif slot_id.is_empty():
			_detail.show_empty(heading, "", "", "", caption)
		else:
			_detail.show_empty(heading, CardTokens.t("vs_empty"), CardTokens.t("fits_count") % fits_count if fits_count > 0 else CardTokens.t("fits_none"), "" if not p.stash.items.is_empty() else CardTokens.t("storage_empty"), caption)
		return
	_detail.show_item(item, rules)
	if from_stash:
		var index := int(_sel_slot.split(":")[1]) if _sel_slot.begins_with(item.slot + ":") else 0
		_detail.fill_compare(item, worn.item_at(item.slot, index), rules)
	# costs and actions
	var camp = GameState.camp_data
	var refine_offer: Dictionary = Refine.quote(item, rules, camp)
	var repair_cost: Dictionary = Repair.quote(item, camp, Camp.repair_discount(p, camp))
	var costs: Array[String] = []
	if refine_offer.get("ok", false):
		costs.append("%s: %s" % [CardTokens.t("refine"), HubItemDetails.cost_text(refine_offer["cost"], camp)])
	elif str(refine_offer.get("reason", "")) == "max_level":
		costs.append(CardTokens.t("refine_max"))
	costs.append("%s: %s" % [CardTokens.t("repair"), HubItemDetails.cost_text(repair_cost, camp)] if str(repair_cost["kind"]) != "none" else CardTokens.t("like_new"))
	_detail.cost.text = "  ·  ".join(costs)
	if from_stash:
		var problem: String = preload("res://logic/profile.gd").slot_problem(card, item, rules)
		var wear := _detail.add_action(CardTokens.t("equip"), _equip.bind(item.id, item.slot))
		wear.tooltip_text = CardTokens.error_text(problem) if not problem.is_empty() else ""
	else:
		_detail.add_action(CardTokens.t("unequip"), _unequip.bind(item.slot, slot_index))
	var refine_button := _detail.add_action(CardTokens.t("refine"), _refine.bind(item.id, item.refine_level))
	refine_button.disabled = not refine_offer.get("ok", false) and str(refine_offer.get("reason", "")) in ["invalid_item", "max_level"]
	var repair_button := _detail.add_action(CardTokens.t("repair"), _repair.bind(item.id))
	repair_button.disabled = str(repair_cost["kind"]) == "none"
	_detail.add_action(CardTokens.t("svc_blacksmith"), func() -> void: blacksmith_requested.emit(item.id))


# ================================================================== input
func _on_slot_tapped(key: String) -> void:
	_sel_slot = key
	_sel_item = ""
	refresh()


## Double-tap / right-click on a worn piece = take it off.
func _on_slot_activated(key: String) -> void:
	var c: SlotCell = _slots[key]
	_sel_slot = key
	_sel_item = ""
	if c.item != null:
		_unequip(c.slot_id, c.index)
	else:
		refresh()


func _on_store_tapped(c: SlotCell) -> void:
	if c.item == null:
		return
	_sel_item = c.item.id
	if not _sel_slot.begins_with(c.item.slot + ":"):
		_sel_slot = _first_free(c.item.slot)
	refresh()


## Double-tap / right-click on a storage piece = wear it.
func _on_store_activated(c: SlotCell) -> void:
	if c.item == null:
		return
	_sel_item = c.item.id
	if not _sel_slot.begins_with(c.item.slot + ":"):
		_sel_slot = _first_free(c.item.slot)
	_equip(c.item.id, c.item.slot)


## The paper-doll key a piece of `slot_id` goes to: the first empty position, else the first.
func _first_free(slot_id: String) -> String:
	var p = _profile()
	var worn = p.loadout_of(card) if p != null else null
	var count := int(GameState.item_rules.slot(slot_id).get("count", 1)) if GameState.item_rules != null else 1
	for n in count:
		if worn != null and worn.item_at(slot_id, n) == null:
			return "%s:%d" % [slot_id, n]
	return "%s:0" % slot_id


func _on_window_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_swipe_from = button.position.x
	elif _swipe_from >= 0.0:
		var dx := button.position.x - _swipe_from
		_swipe_from = -1.0
		if absf(dx) > _window.size.x * 0.25:
			switch_card(-1 if dx > 0.0 else 1)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_Q:
			switch_card(-1)
		elif key.keycode == KEY_E:
			switch_card(1)
		elif key.keycode >= KEY_1 and key.keycode <= KEY_3:
			select_tab(["equipment", "outfit", "skills"][key.keycode - KEY_1])
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed:
		if pad.button_index == JOY_BUTTON_LEFT_SHOULDER:
			switch_card(-1)
		elif pad.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			switch_card(1)
		else:
			return
		get_viewport().set_input_as_handled()


func _set_filter(id: String) -> void:
	_filter = id
	refresh()


# ================================================================== commands (rules in logic/commands.gd)
func _equip(item_id: String, slot_id: String) -> void:
	var index := int(_sel_slot.split(":")[1]) if _sel_slot.begins_with(slot_id + ":") else 0
	var request := {"type": "equip", "item": item_id, "source": "stash", "card": card}
	if index > 0:
		request["index"] = index
	var result := await _run(request)
	if result.get("ok", false):
		_sel_item = ""
		_sel_slot = "%s:%d" % [slot_id, index]
		_say(CardTokens.t("worn_ok"))
	refresh()


func _unequip(slot_id: String, index: int) -> void:
	var request := {"type": "unequip", "slot": slot_id, "destination": "stash", "card": card}
	if index > 0:
		request["index"] = index
	var result := await _run(request)
	if result.get("ok", false):
		_say(CardTokens.t("took_off_ok"))
	refresh()


func _refine(item_id: String, level: int) -> void:
	var result := await _run({"type": "refine", "item": item_id, "level": level})
	if result.get("ok", false):
		var info: Dictionary = result.get("result", {})
		_say((CardTokens.t("refined_ok") if info.get("success", true) else CardTokens.t("refine_failed")) % int(info.get("level", level + 1)))
	refresh()


func _repair(item_id: String) -> void:
	var result := await _run({"type": "repair", "item": item_id})
	if result.get("ok", false):
		_say(CardTokens.t("repaired_ok"))
	refresh()


## Sends one command; a refusal shows its reason. Returns the result.
func _run(request: Dictionary) -> Dictionary:
	if _busy or not send.is_valid():
		return {"ok": false}
	_busy = true
	var result: Dictionary = await send.call(request)
	_busy = false
	if not result.get("ok", false):
		_say(CardTokens.error_text(str(result.get("error", result.get("reason", "")))))
	else:
		changed.emit()
	return result


func _say(text: String) -> void:
	if notify.is_valid():
		notify.call(text)
