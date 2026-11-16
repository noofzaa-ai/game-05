extends SceneTree
## Level-15 race armour, ink-metal glints before/after (client/characters/metal_glint.gd). Run windowed:
##   godot --path . --script res://tools/shots/lv15_metal_shots.gd
## ZORX_OUT=dir (default build/lv15_metal/), ZORX_RACES=human,elf (default all), ZORX_ONLY=close (only the close-ups).
## Per race: desktop 1280x720 and phone 844x390 battle views at two light/camera angles, a hub card portrait, each
## "before" (metal off) and "after". PNG names: <race>_<size>_<angle>_<before|after>.png

const Portrait := preload("res://client/card_portrait.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const SLOTS := ["shirt", "pants", "armband", "shoes"]
const SIZES := {"desktop": Vector2i(1280, 720), "phone": Vector2i(844, 390)}
const ANGLES := {"a": 35.0, "b": -55.0}


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(vp: SubViewport, path: String) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await _frames(3)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _outfit(race: String) -> Dictionary:
	var looks := {}
	for slot in SLOTS:
		looks[slot] = "res://art/armor/race_shared/%s_%s_lv15.glb" % [race, slot]
	return looks


func _set_metal(model, on: bool) -> void:
	for material in model._toon:
		if material.resource_name.begins_with("Level 15 | Original Armor"):
			material.set_shader_parameter("use_metal", on)


func _stage(size: Vector2i) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = CardTokens.PORTRAIT_AMBIENT
	env.ambient_light_energy = CardTokens.PORTRAIT_AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	CharacterLight.light_scene(vp, env, CardTokens.PORTRAIT_KEY_ENERGY, CardTokens.PORTRAIT_RIM_ENERGY)
	var cam := Camera3D.new()
	cam.fov = 45.0
	vp.add_child(cam)
	return {"vp": vp, "cam": cam}


func run() -> void:
	var out := OS.get_environment("ZORX_OUT")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://build/lv15_metal/")
	out = out.rstrip("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var races: PackedStringArray = ["human", "viking", "elf", "runeborn"]
	if not OS.get_environment("ZORX_RACES").is_empty():
		races = OS.get_environment("ZORX_RACES").split(",")
	var close_only := OS.get_environment("ZORX_ONLY") == "close"
	for size_name in SIZES:
		var stage := _stage(SIZES[size_name])
		var vp: SubViewport = stage["vp"]
		var cam: Camera3D = stage["cam"]
		var model = CharacterModel.new()
		model.ink_outline = true
		vp.add_child(model)
		model.load_model()
		model.dress({"class": "sword_shield", "weapon": {"path": "", "family": "blade", "style": "blade"}})
		for race in races:
			model.dress({"appearance": {"race": race}})
			model.dress(_outfit(race))
			await _frames(2)
			for angle in ANGLES:
				model.rotation.y = deg_to_rad(ANGLES[angle])
				var dist := 2.6 if size_name == "desktop" else 2.5
				cam.position = Vector3(0.0, 1.30, dist)
				cam.look_at(Vector3(0.0, 0.72, 0.0))
				model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
				for i in 3:
					model.apply_pose(0.11)
				for state in ["before", "after"]:
					_set_metal(model, state == "after")
					if not close_only:
						await _save(vp, "%s%s_%s_%s_%s.png" % [out, race, size_name, angle, state])
					cam.position = Vector3(0.0, 0.75, 1.25)
					cam.look_at(Vector3(0.0, 0.50, 0.0))
					await _save(vp, "%s%s_%s_%s_close_%s.png" % [out, race, size_name, angle, state])
					cam.position = Vector3(0.0, 1.30, dist)
					cam.look_at(Vector3(0.0, 0.72, 0.0))
		vp.queue_free()
		await _frames(2)
	# the hub card portrait
	var holder := Control.new()
	root.add_child(holder)
	var portrait: Control = Portrait.new()
	portrait.size = Vector2(440, 660)
	holder.add_child(portrait)
	await _frames(2)
	portrait.viewport.size = Vector2i(440, 660)
	portrait.set_framing("hub")
	portrait.set_render_mode(Portrait.Mode.ONCE)
	portrait.set_class("sword_shield")
	await _frames(2)
	for race in races:
		portrait.model.dress({"appearance": {"race": race}})
		portrait.model.dress(_outfit(race))
		portrait._fit_camera()
		portrait._pivot.rotation.y = 0.0
		portrait._turn = 0.0
		portrait._turn_target = 0.0
		portrait.model.apply_pose(0.0)
		for state in ["before", "after"]:
			_set_metal(portrait.model, state == "after")
			await _save(portrait.viewport, "%s%s_card_%s.png" % [out, race, state])
	print("LV15_METAL_SHOTS DONE")
	quit()
