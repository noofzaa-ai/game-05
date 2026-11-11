extends RefCounted
## Floating-island board (Boss 2026-11-10, auto-battler, Teamfight-Tactics style, phone held upright;
## map camera_style "arena"). The simulation owns the real bounds (map.half_width / half_depth); this only
## builds the look: a tiled board, a stone rim, a rock underside that tapers to a point, and a sky around.
## The map's own art scene (built for big stages) is hidden: only its lights stay.

const TILE_A := Color(0.43, 0.58, 0.36)
const TILE_B := Color(0.38, 0.52, 0.32)
const RIM := Color(0.62, 0.60, 0.55)
const ROCK := Color(0.42, 0.34, 0.28)
const ROCK_DARK := Color(0.30, 0.25, 0.22)
const BORDER_COLOR := Color(0.86, 0.68, 0.30)


## Hides the art scene's geometry (its ground and props); lights and markers stay.
static func hide_scene(root: Node) -> int:
	var hidden := 0
	for node in root.find_children("*", "VisualInstance3D", true, false):
		if node is Light3D:
			continue
		var parent := node.get_parent()
		if node is MultiMeshInstance3D or String(node.name) == "Ground" or (parent != null and String(parent.name) in ["Ground"]):
			node.visible = false
			hidden += 1
	return hidden


