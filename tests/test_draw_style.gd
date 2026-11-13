extends RefCounted
## The drawn (ink-and-wash) battle look, client/draw_style/draw_style.gd (Boss 2026-11-13 picked ink_c as default):
## - the graphics setting `drawn_style` defaults to "on" and only takes off / lite / on;
## - the full-screen ink pass runs only at render scale 0.5 (web cost, docs/tech/draw_style.md) and not on a device
##   the slow guard has flagged; "lite" and "off" never run it;
## - the panel words exist in Thai and English;
## - an opaque HP bar quad is moved after the screen pass (stays clean), a lit mesh is left alone;
## - the shaders compile in the project renderer.
## The setting is read and restored around each check, so a saved user://graphics.cfg is left as it was.

const Options := preload("res://client/graphics_options.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")


func run(ctx) -> void:
	var saved_style = Options.value("drawn_style")
	var saved_scale = Options.value("render_scale")
	var had_config := FileAccess.file_exists(Options.PATH)
	var config_text := FileAccess.get_file_as_string(Options.PATH) if had_config else ""
	DrawStyle._override = ""  # (ignore any --style= on the test command line)

	ctx.check("drawn_style is a graphics setting, default on", Options.DRAWN_STYLES == ["off", "lite", "on"] and Options._values.has("drawn_style"))
	ctx.check("drawn_style refuses unknown values", not Options._valid("drawn_style", "ink") and not Options._valid("drawn_style", true) and Options._valid("drawn_style", "lite"))

	Options.set_value("drawn_style", "on")
	Options.set_value("render_scale", 0.5)
	DrawStyle.slow_device = false
	ctx.check("on at render scale 0.5: the screen pass runs", DrawStyle.mode() == "on" and DrawStyle.screen_allowed())
	Options.set_value("render_scale", 1.0)
	ctx.check("on at render scale 1.0: the screen pass is off (materials only)", not DrawStyle.screen_allowed())
	Options.set_value("render_scale", 0.75)
	ctx.check("on at render scale 0.75: the screen pass is off", not DrawStyle.screen_allowed())
	Options.set_value("render_scale", 0.5)
	DrawStyle.slow_device = true
	ctx.check("on, but the device was found slow: the screen pass is off", not DrawStyle.screen_allowed())
	DrawStyle.slow_device = false
	Options.set_value("drawn_style", "lite")
	ctx.check("lite: materials only, never the screen pass", DrawStyle.mode() == "lite" and not DrawStyle.screen_allowed())
	Options.set_value("drawn_style", "off")
	ctx.check("off: the old look", DrawStyle.mode() == "off" and not DrawStyle.screen_allowed())

	var words_ok := true
	for key in DrawStyle.DRAWN_KEYS + ["drawn_style", "drawn_hint"]:
		var entry: Array = DrawStyle.STRINGS.get(key, [])
		words_ok = words_ok and entry.size() == 2 and not str(entry[0]).is_empty() and not str(entry[1]).is_empty() and entry[0] != entry[1]
	ctx.check("the panel words exist in Thai and English", words_ok and DrawStyle.DRAWN_KEYS.size() == Options.DRAWN_STYLES.size())

	var bar := MeshInstance3D.new()
	var bar_material := StandardMaterial3D.new()
	bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_material.no_depth_test = true
	bar.material_override = bar_material
	DrawStyle._keep_clean(bar)
	ctx.check("an HP bar quad is drawn after the screen pass (alpha blended, same look)", bar_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and bar_material.albedo_color.a == 1.0)
	var body := MeshInstance3D.new()
	var body_material := StandardMaterial3D.new()
	body.material_override = body_material
	DrawStyle._keep_clean(body)
	ctx.check("a lit mesh stays opaque", body_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	bar.free()
	body.free()

	for path in ["res://client/draw_style/ink_world.gdshader", "res://client/draw_style/ink_screen.gdshader", "res://client/draw_style/ink_outline_brush.gdshader"]:
		var shader := load(path) as Shader
		ctx.check("%s loads with its uniforms" % path.get_file(), shader != null and not shader.get_shader_uniform_list().is_empty())

	DrawStyle._override = "?"
	# Restore the in-memory values, then the file exactly as it was (set_value saves the file each time).
	Options._values["drawn_style"] = saved_style
	Options._values["render_scale"] = saved_scale
	Options.revision += 1
	if had_config:
		var file := FileAccess.open(Options.PATH, FileAccess.WRITE)
		file.store_string(config_text)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
