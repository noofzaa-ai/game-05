extends RefCounted
## Reads and validates map files. A broken map never crashes the game: it comes back with
## `errors` filled in (the future map editor will show these).
## To add a map: drop a JSON file into data/maps/ and list its file name in data/maps/index.json.

const MapData := preload("res://logic/map_data.gd")

const MAP_DIR := "res://data/maps/"
const INDEX_PATH := "res://data/maps/index.json"
const SUPPORTED_VERSION := 1
const KINDS: Array[String] = ["fight", "rest"]
const ART_MOODS: Array[String] = ["", "night", "camp"]
const ART_EXTENSIONS: Array[String] = ["glb", "gltf", "tscn", "scn"]


static func load_by_id(id: String) -> MapData:
	var path := MAP_DIR + id + ".json"
	if not FileAccess.file_exists(path):
		var missing := MapData.new()
		missing.errors.append("map file not found: %s" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path))


## All valid maps in the index that allow the given mode ("pve" or "pvp").
static func list_for_mode(mode: String) -> Array[MapData]:
	var result: Array[MapData] = []
	if not FileAccess.file_exists(INDEX_PATH):
		return result
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(INDEX_PATH)) != OK or typeof(json.data) != TYPE_ARRAY:
		return result
	for entry in json.data:
		var map := load_by_id(str(entry))
		if map.is_valid() and map.modes.has(mode):
			result.append(map)
	return result


