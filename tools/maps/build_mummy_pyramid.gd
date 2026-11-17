extends SceneTree
## Builds the Mummy Pyramid stages (level-designer 2026-11-17, Boss: the mummies live ONLY in this zone and the map is
## made like the goblin map): data/maps/mummy_pyramid_*.json + art/maps/mummy_pyramid/*.tscn.
##   godot --headless --path . --script res://tools/maps/build_mummy_pyramid.gd
## The boards are the goblin boards: 16 x 9 m floating islands (camera_style arena), squad on the left, monsters on the
## right, no obstacles. client/arena_props.gd hides the scene's MultiMeshes and builds the tile island; this scene adds
## a sandstone terrace over it (a floor with painted slabs) and re-places the Boss-delivered tomb kit
## (art/props/mummy_tomb/mummy_kit.glb, 11 props) around the board: they are plain MeshInstance3D (a MultiMeshInstance3D
## would be hidden by hide_scene). Lights are light_fire empties (client/stage_props.gd turns them into flickering omni lights).
## The kit's meshes are saved once as art/props/mummy_tomb/meshes/*.res with ONE material (the kit albedo, no normal/MR map:
## web size) and an unshaded "mummy_fire" material for the flames. The kit GLB itself stays out of the web export.

const KIT := "res://art/props/mummy_tomb/mummy_kit.glb"
const MESH_DIR := "res://art/props/mummy_tomb/meshes/"
const SCENE_DIR := "res://art/maps/mummy_pyramid/"
const MAP_DIR := "res://data/maps/"
const W := 8.0
const D := 4.5
const TERRACE_SIDE := 3.2
const TERRACE_BACK := 3.6
const TERRACE_FRONT := 0.9

## Props: [kit name, x, z, yaw degrees, scale, y]
## Lights: [x, y, z] (light_fire at a torch/brazier flame)
const SPAWNS_FIGHT: Array = [
	["mummy", 2.6, -3.4], ["mummy", 2.6, -1.13], ["mummy", 2.6, 1.13], ["mummy", 2.6, 3.4],
	["mummy", 3.9, -3.4], ["mummy", 3.9, 0.0], ["mummy", 3.9, 3.4], ["mummy_archer", 6.8, 0.0]]
const SPAWNS_BOSS: Array = [
	["mummy_boss_placeholder", 5.2, 0.0], ["mummy", 2.6, -3.4], ["mummy", 2.6, 3.4],
	["mummy_archer", 6.8, -3.4], ["mummy_archer", 6.8, 3.4]]


