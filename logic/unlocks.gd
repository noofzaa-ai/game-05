extends RefCounted
## Content gates of the new-player tutorial (design/gdd/tutorial.md 2): Magic and Runeborn stay locked until the
## first goblin_waves run that clears wave 12. Pure rules: reads data/tutorial/unlocks.json and the profile's
## `unlocks` dictionary; the server alone sets the flag (on_battle_result). No nodes, no client code.

const PATH := "res://data/tutorial/unlocks.json"
const DEFAULT_FLAG := "magic_runeborn"

static var _cache = null


static func config() -> Dictionary:
	if _cache == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func flag() -> String:
	return str(config().get("flag", DEFAULT_FLAG))


static func locked_classes() -> Array:
	return Array(config().get("locked", {}).get("classes", []))


static func locked_races() -> Array:
	return Array(config().get("locked", {}).get("races", []))


static func unlock_journey() -> String:
	return str(config().get("unlock_on", {}).get("journey", ""))


static func unlock_wave() -> int:
	return int(config().get("unlock_on", {}).get("wave", 12))


## `profile` is a Profile (or anything with an `unlocks` Dictionary).
static func unlocked(profile) -> bool:
	return profile != null and "unlocks" in profile and profile.unlocks is Dictionary and bool(profile.unlocks.get(flag(), false))


static func is_class_unlocked(profile, class_id: String) -> bool:
	return not locked_classes().has(class_id) or unlocked(profile)


static func is_race_unlocked(profile, race: String) -> bool:
	return not locked_races().has(race) or unlocked(profile)


## Server battle-result hook: sets the flag the first time a run of the unlock journey clears the unlock wave.
## Returns true when this call unlocked it (false when already unlocked or the result does not qualify).
static func on_battle_result(profile, journey_id: String, cleared_wave: int) -> bool:
	if profile == null or unlocked(profile) or journey_id != unlock_journey() or cleared_wave < unlock_wave():
		return false
	profile.unlocks[flag()] = true
	return true
