extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 288)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d3dfed")
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.0
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.2
	camera.position = Vector3(6, 6, 8)
	world.add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://art/ui/facility_levels")
	for kind in ["campfire", "refine", "upgrade"]:
		for level in [1, 2, 3]:
			var path := "res://art/props/campfire_workshop/campfire_level_%d.glb" % level if kind == "campfire" else "res://art/props/camp_modular/workshops/%s_lv%d.glb" % [kind, level]
			var packed := load(path) as PackedScene
			var model := packed.instantiate() as Node3D
			world.add_child(model)
			for frame in range(5): await process_frame
			await RenderingServer.frame_post_draw
			var img := viewport.get_texture().get_image()
			img = img.get_region(img.get_used_rect())
			var fit := minf(244.0 / img.get_width(), 180.0 / img.get_height())
			img.resize(maxi(1, int(img.get_width() * fit)), maxi(1, int(img.get_height() * fit)), Image.INTERPOLATE_LANCZOS)
			var canvas := Image.create(256, 192, false, Image.FORMAT_RGBA8)
			canvas.fill(Color.TRANSPARENT)
			canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (Vector2i(256, 192) - img.get_size()) / 2)
			img = canvas
			img.save_png("res://art/ui/facility_levels/%s_lv%d.png" % [kind, level])
			world.remove_child(model)
			model.queue_free()
	quit()
