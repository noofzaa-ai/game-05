extends CanvasLayer
## The screens where the player manages their stuff:
##  - at CAMP (the campfire): Inventory (gear_panel.gd: the character, the 14 slots, the stash grid and
##    details), Look (look_panel.gd: face, skin, hair color), Repair, Camp (upgrades, skills)
##  - at a REST POINT in a stage: Inventory (the same window over the trip's bag), and the Rest tab
##    (heal once, go back to camp with the loot, or keep going)
## It shows and changes the player's profile / run through the rules in logic/; it decides nothing.
## The whole menu is drawn in the ink style (ink_ui.gd) and scaled per screen: desktop, phone
## landscape and phone portrait each get a layout that stays readable and touchable.
## EXTENDING: a new tab is one more page in _build_tabs() and a _build_<name>() function.

const LocalSession := preload("res://client/session/local_session.gd")
var session
var backpack_mode := false
var merchant_mode := false
var skill_mode := false
var smith_role := ""
var _upgrade_target := "campfire"
var blacksmith_mode := false
var _repair_detail: VBoxContainer
var _forge_selection := {"Repair": "", "Refine": "", "Upgrade": ""}

const Camp := preload("res://logic/camp.gd")
const GearPanel := preload("res://client/gear_panel.gd")
const InkUi := preload("res://client/ink_ui.gd")
const ItemText := preload("res://client/item_text.gd")
const LookPanel := preload("res://client/look_panel.gd")
const Repair := preload("res://logic/repair.gd")

signal closed
signal retreat_requested  ## rest mode: the player wants to go back to camp with the loot
signal rest_requested  ## rest mode: the player wants to heal here
signal gear_changed  ## rest mode: the worn gear changed (the simulation must recompute stats)
## Journey camp: the bag was just stored in the stash (Journey.bank_bag(), the same rule the stage's
## "B" key used). `summary` is Run.return_to_camp()'s result. The banking is already done when this
## fires; the stage may connect it for its own feedback (HUD loot line, GameState.last_trip).
signal bag_banked(summary: Dictionary)

## Words the player sees in the frame (one place, for translation).
const TEXT := {
	"camp": "Camp", "rest_point": "Rest point",
	"inventory": "Inventory", "look": "Look", "repair": "Repair", "camp_tab": "Camp", "rest": "Rest",
	"close": "Close (Esc)", "close_touch": "Close",
	"stash": "Stash", "bag": "Bag", "gold": "Gold",
	"bank": "Store the bag in the stash", "bank_note": "Safe from death; the bag empties.",
	"bank_empty": "Nothing to store: the bag is empty.",
	"bank_not_here": "This camp cannot store the bag: take it home or keep it with you.",
	"bank_done": "Stored in the stash: %s.", "bank_left": " %d item(s) stayed in the bag: the stash is full.",
	"bank_nothing": "Nothing was stored: the stash is full.",
}

var profile
var camp
var rules
var combat
var run = null  ## set at a rest point: the trip in progress
var rest_point_id := ""
var journey = null  ## at a journey camp: the journey (logic/journey.gd) whose bag can be banked here
var gear  ## the GearPanel (the Inventory tab)
var look  ## the LookPanel (the Look tab; at camp only)
var layout: Dictionary = {}  ## the current InkUi.layout_for() result
var density_override := 0.0  ## > 0: use this screen density instead of the display's (screenshots)

var _pages: Dictionary = {}  ## tab name -> the VBoxContainer holding its rows (the list pages)
var _root: Control  ## everything, scaled to the screen
var _margin: MarginContainer
var _tabs: TabContainer
var _title: Label
var _wallet: Control  ## the resource bar: an icon and a number per currency (tooltip: its name)
var _status: Label
var _close_button: Button
var _built_mode := ""  ## the layout mode the list pages were last built for
var _points_per_unit := 1.0  ## real screen points per menu unit (for touch-size targets)
var _bank_note := ""  ## the last "Stored in the stash" line, shown under the bank button


