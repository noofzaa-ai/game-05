extends RefCounted
## The Mummy Pyramid zone (level-designer 2026-11-17; Boss: mummies live ONLY in the mummy map, made like the goblin
## map): its five maps, its 9-wave journey, the monsters it names, the zone state and the family separation rule.
## Data only: the families are derived from the combat data and the journey/map files, never from a hand list.

const MapLoader := preload("res://logic/map_loader.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Zones := preload("res://logic/world_zones.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")

const MAPS := ["mummy_pyramid_gate", "mummy_pyramid_hall", "mummy_pyramid_sanctum", "mummy_pyramid_pharaoh", "mummy_pyramid_rest"]
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
		if map.kind == "rest":
			ctx.check("%s is the safe rest map: no monsters, a rest point inside the bounds" % id, map.enemy_spawns.is_empty() and map.rest_points.size() >= 1 and absf(map.rest_points[0]["position"].x) < map.half_width and absf(map.rest_points[0]["position"].z) < map.half_depth)
			continue
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
	ctx.check("there are four fight boards: three arenas and the throne chamber", fight_ids.size() == 4)

	# --- the journey: same schema as goblin_waves, 9 waves, the boss last
	var data = JourneyData.load_by_id(JOURNEY, types)
	ctx.check("%s.json parses with no errors %s" % [JOURNEY, data.errors], data.is_valid())
	var goblin = JourneyData.load_by_id("goblin_waves", types)
	ctx.check("it is a wave-mode journey of 9 waves like the goblin one (%d vs %d)" % [data.stage_count, goblin.stage_count], data.wave_mode and data.stage_count == 9 and data.stages.size() == 9 and data.stage_count == goblin.stage_count)
	ctx.check("it keeps the goblin journey's pacing fields (camps, node weights, heal, corpse clear, count scale, loot by squad)", data.first_camp_stages == goblin.first_camp_stages and data.last_camp_stage == goblin.last_camp_stage and data.node_weights == goblin.node_weights and is_equal_approx(data.wave_heal_fraction, goblin.wave_heal_fraction) and is_equal_approx(data.wave_count_scale, goblin.wave_count_scale) and data.loot_by_squad == goblin.loot_by_squad and data.treasure == goblin.treasure)
	var last: Dictionary = data.stages[-1]
	var boss_entries: Array = last["enemies"].filter(func(e): return bool(e.get("boss", false)))
	ctx.check("wave 9 has exactly one boss entry, the clearly named placeholder", boss_entries.size() == 1 and str(boss_entries[0]["type"]) == "mummy_boss_placeholder" and int(boss_entries[0]["count"]) == 1)
	ctx.check("the boss and the archer are flagged PLACEHOLDER in the combat data", str(combat.enemies["mummy_boss_placeholder"].get("role", "")).contains("PLACEHOLDER") and str(combat.enemies["mummy_archer"].get("role", "")).contains("PLACEHOLDER"))
	ctx.check("the arena pool and the special maps all exist and are valid pyramid maps", data.arena_maps.size() == 3 and data.arena_maps.all(func(m): return MAPS.has(m)) and MAPS.has(data.boss_map) and MAPS.has(data.camp_map) and MapLoader.load_by_id(data.camp_map).kind == "rest" and data.combat_maps.all(func(m): return MAPS.has(m)))
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
		map_ids.append_array([jd.boss_map, jd.camp_map])
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
	ctx.check("the pyramid zone names the built journey as dev_journey and it exists", str(zone.get("dev_journey", "")) == JOURNEY and FileAccess.file_exists("res://data/journeys/%s.json" % JOURNEY))
	var f := F.make()
	var p = Profile.new_player(f.rules, f.camp, F.rng(5))
	ctx.check("a new player: the pyramid is coming soon", Zones.state(p, "pyramid") == Zones.SOON)
	p.unlocks[Zones.boss_key("goblin_base")] = true
	ctx.check("even with the goblin boss beaten the pyramid is still coming soon (not exposed until the Boss approves it)", Zones.state(p, "pyramid") == Zones.SOON)
	ctx.check("a mummy run cannot beat any boss yet (no zone owns the journey)", Zones.zone_of_journey(JOURNEY).is_empty() and not Zones.on_battle_result(p, JOURNEY, 9, 9))


## The scene is data-checkable without rendering: every kit mesh it uses is a real kit part, it has lights, a floor, no MultiMesh
## (client/arena_props.gd hides those) and no new texture file.
func _check_scene(ctx, map) -> void:
	var scene := (load(map.art_scene) as PackedScene).instantiate() as Node3D
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var kit_used := {}
	for node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		ctx.check("%s: %s has a mesh" % [map.id, node.name], mesh != null)
		if mesh != null and mesh.resource_path.begins_with("res://art/props/mummy_tomb/meshes/"):
			kit_used[mesh.resource_path.get_file().get_basename()] = true
	ctx.check("%s: it uses only the 11 kit parts and at least 4 of them (%s)" % [map.id, kit_used.keys()], kit_used.keys().all(func(k): return KIT_PROPS.has(k)) and kit_used.size() >= 4)
	ctx.check("%s: it has a sand floor, warm firelight markers and no MultiMesh" % map.id, scene.find_child("SandFloor", true, false) != null and scene.find_children("light_fire*", "Node3D", true, false).size() >= 3 and scene.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
	ctx.check("%s: the scene file is small (%d bytes, no embedded textures)" % [map.id, FileAccess.get_file_as_bytes(map.art_scene).size()], FileAccess.get_file_as_bytes(map.art_scene).size() < 300000)
	scene.free()
