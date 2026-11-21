extends RefCounted
## The Orc Camp night board (level-designer 2026-11-20, tools/maps/build_orc_camp.gd): the goblin courtyard's board (same
## bounds, spawns, no cover) on a floating island at night, three merged meshes, at most 4 real lights, fake torch glow,
## embers, phone-light budgets, the night look in the client. Wired 2026-11-21: the orc_waves journey (tests/test_orc_zone.gd).

const MapLoader := preload("res://logic/map_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const MapTests := preload("res://tests/test_map_data.gd")
const StageProps := preload("res://client/stage_props.gd")
const ArenaProps := preload("res://client/arena_props.gd")

const ID := "orc_camp_night"
const TWIN := "goblin_base_courtyard"
const MESH_DIR := "res://art/maps/orc_camp/meshes/"
const ATLAS := "res://art/props/orc_camp/orc_kit_atlas.png"
const DIRT := "res://art/maps/goblin_base/painted/dirt.png"
const MAX_SURFACES := 6
const MIN_TRIS := 18000
const MAX_TRIS := 25000
const MAX_MESH_BYTES := 700000
const MAX_SCENE_BYTES := 10000
const MAX_LIGHTS := 4


func run(ctx) -> void:
	var combat := CombatDataLoader.load_default()
	var index: Array = JSON.parse_string(FileAccess.get_file_as_string(MapLoader.INDEX_PATH))
	var map = MapLoader.load_by_id(ID)
	var twin = MapLoader.load_by_id(TWIN)
	ctx.check("%s loads with no errors %s" % [ID, map.errors], map.is_valid())
	ctx.check("%s is listed in data/maps/index.json" % ID, index.has(ID))
	ctx.check("%s has its art scene and a night mood" % ID, ResourceLoader.exists(map.art_scene) and map.art_mood == "night")
	ctx.check("%s is the goblin courtyard board: same arena camera, bounds, player spawns and enemy spots" % ID,
		map.camera_style == "arena" and is_equal_approx(map.half_width, twin.half_width) and is_equal_approx(map.half_depth, twin.half_depth)
		and map.player_spawns == twin.player_spawns and map.spawn == twin.spawn and map.enemy_spawns.size() == 8
		and range(8).all(func(k): return (map.enemy_spawns[k]["position"] as Vector3).is_equal_approx(twin.enemy_spawns[k]["position"])))
	ctx.check("%s: only the floor solid (no cover, like the courtyard)" % ID, map.solids.size() == 1)
	ctx.check("%s: every fixture monster exists in the combat data" % ID, map.enemy_spawns.all(func(s): return combat.enemies.has(str(s["type"]))))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % ID))
	ctx.check("%s is a pve fight in the orc_camp region" % ID, map.modes.has("pve") and map.kind == "fight" and str(raw.get("world_region", "")) == "orc_camp")
	var tests = MapTests.new()
	tests._check_layout(ctx, map)
	tests._check_camera_8_layout(ctx, map)
	tests._check_monsters_reach_player(ctx, map, combat)
	ctx.check("wired: orc_waves is the only journey naming %s" % ID, _journeys_naming(ID) == ["orc_waves.json"])
	_check_scene(ctx, map)
	_check_island(ctx, map)
	_check_client(ctx, map)
	_check_pack(ctx)


static func _journeys_naming(id: String) -> Array:
	var out: Array = []
	for file in DirAccess.get_files_at("res://data/journeys"):
		if file.ends_with(".json") and FileAccess.get_file_as_string("res://data/journeys/" + file).contains(id):
			out.append(file)
	return out


