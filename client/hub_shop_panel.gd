extends "res://client/hub_service_panel.gd"
## Shop (docs/ui/hub_layout_spec.md §2): Buy / Sell tabs over the dimmed hub, the gold in the header.
## - Buy: the merchant's stock (logic/shop.gd stock(), server-owned data/items/shop.json) as tiles with the price;
##   `shop_buy {sku}`. An empty stock shows a "nothing for sale" message (the shop data currently lists an item
##   the catalog does not have, so the stock is empty: a data issue, not fixed here).
## - Sell: the shared Storage grid with details and the server's price (Shop.item_sell_price); Sell one piece
##   `shop_sell {item, expected_price}`, or Mark several and sell them together `shop_sell_batch {entries,
##   expected_price}`. Materials are sold one stack at a time: `shop_sell_material {material, count, expected_price}`.
## Prices shown are the server's own quote functions, so a stale quote is refused as "price_changed".
## Boss loot (design/gdd/boss-loot.md 2, Boss 2026-11-16): the stock is the boss set pieces, priced in that boss's coin
## (offer["currency"], a camp material with its painted icon_path); the coin count sits beside the tabs. Relics are
## never offered. A tile shows the piece icon, its name and the coin icon + price; short of coins, the details say
## "Need 500 coins (have 120)" and Buy is off.

const Shop := preload("res://logic/shop.gd")
const HubLook := preload("res://client/hub_look.gd")
const ItemAssets := preload("res://client/item_assets.gd")
## Bulk sale buttons: key -> [label token, rules.tiers ids]. white = normal, blue = rare (logic/shop.gd batch_sellable).
const BULK := {"white": ["shop_bulk_white", ["normal"]], "blue": ["shop_bulk_blue", ["rare"]], "both": ["shop_bulk_both", ["normal", "rare"]]}

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
var _coins: HBoxContainer  ## the boss coins the player has (buy tab)
var _bulk_row: HBoxContainer  ## Sell tab: "Sell all White / Blue / White + Blue" (Boss 2026-11-17)
var _bulk_buttons := {}  ## BULK key -> Button
var _bulk_hint: Label
var bulk_pending := ""  ## the BULK key waiting for its second press (the one-step confirm)
var _tile_w := 0.0  ## a stock tile: half the list width (two columns)


func _init() -> void:
	service = "shop"


func build() -> void:
	_tab_row = HBoxContainer.new()
	body.add_child(_tab_row)
	for id in ["buy", "sell"]:
		var b := plate(CardTokens.t("shop_tab_" + id), select_tab.bind(id))
		_tab_row.add_child(b)
		_tabs[id] = b
	_coins = HBoxContainer.new()
	_coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(_coins)
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
	_bulk_row = HBoxContainer.new()
	body.add_child(_bulk_row)
	for key in BULK:
		var bb := plate("", _bulk_pressed.bind(key))
		_bulk_row.add_child(bb)
		_bulk_buttons[key] = bb
	_bulk_hint = CardTokens.label(CardTokens.t("shop_bulk_hint"), CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_SUBTEXT, 1.0, 0, "medium")
	_bulk_hint.clip_text = true
	_bulk_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_bulk_hint)
	_mats_title = CardTokens.label(CardTokens.t("shop_materials"), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0)
	body.add_child(_mats_title)
	_mats = HFlowContainer.new()
	body.add_child(_mats)


func select_tab(id: String) -> void:
	tab = id
	selected = ""
	bulk_pending = ""
	marked.clear()
	refresh()


