extends RefCounted
## Tests map loading and validation (logic/map_loader.gd + data/maps/).

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimBody := preload("res://logic/sim_body.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const StageProps := preload("res://client/stage_props.gd")
const MapLoader := preload("res://logic/map_loader.gd")

const MINIMAL := """{"version": 1, "id": "t", "name": "T", "modes": ["pve"],
	"bounds": {"half_width": 5, "half_depth": 2}, "spawn": [0, 0, 0],
	"solids": [{"center": [0, 0, 0], "size": [1, 1, 1]}]}"""


func run(ctx) -> void:
	var real := MapLoader.load_by_id("sunward_valley")
	ctx.check("the shipped map is valid %s" % [real.errors], real.is_valid())
	ctx.check("shipped map has solids and a camera zone", real.solids.size() == 5 and real.camera_zones.size() == 1)
	ctx.check("the camera zone keeps its camera settings", real.camera_zones[0]["camera"]["fov"] == 45.0)
	ctx.check("the shipped map has 7 monsters, all goblins (Boss 2026-10-10: goblins only)", real.enemy_spawns.size() == 7 and real.enemy_spawns.all(func(s): return s["type"] == "goblin"))

	var combat := CombatDataLoader.load_default()
	var known_enemies := true
	for spawn in real.enemy_spawns:
		known_enemies = known_enemies and combat.enemies.has(spawn["type"])
	ctx.check("every enemy a map spawns exists in the combat data", known_enemies)
	ctx.check("a monster spawn defaults to level 1 and may set a level", real.enemy_spawns[0]["level"] == 1 and MapLoader.parse(MINIMAL.replace("\"solids\"", "\"enemy_spawns\": [{\"type\": \"x\", \"level\": 4, \"position\": [0, 0, 0]}], \"solids\"")).enemy_spawns[0]["level"] == 4)
	ctx.check("a spawn level below 1 is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"enemy_spawns\": [{\"type\": \"x\", \"level\": 0, \"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("the shipped map has a rest point with a position and a radius", real.rest_points.size() >= 1 and real.rest_points[0]["radius"] > 0.0 and real.rest_points[0]["id"] != "")
	ctx.check("a rest point without an id is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"rest_points\": [{\"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("two rest points with the same id are reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"rest_points\": [{\"id\": \"a\", \"position\": [0, 0, 0]}, {\"id\": \"a\", \"position\": [1, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("a rest point with a zero radius is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"rest_points\": [{\"id\": \"a\", \"radius\": 0, \"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	var arena := MapLoader.load_by_id("ink_garden")
	ctx.check("the wide arena map is valid %s" % [arena.errors], arena.is_valid())
	ctx.check("it is a wide top-down arena (%.0f x %.0f)" % [arena.half_width * 2.0, arena.half_depth * 2.0], arena.camera_style == "top_down" and arena.half_depth >= 12.0 and arena.half_width >= 20.0)
	var arena_known := true
	for spawn in arena.enemy_spawns:
		arena_known = arena_known and combat.enemies.has(spawn["type"])
	ctx.check("it has a crowd of monsters of known types (%d)" % arena.enemy_spawns.size(), arena.enemy_spawns.size() >= 6 and arena_known)
	var kinds_known := true
	for prop in arena.props:
		kinds_known = kinds_known and StageProps.KINDS.has(prop["kind"])
	ctx.check("it has scenery and every prop kind exists in the client (%d props)" % arena.props.size(), arena.props.size() >= 10 and kinds_known)
	ctx.check("legacy ink garden retains rest points but is not offered for PvE", arena.rest_points.size() >= 1 and not MapLoader.list_for_mode("pve").any(func(m): return m.id == "ink_garden"))
	ctx.check("the side-view valley keeps the default camera style", real.camera_style == "side")
	ctx.check("an unknown camera style is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"camera_style\": \"upside_down\", \"solids\"")).is_valid())
	ctx.check("a prop without a kind is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"props\": [{\"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("a prop with a zero scale is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"props\": [{\"kind\": \"rock\", \"scale\": 0, \"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("a spawn without a type is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"enemy_spawns\": [{\"position\": [0, 0, 0]}], \"solids\"")).is_valid())
	ctx.check("a spawn with a bad position is reported", not MapLoader.parse(MINIMAL.replace("\"solids\"", "\"enemy_spawns\": [{\"type\": \"x\", \"position\": [0]}], \"solids\"")).is_valid())

	ctx.check("pve lists the shipped map", MapLoader.list_for_mode("pve").size() >= 1)
	ctx.check("pvp has no maps yet", MapLoader.list_for_mode("pvp").is_empty())
	ctx.check("a missing map reports an error instead of crashing", not MapLoader.load_by_id("nope").is_valid())

	var all_valid := true
	var index := JSON.new()
	index.parse(FileAccess.get_file_as_string(MapLoader.INDEX_PATH))
	for id in index.data:
		all_valid = all_valid and MapLoader.load_by_id(str(id)).is_valid()
	ctx.check("every map listed in index.json is valid", all_valid)

	_test_second_stage(ctx, combat, arena)
	for id in index.data:
		_check_layout(ctx, MapLoader.load_by_id(str(id)))
	for id in ["ink_garden", "shrine_wall"]:
		_check_camera_8_layout(ctx, MapLoader.load_by_id(id))
		_check_monsters_reach_player(ctx, MapLoader.load_by_id(id), combat)

	ctx.check("minimal map is valid", MapLoader.parse(MINIMAL).is_valid())
	ctx.check("unknown extra fields are ignored", MapLoader.parse(MINIMAL.replace("\"id\"", "\"future_field\": 1, \"id\"")).is_valid())

	ctx.check("broken JSON is reported", not MapLoader.parse("{ nope").is_valid())
	ctx.check("a non-object is reported", not MapLoader.parse("[1, 2]").is_valid())
	ctx.check("wrong version is reported", not MapLoader.parse(MINIMAL.replace("\"version\": 1", "\"version\": 99")).is_valid())
	ctx.check("missing id is reported", not MapLoader.parse(MINIMAL.replace("\"id\": \"t\",", "")).is_valid())
	ctx.check("empty modes is reported", not MapLoader.parse(MINIMAL.replace("[\"pve\"]", "[]")).is_valid())
	ctx.check("zero-size solid is reported", not MapLoader.parse(MINIMAL.replace("[1, 1, 1]", "[0, 1, 1]")).is_valid())
	ctx.check("malformed vector is reported", not MapLoader.parse(MINIMAL.replace("[0, 0, 0],\n\t\"solids\"", "[0, 0],\n\t\"solids\"")).is_valid())
	ctx.check("solids that are not a list are reported", not MapLoader.parse(MINIMAL.replace("\"solids\": [", "\"solids\": {\"a\": [")).is_valid())
	ctx.check("a solid that is not an object is reported without crashing", not MapLoader.parse(MINIMAL.replace("[{\"center\": [0, 0, 0], \"size\": [1, 1, 1]}]", "[5]")).is_valid())
	_test_practice_field(ctx, CombatDataLoader.load_default())