## Builds the screen. Give `trip` (a Run) and `point_id` to open it at a rest point instead of at camp.
## `trip_journey` is the journey that trip belongs to (for the bank button); when not given it is
## found from GameState.journey if that journey's bag is `trip`.
func setup(player_profile, camp_data, item_rules, combat_data, trip = null, point_id: String = "", trip_journey = null, command_session = null) -> void:
	profile = player_profile
	camp = camp_data
	rules = item_rules
	combat = combat_data
	run = trip
	rest_point_id = point_id
	journey = trip_journey if trip_journey != null else _journey_of(trip)
	session = command_session if command_session != null else LocalSession.for_menu(profile, rules, camp, run, journey)
	if skill_mode:
		set_process_unhandled_key_input(false)
		var skills = preload("res://client/skill_window.gd").new()
		add_child(skills)
		skills.setup(profile, session)
		skills.closed.connect(_close)
		return
	if merchant_mode:
		# Reuse Storage's two-pane drag/touch flow; keep Hub's existing modal lifecycle.
		set_process_unhandled_key_input(false)
		var merchant := preload("res://client/merchant_sell_panel.gd").new()
		add_child(merchant)
		merchant.setup(profile, rules, camp, session)
		merchant.closed.connect(_close)
		return
	if session.has_signal("ownership_changed") and not session.ownership_changed.is_connected(_refresh): session.ownership_changed.connect(_refresh)
	if session.has_signal("command_completed") and not session.command_completed.is_connected(_online_done): session.command_completed.connect(_online_done)
	layer = 20
	_build_frame()
	_build_tabs()
	_apply_layout()
	_refresh()
	if not get_viewport().size_changed.is_connected(_apply_layout):
		get_viewport().size_changed.connect(_apply_layout)