## The atmosphere's 240 m ground plane (a PlaneMesh directly under the stage) would hide the sky below the island.
static func hide_ground_plane(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node.mesh is PlaneMesh and (node.mesh as PlaneMesh).size.x >= 100.0:
			node.visible = false


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material


## The island under and around the board. Returns its root node.
static func add_island(parent: Node3D, map) -> Node3D:
	var island := Node3D.new()
	island.name = "FloatingIsland"
	var w: float = map.half_width
	var d: float = map.half_depth
	# Tiled top: one MultiMesh of 1 m tiles, alternating tones.
	var tile := BoxMesh.new()
	tile.size = Vector3(0.98, 0.3, 0.98)
	tile.material = _material(Color.WHITE)
	(tile.material as StandardMaterial3D).vertex_color_use_as_albedo = true
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = tile
	var columns := int(ceil(w * 2.0))
	var rows := int(ceil(d * 2.0))
	multimesh.instance_count = columns * rows
	var index := 0
	for r in rows:
		for c in columns:
			var at := Vector3(-w + 0.5 + float(c) * (w * 2.0 / columns), -0.15, -d + 0.5 + float(r) * (d * 2.0 / rows))
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))
			multimesh.set_instance_color(index, TILE_A if (r + c) % 2 == 0 else TILE_B)
			index += 1
	var tiles := MultiMeshInstance3D.new()
	tiles.multimesh = multimesh
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	island.add_child(tiles)
	# Stone rim around the board.
	var rim_material := _material(RIM)
	for edge in [[Vector3(0, -0.12, -d - 0.25), Vector3(2 * w + 1.0, 0.5, 0.5)], [Vector3(0, -0.12, d + 0.25), Vector3(2 * w + 1.0, 0.5, 0.5)],
			[Vector3(-w - 0.25, -0.12, 0), Vector3(0.5, 0.5, 2 * d)], [Vector3(w + 0.25, -0.12, 0), Vector3(0.5, 0.5, 2 * d)]]:
		var rim := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = edge[1]
		box.material = rim_material
		rim.mesh = box
		rim.position = edge[0]
		island.add_child(rim)
	# Thin gold line on the board's edge.
	var gold := _material(BORDER_COLOR)
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for edge in [[Vector3(0, 0.01, -d), Vector3(2 * w, 0.02, 0.08)], [Vector3(0, 0.01, d), Vector3(2 * w, 0.02, 0.08)],
			[Vector3(-w, 0.01, 0), Vector3(0.08, 0.02, 2 * d)], [Vector3(w, 0.01, 0), Vector3(0.08, 0.02, 2 * d)]]:
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = edge[1]
		box.material = gold
		line.mesh = box
		line.position = edge[0]
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		island.add_child(line)
	# Rock underside: a stack of cones tapering to a point, offset a little so it is not a perfect spike.
	var rock_material := _material(ROCK)
	var dark_material := _material(ROCK_DARK)
	var layers := [[0.0, 1.0, 1.4], [-1.6, 0.78, 1.8], [-3.6, 0.5, 2.0], [-5.8, 0.24, 2.4]]
	for layer in layers:
		var cone := CylinderMesh.new()
		cone.top_radius = 1.0
		cone.bottom_radius = 0.2
		cone.height = float(layer[2])
		cone.radial_segments = 10
		cone.rings = 1
		cone.material = rock_material if int(abs(layer[0])) % 2 == 0 else dark_material
		var instance := MeshInstance3D.new()
		instance.mesh = cone
		instance.scale = Vector3(w * 1.45 * float(layer[1]) + 0.3, 1.0, d * 1.45 * float(layer[1]) + 0.3)
		instance.position = Vector3(0, -0.45 + float(layer[0]) - float(layer[2]) * 0.5, 0)
		island.add_child(instance)
	# A few small rocks drifting around the island and a ring of soft clouds below, so it reads as floating.
	var cloud_material := _material(Color(1, 1, 1))
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_material.albedo_color = Color(1, 1, 1, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 7:
		var cloud := MeshInstance3D.new()
		var puff := SphereMesh.new()
		puff.radius = 1.0
		puff.height = 1.2
		puff.material = cloud_material
		cloud.mesh = puff
		var angle := TAU * float(i) / 7.0 + rng.randf() * 0.4
		cloud.position = Vector3(cos(angle) * (w + 3.5 + rng.randf() * 2.0), -4.2 - rng.randf() * 1.5, sin(angle) * (d + 3.0 + rng.randf() * 2.0))
		cloud.scale = Vector3(2.2 + rng.randf() * 1.5, 1.0, 1.6 + rng.randf())
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		island.add_child(cloud)
	for i in 4:
		var chunk := MeshInstance3D.new()
		var lump := CylinderMesh.new()
		lump.top_radius = 0.6
		lump.bottom_radius = 0.1
		lump.height = 1.1
		lump.radial_segments = 7
		lump.material = rock_material
		chunk.mesh = lump
		var side := -1.0 if i % 2 == 0 else 1.0
		chunk.position = Vector3(side * (w + 1.8 + rng.randf() * 1.2), -1.0 - rng.randf() * 2.5, -d + float(i) * (d * 0.7) + rng.randf())
		island.add_child(chunk)
	parent.add_child(island)
	return island


## A soft sky (day) around the island instead of the stage's ink sky; fog off so the rock stays crisp.
static func set_sky(root: Node) -> void:
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = node.environment
		if env == null:
			continue
		var material := ProceduralSkyMaterial.new()
		material.sky_top_color = Color(0.30, 0.58, 0.95)
		material.sky_horizon_color = Color(0.80, 0.90, 1.0)
		material.ground_horizon_color = Color(0.80, 0.90, 1.0)
		material.ground_bottom_color = Color(0.62, 0.78, 0.98)
		var sky := Sky.new()
		sky.sky_material = material
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.fog_enabled = false
		env.adjustment_enabled = true
		env.adjustment_saturation = 1.25
		env.adjustment_contrast = 1.05
		env.ambient_light_color = Color(0.85, 0.88, 0.92)
		env.ambient_light_energy = 0.6



## ---- Goblin camp island (Boss 2026-11-10: "a proper map like the original, not a football pitch") ----
## The kit pieces of the map's own art scene (palisade, gate, towers, huts, banners, crates, stones, logs,
## weapon rack, grass) are re-placed around a dirt yard on a floating island. The yard (the board) stays
## clear; walls, towers and huts stand on a grass margin around it. `variant` is the map id.

const DIRT := Color(0.52, 0.40, 0.29)
const DIRT_DARK := Color(0.42, 0.32, 0.23)
const GRASS := Color(0.30, 0.46, 0.24)
const SOIL := Color(0.36, 0.27, 0.20)
const MARGIN_X := 3.6  ## island ground beyond the board, sides
const MARGIN_Z := 3.4  ## ... front and back


static func _kit(root: Node, node_name: String) -> Mesh:
	var node := root.find_child(node_name, true, false)
	if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		return node.multimesh.mesh
	return null


static func _place(parent: Node3D, mesh: Mesh, transforms: Array) -> void:
	if mesh == null or transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	parent.add_child(instance)


static func _at(x: float, z: float, yaw_deg: float = 0.0, scale_by: float = 1.0, y: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale_by), Vector3(x, y, z))


