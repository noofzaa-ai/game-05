extends RefCounted
## The Mummy Pyramid zone (level-designer 2026-11-17; Boss: mummies live ONLY in the mummy map, made like the goblin
## map): its three fight boards (ONE fight on one board from arena_maps; the throne-room and
## rest-camp maps were removed 2026-11-18, Boss), its 9-wave journey, the monsters it names, the zone state and the family separation rule.
## Data only: the families are derived from the combat data and the journey/map files, never from a hand list.

const MapLoader := preload("res://logic/map_loader.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Zones := preload("res://logic/world_zones.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const MapTests := preload("res://tests/test_map_data.gd")
const StageProps := preload("res://client/stage_props.gd")

const MAPS := ["mummy_pyramid_gate", "mummy_pyramid_hall", "mummy_pyramid_sanctum"]
const JOURNEY := "mummy_waves"
const KIT_PROPS := ["coffin", "torch", "pillar", "anubis_urn", "brazier", "altar", "stairs", "chest", "obelisk", "wall_panel", "urn"]


## The family of a monster id: its first name part (goblin_archer -> goblin, mummy_archer -> mummy), from the combat data's own ids.
static func family(enemy_id: String) -> String:
	return enemy_id.split("_")[0]


func run(ctx) -> void:
	var combat := CombatDataLoader.load_default()
	var types: Array = combat.enemies.keys()
	var index: Array = JSON.parse_string(FileAccess.get_file_as_string(MapLoader.INDEX_PATH))

	# --- the maps
	var fight_ids: Array = []
	for id in MAPS:
		var map = MapLoader.load_by_id(id)
		ctx.check("%s loads with no errors %s" % [id, map.errors], map.is_valid())
		ctx.check("%s is listed in data/maps/index.json" % id, index.has(id))
		ctx.check("%s has its art scene file" % id, not map.art_scene.is_empty() and ResourceLoader.exists(map.art_scene))
		ctx.check("%s is a pve stage in the pyramid region (not the goblin base)" % id, map.modes.has("pve") and str(JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id)).get("world_region", "")) == "pyramid")
		fight_ids.append(id)
		ctx.check("%s is a 16 x 9 m arena board with the arena camera, like the goblin boards" % id, map.camera_style == "arena" and is_equal_approx(map.half_width, 8.0) and is_equal_approx(map.half_depth, 4.5))
		ctx.check("%s: the squad of 3 starts on the left, the monsters on the right" % id, map.player_spawns.size() == 3 and map.player_spawns.all(func(p): return p.x < 0.0) and map.enemy_spawns.size() >= 5 and map.enemy_spawns.all(func(s): return s["position"].x > 0.0))
		var known: bool = map.enemy_spawns.all(func(s): return types.has(str(s["type"])))
		ctx.check("%s: every monster id it spawns exists in the combat data" % id, known)
		ctx.check("%s: it has the mummy melee in front and an archer behind (the ranged are listed last, furthest right)" % id, str(map.enemy_spawns[0]["type"]).begins_with("mummy") and map.enemy_spawns.any(func(s): return s["type"] == "mummy_archer"))
		for spawn in map.enemy_spawns:
			var at: Vector3 = spawn["position"]
			var inside := false
			for i in range(1, map.solids.size()):
				inside = inside or (map.solids[i]["box"] as AABB).has_point(at)
			ctx.check("%s: spawn %s %s is on the board and not inside a solid" % [id, spawn["type"], at], absf(at.x) <= map.half_width and absf(at.z) <= map.half_depth and not inside)
		_check_scene(ctx, map)
	ctx.check("there are three fight boards (the wave arenas), no rest map", fight_ids.size() == 3 and fight_ids.all(func(m): return MapLoader.load_by_id(m).kind != "rest"))
	for id in fight_ids:
		_check_gameplay(ctx, MapLoader.load_by_id(id), combat)
	var pool: Array = JourneyData.load_by_id(JOURNEY, types).arena_maps
	for id in pool:
		_check_island(ctx, MapLoader.load_by_id(str(id)))
	_check_budget_vs_goblin(ctx)

	# --- the journey: same schema as goblin_waves, 9 waves, the boss last
	var data = JourneyData.load_by_id(JOURNEY, types)
	ctx.check("%s.json parses with no errors %s" % [JOURNEY, data.errors], data.is_valid())
	var goblin = JourneyData.load_by_id("goblin_waves", types)
	ctx.check("it is a wave-mode journey of 9 waves like the goblin one (%d vs %d)" % [data.stage_count, goblin.stage_count], data.wave_mode and data.stage_count == 9 and data.stages.size() == 9 and data.stage_count == goblin.stage_count)
	# Between-wave heal (Boss 2026-11-20): the pyramid squad started every wave at full HP, so mummy_waves healed 0;
	# later the same day the goblin zone also went to 0 (no heal in either zone; see test_high_wizard.gd, test_journey.gd).
	ctx.check("it keeps the goblin journey's pacing fields (camps, node weights, corpse clear, count scale, loot by squad)", data.first_camp_stages == goblin.first_camp_stages and data.last_camp_stage == goblin.last_camp_stage and data.node_weights == goblin.node_weights and is_equal_approx(data.wave_count_scale, goblin.wave_count_scale) and data.loot_by_squad == goblin.loot_by_squad and data.treasure == goblin.treasure)
	ctx.check("no between-wave heal in the pyramid nor the goblin base (Boss 2026-11-20: too generous, both zones 0): %.2f / %.2f" % [data.wave_heal_fraction, goblin.wave_heal_fraction], is_zero_approx(data.wave_heal_fraction) and is_zero_approx(goblin.wave_heal_fraction))
	var last: Dictionary = data.stages[-1]
	var boss_entries: Array = last["enemies"].filter(func(e): return bool(e.get("boss", false)))
	var boss_types: Array = boss_entries.map(func(e): return str(e["type"]))
	boss_types.sort()
	ctx.check("wave 9 is the boss pair (Boss 2026-11-17): one Mummy High Wizard and one Mummy Pharaoh, both bosses %s" % [boss_types], boss_types == ["mummy_boss", "mummy_high_wizard"] and boss_entries.all(func(e): return int(e["count"]) == 1))
	ctx.check("the High Wizard is a real combat entry with its own kit (not the placeholder copy of the Pharaoh)", types.has("mummy_high_wizard") and not str(combat.enemies["mummy_high_wizard"].get("role", "")).contains("PLACEHOLDER") and str(combat.enemies["mummy_high_wizard"]["style"]) == "mummy_high_wizard")
	ctx.check("no journey wave names the superseded placeholder boss", data.stages.all(func(s): return s["enemies"].all(func(e): return str(e["type"]) != "mummy_boss_placeholder")))
	ctx.check("the Pharaoh is a real combat entry, not flagged PLACEHOLDER", types.has("mummy_boss") and not str(combat.enemies["mummy_boss"].get("role", "")).contains("PLACEHOLDER"))
	ctx.check("the arena pool is the three pyramid boards and every map the journey names exists (no separate boss arena or rest camp: boss_map/camp_map empty or a listed board) [%s, %s]" % [data.boss_map, data.camp_map], data.arena_maps.size() == 3 and data.arena_maps.all(func(m): return MAPS.has(m)) and data.combat_maps.all(func(m): return MAPS.has(m)) and [data.boss_map, data.camp_map].all(func(m): return str(m).is_empty() or MAPS.has(m)))
	var threat := func(fight: Dictionary) -> float:
		var total := 0.0
		for e in fight["enemies"]:
			var stats: Dictionary = combat.enemy_stats(str(e["type"]), int(e.get("level", fight["level"])))
			total += float(e["count"]) * float(stats["HP"]) * float(stats["ATK"]) * float(fight["power"]) * float(fight["power"])
		return total
	var boss_threat: float = threat.call(last) * float(data.boss.get("hp_mult", 1.0))
	var other_max := 0.0
	for i in 8:
		other_max = maxf(other_max, threat.call(data.stages[i]))
	ctx.check("escalation: the boss wave is the peak threat (%.0f vs the best plain wave %.0f)" % [boss_threat, other_max], boss_threat > other_max)
	ctx.check("escalation: the last plain wave is harder than wave 1 (levels and the archer rise)", threat.call(data.stages[7]) > threat.call(data.stages[0]) * 2.0 and int(data.stages[7]["level"]) > int(data.stages[0]["level"]))

	# --- no family mix across zones (families derived from the data)
	var journeys: Dictionary = {}  # journey id -> {family: true}
	var dir := DirAccess.open("res://data/journeys")
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var jd = JourneyData.load_by_id(file.get_basename(), types)
		if not jd.wave_mode:
			continue  # (ink_road is the old multi-family road, not a zone journey)
		var families := {}
		var fights: Array = []
		for stage in jd.stages:
			fights.append(stage)
			if not stage.get("challenge", {}).is_empty():
				fights.append(stage["challenge"])
		for fight in fights:
			for e in fight["enemies"]:
				families[family(str(e["type"]))] = true
		journeys[jd.id] = families
		ctx.check("journey %s has ONE monster family %s" % [jd.id, families.keys()], families.size() == 1)
		var map_ids: Array = []
		map_ids.append_array(jd.combat_maps)
		map_ids.append_array(jd.arena_maps)
		map_ids.append_array([jd.boss_map, jd.camp_map].filter(func(m): return not str(m).is_empty()))
		var map_ok := true
		for map_id in map_ids:
			for spawn in MapLoader.load_by_id(str(map_id)).enemy_spawns:
				map_ok = map_ok and families.has(family(str(spawn["type"])))
		ctx.check("every map of journey %s only spawns its family" % jd.id, map_ok)
	ctx.check("both zone journeys are found: goblin_waves and %s" % JOURNEY, journeys.has("goblin_waves") and journeys.has(JOURNEY))
	var seen := {}
	var shared := false
	for id in journeys:
		for fam in journeys[id]:
			shared = shared or seen.has(fam)
			seen[fam] = true
	ctx.check("no monster family is used by two zone journeys %s" % [seen.keys()], not shared and seen.size() == journeys.size())

	# --- the zone: built but still coming soon (a dev way opens it)
	var zone: Dictionary = Zones.zone("pyramid")
	ctx.check("zones.json has no problems %s" % [Zones.problems()], Zones.problems().is_empty())
	ctx.check("the pyramid zone owns the mummy journey and it exists", str(zone.get("journey", "")) == JOURNEY and FileAccess.file_exists("res://data/journeys/%s.json" % JOURNEY))
	var f := F.make()
	var p = Profile.new_player(f.rules, f.camp, F.rng(5))
	ctx.check("a new player: the pyramid is locked", Zones.state(p, "pyramid") == Zones.LOCKED)
	p.unlocks[Zones.boss_key("goblin_base")] = true
	ctx.check("the goblin boss beaten is not enough: the pyramid quest (card level 15) is still needed", Zones.state(p, "pyramid") == Zones.LOCKED)
	ctx.check("the pyramid zone owns the mummy journey", str(Zones.zone_of_journey(JOURNEY).get("id", "")) == "pyramid")


