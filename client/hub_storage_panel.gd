extends "res://client/hub_service_panel.gd"
## Storage (docs/ui/hub_layout_spec.md §2): the shared stash grid (and the vault, the Storage NPC bank) with item
## details, Discard (asks first), "Wear on card..." (a picker of the class cards; refused cards say why) and
## Move to vault / Move to storage. Commands (logic/commands.gd): equip {item, source: stash, card},
## discard {item, source: stash}, storage_item {item, source: stash|vault}.
## A vault piece must come back to the stash before it can be worn or discarded (the rules refuse vault ids).

const CardDeck := preload("res://logic/card_deck.gd")
const Profile := preload("res://logic/profile.gd")

var tab := "stash"  ## stash | vault
var selected := ""
var _tabs := {}
var _tab_row: HBoxContainer
var _count: Label
var _grid: GridContainer
var _cells: Array = []
var _details: HubItemDetails
var _picker: Control  ## "wear on card" / "discard?" choices, over the details
var _picker_head: Label
var _picker_box: GridContainer


func _init() -> void:
	service = "storage"


func build() -> void:
	_tab_row = HBoxContainer.new()
	body.add_child(_tab_row)
	for id in ["stash", "vault"]:
		var b := plate(CardTokens.t("store_tab_" + id), select_tab.bind(id))
		_tab_row.add_child(b)
		_tabs[id] = b
	_count = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(_count)
	_grid = make_grid(body)
	_details = HubItemDetails.new()
	body.add_child(_details)
	_picker = Panel.new()
	_picker.visible = false
	body.add_child(_picker)
	_picker_head = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0)
	_picker_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_picker.add_child(_picker_head)
	_picker_box = GridContainer.new()
	_picker_box.columns = 2
	_picker.add_child(_picker_box)


func select_tab(id: String) -> void:
	tab = id
	selected = ""
	_picker.visible = false
	refresh()


func select_item(id: String) -> void:
	selected = id
	_picker.visible = false
	refresh()


func first_focus() -> Control:
	return _tabs.get(tab, _close)


