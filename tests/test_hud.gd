extends RefCounted
## Tests the in-stage HUD: key hints match the real controls, the ultimate names its real key,
## nothing overlaps in the desktop and the compact (phone) layout, and the HUD never takes clicks.

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const GameSim := preload("res://logic/game_sim.gd")
const Hud := preload("res://client/hud.gd")
const InputReader := preload("res://client/input_reader.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const StageView := preload("res://client/stage_view.gd")


func _sim(data) -> GameSim:
	var world := SimWorld.new()
	world.half_width = 30.0
	world.half_depth = 3.0
	world.add_solid(AABB(Vector3(-40, -0.4, -5), Vector3(80, 0.4, 10)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sim := GameSim.new(world, data, rng)
	sim.add_player(1, Vector3(0, 0.05, 0), {"STAMINA": 1000})  # (a huge pool: the bar must still stay clear of the banner)
	return sim


func _rect(control: Control, size: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(control.position, size if size != Vector2.ZERO else control.size)


func _all_controls(node: Node, found: Array = []) -> Array:
	if node is Control:
		found.append(node)
	for child in node.get_children():
		_all_controls(child, found)
	return found


func run(ctx) -> void:
	InputReader.setup_actions()
	ctx.check("key hints come from the input reader: LMB/RMB attack, F guard, C dodge, 1 skill, 2 ultimate",
		InputReader.key_label("light") == "LMB" and InputReader.key_label("heavy") == "RMB" and InputReader.key_label("guard") == "F"
		and InputReader.key_label("dodge") == "C" and InputReader.key_label("special") == "1" and InputReader.key_label("ultimate") == "2")
	ctx.check("an unbound action shows the fallback text", InputReader.key_label("no_such_action", "?") == "?")
	ctx.check("auto-battle hides our squad's overhead name/HP tag (the squad panel shows it); co-op outside auto-battle keeps it",
		not StageView.party_status_shown(true, true) and StageView.party_status_shown(true, false) and not StageView.party_status_shown(false, false))

	var data = CombatDataLoader.load_default()
	var sim := _sim(data)
	var player = sim.fighters[1]
	var hud: CanvasLayer = Hud.new()
	hud.compact_override = 0
	ctx.root.add_child(hud)
	await ctx.process_frame
	hud.set_help("")
	ctx.check("the skill icons show F / C / 1 / 2", hud._icons["guard"]["key"].text == "F" and hud._icons["dodge"]["key"].text == "C"
		and hud._icons["special"]["key"].text == "1" and hud._icons["ultimate"]["key"].text == "2")

	player.gauge = float(data.rules["ultimate_gauge_max"])
	hud.update_from(player, data, 3, "Camera 8: High", "Bag 2/12    Gold 40")
	ctx.check("a full ultimate says READY with its real key (%s)" % hud._gauge["label"].text, hud._gauge["label"].text.contains("READY") and hud._gauge["label"].text.contains("[2]"))
	ctx.check("the trip line shows enemies, bag and gold (%s)" % hud._trip.text, hud._trip.text.contains("Enemies  3") and hud._trip.text.contains("Bag 2/12") and hud._trip.text.contains("Gold 40"))
	player.gauge = 0.0
	hud.update_from(player, data, 3, "Camera 8: High", "")
	ctx.check("an empty ultimate is shown charging (dim), not as an error (red)", hud._icons["ultimate"]["root"].color.r < 0.2)

	# Desktop layout: banner, bars, trip line, combo and icons stay apart and on screen.
	var area: Vector2 = hud._root.size
	var banner := _rect(hud._skill_banner, Hud.BANNER_SIZE)
	var blocks := {"HP bar": _rect(hud._hp["back"]), "stamina bar": _rect(hud._energy["back"]), "ultimate bar": _rect(hud._gauge["back"]), "trip line": _rect(hud._trip)}
	var clear := true
	for name in blocks:
		if banner.intersects(blocks[name]):
			clear = false
			ctx.check("desktop: the skill banner does not cover the %s" % name, false)
	ctx.check("desktop (%dx%d): the skill banner covers none of the bars or the trip line" % [area.x, area.y], clear)
	var screen := Rect2(Vector2.ZERO, area)
	var icons_ok := true
	for key in hud._icons:
		var icon := _rect(hud._icons[key]["root"])
		icons_ok = icons_ok and screen.encloses(icon) and not icon.intersects(_rect(hud._help_plate))
	ctx.check("desktop: the skill icons are on screen and clear of the help lines", icons_ok)
	ctx.check("desktop: the combo counter is on screen and under the trip line", screen.encloses(_rect(hud._combo_box)) and not _rect(hud._combo_box).intersects(_rect(hud._trip)))
	hud.toggle_help()
	ctx.check("F1 hides the help lines", not hud.help_visible())
	hud.toggle_help()

	# Compact (phone) layout: bigger, no keyboard help, banner away from the bars.
	hud.compact_override = 1
	hud._layout()
	area = hud._root.size
	screen = Rect2(Vector2.ZERO, area)
	ctx.check("compact: the HUD is scaled up (%.1fx)" % hud.ui_scale, hud.compact and hud.ui_scale > 1.4)
	ctx.check("compact: the keyboard help is hidden", not hud.help_visible())
	ctx.check("compact: HP capsule stays under310 screen pixels", hud._hp["back"].size.x * hud.ui_scale <= 310)
	ctx.check("compact: HP capsule is thin", hud._hp["back"].size.y * hud.ui_scale <= 26)
	ctx.check("compact: round capsule replaces ornate bar", hud._hp["pill"].visible and not hud._hp["decor"].visible)
	ctx.check("compact: new empty trip frame is shown", hud._trip_art != null and hud._trip_art.visible)
	ctx.check("compact: stamina stays shorter than HP", hud._energy["back"].size.x <= hud._hp["back"].size.x)
	banner = _rect(hud._skill_banner, Hud.BANNER_SIZE)
	var compact_ok := screen.encloses(banner) and not banner.intersects(_rect(hud._hp["back"])) and not banner.intersects(_rect(hud._trip))
	for key in hud._icons:
		compact_ok = compact_ok and screen.encloses(_rect(hud._icons[key]["root"])) and not banner.intersects(_rect(hud._icons[key]["root"]))
	ctx.check("compact (%dx%d): banner, bars and icons are on screen and apart" % [area.x, area.y], compact_ok)

	# Attacks are on the mouse buttons, so no part of the HUD may catch a click.
	var takes_clicks := _all_controls(hud).filter(func(control): return control.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	ctx.check("no HUD element takes mouse clicks (%d do)" % takes_clicks.size(), takes_clicks.is_empty())
	hud.queue_free()
	await ctx.process_frame

	# The result plate (Boss phone playtest 2026-11-14): real buttons, on screen, clear of the top bars and the
	# squad tray, tap-sized on a phone.
	var panel = preload("res://client/result_panel.gd").new()
	ctx.root.add_child(panel)
	await ctx.process_frame
	panel.show_result("defeated", [["camp", "camp"], ["retry", "retry"]])
	var view_area: Vector2 = panel.get_viewport().get_visible_rect().size
	var plate: Rect2 = panel.plate_rect()
	var tray_top: float = view_area.y - preload("res://client/card_tokens.gd").SQUAD_HUD_CARD.y - preload("res://client/card_tokens.gd").SQUAD_HUD_MARGIN
	ctx.check("result plate (%s in %s) is on screen, under the boss bar and above the squad tray" % [plate, view_area],
		Rect2(Vector2.ZERO, view_area).encloses(plate) and plate.position.y >= 60.0 and plate.end.y <= tray_top)
	ctx.check("result plate has two real buttons that take taps", panel.buttons().size() == 2 and panel.buttons().all(func(b): return b.mouse_filter == Control.MOUSE_FILTER_STOP and b.focus_mode == Control.FOCUS_ALL))
	var pressed := []
	panel.action.connect(func(id): pressed.append(id))
	panel.buttons()[1].pressed.emit()
	ctx.check("a result button reports its action", pressed == ["retry"])
	panel.hide_result()
	ctx.check("the result plate hides", not panel.shown() and panel.plate_rect() == Rect2())
	panel.queue_free()
	await ctx.process_frame
