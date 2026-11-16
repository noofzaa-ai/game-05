extends RefCounted
## World map zones (Boss 2026-11-16: a boss-farming game). data/world/zones.json lists the zones in unlock order;
## zone N+1 opens once zone N's boss has been beaten one time. A zone without a journey is shown but not playable
## ("coming soon"). Pure rules: reads the data file and the profile's `unlocks` {key: bool}; only the server sets
## a boss flag (on_battle_result, from the run's end on the authority). No nodes, no client code.

const PATH := "res://data/world/zones.json"
const OPEN := "open"
const LOCKED := "locked"
const SOON := "coming_soon"

static var _cache = null


static func data() -> Dictionary:
	if _cache == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


## Zones sorted by `order`.
static func zones() -> Array:
	var list: Array = Array(data().get("zones", [])).duplicate()
	list.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return list


static func zone(id: String) -> Dictionary:
	for z in zones():
		if str(z.get("id", "")) == id:
			return z
	return {}


static func zone_of_journey(journey_id: String) -> Dictionary:
	if journey_id.is_empty():
		return {}
	for z in zones():
		if str(z.get("journey", "")) == journey_id:
			return z
	return {}


static func boss_key(zone_id: String) -> String:
	return "boss_" + zone_id


static func boss_beaten(profile, zone_id: String) -> bool:
	return profile != null and "unlocks" in profile and profile.unlocks is Dictionary and bool(profile.unlocks.get(boss_key(zone_id), false))


## OPEN (playable), LOCKED (the zone before it is not beaten yet) or SOON (no journey yet). The first zone is
## always open.
static func state(profile, zone_id: String) -> String:
	var list := zones()
	for i in list.size():
		if str(list[i].get("id", "")) != zone_id:
			continue
		if str(list[i].get("journey", "")).is_empty():
			return SOON
		if i == 0 or boss_beaten(profile, str(list[i - 1].get("id", ""))):
			return OPEN
		return LOCKED
	return LOCKED


## The furthest open zone (where the player is headed): the default pick on the map.
static func current_zone(profile) -> Dictionary:
	var best := {}
	for z in zones():
		if state(profile, str(z.get("id", ""))) == OPEN:
			best = z
	return best


## Server run-end hook: the first time a run of a zone's journey clears its last wave (the boss), mark the boss
## beaten. Returns true when this call set it.
static func on_battle_result(profile, journey_id: String, cleared_wave: int, wave_total: int) -> bool:
	var z := zone_of_journey(journey_id)
	if profile == null or z.is_empty() or wave_total <= 0 or cleared_wave < wave_total:
		return false
	var key := boss_key(str(z.get("id", "")))
	if bool(profile.unlocks.get(key, false)):
		return false
	profile.unlocks[key] = true
	return true


## Data check (tests): every zone has an id, names, a boss name and a position inside the image; ids and orders
## are unique; a journey, when set, is a real file.
static func problems() -> Array:
	var out: Array = []
	var ids := {}
	var orders := {}
	for z in Array(data().get("zones", [])):
		var id := str(z.get("id", ""))
		if id.is_empty() or ids.has(id):
			out.append("bad or repeated id %s" % id)
		ids[id] = true
		if orders.has(int(z.get("order", 0))):
			out.append("repeated order %s" % z.get("order"))
		orders[int(z.get("order", 0))] = true
		for key in ["name_th", "name_en", "boss_th", "boss_en"]:
			if str(z.get(key, "")).is_empty():
				out.append("%s missing %s" % [id, key])
		var pos: Array = z.get("pos", [])
		if pos.size() != 2 or float(pos[0]) < 0.0 or float(pos[0]) > 1.0 or float(pos[1]) < 0.0 or float(pos[1]) > 1.0:
			out.append("%s pos outside the image" % id)
		var journey := str(z.get("journey", ""))
		if not journey.is_empty() and not FileAccess.file_exists("res://data/journeys/%s.json" % journey):
			out.append("%s journey file missing" % id)
	return out