func layout_body(area: Vector2) -> void:
	var gap := CardTokens.CHAR_GAP * s
	var row_h := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s
	var left_w := area.x * CardTokens.SVC_SPLIT
	_tab_row.position = Vector2.ZERO
	_tab_row.size = Vector2(left_w * 0.6, row_h)
	CardTokens.gap(_tab_row, 8.0, s)
	for id in _tabs:
		(_tabs[id] as Button).custom_minimum_size = Vector2(0.0, row_h)
		(_tabs[id] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.position = Vector2(left_w * 0.6, 0.0)
	_count.size = Vector2(left_w * 0.4, row_h)
	CardTokens.hub_text(_count, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
	place_grid(_grid, Rect2(0.0, row_h + gap * 0.5, left_w, area.y - row_h - gap * 0.5))
	var rx := left_w + gap * 2.0
	var rw := area.x - rx
	var button_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	_details.position = Vector2(rx, 0.0)
	_details.layout_box(rw, area.y, button_h, s, false)
	var row_px := maxf(button_h, CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s)
	_picker.position = Vector2(rx, area.y * 0.22)
	_picker.size = Vector2(rw, area.y * 0.78 - row_px - gap * 1.5)
	CardTokens.panel(_picker, CardTokens.hub_box(CardTokens.HUB_PAPER, CardTokens.HUB_DETAIL_EDGE, 3.0, 18.0, s))
	var head_h := CardTokens.FONT_CHAR_LINE * 2.6 * s
	_picker_head.position = Vector2(gap, gap * 0.3)
	_picker_head.size = Vector2(rw - gap * 2.0, head_h)
	CardTokens.hub_text(_picker_head, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s)
	_picker_box.position = Vector2(gap, gap * 0.3 + head_h)
	_picker_box.size = Vector2(rw - gap * 2.0, _picker.size.y - head_h - gap)
	CardTokens.flow_gap(_picker_box, 8.0, s)


func _container(p):
	return p.vault if tab == "vault" else p.stash


func refresh() -> void:
	super()
	var p = _profile()
	if p == null or _grid == null:
		return
	for id in _tabs:
		style_plate(_tabs[id], id == tab)
	var store = _container(p)
	_count.text = "%d / %d" % [store.items.size(), store.capacity]
	var item = null
	for piece in store.items:
		if piece.id == selected:
			item = piece
	if item == null:
		selected = ""
	fill_grid(_grid, _cells, store.items, store.capacity, selected, func(piece) -> void: select_item(piece.id))
	if item == null:
		_details.show_empty(CardTokens.t("pick_piece"), "", CardTokens.t("storage_empty") if store.items.is_empty() else "", "")
		return
	var rules = GameState.item_rules
	_details.show_item(item, rules)
	if tab == "stash":
		_details.add_action(CardTokens.t("wear_on"), _show_wear_picker)
		_details.add_action(CardTokens.t("to_vault"), _move.bind(item.id, "stash"))
		_details.add_action(CardTokens.t("discard"), _ask_discard)
	else:
		_details.add_action(CardTokens.t("to_stash"), _move.bind(item.id, "vault"))


func _picker_title(text: String) -> void:
	for child in _picker_box.get_children():
		_picker_box.remove_child(child)
		child.queue_free()
	_picker_head.text = text


func _picker_button(text: String, callback: Callable, disabled := false, why := "") -> Button:
	var b := plate(text if why.is_empty() else "%s  (%s)" % [text, why], callback)
	b.custom_minimum_size = Vector2(0.0, CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = disabled
	CardTokens.hub_button(b, s)
	_picker_box.add_child(b)
	CardTokens.hub_fit(b, b.text, CardTokens.FONT_CHAR_LINE, (_picker_box.size.x * 0.5 - 24.0 * s), CardTokens.HUB_INK, s, 0, "medium")
	return b


## "Wear on card...": one button per class card; a card that can't wear it says why (and stays disabled).
func _show_wear_picker() -> void:
	var p = _profile()
	var item = _find(p, selected)
	if item == null:
		return
	_picker_title(CardTokens.t("wear_on_title"))
	var first: Button = null
	for id in CardDeck.classes():
		var problem := Profile.slot_problem(id, item, GameState.item_rules)
		var b := _picker_button(CardTokens.class_name_of(id), _wear.bind(item.id, id), not problem.is_empty(), CardTokens.error_text(problem) if not problem.is_empty() else "")
		if first == null and not b.disabled:
			first = b
	_picker_button(CardTokens.t("cancel"), func() -> void: _picker.visible = false)
	_picker.visible = true
	if first != null:
		first.grab_focus.call_deferred()


func _ask_discard() -> void:
	var item = _find(_profile(), selected)
	if item == null:
		return
	_picker_title(CardTokens.t("discard_confirm") % HubItemDetails.item_name(item, GameState.item_rules))
	_picker_button(CardTokens.t("cancel"), func() -> void: _picker.visible = false).grab_focus.call_deferred()
	_picker_button(CardTokens.t("discard"), _discard.bind(item.id))
	_picker.visible = true


func _find(p, id: String):
	if p == null:
		return null
	for piece in _container(p).items:
		if piece.id == id:
			return piece
	return null


# ------------------------------------------------------------------ commands (rules in logic/commands.gd)
func _wear(item_id: String, card: String) -> void:
	_picker.visible = false
	var result := await run({"type": "equip", "item": item_id, "source": "stash", "card": card})
	if result.get("ok", false):
		selected = ""
		say(CardTokens.t("worn_on") % CardTokens.class_name_of(card))
		refresh()


func _discard(item_id: String) -> void:
	_picker.visible = false
	var result := await run({"type": "discard", "item": item_id, "source": "stash"})
	if result.get("ok", false):
		selected = ""
		say(CardTokens.t("discarded"))
		refresh()


func _move(item_id: String, from: String) -> void:
	var result := await run({"type": "storage_item", "item": item_id, "source": from})
	if result.get("ok", false):
		selected = ""
		say(CardTokens.t("moved_to_vault") if from == "stash" else CardTokens.t("moved_to_stash"))
		refresh()
