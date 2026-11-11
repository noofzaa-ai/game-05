extends SceneTree
## Render actual armor geometry into transparent, tightly framed 192px inventory art.
func meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): meshes(child,result)
func _initialize() -> void:
	await process_frame
	var viewport := SubViewport.new()
	viewport.size=Vector2i(192,192)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_CLEAR_COLOR
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color.WHITE
	environment.ambient_light_energy=.85
	world.environment=environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-25,-30,0)
	light.light_energy=1.5
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	for style in ["obsidian_gold","obsidian_leather","obsidian_cloth","royal_gold","royal_leather","royal_cloth","ash_steel","ash_leather","ash_cloth"]:
		for slot in ["head","shirt","pants","arms","shoes"]:
			var folder: String = "res://art/armor/"+style+"/"
			var asset = load(folder+slot+".glb").instantiate()
			viewport.add_child(asset)
			var pieces: Array = []
			meshes(asset,pieces)
			var bounds: AABB = pieces[0].global_transform*pieces[0].get_aabb()
			for piece in pieces: bounds=bounds.merge(piece.global_transform*piece.get_aabb())
			camera.size=maxf(bounds.size.y,bounds.size.x)*1.16
			camera.position=bounds.get_center()+Vector3(0,0,3)
			camera.look_at(bounds.get_center())
			for frame in 2: await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder+"icon-"+slot+".png"))
			asset.queue_free()
			await process_frame
			print("TRANSPARENT ARMOR ICON ",style,"/",slot)
	quit()
