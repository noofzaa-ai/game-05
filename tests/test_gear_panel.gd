extends RefCounted
## Tests the inventory window (client/gear_panel.gd inside the camp / rest-point screen) the way a
## player uses it: real mouse events pushed into the viewport (double-click, right-click, drag and
## drop) and the detail panel's buttons, at camp and at a rest point, in every layout mode.

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CampScreen := preload("res://client/camp_screen.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const InkUi := preload("res://client/ink_ui.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")


func _frames(ctx, count: int = 3) -> void:
	for i in count:
		await ctx.process_frame


## The middle of `control` in viewport coordinates (the menu is scaled, so this goes through the canvas).
func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _press(ctx, at: Vector2, button: MouseButton, pressed: bool, double: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.double_click = double
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if (pressed and button == MOUSE_BUTTON_LEFT) else 0
	ctx.root.push_input(event, true)  # viewport coordinates (the headless window is tiny and stretched)


var _mouse_at := Vector2.ZERO


func _move(ctx, at: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = at - _mouse_at  # Godot starts a drag once the relative motion passes a threshold
	_mouse_at = at
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	ctx.root.push_input(event, true)  # viewport coordinates (the headless window is tiny and stretched)


func click(ctx, control: Control) -> void:
	var at := _center(control)
	_move(ctx, at, false)
	_press(ctx, at, MOUSE_BUTTON_LEFT, true)
	_press(ctx, at, MOUSE_BUTTON_LEFT, false)
	await _frames(ctx)


func double_click(ctx, control: Control) -> void:
	var at := _center(control)
	_move(ctx, at, false)
	_press(ctx, at, MOUSE_BUTTON_LEFT, true)
	_press(ctx, at, MOUSE_BUTTON_LEFT, false)
	_press(ctx, at, MOUSE_BUTTON_LEFT, true, true)
	_press(ctx, at, MOUSE_BUTTON_LEFT, false)
	await _frames(ctx)


func right_click(ctx, control: Control) -> void:
	var at := _center(control)
	_move(ctx, at, false)
	_press(ctx, at, MOUSE_BUTTON_RIGHT, true)
	_press(ctx, at, MOUSE_BUTTON_RIGHT, false)
	await _frames(ctx)


## Presses on `from`, moves in steps to `to` with the button held, and lets go there.
func drag(ctx, from: Control, to: Control) -> void:
	var a := _center(from)
	var b := _center(to)
	_move(ctx, a, false)
	_press(ctx, a, MOUSE_BUTTON_LEFT, true)
	await _frames(ctx, 1)
	for i in range(1, 9):
		_move(ctx, a.lerp(b, float(i) / 8.0), true)
		await _frames(ctx, 1)
	_press(ctx, b, MOUSE_BUTTON_LEFT, false)
	await _frames(ctx)


func _bag_cell(gear, item) -> Control:
	for cell in gear.bag_cells:
		if cell.kind == "item" and cell.item == item:
			return cell
	return null


func _empty_bag_cell(gear) -> Control:
	for cell in gear.bag_cells:
		if cell.kind == "empty":
			return cell
	return null


func _find(node: Node, node_name: String) -> Node:
	if node.name == node_name and node is Button and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find(child, node_name)
		if found != null:
			return found
	return null


func _text_anywhere(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text.contains(needle):
		return true
	for child in node.get_children():
		if _text_anywhere(child, needle):
			return true
	return false


func _tab_names(screen) -> Array:
	var names: Array = []
	for child in screen._tabs.get_children():
		names.append(str(child.name))
	return names


func run(ctx) -> void:
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var combat := CombatDataLoader.load_default()
	if not (rules.is_valid() and camp.is_valid() and combat.is_valid()):
		ctx.check("the data loads for the inventory window test", false)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	await _at_camp(ctx, rules, camp, combat, rng)
	await _at_rest_point(ctx, rules, camp, combat, rng)
	await _layouts(ctx, rules, camp, combat, rng)
	await _mobile_scroll(ctx, rules, camp, combat, rng)
	_move(ctx, Vector2(-5000.0, -5000.0), false)  # leave nothing hovered for the tests that follow
	await _frames(ctx, 1)


func _at_camp(ctx, rules, camp, combat, rng: RandomNumberGenerator) -> void:
	var profile = Profile.new_player(rules, camp, rng)
	profile.stash.capacity = 30
	var hat = ItemSystem.create_item(rules, "a-hat", "hat", 2, rng)
	var ring = ItemSystem.create_item(rules, "a-ring", "ring", 1, rng)
	profile.stash.add_item(hat)
	profile.stash.add_item(ring)
	var screen: CanvasLayer = CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(profile, camp, rules, combat)
	await _frames(ctx)
	var gear = screen.gear
	ctx.check("camp: the screen has Inventory, Look, Repair and Camp tabs", _tab_names(screen) == ["Inventory", "Look", "Repair", "Camp"])
	ctx.check("camp: the inventory has a cell for each of the 14 equipment slots", gear.slot_cells.size() == rules.total_slot_count() and rules.total_slot_count() == 14)
	ctx.check("camp: the worn weapon shows in its slot", gear.slot_cells["weapon:0"].item == profile.loadout.item_at("weapon"))
	ctx.check("camp: the stash grid shows the stash pieces, the material stacks and the free cells",
		_bag_cell(gear, hat) != null and _bag_cell(gear, ring) != null and gear.bag_cells.size() == profile.stash.capacity)
	ctx.check("camp: money is shown under the grid", gear._money.text.contains(str(profile.stash.gold)))
	ctx.check("camp: with nothing selected the details show the fighting style and attack speed",
		_text_anywhere(gear, "Fighting style: Sword") and _text_anywhere(gear, "Attack speed:"))
	ctx.check("camp: the paper-doll renders while the inventory is shown", gear.doll.is_rendering())

	# Double-click a stash piece: it is worn.
	await double_click(ctx, _bag_cell(gear, hat))
	ctx.check("double-click on a stash piece wears it", profile.loadout.item_at("hat") == hat and not profile.stash.items.has(hat))
	ctx.check("the worn piece shows in its slot and the status line says so", gear.slot_cells["hat:0"].item == hat and screen._status.text.begins_with("Worn"))
	# Right-click the worn piece: it comes off.
	await right_click(ctx, gear.slot_cells["hat:0"])
	ctx.check("right-click on a worn piece takes it off into the stash", profile.loadout.item_at("hat") == null and profile.stash.items.has(hat))
	# Drag from the grid onto the slot.
	await drag(ctx, _bag_cell(gear, hat), gear.slot_cells["hat:0"])
	ctx.check("dragging a stash piece onto its slot wears it", profile.loadout.item_at("hat") == hat)
	# Drag onto the wrong slot: nothing happens.
	await drag(ctx, _bag_cell(gear, ring), gear.slot_cells["hat:0"])
	ctx.check("dragging a piece onto a slot it does not fit changes nothing", profile.loadout.item_at("hat") == hat and profile.stash.items.has(ring))
	# Drag the second ring position: it goes there, not into the first.
	await drag(ctx, _bag_cell(gear, ring), gear.slot_cells["ring:1"])
	ctx.check("dragging a ring onto the second ring slot wears it there", profile.loadout.item_at("ring", 1) == ring and profile.loadout.item_at("ring", 0) == null)
	# Drag a worn piece back onto the grid.
	await drag(ctx, gear.slot_cells["ring:1"], _empty_bag_cell(gear))
	ctx.check("dragging a worn piece onto the stash grid takes it off", profile.loadout.item_at("ring", 1) == null and profile.stash.items.has(ring))

	# Tap = select; the detail panel's buttons do the same (touch, no hover, no double-tap needed).
	ctx.check("a piece taken off stays selected so its details show", gear.selection.get("item") == ring)
	await click(ctx, _empty_bag_cell(gear))
	ctx.check("a tap on a free cell clears the selection (the details show the character)", gear.selection.is_empty())
	await click(ctx, _bag_cell(gear, ring))
	ctx.check("a tap selects the piece and marks the slots it fits", gear.selection.get("item") == ring and gear.slot_cells["ring:0"].highlighted and gear.slot_cells["ring:1"].highlighted)
	ctx.check("the details compare it with what the slot has", _text_anywhere(gear, "is empty: everything is a gain"))
	var wear_second: Button = _find(gear, "Wear1")
	ctx.check("a paired slot offers a Wear button for each position", _find(gear, "Wear0") != null and wear_second != null)
	await click(ctx, wear_second)
	ctx.check("pressing 'Wear as Ring 2' wears it in the second position", profile.loadout.item_at("ring", 1) == ring)
	ctx.check("after wearing, the worn slot is selected and offers Take off", gear.selection.get("kind") == "slot" and _find(gear, "TakeOff") != null)
	await click(ctx, _find(gear, "TakeOff"))
	ctx.check("pressing Take off puts it back in the stash", profile.loadout.item_at("ring", 1) == null and profile.stash.items.has(ring))

	# A worn piece's swap: wearing a second hat puts the first one back into the stash.
	var hat2 = ItemSystem.create_item(rules, "b-hat", "hat", 3, rng)
	profile.stash.add_item(hat2)
	gear.refresh()
	await _frames(ctx)
	await click(ctx, _bag_cell(gear, hat2))
	ctx.check("the details compare a hat with the worn hat", _text_anywhere(gear, "Compared with your Hat:"))
	await double_click(ctx, _bag_cell(gear, hat2))
	ctx.check("wearing over a worn piece swaps them", profile.loadout.item_at("hat") == hat2 and profile.stash.items.has(hat))

	# Search and filters.
	gear._search.text = "ring"
	gear._search.text_changed.emit("ring")
	await _frames(ctx)
	var only_rings := true
	for cell in gear.bag_cells:
		only_rings = only_rings and cell.kind == "item" and cell.item.slot == "ring"
	ctx.check("searching 'ring' shows only rings", only_rings and gear.bag_cells.size() == 1)
	gear._search.text = "zzz"
	gear._search.text_changed.emit("zzz")
	await _frames(ctx)
	ctx.check("a search with no result says so", gear.bag_cells.is_empty() and gear._grid_note.text == gear.TEXT["no_match"])
	gear._search.text = ""
	gear._search.text_changed.emit("")
	await click(ctx, gear._category_buttons["material"])
	var only_materials: bool = not gear.bag_cells.is_empty()
	for cell in gear.bag_cells:
		only_materials = only_materials and cell.kind == "material"
	ctx.check("the Material filter shows only material stacks", only_materials)
	await click(ctx, gear._category_buttons["all"])

	# Discard takes two presses.
	await click(ctx, _bag_cell(gear, hat))
	await click(ctx, _find(gear, "Discard"))
	ctx.check("one press on Discard only asks", profile.stash.items.has(hat) and _find(gear, "Discard").text.begins_with("Sure"))
	await click(ctx, _find(gear, "Discard"))
	ctx.check("the second press throws it away", not profile.stash.items.has(hat))

	# A full stash: nothing can be taken off, and the screen says why.
	profile.stash.capacity = profile.stash.slots_used()
	gear.refresh()
	await _frames(ctx)
	await right_click(ctx, gear.slot_cells["hat:0"])
	ctx.check("with a full stash a worn piece stays on and the screen says why", profile.loadout.item_at("hat") == hat2 and screen._status.text == gear.TEXT["stash_full"])
	await click(ctx, gear.slot_cells["hat:0"])
	ctx.check("and its Take off button is disabled", _find(gear, "TakeOff") != null and _find(gear, "TakeOff").disabled)
	ctx.check("the full stash is flagged", gear._capacity.text.contains(gear.TEXT["full"]))

	# Other tabs stop the doll rendering (the web build has no threads to spare).
	screen._tabs.current_tab = 1
	await _frames(ctx)
	ctx.check("the paper-doll stops rendering when another tab is shown", not gear.doll.is_rendering())
	screen._tabs.current_tab = 0
	await _frames(ctx)
	ctx.check("and starts again when the inventory is shown", gear.doll.is_rendering())
	screen.queue_free()
	await _frames(ctx)


func _at_rest_point(ctx, rules, camp, combat, rng: RandomNumberGenerator) -> void:
	var profile = Profile.new_player(rules, camp, rng)
	var trip = Run.start(profile, camp)
	var shirt = ItemSystem.create_item(rules, "found-shirt", "shirt", 3, rng)
	var pants = ItemSystem.create_item(rules, "found-pants", "pants", 1, rng)
	trip.bag.add_item(shirt)
	trip.bag.add_item(pants)
	trip.bag.gold = 42
	var screen: CanvasLayer = CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(profile, camp, rules, combat, trip, "spot")
	var events := {"gear": 0}
	screen.gear_changed.connect(func() -> void: events["gear"] += 1)
	await _frames(ctx)
	var gear = screen.gear
	ctx.check("rest: the screen has Inventory and Rest tabs", _tab_names(screen) == ["Inventory", "Rest"])
	ctx.check("rest: the grid shows the trip's bag and its gold", _bag_cell(gear, shirt) != null and gear._money.text.contains("42") and _text_anywhere(gear, "lost if you fall"))
	var old_shirt = profile.loadout.item_at("shirt")
	await double_click(ctx, _bag_cell(gear, shirt))
	ctx.check("rest: double-click wears a found piece, the old one goes into the bag, the simulation is told",
		profile.loadout.item_at("shirt") == shirt and trip.bag.items.has(old_shirt) and events["gear"] == 1)
	await drag(ctx, _bag_cell(gear, pants), gear.slot_cells["pants:0"])
	ctx.check("rest: dragging a found piece onto its slot wears it", profile.loadout.item_at("pants") == pants and events["gear"] == 2)
	await right_click(ctx, gear.slot_cells["pants:0"])
	ctx.check("rest: right-click takes a worn piece off into the bag and tells the simulation",
		profile.loadout.item_at("pants") == null and trip.bag.items.has(pants) and events["gear"] == 3 and screen._status.text.contains("bag"))
	await double_click(ctx, _bag_cell(gear, pants))
	ctx.check("rest: double-click puts it back on", profile.loadout.item_at("pants") == pants and events["gear"] == 4)
	await double_click(ctx, gear.slot_cells["pants:0"])
	ctx.check("rest: double-click on a worn piece takes it off", profile.loadout.item_at("pants") == null and trip.bag.items.has(pants) and events["gear"] == 5)
	await drag(ctx, _bag_cell(gear, pants), gear.slot_cells["pants:0"])
	await drag(ctx, gear.slot_cells["pants:0"], _empty_bag_cell(gear))
	ctx.check("rest: dragging a worn piece onto the bag takes it off", profile.loadout.item_at("pants") == null and trip.bag.items.has(pants) and events["gear"] == 7)
	await click(ctx, gear.slot_cells["shirt:0"])
	await click(ctx, _find(gear, "TakeOff"))
	ctx.check("rest: the Take off button takes it off into the bag", profile.loadout.item_at("shirt") == null and trip.bag.items.has(shirt) and events["gear"] == 8)
	await double_click(ctx, _bag_cell(gear, shirt))
	ctx.check("rest: and it can be worn again", profile.loadout.item_at("shirt") == shirt and events["gear"] == 9)
	# A full bag: the piece stays on, the button is greyed out, and the screen says why.
	while trip.bag.free_slots() > 0:
		trip.bag.add_item(ItemSystem.create_item(rules, "filler-%d" % trip.bag.items.size(), "earring", 0, rng))
	gear.refresh()
	await _frames(ctx)
	await right_click(ctx, gear.slot_cells["shirt:0"])
	ctx.check("rest: with a full bag a worn piece stays on and the screen says why",
		profile.loadout.item_at("shirt") == shirt and screen._status.text == gear.TEXT["bag_full"] and events["gear"] == 9)
	gear.select({})  # (a tap on the already selected slot would clear it)
	await click(ctx, gear.slot_cells["shirt:0"])
	ctx.check("rest: its Take off button is disabled with the reason shown", _find(gear, "TakeOff").disabled and _text_anywhere(gear, gear.TEXT["bag_full"]))
	trip.bag.take_item(trip.bag.items.size() - 1)
	gear.select({})
	gear.refresh()
	await _frames(ctx)
	ctx.check("rest: with nothing selected the hint says how to take a piece off into the bag", _text_anywhere(gear, "back onto the bag to take off"))
	await click(ctx, _bag_cell(gear, old_shirt))
	await click(ctx, _find(gear, "Wear"))
	ctx.check("rest: the detail Wear button swaps back", profile.loadout.item_at("shirt") == old_shirt and trip.bag.items.has(shirt) and events["gear"] == 10)
	screen.queue_free()
	await _frames(ctx)


## Every layout mode builds, and the slots and bag stay inside the screen.
func _layouts(ctx, rules, camp, combat, rng: RandomNumberGenerator) -> void:
	var profile = Profile.new_player(rules, camp, rng)
	var screen: CanvasLayer = CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(profile, camp, rules, combat)
	await _frames(ctx)
	var gear = screen.gear
	for mode in [InkUi.COMPACT, InkUi.PORTRAIT, InkUi.WIDE]:
		gear.set_mode(mode)
		await _frames(ctx)
		var inside := true
		var page: Rect2 = gear.get_global_rect().grow(1.0)
		for key in gear.slot_cells:
			inside = inside and page.encloses(gear.slot_cells[key].get_global_rect())
		ctx.check("layout %s: all 14 slots sit inside the inventory page" % mode, inside)
	# Portrait: holding a piece opens its details as a sheet over the bag; Back closes it.
	profile.stash.add_item(ItemSystem.create_item(rules, "held", "hat", 1, rng))
	gear.set_mode(InkUi.PORTRAIT)
	gear.refresh()
	await _frames(ctx)
	var held: Control = _bag_cell(gear, profile.stash.items[0])
	var at := _center(held)
	_move(ctx, at, false)
	_press(ctx, at, MOUSE_BUTTON_LEFT, true)
	await ctx.create_timer(0.7).timeout
	_press(ctx, at, MOUSE_BUTTON_LEFT, false)
	await _frames(ctx)
	ctx.check("portrait: holding a piece opens its details over the bag", gear._sheet_open and not gear._bag_box.visible and gear.selection.get("item") == profile.stash.items[0])
	await click(ctx, _find(gear, "Back"))
	ctx.check("portrait: Back closes the sheet and shows the bag again", not gear._sheet_open and gear._bag_box.visible and gear.selection.is_empty())
	gear.set_mode(InkUi.WIDE)
	var picked: Dictionary = InkUi.layout_for(Vector2(1170, 2532), Vector2(1280, 2770), 3.0)
	ctx.check("a phone held upright gets the portrait layout", picked["mode"] == InkUi.PORTRAIT)
	picked = InkUi.layout_for(Vector2(2532, 1170), Vector2(1558, 720), 3.0)
	ctx.check("a phone held sideways gets the compact layout", picked["mode"] == InkUi.COMPACT)
	screen.queue_free()
	await _frames(ctx)


func _mobile_scroll(ctx, rules, camp, combat, rng: RandomNumberGenerator) -> void:
	var saved: Vector2i = ctx.root.size
	ctx.root.size = Vector2i(844, 390)
	var profile = Profile.new_player(rules, camp, rng)
	profile.stash.capacity = 100
	for i in 70:
		profile.stash.add_item(ItemSystem.create_item(rules, "swipe%d" % i, "hat", 1, rng))
	var screen := CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(profile, camp, rules, combat)
	await _frames(ctx, 8)
	var gear = screen.gear
	gear.set_mode(InkUi.COMPACT)
	await _frames(ctx, 5)
	var worn_before: Array = profile.loadout.items().duplicate()
	var before: Rect2 = gear._bag_box.get_global_rect()
	var detail_width: float = gear._detail_panel.size.x
	gear._detail_header(null, "An extremely long legendary equipment name that must wrap without resizing the inventory", InkUi.PAPER, "A very long slot and tier subtitle that also needs to wrap")
	await _frames(ctx, 8)
	ctx.check("long details never shift inventory width", gear._bag_box.get_global_rect().is_equal_approx(before) and is_equal_approx(gear._detail_panel.size.x, detail_width))
	var preview: Control = gear._preview_cell(profile.stash.items[0])
	gear._detail_header(preview, "A very long equipment title that wraps across many lines in the fixed detail panel", InkUi.PAPER, "Shirt Tier 3 of 4 WORN")
	await _frames(ctx)
	ctx.check("wrapped equipment header keeps preview square", is_equal_approx(preview.size.x, preview.size.y))
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.pressed = true
	touch.position = gear._grid_scroll.get_global_rect().get_center()
	ctx.root.push_input(touch, true)
	ctx.check("item grid captures touch scrolling", gear._scroll_finger == 7)
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = touch.position - Vector2(0, 60)
	ctx.root.push_input(drag, true)
	touch.pressed = false
	ctx.root.push_input(touch, true)
	ctx.check("swiping item cells scrolls without selecting or equipping", gear._grid_scroll.scroll_vertical > 0 and gear.selection.is_empty() and profile.loadout.items() == worn_before)
	ctx.check("mobile scroll handle is wide", gear._grid_scroll.get_v_scroll_bar().size.x >= 32)
	screen.queue_free()
	await _frames(ctx)
	ctx.root.size = saved
