extends CanvasLayer
## Read-only camp character sheet. Stats use the game's own rules, wear and set bonuses.
signal closed
const Ink := preload("res://client/ink_ui.gd")
const Text := preload("res://client/item_text.gd")
const Stats := preload("res://logic/stats.gd")
const Doll := preload("res://client/paper_doll.gd")
const Cell := preload("res://client/item_cell.gd")
const Assets := preload("res://client/item_assets.gd")
const Icon := preload("res://client/item_icon.gd")
var profile
var rules
var _root: Control
var _window: PanelContainer
var _body: BoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _doll
var _detail: VBoxContainer
var _cells: Array = []
var _selected
var _close_button: Button
var _session

func setup(player, item_rules, authority = null) -> void:
	profile = player
	rules = item_rules
	_session = authority
	layer = 55
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Ink.make_theme(Ink.FONT_BODY)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.035, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_window = PanelContainer.new()
	Ink.panel(_window, Ink.camp_menu_window_style())
	_root.add_child(_window)
	var content := VBoxContainer.new()
	Ink.gap(content, 10)
	_window.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var emblem := TextureRect.new()
	emblem.texture = Ink.icon("player_info", 42)
	emblem.custom_minimum_size = Vector2(42, 42)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	header.add_child(emblem)
	var heading := Ink.label("Player Info", Ink.GOLD, Ink.FONT_TITLE)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.custom_minimum_size = Vector2(52, 48)
	Ink.close_button(_close_button)
	_close_button.pressed.connect(close)
	header.add_child(_close_button)
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Ink.gap(_body, 18)
	content.add_child(_body)
	_left = VBoxContainer.new()
	_left.custom_minimum_size.x = 420
	Ink.gap(_left, 8)
	_body.add_child(_left)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ink.gap(_right, 8)
	_body.add_child(_right)
	_build_character()
	_build_stats()
	var note := Ink.label("ค่าสเตตัสรวมพื้นฐาน + อุปกรณ์ + โบนัสเซ็ต · แตะอุปกรณ์เพื่อดูรายละเอียด", Ink.MUTED, Ink.FONT_SMALL)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()
	_close_button.grab_focus()
	if _session != null and _session.has_signal("ownership_changed"):
		_session.ownership_changed.connect(_refresh)

func _build_character() -> void:
	var name_label := Ink.label(profile.name if not profile.name.is_empty() else "Adventurer", Ink.PAPER, Ink.FONT_HEADING)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left.add_child(name_label)
	var equipment := HBoxContainer.new()
	Ink.gap(equipment, 8)
	_left.add_child(equipment)
	var left_slots := VBoxContainer.new()
	Ink.gap(left_slots, 10)
	equipment.add_child(left_slots)
	_doll = Doll.new()
	_doll.custom_minimum_size = Vector2(232, 300)
	_doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment.add_child(_doll)
	var right_slots := VBoxContainer.new()
	Ink.gap(right_slots, 10)
	equipment.add_child(right_slots)
	for slot in ["weapon", "shirt", "pants"]: _slot(left_slots, slot, 0, 80)
	for slot in ["hat", "armband", "shoes"]: _slot(right_slots, slot, 0, 80)
	var accessories := HBoxContainer.new()
	accessories.alignment = BoxContainer.ALIGNMENT_CENTER
	Ink.gap(accessories, 5)
	_left.add_child(accessories)
	for entry in rules.slots:
		if entry.id in ["weapon", "shirt", "pants", "hat", "armband", "shoes"]: continue
		for index in int(entry.count): _slot(accessories, entry.id, index, 46)
	var set_box := Ink.label("Equipment · อุปกรณ์ที่สวมใส่", Ink.GOLD, Ink.FONT_SMALL)
	set_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left.add_child(set_box)
	_dress()

func _slot(parent: Control, slot: String, index: int, px: int) -> void:
	var cell := Cell.new()
	cell.custom_minimum_size = Vector2.ONE * px
	var item = profile.loadout.item_at(slot, index)
	cell.kind = "item" if item != null else "slot"
	cell.slot_id = slot
	cell.item = item
	cell.icon_texture = Assets.icon(item, rules.catalog) if item != null else Ink.icon(slot, px - 22)
	cell.tier = item.tier if item != null else -1
	cell.frame_color = Text.tier_color(item, rules) if item != null else Ink.GOLD
	cell.icon_fill = Ink.GOLD
	cell.icon_shape = Icon.shape_for(slot, item.weapon_type if item != null else "")
	cell.level = item.refine_level if item != null else 0
	cell.tooltip_text = Text.title(item, rules) if item != null else slot.capitalize() + " · ว่าง"
	cell.tapped.connect(func(_cell): _show_item(item, slot))
	parent.add_child(cell)
	_cells.append(cell)

