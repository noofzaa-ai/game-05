extends CanvasLayer
## No optimistic inventory edits: every cross-pane move waits for authoritative profile refresh.
signal closed
const Ink := preload("res://client/ink_ui.gd")
const Text := preload("res://client/item_text.gd")
const Assets := preload("res://client/item_assets.gd")
const Icon := preload("res://client/item_icon.gd")
const Cell := preload("res://client/storage_cell.gd")
const OnlineText := preload("res://client/online/online_text.gd")
var profile
var rules
var camp
var session
var _root: Control
var _window: PanelContainer
var _panes: BoxContainer
var _scrolls := {}
var _finger := -1
var _touch_cell
var _touch_from := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _touch_started := 0
var _dragging := false
var _scrolling := false
var _ghost: Control
var _grids := {}
var _heads := {}
var _cells: Array = []
var _status: Label
var _detail: VBoxContainer
var _move: Button
var _refresh_button: Button
var _close: Button
var _selected := {}
var _busy := false
var _blocked := false
var _request := -1

func setup(player, item_rules, camp_data, authority) -> void:
	profile = player; rules = item_rules; camp = camp_data; session = authority
	layer = 55
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Ink.make_theme(Ink.FONT_BODY)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0.02, 0.03, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_window = PanelContainer.new()
	Ink.panel(_window, Ink.camp_menu_window_style())
	_root.add_child(_window)
	var content := VBoxContainer.new()
	Ink.gap(content, 10)
	_window.add_child(content)
	var top := HBoxContainer.new()
	content.add_child(top)
	var title := Ink.label(_panel_title(), Ink.GOLD, Ink.FONT_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_close = Button.new(); _close.text = "×"; _close.custom_minimum_size = Vector2(52, 48)
	Ink.close_button(_close)
	Ink.npc_help(_close, _guide_key())
	_close.pressed.connect(close)
	top.add_child(_close)
	_panes = BoxContainer.new()
	_panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Ink.gap(_panes, 18)
	content.add_child(_panes)
	for source in ["vault", "stash"]: _pane(source)
	var bottom := HBoxContainer.new()
	Ink.gap(bottom, 16)
	content.add_child(bottom)
	var detail_plate := PanelContainer.new()
	Ink.panel(detail_plate, Ink.panel_style())
	detail_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(detail_plate)
	_detail = VBoxContainer.new(); Ink.gap(_detail, 3)
	detail_plate.add_child(_detail)
	var actions := VBoxContainer.new(); Ink.gap(actions, 8)
	actions.custom_minimum_size.x = 220
	bottom.add_child(actions)
	_move = Button.new(); _move.text = "เลือกของเพื่อย้าย"; _move.custom_minimum_size.y = 52
	_move.pressed.connect(func(): _submit(_selected))
	actions.add_child(_move)
	_refresh_button = Button.new(); _refresh_button.text = "โหลดข้อมูลล่าสุด"; _refresh_button.custom_minimum_size.y = 44
	_refresh_button.pressed.connect(_reload)
	actions.add_child(_refresh_button)
	_status = Ink.label(_instructions(), Ink.MUTED, Ink.FONT_SMALL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	if session != null and session.has_signal("ownership_changed"): session.ownership_changed.connect(_render)
	if session != null and session.has_signal("command_completed"): session.command_completed.connect(_completed)
	get_viewport().size_changed.connect(_fit)
	_render()
	_close.grab_focus()

func _pane(source: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Ink.panel(panel, Ink.panel_style())
	_panes.add_child(panel)
	var box := VBoxContainer.new(); Ink.gap(box, 10)
	panel.add_child(box)
	var heading := Ink.label("", Ink.GOLD, Ink.FONT_HEADING)
	box.add_child(heading); _heads[source] = heading
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(448, 360 if source == "vault" else 340)
	_scrolls[source] = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	Ink.gap(grid, 8, 8)
	scroll.add_child(grid); _grids[source] = grid

func _entries(inventory) -> Array:
	var entries := []
	for item in inventory.items: entries.append({"kind": "item", "item": item, "id": item.id})
	var ids: Array = inventory.materials.keys(); ids.sort()
	for id in ids:
		var remaining: int = inventory.material_count(id)
		while remaining > 0:
			var amount: int = mini(remaining, inventory.stack_size(id))
			entries.append({"kind": "material", "id": str(id), "count": amount})
			remaining -= amount
	return entries

func _render() -> void:
	if _detail == null: return
	_selected = {}
	_cells.clear()
	for source in ["vault", "stash"]:
		var inventory = profile.vault if source == "vault" else profile.stash
		_heads[source].text = ("คลัง · " if source == "vault" else "กระเป๋า · ") + "%d/%d" % [inventory.slots_used(), inventory.capacity]
		var grid: GridContainer = _grids[source]
		for child in grid.get_children():
			grid.remove_child(child); child.queue_free()
		var entries := _entries_for_source(source)
		for index in maxi(_capacity_for_source(source), entries.size()):
			var cell := Cell.new()
			cell.custom_minimum_size = Vector2(80, 80)
			cell.source = source; cell.owner_panel = get_instance_id()
			cell.entry = entries[index] if index < entries.size() else {}
			cell.kind = str(cell.entry.get("kind", "empty"))
			cell.locked = _busy or _blocked
			if cell.kind == "item":
				var item = cell.entry.item
				cell.item = item; cell.tier = item.tier; cell.level = item.refine_level
				cell.icon_texture = Assets.icon(item, rules.catalog)
				cell.frame_color = Text.tier_color(item, rules)
				cell.icon_fill = cell.frame_color
				cell.icon_shape = Icon.shape_for(item.slot, item.weapon_type)
				cell.tooltip_text = Text.title(item, rules)
			elif cell.kind == "material":
				cell.material_id = cell.entry.id; cell.count = cell.entry.count
				cell.icon_texture = Ink.icon(cell.entry.id, 56)
				cell.frame_color = Ink.GOLD
				cell.tooltip_text = str(camp.materials[cell.entry.id].name) + " ×" + str(cell.entry.count)
			cell.tapped.connect(func(c): _select(c))
			cell.drop_check = func(target, data): return _can_drop(target, data)
			cell.drop_handler = func(_target, data): _submit(_payload(data.cell))
			grid.add_child(cell); _cells.append(cell)
	_select(null)
	_locks()
	_fit.call_deferred()

func _payload(cell) -> Dictionary:
	if cell == null or cell.entry.is_empty(): return {}
	var request := {"source": cell.source}
	if cell.kind == "item":
		request.merge({"type": "storage_item", "item": cell.entry.id})
	else:
		request.merge({"type": "storage_material", "material": cell.entry.id, "count": cell.entry.count})
	return request

func _can_drop(target, data) -> bool:
	if _busy or _blocked or not data is Dictionary or not is_instance_valid(data.get("cell")): return false
	var cell = data.cell
	return cell is Cell and cell.owner_panel == get_instance_id() and cell.source != target.source and not cell.entry.is_empty()

func _select(cell) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child); child.queue_free()
	_selected = _payload(cell)
	for other in _cells: other.selected = other == cell and not _selected.is_empty()
	if _selected.is_empty():
		_detail.add_child(Ink.label("เลือกอุปกรณ์หรือวัตถุดิบเพื่อดูรายละเอียด", Ink.MUTED, Ink.FONT_SMALL))
		_move.text = "เลือกของเพื่อย้าย"
	else:
		_move.text = "← ฝากเข้าคลัง" if cell.source == "stash" else "ถอนเข้ากระเป๋า →"
		if cell.kind == "item":
			var item = cell.entry.item
			var title := Ink.label(Text.title(item, rules), Text.tier_color(item, rules), Ink.FONT_LABEL)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_detail.add_child(title)
			var base := Text.base_label(item, rules); Ink.text_size(base, Ink.FONT_LABEL); _detail.add_child(base)
			for index in item.substats.size(): _detail.add_child(Ink.label(Text.substat_text(item, rules, index), Ink.SUBSTAT, Ink.FONT_SMALL))
		else:
			_detail.add_child(Ink.label(str(camp.materials[cell.entry.id].name) + " ×" + str(cell.entry.count), Ink.PAPER, Ink.FONT_LABEL))
	_locks()
	_fit.call_deferred()

func _locks() -> void:
	_move.disabled = _busy or _blocked or _selected.is_empty() or session == null
	_close.disabled = _busy
	_refresh_button.disabled = _busy or session == null
	for cell in _cells: cell.locked = _busy or _blocked; cell.dimmed = _busy

func _submit(request: Dictionary) -> void:
	if _busy or _blocked or request.is_empty() or session == null: return
	_busy = true; _locks()
	_status.text = _pending_text()
	var result: Dictionary = session.command(request.duplicate(true))
	if result.get("pending", false): _request = int(result.id)
	else: _completed(-1, result)

func _completed(id: int, result: Dictionary) -> void:
	if not _busy or id != _request: return
	_busy = false; _request = -1
	if result.get("ok", false):
		_status.text = _success_text()
	else:
		_status.text = OnlineText.command_message(result)
		_blocked = str(result.get("error", "")) in ["unavailable", "connection_changed", "not_online", "stale_response"]
		if _blocked: _status.text += " · โหลดข้อมูลล่าสุดก่อนทำรายการต่อ"
	_render()

func _reload() -> void:
	if _busy or session == null: return
	_busy = true; _locks()
	var result: Dictionary
	if session.has_method("refresh_account"): result = await session.refresh_account()
	else: result = {"ok": true}
	if not is_inside_tree(): return
	_busy = false
	_blocked = not result.get("ok", false)
	_status.text = "โหลดข้อมูลล่าสุดแล้ว" if not _blocked else OnlineText.command_message(result)
	_render()

func _fit() -> void:
	if _window == null or not is_inside_tree(): return
	var area := get_viewport().get_visible_rect().size
	var portrait := area.x < area.y * 0.9
	_panes.vertical = portrait
	var desired := Vector2(750, 1300) if portrait else Vector2(1100, 760)
	_window.size = desired
	desired = desired.max(_window.get_combined_minimum_size())
	var factor := minf((area.x - 32) / desired.x, (area.y - 32) / desired.y)
	_window.scale = Vector2.ONE * factor
	_window.size = desired
	_window.position = (area - desired * factor) * 0.5

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if _busy: return
	closed.emit(); queue_free()


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or _root == null: return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _finger < 0 and not _busy and not _blocked:
			for cell in _cells:
				if cell.get_global_rect().has_point(event.position) and _scrolls[cell.source].get_global_rect().has_point(event.position):
					_finger = event.index; _touch_cell = cell
					_touch_from = event.position; _touch_last = event.position
					_touch_started = Time.get_ticks_msec(); _dragging = false; _scrolling = false
					get_viewport().set_input_as_handled()
					return
		elif not event.pressed and event.index == _finger:
			if not event.canceled and is_instance_valid(_touch_cell):
				if _dragging:
					for source in _scrolls:
						if source != _touch_cell.source and _scrolls[source].get_global_rect().has_point(event.position):
							_submit(_payload(_touch_cell)); break
				elif not _scrolling: _select(_touch_cell)
			_cancel_touch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _finger:
		if not is_instance_valid(_touch_cell):
			_cancel_touch(); return
		var delta: Vector2 = event.position - _touch_from
		if not _dragging and not _scrolling and delta.length() > 14:
			if _touch_cell.has_thing() and (absf(delta.x) > absf(delta.y) or Time.get_ticks_msec() - _touch_started >= 250):
				_dragging = true
				var ghost := Cell.new()
				ghost.copy_look(_touch_cell)
				ghost.size = _touch_cell.size
				ghost.scale = _touch_cell.get_global_transform_with_canvas().get_scale()
				ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ghost.modulate.a = 0.8
				_root.add_child(ghost); _ghost = ghost
			else: _scrolling = true
		if _dragging and is_instance_valid(_ghost):
			_ghost.position = event.position - _ghost.size * _ghost.scale * 0.5
		elif _scrolling:
			var scroll: ScrollContainer = _scrolls[_touch_cell.source]
			scroll.scroll_vertical += roundi((_touch_last.y - event.position.y) / maxf(scroll.get_global_transform_with_canvas().get_scale().y, 0.01))
		_touch_last = event.position
		get_viewport().set_input_as_handled()

func _cancel_touch() -> void:
	_finger = -1; _touch_cell = null; _dragging = false; _scrolling = false
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _cancel_touch()


func _panel_title() -> String: return "Storage"
func _guide_key() -> String: return "storage"
func _instructions() -> String: return "ลากข้ามฝั่งเพื่อย้าย · ปัดขึ้นลงเพื่อเลื่อน · หรือแตะของแล้วกดฝาก / ถอน"
func _pending_text() -> String: return "กำลังย้าย · รอเซิร์ฟเวอร์ยืนยัน…"
func _success_text() -> String: return "ย้ายเรียบร้อย · บันทึกบนเซิร์ฟเวอร์แล้ว"


func _entries_for_source(source: String) -> Array:
	return _entries(profile.vault if source == "vault" else profile.stash)

func _capacity_for_source(source: String) -> int:
	return (profile.vault if source == "vault" else profile.stash).capacity
