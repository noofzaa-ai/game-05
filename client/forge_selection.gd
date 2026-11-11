extends VBoxContainer
## Smith workspace; authority owns prices, random rolls and item mutations.
const Ink := preload("res://client/ink_ui.gd")
const Cell := preload("res://client/item_cell.gd")
const Assets := preload("res://client/item_assets.gd")
const Text := preload("res://client/item_text.gd")
const Icon := preload("res://client/item_icon.gd")
signal item_selected(id: String)
var profile
var rules
var selected_id := ""
var _items := {}
var _cells: Array = []
var _slot: Control
var _details: Label
var _remove: Button
var _grid: GridContainer
var session
var camp
var _mode := ""
var _substats: Label
var _base: Label
var _preview: Label
var _refine: Button
var _pending := false
var _filter := "All"
var _inventory: VBoxContainer
var _worn := {}
var touch_minimum := 48.0

func setup(player, item_rules, mode: String, selection: String = "", authority = null, camp_data = null) -> void:
	session = authority
	camp = camp_data
	_mode = mode
	profile = player
	rules = item_rules
	selected_id = selection
	Ink.gap(self, Ink.GAP_M)
	var workspace := HBoxContainer.new()
	Ink.gap(workspace, Ink.GAP_M)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(workspace)
	var inventory_plate := PanelContainer.new()
	inventory_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_plate.size_flags_stretch_ratio = 0.44
	Ink.panel(inventory_plate, Ink.panel_style())
	workspace.add_child(inventory_plate)
	_inventory = VBoxContainer.new()
	inventory_plate.add_child(_inventory)
	var filters := HBoxContainer.new()
	_inventory.add_child(filters)
	for title in ["All", "Equipped", "Bag"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size.y = touch_minimum
		button.toggle_mode = true
		button.button_pressed = title == _filter
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			_filter = title
			for sibling in filters.get_children(): sibling.button_pressed = sibling.text == _filter
			_filter_items())
		filters.add_child(button)
	var plate := PanelContainer.new()
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.size_flags_stretch_ratio = 0.56
	Ink.panel(plate, Ink.panel_style())
	workspace.add_child(plate)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.add_child(info)
	info.add_child(Ink.label(mode + " · เลือกอุปกรณ์", Ink.GOLD, Ink.FONT_HEADING))
	var row := HBoxContainer.new()
	info.add_child(row)
	_slot = Cell.new()
	_slot.kind = "empty"
	_slot.custom_minimum_size = Vector2(64, 64)
	_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_slot.drop_check = func(_target, data): return is_instance_valid(data.get("cell")) and data.cell.item != null and _items.has(data.cell.item.id)
	_slot.drop_handler = func(_target, data): _choose(data.cell.item.id)
	row.add_child(_slot)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_details)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info.add_child(detail_scroll)
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(stats)
	_base = Ink.label("", Ink.GOLD, Ink.FONT_HEADING)
	_base.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var bold := FontVariation.new()
	bold.base_font = Ink.FONT
	bold.variation_embolden = 1.0
	_base.add_theme_font_override("font", bold)
	stats.add_child(_base)
	_substats = Ink.label("", Ink.SUBSTAT, Ink.FONT_LABEL)
	stats.add_child(_substats)
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(_preview)
	_refine = Button.new()
	_refine.text = "Refine +1"
	_refine.visible = true
	_refine.pressed.connect(_submit_refine)
	Ink.make_primary(_refine)
	_refine.add_theme_stylebox_override("normal", Ink.flat(Color("674921"), Ink.GOLD, 2, 4, 10))
	var actions := HBoxContainer.new()
	info.add_child(actions)
	_refine.custom_minimum_size.y = touch_minimum
	_refine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_refine)
	_remove = Button.new()
	_remove.text = "นำออก"
	_remove.custom_minimum_size.y = touch_minimum
	_remove.pressed.connect(func(): _choose(""))
	actions.add_child(_remove)
	if _mode == "Repair":
		var repair_all := Button.new()
		repair_all.text = "ซ่อมที่สวมใส่ทั้งหมด"
		repair_all.custom_minimum_size.y = touch_minimum
		repair_all.pressed.connect(func():
			if _pending or session == null: return
			var result: Dictionary = session.command({"type":"repair_all"})
			_pending = bool(result.get("pending", false))
			repair_all.disabled = _pending
			_choose(selected_id))
		actions.add_child(repair_all)
		repair_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory.add_child(Ink.label("แตะเลือก / ลากเข้าช่อง", Ink.MUTED, Ink.FONT_SMALL))
	_grid = GridContainer.new()
	Ink.gap(_grid, Ink.GAP_S, Ink.GAP_S)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inventory.add_child(scroll)
	scroll.add_child(_grid)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in profile.loadout.items(): _worn[item.id] = true
	var owned: Array = profile.stash.items.duplicate()
	owned.append_array(profile.loadout.items())
	for item in owned:
		if item.destroyed or (_mode == "Refine" and not item.slot in ["weapon", "hat", "shirt", "armband", "pants", "shoes"]) or _items.has(item.id): continue
		_items[item.id] = item
		var cell := Cell.new()
		cell.kind = "item"
		cell.custom_minimum_size = Vector2(68, 68)
		cell.worn_mark = _worn.has(item.id)
		_paint(cell, item)
		cell.tapped.connect(func(_cell): _choose(item.id))
		cell.activated.connect(func(_cell): _choose(item.id))
		_grid.add_child(cell)
		_cells.append(cell)
	if _items.is_empty(): add_child(Ink.label("ยังไม่มีชุดหรืออาวุธให้เลือก", Ink.MUTED))
	resized.connect(_fit_grid)
	_fit_grid.call_deferred()
	_choose(selected_id)

