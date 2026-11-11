extends RefCounted
## The goblin-forest stages (Boss 2026-10-13, enlarged 2026-10-14) and the optional map fields they brought:
## kind, art_scene, art_mood, exit_portals, campfire (logic/map_loader.gd), the art scene in client/stage_props.gd,
## and that each map JSON matches the gameplay empties inside its glb (tools/blender/build_goblin_stages.py).

const MapLoader := preload("res://logic/map_loader.gd")
const StageProps := preload("res://client/stage_props.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const MapTests := preload("res://tests/test_map_data.gd")

const MAPS := ["goblin_arena_a", "goblin_arena_b", "goblin_arena_c", "goblin_rest_camp"]
const MINIMAL := """{"version": 1, "id": "t", "name": "T", "modes": ["pve"],
	"bounds": {"half_width": 10, "half_depth": 8}, "spawn": [0, 0, 0],
	"solids": [{"center": [0, 0, 0], "size": [1, 1, 1]}]}"""
## Boss 2026-10-16: the orc kit keeps its full source detail (v1 was decimated into blobs), so a stage dressed
## with it is ~50-100k tris (was 30k). GL Compatibility handles that on desktop browsers; revisit for mobile web.
const MAX_TRIS := 110000
## Boss 2026-10-14: the fight arenas are ~2-2.5 screens at camera 8 (one screenful of ground round the player is
## roughly 18 x 12 m), about 1.7x the first version's 22 x 16 m - room to retreat, circle and kite. Still ONE
## arena: never a corridor and never a long walk, so the area has an upper bound too.
const FIGHT_AREA := Vector2(540.0, 640.0)   ## m^2 of walkable floor
const REST_AREA := Vector2(260.0, 320.0)


func run(ctx) -> void:
	_test_fields(ctx)
	var combat := CombatDataLoader.load_default()
	var map_tests = MapTests.new()
	var index: Array = JSON.parse_string(FileAccess.get_file_as_string(MapLoader.INDEX_PATH))
	for id in MAPS:
		var map := MapLoader.load_by_id(id)
		ctx.check("%s legacy is valid %s and retired from index.json" % [id, map.errors], map.is_valid() and not index.has(id))
		var area := map.half_width * map.half_depth * 4.0
		var want: Vector2 = REST_AREA if map.kind == "rest" else FIGHT_AREA
		ctx.check("%s is one arena with room to kite (%.0f x %.0f m = %.0f m2, want %.0f-%.0f, top-down)" % [id, map.half_width * 2.0, map.half_depth * 2.0, area, want.x, want.y], map.camera_style == "top_down" and area >= want.x and area <= want.y and map.half_width <= map.half_depth * 1.5)
		ctx.check("%s: its art scene exists (%s)" % [id, map.art_scene], map.art_scene.begins_with("res://art/maps/goblin_forest/") and ResourceLoader.exists(map.art_scene))
		ctx.check("%s: two exit portals, north of the middle, in bounds, not in a solid" % id, map.exit_portals.size() == 2 and map.exit_portals.all(func(p): return p.z < 0.0 and _free(map, p)))
		if map.kind == "rest":
			ctx.check("%s: a safe rest map (no monsters) with a campfire and a rest point" % id, map.enemy_spawns.is_empty() and map.has_campfire and map.rest_points.size() == 1)
		else:
			ctx.check("%s: a fight map with 8 monster spots of known types" % id, map.enemy_spawns.size() == 8 and map.enemy_spawns.all(func(s): return combat.enemies.has(s["type"])) and not map.has_campfire)
			ctx.check("%s: at least 5 cover pieces, spread out (the extra room is used, not empty)" % id, _cover_count(map) >= 5 and _cover_spread(map) >= 3.0)
			ctx.check("%s: the monster spots use the whole floor (widest pair %.1f m apart)" % [id, _spot_spread(map)], _spot_spread(map) >= map.half_width * 1.5)
			map_tests._check_camera_8_layout(ctx, map)
			map_tests._check_monsters_reach_player(ctx, map, combat)
		_check_art(ctx, map)


func _test_fields(ctx) -> void:
	var plain := MapLoader.parse(MINIMAL)
	ctx.check("a map without the new fields: fight, no art, no campfire", plain.is_valid() and plain.kind == "fight" and plain.art_scene == "" and plain.art_mood == "" and not plain.has_campfire)
	ctx.check("default exit portals: two spots north of the centre inside the bounds (%s)" % [plain.exit_portals], plain.exit_portals.size() == 2 and plain.exit_portals.all(func(p): return p.z < 0.0 and absf(p.x) < plain.half_width and absf(p.z) < plain.half_depth) and plain.exit_portals[0].x < plain.exit_portals[1].x)
	ctx.check("the old maps keep loading unchanged (no art prop added)", ["practice_field", "sunward_valley", "ink_garden", "shrine_wall"].all(func(id): var m := MapLoader.load_by_id(id); return m.is_valid() and m.kind == "fight" and not m.props.any(func(p): return p["kind"] == "art_scene")))
	var rest := MapLoader.parse(MINIMAL.replace("\"solids\"", "\"kind\": \"rest\", \"campfire\": [1, 0, 2], \"exit_portals\": [[0, 0, -5]], \"art_scene\": \"res://x/y.glb\", \"art_mood\": \"camp\", \"solids\""))
	ctx.check("explicit kind / campfire / exit_portals / art_scene / art_mood are read %s" % [rest.errors], rest.is_valid() and rest.kind == "rest" and rest.has_campfire and rest.campfire == Vector3(1, 0, 2) and rest.exit_portals == [Vector3(0, 0, -5)] and rest.art_scene == "res://x/y.glb" and rest.art_mood == "camp")
	ctx.check("the art scene reaches the client as one art_scene prop", rest.props.size() == 1 and rest.props[0]["kind"] == "art_scene" and rest.props[0]["path"] == "res://x/y.glb" and rest.props[0]["mood"] == "camp" and StageProps.KINDS.has("art_scene"))
	ctx.check("an unknown kind is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"kind\": \"shop\", \"solids\"")).is_valid())
	ctx.check("a campfire on a fight map is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"campfire\": [0, 0, 0], \"solids\"")).is_valid())
	ctx.check("monsters on a rest map are reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"kind\": \"rest\", \"enemy_spawns\": [{\"type\": \"goblin\", \"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("an exit portal outside the bounds is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"exit_portals\": [[0, 0, -30]], \"solids\"")).is_valid())
	ctx.check("an empty exit_portals list is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"exit_portals\": [], \"solids\"")).is_valid())
	ctx.check("an art_scene that is not a res:// scene file is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"art_scene\": \"C:/a.png\", \"solids\"")).is_valid())
	ctx.check("an unknown art_mood is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"art_mood\": \"disco\", \"solids\"")).is_valid())


