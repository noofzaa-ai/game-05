extends VBoxContainer
const Ink := preload("res://client/ink_ui.gd")
const Shop := preload("res://logic/shop.gd")
const Assets := preload("res://client/item_assets.gd")
signal message(text: String)
signal changed
var _session
var _profile
var _buttons: Array[Button] = []
var _rows: Array = []
var _pending := false

func setup(profile, rules, camp, authority) -> void:
	_session = authority
	_profile = profile
	Ink.gap(self, Ink.GAP_M)
	if Shop.stock(rules, camp).is_empty():
		add_child(Ink.label("ร้านค้ายังไม่มีสินค้า", Ink.MUTED))
		return
	var note := Label.new()
	note.text = "ทุกชิ้น 1,000 Gold · ซื้อแล้วเข้าคลัง · อุปกรณ์ Normal +0\nGold ที่มี: %d" % profile.stash.gold
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var search := LineEdit.new()
	search.placeholder_text = "ค้นหาไอเทม…"
	add_child(search)
	search.text_changed.connect(func(query: String):
		for entry in _rows: entry.row.visible = query.is_empty() or str(entry.name).to_lower().contains(query.to_lower()))
	for offer in Shop.stock(rules, camp):
		var plate := PanelContainer.new()
		Ink.panel(plate, Ink.panel_style())
		add_child(plate)
		var row := HBoxContainer.new()
		Ink.gap(row, Ink.GAP_M)
		plate.add_child(row)
		var picture := TextureRect.new()
		picture.custom_minimum_size = Vector2(64, 64)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture = Assets.icon_for_id(offer.id, rules.catalog) if offer.kind == "item" else Ink.icon(offer.id, 48)
		row.add_child(picture)
		var name_label := Label.new()
		name_label.text = str(offer.name)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var buy := Button.new()
		buy.text = "ซื้อ · 1,000 Gold"
		buy.custom_minimum_size = Vector2(180, 48)
		buy.disabled = profile.stash.gold < int(offer.price) or (profile.stash.free_slots() < 1 if offer.kind == "item" else profile.stash.room_for(offer.id) < 1)
		buy.tooltip_text = "Gold ไม่พอหรือคลังเต็ม" if buy.disabled else "ซื้อ 1 ชิ้นเข้าคลัง"
		buy.pressed.connect(_buy.bind(offer.sku))
		row.add_child(buy)
		_buttons.append(buy)
		_rows.append({"row": plate, "name": offer.name})

func _buy(sku: String) -> void:
	if _pending or _session == null: return
	var result: Dictionary = _session.command({"type": "shop_buy", "sku": sku})
	_pending = bool(result.get("pending", false))
	if _pending:
		for button in _buttons: button.disabled = true
		message.emit("กำลังซื้อ…")
	elif result.get("ok", false):
		for button in _buttons: button.disabled = true
		message.emit("ซื้อแล้ว ของอยู่ในคลัง")
		changed.emit()
	else:
		message.emit(preload("res://client/online/online_text.gd").command_message(result))
