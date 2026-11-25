extends RefCounted
## The Elder Grove boards (level-designer 2026-11-24, zone elder_tree, order 4; tools/maps/build_elder_grove.gd): three
## floating-island fight boards made like the orc / mummy ones: the goblin courtyard's bounds and spawns, no cover, root
## walls north/east/west, an open cliff in front, three merged meshes, 22-25k triangles, the forest look in the client.
## The zone stays "coming soon" (no journey yet: the grove monster family does not exist), so the fixture monsters on the
## spots are placeholders that no zone journey uses.

const MapLoader := preload("res://logic/map_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Zones := preload("res://logic/world_zones.gd")
const MapTests := preload("res://tests/test_map_data.gd")
const StageProps := preload("res://client/stage_props.gd")
const ArenaProps := preload("res://client/arena_props.gd")
const EnemyBars := preload("res://client/enemy_bars.gd")

const MAPS := ["elder_grove_heart", "elder_grove_gate", "elder_grove_shrine"]
const TWIN := "goblin_base_courtyard"
const MESH_DIR := "res://art/maps/elder_grove/meshes/"
const TEXTURES := ["res://art/maps/goblin_base/painted/dirt.png", "res://art/maps/goblin_base/painted/grass.png"]
const MAX_SURFACES := 6
const MIN_TRIS := 22000
const MAX_TRIS := 25500
const MAX_MESH_BYTES := 450000
const MAX_SCENE_BYTES := 10000
const MAX_LIGHTS := 4
const ZONE_FAMILIES := ["goblin", "mummy", "orc"]  ## families of the built zones: never a grove spot fixture


func run(ctx) -> void:
	var combat := CombatDataLoader.load_default()
	var index: Array = JSON.parse_string(FileAccess.get_file_as_string(MapLoader.INDEX_PATH))
	var twin = MapLoader.load_by_id(TWIN)
	for id in MAPS:
		var map = MapLoader.load_by_id(id)
		ctx.check("%s loads with no errors %s" % [id, map.errors], map.is_valid())
		ctx.check("%s is listed in data/maps/index.json" % id, index.has(id))
		ctx.check("%s has its art scene" % id, not map.art_scene.is_empty() and ResourceLoader.exists(map.art_scene))
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id))
		ctx.check("%s is a pve fight in the elder_tree region" % id, map.modes.has("pve") and map.kind == "fight" and str(raw.get("world_region", "")) == "elder_tree")
		ctx.check("%s is the goblin courtyard board: same arena camera, bounds, player spawns and the 8 enemy spots" % id,
			map.camera_style == "arena" and is_equal_approx(map.half_width, twin.half_width) and is_equal_approx(map.half_depth, twin.half_depth)
			and map.player_spawns == twin.player_spawns and map.spawn == twin.spawn and map.enemy_spawns.size() == 8
			and range(8).all(func(k): return (map.enemy_spawns[k]["position"] as Vector3).is_equal_approx(twin.enemy_spawns[k]["position"])))
		ctx.check("%s: only the floor solid (no cover, like the courtyard)" % id, map.solids.size() == 1)
		ctx.check("%s: every fixture monster exists in the combat data" % id, map.enemy_spawns.all(func(s): return combat.enemies.has(str(s["type"]))))
		ctx.check("%s: the fixture is a placeholder from no built zone's family (goblin/mummy/orc stay in their zones)" % id,
			map.enemy_spawns.all(func(s): return not ZONE_FAMILIES.has(str(s["type"]).split("_")[0])))
		var roles: String = str(raw.get("_spots", ""))
		ctx.check("%s: spots for melee, knight, archer and mage (%s)" % [id, roles], ["melee", "knight", "archer", "mage"].all(func(r): return roles.contains(r)))
		var tests = MapTests.new()
		tests._check_layout(ctx, map)
		tests._check_camera_8_layout(ctx, map)
		tests._check_monsters_reach_player(ctx, map, combat)
		ctx.check("%s: no journey names it yet (the zone is coming soon)" % id, _journeys_naming(id).is_empty())
		_check_scene(ctx, map)
		_check_island(ctx, map)
	ctx.check("three distinct boards (each its own art scene)", MAPS.map(func(m): return MapLoader.load_by_id(m).art_scene).reduce(func(acc, s): return acc if acc.has(s) else acc + [s], []).size() == 3)
	_check_client(ctx, MapLoader.load_by_id(MAPS[0]))
	_check_zone(ctx)
	_check_themes(ctx)
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
		ctx.check("%s: the art scene instances" % map.id, false)
		holder.free()
		return
	var ground := scene.get_node_or_null("PyramidFloor") as MeshInstance3D
	var dressing := scene.get_node_or_null("Dressing") as MeshInstance3D
	var kit := scene.get_node_or_null("Kit") as MeshInstance3D
	ctx.check("%s: three merged meshes (floor, dressing, kit)" % map.id, ground != null and dressing != null and kit != null)
	if ground == null or dressing == null or kit == null:
		holder.free()
		return
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	ctx.check("%s: its 3 meshes are external .res files under art/maps/elder_grove/meshes" % map.id, meshes.size() == 3 and meshes.all(func(n): return (n as MeshInstance3D).mesh.resource_path.begins_with(MESH_DIR)))
	ctx.check("%s: no MultiMesh" % map.id, scene.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
	ctx.check("%s: the flat floor has no ink outline and casts no shadow" % map.id, bool(ground.get_meta("toon_no_outline", false)) and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var surfaces := 0
	var tris := 0
	var textures := {}
	var glow_on_kit := false
	for node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			surfaces += 1
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var material := mesh.surface_get_material(s) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				textures[material.albedo_texture.resource_path] = true
			if node != ground and material != null and material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				glow_on_kit = true
	ctx.check("%s: phone-light (%d draw surfaces <= %d, %d tris in %d..%d)" % [map.id, surfaces, MAX_SURFACES, tris, MIN_TRIS, MAX_TRIS], surfaces <= MAX_SURFACES and tris >= MIN_TRIS and tris <= MAX_TRIS)
	ctx.check("%s: only the goblin painted dirt and grass, no new texture %s" % [map.id, textures.keys()], textures.keys().all(func(t): return TEXTURES.has(t)))
	ctx.check("%s: the trees, arch and shrine are flat colours (kit: one untextured surface)" % map.id,
		kit.mesh.get_surface_count() == 1 and (kit.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture == null)
	ctx.check("%s: the additive glow rides on the outline-free floor mesh, never on an inked mesh (dark rings)" % map.id, not glow_on_kit)
	var lights := scene.find_children("*", "OmniLight3D", true, false)
	ctx.check("%s: 1-%d real lights (shrine lanterns), none casts shadows (%d)" % [map.id, MAX_LIGHTS, lights.size()], lights.size() >= 1 and lights.size() <= MAX_LIGHTS and lights.all(func(l): return not (l as Light3D).shadow_enabled))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/elder_grove/manifest.json"))
	var row: Dictionary = manifest.get(map.id, {}) if manifest is Dictionary else {}
	ctx.check("%s: the manifest matches the scene (%s tris) and mesh bytes %s <= %d" % [map.id, row.get("triangles"), row.get("mesh_bytes"), MAX_MESH_BYTES],
		not row.is_empty() and int(row.triangles) == tris and int(row.mesh_bytes) <= MAX_MESH_BYTES)
	var size := FileAccess.get_file_as_bytes(map.art_scene).size()
	ctx.check("%s: the scene file is tiny (%d bytes)" % [map.id, size], size <= MAX_SCENE_BYTES)
	var problems: Array[String] = []
	_near(problems, scene, "spawn", map.spawn)
	for i in map.enemy_spawns.size():
		_near(problems, scene, "enemy_%d" % i, map.enemy_spawns[i]["position"])
	ctx.check("%s: the scene's markers match the map %s" % [map.id, problems], problems.is_empty())
	var stray := 0
	for mesh_node in [kit, dressing, ground]:
		for s in (mesh_node as MeshInstance3D).mesh.get_surface_count():
			for v in ((mesh_node as MeshInstance3D).mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if absf(v.x) < map.half_width - 0.05 and absf(v.z) < map.half_depth - 0.05 and v.y > 0.1:
					stray += 1
	ctx.check("%s: nothing stands on (or hangs over) the board, roots and stones are flat (%d stray vertices)" % [map.id, stray], stray == 0)
	holder.free()


## Island like the orc / pyramid boards: walls north/east/west, an open cliff in front, the footprint of the goblin island.
func _check_island(ctx, map) -> void:
	var holder := Node3D.new()
	var scene := StageProps.add_art_scene(holder, map.art_scene, map.art_mood)
	ctx.check("%s: marked a floating island and an elder grove (not the orc night)" % map.id, ArenaProps.is_pyramid_island(holder) and ArenaProps.is_grove_island(holder) and not ArenaProps.is_orc_island(holder))
	var iw: float = map.half_width + ArenaProps.MARGIN_X
	var idp: float = map.half_depth + ArenaProps.MARGIN_Z
	var floor_box: AABB = (scene.get_node("PyramidFloor") as MeshInstance3D).mesh.get_aabb()
	ctx.check("%s: the island top is the goblin island footprint (floor %s)" % [map.id, floor_box],
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
				if v.y < 1.2:
					continue
				if v.z < -idp + 1.6:
					north[int(floor(v.x))] = true
				if v.x < -iw + 1.6:
					west[int(floor(v.z))] = true
				if v.x > iw - 1.6:
					east[int(floor(v.z))] = true
	ctx.check("%s: root walls over 1.2 m along the north (%d of %d m), west (%d) and east (%d)" % [map.id, north.size(), int(iw * 2.0), west.size(), east.size()],
		north.size() >= int(iw * 2.0) - 2 and west.size() >= int(idp * 2.0) - 4 and east.size() >= int(idp * 2.0) - 4)
	ctx.check("%s: the front is an open cliff (nothing over 1.3 m in front of the board: %d vertices)" % [map.id, front_tall], front_tall == 0)
	holder.free()


## The client's forest look: the grove island (underside + one mote drift), the day sky, a warm gold sun.
func _check_client(ctx, map) -> void:
	var stage := Node3D.new()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	StageProps.add_art_scene(stage, map.art_scene, map.art_mood)
	var island := ArenaProps.add_grove_island(stage, map)
	var cones := island.find_children("*", "MeshInstance3D", true, false)
	var motes := island.find_children("*", "CPUParticles3D", true, false)
	ctx.check("%s: the client adds the rock underside (%d layers) and ONE mote drift (%d systems)" % [map.id, cones.size(), motes.size()], cones.size() == 4 and motes.size() == 1)
	if motes.size() == 1:
		var m := motes[0] as CPUParticles3D
		ctx.check("%s: motes are cheap: <= 30 particles from the canopy points (%d, %d points)" % [map.id, m.amount, m.emission_points.size()], m.amount <= 30 and m.emission_points.size() >= 3)
	ArenaProps.set_grove_sky(stage)
	ctx.check("%s: forest day: the day sky, a warm gold sun (r > b) and a leafy ambient (g highest)" % map.id,
		env.environment.background_mode == Environment.BG_SKY and sun.light_color.r > sun.light_color.b
		and env.environment.ambient_light_color.g >= env.environment.ambient_light_color.r and env.environment.ambient_light_color.g > env.environment.ambient_light_color.b)
	stage.free()
	var view := FileAccess.get_file_as_string("res://client/stage_view.gd")
	ctx.check("StageView dresses grove boards with their own variant (add_grove_island + set_grove_sky)", view.contains("is_grove_island") and view.contains("add_grove_island") and view.contains("set_grove_sky"))


## The zone: elder_tree is order 4, still coming soon (no journey: the monsters are not ready).
func _check_zone(ctx) -> void:
	var zone: Dictionary = Zones.zone("elder_tree")
	ctx.check("zones.json has the elder_tree zone at order 4", int(zone.get("order", 0)) == 4)
	ctx.check("elder_tree has NO journey yet (coming soon until its monster family exists)", str(zone.get("journey", "x")).is_empty())


## Health bars and debris colours follow the map: the grove has its own bar style and forest debris.
func _check_themes(ctx) -> void:
	var bars = EnemyBars.new().load_default()
	for id in MAPS:
		var map = MapLoader.load_by_id(id)
		var base: Dictionary = bars.resolve(map.id, map.atmosphere, "base")
		var brass: Dictionary = bars.resolve("practice_field", "", "base")
		ctx.check("%s: its own crude grove bar (not the brass default)" % id, base["frame_shape"] == "crude" and base["fill"] != brass["fill"] and bars.resolve(map.id, map.atmosphere, "boss")["frame_shape"] == "chief")
	var vfx = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/vfx.json"))
	var colours: Dictionary = vfx["violence"]["map_colors"].get("elder_grove", {})
	ctx.check("violent_vfx debris/dust colours for the grove (forest brown chunks, green grit) %s" % [colours],
		colours.has("rock") and colours.has("grit") and colours.has("smoke")
		and Color.html(str(colours.get("grit", "#000"))).g > Color.html(str(colours.get("grit", "#000"))).r
		and Color.html(str(colours.get("rock", "#000"))).r > Color.html(str(colours.get("rock", "#000"))).b)


func _check_pack(ctx) -> void:
	var layout = JSON.parse_string(FileAccess.get_file_as_string("res://tools/web/pack_layout.json"))
	var ok := false
	for pack in layout.get("packs", []):
		if str(pack.get("name", "")) == "stages" and str(pack.get("stage", "")) == "battle":
			var include: Array = pack.get("include", [])
			ok = include.any(func(p): return MESH_DIR.begins_with(str(p))) and TEXTURES.all(func(t): return include.any(func(p): return t.begins_with(str(p))))
	ctx.check("the grove meshes and the painted floors ship in the 'stages' battle pack", ok)
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	ctx.check("the web export does not exclude the grove maps", not presets.contains("art/maps/elder_grove"))


func _near(problems: Array[String], scene: Node, name: String, want: Vector3) -> void:
	var node := scene.find_child(name, true, false) as Node3D
	if node == null:
		problems.append(name + " missing")
	elif node.position.distance_to(want) > 0.02:
		problems.append("%s at %s, map says %s" % [name, node.position, want])
