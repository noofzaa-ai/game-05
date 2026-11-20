extends RefCounted
## The optional map fields the goblin-forest stages brought (Boss 2026-10-13): kind, art_scene, art_mood,
## exit_portals, campfire (logic/map_loader.gd) and the art scene prop in client/stage_props.gd; plus the per-map
## checks on the goblin maps still in play. The goblin_arena_a/b/c and goblin_rest_camp stages (and the
## goblin_base_chief / goblin_base_rest maps) were removed 2026-11-20 (Boss: unused); wave mode plays the three
## goblin_base boards below (their render budget: tests/test_goblin_base_render_budget.gd; camera-8 layout and
## monster reach: tests/test_map_data.gd for every index map).

const MapLoader := preload("res://logic/map_loader.gd")
const StageProps := preload("res://client/stage_props.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")

const MAPS := ["goblin_base_gate", "goblin_base_courtyard", "goblin_base_quarry"]
const REMOVED := ["goblin_arena_a", "goblin_arena_b", "goblin_arena_c", "goblin_rest_camp", "goblin_base_chief", "goblin_base_rest"]
const MINIMAL := """{"version": 1, "id": "t", "name": "T", "modes": ["pve"],
	"bounds": {"half_width": 10, "half_depth": 8}, "spawn": [0, 0, 0],
	"solids": [{"center": [0, 0, 0], "size": [1, 1, 1]}]}"""


func run(ctx) -> void:
	_test_fields(ctx)
	var combat := CombatDataLoader.load_default()
	var index: Array = JSON.parse_string(FileAccess.get_file_as_string(MapLoader.INDEX_PATH))
	for id in MAPS:
		var map := MapLoader.load_by_id(id)
		ctx.check("%s is valid %s and listed in index.json" % [id, map.errors], map.is_valid() and index.has(id))
		ctx.check("%s: its art scene exists (%s)" % [id, map.art_scene], map.art_scene.begins_with("res://art/maps/goblin_base/") and ResourceLoader.exists(map.art_scene))
		ctx.check("%s: two exit portals, north of the middle, in bounds, not in a solid" % id, map.exit_portals.size() == 2 and map.exit_portals.all(func(p): return p.z < 0.0 and absf(p.x) < map.half_width and absf(p.z) < map.half_depth and _free(map, p)))
		ctx.check("%s: a fight map with 8 monster spots of known types" % id, map.kind == "fight" and map.enemy_spawns.size() == 8 and map.enemy_spawns.all(func(s): return combat.enemies.has(s["type"])) and not map.has_campfire)
	for id in REMOVED:
		ctx.check("%s is removed: no map file, not in index.json" % id, not FileAccess.file_exists("res://data/maps/%s.json" % id) and not index.has(id))


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


func _free(map, at: Vector3) -> bool:
	for solid in map.solids:
		var box: AABB = solid["box"]
		if box.end.y <= 0.001:
			continue
		if box.grow(0.5).has_point(Vector3(at.x, box.get_center().y, at.z)):
			return false
	return true