static func parse(text: String) -> MapData:
	var map := MapData.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		map.errors.append("invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return map
	if typeof(json.data) != TYPE_DICTIONARY:
		map.errors.append("top level must be an object")
		return map
	var root: Dictionary = json.data

	if int(root.get("version", 0)) != SUPPORTED_VERSION:
		map.errors.append("unsupported version (expected %d)" % SUPPORTED_VERSION)
	map.id = str(root.get("id", ""))
	map.display_name = str(root.get("name", ""))
	if map.id.is_empty():
		map.errors.append("missing id")
	if map.display_name.is_empty():
		map.errors.append("missing name")

	for mode in _list(root, "modes", map):
		map.modes.append(str(mode))
	if map.modes.is_empty():
		map.errors.append("modes must list at least one of: pve, pvp")

	var bounds: Dictionary = root.get("bounds", {}) if typeof(root.get("bounds")) == TYPE_DICTIONARY else {}
	map.half_width = float(bounds.get("half_width", 0.0))
	map.half_depth = float(bounds.get("half_depth", 0.0))
	if map.half_width <= 0.0 or map.half_depth <= 0.0:
		map.errors.append("bounds.half_width and bounds.half_depth must be positive")

	map.spawn = _vec3(root.get("spawn"), "spawn", map)
	if root.has("player_spawns"):
		if root["player_spawns"] is Array:
			for point in root["player_spawns"]:
				map.player_spawns.append(_vec3(point, "player_spawns", map))
		else:
			map.errors.append("player_spawns must be an array")

	var index := 0
	for solid in _list(root, "solids", map):
		var label := "solids[%d]" % index
		index += 1
		if typeof(solid) != TYPE_DICTIONARY:
			map.errors.append("%s must be an object" % label)
			continue
		map.solids.append({"box": _box(solid, label, map), "material": str(solid.get("material", "default"))})

	index = 0
	for zone in _list(root, "camera_zones", map):
		var label := "camera_zones[%d]" % index
		index += 1
		if typeof(zone) != TYPE_DICTIONARY:
			map.errors.append("%s must be an object" % label)
			continue
		var camera: Dictionary = zone.get("camera", {}) if typeof(zone.get("camera")) == TYPE_DICTIONARY else {}
		map.camera_zones.append({
			"box": _box(zone, label, map),
			"camera": {
				"name": str(camera.get("name", "Zone camera")),
				"offset": _vec3(camera.get("offset"), label + ".camera.offset", map),
				"look_y": float(camera.get("look_y", 1.0)),
				"fov": float(camera.get("fov", 55.0)),
			},
			"lock": bool(zone.get("lock", false)),
		})

	index = 0
	for spawn in _list(root, "enemy_spawns", map):
		var label := "enemy_spawns[%d]" % index
		index += 1
		if typeof(spawn) != TYPE_DICTIONARY:
			map.errors.append("%s must be an object" % label)
			continue
		var enemy_type := str(spawn.get("type", ""))
		if enemy_type.is_empty():
			map.errors.append("%s needs a type" % label)
		var level := int(spawn.get("level", 1))
		if level < 1:
			map.errors.append("%s.level must be 1 or more" % label)
			level = 1
		map.enemy_spawns.append({"type": enemy_type, "level": level, "position": _vec3(spawn.get("position"), label + ".position", map)})

	index = 0
	var rest_ids: Array[String] = []
	for point in _list(root, "rest_points", map):
		var label := "rest_points[%d]" % index
		index += 1
		if typeof(point) != TYPE_DICTIONARY:
			map.errors.append("%s must be an object" % label)
			continue
		var point_id := str(point.get("id", ""))
		if point_id.is_empty() or rest_ids.has(point_id):
			map.errors.append("%s needs a unique id" % label)
		rest_ids.append(point_id)
		var radius := float(point.get("radius", 1.5))
		if radius <= 0.0:
			map.errors.append("%s.radius must be positive" % label)
		map.rest_points.append({"id": point_id, "position": _vec3(point.get("position"), label + ".position", map), "radius": radius})

	index = 0
	for prop in _list(root, "props", map):
		var label := "props[%d]" % index
		index += 1
		if typeof(prop) != TYPE_DICTIONARY:
			map.errors.append("%s must be an object" % label)
			continue
		var kind := str(prop.get("kind", ""))
		if kind.is_empty():
			map.errors.append("%s needs a kind" % label)
		var prop_scale := float(prop.get("scale", 1.0))
		var count := int(prop.get("count", 1))
		if prop_scale <= 0.0 or count < 1 or float(prop.get("radius", 0.0)) < 0.0:
			map.errors.append("%s: scale must be above 0, count at least 1 and radius not negative" % label)
		map.props.append({
			"kind": kind, "position": _vec3(prop.get("position"), label + ".position", map), "scale": maxf(prop_scale, 0.01),
			"yaw": float(prop.get("yaw", 0.0)), "count": maxi(count, 1), "radius": maxf(float(prop.get("radius", 0.0)), 0.0),
		})
	map.camera_style = str(root.get("camera_style", "side"))
	if not ["side", "top_down", "arena"].has(map.camera_style):
		map.errors.append("camera_style must be side, top_down or arena")
	map.atmosphere = str(root.get("atmosphere", "golden"))
	if not ["golden", "ink"].has(map.atmosphere):
		map.errors.append("atmosphere must be golden or ink")
	_parse_stage_fields(root, map)
	return map


## The optional fields of the small journey stages (Boss 2026-10-13): kind, art_scene, art_mood, exit_portals,
## campfire. A map without them loads exactly as before (fight, no art scene, portals derived from the bounds).
static func _parse_stage_fields(root: Dictionary, map: MapData) -> void:
	map.kind = str(root.get("kind", "fight"))
	if not KINDS.has(map.kind):
		map.errors.append("kind must be one of %s" % [KINDS])
	if map.kind == "rest" and not map.enemy_spawns.is_empty():
		map.errors.append("a rest map is safe: it may not have enemy_spawns")

	map.art_scene = str(root.get("art_scene", ""))
	if not map.art_scene.is_empty() and (not map.art_scene.begins_with("res://") or not ART_EXTENSIONS.has(map.art_scene.get_extension())):
		map.errors.append("art_scene must be a res:// path to a %s file" % [ART_EXTENSIONS])
	map.art_mood = str(root.get("art_mood", ""))
	if not ART_MOODS.has(map.art_mood):
		map.errors.append("art_mood must be one of %s" % [ART_MOODS])
	if not map.art_scene.is_empty():
		# The client builds scenery from `props`, so the art scene travels as one extra prop entry.
		map.props.append({"kind": "art_scene", "path": map.art_scene, "mood": map.art_mood, "position": Vector3.ZERO,
			"scale": 1.0, "yaw": 0.0, "count": 1, "radius": 0.0})

	if root.has("exit_portals"):
		var index := 0
		for spot in _list(root, "exit_portals", map):
			var at := _vec3(spot, "exit_portals[%d]" % index, map)
			if absf(at.x) > map.half_width or absf(at.z) > map.half_depth:
				map.errors.append("exit_portals[%d] is outside the bounds" % index)
			map.exit_portals.append(at)
			index += 1
		if map.exit_portals.is_empty():
			map.errors.append("exit_portals, when given, needs at least one position")
	else:
		map.exit_portals = default_exit_portals(map)

	if root.has("campfire"):
		map.campfire = _vec3(root.get("campfire"), "campfire", map)
		map.has_campfire = true
		if map.kind != "rest":
			map.errors.append("only a rest map has a campfire")


## Two spots north (up-screen, -z) of the centre, each a quarter of the width to the side.
static func default_exit_portals(map: MapData) -> Array[Vector3]:
	var z := -map.half_depth * 0.6
	return [Vector3(-map.half_width * 0.25, 0.05, z), Vector3(map.half_width * 0.25, 0.05, z)]


## Optional list field: missing is fine, a non-list is reported.
static func _list(root: Dictionary, key: String, map: MapData) -> Array:
	var value: Variant = root.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		map.errors.append("%s must be a list" % key)
		return []
	return value


static func _vec3(value: Variant, label: String, map: MapData) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		map.errors.append("%s must be [x, y, z]" % label)
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _box(value: Variant, label: String, map: MapData) -> AABB:
	if typeof(value) != TYPE_DICTIONARY:
		map.errors.append("%s must be an object" % label)
		return AABB()
	var center := _vec3(value.get("center"), label + ".center", map)
	var size := _vec3(value.get("size"), label + ".size", map)
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		map.errors.append("%s.size must be positive" % label)
	return AABB(center - size / 2.0, size)
