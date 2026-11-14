extends "res://client/hub_service_panel.gd"
## Blacksmith (docs/ui/hub_layout_spec.md §2): pick a source (one of the class cards = what it wears, or the shared
## Storage), pick a piece in the grid, then Refine / Upgrade / Upgrade tier / Repair it (or Repair all of a card).
## The right side shows the item details, every action's cost and its chance / result (Refine: success chance and
## the level a failure falls to; Upgrade: a new substat row or a boost, attempts used), and the status line says the
## outcome. Commands (logic/commands.gd): refine {item, level}, upgrade {item, count}, repair {item},
## repair_all {card}. upgrade_tier / enhance are refused by the rules ("not_configured", Boss 2026-10-17): the
## Upgrade tier button stays visible, disabled, with that reason.

const CardDeck := preload("res://logic/card_deck.gd")
const Refine := preload("res://logic/refine.gd")
const Upgrade := preload("res://logic/upgrade.gd")
const Repair := preload("res://logic/repair.gd")
const Camp := preload("res://logic/camp.gd")
const ItemText := preload("res://client/item_text.gd")

var source := ""  ## a class id, or "storage"
var selected := ""  ## item id
var _sources := {}  ## source id -> Button
var _source_row: HBoxContainer
var _repair_all: Button
var _grid: GridContainer
var _cells: Array = []
var _details: HubItemDetails
var _odds: Label
var _buttons: GridContainer
var _refine: Button
var _upgrade: Button
var _tier: Button
var _repair: Button


func _init() -> void:
	service = "blacksmith"


func build() -> void:
	_source_row = HBoxContainer.new()
	body.add_child(_source_row)
	for id in CardDeck.classes():
		var b := plate(CardTokens.class_name_of(id), select_source.bind(id))
		_source_row.add_child(b)
		_sources[id] = b
	var store := plate(CardTokens.t("svc_storage"), select_source.bind("storage"))
	_source_row.add_child(store)
	_sources["storage"] = store
	_grid = make_grid(body)
	_details = HubItemDetails.new()
	body.add_child(_details)
	_odds = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odds.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_child(_odds)
	_buttons = GridContainer.new()
	_buttons.columns = 3
	body.add_child(_buttons)
	_refine = _action(CardTokens.t("refine"), _on_refine)
	_upgrade = _action(CardTokens.t("upgrade"), _on_upgrade)
	_tier = _action(CardTokens.t("upgrade_tier"), func() -> void: say(CardTokens.error_text("not_configured")))
	_repair = _action(CardTokens.t("repair"), _on_repair)
	_repair_all = _action(CardTokens.t("repair_all"), _on_repair_all)
	if source.is_empty():
		source = CardDeck.classes()[0] if not CardDeck.classes().is_empty() else "storage"