func _dress() -> void:
	var weapon = profile.loadout.item_at("weapon", 0)
	_doll.dress(profile.loadout, weapon.weapon_type if weapon != null else "", rules.catalog, profile.appearance)

func _build_stats() -> void:
	var section := Ink.label("Status", Ink.GOLD, Ink.FONT_HEADING)
	_right.add_child(section)
	var values: Dictionary = Stats.totals(rules, profile.loadout.items())
	var grid := GridContainer.new()
	grid.columns = 2
	Ink.gap(grid, 8, 8)
	_right.add_child(grid)
	for stat in rules.stat_ids:
		var plate := PanelContainer.new()
		Ink.panel(plate, Ink.plate(Ink.INK, Ink.GOLD, 0.8))
		plate.custom_minimum_size = Vector2(270, 39)
		plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(plate)
		var row := HBoxContainer.new()
		plate.add_child(row)
		var label: String = {"HP": "Max HP", "STAMINA": "Max Stamina"}.get(stat, Text.STAT_LABELS.get(stat, stat))
		var title := Ink.label(label, Ink.PAPER, Ink.FONT_SMALL)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var number := _number(float(values.get(stat, 0.0)))
		if number.is_empty(): number = "0"
		var unit := str(rules.stat_unit.get(stat, "flat"))
		if unit == "percent": number += "%"
		elif unit == "per_second": number += "/s"
		row.add_child(Ink.label(number, Ink.GOLD, Ink.FONT_LABEL))
	var detail_plate := PanelContainer.new()
	Ink.panel(detail_plate, Ink.panel_style())
	detail_plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(detail_plate)
	_detail = VBoxContainer.new()
	Ink.gap(_detail, 3)
	detail_plate.add_child(_detail)
	var first = profile.loadout.item_at("weapon", 0)
	_show_item(first, "weapon" if first != null else "")

func _show_item(item, slot: String) -> void:
	_selected = item
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	for cell in _cells:
		cell.selected = item != null and cell.item == item
	if item == null:
		_detail.add_child(Ink.label("เลือกอุปกรณ์เพื่อดูรายละเอียด" if slot.is_empty() else slot.capitalize() + " · ยังไม่ได้สวมใส่", Ink.MUTED, Ink.FONT_SMALL))
		return
	var title := Ink.label(Text.title(item, rules), Text.tier_color(item, rules), Ink.FONT_LABEL)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(title)
	var base := Text.base_label(item, rules)
	Ink.text_size(base, Ink.FONT_LABEL)
	_detail.add_child(base)
	for index in item.substats.size():
		_detail.add_child(Ink.label(Text.substat_text(item, rules, index), Ink.SUBSTAT, Ink.FONT_SMALL))
	_detail.add_child(Ink.label("Upgrade %d/%d · %s" % [item.upgrade_count, int(rules.upgrade.get("max_attempts", 5)), Text.durability_text(item, rules)], Ink.MUTED, Ink.FONT_TINY))
	_fit.call_deferred()

func _refresh() -> void:
	# Account refresh replaces loadout objects; rebuild the sheet from its current profile.
	for child in _left.get_children():
		_left.remove_child(child)
		child.queue_free()
	for child in _right.get_children():
		_right.remove_child(child)
		child.queue_free()
	_cells.clear()
	_build_character()
	_build_stats()
	_fit.call_deferred()

func _fit() -> void:
	if _window == null or not is_inside_tree(): return
	var area := get_viewport().get_visible_rect().size
	var portrait := area.x < area.y * 0.9
	_body.vertical = portrait
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_SHRINK_BEGIN
	var desired := Vector2(650, 1160) if portrait else Vector2(1100, 700)
	_window.size = desired
	var minimum := _window.get_combined_minimum_size()
	desired = desired.max(minimum)
	var factor := minf((area.x - 32) / desired.x, (area.y - 32) / desired.y)
	_window.scale = Vector2.ONE * factor
	_window.size = desired
	_window.position = (area - desired * factor) * 0.5

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	closed.emit()
	queue_free()


static func _number(value: float) -> String:
	if absf(value - roundf(value)) < 0.00001: return str(int(roundf(value)))
	return String.num(value, 3).rstrip("0").trim_suffix(".")