func select_item(id: String) -> void:
	bulk_pending = ""
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
	_coins.position = Vector2(left_w * 0.6, 0.0)
	_coins.size = Vector2(left_w * 0.4, row_h)
	CardTokens.gap(_coins, 8.0, s)
	var list := Rect2(0.0, row_h + gap * 0.5, left_w, area.y - row_h - gap * 0.5)
	place_grid(_grid, list)
	_stock_scroll.position = list.position
	_stock_scroll.size = list.size
	CardTokens.flow_gap(_stock, CardTokens.CHAR_STORE_GAP, s)
	_tile_w = floorf((list.size.x - CardTokens.CHAR_STORE_GAP * s) * 0.5 - 2.0)
	_empty.position = list.position + Vector2(0.0, list.size.y * 0.3)
	_empty.size = Vector2(list.size.x, list.size.y * 0.3)
	CardTokens.hub_text(_empty, CardTokens.FONT_HUB_BODY, CardTokens.HUB_INK, s, 0, "medium")
	var rx := left_w + gap * 2.0
	var rw := area.x - rx
	var button_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	var detail_h := area.y * CardTokens.SHOP_DETAIL_H
	_details.position = Vector2(rx, 0.0)
	_details.layout_box(rw, detail_h, button_h, s, false)
	_bulk_row.position = Vector2(rx, detail_h + gap * 0.5)
	_bulk_row.size = Vector2(rw, row_h)
	CardTokens.gap(_bulk_row, 6.0, s)
	for key in _bulk_buttons:
		(_bulk_buttons[key] as Button).custom_minimum_size = Vector2(0.0, row_h)
		(_bulk_buttons[key] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bulk_hint.position = Vector2(rx, _bulk_row.position.y + row_h)
	_bulk_hint.size = Vector2(rw, CardTokens.FONT_CHAR_SLOT * 1.5 * s)
	CardTokens.hub_text(_bulk_hint, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_SUBTEXT, s, 0, "medium")
	_mats_title.position = Vector2(rx, _bulk_hint.position.y + _bulk_hint.size.y)
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
	CardTokens.hub_text(_details.subs, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")  # the buy tab paints a shortfall line red
	var selling := tab == "sell"
	(_grid.get_parent() as Control).visible = selling
	_stock_scroll.visible = not selling
	_mats_title.visible = selling
	_mats.visible = selling
	_bulk_row.visible = selling
	_bulk_hint.visible = selling
	_coins.visible = not selling
	if selling:
		_refresh_sell(p)
	else:
		_refresh_buy(p)


# ------------------------------------------------------------------ Buy
func _refresh_buy(p) -> void:
	for box in [_stock, _coins]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var offers := Shop.stock(GameState.item_rules, GameState.camp_data)
	_empty.visible = offers.is_empty()
	_empty.text = CardTokens.t("shop_empty_stock") + "\n" + CardTokens.t("shop_empty_stock_line")
	var currencies: Array = []
	var chosen := {}
	for offer in offers:
		var currency := str(offer.get("currency", "gold"))
		if currency != "gold" and not currencies.has(currency):
			currencies.append(currency)
		if str(offer["sku"]) == selected:
			chosen = offer
		_stock.add_child(_offer_tile(offer, p))
	for currency in currencies:  # the coins the player has, beside the tabs
		_coins.add_child(_icon_rect(_currency_icon(currency), CardTokens.FONT_CHAR_LINE * 1.5 * s))
		var count := CardTokens.label(CardTokens.t("shop_coins") % _have(p, currency), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
		count.tooltip_text = _currency_name(currency)
		count.mouse_filter = Control.MOUSE_FILTER_PASS
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_coins.add_child(count)
	if chosen.is_empty():
		_details.show_empty(CardTokens.t("shop_tab_buy"), "", "" if offers.is_empty() else CardTokens.t("pick_piece"), "")
		return
	var price := int(chosen["price"])
	var currency := str(chosen.get("currency", "gold"))
	var have := _have(p, currency)
	var short := have < price
	var boss := currency != "gold"
	_details.show_empty(str(chosen["name"]), CardTokens.slot_name(str(chosen.get("slot", ""))) if chosen.has("slot") else "", _price_text(price, currency),
		_need_text(price, have, currency) if short else (CardTokens.t("shop_boss_piece") if boss else ""))
	_details.cost.visible = boss  # the random-tier note stays on screen when short of coins too (the need line takes the line above)
	_details.set_cost(CardTokens.t("shop_tier_random") if boss else "")
	if str(chosen.get("kind", "")) == "item":  # a preview of the piece as bought (icon + tier pips)
		var piece = preload("res://logic/item.gd").new()
		piece.item_id = str(chosen["id"])
		piece.slot = str(chosen.get("slot", ""))
		piece.tier = 0 if boss else int(Shop.config().get("equipment_tier", 0))  # boss pieces roll their tier at purchase
		_details.cell.show_item(piece, GameState.item_rules, "")
		_details.show_level(piece, GameState.item_rules)
	if short:
		CardTokens.hub_text(_details.subs, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_BAD, s, 0, "medium")
	else:
		CardTokens.hub_text(_details.subs, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")
	var buy := _details.add_action(CardTokens.t("shop_buy_coins" if boss else "shop_buy_for") % price, _buy.bind(str(chosen["sku"]), str(chosen["name"])))
	buy.disabled = short
	if short:
		buy.tooltip_text = _need_text(price, have, currency)


## One stock tile: the piece icon, its name, and the price (coin icon + number for boss coins, "N gold" otherwise).
func _offer_tile(offer: Dictionary, p) -> Button:
	var b := Button.new()
	var currency := str(offer.get("currency", "gold"))
	var price := int(offer["price"])
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(maxf(_tile_w, CardTokens.TAILOR_CHIP.x * s), CardTokens.tap(CardTokens.TAILOR_CHIP.y * 1.4, phone) * s)
	b.clip_contents = true
	b.tooltip_text = "%s  ·  %s" % [str(offer["name"]), _price_text(price, currency)] + ("  ·  " + CardTokens.t("shop_tier_random") if currency != "gold" else "")
	CarvedLook.chip_button(b, s)
	var on := str(offer["sku"]) == selected
	var pad := 8.0 * s
	var h := b.custom_minimum_size.y
	var icon_px := h - pad * 2.0
	var picture := _icon_rect(ItemAssets.icon_for_id(str(offer.get("id", "")), GameState.item_rules.catalog) if str(offer.get("kind", "")) == "item" else null, icon_px)
	picture.position = Vector2(pad, pad)
	picture.size = Vector2(icon_px, icon_px)
	b.add_child(picture)
	var tx := pad * 2.0 + icon_px
	var tw := b.custom_minimum_size.x - tx - pad
	var title := CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(tx, pad * 0.5)
	title.size = Vector2(tw, h * 0.5 - pad * 0.5)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HubLook.fit(title, str(offer["name"]), CardTokens.FONT_CHAR_LINE, tw, CardTokens.HUB_INK, s, 1, "display" if on else "medium")
	b.add_child(title)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(tx, h * 0.5)
	row.size = Vector2(tw, h * 0.5 - pad * 0.5)
	CardTokens.gap(row, 6.0, s)
	b.add_child(row)
	var short := _have(p, currency) < price
	if currency != "gold":
		row.add_child(_icon_rect(_currency_icon(currency), row.size.y))
	var tag := CardTokens.label(str(price) if currency != "gold" else CardTokens.t("cost_gold") % price, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_BAD if short else CardTokens.HUB_INK, s, 0, "medium")
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	if currency != "gold":  # a boss piece rolls its tier when bought (data/items/shop.json boss_item_tier "random")
		var roll := CardTokens.label(CardTokens.t("shop_tier_random_short"), CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_SUBTEXT, s, 0, "medium")
		roll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		roll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roll.clip_text = true
		roll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(roll)
	if str(offer.get("kind", "")) == "item" and GameState.item_rules.catalog.req_level(str(offer.get("id", ""))) > 1:  # level chip (Boss 2026-11-16)
		var level := CardTokens.label(CardTokens.t("req_lv_short") % GameState.item_rules.catalog.req_level(str(offer["id"])), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_SUBTEXT, s, 0, "medium")
		level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		level.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(level)
	b.pressed.connect(select_item.bind(str(offer["sku"])))
	return b


func _icon_rect(texture: Texture2D, px: float) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(px, px)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _have(p, currency: String) -> int:
	return int(p.stash.gold) if currency == "gold" else int(p.stash.material_count(currency))


func _currency_icon(currency: String) -> Texture2D:
	var path := str(GameState.camp_data.materials.get(currency, {}).get("icon_path", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return preload("res://client/brass_icons.gd").texture(currency, 48, CardTokens.HUB_INK)


func _currency_name(currency: String) -> String:
	var info: Dictionary = GameState.camp_data.materials.get(currency, {})
	return str(info.get("name_th" if CardTokens.language == "th" else "name", info.get("name", currency)))


func _price_text(price: int, currency: String) -> String:
	return CardTokens.t("cost_gold") % price if currency == "gold" else "%s  ·  %s" % [CardTokens.t("shop_price_coins") % price, _currency_name(currency)]


## "Need 500 coins (have 120)": what the player is short of.
func _need_text(price: int, have: int, currency: String) -> String:
	return CardTokens.t("shop_need_gold" if currency == "gold" else "shop_need_coins") % [price, have]


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
		_details.set_cost(CardTokens.t("shop_price_line") % price if price > 0 else CardTokens.t("shop_not_sellable"))
		var sell := _details.add_action(CardTokens.t("shop_sell_for") % price, _sell.bind(item.id, price))
		sell.disabled = price < 1
		_details.add_action(CardTokens.t("shop_unmark") if marked.has(item.id) else CardTokens.t("shop_mark"), _toggle_mark.bind(item.id))
	if not marked.is_empty():
		_details.add_action(CardTokens.t("shop_sell_marked") % [marked.size(), _marked_total(p)], _sell_marked)
	_refresh_bulk(p)
	_fill_materials(p)


## The bulk buttons: the label (with the count and gold of what it would sell), off when nothing qualifies; the pressed
## one shows the confirm text until the second press (or any other tap).
func _refresh_bulk(p) -> void:
	for key in BULK:
		var b: Button = _bulk_buttons[key]
		var plan := bulk_plan(p, str(key))
		var armed: bool = bulk_pending == key and int(plan["count"]) > 0
		if bulk_pending == key and not armed:
			bulk_pending = ""
		b.disabled = int(plan["count"]) < 1
		var name := CardTokens.t(str(BULK[key][0]))
		b.text = CardTokens.t("shop_bulk_sure") % [int(plan["count"]), int(plan["total"])] if armed else (CardTokens.t("shop_bulk_line") % [name, int(plan["count"]), int(plan["total"])] if int(plan["count"]) > 0 else "%s · %s" % [name, CardTokens.t("shop_bulk_none")])
		b.tooltip_text = CardTokens.t("shop_bulk_hint")
		CarvedLook.chip_button(b, s, armed, not armed)
		var w := b.size.x if b.size.x > 0.0 else b.custom_minimum_size.x
		CardTokens.hub_fit(b, b.text, CardTokens.FONT_CHAR_SLOT, maxf(w - 16.0 * s, 1.0), CardTokens.HUB_BAD if armed else (CardTokens.HUB_TAB_IDLE if b.disabled else CardTokens.HUB_INK), s, 0, "medium")


## What `key` would sell (logic/shop.gd batch_sellable): {"entries", "count", "total", "ids"}.
func bulk_plan(p, key: String) -> Dictionary:
	return Shop.batch_sellable(p, GameState.item_rules, BULK[key][1])


func _bulk_pressed(key: String) -> void:
	var p = _profile()
	var plan := bulk_plan(p, key)
	if int(plan["count"]) < 1:
		return
	if bulk_pending != key:  # first press: the button turns into "Tap again: sell N items (G gold)"
		bulk_pending = key
		refresh()
		return
	bulk_pending = ""
	var result := await run({"type": "shop_sell_batch", "entries": plan["entries"], "expected_price": int(plan["total"])})
	if result.get("ok", false):
		marked.clear()
		selected = ""
		var done: Dictionary = result.get("result", {})
		say(CardTokens.t("shop_bulk_sold") % [int(done.get("items", plan["count"])), int(done.get("price", plan["total"]))])
		refresh()


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
		CarvedLook.chip_button(b, s)
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
	var offer := {}
	for o in Shop.stock(GameState.item_rules, GameState.camp_data):
		if str(o["sku"]) == sku:
			offer = o
	var result := await run({"type": "shop_buy", "sku": sku})
	if result.get("ok", false):
		say(CardTokens.t("shop_bought") % name)
	elif str(result.get("error", result.get("reason", ""))) == "cannot_afford" and not offer.is_empty() and _profile() != null:
		var currency := str(offer.get("currency", "gold"))
		say(_need_text(int(offer["price"]), _have(_profile(), currency), currency), false)


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