func _check_scene(ctx, map) -> void:
	var holder := Node3D.new()
	var scene := StageProps.add_art_scene(holder, map.art_scene, map.art_mood)
	if scene == null:
		ctx.check("%s: the art scene instances" % ID, false)
		holder.free()
		return
	var ground := scene.get_node_or_null("PyramidFloor") as MeshInstance3D
	var dressing := scene.get_node_or_null("Dressing") as MeshInstance3D
	var kit := scene.get_node_or_null("Kit") as MeshInstance3D
	ctx.check("%s: three merged meshes (floor, dressing, kit)" % ID, ground != null and dressing != null and kit != null)
	if ground == null or dressing == null or kit == null:
		holder.free()
		return
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	ctx.check("%s: its 3 meshes are external .res files under art/maps/orc_camp/meshes" % ID, meshes.size() == 3 and meshes.all(func(n): return (n as MeshInstance3D).mesh.resource_path.begins_with(MESH_DIR)))
	ctx.check("%s: no MultiMesh" % ID, scene.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
	ctx.check("%s: the flat floor has no ink outline and casts no shadow" % ID, bool(ground.get_meta("toon_no_outline", false)) and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var surfaces := 0
	var tris := 0
	var textures := {}
	for node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			surfaces += 1
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var material := mesh.surface_get_material(s) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				textures[material.albedo_texture.resource_path] = true
	ctx.check("%s: phone-light (%d draw surfaces <= %d, %d tris in %d..%d)" % [ID, surfaces, MAX_SURFACES, tris, MIN_TRIS, MAX_TRIS], surfaces <= MAX_SURFACES and tris >= MIN_TRIS and tris <= MAX_TRIS)
	ctx.check("%s: only the orc kit atlas and the goblin painted dirt, no new texture %s" % [ID, textures.keys()], textures.keys().all(func(t): return t in [ATLAS, DIRT]) and textures.has(ATLAS))
	var names := []
	for s in kit.mesh.get_surface_count():
		names.append(str(kit.mesh.surface_get_material(s).resource_name))
	ctx.check("%s: the kit is one atlas surface + unshaded flames + an additive halo surface %s" % [ID, names], names == ["orc_kit", "orc_fire", "orc_glow"])
	var glow := kit.mesh.surface_get_material(2) as StandardMaterial3D
	var fire := kit.mesh.surface_get_material(1) as StandardMaterial3D
	ctx.check("%s: the torch flames are unshaded and the halos additive (fake glow, no extra lights)" % ID,
		fire.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and glow.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and glow.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	var lights := scene.find_children("*", "OmniLight3D", true, false)
	ctx.check("%s: 2-%d real firelights, none casts shadows (%d)" % [ID, MAX_LIGHTS, lights.size()], lights.size() >= 2 and lights.size() <= MAX_LIGHTS and lights.all(func(l): return not (l as Light3D).shadow_enabled))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/orc_camp/manifest.json"))
	var row: Dictionary = manifest.get(ID, {}) if manifest is Dictionary else {}
	ctx.check("%s: more torches than real lights (the rest are fake glow): %s torches" % [ID, row.get("torches")], int(row.get("torches", 0)) > lights.size())
	ctx.check("%s: mesh bytes %s <= %d" % [ID, row.get("mesh_bytes"), MAX_MESH_BYTES], not row.is_empty() and int(row.mesh_bytes) <= MAX_MESH_BYTES)
	var size := FileAccess.get_file_as_bytes(map.art_scene).size()
	ctx.check("%s: the scene file is tiny (%d bytes)" % [ID, size], size <= MAX_SCENE_BYTES)
	var problems: Array[String] = []
	_near(problems, scene, "spawn", map.spawn)
	for i in map.enemy_spawns.size():
		_near(problems, scene, "enemy_%d" % i, map.enemy_spawns[i]["position"])
	ctx.check("%s: the scene's markers match the map %s" % [ID, problems], problems.is_empty())
	var stray := 0
	for mesh_node in [kit, dressing]:
		for s in (mesh_node as MeshInstance3D).mesh.get_surface_count():
			for v in ((mesh_node as MeshInstance3D).mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if absf(v.x) < map.half_width - 0.05 and absf(v.z) < map.half_depth - 0.05 and v.y > 0.1:
					stray += 1
	ctx.check("%s: nothing stands on the board (%d stray vertices): no prop hides a fight" % [ID, stray], stray == 0)
	holder.free()


## Island like the pyramid boards: walls north/east/west, an open cliff in front, the client's rock underside.
func _check_island(ctx, map) -> void:
	var holder := Node3D.new()
	var scene := StageProps.add_art_scene(holder, map.art_scene, map.art_mood)
	ctx.check("%s: marked a floating island and a night camp" % ID, ArenaProps.is_pyramid_island(holder) and ArenaProps.is_orc_island(holder))
	var iw: float = map.half_width + ArenaProps.MARGIN_X
	var idp: float = map.half_depth + ArenaProps.MARGIN_Z
	var floor_box: AABB = (scene.get_node("PyramidFloor") as MeshInstance3D).mesh.get_aabb()
	ctx.check("%s: the island top is the goblin island footprint (floor %s)" % [ID, floor_box],
		absf(floor_box.position.x + iw) < 0.05 and absf(floor_box.end.x - iw) < 0.05 and absf(floor_box.position.z + idp) < 0.05 and absf(floor_box.end.z - idp) < 0.05 and floor_box.position.y < -0.9)
	var north := {}
	var west := {}
	var east := {}
	var front_tall := 0
	for node_name in ["Dressing", "Kit"]:
		var mesh: Mesh = (scene.get_node(node_name) as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if v.z > idp - 1.2 and absf(v.x) < map.half_width + 1.0 and v.y > 1.3:
					front_tall += 1
				if v.y < 1.2 or node_name != "Dressing":
					continue
				if v.z < -idp + 1.6:
					north[int(floor(v.x))] = true
				if v.x < -iw + 1.6:
					west[int(floor(v.z))] = true
				if v.x > iw - 1.6:
					east[int(floor(v.z))] = true
	ctx.check("%s: palisade over 1.2 m along the north (%d of %d m), west (%d) and east (%d)" % [ID, north.size(), int(iw * 2.0), west.size(), east.size()],
		north.size() >= int(iw * 2.0) - 2 and west.size() >= int(idp * 2.0) - 4 and east.size() >= int(idp * 2.0) - 4)
	ctx.check("%s: the front is an open cliff (nothing over 1.3 m in front of the board: %d vertices)" % [ID, front_tall], front_tall == 0)
	holder.free()


## The client's night look: the orc island (underside + embers), a dark night background, a dimmed moon.
func _check_client(ctx, map) -> void:
	var stage := Node3D.new()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	stage.add_child(sun)
	StageProps.add_art_scene(stage, map.art_scene, map.art_mood)
	var island := ArenaProps.add_orc_island(stage, map)
	var cones := island.find_children("*", "MeshInstance3D", true, false)
	var embers := island.find_children("*", "CPUParticles3D", true, false)
	ctx.check("%s: the client adds the rock underside (%d layers) and ONE ember drift (%d systems)" % [ID, cones.size(), embers.size()], cones.size() == 4 and embers.size() == 1)
	if embers.size() == 1:
		var e := embers[0] as CPUParticles3D
		ctx.check("%s: embers are cheap: <= 40 particles from the fire points (%d, %d points)" % [ID, e.amount, e.emission_points.size()], e.amount <= 40 and e.emission_points.size() >= 4)
	ArenaProps.set_night_sky(stage)
	var bg: Color = env.environment.background_color
	ctx.check("%s: night: a dark blue flat background (the drawn style keeps it) %s" % [ID, bg], env.environment.background_mode == Environment.BG_COLOR and bg.b > bg.r and bg.get_luminance() < 0.2)
	ctx.check("%s: the moon is dimmer than the day sun (%.2f)" % [ID, sun.light_energy], sun.light_energy < 0.7)
	stage.free()


func _check_pack(ctx) -> void:
	var layout = JSON.parse_string(FileAccess.get_file_as_string("res://tools/web/pack_layout.json"))
	var ok := false
	for pack in layout.get("packs", []):
		if str(pack.get("name", "")) == "stages" and str(pack.get("stage", "")) == "battle":
			var include: Array = pack.get("include", [])
			ok = include.any(func(p): return MESH_DIR.begins_with(str(p))) and include.any(func(p): return ATLAS.begins_with(str(p)))
	ctx.check("the orc meshes and the kit atlas ship in the 'stages' battle pack", ok)
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	ctx.check("the web export no longer excludes the orc kit atlas (only the unused .glb / normal map / README)",
		not presets.contains("art/props/orc_camp/*") and not presets.contains("orc_kit_atlas") and not presets.contains("art/maps/orc_camp"))


func _near(problems: Array[String], scene: Node, name: String, want: Vector3) -> void:
	var node := scene.find_child(name, true, false) as Node3D
	if node == null:
		problems.append(name + " missing")
	elif node.position.distance_to(want) > 0.02:
		problems.append("%s at %s, map says %s" % [name, node.position, want])