func _fit_grid() -> void:
	_grid.columns = clampi(int((_inventory.size.x - 24) / 76.0), 2, 5)

func _filter_items() -> void:
	for cell in _cells:
		cell.visible = _filter == "All" or (_filter == "Equipped" and _worn.has(cell.item.id)) or (_filter == "Bag" and not _worn.has(cell.item.id))

func _paint(cell, item) -> void:
	cell.item = item
	cell.icon_texture = Assets.icon(item, rules.catalog)
	cell.tier = item.tier
	cell.level = item.refine_level if item.refine_level > 0 else item.level
	cell.frame_color = Text.tier_color(item, rules)
	cell.icon_fill = cell.frame_color
	cell.icon_shape = Icon.shape_for(item.slot, item.weapon_type)
	cell.tooltip_text = Text.title(item, rules)
	cell.queue_redraw()

func _choose(id: String) -> void:
	selected_id = id if _items.has(id) else ""
	if selected_id.is_empty():
		_slot.item = null
		_slot.icon_texture = null
		_slot.tier = -1
		_slot.kind = "empty"
		_slot.queue_redraw()
		_details.text = "เลือกอุปกรณ์จากช่องทางซ้าย"
		_refine.text = "ซ่อมอุปกรณ์" if _mode == "Repair" else _mode
	else:
		var item = _items[selected_id]
		_slot.kind = "item"
		_paint(_slot, item)
		_details.text = Text.title(item, rules)
	_substats.text = ""
	_base.visible = not selected_id.is_empty()
	_preview.visible = not selected_id.is_empty()
	_refine.disabled = true
	if not selected_id.is_empty():
		var chosen = _items[selected_id]
		var base: float = chosen.base_value(rules)
		_base.text = Text.base_text(chosen, rules)
		for index in chosen.substats.size():
			_substats.text += ("\n" if index > 0 else "") + Text.substat_text(chosen, rules, index)
		if _mode == "Repair":
			var repair_logic = preload("res://logic/repair.gd")
			var camp_logic = preload("res://logic/camp.gd")
			var offer: Dictionary = repair_logic.quote(chosen, camp, camp_logic.repair_discount(profile, camp))
			_preview.text = "ความทนทาน %d%% → 100%%\nค่าใช้จ่าย: %s" % [roundi(chosen.durability_ratio()*100), Text.cost_text(offer, camp.materials)]
			_refine.text = "ซ่อมอุปกรณ์"
			_refine.disabled = _pending or session == null or offer.kind == "none" or not camp_logic.is_built(profile, str(camp.repair.facility)) or not profile.stash.can_afford(offer)
			if offer.kind == "none": _preview.text = "ความทนทานเต็มแล้ว · ไม่ต้องซ่อม"
		elif _mode == "Refine":
			var rate := float(rules.refine.get("bonus_per_level", 0))
			_preview.text = "Refine +%d → +%d · %s → %s (+%s)" % [chosen.refine_level, chosen.refine_level + 1, String.num(chosen.main_value(rules), 3), String.num(chosen.main_value(rules) + base * rate, 3), String.num(base * rate, 3)]
			_refine.text = "Refine +%d" % (chosen.refine_level + 1)
			if camp != null:
				var offer := preload("res://logic/refine.gd").quote(chosen, rules, camp)
				_refine.disabled = _pending or session == null or not offer.ok or (offer.ok and not profile.stash.can_afford(offer.cost))
				if offer.ok:
					_preview.text += "\nค่าใช้จ่าย: " + Text.cost_text(offer.cost, camp.materials)
					_preview.text += "\nสำเร็จ %s%% · พลาด → +%d" % [String.num(float(offer.success_chance) * 100, 0), int(offer.failure_level)]
				if not offer.ok:
					_preview.text = "ถึงระดับสูงสุดแล้ว" if offer.reason == "max_level" else _preview.text + "\nรอกำหนดค่าใช้จ่าย Refine"
		else:
			var cfg: Dictionary = rules.upgrade
			_preview.text = "Upgrade %d/%d · เหลือ %d ครั้ง" % [chosen.upgrade_count, int(cfg.get("max_attempts", 5)), maxi(0, int(cfg.get("max_attempts", 5)) - chosen.upgrade_count)]
			_refine.text = "Upgrade · สุ่มเพิ่ม 1 ออฟ" if chosen.substats.size() >= int(cfg.get("max_substats", 4)) else "Upgrade · สุ่มออฟใหม่ 1 แถว"
			if camp != null:
				var offer := preload("res://logic/upgrade.gd").quote(chosen, rules, camp)
				_refine.disabled = _pending or session == null or not offer.ok or (offer.ok and not profile.stash.can_afford(offer.cost))
				if offer.ok:
					_preview.text += "\nค่าใช้จ่าย: " + Text.cost_text(offer.cost, camp.materials)
				else:
					_preview.text += "\nครบจำนวน Upgrade แล้ว" if offer.reason == "max_level" else "\nยังไม่พร้อม Upgrade"

	_remove.disabled = selected_id.is_empty()
	for cell in _cells: cell.selected = cell.item.id == selected_id
	item_selected.emit(selected_id)


func _submit_refine() -> void:
	if _pending or selected_id.is_empty() or session == null: return
	var chosen = _items[selected_id]
	var request := {"type": "refine", "item": chosen.id, "level": chosen.refine_level} if _mode == "Refine" else {"type": "upgrade", "item": chosen.id, "count": chosen.upgrade_count}
	if _mode == "Repair": request = {"type":"repair", "item":chosen.id}
	var response: Dictionary = session.command(request)
	_pending = bool(response.get("pending", false))
	_refine.disabled = _pending
	if not _pending: _choose(selected_id)
