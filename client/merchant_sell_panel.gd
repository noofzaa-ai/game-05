extends "res://client/storage_panel.gd"
## Basket is local selection only. One server command sells the entire validated basket.
const Shop := preload("res://logic/shop.gd")
var _basket_items: Array[String] = []
var _basket_materials := {}
var _confirmation: ConfirmationDialog
var _sale_price := 0
var _stage_button: Button
var _clear_button: Button
var _picked_action := {}

func setup(player, item_rules, camp_data, authority) -> void:
	super.setup(player, item_rules, camp_data, authority)
	var buy_button := Button.new()
	buy_button.text = "ซื้ออาวุธ · ธนู"
	buy_button.custom_minimum_size.y = 48
	_move.get_parent().add_child(buy_button)
	buy_button.pressed.connect(func():
		if _busy or _blocked: return
		var shop = preload("res://client/merchant_buy_panel.gd").new()
		add_child(shop)
		shop.setup(profile, rules, camp, session))
	if preload("res://logic/skill_build.gd").enabled():
		var catalog_button := Button.new()
		catalog_button.text = "สกิล / Gem · ปลดล็อกทั้งหมด"
		catalog_button.custom_minimum_size.y = 48
		_stage_catalog_button(catalog_button)
	var row := HBoxContainer.new()
	_move.get_parent().add_child(row)
	_move.get_parent().move_child(row, 0)
	_stage_button = Button.new(); _stage_button.text = "ใส่กอง"
	_clear_button = Button.new(); _clear_button.text = "คืนทั้งหมด"
	for button in [_stage_button, _clear_button]:
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Ink.text_size(button, Ink.FONT_SMALL)
		row.add_child(button)
	_stage_button.pressed.connect(func(): _submit(_picked_action))
	_clear_button.pressed.connect(func():
		if _busy or _blocked: return
		_basket_items.clear(); _basket_materials.clear(); _render())
	_render()

func _panel_title() -> String: return "Merchant · ขายของ"
func _guide_key() -> String: return "merchant"
func _instructions() -> String: return "ลากของขวาไปกองซ้าย · ลากกลับเพื่อนำออก · กดขายทั้งกองเมื่อเลือกครบ (ยังไม่ขายตอนลาก)"
func _pending_text() -> String: return "กำลังขายทั้งกอง · รอเซิร์ฟเวอร์ยืนยัน…"
func _success_text() -> String: return "ขายทั้งกองแล้ว +%d Gold · บันทึกบนเซิร์ฟเวอร์แล้ว" % _sale_price

func _reconcile_basket() -> void:
	var owned := {}
	for item in profile.stash.items: owned[item.id] = true
	for index in range(_basket_items.size() - 1, -1, -1):
		if not owned.has(_basket_items[index]): _basket_items.remove_at(index)
	for id in _basket_materials.keys():
		_basket_materials[id] = mini(int(_basket_materials[id]), profile.stash.material_count(id))
		if int(_basket_materials[id]) <= 0: _basket_materials.erase(id)

func _entries_for_source(source: String) -> Array:
	var entries := []
	for item in profile.stash.items:
		if _basket_items.has(item.id) == (source == "vault"):
			entries.append({"kind": "item", "item": item, "id": item.id})
	var ids: Array = profile.stash.materials.keys(); ids.sort()
	for id in ids:
		var staged := int(_basket_materials.get(id, 0))
		var remaining: int = staged if source == "vault" else profile.stash.material_count(id) - staged
		while remaining > 0:
			var amount := mini(remaining, profile.stash.stack_size(id))
			entries.append({"kind": "material", "id": id, "count": amount})
			remaining -= amount
	return entries

func _capacity_for_source(source: String) -> int:
	# Keep empty drop slots in both panes; neither pane represents the real vault.
	return maxi(20, _entries_for_source(source).size() + 1) if source == "vault" else profile.stash.capacity

func _render() -> void:
	if profile != null: _reconcile_basket()
	super._render()
	if _detail == null: return
	var request := _batch_request()
	_heads.vault.text = "กองรอขาย · %d ช่อง · %d Gold" % [_entries_for_source("vault").size(), int(request.get("expected_price", 0))]
	_heads.stash.text = "กระเป๋า · Gold %d" % profile.stash.gold
	_fit.call_deferred()

func _payload(cell) -> Dictionary:
	if cell == null or cell.entry.is_empty(): return {}
	var action := {"action": "add" if cell.source == "stash" else "remove", "kind": cell.kind, "id": cell.entry.id}
	if cell.kind == "material": action["count"] = int(cell.entry.count)
	return action

