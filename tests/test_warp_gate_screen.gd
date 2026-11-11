extends RefCounted
## The Warp Gate window (client/warp_gate_screen.gd): its lists come from the same data the campfire
## menu used (journeys in data/journeys/, the maps of data/maps/index.json per mode, in index order),
## Enter starts the chosen content through the GameState calls (a fake starter records them here, so
## no scene changes), a journey that will not start shows an error, Esc and Close emit `closed`, and
## the targets are big enough on phones.

const WarpGateScreen := preload("res://client/warp_gate_screen.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const InkUi := preload("res://client/ink_ui.gd")


## Stands in for GameState: records the calls instead of changing the scene.
class FakeStarter:
	extends RefCounted
	var journeys: Array = []
	var stages: Array = []
	var journey_ok := true

	func start_journey(journey_id: String = "ink_road", _seed: int = 0) -> bool:
		journeys.append(journey_id)
		return journey_ok

	func start_stage(mode, map_id: String) -> void:
		stages.append([mode, map_id])


func _frames(ctx, count: int) -> void:
	for i in count:
		await ctx.process_frame


func _ids(list: Array) -> Array:
	return list.map(func(entry) -> String: return str(entry["id"] if entry is Dictionary else entry.id))


func run(ctx) -> void:
	_check_data(ctx)
	await _check_screen(ctx)


func _check_data(ctx) -> void:
	# The campfire menu's list (hub._stages_for): MapLoader.list_for_mode(GameState.mode_key(mode)).
	for kind in ["farm", "pvp"]:
		var hub_list := MapLoader.list_for_mode(GameState.mode_key(GameState.Mode.PVE if kind == "farm" else GameState.Mode.PVP))
		var gate_list: Array = WarpGateScreen.destinations_for(kind)
		ctx.check("the %s tab lists the same maps as the campfire menu, in order (%s)" % [kind, _ids(gate_list)], _ids(gate_list) == _ids(hub_list))
		for i in mini(gate_list.size(), hub_list.size()):
			ctx.check("%s '%s' shows the map's name" % [kind, gate_list[i]["id"]], hub_list[i].display_name.begins_with(gate_list[i]["name"]) and gate_list[i]["name"] != "")
	var journeys: Array = WarpGateScreen.destinations_for("journey")
	ctx.check("the journey tab lists the journey files, the default first (%s)" % [_ids(journeys)], not journeys.is_empty() and journeys[0]["id"] == GameState.DEFAULT_JOURNEY)
	var files: Array = []
	for file_name in DirAccess.get_files_at("res://data/journeys/"):
		if file_name.ends_with(".json"):
			files.append(file_name.get_basename())
	ctx.check("every journey file is listed once", journeys.size() == files.size() and files.all(func(id) -> bool: return id in _ids(journeys)))
	var road: Dictionary = journeys[0] if not journeys.is_empty() else {}
	ctx.check("the default journey reads as valid, with its name and stage count from the data", road.get("ok", false) and road.get("name", "") == "The Ink Road" and "12 stages" in str(road.get("sub", "")))
	ctx.check("the journey details name the boss and the monster levels", str(road.get("facts", [])).contains("Boss:") and str(road.get("sub", "")).contains("monster level"))
	ctx.check("the journey warns that leaving early loses the bag", "bag is lost" in str(road.get("note", "")))
	ctx.check("an unknown tab has no destinations", WarpGateScreen.destinations_for("nope").is_empty())


func _check_screen(ctx) -> void:
	var fake := FakeStarter.new()
	var gate := WarpGateScreen.new()
	gate.starter = fake
	var closes := [0]
	var entries: Array = []
	gate.closed.connect(func() -> void: closes[0] += 1)
	gate.entered.connect(func(kind: String, id: String) -> void: entries.append([kind, id]))
	ctx.root.add_child(gate)
	await _frames(ctx, 3)
	ctx.check("the gate opens on the Journey tab with Journey / Farm / PvP tabs", gate.tab == "journey" and gate.tab_buttons.keys() == ["journey", "farm", "pvp"])
	ctx.check("the tabs say Journey, Farm and PvP", ["journey", "farm", "pvp"].map(func(k) -> String: return gate.tab_buttons[k].text) == ["Journey", "Farm", "PvP"])
	ctx.check("the first journey is selected and has the focus (keyboard / gamepad ready)", gate.selected == 0 and not gate.rows.is_empty() and gate.rows[0].has_focus())
	ctx.check("one row per journey", gate.rows.size() == gate.destinations("journey").size())
	ctx.check("Enter is enabled for a valid journey", gate.enter_button != null and not gate.enter_button.disabled and gate.enter_button.text == "Enter")

	gate.enter_button.pressed.emit()
	ctx.check("Enter on a journey starts it through start_journey(id) %s" % [fake.journeys], fake.journeys == [GameState.DEFAULT_JOURNEY])
	ctx.check("Enter tells the camp what was entered", entries == [["journey", GameState.DEFAULT_JOURNEY]])
	ctx.check("a journey that starts shows no error", not gate.message.visible)
	fake.journey_ok = false
	gate.enter()
	ctx.check("a journey that will not start says so in the window", gate.message.visible and gate.message.text == gate.TEXT["start_failed"])

	gate.tab_buttons["farm"].pressed.emit()
	await _frames(ctx, 2)
	var farm: Array = gate.destinations("farm")
	ctx.check("the Farm tab shows one row per farm map", gate.tab == "farm" and gate.rows.size() == farm.size() and not farm.is_empty())
	ctx.check("the error line goes away on another tab", not gate.message.visible)
	if farm.size() > 1:
		gate.rows[1].pressed.emit()
		ctx.check("pressing a row selects it", gate.selected == 1 and gate.rows[1].button_pressed and not gate.rows[0].button_pressed)
		gate.rows[1].pressed.emit()
		await _frames(ctx, 1)
		ctx.check("pressing the selected row again moves the focus to Enter", gate.enter_button.has_focus())
	gate.enter()
	var farm_id: String = farm[gate.selected]["id"] if gate.selected >= 0 else ""
	ctx.check("Enter on a farm map starts it as a PvE stage %s" % [fake.stages], fake.stages == [[GameState.Mode.PVE, farm_id]])

	gate.show_tab("pvp")
	await _frames(ctx, 1)
	var pvp: Array = gate.destinations("pvp")
	if pvp.is_empty():
		ctx.check("an empty PvP tab says so and Enter is disabled", gate.rows.is_empty() and gate.selected == -1 and gate.enter_button.disabled)
		gate.enter()
		ctx.check("Enter does nothing with nothing selected", fake.stages.size() == 1)
	else:
		gate.enter()
		ctx.check("Enter on a PvP arena starts it as a PvP stage", fake.stages.back() == [GameState.Mode.PVP, pvp[0]["id"]])

	# Phones: every target at least 56 menu units (44 pt) in landscape and upright.
	for spec in [{"mode": InkUi.COMPACT, "scale": 0.78, "size": Vector2(1195.0, 551.0)}, {"mode": InkUi.PORTRAIT, "scale": 1.0, "size": Vector2(430.0, 932.0)}]:
		gate.apply_layout(spec)
		gate.show_tab("farm")
		await _frames(ctx, 2)
		var small: Array = []
		for button in gate.tab_buttons.values() + gate.rows + [gate.enter_button, gate.close_button]:
			if button.get_combined_minimum_size().y < 56.0:
				small.append(button.text if button.text != "" else "row")
		ctx.check("%s: tabs, rows, Enter and Close are at least 56 units tall %s" % [spec["mode"], small], small.is_empty())
		ctx.check("%s: the farm list is complete" % spec["mode"], gate.rows.size() == farm.size())

	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	gate._unhandled_input(cancel)
	ctx.check("Esc (ui_cancel) emits closed", closes[0] == 1)
	gate.close()
	ctx.check("closed is emitted only once", closes[0] == 1)
	await _frames(ctx, 2)
	ctx.check("the window frees itself after closing", not is_instance_valid(gate))

	var second := WarpGateScreen.new()
	second.starter = fake
	second.tab = "farm"
	var second_closes := [0]
	second.closed.connect(func() -> void: second_closes[0] += 1)
	ctx.root.add_child(second)
	await _frames(ctx, 2)
	ctx.check("the gate can open on another tab (tab set before add_child)", second.tab == "farm" and second.tab_buttons["farm"].button_pressed)
	second.close_button.pressed.emit()
	ctx.check("the Close button emits closed", second_closes[0] == 1)
	await _frames(ctx, 2)
