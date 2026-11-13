extends RefCounted
## The settings overlay (client/graphics_panel.gd) in the hub look: every graphics option has a row, a plate writes
## its value through client/graphics_options.gd (and only that), phone plates are >= 96 px, the first plate takes
## the focus (keyboard / gamepad), the rows scroll at 844x390, Esc (ui_cancel = gamepad B) closes it, and every
## word exists in Thai and English. The player's saved settings are put back afterwards.

const Options := preload("res://client/graphics_options.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const SettingsUi := preload("res://client/graphics_panel.gd")


func _frames(ctx, count: int) -> void:
	for i in count:
		await ctx.process_frame


func run(ctx) -> void:
	var saved := Options.snapshot()
	_check_words(ctx)
	await _check_overlay(ctx, Vector2(1920, 1080))
	await _check_overlay(ctx, Vector2(844, 390))
	for key in saved:
		Options.set_value(key, saved[key])


func _check_words(ctx) -> void:
	var missing: Array = []
	for rows in [SettingsUi.QUALITY, SettingsUi.DRAWN, SettingsUi.SCENE, SettingsUi.EFFECTS]:
		for row in rows:
			var words: Array = [row[1]] + (row[3] if row.size() > 3 else ["gfx_on", "gfx_off"])
			for key in words:
				if not CardTokens.STRINGS.has(key) or str(CardTokens.STRINGS[key][0]).is_empty() or str(CardTokens.STRINGS[key][1]).is_empty():
					missing.append(key)
	for key in ["svc_settings", "gfx_sec_quality", "gfx_sec_drawn", "gfx_sec_scene", "gfx_sec_effects", "gfx_note", "gfx_scale_hint", "gfx_drawn_hint"]:
		if not CardTokens.STRINGS.has(key):
			missing.append(key)
	ctx.check("every settings word is in Thai and English %s" % [missing], missing.is_empty())
	var keys: Array = []
	for rows in [SettingsUi.QUALITY, SettingsUi.DRAWN, SettingsUi.SCENE, SettingsUi.EFFECTS]:
		for row in rows:
			keys.append(row[0])
	var all_keys: Array = Options.snapshot().keys()
	var left_out: Array = all_keys.filter(func(k) -> bool: return not k in keys)
	ctx.check("every graphics option has a row in the panel %s" % [left_out], left_out.is_empty())


func _check_overlay(ctx, screen: Vector2) -> void:
	var holder := Control.new()
	holder.size = screen
	ctx.root.add_child(holder)
	var layer = SettingsUi.new()
	holder.add_child(layer)
	var hub: Control = layer.panel
	hub.size = screen
	hub._layout()
	await _frames(ctx, 3)
	var phone := CardTokens.is_phone(screen)
	var label := "%dx%d" % [screen.x, screen.y]
	var plates: Array = hub.find_children("*", "Button", true, false).filter(func(b) -> bool: return b.has_meta("value"))
	ctx.check("%s: the panel has every choice plate (%d)" % [label, plates.size()], plates.size() == 3 + 3 + 3 + 8 * 2)
	if phone:
		var small: Array = plates.filter(func(b) -> bool: return b.custom_minimum_size.y < CardTokens.HUB_TAP_MIN_PHONE * hub.s - 0.5)
		ctx.check("%s: every plate is >= 96 px tall on a phone (scaled)" % label, small.is_empty() and hub._close.size.y >= CardTokens.HUB_TAP_MIN_PHONE * hub.s - 0.5)
		var scroll: ScrollContainer = hub.find_child("Scroll", true, false)
		ctx.check("%s: the rows scroll when they don't fit" % label, scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y)
	var focus: Control = hub.get_viewport().gui_get_focus_owner()
	ctx.check("%s: the first plate has the keyboard / gamepad focus" % label, focus != null and focus.has_meta("value"))
	var lite: Button = hub.find_child("Drawn_lite", true, false)
	Options.set_value("drawn_style", "on")
	if lite != null:
		lite.pressed.emit()
	ctx.check("%s: Lite writes drawn_style = lite" % label, str(Options.value("drawn_style")) == "lite")
	ctx.check("%s: the chosen plate shows a check mark" % label, lite != null and lite.text.begins_with("✓"))
	var shadows_off: Button = hub.find_child("shadows_false", true, false)
	if shadows_off != null:
		shadows_off.pressed.emit()
	ctx.check("%s: Shadows Off writes shadows = false" % label, not Options.enabled("shadows"))
	var high: Array = plates.filter(func(b) -> bool: return b.name.begins_with("render_scale") and is_equal_approx(float(b.get_meta("value")), 0.75))
	if not high.is_empty():
		high[0].pressed.emit()
	ctx.check("%s: High writes render scale 0.75" % label, is_equal_approx(float(Options.value("render_scale")), 0.75))
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	hub._unhandled_input(cancel)
	await _frames(ctx, 2)
	ctx.check("%s: Esc / gamepad B closes the settings" % label, not is_instance_valid(layer))
	holder.queue_free()
	await _frames(ctx, 1)