## The practice field (Boss 2026-10-06): no monsters, and the stage never "clears" by itself.
func _test_practice_field(ctx, combat) -> void:
	var field = MapLoader.load_by_id("practice_field")
	var pve := MapLoader.list_for_mode("pve")
	ctx.check("the practice field is valid and the first PvE stage %s" % [field.errors], field.is_valid() and not pve.is_empty() and pve[0].id == "practice_field")
	ctx.check("the practice field has no monsters and a rest point", field.enemy_spawns.is_empty() and field.rest_points.size() == 1)
	var world := SimWorld.new()
	world.half_width = field.half_width
	world.half_depth = field.half_depth
	for solid in field.solids:
		world.add_solid(solid["box"])
	var sim := GameSim.new(world, combat, RandomNumberGenerator.new())
	sim.add_player(1, field.spawn)
	var cleared := false
	for tick in 120:
		sim.tick()
		for event in sim.events:
			cleared = cleared or event["type"] == "stage_cleared"
	ctx.check("a stage with no monsters never ends by itself", not cleared)


## The second stage: valid, listed, and a step harder than the Ink Garden (higher monster levels,
## more total monster health and attack), with the gear-check moment (a level 3 monster drops better tiers).
func _test_second_stage(ctx, combat, garden) -> void:
	var shrine := MapLoader.load_by_id("shrine_wall")
	ctx.check("the second stage (shrine wall) is valid %s" % [shrine.errors], shrine.is_valid())
	ctx.check("legacy shrine remains loadable but is not offered for PvE", not MapLoader.list_for_mode("pve").any(func(m): return m.id == "shrine_wall") and shrine.camera_style == "top_down" and shrine.half_width >= 24.0 and shrine.half_depth >= 16.0)
	var known := true
	var types := {}
	for spawn in shrine.enemy_spawns:
		known = known and combat.enemies.has(spawn["type"])
		types[spawn["type"]] = true
	var family := types.keys().all(func(t): return str(t).begins_with("goblin"))
	ctx.check("its monsters are the goblin family (goblins + archer, mage, knight: Boss-approved plan 2026-10-10), all known (%d monsters: %s)" % [shrine.enemy_spawns.size(), types.keys()], known and family and types.has("goblin") and types.has("goblin_knight") and shrine.enemy_spawns.size() >= 6)
	var min_level := 99
	var max_level := 0
	for spawn in shrine.enemy_spawns:
		min_level = mini(min_level, spawn["level"])
		max_level = maxi(max_level, spawn["level"])
	var garden_max := 0
	for spawn in garden.enemy_spawns:
		garden_max = maxi(garden_max, spawn["level"])
	ctx.check("its monsters are level 2+ and some reach level 3 (garden tops out at %d)" % garden_max, min_level >= 2 and max_level >= 3 and max_level > garden_max)
	var shrine_power := _total_power(shrine, combat)
	var garden_power := _total_power(garden, combat)
	ctx.check("it is harder: total monster HP %.0f vs %.0f, total ATK %.0f vs %.0f" % [shrine_power.x, garden_power.x, shrine_power.y, garden_power.y], shrine_power.x > garden_power.x * 1.1 and shrine_power.y > garden_power.y * 1.1)
	ctx.check("it has two rest points and a camera zone over the shrine yard", shrine.rest_points.size() == 2 and shrine.camera_zones.size() == 1)
	var kinds_known := true
	for prop in shrine.props:
		kinds_known = kinds_known and StageProps.KINDS.has(prop["kind"])
	ctx.check("its scenery uses only prop kinds the client has (%d props)" % shrine.props.size(), shrine.props.size() >= 10 and kinds_known)


