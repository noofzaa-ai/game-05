extends SceneTree
## Look-only preview of the model team's verdant_reach map art (art/maps/verdant_reach, not a playable
## map yet): the terrain + landmarks GLB, the props placed from instances.json (one MultiMesh per prop),
## the chibi player for scale, simple sun + sky. Saves:
##   0_overview      the whole 192 m map from high above
##   1_<clearing>    the game's default camera (pitch 38, 12 m, as in design.json) over each clearing
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/verdant_shot.gd -- <out_dir>

const DIR := "res://art/maps/verdant_reach/"
const PLAYER := "res://art/characters/chibi-studio/chibi_base_animated.glb"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://verdant_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "design.json"))
	var world := Node3D.new()
	root.add_child(world)
	_light(world)
	var terrain: Node = load(DIR + "terrain_landmarks.glb").instantiate()
	_use_vertex_colors(terrain)
	world.add_child(terrain)
	var counts := _props(world)
	print("props placed: ", counts)
	var heights: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "heightmap.json"))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true

	camera.fov = 50.0
	camera.far = 600.0
	camera.look_at_from_position(Vector3(0, 230, 120), Vector3.ZERO)
	await _save(out, "0_overview")

	var cam: Dictionary = design["camera"]
	camera.fov = float(cam["vertical_fov_degrees"])
	camera.far = 300.0
	var player: Node3D = load(PLAYER).instantiate()
	world.add_child(player)
	for clearing in design["clearings"]:
		var spot := Vector3(float(clearing["x"]), 0.0, float(clearing["z"]))
		spot.y = _height(heights, spot.x, spot.z)
		player.position = spot
		var pitch := deg_to_rad(float(cam["pitch_degrees"]))
		var target := spot + Vector3(0, float(cam["target_height_m"]), 0)
		camera.look_at_from_position(target + Vector3(0, sin(pitch), cos(pitch)) * float(cam["distance_m"]), target)
		print(clearing["id"], " player ", spot, " camera ", camera.global_position)
		await _save(out, "1_" + str(clearing["id"]))
	quit()


func _light(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = env
	world.add_child(holder)


## instances.json: {prop: [[x, y, z, yaw, scale, scale_y?], ...]} -> one MultiMesh per mesh of each prop.
func _props(world: Node3D) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "instances.json"))
	var counts := {}
	for prop in data:
		var path := DIR + "props/%s.glb" % prop
		if not ResourceLoader.exists(path):
			continue
		var scene: Node = load(path).instantiate()
		_use_vertex_colors(scene)
		for mesh_node in scene.find_children("*", "MeshInstance3D", true, false):
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh_node.mesh
			multi.instance_count = data[prop].size()
			var local: Transform3D = mesh_node.global_transform if mesh_node.is_inside_tree() else _local_to(scene, mesh_node)
			for i in data[prop].size():
				var row: Array = data[prop][i]
				var scale := float(row[4])
				var scale_y := float(row[5]) if row.size() > 5 else 1.0
				var basis := Basis(Vector3.UP, float(row[3])).scaled(Vector3(scale, scale * scale_y, scale))
				multi.set_instance_transform(i, Transform3D(basis, Vector3(row[0], row[1], row[2])) * local)
			var holder := MultiMeshInstance3D.new()
			holder.multimesh = multi
			world.add_child(holder)
		counts[prop] = data[prop].size()
		scene.free()
	return counts


## The model team paints most surfaces with vertex colors (COLOR_0); Godot's glTF import leaves
## vertex_color_use_as_albedo off, so they render white. Switched on for every material (textures are painted masks multiplied by the vertex colors).
## (For the real map do this in the .import settings or a material pass, not at runtime.)
func _use_vertex_colors(scene: Node) -> void:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = true


func _local_to(top: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != top:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _height(h: Dictionary, x: float, z: float) -> float:
	var step := float(h["step_m"])
	var grid: Array = h["heights"]
	var i := clampi(int(round((z - float(h["origin_z"])) / step)), 0, grid.size() - 1)
	var j := clampi(int(round((x - float(h["origin_x"])) / step)), 0, grid[i].size() - 1)
	return float(grid[i][j])


func _save(out: String, name: String) -> void:
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
