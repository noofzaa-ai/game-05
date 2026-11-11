extends Control
## The gear page of the camp / rest-point screen: one window with
##   - the paper-doll (the player's live 3D character) and the 15 equipment slots around it
##     (accessories along the top, armor down the left, arm pieces down the right, weapon and back below),
##   - the bag grid (the camp stash, or the run bag at a rest point): item icons with tier frames and
##     pips, stack counts, a search box and category filters,
##   - a detail panel: the selected piece, how it compares with what is worn, and its actions
##     (with nothing selected it shows the character's stats and fighting style).
## Equip / take off, the same on mouse and touch:
##   tap a piece = select it (details); double-click / double-tap or right-click = wear it / take it off;
##   drag a piece onto its slot = wear it there; drag a worn piece onto the bag = take it off;
##   hold = details (on a phone in portrait it opens the detail sheet); the detail panel's buttons
##   do everything too, so nothing needs a mouse or hovering.
## All ownership changes go through LocalSession.command(); this page shows state and choices.
## Words the player sees are in TEXT (one place, for translation).
## EXTENDING: a new slot gets a place in SLOT_PLACES (or falls into the bottom rows on its own);
## a new filter is one more entry in CATEGORIES.

const LocalSession := preload("res://client/session/local_session.gd")
var session