static func layouts() -> Dictionary:
	var back := -D - 1.0  # z of the first row behind the board
	var gate := {
		"name": "Pyramid · Gate", "mood": "camp", "spawns": SPAWNS_FIGHT, "seed": 1,
		"props": [
			["stairs", 0.0, -D - 0.9, 0, 3.2, 0.0],
			["pillar", -3.3, -D - 1.2, 0, 1.0, 0.0], ["pillar", 3.3, -D - 1.2, 0, 1.0, 0.0],
			["torch", -5.0, -D - 1.0, 0, 1.0, 0.0], ["torch", 5.0, -D - 1.0, 0, 1.0, 0.0],
			["obelisk", -7.4, -D - 1.1, 0, 1.2, 0.0], ["obelisk", 7.4, -D - 1.1, 0, 1.2, 0.0],
			["anubis_urn", -9.4, -D - 0.2, 20, 1.0, 0.0], ["anubis_urn", 9.4, -D - 0.2, -20, 1.0, 0.0],
			["brazier", -W - 1.2, -1.6, 0, 1.0, 0.0], ["brazier", W + 1.2, 1.6, 0, 1.0, 0.0],
			["urn", -W - 1.4, 2.4, 30, 1.0, 0.0], ["urn", W + 1.5, -2.6, -10, 1.2, 0.0], ["urn", W + 2.0, -3.4, 50, 0.9, 0.0],
			["chest", -W - 1.6, 0.6, 90, 0.9, 0.0],
		],
		"walls": 12, "lights": [[-5.0, 2.3, -D - 1.0], [5.0, 2.3, -D - 1.0], [-W - 1.2, 1.5, -1.6], [W + 1.2, 1.5, 1.6]],
	}
	var hall := {
		"name": "Pyramid · Hall of Coffins", "mood": "night", "spawns": SPAWNS_FIGHT, "seed": 2,
		"props": [
			["coffin", -7.2, back, 0, 1.0, 0.0], ["coffin", -4.8, back, 0, 1.0, 0.0], ["coffin", -2.4, back, 0, 1.0, 0.0],
			["coffin", 0.0, back, 0, 1.0, 0.0], ["coffin", 2.4, back, 0, 1.0, 0.0], ["coffin", 4.8, back, 0, 1.0, 0.0], ["coffin", 7.2, back, 0, 1.0, 0.0],
			["pillar", -W - 1.3, -3.4, 0, 1.0, 0.0], ["pillar", -W - 1.3, 0.4, 0, 1.0, 0.0], ["pillar", W + 1.3, -3.4, 0, 1.0, 0.0], ["pillar", W + 1.3, 0.4, 0, 1.0, 0.0],
			["torch", -W - 1.3, -1.5, 0, 1.0, 0.0], ["torch", W + 1.3, -1.5, 0, 1.0, 0.0],
			["brazier", -3.6, back - 1.7, 0, 1.0, 0.0], ["brazier", 3.6, back - 1.7, 0, 1.0, 0.0],
			["anubis_urn", -W - 1.6, 3.0, 30, 1.0, 0.0], ["anubis_urn", W + 1.6, 3.0, -30, 1.0, 0.0],
			["urn", -9.9, 1.9, 0, 1.0, 0.0], ["urn", 9.9, -2.2, 40, 1.0, 0.0],
		],
		"walls": 12, "lights": [[-W - 1.3, 2.0, -1.5], [W + 1.3, 2.0, -1.5], [-3.6, 1.4, back - 1.7], [3.6, 1.4, back - 1.7]],
	}
	var sanctum := {
		"name": "Pyramid · Sun Sanctum", "mood": "night", "spawns": SPAWNS_FIGHT, "seed": 3,
		"props": [
			["altar", 0.0, -D - 1.3, 0, 1.5, 0.0],
			["anubis_urn", -2.8, -D - 1.0, 10, 1.1, 0.0], ["anubis_urn", 2.8, -D - 1.0, -10, 1.1, 0.0],
			["obelisk", -W - 1.4, -D + 0.4, 0, 1.2, 0.0], ["obelisk", W + 1.4, -D + 0.4, 0, 1.2, 0.0],
			["obelisk", -W - 1.4, D - 0.4, 0, 1.0, 0.0], ["obelisk", W + 1.4, D - 0.4, 0, 1.0, 0.0],
			["brazier", -4.6, -D - 1.1, 0, 1.2, 0.0], ["brazier", 4.6, -D - 1.1, 0, 1.2, 0.0],
			["brazier", -W - 1.5, 0.0, 0, 1.0, 0.0], ["brazier", W + 1.5, 0.0, 0, 1.0, 0.0],
			["pillar", -7.0, -D - 1.6, 0, 1.0, 0.0], ["pillar", 7.0, -D - 1.6, 0, 1.0, 0.0],
			["urn", -W - 2.0, 2.0, 0, 1.0, 0.0], ["urn", W + 2.0, -2.0, 0, 1.0, 0.0], ["chest", W + 1.8, 2.8, -90, 0.9, 0.0],
		],
		"walls": 12, "lights": [[-4.6, 1.9, -D - 1.1], [4.6, 1.9, -D - 1.1], [-W - 1.5, 1.7, 0.0], [W + 1.5, 1.7, 0.0]],
	}
	var pharaoh := {
		"name": "Pyramid · Throne Chamber", "mood": "night", "spawns": SPAWNS_BOSS, "seed": 4,
		"props": [
			["stairs", 0.0, -D - 1.0, 0, 4.0, 0.0],
			["altar", 0.0, -D - 1.6, 0, 1.4, 2.4],
			["pillar", -3.4, -D - 0.8, 0, 1.1, 0.0], ["pillar", 3.4, -D - 0.8, 0, 1.1, 0.0],
			["pillar", -7.0, -D - 0.8, 0, 1.1, 0.0], ["pillar", 7.0, -D - 0.8, 0, 1.1, 0.0],
			["torch", -5.2, -D - 0.6, 0, 1.0, 0.0], ["torch", 5.2, -D - 0.6, 0, 1.0, 0.0],
			["coffin", -9.2, -2.6, 90, 1.0, 0.0], ["coffin", 9.2, -2.6, -90, 1.0, 0.0],
			["brazier", -W - 1.3, 1.4, 0, 1.2, 0.0], ["brazier", W + 1.3, 1.4, 0, 1.2, 0.0],
			["chest", -W - 1.6, 3.2, 90, 1.0, 0.0], ["chest", W + 1.6, 3.2, -90, 1.0, 0.0],
			["anubis_urn", -9.6, 0.0, 90, 1.0, 0.0], ["anubis_urn", 9.6, 0.0, -90, 1.0, 0.0],
		],
		"walls": 12, "lights": [[-5.2, 2.3, -D - 0.6], [5.2, 2.3, -D - 0.6], [-W - 1.3, 1.6, 1.4], [W + 1.3, 1.6, 1.4]],
	}
	var rest := {
		"name": "Pyramid · Rest", "mood": "camp", "spawns": [], "seed": 5, "rest": true,
		"props": [
			["brazier", 0.0, -0.6, 0, 1.4, 0.0],
			["altar", 0.0, -7.2, 0, 1.4, 0.0], ["pillar", -3.0, -7.4, 0, 1.0, 0.0], ["pillar", 3.0, -7.4, 0, 1.0, 0.0],
			["torch", -5.2, -7.3, 0, 1.0, 0.0], ["torch", 5.2, -7.3, 0, 1.0, 0.0],
			["obelisk", -10.9, -6.6, 0, 1.0, 0.0], ["obelisk", 10.9, -6.6, 0, 1.0, 0.0],
			["urn", -3.2, 1.0, 30, 1.0, 0.0], ["urn", 3.0, 1.3, -20, 1.0, 0.0], ["chest", 3.4, -2.0, -30, 0.9, 0.0],
			["anubis_urn", -7.2, -3.0, 20, 1.0, 0.0], ["anubis_urn", 7.2, 3.0, -20, 1.0, 0.0],
		],
		"walls": 0, "lights": [[0.0, 1.8, -0.6], [-5.2, 2.3, -7.3], [5.2, 2.3, -7.3]],
	}
	return {"mummy_pyramid_gate": gate, "mummy_pyramid_hall": hall, "mummy_pyramid_sanctum": sanctum, "mummy_pyramid_pharaoh": pharaoh, "mummy_pyramid_rest": rest}


