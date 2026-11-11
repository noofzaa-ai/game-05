extends SceneTree
## Visual review of the actual default New v1 game model and runtime sets.
const Model := preload("res://client/character_model.gd")
const Rules := preload("res://logic/item_rules_loader.gd")
const Loadout := preload("res://logic/loadout.gd")
const Items := preload("res://logic/item_system.gd")
const Assets := preload("res://client/item_assets.gd")

func _initialize() -> void:
	var out_dir := ProjectSettings.globalize_path("res://build/screenshots/new-v1")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.88, 0.85)
	env.ambient_light_energy = 0.8
	world.environment = env
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	viewport.add_child(light)
	preload("res://client/character_light.gd").light_scene(viewport, env, 0.5, 0.4)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.45
	camera.look_at_from_position(Vector3(4, 2.3, 4), Vector3(0, 0.9, 0))
	viewport.add_child(camera)
	var rules := Rules.load_default()
	var rng := RandomNumberGenerator.new()
	for style in ["fists", "blade", "dagger", "spear", "hammer"]:
		var model := Model.new()
		viewport.add_child(model)
		if not model.load_model(): quit(1); return
		var loadout := Loadout.new(rules)
		if style != "fists":
			var id: String = style + "_01"
			var base: Dictionary = rules.catalog.entry(id)
			loadout.equip(Items.create_item(rules, id, base["slot"], 0, rng, "", id))
		var looks := Assets.looks(loadout, rules.catalog, style)
		looks["appearance"] = {"skin": Color("f0cdb0")}
		model.dress(looks)
		for motion in ["idle", "run"]:
			model.set_pose(motion, 0.0, 1.0 if motion == "run" else 0.0, true, Vector2(1, 0), false, "", "", style)
			for f in 20: model.apply_pose(1.0 / 60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out_dir.path_join(style + "_" + motion + ".png"))
			print("NEW_V1_GAME_VIEW ", style, " ", motion, " ", model.current_clip())
		model.queue_free()
		await process_frame
	quit()
