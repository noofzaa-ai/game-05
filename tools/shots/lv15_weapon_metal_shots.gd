extends SceneTree
## Level-15 weapons, ink-metal glints before/after (client/characters/metal_glint.gd, kind "weapon"). Run windowed:
##   godot --path . --script res://tools/shots/lv15_weapon_metal_shots.gd
## ZORX_OUT=dir (default build/lv15_weapon_metal/), ZORX_RACES=human,viking, ZORX_WEAPON_DIR=res://art/weapons/race_zz_lv15_tmp/
## (a folder with <class>.glb = the delivery <class>_weapons_lv15.glb: all four races in one file, so the other races' meshes
## are hidden here; the split files art/weapons/race_<race>/<class>_lv15.glb have one race each).
## Per class and race: card portrait 440x660 (hub framing, front) and a 1280x720 fight view at two angles, "before" (weapon
## metal off) and "after". Armour is the same lv15 look with its glint on in both. Names: <class>_<race>_<card|fight_a|fight_b>_<before|after>.png

const Portrait := preload("res://client/card_portrait.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const MetalGlint := preload("res://client/characters/metal_glint.gd")
const SLOTS := ["shirt", "pants", "armband", "shoes"]
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const FAMILY := {"sword_shield": "blade", "greatsword": "greatsword", "longbow": "longbow", "magic": "magic"}
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


## Only this race's weapon meshes show (the delivery file holds four races), and the weapon glint is on or off.
func _weapon_state(model, race: String, metal_on: bool) -> void:
	for mesh in model._race_weapon_meshes:
		var is_race := str(mesh.name).to_lower().contains("_" + race + "_") or not str(mesh.name).to_lower().contains("lv15_")
		mesh.visible = is_race
	for mesh in model._class_weapons:
		mesh.visible = false  # the delivery file stands in for the whole kit
	for mesh in model._class_shield:
		mesh.visible = false
	for material in model._toon:
		if MetalGlint.is_weapon_material(material.resource_name):
			material.set_shader_parameter("use_metal", metal_on)


func _look(cls: String, race: String, dir: String) -> Dictionary:
	var file := dir + cls + ".glb"
	var look := _outfit(race)
	look["weapon"] = {"path": file, "family": FAMILY[cls], "style": FAMILY[cls]}
	return look


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
		out = ProjectSettings.globalize_path("res://build/lv15_weapon_metal/")
	out = out.rstrip("/") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	var dir := OS.get_environment("ZORX_WEAPON_DIR")
	if dir.is_empty():
		dir = "res://art/weapons/race_zz_lv15_tmp/"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var races: PackedStringArray = ["human", "viking"]
	if not OS.get_environment("ZORX_RACES").is_empty():
		races = OS.get_environment("ZORX_RACES").split(",")
	# fight views
	var stage := _stage(Vector2i(1280, 720))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	for cls in CLASSES:
		model.dress({"class": cls})
		for race in races:
			model.dress({"appearance": {"race": race}})
			model.dress(_look(cls, race, dir))
			await _frames(2)
			for angle in ANGLES:
				model.rotation.y = deg_to_rad(ANGLES[angle])
				cam.position = Vector3(0.0, 1.30, 2.6)
				cam.look_at(Vector3(0.0, 0.72, 0.0))
				model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
				for i in 3:
					model.apply_pose(0.11)
				for state in ["before", "after"]:
					_weapon_state(model, race, state == "after")
					await _save(vp, "%s%s_%s_fight_%s_%s.png" % [out, cls, race, angle, state])
					cam.position = Vector3(0.0, 0.95, 1.45)
					cam.look_at(Vector3(0.0, 0.62, 0.0))
					await _save(vp, "%s%s_%s_close_%s_%s.png" % [out, cls, race, angle, state])
					cam.position = Vector3(0.0, 1.30, 2.6)
					cam.look_at(Vector3(0.0, 0.72, 0.0))
	vp.queue_free()
	await _frames(2)
	# hub card portrait
	var holder := Control.new()
	root.add_child(holder)
	var portrait: Control = Portrait.new()
	portrait.size = Vector2(440, 660)
	holder.add_child(portrait)
	await _frames(2)
	portrait.viewport.size = Vector2i(440, 660)
	portrait.set_framing("hub")
	portrait.set_render_mode(Portrait.Mode.ONCE)
	for cls in CLASSES:
		portrait.set_class(cls)
		await _frames(2)
		for race in races:
			portrait.model.dress({"appearance": {"race": race}})
			portrait.model.dress(_look(cls, race, dir))
			portrait._fit_camera()
			portrait._pivot.rotation.y = 0.0
			portrait._turn = 0.0
			portrait._turn_target = 0.0
			portrait.model.apply_pose(0.0)
			for state in ["before", "after"]:
				_weapon_state(portrait.model, race, state == "after")
				await _save(portrait.viewport, "%s%s_%s_card_%s.png" % [out, cls, race, state])
	print("LV15_WEAPON_METAL_SHOTS DONE")
	quit()