var kit_meshes: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func _stone_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "mummy_stone"
	m.albedo_texture = load("res://art/props/mummy_tomb/mummy_kit_albedo.png")
	m.roughness = 0.95
	m.metallic_specular = 0.1
	return m


func _fire_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "mummy_fire"  # *_fire: shown unshaded (stage_props._is_emissive)
	m.albedo_color = Color(1.0, 0.62, 0.22)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _extract_kit() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var kit := (load(KIT) as PackedScene).instantiate()
	var stone := _stone_material()
	var fire := _fire_material()
	var total := 0
	for node in kit.find_children("*", "MeshInstance3D", true, false):
		var source: Mesh = node.mesh
		var copy := ArrayMesh.new()
		for i in source.get_surface_count():
			var arrays := source.surface_get_arrays(i)
			arrays[Mesh.ARRAY_COLOR] = null  # the stage turns vertex colours on for every art scene: keep the atlas look
			arrays[Mesh.ARRAY_TANGENT] = null
			copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material_name := str(source.surface_get_material(i).resource_name) if source.surface_get_material(i) != null else ""
			copy.surface_set_material(i, fire if material_name.contains("flame") else stone)
		copy.resource_name = str(node.name)
		var path := MESH_DIR + str(node.name) + ".res"
		if ResourceSaver.save(copy, path) != OK:
			printerr("cannot save ", path)
			return false
		kit_meshes[str(node.name)] = load(path)
		total += FileAccess.get_file_as_bytes(path).size()
	print("kit meshes saved: ", kit_meshes.keys().size(), " ", total, " bytes")
	kit.free()
	return kit_meshes.size() == 11