## Opens tab number `index` (0 = Inventory; at camp 1 = Look).
func show_tab(index: int) -> void:
	if _tabs == null: return  # Merchant owns its separate Storage-style panel.
	_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _build_frame() -> void:
	var dim := ColorRect.new()
	dim.color = InkUi.SCRIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = Control.new()
	_root.name = "Menu"
	_root.theme = InkUi.make_theme()
	add_child(_root)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	var panel := PanelContainer.new()
	InkUi.panel(panel, InkUi.window_style())
	_margin.add_child(panel)
	var column := VBoxContainer.new()
	InkUi.gap(column, InkUi.GAP_S)
	panel.add_child(column)

	var header := HBoxContainer.new()
	InkUi.gap(header, InkUi.GAP_XL)
	column.add_child(header)
	_title = Label.new()
	_title.text = "Backpack" if backpack_mode else "Merchant" if merchant_mode else "Blacksmith" if blacksmith_mode else (TEXT["camp"] if run == null else TEXT["rest_point"])
	InkUi.style_text(_title, InkUi.PAPER, InkUi.FONT_TITLE)
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_wallet = PanelContainer.new()  # the resource bar, on a brass plate
	_wallet.name = "Wallet"
	InkUi.panel(_wallet, InkUi.plate(InkUi.PANEL, InkUi.BORDER, 0.5, false, InkUi.CLEAR, 6.0))
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var entries := HBoxContainer.new()
	InkUi.gap(entries, InkUi.GAP_L, InkUi.GAP_XXS)
	_wallet.add_child(entries)
	header.add_child(_wallet)
	_close_button = _button(TEXT["close"], _close, 96.0)
	InkUi.close_button(_close_button)
	_close_button.name = "Close"
	_close_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_close_button)
	if not backpack_mode: InkUi.npc_help(_close_button, "blacksmith" if blacksmith_mode else "merchant" if merchant_mode else "customize")

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_tab: int) -> void: _fit_header())
	column.add_child(_tabs)
	_status = Label.new()
	InkUi.style_text(_status, InkUi.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_status.visible = false  # takes no room until there is something to say


func _build_tabs() -> void:
	if blacksmith_mode or merchant_mode:
		var titles := ["Shop"] if merchant_mode else ["Repair", "Refine", "Upgrade", "Camp"]
		if smith_role == "refine": titles = ["Refine", "Repair", "Camp"]
		elif smith_role == "upgrade": titles = ["Upgrade", "Camp"]
		for title in titles:
			var box := VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			if blacksmith_mode and title in ["Repair", "Refine", "Upgrade"]:
				box.name = title
				_tabs.add_child(box)
			else:
				var scroll := ScrollContainer.new()
				scroll.name = title
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				_tabs.add_child(scroll)
				scroll.add_child(box)
			_pages[title] = box
		return
	gear = GearPanel.new()
	gear.name = TEXT["inventory"]
	gear.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(gear)
	if backpack_mode: gear.store_label_override = "Bag"
	gear.setup(profile, run, rules, camp, combat, session)
	gear.message.connect(_say)
	gear.changed.connect(_refresh.bind(false))
	gear.gear_changed.connect(func() -> void: gear_changed.emit())
	if backpack_mode:
		_tabs.tabs_visible = false
		return
	if run == null:
		look = LookPanel.new()
		look.name = TEXT["look"]
		look.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tabs.add_child(look)
		look.setup(profile, rules, combat, session)
		look.changed.connect(gear.refresh)
		_tabs.tab_changed.connect(func(_tab: int) -> void: look.refresh())  # (worn gear may have changed)
	var titles: Array = ["Repair", "Camp"] if run == null else ["Rest"]
	for title in titles:
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		_pages[title] = box

	if run == null and preload("res://logic/skill_build.gd").enabled():
		var skills := preload("res://client/skill_panel.gd").new()
		skills.name = "Skill"
		_tabs.add_child(skills)
		skills.setup(profile, session)
		_tabs.tab_changed.connect(func(_tab: int): skills.refresh_weapon())


## Fits the menu to the window: picks desktop / phone landscape / phone portrait and scales to it.
func _apply_layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	var logical: Vector2 = viewport.get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var density := DisplayServer.screen_get_scale()
	if window.x <= 0.0 or window.y <= 0.0:
		window = logical
	if density_override > 0.0:
		density = density_override  # (the window's pixels / this = its size in points)
	layout = InkUi.layout_for(window, logical, density)
	_points_per_unit = float(layout["scale"]) * (window.y / maxf(density, 0.01)) / maxf(logical.y, 1.0)
	_root.scale = Vector2.ONE * float(layout["scale"])
	_root.size = layout["size"]
	InkUi.margins(_margin, InkUi.edge_for(layout["mode"]))
	if gear != null: gear.set_mode(layout["mode"])
	if look != null:
		look.set_mode(layout["mode"])
	_fit_header()
	if _built_mode != "" and _built_mode != layout["mode"]:
		_refresh(false)  # the list pages size their buttons per mode (touch targets)


## Phones held upright have no room for the full wallet next to the title: the inventory already
## shows gold, the bag's fill and the material stacks, so the wallet line is left to the other tabs.
## There is no Esc key on a phone, so the close button just says Close.
func _fit_header() -> void:
	if _tabs == null or layout.is_empty():
		return
	var upright: bool = layout["mode"] == InkUi.PORTRAIT
	_wallet.visible = not (upright and _tabs.current_tab == 0)
	# Tab icons: on wide screens; an upright phone has room for the words only.
	var tab_icons := {TEXT["inventory"]: "inventory", TEXT["look"]: "look", "Repair": "repair", "Refine": "repair", "Upgrade": "repair", "Camp": "camp", "Rest": "rest"}
	for i in _tabs.get_tab_count():
		var page := str(_tabs.get_tab_control(i).name)
		_tabs.set_tab_icon(i, null if upright or not tab_icons.has(page) else InkUi.icon(tab_icons[page], 22))
	for entry in _wallet.get_child(0).get_children():
		InkUi.text_size(entry.get_child(1), InkUi.FONT_CAPTION if upright else InkUi.FONT_SMALL)
	InkUi.close_button(_close_button)


## Rebuilds the list tabs from the current state (called after anything changes). The inventory
## refreshes itself when the change came from it (`refresh_gear` false).
func _refresh(refresh_gear: bool = true) -> void:
	if _pages.is_empty() and gear == null:
		return
	for title in _pages:
		var box: VBoxContainer = _pages[title]
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
		call("_build_" + title.to_lower(), box)
	_built_mode = "" if layout.is_empty() else str(layout["mode"])
	if refresh_gear and gear != null:
		gear.refresh()
	_show_wallet()


## Fills the resource bar: the store's fill, gold, then every material, each as an icon and a number.
func _show_wallet() -> void:
	var entries: Control = _wallet.get_child(0)
	for child in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	var store = profile.stash if run == null else run.bag
	var upright: bool = not layout.is_empty() and layout["mode"] == InkUi.PORTRAIT
	var parts: Array = [["bag" if run != null else "stash", TEXT["bag"] if run != null else TEXT["stash"], "%d/%d" % [store.slots_used(), store.capacity], InkUi.PAPER],
		["gold", TEXT["gold"], str(store.gold), InkUi.GOLD]]
	for id in camp.materials:
		parts.append([str(id), str(camp.materials[id]["name"]), str(store.material_count(id)), InkUi.PAPER])
	_wallet.tooltip_text = _wallet_text()
	for part in parts:
		var entry := HBoxContainer.new()
		InkUi.gap(entry, InkUi.GAP_XS)
		entry.tooltip_text = part[1]
		entry.mouse_filter = Control.MOUSE_FILTER_PASS
		var picture := TextureRect.new()
		picture.texture = InkUi.icon(part[0], 20)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(20.0, 20.0) if picture.texture != null else Vector2.ZERO
		entry.add_child(picture)
		var value := InkUi.label(part[2] if picture.texture != null else "%s %s" % [part[1], part[2]], part[3], InkUi.FONT_CAPTION if upright else InkUi.FONT_SMALL)
		entry.add_child(value)
		entries.add_child(entry)


func _say(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _wallet_text() -> String:
	var store = profile.stash if run == null else run.bag
	var parts: Array[String] = ["Gold %d" % store.gold]
	for id in camp.materials:
		parts.append("%s %d" % [camp.materials[id]["name"], store.material_count(id)])
	if run != null:
		parts.insert(0, "Bag %d/%d" % [store.slots_used(), store.capacity])
	else:
		parts.insert(0, "Stash %d/%d" % [store.slots_used(), store.capacity])
	return "   ".join(parts)


# ---------------------------------------------------------------- repair

func _build_repair(box: VBoxContainer) -> void:
	_build_forge(box, "Repair")


func _repair_row(box: VBoxContainer, item, where: String, built: bool) -> bool:
	var quote: Dictionary = Repair.quote(item, camp, Camp.repair_discount(profile, camp))
	if quote["kind"] == "none":
		return false
	var plate := PanelContainer.new()
	InkUi.panel(plate, InkUi.panel_style())
	box.add_child(plate)
	var row := HBoxContainer.new()
	plate.add_child(row)
	var cell := preload("res://client/item_cell.gd").new()
	cell.custom_minimum_size = Vector2(64, 64)
	cell.kind = "item"
	cell.item = item
	cell.icon_texture = preload("res://client/item_assets.gd").icon(item, rules.catalog)
	cell.tier = item.tier
	cell.level = item.refine_level
	cell.frame_color = ItemText.tier_color(item, rules)
	row.add_child(cell)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var select := Button.new()
	select.text = ItemText.title(item, rules) + " · " + where
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.clip_text = true
	select.add_theme_color_override("font_color", ItemText.tier_color(item, rules))
	select.pressed.connect(func(): _show_repair_detail(item, quote, built))
	cell.tapped.connect(func(_cell): _show_repair_detail(item, quote, built))
	detail.add_child(select)
	var bar := ProgressBar.new()
	bar.value = item.durability_ratio() * 100.0
	bar.custom_minimum_size.y = 20
	detail.add_child(bar)
	detail.add_child(InkUi.label(ItemText.cost_text(quote, camp.materials), InkUi.GOLD, InkUi.FONT_SMALL))
	var affordable: bool = profile.stash.can_afford(quote)
	var button := _button("Repair", _repair.bind(item), 100.0)
	button.disabled = not built or not affordable
	row.add_child(button)
	return true


func _show_repair_detail(item, quote: Dictionary, built: bool) -> void:
	if not is_instance_valid(_repair_detail): return
	for child in _repair_detail.get_children():
		_repair_detail.remove_child(child)
		child.queue_free()
	_repair_detail.add_child(InkUi.label(ItemText.title(item, rules), ItemText.tier_color(item, rules), InkUi.FONT_HEADING))
	var art := TextureRect.new()
	art.texture = preload("res://client/item_assets.gd").icon(item, rules.catalog)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(140, 140)
	_repair_detail.add_child(art)
	_repair_detail.add_child(InkUi.label("Durability %d%% → 100%%" % roundi(item.durability_ratio() * 100), InkUi.GOLD))
	_repair_detail.add_child(InkUi.label(ItemText.base_text(item, rules), InkUi.GOLD))
	for index in item.substats.size():
		_repair_detail.add_child(InkUi.label(ItemText.substat_text(item, rules, index), InkUi.SUBSTAT))
	_repair_detail.add_child(InkUi.label("Repair Cost · " + ItemText.cost_text(quote, camp.materials), InkUi.GOLD))
	var action := _button("Repair Item", _repair.bind(item), 180)
	InkUi.make_primary(action)
	action.disabled = not built or not profile.stash.can_afford(quote)
	_repair_detail.add_child(action)


func _repair(item) -> void:
	var result: Dictionary = session.command({"type": "repair", "item": item.id})
	if result.get("pending", false):
		_say("กำลังรอเซิร์ฟเวอร์…"); return
	Audio.play_ui("repair" if result["ok"] else "error")
	_say("Repaired." if result["ok"] else "Cannot repair: %s." % ("พัฒนาฐานรองให้ครบระดับกองไฟก่อน" if result.get("error", "") == "facilities_not_ready" else str(result["error"]).replace("_", " ")))
	_refresh.call_deferred()


func _repair_all() -> void:
	var response: Dictionary = session.command({"type": "repair_all"})
	if response.get("pending", false):
		_say("กำลังรอเซิร์ฟเวอร์…"); return
	var summary: Dictionary = response.get("result", {"repaired": 0, "gold": 0, "skipped": 0})
	Audio.play_ui("repair" if summary["repaired"] > 0 else "error")
	_say("Repaired %d piece(s) for %d gold%s." % [summary["repaired"], summary["gold"], (", skipped %d (not enough)" % summary["skipped"]) if summary["skipped"] > 0 else ""])
	_refresh.call_deferred()


# ---------------------------------------------------------------- camp

func _build_camp(box: VBoxContainer) -> void:
	var choices: Array[String] = ["campfire"]
	for id in camp.facilities: choices.append(str(id))
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 44
	for id in choices:
		picker.add_item("กองไฟ" if id == "campfire" else "Refine Workshop" if id == "workbench" else "Upgrade Workshop" if id == "armory" else str(camp.facilities[id]["name"]))
	picker.select(maxi(0, choices.find(_upgrade_target)))
	picker.item_selected.connect(func(index: int):
		_upgrade_target = choices[index]
		_refresh(false))
	box.add_child(picker)
	if _upgrade_target != "campfire":
		_build_facility_upgrade(box, _upgrade_target)
		return
	box.add_child(_label("กองไฟ · Lv.%d / %d" % [profile.camp_level, camp.max_camp_level()], 0.0, InkUi.HEADING_ACCENT))
	var next_cost: Dictionary = Camp.next_camp_cost(profile, camp)
	if not next_cost.is_empty():
		var unlocks: Array[String] = []
		var next_level := int(profile.camp_level) + 1
		if next_level==int(preload("res://logic/farm.gd").config().required_level):unlocks.append("ปลดล็อกฟาร์ม · แปลงปลูก 4 ช่อง")
		for skill in camp.skills:
			if int(skill["camp_level"]) == next_level: unlocks.append(str(skill["name"]) + ": " + str(skill["summary"]))
		for id in camp.progression_facilities:
			for step in camp.facilities[id]["levels"]:
				if int(step["camp_level"]) == next_level:
					var name := "Refine" if id == "workbench" else "Upgrade" if id == "armory" else "Storage"
					unlocks.append("ปลดเพดาน " + name + " เป็น Lv.%d" % next_level)
		var blockers: Array[String] = Camp.camp_upgrade_blockers(profile, camp)
		var requirements: Array[String] = []
		for id in camp.progression_facilities:
			var title := "Refine" if id == "workbench" else "Upgrade" if id == "armory" else "Storage" if id == "storage" else str(camp.facilities[id]["name"])
			var built := int(profile.facility_levels.get(id, 0))
			requirements.append("%s %s Lv.%d / %d" % ["✓" if built >= profile.camp_level else "•", title, built, profile.camp_level])
		unlocks.append("\nก่อนอัปกองไฟ ต้องพัฒนาฐานรองให้ครบ:\n" + " · ".join(requirements))
		_upgrade_card(box, "campfire", next_level, "กองไฟ", next_cost, "\n".join(unlocks), not blockers.is_empty(), _upgrade_camp)
	else: box.add_child(_label("กองไฟอยู่ที่ระดับสูงสุดแล้ว", 0.0, InkUi.GOOD_TEXT))

func _build_facility_upgrade(box: VBoxContainer, id: String) -> void:
	if id=="farm":
		var open:=preload("res://logic/farm.gd").unlocked(profile)
		box.add_child(_label("ฟาร์ม · ปลดล็อกอัตโนมัติเมื่อกองไฟ Lv.2"+ (" · ใช้งานได้แล้ว" if open else " · ยังล็อกอยู่"),0.0,InkUi.GOLD))
		return
	var facility: Dictionary = camp.facilities[id]
	var level := int(profile.facility_levels.get(id, 0))
	var next := Camp.next_facility_level(profile, camp, id)
	var title := "Refine Workshop" if id == "workbench" else "Upgrade Workshop" if id == "armory" else str(facility["name"])
	box.add_child(_label("%s · Lv.%d" % [title, level], 0.0, InkUi.HEADING_ACCENT))
	if next.is_empty():
		box.add_child(_label("พัฒนาถึงระดับสูงสุดแล้ว", 0.0, InkUi.GOOD_TEXT))
		return
	var kind := "refine" if id == "workbench" else "upgrade" if id == "armory" else id
	var required_camp := maxi(level + 1, int(next["camp_level"]))
	var locked: bool = profile.camp_level < required_camp
	var description := _effects_text(next["effects"], str(facility["function"]))
	if locked: description += "\nต้องอัปกองไฟเป็น Lv.%d ก่อน (ฐานรองห้ามเกินกองไฟ)" % required_camp
	_upgrade_card(box, kind, level + 1, title, next["cost"], description, locked, _upgrade_facility.bind(id))

func _upgrade_card(box: VBoxContainer, kind: String, level: int, title: String, cost: Dictionary, unlocks: String, locked: bool, callback: Callable) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", InkUi.panel_style())
	box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var path := "res://art/ui/facility_levels/%s_lv%d.png" % [kind, mini(level, 3)]
	if ResourceLoader.exists(path):
		var picture := TextureRect.new()
		picture.texture = load(path)
		picture.custom_minimum_size = Vector2(128, 96)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	detail.add_child(_label("%s → Lv.%d" % [title, level], 0.0, InkUi.GOLD))
	if level > 3 and ResourceLoader.exists(path): detail.add_child(_label("ภาพอ้างอิงรูปแบบ Lv.3", 0.0, InkUi.MUTED))
	if not ResourceLoader.exists(path): detail.add_child(_label("ภาพระดับนี้ยังไม่พร้อม", 0.0, InkUi.MUTED))
	detail.add_child(_label("สิ่งที่จะได้รับ\n" + unlocks, 0.0))
	detail.add_child(_label("ใช้: " + ItemText.cost_text(cost, camp.materials), 0.0))
	var button := _button("พัฒนาเป็น Lv.%d" % level, callback, 130.0)
	button.disabled = locked or not profile.stash.can_afford(cost)
	detail.add_child(button)


func _effects_text(effects: Dictionary, function_name: String) -> String:
	var parts: Array[String] = []
	if effects.has("stash_slots"):
		parts.append("stash +%d slots" % int(effects["stash_slots"]))
	if effects.has("bag_slots"):
		parts.append("run bag +%d slots" % int(effects["bag_slots"]))
	if effects.has("repair_discount"):
		parts.append("repairs %d%% cheaper" % int(float(effects["repair_discount"]) * 100.0))
	if parts.is_empty():
		parts.append("unlocks: " + function_name + " (coming soon)")
	return ", ".join(parts)


func _upgrade_camp() -> void:
	var result: Dictionary = session.command({"type": "upgrade_camp"})
	if result.get("pending", false):
		_say("กำลังรอเซิร์ฟเวอร์…"); return
	Audio.play_ui("upgrade" if result["ok"] else "error")
	_say("The camp grew to level %d." % profile.camp_level if result["ok"] else "Cannot upgrade: %s." % str(result["error"]).replace("_", " "))
	_refresh.call_deferred()


func _upgrade_facility(id: String) -> void:
	var result: Dictionary = session.command({"type": "upgrade_facility", "facility": id})
	if result.get("pending", false):
		_say("กำลังรอเซิร์ฟเวอร์…"); return
	Audio.play_ui("upgrade" if result["ok"] else "error")
	_say("%s upgraded." % camp.facilities[id]["name"] if result["ok"] else "Cannot upgrade: %s." % str(result["error"]).replace("_", " "))
	_refresh.call_deferred()


# ---------------------------------------------------------------- rest point

func _build_rest(box: VBoxContainer) -> void:
	var available: bool = run.rest_available(rest_point_id)
	box.add_child(_label("A quiet spot. Sort your bag, wear what you found, patch yourself up, or go home with your loot.", 0.0))
	var heal := _button("Rest here: heal %d%% and refill stamina%s" % [int(camp.rest_heal_fraction * 100.0), "" if available else " (used)"], _request_rest, 420.0)
	heal.disabled = not available
	box.add_child(heal)
	_touch(heal)
	box.add_child(HSeparator.new())
	if journey != null:
		_build_bank(box)
		box.add_child(HSeparator.new())
	box.add_child(_touch(_button("Return to camp with the loot (ends this trip)", _request_retreat, 420.0)))
	box.add_child(_touch(_button("Keep going", _close, 420.0)))


## The journey camp's "Store the bag in the stash" button, its one-line explanation (or why it can't
## be used now) and, after storing, what went in.
func _build_bank(box: VBoxContainer) -> void:
	var reason := bank_block_reason()
	var bank := _touch(_button(TEXT["bank"], _request_bank, 420.0))
	bank.name = "Bank"
	InkUi.icon_button(bank, "stash", 22)
	bank.disabled = reason != ""
	bank.tooltip_text = TEXT["bank_note"] if reason == "" else reason
	box.add_child(bank)
	if _bank_note != "":  # what just went in reads first, then why the button is now off
		var done := _label(_bank_note, 0.0, InkUi.GOOD_TEXT)
		done.name = "BankDone"
		box.add_child(done)
	var note := _label(TEXT["bank_note"] if reason == "" else reason, 0.0, InkUi.TEXT_TAG)
	note.name = "BankNote"
	InkUi.text_size(note, InkUi.FONT_SMALL)
	box.add_child(note)


## Why the bag cannot be stored right now ("" = it can): the camp rules (Journey.can_bank_bag) or an
## empty bag.
func bank_block_reason() -> String:
	if journey == null or not journey.can_bank_bag():
		return TEXT["bank_not_here"]
	if run.bag.is_empty():
		return TEXT["bank_empty"]
	return ""


func _request_bank() -> void:
	if bank_block_reason() != "":
		return
	var response: Dictionary = session.command({"type": "bank_bag"})
	if response.get("pending", false):
		_say("กำลังรอเซิร์ฟเวอร์…"); return
	if not response["ok"]:
		return
	var summary: Dictionary = response["result"]
	_bank_note = bank_summary_text(summary)  # (shown right under the button, not in the bottom status line)
	_say("")
	Audio.play_ui("select" if int(summary.get("items", 0)) + int(summary.get("gold", 0)) > 0 or not summary.get("materials", {}).is_empty() else "error")
	bag_banked.emit(summary)
	_refresh.call_deferred()  # the bag grid and the wallet empty out


## "Stored in the stash: 3 items, 55 gold, 4 materials." (+ what stayed behind when the stash was full).
static func bank_summary_text(summary: Dictionary) -> String:
	var parts: Array[String] = []
	var items := int(summary.get("items", 0))
	if items > 0:
		parts.append("%d item%s" % [items, "" if items == 1 else "s"])
	if int(summary.get("gold", 0)) > 0:
		parts.append("%d gold" % int(summary["gold"]))
	var pieces := 0
	for id in summary.get("materials", {}):
		pieces += int(summary["materials"][id])
	if pieces > 0:
		parts.append("%d material%s" % [pieces, "" if pieces == 1 else "s"])
	var text: String = TEXT["bank_nothing"] if parts.is_empty() else TEXT["bank_done"] % ", ".join(parts)
	if int(summary.get("left_items", 0)) > 0 and not parts.is_empty():
		text += TEXT["bank_left"] % int(summary["left_items"])
	return text


## The journey a rest-point trip belongs to (GameState.journey when its bag is `trip`), else null.
func _journey_of(trip):
	if trip == null:
		return null
	var state: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() is SceneTree else null
	if state == null or state.get("journey") == null:
		return null
	return state.journey if state.journey.run == trip else null


func _request_rest() -> void:
	rest_requested.emit()
	_say("You feel better.")
	_refresh.call_deferred()


func _request_retreat() -> void:
	retreat_requested.emit()
	queue_free()


# ---------------------------------------------------------------- widgets

## A row of a list tab: its parts wrap onto the next line when the screen is narrow (phone upright).
func _row() -> HFlowContainer:
	var row := HFlowContainer.new()
	InkUi.gap(row, InkUi.GAP_L, InkUi.GAP_XS)
	return row


## The width a list tab's content can use (in menu units).
func _content_width() -> float:
	return (layout["size"].x - 80.0) if not layout.is_empty() else 1200.0


## A label that wraps; `min_width` 0 = as wide as the row allows.
func _label(text: String, min_width: float, color: Color = InkUi.TEXT_PLAIN, _italic: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if min_width > 0.0:
		label.custom_minimum_size.x = minf(min_width, _content_width())
	else:
		label.custom_minimum_size.x = minf(160.0, _content_width())
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.style_text(label, color)
	return label


## One line describing an item: tier-colored name, stats and wear.
func _item_label(item) -> Control:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var weapon_names := {}
	for id in combat.weapons:
		weapon_names[id] = combat.weapons[id]["name"]
	var title := _label(ItemText.title(item, rules, weapon_names), 0.0, ItemText.tier_color(item, rules))
	holder.add_child(title)
	var detail := _label("%s   %s" % [ItemText.stats_line(item, rules), ItemText.durability_text(item, rules)], 0.0, ItemText.durability_color(item, rules))
	InkUi.text_size(detail, InkUi.FONT_TINY)
	holder.add_child(detail)
	return holder


## Makes a button at least 44 pt of real screen tall on a phone (the menu is scaled down there; on a
## mouse screen 44 menu units) and returns it.
func _touch(button: Button) -> Button:
	var phone: bool = not layout.is_empty() and layout["mode"] != InkUi.WIDE
	button.custom_minimum_size.y = ceilf(maxf(44.0, 44.0 / maxf(_points_per_unit, 0.1))) if phone else 44.0
	return button


func _button(text: String, callback: Callable, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long button text wraps on a narrow screen
	button.custom_minimum_size = Vector2(minf(min_width, _content_width()), 44.0)
	button.pressed.connect(callback)
	return button


func _online_done(_id: int, result: Dictionary) -> void:
	if merchant_mode: _refresh(false)
	_say(preload("res://client/online/online_text.gd").command_message(result))


func _build_refine(box: VBoxContainer) -> void:
	_build_forge(box, "Refine")

func _build_upgrade(box: VBoxContainer) -> void:
	_build_forge(box, "Upgrade")

func _build_forge(box: VBoxContainer, mode: String) -> void:
	var selector := preload("res://client/forge_selection.gd").new()
	selector.touch_minimum = maxf(48, ceilf(44.0 / maxf(_points_per_unit, 0.1)))
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(selector)
	selector.item_selected.connect(func(id: String): _forge_selection[mode] = id)
	selector.setup(profile, rules, mode, str(_forge_selection[mode]), session, camp)


func _build_shop(box: VBoxContainer) -> void:
	var shop := preload("res://client/shop_panel.gd").new()
	box.add_child(shop)
	shop.message.connect(_say)
	shop.changed.connect(_refresh.bind(false))
	shop.setup(profile, rules, camp, session)
