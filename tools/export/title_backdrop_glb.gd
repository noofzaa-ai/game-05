extends SceneTree
## Static, portable glTF snapshot of the procedural title scenery.
var converted := 0
var materials := {}

func _initialize() -> void:
	call_deferred("export_scene")

func portable(source: Material) -> Material:
	if not source is ShaderMaterial:
		return source
	if materials.has(source):
		return materials[source]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shader: ShaderMaterial = source
	var code := shader.shader.code
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y in 512:
		for x in 512:
			var uv := Vector2(x, y) / 511.0
			var color := Color.TRANSPARENT
			if "uniform float disc" in code:
				var r := uv.distance_to(Vector2(0.5, 0.5))
				var body := 1.0 - smoothstep(0.274, 0.28, r)
				var glow := exp(-maxf(r - 0.28, 0.0) * 20.0) * 0.35
				color = Color(0.75, 0.83, 1.0, maxf(body, glow))
			elif "horizon_color" in code:
				var top: Color = shader.get_shader_parameter("top_color")
				var horizon: Color = shader.get_shader_parameter("horizon_color")
				color = top.lerp(horizon, smoothstep(0.0, 1.0, uv.y))
			else:
				var tint = shader.get_shader_parameter("tint")
				if tint is Color:
					color = tint
					color.a = sin(uv.x * PI) * sin(uv.y * PI) * 0.12
			image.set_pixel(x, y, color)
	mat.albedo_texture = ImageTexture.create_from_image(image)
	if not "horizon_color" in code:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materials[source] = mat
	return mat

func convert_node(node: Node) -> void:
	if node is MultiMeshInstance3D and node.multimesh != null:
		var multi: MultiMesh = node.multimesh
		for i in multi.instance_count:
			var mesh := MeshInstance3D.new()
			mesh.name = "Prop_%d" % i
			mesh.mesh = multi.mesh
			mesh.transform = multi.get_instance_transform(i)
			mesh.material_override = node.material_override
			node.add_child(mesh)
			converted += 1
		node.multimesh = null
	if node is MeshInstance3D:
		if node.material_override != null:
			node.material_override = portable(node.material_override)
		if node.mesh != null:
			for surface in node.mesh.get_surface_count():
				var original: Material = node.get_active_material(surface)
				if original is ShaderMaterial:
					node.set_surface_override_material(surface, portable(original))
	for child in node.get_children():
		if child is CPUParticles3D or child is WorldEnvironment:
			child.free()
		else:
			convert_node(child)

func export_scene() -> void:
	var backdrop = load("res://client/title_backdrop.gd").new()
	backdrop.name = "TitleBackdrop"
	backdrop.menu_shade = false
	root.add_child(backdrop)
	backdrop.set_process(false)
	await process_frame
	convert_node(backdrop)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(backdrop, state)
	if error == OK:
		error = document.write_to_filesystem(state, "res://art/scenes/title_backdrop.glb")
	print("Title GLB export: ", error, "; expanded props: ", converted)
	quit(0 if error == OK else 1)