## A floor of 0.5 m cells with vertex colours: sand, darker 2 m slab joints, a few worn and darker slabs.
func _floor_mesh(x0: float, x1: float, z0: float, z1: float, seed_value: int, hall_dark: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cell := 0.5
	var nx := int(round((x1 - x0) / cell))
	var nz := int(round((z1 - z0) / cell))
	var base := Color(0.50, 0.42, 0.31) if not hall_dark else Color(0.42, 0.36, 0.29)
	var joint := Color(0.22, 0.17, 0.12)
	var slab_tones := {}
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in nz:
		for i in nx:
			var x := x0 + float(i) * cell
			var z := z0 + float(j) * cell
			var slab := Vector2i(int(floor((x + 40.0) / 2.0)), int(floor((z + 40.0) / 2.0)))
			if not slab_tones.has(slab):
				slab_tones[slab] = rng.randf()
			var tone: float = slab_tones[slab]
			var color := base.lerp(base.darkened(0.14), tone * 0.6) if tone > 0.35 else base.lightened(0.05 * tone)
			# a slab joint along the cell's west/north edge when it is on a 2 m line
			var on_x := absf(fposmod(x + 40.0, 2.0)) < 0.01
			var on_z := absf(fposmod(z + 40.0, 2.0)) < 0.01
			if on_x or on_z:
				color = color.lerp(joint, 0.35)
			var a := vertices.size()
			for corner in [Vector2(0, 0), Vector2(cell, 0), Vector2(cell, cell), Vector2(0, cell)]:
				vertices.append(Vector3(x + corner.x, 0.02, z + corner.y))
				normals.append(Vector3.UP)
				colors.append(color)
			indices.append_array([a, a + 1, a + 2, a, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.resource_name = "mummy_floor"
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = 1.0
	material.metallic_specular = 0.0
	mesh.surface_set_material(0, material)
	return mesh


func _add_mesh(root: Node3D, node_name: String, mesh: Mesh, at: Vector3, yaw_degrees: float = 0.0, scale_by: float = 1.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees.y = yaw_degrees
	instance.scale = Vector3.ONE * scale_by
	root.add_child(instance)
	instance.owner = root
	return instance


func _slab(root: Node3D, name_: String, from: Vector3, to: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = to - from
	var material := StandardMaterial3D.new()
	material.resource_name = "mummy_slab"
	material.albedo_color = color
	material.roughness = 1.0
	box.material = material
	_add_mesh(root, name_, box, (from + to) * 0.5)


func _build_scene(id: String, layout: Dictionary) -> Dictionary:
	var root_node := Node3D.new()
	root_node.name = id
	var rest: bool = layout.get("rest", false)
	var w := 9.8 if rest else W
	var d := 7.5 if rest else D
	var x0 := -(w + TERRACE_SIDE)
	var x1 := w + TERRACE_SIDE
	var z0 := -(d + TERRACE_BACK)
	var z1 := d + TERRACE_FRONT
	if rest:  # a safe courtyard seen from above: the terrace is the whole stage, a little larger than the walkable floor
		z0 = -(d + 1.2)
		z1 = d + 1.2
		x0 = -(w + 1.2)
		x1 = w + 1.2
	# terrace slab (darker sandstone sides) and the painted floor on top of it
	_slab(root_node, "TerraceSlab", Vector3(x0, -0.9, z0), Vector3(x1, 0.0, z1), Color(0.45, 0.34, 0.22))
	var floor_mesh := _floor_mesh(x0, x1, z0, z1, int(layout.seed) * 17, str(layout.mood) == "night")
	_add_mesh(root_node, "SandFloor", floor_mesh, Vector3.ZERO)
	# back wall of wall panels (outer edge of the terrace)
	var panels := int(layout.walls)
	var instance_count := 0
	if panels > 0:
		var step := (x1 - x0 - 0.8) / float(panels - 1)
		for i in panels:
			_add_mesh(root_node, "WallPanel%d" % i, kit_meshes["wall_panel"], Vector3(x0 + 0.4 + step * i, 0.0, z0 + 0.5), 0.0, 1.9)
			instance_count += 1
	# side low walls on the terrace edge (panels turned): left and right, behind the side props
	if panels > 0:
		for side in [-1.0, 1.0]:
			for k in 4:
				_add_mesh(root_node, "SideWall%d_%d" % [int(side), k], kit_meshes["wall_panel"], Vector3(side * (x1 - 0.5), 0.0, z0 + 2.0 + 2.0 * float(k)), 90.0 * side, 2.0)
				instance_count += 1
	var tris := 0
	for prop in layout.props:
		var kit_name: String = prop[0]
		var node := _add_mesh(root_node, "%s_%d" % [kit_name, instance_count], kit_meshes[kit_name], Vector3(float(prop[1]), float(prop[5]), float(prop[2])), float(prop[3]), float(prop[4]))
		instance_count += 1
	var light_index := 0
	for light in layout.lights:
		var marker := Node3D.new()
		marker.name = "light_fire%d" % light_index
		marker.position = Vector3(float(light[0]), float(light[1]), float(light[2]))
		root_node.add_child(marker)
		marker.owner = root_node
		light_index += 1
	return {"root": root_node, "instances": instance_count}


func _map_json(id: String, layout: Dictionary) -> Dictionary:
	var rest: bool = layout.get("rest", false)
	var d := {
		"version": 1, "id": id, "name": layout.name,
		"_design": "Mummy Pyramid zone (level-designer 2026-11-17; Boss: mummies live ONLY here). Generated by tools/maps/build_mummy_pyramid.gd, made like the goblin map: 16 x 9 m floating-island board, squad left, monsters right, no obstacles; the tomb kit (art/props/mummy_tomb) stands on a sandstone terrace around the board. Monster ids/levels here are a fixture: the real waves come from data/journeys/mummy_waves.json.",
		"modes": ["pve"],
	}
	if rest:
		d["kind"] = "rest"
	else:
		d["kind"] = "fight"
	d["camera_style"] = "top_down" if rest else "arena"
	d["atmosphere"] = "ink"
	d["art_scene"] = SCENE_DIR + id + ".tscn"
	d["art_mood"] = layout.mood
	if rest:
		d["bounds"] = {"half_width": 9.8, "half_depth": 7.5}
		d["spawn"] = [0.0, 0.05, 5.9]
		d["exit_portals"] = [[-3.9, 0.05, -5.6], [3.9, 0.05, -5.6]]
		d["solids"] = [{"center": [0, -0.2, 0], "size": [19.6, 0.4, 15.0], "material": "ink"}]
		d["enemy_spawns"] = []
		d["rest_points"] = [{"id": "brazier", "position": [0.0, 0.05, 1.6], "radius": 2.0}]
		d["campfire"] = [0.0, 0.05, -0.6]
	else:
		d["bounds"] = {"half_width": W, "half_depth": D}
		d["spawn"] = [-5.6, 0.05, 0.0]
		d["solids"] = [{"center": [0, -0.2, 0], "size": [16.0, 0.4, 9.0], "material": "ink"}]
		var spawns: Array = []
		for s in layout.spawns:
			spawns.append({"type": s[0], "level": 1, "position": [s[1], 0.05, s[2]]})
		d["enemy_spawns"] = spawns
		d["rest_points"] = []
		d["player_spawns"] = [[-5.6, 0.05, 0.0], [-4.6, 0.05, -2.2], [-4.6, 0.05, 2.2]]
		d["_arena"] = "Floating-island board, LANDSCAPE, like the goblin boards: 16 x 9 m, no obstacles. client/arena_props.gd builds the island and the sky; the scene adds the sandstone terrace and the tomb props around it."
	d["world_region"] = "pyramid"
	return d


func run() -> void:
	if not _extract_kit():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))
	var all := layouts()
	var ids: Array = all.keys()
	for id in ids:
		var layout: Dictionary = all[id]
		var built := _build_scene(id, layout)
		var packed := PackedScene.new()
		packed.pack(built.root)
		var scene_path: String = SCENE_DIR + id + ".tscn"
		if ResourceSaver.save(packed, scene_path) != OK:
			printerr("cannot save ", scene_path)
			quit(1)
			return
		built.root.free()
		var json := JSON.stringify(_map_json(id, layout), " ")
		var f := FileAccess.open(MAP_DIR + id + ".json", FileAccess.WRITE)
		f.store_string(json)
		f.close()
		print("built ", id, " props+walls=", built.instances, " scene=", FileAccess.get_file_as_bytes(scene_path).size(), " bytes")
	print("MUMMY PYRAMID BUILT")
	quit()