const Camp := preload("res://logic/camp.gd")
const InkUi := preload("res://client/ink_ui.gd")
const ItemCell := preload("res://client/item_cell.gd")
const ItemIcon := preload("res://client/item_icon.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemText := preload("res://client/item_text.gd")
const PaperDoll := preload("res://client/paper_doll.gd")
const Stats := preload("res://logic/stats.gd")

signal message(text: String)  ## a short line for the screen's status bar
signal changed  ## something was worn, taken off or thrown away (the screen refreshes its other parts)
signal gear_changed  ## rest point: the worn gear changed (the simulation must recompute stats)

const TEXT := {
	"equipment": "Equipment",
	"stash": "Stash", "bag": "Bag",
	"capacity": "%d / %d",
	"money": "Gold  %d",
	"full": "FULL",
	"bag_note": "Found on this trip. Kept when you go home or fall.",
	"search": "Search...",
	"cat_all": "All", "cat_weapon": "Weapon", "cat_armor": "Armor", "cat_trinket": "Trinket", "cat_material": "Material",
	"nothing_yet": "Nothing here yet. Monsters drop gear and materials.",
	"no_match": "Nothing matches.",
	"character": "Character",
	"style": "Fighting style: %s",
	"speed": "Attack speed: %.2f s per light hit, %.2f s per heavy (ATK SPD %+d%%)",
	"weapon_line": "Reach %.1f   Light %.1fx   Heavy %.1fx   Push %.0f   Stun %d",
	"hint_mouse": "Click: details.  Double-click or right-click: wear / take off.  Drag onto a slot to wear, back onto the %s to take off.  Drag the doll to turn it.",
	"hint_touch": "Tap: details. Swipe over the %s to scroll. Use Wear / Take off in the details.",
	"slot_name": "%s",
	"slot_pair": "%s %d",
	"empty_slot": "Nothing worn here.",
	"fits": "%d piece(s) in your %s fit here (marked).",
	"fits_none": "Nothing in your %s fits here.",
	"tier_slot": "%s    Tier %d of %d",
	"compare_with": "Compared with your %s:",
	"compare_empty": "%s is empty: everything is a gain.",
	"same": "No change.",
	"wear": "Wear",
	"wear_in": "Wear as %s",
	"take_off": "Take off",
	"discard": "Discard",
	"discard_sure": "Sure? Discard",
	"discard_ask": "Press again to throw it away for good.",
	"discarded": "Thrown away.",
	"worn": "Worn: %s.",
	"took_off": "Moved to the %s.",
	"stash_full": "The stash is full: discard something first.",
	"bag_full": "The bag is full: discard something first.",
	"trip_over": "The trip is over: nothing can go into the bag.",
	"cannot_wear": "That does not fit there.",
	"material_note": "Used for repairs and camp upgrades.",
	"material_count": "%d in total",
	"close_detail": "Back",
	"worn_tag": "WORN",
	"up": "+%s  (up)", "down": "%s  (down)",
}

## Equipment slot -> filter category.
const CATEGORIES := {
	"weapon": "weapon",
	"hat": "armor", "shirt": "armor", "pants": "armor", "shoes": "armor", "armband": "armor", "back": "armor",
	"necklace": "trinket", "earring": "trinket", "bracelet": "trinket", "ring": "trinket",
}
const CATEGORY_ORDER := ["all", "weapon", "armor", "trinket", "material"]

## "slot:index" -> [column, row] on the 5 x 6 board; the doll fills columns 1-3 of rows 1-4.
const SLOT_PLACES := {
	"earring:0": [0, 0], "earring:1": [1, 0], "necklace:0": [2, 0], "ring:0": [3, 0], "ring:1": [4, 0],
	"hat:0": [0, 1], "shirt:0": [0, 2], "pants:0": [0, 3], "shoes:0": [0, 4],
	"armband:0": [4, 1], "bracelet:0": [4, 2], "bracelet:1": [4, 3],
	"weapon:0": [1, 5], "back:0": [3, 5],
}
const BOARD_COLUMNS := 5
const BOARD_ROWS := 6

## Per layout mode: cell size, gap, detail panel width (wide/compact) or height (portrait), and the
## height of the filter/action buttons (touch targets: see the style guide, section 7).
const SIZES := {
	InkUi.WIDE: {"cell": 60.0, "gap": 6.0, "detail": 340.0, "button": 40.0},
	InkUi.COMPACT: {"cell": 56.0, "gap": 4.0, "detail": 300.0, "button": 56.0},  # 56 units = 44 pt on a 390 pt tall phone
	InkUi.PORTRAIT: {"cell": 48.0, "gap": 4.0, "detail": 176.0, "button": 48.0},
}

var store_label_override := ""
var profile
var run = null
var rules
var camp
var combat
var mode := InkUi.WIDE
var touch_hints := false

var doll  ## PaperDoll
var slot_cells: Dictionary = {}  ## "slot:index" -> ItemCell
var bag_cells: Array = []  ## ItemCells in the grid, in order

var _fashion_slot: Button
var _fashion_caption: Label
var _fashion_toggle: CheckBox
var _fashion_pending := false
var _board: Control
var _bag_box: VBoxContainer
var _bag_title: HBoxContainer
var _capacity: Label
var _search: LineEdit
var _category := "all"
var _category_buttons: Dictionary = {}
var _grid_scroll: ScrollContainer
var _scroll_finger := -1
var _scroll_from := Vector2.ZERO
var _scroll_last := Vector2.ZERO
var _scroll_moved := false
var _scroll_cell: Control
var _grid: GridContainer
var _grid_note: Label
var _money: Label
var _detail_panel: PanelContainer
var _detail: VBoxContainer
var _actions: HFlowContainer  ## the selected piece's buttons, pinned under the (scrolling) details
var _board_title: Control
var _layout_box: BoxContainer
var _sheet_open := false

## What is selected: {"kind": "slot", "slot": id, "index": i} / {"kind": "item", "item": Item} /
## {"kind": "material", "id": id} / {} (nothing: the detail shows the character).
var selection: Dictionary = {}
var _pending_discard = null  ## the Item a first Discard press is waiting to confirm


func setup(player_profile, trip, item_rules, camp_data, combat_data, command_session = null) -> void:
	session = command_session if command_session != null else LocalSession.for_menu(player_profile, item_rules, camp_data, trip)
	if session.has_signal("ownership_changed") and not session.ownership_changed.is_connected(refresh): session.ownership_changed.connect(refresh)
	if session.has_signal("command_completed") and not session.command_completed.is_connected(_online_command_done): session.command_completed.connect(_online_command_done)
	profile = player_profile
	run = trip
	rules = item_rules
	camp = camp_data
	combat = combat_data
	touch_hints = DisplayServer.is_touchscreen_available()
	_build()
	visibility_changed.connect(func() -> void: _scroll_finger = -1)
	refresh()


func store():
	return profile.stash if run == null else run.bag


func store_name() -> String:
	return store_label_override if not store_label_override.is_empty() else (TEXT["stash"] if run == null else TEXT["bag"])


# ---------------------------------------------------------------- building

func _build() -> void:
	_board = Control.new()
	_board.name = "Board"
	doll = PaperDoll.new()
	doll.name = "PaperDoll"
	_board.add_child(doll)
	var placed := 0
	for slot in rules.slots:
		for index in int(slot["count"]):
			var key := "%s:%d" % [slot["id"], index]
			var cell: Control = ItemCell.new()
			cell.kind = "slot"
			cell.slot_id = str(slot["id"])
			cell.slot_index = index
			cell.worn_mark = true
			cell.icon_shape = ItemIcon.shape_for(cell.slot_id)
			cell.tooltip_text = _slot_name(cell.slot_id, index)
			cell.touch_scroll_owner = self
			cell.drop_check = _can_drop
			cell.drop_handler = _drop
			_connect_cell(cell)
			_board.add_child(cell)
			slot_cells[key] = cell
			if not SLOT_PLACES.has(key):
				cell.set_meta("extra_place", placed)  # a slot the board has no place for: bottom rows
				placed += 1

	_fashion_slot = Button.new()
	_fashion_slot.name = "FashionSlot"
	_fashion_slot.tooltip_text = "ชุดแฟชั่นที่เลือก · แตะเพื่อเปลี่ยน"
	_fashion_slot.pressed.connect(func(): select({"kind":"fashion"}))
	_board.add_child(_fashion_slot)
	_fashion_toggle=CheckBox.new()
	_fashion_toggle.name="ShowFashion"
	_fashion_toggle.text=""
	_fashion_toggle.alignment=HORIZONTAL_ALIGNMENT_CENTER
	_fashion_caption=InkUi.label("แฟชั่น",InkUi.PAPER,InkUi.FONT_TINY)
	_fashion_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_fashion_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_fashion_toggle.add_child(_fashion_caption)
	_fashion_toggle.add_theme_font_size_override("font_size",12)
	_fashion_toggle.tooltip_text="แสดงแฟชั่นทั้งชุด / ซ่อนเพื่อแสดงชุดต่อสู้ · ปีกไม่เปลี่ยน"
	_fashion_toggle.toggled.connect(func(on: bool): _choose_fashion("fashion_display","on" if on else "off"))
	_board.add_child(_fashion_toggle)
	_bag_box = VBoxContainer.new()
	_bag_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_title = HBoxContainer.new()
	_bag_box.add_child(_bag_title)
	_bag_title.add_child(InkUi.brush_title(store_name()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_title.add_child(spacer)
	_money = Label.new()
	_money.name = "Money"
	InkUi.style_text(_money, InkUi.GOLD)
	_bag_title.add_child(_money)
	_capacity = Label.new()
	_capacity.custom_minimum_size.x = 64.0
	_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bag_title.add_child(_capacity)
	if run != null:
		var note := Label.new()
		note.text = TEXT["bag_note"]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		InkUi.style_text(note, InkUi.MUTED, InkUi.FONT_NOTE)
		_bag_box.add_child(note)
	_search = LineEdit.new()
	_search.placeholder_text = TEXT["search"]
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 40.0
	_search.text_changed.connect(func(_text: String) -> void: _rebuild_grid())
	_bag_box.add_child(_search)
	var filters := HFlowContainer.new()
	InkUi.gap(filters, InkUi.GAP_XS, InkUi.GAP_XS)
	_bag_box.add_child(filters)
	var group := ButtonGroup.new()
	for category in CATEGORY_ORDER:
		var button := Button.new()
		button.text = TEXT["cat_" + category]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = category == _category
		button.custom_minimum_size = Vector2(0.0, 40.0)
		InkUi.text_size(button, InkUi.FONT_SMALL)
		InkUi.icon_button(button, category, 22, true)  # a brass cogwheel per category
		button.pressed.connect(_set_category.bind(category))
		filters.add_child(button)
		_category_buttons[category] = button
		var badge := InkUi.count_badge()  # how many things of this kind are in the bag
		if badge != null:
			button.add_child(badge)
			button.resized.connect(func() -> void: badge.position = Vector2(button.size.x - badge.size.x * 0.7, -badge.size.y * 0.35))
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.set_drag_forwarding(Callable(), _can_drop_on_bag, _drop_on_bag)
	_grid_scroll.resized.connect(_fit_columns)
	_bag_box.add_child(_grid_scroll)
	var grid_holder := VBoxContainer.new()
	grid_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.add_child(grid_holder)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var room := Control.new()  # room above the first row for the selection ring (drawn outside the cell)
	room.custom_minimum_size.y = InkUi.GAP_HUGE
	grid_holder.add_child(room)
	grid_holder.add_child(_grid)
	_grid_note = Label.new()
	_grid_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	InkUi.style_text(_grid_note, InkUi.MUTED)
	_grid_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_holder.add_child(_grid_note)

	_detail_panel = PanelContainer.new()
	_detail_panel.name = "Details"
	var detail_column := VBoxContainer.new()
	_detail_panel.add_child(detail_column)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(_detail, InkUi.GAP_S)
	detail_scroll.add_child(_detail)
	_actions = HFlowContainer.new()
	InkUi.gap(_actions, InkUi.GAP_S, InkUi.GAP_S)
	detail_column.add_child(_actions)
	set_mode(mode, true)


func _connect_cell(cell: Control) -> void:
	cell.tapped.connect(_on_tapped)
	cell.activated.connect(_on_activated)
	cell.long_pressed.connect(_on_long_pressed)


## Lays the page out for a screen mode (InkUi.WIDE / COMPACT / PORTRAIT).
func set_mode(new_mode: String, force: bool = false) -> void:
	if new_mode == mode and not force:
		return
	mode = new_mode
	touch_hints = DisplayServer.is_touchscreen_available() or mode != InkUi.WIDE
	_scroll_finger = -1
	_grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	InkUi.inventory_scrollbar(_grid_scroll.get_v_scroll_bar(), mode != InkUi.WIDE)
	if _layout_box != null:
		for part in [_board_holder(), _bag_box, _detail_panel]:
			if part.get_parent() != null:
				part.get_parent().remove_child(part)
		_layout_box.queue_free()
	var sizes: Dictionary = SIZES[mode]
	_layout_board(sizes["cell"], sizes["gap"])
	for category in _category_buttons:
		_category_buttons[category].custom_minimum_size.y = sizes["button"]
	_search.custom_minimum_size.y = sizes["button"]
	var board_holder := _board_holder()
	_board_title.visible = mode == InkUi.WIDE  # small screens need the height for the slots
	if mode == InkUi.PORTRAIT:
		var column := VBoxContainer.new()
		InkUi.gap(column, InkUi.GAP_M)
		_layout_box = column
		board_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_panel.size_flags_horizontal = Control.SIZE_FILL
		column.add_child(board_holder)
		column.add_child(_detail_panel)
		column.add_child(_bag_box)
	else:
		var row := HBoxContainer.new()
		InkUi.gap(row, InkUi.GAP_XL)
		_layout_box = row
		board_holder.size_flags_horizontal = Control.SIZE_FILL
		_detail_panel.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(board_holder)
		row.add_child(_bag_box)
		row.add_child(_detail_panel)
	_layout_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_layout_box)
	_size_detail()
	_fit_columns.call_deferred()


func _board_holder() -> Control:
	var holder: Control = _board.get_parent()
	if holder == null:
		holder = PanelContainer.new()
		holder.name = "EquipmentPanel"
		var column := VBoxContainer.new()
		holder.add_child(column)
		_board_title = InkUi.brush_title(TEXT["equipment"])
		column.add_child(_board_title)
		var center := CenterContainer.new()
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(center)
		center.add_child(_board)
		return holder
	return holder.get_parent().get_parent()  # board -> center -> column -> panel


func _layout_board(cell_size: float, gap: float) -> void:
	var step := cell_size + gap
	var extra_rows := ceili(float(_extra_slot_count()) / float(BOARD_COLUMNS))
	_board.custom_minimum_size = Vector2(BOARD_COLUMNS * step - gap, (BOARD_ROWS + extra_rows) * step - gap)
	doll.position = Vector2(step, step)
	doll.size = Vector2(3.0 * step - gap, 4.0 * step - gap)
	for key in slot_cells:
		var cell: Control = slot_cells[key]
		var place: Array = SLOT_PLACES.get(key, [])
		if place.is_empty():
			var n: int = cell.get_meta("extra_place", 0)
			place = [n % BOARD_COLUMNS, BOARD_ROWS + n / BOARD_COLUMNS]
		cell.position = Vector2(place[0] * step, place[1] * step)
		cell.size = Vector2(cell_size, cell_size)
	_fashion_toggle.position=Vector2(4*step,4*step)
	_fashion_toggle.size=Vector2(cell_size,cell_size)
	_fashion_caption.position=Vector2(0,cell_size-18)
	_fashion_caption.size=Vector2(cell_size,18)
	_fashion_slot.position=Vector2(4*step,5*step)
	_fashion_slot.size=Vector2(cell_size,cell_size)
	_fashion_slot.add_theme_constant_override("icon_max_width",int(cell_size-8))
	for cell in bag_cells:
		cell.custom_minimum_size = Vector2(cell_size, cell_size)


func _extra_slot_count() -> int:
	var count := 0
	for key in slot_cells:
		if not SLOT_PLACES.has(key):
			count += 1
	return count


## Portrait: the details sit between the slots and the bag; a held piece opens them as a sheet over
## the bag (Back closes it).
func _size_detail() -> void:
	var sizes: Dictionary = SIZES[mode]
	if mode == InkUi.PORTRAIT:
		_detail_panel.custom_minimum_size = Vector2(0.0, sizes["detail"])
		_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if _sheet_open else Control.SIZE_FILL
		_bag_box.visible = not _sheet_open
	else:
		_bag_box.visible = true
		_detail_panel.custom_minimum_size = Vector2(sizes["detail"], 0.0)
		_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _fit_columns() -> void:
	if _grid_scroll == null:
		return
	var step: float = SIZES[mode]["cell"] + SIZES[mode]["gap"]
	var width := _grid_scroll.size.x - _grid_scroll.get_v_scroll_bar().size.x  # leave room for the scroll bar
	_grid.columns = maxi(4, int((width + SIZES[mode]["gap"]) / step))


## Swipe anywhere over item tiles. Selection happens on release, never during a scroll.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_scroll_finger = -1
		_scroll_cell = null


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _grid_scroll == null:
		_scroll_finger = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _scroll_finger < 0:
			if not _grid_scroll.get_global_rect().has_point(event.position):
				return
			# Leave the scrollbar itself to its native GUI handler.
			if _grid_scroll.get_v_scroll_bar().get_global_rect().has_point(event.position):
				return
			_scroll_finger = event.index
			_scroll_from = event.position
			_scroll_last = event.position
			_scroll_moved = false
			_scroll_cell = null
			for cell in bag_cells:
				if cell.get_global_rect().has_point(event.position):
					_scroll_cell = cell
					break
			get_viewport().set_input_as_handled()
		elif (not event.pressed or event.canceled) and event.index == _scroll_finger:
			var picked := _scroll_cell
			var tap: bool = not event.canceled and not _scroll_moved
			_scroll_finger = -1
			_scroll_cell = null
			if tap and is_instance_valid(picked):
				_on_tapped(picked)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _scroll_finger:
		if event.position.distance_to(_scroll_from) > 10.0:
			_scroll_moved = true
		if _scroll_moved:
			var scale_y := maxf(_grid_scroll.get_global_transform_with_canvas().get_scale().y, 0.01)
			_grid_scroll.scroll_vertical += roundi((_scroll_last.y - event.position.y) / scale_y)
		_scroll_last = event.position
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- showing the state

## Shows the current state of the profile / run (call after anything changes).
func refresh() -> void:
	if not is_instance_valid(_board):
		return
	if selection.get("kind", "") == "item" and not store().items.has(selection["item"]):
		selection = {}
	for key in slot_cells:
		var cell: Control = slot_cells[key]
		var item = profile.loadout.item_at(cell.slot_id, cell.slot_index)
		_show_item(cell, item)
		if item == null:
			cell.icon_shape = ItemIcon.shape_for(cell.slot_id)
	_refresh_fashion()
	doll.dress(profile.loadout, profile.loadout.weapon_style(combat.styles.keys()), rules.catalog, profile.appearance)
	var bag = store()
	_capacity.text = TEXT["capacity"] % [bag.slots_used(), bag.capacity]
	if bag.free_slots() <= 0:
		_capacity.text += "  " + TEXT["full"]
	InkUi.style_text(_capacity, InkUi.BAD if bag.free_slots() <= 0 else InkUi.PAPER)
	_money.text = TEXT["money"] % bag.gold
	_rebuild_grid()


func _show_item(cell: Control, item) -> void:
	cell.item = item
	cell.icon_texture = ItemAssets.icon(item, rules.catalog)
	if item == null:
		cell.tier = -1
		cell.level = 0
		cell.wear_warning = 0
		cell.frame_color = InkUi.BORDER
	else:
		var color: Color = ItemText.tier_color(item, rules)
		cell.tier = item.tier
		cell.level = item.refine_level if item.refine_level > 0 else item.level
		cell.frame_color = color
		cell.icon_fill = color
		cell.icon_shape = ItemIcon.shape_for(item.slot, item.weapon_type)
		cell.wear_warning = 2 if item.is_broken_down() else (1 if item.durability_ratio() < rules.durability_full_above else 0)
		cell.tooltip_text = _title(item)
	cell.queue_redraw()


func _set_category(category: String) -> void:
	_category = category
	_rebuild_grid()


## Rebuilds the bag grid: equipment (sorted by kind, best first), then material stacks, then the free cells.
func _rebuild_grid() -> void:
	for cell in bag_cells:
		_grid.remove_child(cell)
		cell.queue_free()
	bag_cells.clear()
	var bag = store()
	var needle := _search.text.strip_edges().to_lower()
	var filtering := needle != "" or _category != "all"
	var entries: Array = []
	for item in bag.items:
		if _category != "all" and CATEGORIES.get(item.slot, "armor") != _category:
			continue
		if needle != "" and not _search_text(item).contains(needle):
			continue
		entries.append(item)
	var slot_order: Array = rules.slots.map(func(slot: Dictionary) -> String: return str(slot["id"]))
	entries.sort_custom(func(a, b) -> bool:
		var ca: int = CATEGORY_ORDER.find(CATEGORIES.get(a.slot, "armor"))
		var cb: int = CATEGORY_ORDER.find(CATEGORIES.get(b.slot, "armor"))
		if ca != cb:
			return ca < cb
		if a.slot != b.slot:
			return slot_order.find(a.slot) < slot_order.find(b.slot)
		if a.tier != b.tier:
			return a.tier > b.tier
		return a.level > b.level)
	var cell_size: float = SIZES[mode]["cell"]
	for item in entries:
		var cell := _new_bag_cell(cell_size)
		cell.kind = "item"
		cell.slot_id = item.slot
		cell.item_index = bag.items.find(item)
		_show_item(cell, item)
	if _category == "all" or _category == "material":
		for id in bag.materials:
			var name: String = str(camp.materials.get(id, {}).get("name", id))
			if needle != "" and not name.to_lower().contains(needle):
				continue
			var left: int = bag.material_count(id)
			var stack: int = bag.stack_size(id)
			while left > 0:
				var cell := _new_bag_cell(cell_size)
				cell.kind = "material"
				cell.material_id = str(id)
				cell.count = mini(left, stack)
				cell.icon_shape = ItemIcon.shape_for(str(id))
				cell.icon_fill = _material_color(str(id))
				cell.frame_color = InkUi.MUTED
				cell.tooltip_text = name
				left -= cell.count
	if not filtering:
		for i in maxi(0, bag.free_slots()):
			var cell := _new_bag_cell(cell_size)
			cell.kind = "empty"
	_update_counts(bag)
	_grid_note.text = ""
	if bag_cells.is_empty() or (not filtering and bag.items.is_empty() and bag.materials.is_empty()):
		_grid_note.text = TEXT["no_match"] if filtering else TEXT["nothing_yet"]
	_update_marks()


## The count badge on each filter button (whatever the filter shows now).
func _update_counts(bag) -> void:
	var counts := {"all": 0, "material": bag.materials.size()}
	for item in bag.items:
		var category: String = CATEGORIES.get(item.slot, "armor")
		counts[category] = int(counts.get(category, 0)) + 1
		counts["all"] += 1
	counts["all"] += bag.materials.size()
	for category in _category_buttons:
		var button: Button = _category_buttons[category]
		if button.get_child_count() > 0:
			button.get_child(0).set_count(int(counts.get(category, 0)))


func _new_bag_cell(cell_size: float) -> Control:
	var cell: Control = ItemCell.new()
	cell.custom_minimum_size = Vector2(cell_size, cell_size)
	cell.touch_scroll_owner = self
	cell.drop_check = _can_drop
	cell.drop_handler = _drop
	_connect_cell(cell)
	_grid.add_child(cell)
	bag_cells.append(cell)
	return cell


func _search_text(item) -> String:
	return ("%s %s %s %s" % [_title(item), _slot_name(item.slot, -1), ItemText.stats_line(item, rules), str(rules.tiers[item.tier]["color"])]).to_lower()


## Updates the selected / highlighted / dimmed marks without rebuilding anything (so a press that
## selects never destroys the cell under the finger, and a double-click or a drag can follow it).
func _update_marks() -> void:
	var kind: String = selection.get("kind", "")
	var fits_slot := ""
	if kind == "item":
		fits_slot = selection["item"].slot
	elif kind == "slot":
		fits_slot = selection["slot"]
	for key in slot_cells:
		var cell: Control = slot_cells[key]
		cell.selected = kind == "slot" and cell.slot_id == selection["slot"] and cell.slot_index == selection["index"]
		cell.highlighted = kind == "item" and cell.slot_id == fits_slot
		cell.dimmed = false
	for cell in bag_cells:
		cell.selected = (kind == "item" and cell.item == selection["item"]) or (kind == "material" and cell.kind == "material" and cell.material_id == selection["id"])
		cell.highlighted = kind == "slot" and cell.kind == "item" and cell.slot_id == fits_slot
		cell.dimmed = kind == "slot" and cell.kind != "empty" and cell.slot_id != fits_slot
	_build_detail()


# ---------------------------------------------------------------- input from the cells

func _on_tapped(cell: Control) -> void:
	var picked := _selection_for(cell)
	if picked.is_empty() or picked == selection:
		select({})  # tapping the selected thing again (or a free cell) clears the selection
	else:
		select(picked)


func _on_long_pressed(cell: Control) -> void:
	var picked := _selection_for(cell)
	if picked.is_empty():
		return
	selection = picked
	_pending_discard = null
	_sheet_open = mode == InkUi.PORTRAIT
	_size_detail()
	_update_marks()


## Wearing / taking off rebuilds the cells, so it runs after the cell's input handling has finished.
func _on_activated(cell: Control) -> void:
	_activate.call_deferred(cell)


func _activate(cell: Control) -> void:
	if not is_instance_valid(cell):
		return
	if cell.kind == "item" and cell.item != null:
		wear(cell.item)
	elif cell.kind == "slot" and cell.item != null:
		take_off(cell.slot_id, cell.slot_index)


func _selection_for(cell: Control) -> Dictionary:
	match cell.kind:
		"slot":
			return {"kind": "slot", "slot": cell.slot_id, "index": cell.slot_index}
		"item":
			return {"kind": "item", "item": cell.item}
		"material":
			return {"kind": "material", "id": cell.material_id}
	return {}


func select(picked: Dictionary) -> void:
	selection = picked
	_pending_discard = null
	if picked.is_empty() and _sheet_open:
		_sheet_open = false
		_size_detail()
	_update_marks()


func _can_drop(target: Control, data: Dictionary) -> bool:
	var source: Control = data["cell"]
	if not is_instance_valid(source) or source == target or source.item == null:
		return false
	if target.kind == "slot":
		return source.kind == "item" and source.item.slot == target.slot_id
	return source.kind == "slot"  # a worn piece onto the bag / stash: take it off


func _drop(target: Control, data: Dictionary) -> void:
	_apply_drop.call_deferred(target, data)


func _apply_drop(target: Control, data: Dictionary) -> void:
	var source: Control = data["cell"]
	if not is_instance_valid(source) or not is_instance_valid(target) or source.item == null:
		return
	if target.kind == "slot":
		wear(source.item, target.slot_index)
	else:
		take_off(source.slot_id, source.slot_index)


func _can_drop_on_bag(_at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("cell") or not is_instance_valid(data["cell"]):
		return false
	return data["cell"].kind == "slot" and data["cell"].item != null


func _drop_on_bag(_at: Vector2, data: Variant) -> void:
	take_off.call_deferred(data["cell"].slot_id, data["cell"].slot_index)


# ---------------------------------------------------------------- actions (all through logic/)

## Wears `item` from the stash / bag; `slot_index` -1 = the first free position of a paired slot.
func wear(item, slot_index: int = -1) -> bool:
	var bag = store()
	var index: int = bag.items.find(item)
	if index < 0:
		return false
	if slot_index < 0:
		slot_index = _free_slot_index(item)
	var response: Dictionary = session.command({"type": "equip", "item": item.id, "source": "stash" if run == null else "bag", "index": slot_index})
	if response.get("pending", false):
		message.emit("กำลังรอเซิร์ฟเวอร์…"); return false
	var done: bool = response.ok
	if not done:
		message.emit(TEXT["cannot_wear"])
		Audio.play_ui("error")
		return false
	message.emit(TEXT["worn"] % _title(item))
	selection = {"kind": "slot", "slot": item.slot, "index": slot_index}
	_after_change()
	if run != null:
		gear_changed.emit()
	Audio.play_ui("equip")
	return true


## Takes a worn piece off into the stash (camp) or the run bag (rest point; Run.unequip_to_bag decides).
func take_off(slot_id: String, slot_index: int) -> bool:
	var item = profile.loadout.item_at(slot_id, slot_index)
	if item == null:
		return false
	var result: Dictionary = session.command({"type": "unequip", "slot": slot_id, "destination": "stash" if run == null else "bag", "index": slot_index})
	if result.get("pending", false):
		message.emit("กำลังรอเซิร์ฟเวอร์…"); return false
	if not result["ok"]:
		message.emit(TEXT["stash_full"] if run == null and result["error"] == "bag_full" else str(TEXT.get(result["error"], TEXT["cannot_wear"])))
		return false
	message.emit(TEXT["took_off"] % store_name().to_lower())
	selection = {"kind": "item", "item": item}
	_after_change()
	if run != null:
		gear_changed.emit()
	Audio.play_ui("unequip")
	return true


## Throws a stash / bag piece away; the first call only asks (returns false), the second does it.
func discard(item) -> bool:
	if _pending_discard != item:
		_pending_discard = item
		message.emit(TEXT["discard_ask"])
		_build_detail()
		return false
	var index: int = store().items.find(item)
	if index < 0:
		return false
	var result: Dictionary = session.command({"type": "discard", "item": item.id, "source": "stash" if run == null else "bag"})
	if result.get("pending", false):
		message.emit("กำลังรอเซิร์ฟเวอร์…")
		return false
	if not result.get("ok", false): return false
	_pending_discard = null
	selection = {}
	message.emit(TEXT["discarded"])
	_after_change()
	Audio.play_ui("discard")
	return true


func _after_change() -> void:
	_pending_discard = null
	refresh()
	changed.emit()


## Which position of a paired slot (two rings...) a new piece takes: the first empty one, else the first.
func _free_slot_index(item) -> int:
	var slot: Dictionary = rules.slot(item.slot)
	for index in int(slot.get("count", 1)):
		if profile.loadout.item_at(item.slot, index) == null:
			return index
	return 0


# ---------------------------------------------------------------- the detail panel

func _build_detail() -> void:
	if _detail == null:
		return
	for holder in [_detail, _actions]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
	match selection.get("kind", ""):
		"item":
			_detail_item(selection["item"], false)
		"slot":
			var item = profile.loadout.item_at(selection["slot"], selection["index"])
			if item != null:
				_detail_item(item, true)
			else:
				_detail_empty_slot(selection["slot"], selection["index"])
		"material":
			_detail_material(selection["id"])
		"fashion":
			_detail_fashion()
		_:
			_detail_character()


func _detail_header(cell_source, title: String, color: Color, subtitle: String) -> void:
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_L)
	_detail.add_child(row)
	if cell_source != null:
		# Wrapped text can grow the header, but the equipment frame stays square.
		cell_source.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cell_source.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(cell_source)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var name_label := _wrapped(title, color, InkUi.FONT_ITEM)
	name_label.custom_minimum_size.x = 0.0
	InkUi.style_text(name_label, color, InkUi.FONT_ITEM, 3, InkUi.INK)
	words.add_child(name_label)
	if subtitle != "":
		var subtitle_label := _wrapped(subtitle, InkUi.MUTED, InkUi.FONT_NOTE)
		subtitle_label.custom_minimum_size.x = 0.0
		words.add_child(subtitle_label)
	if not selection.is_empty():
		var back := _button(TEXT["close_detail"], select.bind({}))
		back.name = "Back"
		InkUi.close_button(back)
		back.custom_minimum_size = Vector2(52.0, 52.0)
		back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(back)


func _preview_cell(item) -> Control:
	var cell: Control = ItemCell.new()
	cell.kind = "item"
	cell.custom_minimum_size = Vector2.ONE * (64.0 if mode == InkUi.WIDE else 48.0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_item(cell, item)
	return cell


func _detail_item(item, worn: bool) -> void:
	var where := _slot_name(item.slot, selection.get("index", -1) if worn else -1)
	_detail_header(_preview_cell(item), _title(item), ItemText.tier_color(item, rules),
		TEXT["tier_slot"] % [where, item.tier + 1, rules.tiers.size()] + ("   " + TEXT["worn_tag"] if worn else ""))
	_detail.add_child(ItemText.base_label(item, rules))
	for index in item.substats.size():
		_detail.add_child(_line("   " + ItemText.substat_text(item, rules, index), InkUi.SUBSTAT, InkUi.FONT_LABEL))
	_detail.add_child(_line("Upgrade %d/%d" % [item.upgrade_count, int(rules.upgrade.get("max_attempts", 5))], InkUi.MUTED, InkUi.FONT_SMALL))
	_detail.add_child(_line(ItemText.durability_text(item, rules), ItemText.durability_color(item, rules), InkUi.FONT_SMALL))
	var worn_ids: Array = profile.loadout.items().map(func(piece): return piece.item_id)
	var set_line := ItemText.set_text(item, rules, worn_ids)
	if not set_line.is_empty():
		_detail.add_child(_wrapped(set_line, InkUi.GOLD, InkUi.FONT_SMALL))

	if not worn:
		_compare_lines(item)
	var actions := _actions
	if worn:
		var off := _button(TEXT["take_off"], take_off.bind(selection["slot"], selection["index"]))
		off.name = "TakeOff"
		var blocked := ""  # why Take off is greyed out (the rule itself is in logic/, this only explains it)
		if run != null and run.died:
			blocked = "trip_over"
		elif store().free_slots() < 1:
			blocked = "stash_full" if run == null else "bag_full"
		off.disabled = blocked != ""
		actions.add_child(off)
		var reason: Label = null  # shown at the top so it is never scrolled away
		if blocked != "":
			reason = _wrapped(TEXT[blocked], InkUi.BAD)
		if reason != null:
			_detail.add_child(reason)
			_detail.move_child(reason, 1)
	else:
		var count := int(rules.slot(item.slot).get("count", 1))
		if count <= 1:
			var on := _button(TEXT["wear"], wear.bind(item, 0))
			on.name = "Wear"
			actions.add_child(on)
		else:
			for index in count:
				var on := _button(TEXT["wear_in"] % _slot_name(item.slot, index), wear.bind(item, index))
				on.name = "Wear%d" % index
				actions.add_child(on)
		var sure: bool = _pending_discard == item
		var drop := _button(TEXT["discard_sure"] if sure else TEXT["discard"], discard.bind(item))
		drop.name = "Discard"
		if sure:
			InkUi.style_text(drop, InkUi.BAD)
		actions.add_child(drop)


## "Compared with your Hat: HP +150 (up), DEF -3 (down)" against what the piece would replace.
func _compare_lines(item) -> void:
	var index := _free_slot_index(item)
	var worn = profile.loadout.item_at(item.slot, index)
	var count := int(rules.slot(item.slot).get("count", 1))
	var where := _slot_name(item.slot, index if count > 1 else -1)
	if worn == null:
		_detail.add_child(_wrapped(TEXT["compare_empty"] % where, InkUi.GOOD))
		return
	_detail.add_child(_line(TEXT["compare_with"] % where, InkUi.MUTED, InkUi.FONT_SMALL))
	var new_totals: Dictionary = item.stat_totals(rules)
	var old_totals: Dictionary = worn.stat_totals(rules)
	var any := false
	for stat in rules.stat_ids:
		var delta := float(new_totals.get(stat, 0.0)) - float(old_totals.get(stat, 0.0))
		if absf(delta) < 0.05:
			continue
		any = true
		var text := "   %s  %s" % [_stat_label(stat), (TEXT["up"] % _number(delta)) if delta > 0.0 else (TEXT["down"] % _number(delta))]
		_detail.add_child(_line(text, InkUi.GOOD if delta > 0.0 else InkUi.BAD, InkUi.FONT_SMALL))
	if not any:
		_detail.add_child(_line("   " + TEXT["same"], InkUi.MUTED, InkUi.FONT_SMALL))


func _detail_empty_slot(slot_id: String, index: int) -> void:
	var cell: Control = ItemCell.new()
	cell.kind = "slot"
	cell.icon_shape = ItemIcon.shape_for(slot_id)
	cell.custom_minimum_size = Vector2.ONE * (64.0 if mode == InkUi.WIDE else 48.0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := int(rules.slot(slot_id).get("count", 1))
	_detail_header(cell, _slot_name(slot_id, index if count > 1 else -1), InkUi.PAPER, TEXT["empty_slot"])
	var fits := 0
	for item in store().items:
		if item.slot == slot_id:
			fits += 1
	_detail.add_child(_wrapped(TEXT["fits"] % [fits, store_name().to_lower()] if fits > 0 else TEXT["fits_none"] % store_name().to_lower(), InkUi.MUTED))


func _detail_material(id: String) -> void:
	var cell: Control = ItemCell.new()
	cell.kind = "material"
	cell.count = store().material_count(id)
	cell.icon_shape = ItemIcon.shape_for(id)
	cell.icon_fill = _material_color(id)
	cell.frame_color = InkUi.MUTED
	cell.custom_minimum_size = Vector2.ONE * (64.0 if mode == InkUi.WIDE else 48.0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_header(cell, str(camp.materials.get(id, {}).get("name", id)), InkUi.PAPER, TEXT["material_count"] % store().material_count(id))
	_detail.add_child(_wrapped(TEXT["material_note"], InkUi.MUTED))


## Nothing selected: the character's fighting style, attack speed and total stats.
func _detail_character() -> void:
	_detail.add_child(InkUi.brush_title(TEXT["character"]))
	var stats := total_stats()
	var weapon_id: String = profile.loadout.weapon_style(combat.styles.keys())
	var weapon_name := str(combat.weapons.get(weapon_id, {}).get("name", weapon_id.capitalize()))
	_detail.add_child(_line(TEXT["style"] % weapon_name, InkUi.GOLD, InkUi.FONT_SECTION))
	if weapon_id=="bow":_detail.add_child(_wrapped("ยิงได้เมื่ออยู่บนพื้น · ไม่มีท่าวิ่งโจมตีหรือกระโดดโจมตี", InkUi.MUTED, InkUi.FONT_NOTE))
	var info: Dictionary = combat.weapon_stats(weapon_id, float(stats.get("ATKSPD", 0.0)))
	if not info.is_empty():
		_detail.add_child(_wrapped(TEXT["speed"] % [info["light_seconds"], info["heavy_seconds"], int(stats.get("ATKSPD", 0.0))], InkUi.PAPER, InkUi.FONT_NOTE))
		_detail.add_child(_wrapped(TEXT["weapon_line"] % [info["reach"], info["light_power"], info["heavy_power"], info["knockback"], info["stun"]], InkUi.MUTED, InkUi.FONT_NOTE))
	var table := GridContainer.new()
	table.columns = 4
	InkUi.gap(table, InkUi.GAP_L, InkUi.GAP_XXS)
	_detail.add_child(table)
	for stat in rules.stat_ids:
		var name_label := _line(_stat_label(stat), InkUi.MUTED, InkUi.FONT_NOTE)
		table.add_child(name_label)
		var value := _line(_number(float(stats.get(stat, 0.0))), InkUi.PAPER, InkUi.FONT_SMALL)
		value.custom_minimum_size.x = 52.0
		table.add_child(value)
	_detail.add_child(_wrapped((TEXT["hint_touch"] if touch_hints else TEXT["hint_mouse"]) % store_name().to_lower(), InkUi.MUTED, InkUi.FONT_CAPTION))


## Worn gear plus camp skills: what the character has (display; the rules are in logic/).
func total_stats() -> Dictionary:
	var totals: Dictionary = Stats.totals(rules, profile.loadout.items())
	var bonus: Dictionary = Camp.skill_bonus(profile, camp)
	for stat in bonus:
		totals[stat] = float(totals.get(stat, 0.0)) + float(bonus[stat])
	return totals


# ---------------------------------------------------------------- small helpers

func _title(item) -> String:
	var weapon_names := {}
	for id in combat.weapons:
		weapon_names[id] = combat.weapons[id]["name"]
	return ItemText.title(item, rules, weapon_names)


func _slot_name(slot_id: String, index: int) -> String:
	var count := int(rules.slot(slot_id).get("count", 1))
	if count > 1 and index >= 0:
		return TEXT["slot_pair"] % [slot_id.capitalize(), index + 1]
	return TEXT["slot_name"] % slot_id.capitalize()


## A material's colour from data/camp/camp.json (the loader gives a Color; a raw [r, g, b] works too).
func _material_color(id: String) -> Color:
	var value = camp.materials.get(id, {}).get("color", InkUi.ICON_FALLBACK)
	if value is Color:
		return value
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]))  # token-ok: a color from data
	return InkUi.ICON_FALLBACK


func _stat_label(stat: String) -> String:
	return str(ItemText.STAT_LABELS.get(stat, stat))


static func _number(value: float) -> String:
	return str(snappedf(value, 0.1)) if absf(value - roundf(value)) > 0.05 else str(int(roundf(value)))


func _line(text: String, color: Color, font_size: int = InkUi.FONT_LABEL) -> Label:
	return InkUi.label(text, color, font_size)


func _wrapped(text: String, color: Color, font_size: int = InkUi.FONT_SMALL) -> Label:
	var label := _line(text, color, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120.0
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96.0, maxf(44.0, SIZES[mode]["button"]))
	button.pressed.connect(func() -> void: callback.call_deferred())  # the press may rebuild this panel
	return button


func _online_command_done(_id: int, result: Dictionary) -> void:
	_fashion_pending=false
	refresh()
	message.emit(preload("res://client/online/online_text.gd").command_message(result))
	_pending_discard = null


func _refresh_fashion() -> void:
	var picked: Dictionary=ItemAssets.cosmetics().resolve(profile.appearance)
	var choice: Dictionary=picked.get("fashion",{})
	var selected := str(choice.get("id","none")) != "none"
	var shown := selected and str(picked.get("fashion_display",{}).get("id","on"))=="on"
	var file := preload("res://client/look_panel.gd").icon_file("fashion",choice) if selected else ""
	_fashion_slot.icon=load(file) if not file.is_empty() else null
	_fashion_slot.expand_icon=true
	_fashion_slot.text="" if _fashion_slot.icon != null else "แฟชั่น"
	_fashion_slot.modulate=Color.WHITE if shown else Color(.65,.65,.65)
	_fashion_slot.tooltip_text="แฟชั่น: "+str(choice.get("name","ยังไม่ได้เลือก"))+(" · แสดง" if shown else " · ซ่อน")
	if _fashion_toggle != null:
		_fashion_toggle.set_pressed_no_signal(shown)
		_fashion_toggle.disabled=not selected or _fashion_pending

func _choose_fashion(part: String, choice: String) -> void:
	if _fashion_pending: return
	var result: Dictionary=session.command({"type":"appearance","part":part,"choice":choice})
	_fashion_pending=bool(result.get("pending",false))
	if _fashion_pending:
		_refresh_fashion()
		return
	if result.get("ok",false):
		refresh()
		changed.emit()
	else:
		_refresh_fashion()
		message.emit(preload("res://client/online/online_text.gd").command_message(result))

func _detail_fashion() -> void:
	_detail.add_child(_line("ชุดแฟชั่น",InkUi.GOLD,InkUi.FONT_HEADING))
	_detail.add_child(_wrapped("เลือกแฟชั่นทั้งชุด หรือปิดเครื่องหมายแฟชั่นเพื่อแสดงชุดต่อสู้ทั้งชุด ปีกแสดงแยกต่างหาก",InkUi.MUTED))
	var grid := GridContainer.new()
	grid.columns=2
	_detail.add_child(grid)
	for choice in ItemAssets.cosmetics().choices.get("fashion",[]):
		if choice.id=="none": continue
		var button := Button.new()
		button.custom_minimum_size=Vector2(72,72)
		button.tooltip_text=str(choice.name)
		var file := preload("res://client/look_panel.gd").icon_file("fashion",choice)
		if not file.is_empty(): InkUi.picture_button(button,load(file),64)
		else: button.text=str(choice.name)
		button.disabled=run != null or _fashion_pending
		button.pressed.connect(_choose_fashion.bind("fashion",str(choice.id)))
		grid.add_child(button)
	if run != null: _detail.add_child(_wrapped("เปลี่ยนชุดได้เมื่อกลับแคมป์",InkUi.MUTED))
