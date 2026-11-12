extends RefCounted
## A single process schedules bounded independent rooms with fixed server-owned dt.
const Room := preload("res://server/rooms/room.gd")
const STEP := 1.0 / 60.0
const MAX_ROOMS := 8
const MAX_CATCHUP := 5
const MAX_BACKLOG := 0.25
const EMPTY_TTL := 30.0
const FINISHED_TTL := 60.0
const ROUTE_TTL := 300.0
var rooms := {}
var closed: Array = []
var tick_samples: Array[int] = []
var tick_count := 0
var tick_max_usec := 0
var rules = preload("res://logic/item_rules_loader.gd").load_default()
var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
var cosmetics = preload("res://logic/cosmetic_options.gd").load_default()
var combat = preload("res://logic/combat_data_loader.gd").load_default()
var loot = preload("res://logic/loot_data_loader.gd").load_default(camp.materials.keys(), rules.tiers.size())
var journey_data = preload("res://logic/journey_data.gd").load_by_id("ink_road", combat.enemies.keys())

func ready() -> bool:
	return rules.errors.is_empty() and camp.errors.is_empty() and combat.is_valid() and loot.is_valid() and journey_data.errors.is_empty()

func create(id: String, seed_value: int, profiles: Array, lobby: bool = false, capacity: int = 4, farm_map: String = "") -> Dictionary:
	if not ready(): return failure("not_configured")
	if not lobby:
		for entry in profiles:
			if not entry is Dictionary or not entry.get("profile") is Dictionary: return failure("invalid_payload")
			if preload("res://logic/profile.gd").from_dict(entry.profile,rules,camp) == null: return failure("invalid_payload")
	if RegEx.create_from_string("^[a-z0-9-]{8,64}$").search(id) == null: return failure("invalid_payload")
	if rooms.has(id): return failure("room_exists")
	if rooms.size() >= MAX_ROOMS: return failure("worker_full")
	var content = journey_data
	var fixed_maps: Array = []
	if farm_map == "mummy_ascent":
		if profiles.size() != 1 or capacity != 1 or lobby: return failure("invalid_map")
		fixed_maps = ["mummy_arena_a", "mummy_arena_b", "mummy_arena_c"]
		content = preload("res://logic/journey_data.gd").new()
		content.id = "mummy_ascent"; content.display_name = "Pyramid · Private Solo"
		content.stage_count = 3; content.choice_count = 1
		content.first_camp_stages.assign([2]); content.last_camp_stage = 2
		content.combat_maps.assign(["mummy_arena_a"]); content.boss_map = "mummy_arena_c"
		for map_id in fixed_maps:
			var map = preload("res://logic/map_loader.gd").load_by_id(map_id)
			if not map.is_valid(): return failure("invalid_map")
			var enemies: Array = []
			for spawn in map.enemy_spawns:
				if not combat.enemies.has(spawn.type): return failure("invalid_map")
				enemies.append({"type": spawn.type, "level": spawn.level, "count": 1})
			content.stages.append({"level":1,"power":1.0,"enemies":enemies,"challenge":{}})
	elif not farm_map.is_empty():
		var map = preload("res://logic/map_loader.gd").load_by_id(farm_map)
		if profiles.size() != 1 or lobby or not map.is_valid() or not map.modes.has("pve"): return failure("invalid_map")
		content = preload("res://logic/journey_data.gd").new()
		content.id = "farm_" + farm_map; content.display_name = map.display_name
		content.stage_count = 1; content.choice_count = 1
		content.first_camp_stages.assign([2]); content.last_camp_stage = 2
		content.boss_map = farm_map; content.combat_maps.assign([farm_map])
		var enemies: Array = []
		for spawn in map.enemy_spawns:
			if not combat.enemies.has(spawn.type): return failure("invalid_map")
			enemies.append({"type": spawn.type, "level": spawn.level, "count": 1})
		content.stages.assign([{"level": 1, "power": 1.0, "enemies": enemies, "challenge": {}}])
	var room = Room.create(profiles, seed_value, {"rules": rules, "camp": camp, "combat": combat, "loot": loot, "journey": content, "cosmetics": cosmetics, "fixed_maps": fixed_maps})
	if room == null or (lobby and not room.enter_lobby(capacity)): return failure("invalid_state")
	rooms[id] = {"room": room, "backlog": 0.0, "empty_age": 0.0, "inactive_age": 0.0, "loading_age": 0.0}
	return {"v": 1, "ok": true, "room": id, "state": room.summary()}