## (total HP, total ATK) of a map's monsters at their levels.
func _total_power(map, combat) -> Vector2:
	var total := Vector2.ZERO
	for spawn in map.enemy_spawns:
		var stats: Dictionary = combat.enemy_stats(spawn["type"], spawn["level"])
		total += Vector2(float(stats["HP"]), float(stats["ATK"]))
	return total


## Spawn, monster spawns and rest points are inside the bounds, stand on ground and not inside a solid.
func _check_layout(ctx, map) -> void:
	var spots: Array = [["the player spawn", map.spawn]]
	for index in map.enemy_spawns.size():
		spots.append(["monster %d" % index, map.enemy_spawns[index]["position"]])
	for point in map.rest_points:
		spots.append(["rest point " + point["id"], point["position"]])
	var problems: Array[String] = []
	for spot in spots:
		var at: Vector3 = spot[1]
		if absf(at.x) > map.half_width - SimBody.HALF_WIDTH or absf(at.z) > map.half_depth - SimBody.HALF_DEPTH:
			problems.append("%s out of bounds" % spot[0])
		var body := SimBody.new()
		body.position = at
		var on_ground := false
		for solid in map.solids:
			var box: AABB = solid["box"]
			if _overlaps(body.aabb(), box):
				problems.append("%s inside a solid" % spot[0])
			if at.x >= box.position.x and at.x <= box.end.x and at.z >= box.position.z and at.z <= box.end.z and box.end.y <= at.y + 0.01:
				on_ground = true
		if not on_ground:
			problems.append("%s has no ground under it" % spot[0])
	for point in map.rest_points:
		var center: Vector3 = point["position"]
		if absf(center.x) + point["radius"] > map.half_width or absf(center.z) + point["radius"] > map.half_depth:
			problems.append("rest point %s's circle leaves the bounds" % point["id"])
	ctx.check("%s: spawns and rest points are in bounds, on the ground, not in solids %s" % [map.id, problems], problems.is_empty())


