extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://art/relics/goblin/icons")
	for id in ["goblin_medallion","goblin_lantern"]:
		var viewport := SubViewport.new();viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var doc := GLTFDocument.new();var state := GLTFState.new()
		assert(doc.append_from_file("res://art_source/props/goblin_base/parts/"+id+".glb",state)==OK)
		var model: Node3D=doc.generate_scene(state);viewport.add_child(model)
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var material=mesh.get_active_material(surface).duplicate();material.metallic=.35;mesh.set_surface_override_material(surface,material)
		var env := WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_CLEAR_COLOR;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;viewport.add_child(env)
		var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=1.4;viewport.add_child(sun)
		var camera := Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.185;camera.position=Vector3(.04,.095,.35);camera.look_at(Vector3(0,.075,0));camera.current=true
		for frame in 6:await process_frame
		RenderingServer.force_draw()
		var image := viewport.get_texture().get_image();image.resize(128,128,Image.INTERPOLATE_LANCZOS)
		assert(image.save_png("res://art/relics/goblin/icons/"+id+".png")==OK)
		viewport.queue_free();await process_frame
	print("GOBLIN RELIC ICONS PASS: original two models, transparent128px")
	quit()