func _action(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.pressed.connect(callback)
	_buttons.add_child(b)
	return b


## Opens on a piece (from the character screen's Blacksmith button): finds who wears it, else Storage.
func open_on(item_id: String) -> void:
	var p = _profile()
	if p != null and not item_id.is_empty():
		source = "storage"
		for id in CardDeck.classes():
			var worn = p.loadout_of(id)
			if worn != null:
				for item in worn.items():
					if item.id == item_id:
						source = id
		selected = item_id
	open()


func select_source(id: String) -> void:
	source = id
	selected = ""
	refresh()


func select_item(id: String) -> void:
	selected = id
	refresh()


func first_focus() -> Control:
	return _sources.get(source, _close)


func layout_body(area: Vector2) -> void:
	var gap := CardTokens.CHAR_GAP * s
	var row_h := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s
	var left_w := area.x * CardTokens.SVC_SPLIT
	_source_row.position = Vector2.ZERO
	_source_row.size = Vector2(left_w, row_h)
	CardTokens.gap(_source_row, 8.0, s)
	for id in _sources:
		var b: Button = _sources[id]
		b.custom_minimum_size = Vector2(0.0, row_h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid_top := row_h + gap * 0.5
	place_grid(_grid, Rect2(0.0, grid_top, left_w, area.y - grid_top))
	var rx := left_w + gap * 2.0
	var rw := area.x - rx
	var button_h := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	var detail_h := area.y * CardTokens.SVC_DETAIL_H
	_details.position = Vector2(rx, 0.0)
	_details.layout_box(rw, detail_h, 0.0, s, false)
	var buttons_h := maxf(button_h, _refine.get_combined_minimum_size().y) * 2.0 + gap * 0.75
	_buttons.position = Vector2(rx, area.y - buttons_h)
	_buttons.size = Vector2(rw, buttons_h)
	CardTokens.flow_gap(_buttons, CardTokens.CHAR_GAP * 0.75, s)
	for b in [_refine, _upgrade, _tier, _repair, _repair_all]:
		b.custom_minimum_size = Vector2(0.0, button_h)
		CarvedLook.plate_button(b, s)
	HubItemDetails.fit_buttons(_buttons, s, 3)
	_odds.position = Vector2(rx, detail_h + gap * 0.5)
	_odds.size = Vector2(rw, maxf(area.y - buttons_h - detail_h - gap, 0.0))
	CardTokens.hub_text(_odds, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")


func _items(p) -> Array:
	if source == "storage":
		return p.stash.items.filter(func(item) -> bool: return not item.destroyed)
	var worn = p.loadout_of(source)
	return worn.items() if worn != null else []


func refresh() -> void:
	super()
	var p = _profile()
	if p == null or _grid == null:
		return
	for id in _sources:
		style_plate(_sources[id], id == source)
	_repair_all.disabled = source == "storage"
	_repair_all.tooltip_text = CardTokens.t("repair_all_hint")
	var items := _items(p)
	var item = null
	for piece in items:
		if piece.id == selected:
			item = piece
	if item == null and not items.is_empty():
		item = items[0]
		selected = item.id
	fill_grid(_grid, _cells, items, _grid.columns * 2, selected, func(piece) -> void: select_item(piece.id))
	var rules = GameState.item_rules
	var camp = GameState.camp_data
	if item == null:
		_details.show_empty(CardTokens.t("smith_pick"), "", CardTokens.t("smith_none") if source == "storage" else "", "")
		_odds.text = ""
		for b in [_refine, _upgrade, _tier, _repair]:
			b.disabled = true
		return
	_details.show_item(item, rules)
	var refine_offer: Dictionary = Refine.quote(item, rules, camp)
	var upgrade_offer: Dictionary = Upgrade.quote(item, rules, camp)
	var repair_cost: Dictionary = Repair.quote(item, camp, Camp.repair_discount(p, camp))
	var lines: Array[String] = []
	if refine_offer.get("ok", false):
		var chance := int(round(float(refine_offer["success_chance"]) * 100.0))
		var line := CardTokens.t("smith_refine_line") % [int(refine_offer["next_level"]), HubItemDetails.cost_text(refine_offer["cost"], camp), chance]
		if chance < 100:
			line += "  " + CardTokens.t("smith_refine_fail") % int(refine_offer["failure_level"])
		lines.append(line)
	else:
		lines.append("%s: %s" % [CardTokens.t("refine"), CardTokens.error_text(str(refine_offer.get("reason", "")))])
	if upgrade_offer.get("ok", false):
		var what := CardTokens.t("smith_upgrade_add") if upgrade_offer["add_row"] else CardTokens.t("smith_upgrade_boost")
		lines.append(CardTokens.t("smith_upgrade_line") % [HubItemDetails.cost_text(upgrade_offer["cost"], camp), what, int(upgrade_offer["used"]), int(upgrade_offer["max"])])
	else:
		lines.append("%s: %s" % [CardTokens.t("upgrade"), CardTokens.error_text(str(upgrade_offer.get("reason", "")))])
	lines.append("%s: %s" % [CardTokens.t("upgrade_tier"), CardTokens.error_text("not_configured")])
	if str(repair_cost["kind"]) == "none":
		lines.append("%s: %s" % [CardTokens.t("repair"), CardTokens.t("like_new")])
	else:
		lines.append(CardTokens.t("smith_repair_line") % [HubItemDetails.cost_text(repair_cost, camp), int(round(float(repair_cost["points"])))])
	_odds.text = "\n".join(lines)
	_details.cost.text = ""
	_refine.disabled = not refine_offer.get("ok", false) and str(refine_offer.get("reason", "")) in ["invalid_item", "max_level", "not_configured"]
	_upgrade.disabled = not upgrade_offer.get("ok", false) and str(upgrade_offer.get("reason", "")) in ["invalid_item", "max_level", "not_configured"]
	_tier.disabled = true
	_tier.tooltip_text = CardTokens.error_text("not_configured")
	_repair.disabled = str(repair_cost["kind"]) == "none"


func _selected_item():
	var p = _profile()
	if p == null:
		return null
	for item in _items(p):
		if item.id == selected:
			return item
	return null


# ------------------------------------------------------------------ commands (rules in logic/commands.gd)
func _on_refine() -> void:
	var item = _selected_item()
	if item == null:
		return
	var result := await run({"type": "refine", "item": item.id, "level": item.refine_level})
	if result.get("ok", false):
		var info: Dictionary = result.get("result", {})
		say((CardTokens.t("refined_ok") if info.get("success", true) else CardTokens.t("refine_failed")) % int(info.get("level", 0)))


func _on_upgrade() -> void:
	var item = _selected_item()
	if item == null:
		return
	var result := await run({"type": "upgrade", "item": item.id, "count": item.upgrade_count})
	if result.get("ok", false):
		var info: Dictionary = result.get("result", {})
		var stat := str(ItemText.STAT_LABELS.get(str(info.get("stat", "")), info.get("stat", "")))
		if info.get("added_row", false):
			say(CardTokens.t("upgraded_add") % stat)
		else:
			say(CardTokens.t("upgraded_boost") % [stat, HubItemDetails.num(float(info.get("bonus", 0.0)))])


func _on_repair() -> void:
	var item = _selected_item()
	if item == null:
		return
	var result := await run({"type": "repair", "item": item.id})
	if result.get("ok", false):
		var paid: Dictionary = result.get("result", {}).get("cost", {})
		say(CardTokens.t("repaired_for") % HubItemDetails.cost_text(paid, GameState.camp_data))


func _on_repair_all() -> void:
	if source == "storage":
		return
	var result := await run({"type": "repair_all", "card": source})
	if result.get("ok", false):
		var info: Dictionary = result.get("result", {})
		say(CardTokens.t("repaired_all") % [int(info.get("repaired", 0)), int(info.get("gold", 0)), int(info.get("skipped", 0))])