## Rules for the default camera (8: High, looking north from the south): tall scenery stands outside the
## walkable bounds and never on the camera's side (south), so it cannot hide a fight; every rock or wall
## is too high to jump onto (a ledge only the player can reach would strand the monsters) and short enough
## to see over.
func _check_camera_8_layout(ctx, map) -> void:
	var trees_ok := true
	for prop in map.props:
		if prop["kind"] == "pine" or prop["kind"] == "plum":
			var at: Vector3 = prop["position"]
			var outside: bool = absf(at.x) > map.half_width + 1.0 or at.z < -map.half_depth - 0.5
			trees_ok = trees_ok and outside and at.z <= map.half_depth
	ctx.check("%s: tall trees stand outside the walkable area and never south of it" % map.id, trees_ok)
	var jump_apex := 7.5 * 7.5 / (2.0 * 20.0)  # Movement.JUMP_VELOCITY^2 / (2 * GRAVITY)
	var obstacles_ok := true
	for solid in map.solids:
		var box: AABB = solid["box"]
		if box.end.y <= 0.001:
			continue  # floor
		obstacles_ok = obstacles_ok and box.position.y <= 0.001 and box.end.y > jump_apex and box.end.y <= 1.8
	ctx.check("%s: obstacles stand on the floor, too high to jump on (> %.2f) and low enough to see over (<= 1.8)" % [map.id, jump_apex], obstacles_ok)


## The monster AI walks around obstacles but is not a pathfinder: with a passive player at the spawn,
## every monster must arrive within 90 seconds (none gets stuck behind a rock or a wall). A ranged
## monster arrives when it is within its keep_range (+1 m) instead: it stops there to shoot.
func _check_monsters_reach_player(ctx, map, combat) -> void:
	var world := SimWorld.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sim := GameSim.new(world, combat, rng)
	sim.add_player(1, map.spawn, {"HP": 10000000, "DEF": 100000, "STAMINA": 1000})
	for index in map.enemy_spawns.size():
		var spawn: Dictionary = map.enemy_spawns[index]
		sim.add_enemy(10 + index, spawn["position"], spawn["type"], spawn["level"])
	var arrived := {}
	for tick in 60 * 90:
		sim.tick()
		for id in sim.fighters:
			if id != 1 and not arrived.has(id):
				var offset: Vector3 = sim.bodies[id].position - sim.bodies[1].position
				var keep := float(combat.enemies[sim.fighters[id].enemy_type]["ai"].get("keep_range", 0.0))
				if Vector2(offset.x, offset.z).length() < maxf(5.5, keep + 1.0):
					arrived[id] = tick
		if arrived.size() == map.enemy_spawns.size():
			break
	ctx.check("%s: every monster reaches a player waiting at the spawn (%d/%d within 90 s)" % [map.id, arrived.size(), map.enemy_spawns.size()], arrived.size() == map.enemy_spawns.size())


func _overlaps(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - 0.0001 and a.end.x > b.position.x + 0.0001 and a.position.y < b.end.y - 0.0001 and a.end.y > b.position.y + 0.0001 and a.position.z < b.end.z - 0.0001 and a.end.z > b.position.z + 0.0001
