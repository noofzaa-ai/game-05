extends "res://client/hub_service_panel.gd"
## Shop (docs/ui/hub_layout_spec.md §2): Buy / Sell tabs over the dimmed hub, the gold in the header.
## - Buy: the merchant's stock (logic/shop.gd stock(), server-owned data/items/shop.json) as tiles with the price;
##   `shop_buy {sku}`. An empty stock shows a "nothing for sale" message (the shop data currently lists an item
##   the catalog does not have, so the stock is empty: a data issue, not fixed here).
## - Sell: the shared Storage grid with details and the server's price (Shop.item_sell_price); Sell one piece
##   `shop_sell {item, expected_price}`, or Mark several and sell them together `shop_sell_batch {entries,
##   expected_price}`. Materials are sold one stack at a time: `shop_sell_material {material, count, expected_price}`.
## Prices shown are the server's own quote functions, so a stale quote is refused as "price_changed".

const Shop := preload("res://logic/shop.gd")

var tab := "buy"  ## buy | sell
var selected := ""  ## item id (sell) or sku (buy)
var marked: Array = []  ## item ids marked for the batch sale
var _tabs := {}
var _tab_row: HBoxContainer
var _grid: GridContainer
var _cells: Array = []
var _stock_scroll: ScrollContainer
var _stock: HFlowContainer
var _empty: Label
var _details: HubItemDetails
var _mats_title: Label
var _mats: HFlowContainer


func _init() -> void:
	service = "shop"


func build() -> void:
	_tab_row = HBoxContainer.new()
	body.add_child(_tab_row)
	for id in ["buy", "sell"]:
		var b := plate(CardTokens.t("shop_tab_" + id), select_tab.bind(id))
		_tab_row.add_child(b)
		_tabs[id] = b
	_grid = make_grid(body)
	_stock_scroll = ScrollContainer.new()
	_stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_stock_scroll)
	_stock = HFlowContainer.new()
	_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_scroll.add_child(_stock)
	_empty = CardTokens.label("", CardTokens.FONT_HUB_BODY, CardTokens.HUB_INK, 1.0, 0, "medium")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_empty)
	_details = HubItemDetails.new()
	body.add_child(_details)
	_mats_title = CardTokens.label(CardTokens.t("shop_materials"), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0)
	body.add_child(_mats_title)
	_mats = HFlowContainer.new()
	body.add_child(_mats)


func select_tab(id: String) -> void:
	tab = id
	selected = ""
	marked.clear()
	refresh()


func select_item(id: String) -> void:
	selected = id
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
	var list := Rect2(0.0, row_h + gap * 0.5, left_w, area.y - row_h - gap * 0.5)
	place_grid(_grid, list)
	_stock_scroll.position = list.position
	_stock_scroll.size = list.size
	CardTokens.flow_gap(_stock, CardTokens.CHAR_STORE_GAP, s)
	_empty.position = list.position + Vector2(0.0, list.size.y * 0.3)
	_empty.size = Vector2(list.size.x, list.size.y * 0.3)
	CardTokens.hub_text(_empty, CardTokens.FONT_HUB_BODY, CardTokens.HUB_INK, s, 0, "medium")
	var rx := left_w + gap * 2.0
	var rw := area.x - rx
	var button_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	var detail_h := area.y * CardTokens.SHOP_DETAIL_H
	_details.position = Vector2(rx, 0.0)
	_details.layout_box(rw, detail_h, button_h, s, false)
	_mats_title.position = Vector2(rx, detail_h + gap * 0.5)
	_mats_title.size = Vector2(rw, CardTokens.FONT_CHAR_LINE * 1.6 * s)
	CardTokens.hub_text(_mats_title, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s)
	_mats.position = Vector2(rx, _mats_title.position.y + _mats_title.size.y)
	_mats.size = Vector2(rw, area.y - _mats.position.y)
	CardTokens.flow_gap(_mats, 8.0, s)


func refresh() -> void:
	super()
	var p = _profile()
	if p == null or _grid == null:
		return
	for id in _tabs:
		style_plate(_tabs[id], id == tab)
	var selling := tab == "sell"
	(_grid.get_parent() as Control).visible = selling
	_stock_scroll.visible = not selling
	_mats_title.visible = selling
	_mats.visible = selling
	if selling:
		_refresh_sell(p)
	else:
		_refresh_buy(p)


# ------------------------------------------------------------------ Buy
func _refresh_buy(p) -> void:
	for child in _stock.get_children():
		_stock.remove_child(child)
		child.queue_free()
	var offers := Shop.stock(GameState.item_rules, GameState.camp_data)
	_empty.visible = offers.is_empty()
	_empty.text = CardTokens.t("shop_empty_stock") + "\n" + CardTokens.t("shop_empty_stock_line")
	var chosen := {}
	for offer in offers:
		if str(offer["sku"]) == selected:
			chosen = offer
		var b := Button.new()
		b.text = "%s\n%s" % [str(offer["name"]), CardTokens.t("cost_gold") % int(offer["price"])]
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(CardTokens.TAILOR_CHIP.x, CardTokens.tap(CardTokens.TAILOR_CHIP.y * 1.4, phone)) * s
		b.clip_text = true
		CardTokens.hub_button(b, s, false)
		CardTokens.hub_text(b, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "display" if str(offer["sku"]) == selected else "medium")
		b.pressed.connect(select_item.bind(str(offer["sku"])))
		_stock.add_child(b)
	if chosen.is_empty():
		_details.show_empty(CardTokens.t("shop_tab_buy"), "", "" if offers.is_empty() else CardTokens.t("pick_piece"), "")
		return
	_details.show_empty(str(chosen["name"]), CardTokens.slot_name(str(chosen.get("slot", ""))) if chosen.has("slot") else "", CardTokens.t("cost_gold") % int(chosen["price"]), "")
	var buy := _details.add_action(CardTokens.t("shop_buy_for") % int(chosen["price"]), _buy.bind(str(chosen["sku"]), str(chosen["name"])))
	buy.disabled = p.stash.gold < int(chosen["price"])
	if buy.disabled:
		buy.tooltip_text = CardTokens.error_text("cannot_afford")


