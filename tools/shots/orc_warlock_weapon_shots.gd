extends SceneTree
## Orc Warlock boss weapons (PLACEHOLDER 3D, tools/items/build_orc_warlock_weapons.py) on a Sword & Shield card: the sword in
## the right hand and the shield on the left forearm. Close 3/4 view + fight camera for idle / light / heavy / ultimate / guard
## (+ a front view of the guard), and the hero card portrait. ZORX_REF=1 shoots the human level-15 sword & shield instead.
## Run windowed: godot --path . --script res://tools/shots/orc_warlock_weapon_shots.gd   Output: build/orc_warlock_weapons/

const Portrait := preload("res://client/card_portrait.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const OUT := "res://build/orc_warlock_weapons/"
const SWORD := "res://art/weapons/race_boss/orc_warlock_sword.glb"
const SHIELD := "res://art/weapons/race_boss/orc_warlock_shield.glb"
const POSES := [["idle", "idle", "", "", 0.5], ["light", "punch_r", "light_1", "strike", 0.5], ["heavy", "heavy", "heavy", "strike", 0.5],
	["ult", "punch_r", "ultimate", "strike", 0.5], ["guard", "guard", "", "", 0.5]]


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(vp: SubViewport, name: String) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await _frames(3)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + name)
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", path)


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
	sun.shadow_enabled = true
	vp.add_child(sun)
	CharacterLight.light_scene(vp, env, CardTokens.PORTRAIT_KEY_ENERGY, CardTokens.PORTRAIT_RIM_ENERGY)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.6, 0.5)
	ground.material_override = m
	vp.add_child(ground)
	var cam := Camera3D.new()
	vp.add_child(cam)
	return {"vp": vp, "cam": cam}


func _files() -> Array:
	if OS.get_environment("ZORX_REF") == "1":
		return ["res://art/weapons/race_human/sword_shield_lv15.glb", "res://art/weapons/race_human/shield_lv15.glb", "ref_"]
	return [SWORD, SHIELD, ""]


func _dress(model) -> void:
	var f := _files()
	model.dress({"class": "sword_shield", "weapon": {"path": f[0], "family": "blade", "style": "blade"},
		"offhand": {"item_id": "boss_orc_warlock_shield", "asset_id": "", "procedural": false, "path": f[1], "refine_level": 0}})


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var stage := _stage(Vector2i(480, 560))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	var model = CharacterModel.new()
	model.ink_outline = true
	model.class_id = "sword_shield"
	vp.add_child(model)
	model.load_model()
	_dress(model)
	var p: String = _files()[2]
	print("race weapon meshes=", model._race_weapon_meshes.map(func(x): return str(x.name)), " shield=", model._race_shield_meshes.map(func(x): return str(x.name)), " kind=", model.shield_kind())
	for pose in POSES:
		model.set_pose(pose[1], pose[4], 1.0, true, Vector2(0, 1), false, pose[3], pose[2], "blade")
		for k in 12:
			model.apply_pose(0.033)
		var views := ["close", "fight"]
		if pose[0] == "guard" or pose[0] == "idle":
			views.append("front")
		for view in views:
			if view == "close":
				cam.fov = 40.0
				model.rotation.y = deg_to_rad(35.0)
				cam.position = Vector3(0.0, 1.3, 2.9)
				cam.look_at(Vector3(0.0, 0.7, 0.0))
			elif view == "front":
				cam.fov = 40.0
				model.rotation.y = deg_to_rad(-40.0)
				cam.position = Vector3(0.0, 1.0, 2.4)
				cam.look_at(Vector3(0.0, 0.75, 0.0))
			else:
				cam.fov = 45.0
				model.rotation.y = 0.0
				cam.position = Vector3(0.0, 3.0, 7.0) * 0.55
				cam.look_at(Vector3(0.0, 0.5, 0.0))
			await _save(vp, "%s%s_%s.png" % [p, pose[0], view])
	vp.queue_free()
	await _frames(2)
	var holder := Control.new()
	root.add_child(holder)
	var portrait: Control = Portrait.new()
	portrait.size = Vector2(300, 450)
	holder.add_child(portrait)
	await _frames(2)
	portrait.viewport.size = Vector2i(300, 450)
	portrait.set_framing("hub")
	portrait.set_render_mode(Portrait.Mode.ONCE)
	portrait.set_class("sword_shield")
	await _frames(2)
	_dress(portrait.model)
	portrait._fit_camera()
	portrait.model.apply_pose(0.0)
	await _save(portrait.viewport, "%scard.png" % p)
	print("ORC_WARLOCK_WEAPON_SHOTS DONE")
	quit()
