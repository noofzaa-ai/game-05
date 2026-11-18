extends RefCounted
## Phone graphics defaults (Boss 2026-11-18), client/graphics_options.gd + client/draw_style/draw_style.gd:
## - a phone defaults to sun shadow off, MSAA off, drawn style "lite" without hero ink hulls (render scale stays 0.5);
##   desktop / tablet keep the old defaults;
## - a value the player picks in the panel wins over the phone default and survives a reload;
## - SLOW_FPS is 30 and a slow device also loses shadows and MSAA (unless the player picked them);
## - the lag report's graphics section names the active preset and stays small inside the report codec.
## The player's user://graphics.cfg and user://device_speed.cfg are put back exactly afterwards.

const Options := preload("res://client/graphics_options.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")
const Codec := preload("res://runtime/diagnostics/report_codec.gd")


func run(ctx) -> void:
	var had_config := FileAccess.file_exists(Options.PATH)
	var config_text := FileAccess.get_file_as_string(Options.PATH) if had_config else ""
	var had_speed := FileAccess.file_exists(DrawStyle.DEVICE_PATH)
	var speed_text := FileAccess.get_file_as_string(DrawStyle.DEVICE_PATH) if had_speed else ""
	var saved_override := Options.device_override
	DrawStyle._override = ""

	_device_sizes(ctx)
	_defaults(ctx)
	_choice_wins(ctx)
	_slow_mode(ctx)
	_migration(ctx)
	_report(ctx)

	# Put everything back.
	Options.force_device(saved_override)
	Options.set_slow(false)
	DrawStyle._override = "?"
	DrawStyle._decided = false
	DrawStyle.slow_device = false
	_restore(Options.PATH, had_config, config_text)
	_restore(DrawStyle.DEVICE_PATH, had_speed, speed_text)
	Options.reload_settings()


func _restore(path: String, had: bool, text: String) -> void:
	if had:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fresh(device: String) -> void:
	if FileAccess.file_exists(Options.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	Options.set_slow(false)
	Options.force_device(device)


func _device_sizes(ctx) -> void:
	# CSS screen sizes of real devices (portrait numbers; the check is orientation-free).
	ctx.check("iPhone 15 Pro Max (430x932) is a phone", Options.is_phone_screen(true, Vector2(430, 932)))
	ctx.check("iPhone SE (375x667) is a phone", Options.is_phone_screen(true, Vector2(375, 667)))
	ctx.check("a small Android phone (360x800) is a phone", Options.is_phone_screen(true, Vector2(800, 360)))
	ctx.check("iPad (820x1180) is not a phone: desktop defaults", not Options.is_phone_screen(true, Vector2(820, 1180)))
	ctx.check("iPad mini (744x1133) is not a phone", not Options.is_phone_screen(true, Vector2(744, 1133)))
	ctx.check("a desktop screen is never a phone", not Options.is_phone_screen(false, Vector2(430, 932)))


func _defaults(ctx) -> void:
	_fresh("phone")
	ctx.check("phone: sun shadow off by default", not Options.enabled("shadows") and not Options.is_chosen("shadows"))
	ctx.check("phone: MSAA off by default", int(Options.effective("antialiasing")) == 0)
	ctx.check("phone: drawn style lite by default", str(Options.value("drawn_style")) == "lite" and DrawStyle.mode() == "lite")
	ctx.check("phone: render scale stays 0.5", is_equal_approx(float(Options.value("render_scale")), 0.5))
	ctx.check("phone: no screen pass", not DrawStyle.screen_allowed())
	DrawStyle._decided = true
	DrawStyle.slow_device = false
	ctx.check("phone auto lite: no hero ink hulls (the lightest existing look)", not DrawStyle.hero_ink())
	ctx.check("phone: the other options keep the desktop defaults", Options.enabled("outline") and Options.enabled("fog") and Options.enabled("glow") and Options.enabled("combat_vfx"))
	ctx.check("phone: preset name", Options.preset_name() == "phone")
	_fresh("desktop")
	ctx.check("desktop: shadow on, MSAA 2x, drawn style on (unchanged)", Options.enabled("shadows") and int(Options.effective("antialiasing")) == 2 and str(Options.value("drawn_style")) == "on")
	ctx.check("desktop: screen pass and hero ink as before", DrawStyle.screen_allowed() and DrawStyle.hero_ink())
	ctx.check("desktop: preset name", Options.preset_name() == "desktop")


func _choice_wins(ctx) -> void:
	_fresh("phone")
	Options.set_value("shadows", true)
	Options.set_value("antialiasing", 2)
	Options.set_value("drawn_style", "lite")
	ctx.check("phone: the player's Shadows On wins", Options.enabled("shadows") and Options.is_chosen("shadows"))
	ctx.check("phone: the player's MSAA 2x wins", int(Options.effective("antialiasing")) == 2)
	ctx.check("phone: the player picking Lite gets the full Lite (hero ink kept)", DrawStyle.hero_ink())
	Options.reload_settings()
	ctx.check("the player's choices survive a reload", Options.enabled("shadows") and int(Options.effective("antialiasing")) == 2 and Options.is_chosen("drawn_style"))
	ctx.check("an option never picked still follows the phone default after a reload", not Options.is_chosen("fog") and Options.enabled("fog"))
	ctx.check("preset shows custom choices (%s)" % Options.preset_name(),Options.preset_name() == "phone+custom")
	Options.force_device("desktop")
	ctx.check("the same file on a desktop keeps the player's picks", Options.enabled("shadows") and str(Options.value("drawn_style")) == "lite")
	Options.clear_choice("drawn_style")
	ctx.check("clearing a choice returns to the device default", str(Options.value("drawn_style")) == "on" and not Options.is_chosen("drawn_style"))


func _slow_mode(ctx) -> void:
	ctx.check("SLOW_FPS is 30 (Boss 2026-11-18)", is_equal_approx(DrawStyle.SLOW_FPS, 30.0))
	if FileAccess.file_exists(DrawStyle.DEVICE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DrawStyle.DEVICE_PATH))
	ctx.check("a 28 fps battle now marks the device slow", DrawStyle.record_battle(28.0, 60.0))
	DrawStyle.forget_slow()
	ctx.check("a 31 fps battle does not", not DrawStyle.record_battle(31.0, 60.0))
	_fresh("desktop")
	var rev := Options.revision
	DrawStyle.record_battle(20.0, 60.0)
	DrawStyle.begin_battle()
	ctx.check("slow device: shadows off", DrawStyle.slow_device and not Options.enabled("shadows"))
	ctx.check("slow device: MSAA off", int(Options.effective("antialiasing")) == 0)
	ctx.check("slow device: no screen pass, no hero ink (as before)", not DrawStyle.screen_allowed() and not DrawStyle.hero_ink())
	ctx.check("slow device: the runtime is told (revision bumped)", Options.revision != rev)
	ctx.check("slow device: the saved values are untouched", Options.value("shadows") == true and int(Options.value("antialiasing")) == 2)
	ctx.check("slow device: preset name", Options.preset_name() == "slow")
	Options.set_value("shadows", true)
	ctx.check("slow device: a player who picks Shadows On keeps them", Options.enabled("shadows") and int(Options.effective("antialiasing")) == 0)
	DrawStyle.forget_slow()
	ctx.check("forgetting the verdict restores shadow and MSAA", not Options.is_slow() and int(Options.effective("antialiasing")) == 2)
	DrawStyle._decided = false