# ------------------------------------------------------------------ Sell
func _refresh_sell(p) -> void:
	var rules = GameState.item_rules
	var items: Array = p.stash.items
	marked = marked.filter(func(id) -> bool: return _find(p, str(id)) != null)
	var item = _find(p, selected)
	if item == null:
		selected = ""
	fill_grid(_grid, _cells, items, _grid.columns * 3, selected, func(piece) -> void: select_item(piece.id), func(piece) -> void: _toggle_mark(piece.id))
	for c in _cells:
		var cell: HubItemCell = c
		cell.fits = cell.item != null and marked.has(cell.item.id)  # marked for the batch: gold frame + corner notch
		cell.queue_redraw()
	_empty.visible = items.is_empty()
	_empty.text = CardTokens.t("shop_nothing_to_sell")
	if item == null:
		_details.show_empty(CardTokens.t("shop_tab_sell"), "", CardTokens.t("pick_piece"), CardTokens.t("shop_marked_line") % [marked.size(), _marked_total(p)] if not marked.is_empty() else "")
	else:
		_details.show_item(item, rules)
		var price := Shop.item_sell_price(item, rules)
		_details.cost.text = CardTokens.t("shop_price_line") % price if price > 0 else CardTokens.t("shop_not_sellable")
		var sell := _details.add_action(CardTokens.t("shop_sell_for") % price, _sell.bind(item.id, price))
		sell.disabled = price < 1
		_details.add_action(CardTokens.t("shop_unmark") if marked.has(item.id) else CardTokens.t("shop_mark"), _toggle_mark.bind(item.id))
	if not marked.is_empty():
		_details.add_action(CardTokens.t("shop_sell_marked") % [marked.size(), _marked_total(p)], _sell_marked)
	_fill_materials(p)


func _fill_materials(p) -> void:
	for child in _mats.get_children():
		_mats.remove_child(child)
		child.queue_free()
	var camp = GameState.camp_data
	var ids: Array = p.stash.materials.keys()
	ids.sort()
	for id in ids:
		var have: int = p.stash.material_count(str(id))
		var count: int = mini(have, p.stash.stack_size(str(id)))
		if count < 1:
			continue
		var price := Shop.material_sell_price(camp, str(id), count)
		var name := str(camp.materials.get(id, {}).get("name", id))
		var b := plate(CardTokens.t("shop_sell_material") % [count, name, price], _sell_material.bind(str(id), count, price))
		b.custom_minimum_size = Vector2(CardTokens.TAILOR_CHIP.x * s * 1.3, CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s)
		b.disabled = price < 1
		CardTokens.hub_button(b, s)
		CardTokens.hub_text(b, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")
		_mats.add_child(b)


func _find(p, id: String):
	if p == null or id.is_empty():
		return null
	for piece in p.stash.items:
		if piece.id == id:
			return piece
	return null


func _marked_total(p) -> int:
	var total := 0
	for id in marked:
		total += Shop.item_sell_price(_find(p, str(id)), GameState.item_rules)
	return total


func _toggle_mark(id: String) -> void:
	if marked.has(id):
		marked.erase(id)
	else:
		marked.append(id)
	refresh()


# ------------------------------------------------------------------ commands (rules in logic/commands.gd)
func _buy(sku: String, name: String) -> void:
	var result := await run({"type": "shop_buy", "sku": sku})
	if result.get("ok", false):
		say(CardTokens.t("shop_bought") % name)


func _sell(item_id: String, price: int) -> void:
	var result := await run({"type": "shop_sell", "item": item_id, "expected_price": price})
	if result.get("ok", false):
		marked.erase(item_id)
		selected = ""
		say(CardTokens.t("shop_sold") % int(result.get("result", {}).get("price", price)))
		refresh()


func _sell_marked() -> void:
	var p = _profile()
	var entries: Array = []
	for id in marked:
		entries.append({"kind": "item", "id": str(id)})
	var total := _marked_total(p)
	var result := await run({"type": "shop_sell_batch", "entries": entries, "expected_price": total})
	if result.get("ok", false):
		marked.clear()
		selected = ""
		say(CardTokens.t("shop_sold") % int(result.get("result", {}).get("price", total)))
		refresh()


func _sell_material(id: String, count: int, price: int) -> void:
	var result := await run({"type": "shop_sell_material", "material": id, "count": count, "expected_price": price})
	if result.get("ok", false):
		say(CardTokens.t("shop_sold") % int(result.get("result", {}).get("price", price)))
