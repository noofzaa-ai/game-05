extends RefCounted
## Zone unlock quests (Boss 2026-11-17; data/world/zone_quests.json). A zone with a quest opens only when every
## step is met. Pure rules over the profile (`unlocks` boss flags, `card_deck` card levels): no nodes, no client.
## The unlock is derived, never stored, so there is nothing to migrate. Used by logic/world_zones.gd state().

const PATH := "res://data/world/zone_quests.json"
const CardProgress := preload("res://logic/card_progress.gd")
const STEP_TYPES := ["boss_beaten", "card_level"]

static var _cache = null


static func data() -> Dictionary:
	if _cache == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func quest(zone_id: String) -> Dictionary:
	var q = data().get("quests", {}).get(zone_id, {})
	return q if q is Dictionary else {}


static func has_quest(zone_id: String) -> bool:
	return not quest(zone_id).is_empty()


static func _best_levels(profile) -> Array:
	var out: Array = []
	if profile == null or not "card_deck" in profile or not profile.card_deck is Dictionary:
		return out
	for class_id in profile.card_deck.get("cards", {}):
		out.append(CardProgress.level_of(profile.card_deck, str(class_id)))
	out.sort()
	out.reverse()
	return out


static func _fill(text: String, cur: int, target: int) -> String:
	return text.replace("{cur}", str(cur)).replace("{target}", str(target))


## The quest's steps for this profile: [{type, current, target, done, text_th, text_en}]. [] when the zone has
## no quest. card_level with count 1 shows the best card's level (capped at the target); count N shows how many
## cards reach `min` (capped at N).
static func progress(profile, zone_id: String) -> Array:
	var out: Array = []
	for s in Array(quest(zone_id).get("steps", [])):
		var type := str(s.get("type", ""))
		var cur := 0
		var target := 1
		if type == "boss_beaten":
			var flag := "boss_" + str(s.get("zone", ""))
			cur = 1 if profile != null and "unlocks" in profile and profile.unlocks is Dictionary and bool(profile.unlocks.get(flag, false)) else 0
		elif type == "card_level":
			var minimum := int(s.get("min", 1))
			var count := maxi(int(s.get("count", 1)), 1)
			var levels := _best_levels(profile)
			if count == 1:
				target = minimum
				cur = mini(int(levels[0]) if not levels.is_empty() else 0, minimum)
			else:
				target = count
				var reached := 0
				for l in levels:
					if int(l) >= minimum:
						reached += 1
				cur = mini(reached, count)
		else:
			target = 1  # unknown type: never met (fail closed)
		out.append({"type": type, "current": cur, "target": target, "done": type in STEP_TYPES and cur >= target,
			"text_th": _fill(str(s.get("text_th", "")), cur, target), "text_en": _fill(str(s.get("text_en", "")), cur, target)})
	return out


## True when the zone has no quest, or every step is done.
static func met(profile, zone_id: String) -> bool:
	for step in progress(profile, zone_id):
		if not step["done"]:
			return false
	return true


## Data check (tests): zones exist, steps are known types with sane numbers and both-language texts.
static func problems(zone_ids: Array) -> Array:
	var out: Array = []
	var quests = data().get("quests", {})
	if not quests is Dictionary or quests.is_empty():
		return ["no quests"]
	for zone_id in quests:
		var q: Dictionary = quests[zone_id]
		if not zone_ids.has(zone_id):
			out.append("%s is not a zone" % zone_id)
		for key in ["id", "name_th", "name_en", "desc_th", "desc_en"]:
			if str(q.get(key, "")).is_empty():
				out.append("%s missing %s" % [zone_id, key])
		var steps: Array = q.get("steps", [])
		if steps.is_empty():
			out.append("%s has no steps" % zone_id)
		for s in steps:
			var type := str(s.get("type", ""))
			if not type in STEP_TYPES:
				out.append("%s bad step type %s" % [zone_id, type])
			if str(s.get("text_th", "")).is_empty() or str(s.get("text_en", "")).is_empty():
				out.append("%s step %s missing text" % [zone_id, type])
			if type == "boss_beaten" and not zone_ids.has(str(s.get("zone", ""))):
				out.append("%s boss_beaten of unknown zone" % zone_id)
			if type == "card_level" and (int(s.get("min", 0)) < 1 or int(s.get("min", 0)) > CardProgress.max_level() or int(s.get("count", 1)) < 1):
				out.append("%s card_level out of range" % zone_id)
	return out