func _migration(ctx) -> void:
	# A version-3 file wrote every value: values equal to the old default are not the player's choice.
	var config := ConfigFile.new()
	for id in Options.DESKTOP_DEFAULTS: config.set_value("graphics", id, Options.DESKTOP_DEFAULTS[id])
	config.set_value("graphics", "fog", false)
	config.set_value("graphics", "preset_version", 3)
	config.save(Options.PATH)
	Options.force_device("phone")
	ctx.check("old file on a phone: untouched defaults become the phone defaults", not Options.enabled("shadows") and str(Options.value("drawn_style")) == "lite")
	ctx.check("old file on a phone: a changed value stays the player's", not Options.enabled("fog") and Options.is_chosen("fog") and not Options.is_chosen("shadows"))
	var saved := ConfigFile.new()
	saved.load(Options.PATH)
	ctx.check("old file is rewritten as version 4", int(saved.get_value("graphics", "preset_version", 0)) == Options.PRESET_VERSION)


func _report(ctx) -> void:
	_fresh("phone")
	var section := Options.report()
	var fields_ok := true
	for key in ["preset", "device_class", "slow_device", "chosen", "applied", "shadows", "antialiasing", "drawn_style", "render_scale"]:
		fields_ok = fields_ok and section.has(key)
	ctx.check("report: graphics section has preset/device/slow/chosen/applied fields", fields_ok and section["preset"] == "phone" and section["applied"]["antialiasing"] == 0)
	var size := JSON.stringify(section).to_utf8_buffer().size()
	ctx.check("report: graphics section stays small (%d bytes < 1024)" % size, size < 1024)
	var encoded := Codec.encode({"v": 2, "client": {"graphics": section}})
	var decoded := Codec.decode(encoded)
	ctx.check("report: section survives the report codec", encoded.get("ok", false) and decoded.get("client", {}).get("graphics", {}).get("preset") == "phone")
	ctx.check("report: encoded size far below the 98304-byte server cap (%d)" % str(encoded.get("data", "")).length(), str(encoded.get("data", "")).length() < 4096)
