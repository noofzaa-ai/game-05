extends SceneTree
## Boss unique weapons (tools/items/build_boss_weapons.py) in the hand: Great Sword card with the Pharaoh's crook, Magic card
## with the High Wizard's staff. Close 3/4 view (idle, light attack, heavy, ultimate), the fight camera (party camera angle,
## offset (0, 3, 7) fov 45), the hero card portrait (hub framing), and 1024 transparent raw icon frames of each piece alone.
## Run windowed: godot --path . --script res://tools/shots/boss_weapon_shots.gd   Output: build/boss_weapons/shots/

const Portrait := preload("res://client/card_portrait.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const OUT := "res://build/boss_weapons/shots/"
const JOBS := [["greatsword", "res://art/weapons/race_boss/mummy_crook.glb", "crook"], ["magic", "res://art/weapons/race_boss/mummy_staff.glb", "staff"]]
const POSES := [["idle", "idle", "", "", 0.0], ["light", "punch_r", "light_1", "strike", 0.5], ["heavy", "heavy", "heavy", "strike", 0.5], ["ult", "punch_r", "ultimate", "strike", 0.5]]


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


func _stage(size: Vector2i, clear := false) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = clear
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if clear else Environment.BG_COLOR
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
	sun.shadow_enabled = not clear
	vp.add_child(sun)
	CharacterLight.light_scene(vp, env, CardTokens.PORTRAIT_KEY_ENERGY, CardTokens.PORTRAIT_RIM_ENERGY)
	if not clear:
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


func _jobs() -> Array:
	if OS.get_environment("ZORX_REF") == "1":  # the player's own level-15 weapons, for the size check
		return [["greatsword", "res://art/weapons/race_human/greatsword_lv15.glb", "ref_greatsword"], ["magic", "res://art/weapons/race_human/magic_lv15.glb", "ref_staff"]]
	return JOBS


func _dress(model, cls: String, path: String) -> void:
	model.dress({"class": cls, "weapon": {"path": path, "family": cls, "style": cls}})


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await _hand_shots()
	if OS.get_environment("ZORX_REF") == "1":
		quit()
		return
	await _portraits()
	await _icons()
	print("BOSS_WEAPON_SHOTS DONE")
	quit()


func _hand_shots() -> void:
	var stage := _stage(Vector2i(480, 560))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	for job in _jobs():
		_dress(model, job[0], job[1])
		print("WEAPON ", job[2], " race meshes=", model._race_weapon_meshes.size(), " gear weapons=", model._gear_weapons.map(func(m): return str(m.name)))
		for pose in POSES:
			model.set_pose(pose[1], 0.5, 1.0, true, Vector2(0, 1), false, pose[3], pose[2], job[0])
			for k in 12:
				model.apply_pose(0.033)
			for view in ["close", "fight"]:
				if view == "close":
					cam.fov = 40.0
					model.rotation.y = deg_to_rad(35.0)
					cam.position = Vector3(0.0, 1.3, 2.9)
					cam.look_at(Vector3(0.0, 0.7, 0.0))
				else:
					cam.fov = 45.0
					model.rotation.y = 0.0
					cam.position = Vector3(0.0, 3.0, 7.0) * 0.55
					cam.look_at(Vector3(0.0, 0.5, 0.0))
				await _save(vp, "%s_%s_%s.png" % [job[2], pose[0], view])
	vp.queue_free()
	await _frames(2)


func _portraits() -> void:
	var holder := Control.new()
	root.add_child(holder)
	var portrait: Control = Portrait.new()
	portrait.size = Vector2(300, 450)
	holder.add_child(portrait)
	await _frames(2)
	portrait.viewport.size = Vector2i(300, 450)
	portrait.set_framing("hub")
	portrait.set_render_mode(Portrait.Mode.ONCE)
	for job in JOBS:
		portrait.set_class(job[0])
		await _frames(2)
		_dress(portrait.model, job[0], job[1])
		portrait._fit_camera()
		portrait.model.apply_pose(0.0)
		await _save(portrait.viewport, "%s_card.png" % job[2])
	holder.queue_free()
	await _frames(2)


## Each weapon alone in the bind pose, from above / square to the shaft (like tools/shots/race_outfit_shots.gd _icons).
func _icons() -> void:
	var stage := _stage(Vector2i(1024, 1024), true)
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	var views := {"crook": [Vector3(0.761, -0.042, 0.648), Vector3(-0.616, 0.268, 0.741)], "staff": [Vector3(0.19, 0.32, 0.93), Vector3(-0.48, -0.79, 0.38)]}
	for job in JOBS:
		_dress(model, job[0], job[1])
		model._skeleton.reset_bone_poses()
		for mesh in model._skeleton.find_children("*", "MeshInstance3D", true, false):
			var keep := false
			for piece in model._race_weapon_meshes:
				keep = keep or mesh == piece or piece.is_ancestor_of(mesh)
			mesh.visible = keep
		var basis: Basis = model._skeleton.global_transform.basis.orthonormalized()
		var view: Array = views[job[2]]
		var center: Vector3 = model._skeleton.global_position + Vector3(0.0, 0.68, 0.0)
		cam.size = 2.4
		for attempt in 2:
			cam.position = center + (basis * (view[0] as Vector3).normalized()) * 6.0
			cam.look_at(center, basis * (view[1] as Vector3))
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await _frames(3)
			await RenderingServer.frame_post_draw
			var used: Rect2i = vp.get_texture().get_image().get_used_rect()
			if used.size.x <= 0:
				break
			var px := cam.size / float(vp.size.y)
			var mid := Vector2(used.position) + Vector2(used.size) * 0.5 - Vector2(vp.size) * 0.5
			center += cam.global_basis.x * mid.x * px - cam.global_basis.y * mid.y * px
			cam.size = maxf(float(used.size.x), float(used.size.y)) * px * 1.15
		await _save(vp, "iconraw-%s.png" % job[2])
	vp.queue_free()