## The yard: a subdivided plane with vertex colours (dirt in the middle, grass outside, dark dirt patches).
static func _ground(w: float, d: float, board_w: float, board_d: float, seed: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cell := 0.5
	var nx := int(ceil(w * 2.0 / cell))
	var ny := int(ceil(d * 2.0 / cell))
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in ny + 1:
		for i in nx + 1:
			var x := -w + float(i) * (w * 2.0 / nx)
			var z := -d + float(j) * (d * 2.0 / ny)
			vertices.append(Vector3(x, 0.0, z))
			normals.append(Vector3.UP)
			var edge := maxf(absf(x) - (board_w + 0.6), absf(z) - (board_d + 0.6))
			var amount := smoothstep(-0.2, 1.4, edge)
			var dirt := DIRT.lerp(DIRT_DARK, clampf(sin(x * 1.7 + z * 0.9) * sin(z * 2.3 - x * 0.6) * 0.5 + 0.5, 0.0, 1.0) * 0.6)
			colors.append(dirt.lerp(GRASS.lerp(GRASS.darkened(0.15), rng.randf() * 0.6), amount))
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			indices.append_array([a, a + 1, a + nx + 1, a + 1, a + nx + 2, a + nx + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = 0.0
	return instance


static func build_camp(parent: Node3D, scene_root: Node, map, variant: String = "") -> Node3D:
	var camp := Node3D.new()
	camp.name = "GoblinCampIsland"
	var bw: float = map.half_width
	var bd: float = map.half_depth
	var w := bw + MARGIN_X
	var d := bd + MARGIN_Z
	camp.add_child(_ground(w, d, bw, bd, hash(variant)))
	# Soil fascia around the yard's edge and the rock underneath it.
	var soil := _material(SOIL)
	for edge in [[Vector3(0, -0.45, -d), Vector3(2 * w, 0.9, 0.3)], [Vector3(0, -0.45, d), Vector3(2 * w, 0.9, 0.3)], [Vector3(-w, -0.45, 0), Vector3(0.3, 0.9, 2 * d)], [Vector3(w, -0.45, 0), Vector3(0.3, 0.9, 2 * d)]]:
		var fascia := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = edge[1]
		box.material = soil
		fascia.mesh = box
		fascia.position = edge[0]
		camp.add_child(fascia)
	_add_underside(camp, w, d)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(variant) + 5
	var palisade: Mesh = _kit(scene_root, "palisade")
	var gate: Mesh = _kit(scene_root, "gate")
	var tower: Mesh = _kit(scene_root, "tower")
	var hut: Mesh = _kit(scene_root, "hut")
	var banner: Mesh = _kit(scene_root, "banner")
	var corner: Mesh = _kit(scene_root, "corner")
	var crate: Mesh = _kit(scene_root, "goblin_crate")
	var stone: Mesh = _kit(scene_root, "goblin_stoneblock")
	var logwall: Mesh = _kit(scene_root, "goblin_logwall")
	var rack: Mesh = _kit(scene_root, "weapon_rack")
	var tufts: Mesh = _kit(scene_root, "GrassTufts")
	var ferns: Mesh = _kit(scene_root, "Ferns")
	# Back wall (north) with the gate in the middle, side walls, open cliff in front.
	var pieces: Array = []
	var x := -w + 1.2
	while x <= w - 1.0:
		if absf(x) > 1.6:
			pieces.append(_at(x, -d + 0.6, 0.0))
		x += 1.9
	var z := -d + 2.4
	while z <= d - 2.2:
		pieces.append(_at(-w + 0.6, z, 90.0))
		pieces.append(_at(w - 0.6, z, 90.0))
		z += 1.9
	_place(camp, palisade, pieces)
	_place(camp, gate, [_at(0.0, -d + 0.6, 0.0)])
	_place(camp, tower, [_at(-w + 1.5, -d + 1.6, 0.0), _at(w - 1.5, -d + 1.6, 180.0)])
	_place(camp, corner, [_at(-w + 0.8, d - 0.8, 90.0), _at(w - 0.8, d - 0.8, -90.0)])
	var huts: Array = [_at(-w + 3.2, -d + 2.8, 20.0), _at(w - 3.4, -d + 2.7, -20.0)]
	if variant.contains("chief"):
		huts = [_at(-w + 3.0, -d + 2.7, 15.0)]
	if not variant.contains("quarry"):
		_place(camp, hut, huts)
	_place(camp, banner, [_at(-3.2, -d + 1.4, 0.0), _at(3.2, -d + 1.4, 0.0)] + ([_at(-6.0, -d + 1.4, 0.0), _at(6.0, -d + 1.4, 0.0)] if variant.contains("chief") else []))
	_place(camp, rack, [_at(-w + 1.4, -1.2, 90.0)])
	# Clutter on the margins (never on the board).
	var crates: Array = [_at(w - 2.0, bd + 1.5, 15.0), _at(w - 1.0, bd + 1.8, -20.0, 0.9), _at(-w + 2.2, bd + 2.0, 40.0), _at(w - 1.6, -bd - 1.4, 0.0)]
	var stones: Array = [_at(-w + 1.6, bd + 1.4, 10.0), _at(0.0, bd + 2.5, 70.0, 1.2), _at(w - 3.4, bd + 2.4, 30.0)]
	var logs: Array = [_at(-w + 1.2, -bd - 1.4, 90.0), _at(-5.5, bd + 2.6, 0.0)]
	if variant.contains("quarry"):
		stones += [_at(-3.0, bd + 2.2, 0.0, 1.3), _at(5.0, -bd - 1.6, 50.0, 1.4), _at(-w + 1.5, 0.0, 30.0, 1.5)]
		logs += [_at(3.5, bd + 2.7, 0.0), _at(w - 1.3, 1.2, 90.0)]
	if variant.contains("courtyard"):
		crates += [_at(-4.0, bd + 2.4, 0.0), _at(4.2, bd + 2.6, 25.0), _at(-w + 1.4, 2.0, 0.0)]
	_place(camp, crate, crates)
	_place(camp, stone, stones)
	_place(camp, logwall, logs)
	# Grass tufts and ferns on the margin only.
	var tuft_list: Array = []
	var fern_list: Array = []
	for i in 260:
		var tx := rng.randf_range(-w + 0.4, w - 0.4)
		var tz := rng.randf_range(-d + 0.6, d - 0.4)
		if absf(tx) < bw + 0.3 and absf(tz) < bd + 0.3 and rng.randf() > 0.12:
			continue
		var list: Array = fern_list if i % 23 == 0 else tuft_list
		list.append(_at(tx, tz, rng.randf() * 360.0, 0.8 + rng.randf() * 0.6))
	_place(camp, tufts, tuft_list)
	_place(camp, ferns, fern_list)
	# Warm firelight at the gate and by the towers.
	for spot in [Vector3(-2.4, 1.6, -d + 1.0), Vector3(2.4, 1.6, -d + 1.0), Vector3(-w + 1.8, 2.2, -d + 2.2), Vector3(w - 1.8, 2.2, -d + 2.2)]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.3)
		light.light_energy = 1.4
		light.omni_range = 7.0
		light.shadow_enabled = false
		light.position = spot
		camp.add_child(light)
	parent.add_child(camp)
	return camp


static func _add_underside(parent: Node3D, w: float, d: float) -> void:
	var rock := _material(ROCK)
	var dark := _material(ROCK_DARK)
	var layers := [[0.0, 1.0, 1.5], [-1.5, 0.80, 1.9], [-3.4, 0.55, 2.2], [-5.6, 0.28, 2.6]]
	for layer in layers:
		var cone := CylinderMesh.new()
		cone.top_radius = 1.0
		cone.bottom_radius = 0.2
		cone.height = float(layer[2])
		cone.radial_segments = 14
		cone.rings = 1
		cone.material = rock if int(abs(layer[0] * 2.0)) % 2 == 0 else dark
		var instance := MeshInstance3D.new()
		instance.mesh = cone
		instance.scale = Vector3(w * 1.38 * float(layer[1]) + 0.3, 1.0, d * 1.38 * float(layer[1]) + 0.3)
		instance.position = Vector3(0, -0.9 + float(layer[0]) - float(layer[2]) * 0.5, 0)
		parent.add_child(instance)