## Map-art budget (tools/maps/build_mummy_pyramid.gd writes art/maps/mummy_pyramid/manifest.json): a pyramid scene is three
## merged meshes (floor, dressing, kit), i.e. <= 6 draw surfaces, and lighter than every goblin_base camp scene.
const MAX_SURFACES := 6
const MAX_TRIS := 30000
const MAX_MESH_BYTES := 400000
const MAX_SCENE_BYTES := 10000
const MAX_LIGHTS := 4
const BOARD_W := 8.0
const BOARD_D := 4.5
const ALLOWED_TEXTURES := ["res://art/props/mummy_tomb/mummy_kit_albedo.png", "res://art/maps/mummy_tomb/painted/floor_tile.png", "res://art/maps/mummy_tomb/painted/sand.png"]


## The scene as the game loads it (client/stage_props.gd add_art_scene): three merged meshes (the Boss's tomb kit re-placed,
## the architecture, the painted floor) in external .res files (the .tscn stays tiny: scenes ship in the core pack, the meshes
## in the 'stages' battle pack), no MultiMesh (client/arena_props.gd hides those on a non-goblin board), a flat floor with no ink
## outline, 2-4 unshadowed lights, only the kit atlas and the two painted floor textures, the gameplay markers where the map
## JSON says, and nothing standing on the board but the cover.
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
	ctx.check("%s: it has the painted floor, the dressing and the merged kit meshes" % map.id, ground != null and dressing != null and kit != null)
	if ground == null or dressing == null or kit == null:
		holder.free()
		return
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var external := meshes.all(func(n): return (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).mesh.resource_path.begins_with("res://art/maps/mummy_pyramid/meshes/"))
	ctx.check("%s: its 3 meshes are external .res files under art/maps/mummy_pyramid/meshes ('stages' pack)" % map.id, external and meshes.size() == 3)
	ctx.check("%s: no MultiMesh (client/arena_props.gd hides them on a non-goblin board)" % map.id, scene.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
	var outlined := false
	for s in ground.mesh.get_surface_count():
		var material := ground.mesh.surface_get_material(s)
		outlined = outlined or material == null or material.next_pass != null
	ctx.check("%s: the flat floor has no ink outline (toon_no_outline, no next_pass, no shadow)" % map.id, bool(ground.get_meta("toon_no_outline", false)) and not outlined and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
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
	ctx.check("%s: web-cheap (%d draw surfaces <= %d, %d tris <= %d)" % [map.id, surfaces, MAX_SURFACES, tris, MAX_TRIS], surfaces <= MAX_SURFACES and tris <= MAX_TRIS)
	ctx.check("%s: only the kit atlas and the painted floor textures, no new texture %s" % [map.id, textures.keys()], textures.keys().all(func(t): return ALLOWED_TEXTURES.has(t)))
	var kit_material := kit.mesh.surface_get_material(0) as StandardMaterial3D
	ctx.check("%s: the kit is the tomb kit (its atlas) merged into one stone surface (+ flames)" % map.id, kit_material != null and kit_material.albedo_texture != null and kit_material.albedo_texture.resource_path == ALLOWED_TEXTURES[0] and kit.mesh.get_surface_count() <= 2)
	var lights := scene.find_children("*", "OmniLight3D", true, false)
	ctx.check("%s: 2-%d firelights, none casts shadows (%d)" % [map.id, MAX_LIGHTS, lights.size()], lights.size() >= 2 and lights.size() <= MAX_LIGHTS and lights.all(func(l): return not (l as Light3D).shadow_enabled))
	var size := FileAccess.get_file_as_bytes(map.art_scene).size()
	ctx.check("%s: the scene file is tiny (%d bytes <= %d: nothing embedded)" % [map.id, size, MAX_SCENE_BYTES], size <= MAX_SCENE_BYTES)
	var problems: Array[String] = []
	_near(problems, scene, "spawn", map.spawn)
	for i in map.enemy_spawns.size():
		_near(problems, scene, "enemy_%d" % i, map.enemy_spawns[i]["position"])
	ctx.check("%s: the scene's markers match the map (spawn, enemy_N) %s" % [map.id, problems], problems.is_empty())
	if map.kind != "rest":
		var stray := 0
		for v in (kit.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(v.x) < BOARD_W - 0.05 and absf(v.z) < BOARD_D - 0.05 and v.y > 0.1:
				stray += 1
		for v in (dressing.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(v.x) < BOARD_W - 0.05 and absf(v.z) < BOARD_D - 0.05 and v.y > 0.1 and not map.solids.any(func(solid): return (solid["box"] as AABB).grow(0.25).has_point(v)):
				stray += 1
		ctx.check("%s: nothing stands on the board but the cover (%d stray vertices): no prop hides a fight or fakes a wall" % [map.id, stray], stray == 0)
	holder.free()


## The wave boards (the journey's arena_maps) are floating islands like the goblin camp island (Boss 2026-11-17; client/
## arena_props.gd build_camp): the scene says so (meta floating_island, read by arena_props.is_pyramid_island), the island
## top is the board plus the goblin margins (MARGIN_X / MARGIN_Z), walls stand on the north, east and west margins, the
## front (the camera side) is an open cliff, and the client adds the goblin island's rock underside under that footprint.
const ArenaProps := preload("res://client/arena_props.gd")


func _check_island(ctx, map) -> void:
	var holder := Node3D.new()
	var scene := StageProps.add_art_scene(holder, map.art_scene, map.art_mood)
	if scene == null:
		ctx.check("%s: the island scene instances" % map.id, false)
		holder.free()
		return
	ctx.check("%s: the scene is marked a floating island (StageView builds the pyramid island, not the plain tile board)" % map.id, ArenaProps.is_pyramid_island(holder))
	var iw: float = map.half_width + ArenaProps.MARGIN_X
	var idp: float = map.half_depth + ArenaProps.MARGIN_Z
	var floor_box: AABB = (scene.get_node("PyramidFloor") as MeshInstance3D).mesh.get_aabb()
	ctx.check("%s: the island top is the goblin island's footprint (%.1f x %.1f m, floor %s)" % [map.id, iw * 2.0, idp * 2.0, floor_box],
		absf(floor_box.position.x + iw) < 0.05 and absf(floor_box.end.x - iw) < 0.05 and absf(floor_box.position.z + idp) < 0.05 and absf(floor_box.end.z - idp) < 0.05 and floor_box.position.y < -0.9)
	var verts: PackedVector3Array = (scene.get_node("Dressing") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var north := {}
	var west := {}
	var east := {}
	var front_tall := 0
	for v in verts:
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
	var kit_verts: PackedVector3Array = (scene.get_node("Kit") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in kit_verts:
		if v.z > idp - 1.2 and absf(v.x) < map.half_width + 1.0 and v.y > 1.3:
			front_tall += 1
	ctx.check("%s: walls over 1.2 m stand along the north margin (%d of %d metres), the west (%d) and the east (%d)" % [map.id, north.size(), int(iw * 2.0), west.size(), east.size()],
		north.size() >= int(iw * 2.0) - 2 and west.size() >= int(idp * 2.0) - 4 and east.size() >= int(idp * 2.0) - 4)
	ctx.check("%s: the front edge is an open cliff in front of the board (only low clutter there, nothing over 1.3 m; corner palms/piers allowed: %d vertices)" % [map.id, front_tall], front_tall == 0)
	var parent := Node3D.new()
	var island := ArenaProps.add_pyramid_island(parent, map)
	var cones := island.find_children("*", "MeshInstance3D", true, false)
	ctx.check("%s: the client adds the goblin island's rock underside (%d layers) under the footprint" % [map.id, cones.size()], cones.size() == 4 and cones.all(func(c): return (c as MeshInstance3D).position.y < -0.9))
	parent.free()
	holder.free()


func _near(problems: Array[String], scene: Node, name: String, want: Vector3) -> void:
	var node := scene.find_child(name, true, false) as Node3D
	if node == null:
		problems.append(name + " missing")
	elif node.position.distance_to(want) > 0.02:
		problems.append("%s at %s, map says %s" % [name, node.position, want])


## The fight board as gameplay: the goblin map rules (test_map_data.gd: spots on the floor and not in a solid, obstacles too
## high to jump on and low enough to see over, every monster reaches a waiting player within 90 s) plus the pyramid's cover
## rules: 2-4 cover blocks, all on the monster side (logic/auto_pilot.gd walks straight at its target, so the squad's half
## stays open), each enclosed by its dressing (StageView's plain collider box never shows), the archer's and the mage's spots
## each behind one, the extra rows the wave journey stacks on a spot (logic/journey.gd) never inside a block.
func _check_gameplay(ctx, map, combat) -> void:
	var tests = MapTests.new()
	tests._check_layout(ctx, map)
	tests._check_camera_8_layout(ctx, map)
	tests._check_monsters_reach_player(ctx, map, combat)
	var cover: Array = []
	for i in range(1, map.solids.size()):
		cover.append(map.solids[i]["box"])
	ctx.check("%s: 2-4 cover blocks, all on the monster side (x > 1.5): the squad's half stays open" % map.id, cover.size() >= 2 and cover.size() <= 4 and cover.all(func(b): return (b as AABB).position.x > 1.5))
	var scene := (load(map.art_scene) as PackedScene).instantiate() as Node3D
	var dressing := scene.get_node_or_null("Dressing") as MeshInstance3D
	var enclosed := dressing != null
	if dressing != null:
		var verts: PackedVector3Array = dressing.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for box in cover:
			var reach := AABB()
			var first := true
			for v in verts:
				if v.x > box.position.x - 0.3 and v.x < box.end.x + 0.3 and v.z > box.position.z - 0.3 and v.z < box.end.z + 0.3:
					reach = AABB(v, Vector3.ZERO) if first else reach.expand(v)
					first = false
			enclosed = enclosed and not first and reach.position.x < box.position.x and reach.end.x > box.end.x and reach.position.z < box.position.z and reach.end.z > box.end.z and reach.end.y >= box.end.y
	scene.free()
	ctx.check("%s: every cover block's dressing reaches past its collider on every side and over its top" % map.id, enclosed)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % map.id))
	var roles: String = str(raw.get("_spots", ""))
	var want_roles: Array = ["melee", "knight", "archer", "mage"]
	ctx.check("%s: spots for every pyramid monster role %s (%s)" % [map.id, want_roles, roles], want_roles.all(func(r): return roles.contains(r)))
	var last: int = map.enemy_spawns.size()
	var ranged: Array = map.enemy_spawns.slice(last - 2, last)
	var shielded := ranged.size() == 2
	for spot in ranged:
		var at: Vector3 = spot["position"]
		shielded = shielded and cover.any(func(b): return b.get_center().x < at.x and at.x - b.get_center().x < 2.2 and absf(b.get_center().z - at.z) < 0.8 + b.size.z * 0.5)
		shielded = shielded and map.enemy_spawns.slice(0, 4).all(func(m): return m["position"].x < at.x)
	ctx.check("%s: the archer's and the mage's spots are the far right ones, each behind a cover block" % map.id, shielded)
	var stacked_ok := true
	for spot in map.enemy_spawns:
		for row in range(1, 3):
			var at: Vector3 = spot["position"] + Vector3(-0.8 * float(row), 0.0, (0.9 if row % 2 == 0 else -0.9) * float(row))
			var body := Rect2(at.x - 0.4, at.z - 0.4, 0.8, 0.8)
			for box in cover:
				stacked_ok = stacked_ok and not body.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	ctx.check("%s: the extra rows the wave journey stacks on a spot (2 rows) never start inside a cover block" % map.id, stacked_ok)


## The pyramid maps against the goblin camps they are made like (art/maps/*/manifest.json, both written by their builders),
## and the meshes and painted floors go to the 'stages' battle pack (tools/web/pack_layout.json).
func _check_budget_vs_goblin(ctx) -> void:
	var ours = JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/mummy_pyramid/manifest.json"))
	var goblin = JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/goblin_base/manifest.json"))
	if not (ours is Dictionary and goblin is Dictionary):
		ctx.check("both map manifests read", false)
		return
	var goblin_tris := 1e9
	var goblin_surfaces := 1e9
	for id in goblin:
		goblin_tris = minf(goblin_tris, float(goblin[id].get("triangles_instanced", 1e9)))
		goblin_surfaces = minf(goblin_surfaces, float(goblin[id].get("draw_surfaces", 1e9)))
	for id in MAPS:
		var row: Dictionary = ours.get(id, {})
		ctx.check("%s: lighter than every goblin camp scene (%s tris vs %d, %s surfaces vs %d, %s mesh bytes <= %d)" % [id, row.get("triangles"), goblin_tris, row.get("draw_surfaces"), goblin_surfaces, row.get("mesh_bytes"), MAX_MESH_BYTES],
			not row.is_empty() and float(row.triangles) <= goblin_tris and float(row.draw_surfaces) <= goblin_surfaces and float(row.mesh_bytes) <= MAX_MESH_BYTES)
	var layout = JSON.parse_string(FileAccess.get_file_as_string("res://tools/web/pack_layout.json"))
	var stages := false
	for pack in layout.get("packs", []):
		if str(pack.get("name", "")) == "stages" and str(pack.get("stage", "")) == "battle":
			var include: Array = pack.get("include", [])
			stages = include.any(func(p): return "res://art/maps/mummy_pyramid/meshes/".begins_with(str(p))) and include.any(func(p): return ALLOWED_TEXTURES[1].begins_with(str(p))) and include.any(func(p): return ALLOWED_TEXTURES[0].begins_with(str(p)))
	ctx.check("the pyramid meshes, the kit atlas and the painted floors ship in the 'stages' battle pack", stages)