func _batch_request() -> Dictionary:
	var entries := []
	var total := 0
	for item in profile.stash.items:
		if _basket_items.has(item.id):
			entries.append({"kind": "item", "id": item.id})
			total += Shop.item_sell_price(item, rules)
	var ids: Array = _basket_materials.keys(); ids.sort()
	for id in ids:
		entries.append({"kind": "material", "id": id, "count": int(_basket_materials[id])})
		total += Shop.material_sell_price(camp, id, 1) * int(_basket_materials[id])
	return {} if entries.is_empty() else {"type": "shop_sell_batch", "entries": entries, "expected_price": total}

func _select(cell) -> void:
	_picked_action = _payload(cell)
	super._select(cell)
	_selected = _batch_request()
	if not _picked_action.is_empty():
		var price := Shop.item_sell_price(cell.entry.item, rules) if cell.kind == "item" else Shop.material_sell_price(camp, cell.entry.id, int(cell.entry.count))
		_detail.add_child(Ink.label("ราคาขาย %d Gold" % price, Ink.GOLD, Ink.FONT_LABEL))
	_locks()

func _locks() -> void:
	super._locks()
	if _move != null:
		var request := _batch_request()
		_move.text = "ขายทั้งกอง · %d Gold" % int(request.get("expected_price", 0))
		_move.disabled = _busy or _blocked or request.is_empty() or session == null
	if is_instance_valid(_stage_button):
		_stage_button.text = "ใส่กอง" if _picked_action.get("action", "add") == "add" else "คืนกระเป๋า"
		_stage_button.disabled = _busy or _blocked or _picked_action.is_empty()
	if is_instance_valid(_clear_button): _clear_button.disabled = _busy or _blocked or _batch_request().is_empty()

func _submit(request: Dictionary) -> void:
	if _busy or _blocked or request.is_empty() or is_instance_valid(_confirmation): return
	if request.has("action"):
		_stage(request)
		return
	# Rebuild from current ownership and selection; no sale request is sent while dragging.
	var batch := _batch_request()
	if batch.is_empty(): return
	_sale_price = int(batch.expected_price)
	_busy = true; _locks()
	_confirmation = ConfirmationDialog.new()
	_confirmation.theme = Ink.make_theme()
	_confirmation.title = "ยืนยันขายทั้งกอง"
	_confirmation.dialog_text = "ขายอุปกรณ์ %d ชิ้น และวัตถุดิบ %d หน่วย\nได้รับรวม %d Gold\nขายแล้วนำของคืนไม่ได้" % [_basket_items.size(), _material_total(), _sale_price]
	_confirmation.ok_button_text = "ขายทั้งหมด"
	_confirmation.cancel_button_text = "ยกเลิก"
	_root.add_child(_confirmation)
	_confirmation.confirmed.connect(_confirm_sale.bind(batch))
	_confirmation.canceled.connect(_cancel_sale)
	_confirmation.popup_centered(Vector2i(340, 170))

func _stage(action: Dictionary) -> void:
	var old_items := _basket_items.duplicate()
	var old_materials := _basket_materials.duplicate()
	var adding: bool = action.action == "add"
	if action.kind == "item":
		if adding and not _basket_items.has(action.id):
			for item in profile.stash.items:
				if item.id == action.id and Shop.item_sell_price(item, rules) > 0: _basket_items.append(item.id); break
		elif not adding: _basket_items.erase(action.id)
	else:
		var have := int(_basket_materials.get(action.id, 0))
		var count := int(action.get("count", 0))
		if adding:
			if Shop.material_sell_price(camp, action.id, 1) < 1: return
			_basket_materials[action.id] = mini(profile.stash.material_count(action.id), have + count)
		else:
			_basket_materials[action.id] = maxi(0, have - count)
			if int(_basket_materials[action.id]) == 0: _basket_materials.erase(action.id)
	var batch := _batch_request()
	if not batch.is_empty() and (batch.entries.size() > 64 or JSON.stringify(batch).to_utf8_buffer().size() > 3400):
		_basket_items.assign(old_items); _basket_materials = old_materials
		_status.text = "กองรอขายเต็มแล้ว กรุณาแบ่งขายเป็นรอบ"
	else: _status.text = "เลือกของไว้แล้ว · ยังกดคืนได้ · กดขายทั้งกองเมื่อพร้อม"
	_render()

func _material_total() -> int:
	var total := 0
	for count in _basket_materials.values(): total += int(count)
	return total

func _completed(id: int, result: Dictionary) -> void:
	if _busy and id == _request and result.get("ok", false):
		_basket_items.clear(); _basket_materials.clear()
	super._completed(id, result)

func _cancel_sale() -> void:
	if is_instance_valid(_confirmation): _confirmation.queue_free()
	_confirmation = null
	_busy = false; _locks()

func _confirm_sale(request: Dictionary) -> void:
	_cancel_sale()
	super._submit(request)

func _stage_catalog_button(button: Button) -> void:
	_move.get_parent().add_child(button)
	button.pressed.connect(func():
		var catalog := preload("res://client/skill_catalog_panel.gd").new()
		add_child(catalog))
