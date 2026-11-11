extends SceneTree
## Isolated visual review; does not load GameState profiles or contact any backend.
func _initialize() -> void:
	call_deferred("capture")

func bounds(node: Node) -> AABB:
	var result := AABB()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh != null:
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			result = box if result.size == Vector3.ZERO else result.merge(box)
	return result

func capture() -> void:
	root.size = Vector2i(1800, 900)
	var viewports: Array[SubViewport] = []
	var names := ["merchant", "quest_board", "storage", "blacksmith", "tailor"]
	for i in names.size():
		var vp := SubViewport.new()
		vp.size = Vector2i(600, 450)
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		viewports.append(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("222c35")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = .7
		vp.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -35, 0)
		light.light_energy = 1.1
		vp.add_child(light)
		var model: Node3D = load("res://art/npcs/%s.glb" % names[i]).instantiate()
		vp.add_child(model)
		var box := bounds(model)
		print(names[i], " bounds ", box)
		var factor := float(preload("res://client/hub_npc.gd").ROLE_VISUAL_SCALE.get("quest" if names[i] == "quest_board" else names[i], 1.0))
		model.scale *= factor
		model.position = Vector3.ZERO
		var camera := Camera3D.new()
		vp.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 4.2
		camera.position = Vector3(.3, 1.7, 6)
		camera.look_at(Vector3(0, 1.5, 0))
		var label := Label.new()
		label.text = str(names[i]) + " · Color 1024 / Normal+MR 512"
		label.add_theme_font_size_override("font_size", 18)
		label.position = Vector2(16, 12)
		vp.add_child(label)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var combined := Image.create(1800, 900, false, Image.FORMAT_RGBA8)
	combined.fill(Color("222c35"))
	for i in viewports.size():
		var image := viewports[i].get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		combined.blit_rect(image, Rect2i(0, 0, 600, 450), Vector2i((i % 3) * 600, (i / 3) * 450))
	combined.save_png(out)
	print("Saved NPC texture review: ", out)
	quit()
