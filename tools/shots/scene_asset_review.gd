extends SceneTree
## Isolated landscape art captures. No profile, gameplay, or network requests.
const StageProps := preload("res://client/stage_props.gd")
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var paths := ["goblin_arena_a", "goblin_arena_b", "goblin_arena_c", "goblin_rest_camp", "brush_ring"]
	for id in paths:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1200, 720)
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("18252b")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("c7d6ed")
		env.environment.ambient_light_energy = .65
		viewport.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -30, 0)
		sun.light_energy = 1.1
		viewport.add_child(sun)
		var model: Node3D = load("res://art/maps/goblin_forest/%s.glb" % id).instantiate()
		viewport.add_child(model)
		StageProps.use_vertex_colors(model)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 42.0
		camera.position = Vector3(0, 33, 30)
		camera.look_at(Vector3(0, 0, -3))
		for frame in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(id + ".png"))
		if id == "goblin_arena_a":
			camera.size = 23.0
			camera.position = Vector3(0, 13, 12)
			camera.look_at(Vector3(0, 1, -10))
			for frame in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(output.path_join(id + "_detail.png"))
		viewport.queue_free()
		await process_frame
	print("Scene asset review saved: ", output)
	quit()