func advance(elapsed: float) -> void:
	if not is_finite(elapsed) or elapsed < 0: return
	for id in rooms.keys():
		var entry: Dictionary = rooms[id]
		var room = entry.room
		entry.loading_age = entry.loading_age + elapsed if room.scene_loading() else 0.0
		if entry.loading_age >= 120.0:
			close(id, "scene_load_timeout")
			continue
		entry.empty_age = 0.0 if room.has_connected_humans() else entry.empty_age + elapsed
		if entry.empty_age >= EMPTY_TTL:
			close(id, "empty_timeout")
			continue
		if room.status == "finished":
			entry.inactive_age += elapsed
			if entry.inactive_age >= FINISHED_TTL: close(id, "inactive_timeout")
			continue
		entry.inactive_age = entry.inactive_age + elapsed if room.status in ["route", "camp", "treasure", "lobby"] else 0.0
		if entry.inactive_age >= ROUTE_TTL:
			close(id, "route_timeout")
			continue
		if entry.get("external_tick",false):continue
		entry.backlog += elapsed
		if entry.backlog > MAX_BACKLOG + 0.000000001:
			close(id, "overload")
			continue
		var steps := 0
		while entry.backlog + 0.000000001 >= STEP and steps < MAX_CATCHUP:
			var tick_start := Time.get_ticks_usec()
			room.tick()
			var duration := Time.get_ticks_usec() - tick_start
			tick_count += 1; tick_max_usec = maxi(tick_max_usec, duration)
			tick_samples.append(duration)
			if tick_samples.size() > 4096: tick_samples.pop_front()
			entry.backlog = maxf(0, entry.backlog - STEP)
			steps += 1
			if room.status == "finished": break

func close(id: String, reason: String = "closed") -> Dictionary:
	if not rooms.has(id): return failure("room_not_found")
	rooms[id].room.error = reason
	rooms.erase(id)
	closed.append({"room": id, "reason": reason})
	if closed.size() > 32: closed = closed.slice(-32)
	return {"v": 1, "ok": true}

func status(id: String) -> Dictionary:
	if not rooms.has(id): return failure("room_not_found")
	return {"v": 1, "ok": true, "room": id, "state": rooms[id].room.summary()}

func control(request: Variant) -> Dictionary:
	if not request is Dictionary or not request.has_all(["v", "op", "room"]) or not (request.v is int or request.v is float) or request.v != 1 or not request.op is String or not request.room is String:
		return failure("invalid_payload")
	match request.op:
		"create":
			if request.size() != 5 or not request.get("players") is Array or not request.get("seed") is String or RegEx.create_from_string("^[a-f0-9]{15}$").search(request.seed) == null: return failure("invalid_payload")
			return create(request.room, request.seed.hex_to_int(), request.players)
		"status":
			if request.size() != 3: return failure("invalid_payload")
			return status(request.room)
		"close":
			if request.size() != 3: return failure("invalid_payload")
			return close(request.room)
	return failure("invalid_payload")

static func failure(reason: String) -> Dictionary:
	return {"v": 1, "ok": false, "error": reason}

func metrics() -> Dictionary:
	var sorted := tick_samples.duplicate(); sorted.sort()
	var players := 0
	var backlog := 0.0
	for entry in rooms.values():
		players += entry.room.human_ids().filter(func(id): return entry.room.connected[id]).size()
		backlog = maxf(backlog, entry.backlog)
	return {"v": 1, "ok": true, "rooms": rooms.size(), "players": players, "ticks": tick_count, "tick_p95_ms": sorted[int((sorted.size()-1)*0.95)] / 1000.0 if not sorted.is_empty() else 0.0, "tick_max_ms": tick_max_usec / 1000.0, "backlog_ms": backlog * 1000.0, "closed": closed.duplicate(true), "memory_bytes": OS.get_static_memory_usage(), "uptime_seconds": Time.get_ticks_msec() / 1000.0}