## The glb: its gameplay empties sit where the map JSON says, it is cheap (tris, one mesh per material) and
## the client shows it with vertex colours and lights.
func _check_art(ctx, map) -> void:
	var holder := Node3D.new()
	var scene := StageProps.add_art_scene(holder, map.art_scene, map.art_mood)
	if scene == null:
		ctx.check("%s: the art scene instances" % map.id, false)
		holder.free()
		return
	var problems: Array[String] = []
	_near(problems, scene, "spawn", map.spawn)
	for i in map.enemy_spawns.size():
		_near(problems, scene, "enemy_%d" % i, map.enemy_spawns[i]["position"])
	if scene.find_child("enemy_%d" % map.enemy_spawns.size(), true, false) != null:
		problems.append("more enemy_ empties than enemy_spawns")
	for i in map.exit_portals.size():
		_near(problems, scene, "exit_portal_%d" % i, map.exit_portals[i])
	if map.has_campfire:
		_near(problems, scene, "campfire", map.campfire)
	ctx.check("%s: the glb's empties match the map (spawn, enemy_0..%d, exit_portal_0/1%s) %s" % [map.id, map.enemy_spawns.size() - 1, ", campfire" if map.has_campfire else "", problems], problems.is_empty())
	var tris := 0
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var colored := true
	for node in meshes:
		var mesh: Mesh = node.mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var material := mesh.surface_get_material(s) as StandardMaterial3D
			colored = colored and material != null and material.vertex_color_use_as_albedo and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
	ctx.check("%s: web-cheap art (%d tris <= %d, %d meshes = one per material)" % [map.id, tris, MAX_TRIS, meshes.size()], tris > 1000 and tris <= MAX_TRIS and meshes.size() <= 4)
	ctx.check("%s: every surface is vertex-coloured and shown with vertex_color_use_as_albedo" % map.id, colored)
	ctx.check("%s: a light on its fire" % map.id, scene.find_children("light_fire*", "", true, false).any(func(n): return n.get_child_count() > 0 and n.get_child(0) is OmniLight3D))
	holder.free()


func _near(problems: Array[String], scene: Node, name: String, want: Vector3) -> void:
	var node := scene.find_child(name, true, false) as Node3D
	if node == null:
		problems.append(name + " missing")
	elif node.position.distance_to(want) > 0.02:
		problems.append("%s at %s, map says %s" % [name, node.position, want])


func _free(map, at: Vector3) -> bool:
	for solid in map.solids:
		var box: AABB = solid["box"]
		if box.end.y <= 0.001:
			continue
		if box.grow(0.5).has_point(Vector3(at.x, box.get_center().y, at.z)):
			return false
	return true


## Cover = the map's standing solids (the floor box is not cover).
func _cover(map) -> Array:
	var boxes := []
	for solid in map.solids:
		var box: AABB = solid["box"]
		if box.end.y > 0.001:
			boxes.append(box.get_center())
	return boxes


func _cover_count(map) -> int:
	return _cover(map).size()


## The smallest gap between two cover pieces: they must not huddle into one wall.
func _cover_spread(map) -> float:
	var centers := _cover(map)
	var closest := 999.0
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			var a: Vector3 = centers[i]
			var b: Vector3 = centers[j]
			closest = minf(closest, Vector2(a.x - b.x, a.z - b.z).length())
	return closest


## The widest distance between two monster spots: the spawn pattern has to use the whole arena.
func _spot_spread(map) -> float:
	var widest := 0.0
	for i in map.enemy_spawns.size():
		for j in range(i + 1, map.enemy_spawns.size()):
			var a: Vector3 = map.enemy_spawns[i]["position"]
			var b: Vector3 = map.enemy_spawns[j]["position"]
			widest = maxf(widest, Vector2(a.x - b.x, a.z - b.z).length())
	return widest

