extends RefCounted
## Gear level cap of drops (Boss 2026-11-17; data/world/gear_levels.json; design/gdd/drops-and-rewards.md). Gear that drops
## is limited by what the PLAYER has unlocked on the world map, in every map: a piece whose required level (catalog
## req_level) is above the highest gear level of the profile's OPEN zones never drops. Level 1 is always allowed and is the
## same catalog piece with the instance id prefix LEVEL1_PREFIX (the wear gate and x1.0 main stat exempt "starter-*").
## Pure rules, no nodes. Computed on the authority from the profile it owns (a client never sends it).
## A missing or invalid zone value is LOW (level 1), never permissive.
## FORGERY: only fit() (the drop pipeline) stamps LEVEL1_PREFIX. Client commands and profile imports cannot create items
## (they only move pieces the profile already holds), and Item.from_dict keeps the saved id, so a stamped piece is always
## one the authority generated. `level1_forged()` is the server-side check for a profile loaded from outside.

const PATH := "res://data/world/gear_levels.json"
const LEVEL1_PREFIX := "starter-drop-"
const WorldZones := preload("res://logic/world_zones.gd")

static var _cache = null


static func data() -> Dictionary:
	if _cache == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


## The gear level a zone opens (1 when the zone has no valid entry).
static func zone_level(zone_id: String, d: Dictionary = {}) -> int:
	if d.is_empty():
		d = data()
	var zones = d.get("zones", {})
	var raw = zones.get(zone_id, 1) if zones is Dictionary else 1
	return int(raw) if (raw is int or raw is float) and raw >= 1 and raw == floorf(float(raw)) else 1


## The highest gear level among `open_zone_ids` (1 when none).
static func level_for_zones(open_zone_ids: Array, d: Dictionary = {}) -> int:
	var best := 1
	for id in open_zone_ids:
		best = maxi(best, zone_level(str(id), d))
	return best


## The unlocked gear level of `profile` (null profile: 1). `zones` / `d` let tests pass a fake zone table.
static func unlocked_level(profile, d: Dictionary = {}, zones: Array = []) -> int:
	if profile == null:
		return 1
	var open: Array = []
	for z in (zones if not zones.is_empty() else WorldZones.zones()):
		if WorldZones.state(profile, str(z.get("id", ""))) == WorldZones.OPEN:
			open.append(str(z.get("id", "")))
	return level_for_zones(open, d)


## The catalog piece with the same slot / weapon type / class / race as `item_id` whose required level is `level` ("" none).
static func sibling(rules, item_id: String, level: int) -> String:
	var base: Dictionary = rules.catalog.entry(item_id)
	var ids: Array = rules.catalog.items.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = rules.catalog.items[id]
		if not e["no_drop"] and rules.catalog.req_level(id) == level and e["slot"] == base.get("slot", "") and e["weapon_type"] == base.get("weapon_type", "") \
				and e["class"] == base.get("class", "") and e["race"] == base.get("race", ""):
			return str(id)
	return ""


## The levels a drop like `item` can have under `cap`: level 1 plus every level (<= cap) the catalog has a sibling for.
static func allowed_levels(rules, item, cap: int) -> Array:
	var out: Array = [1]
	var levels := {}
	for id in rules.catalog.items:
		levels[rules.catalog.req_level(id)] = true
	var sorted: Array = levels.keys()
	sorted.sort()
	for level in sorted:
		if level > 1 and level <= cap and not sibling(rules, item.item_id, level).is_empty():
			out.append(level)
	return out


## `item` made to respect `cap` (the unlocked gear level): picked among the allowed levels (weights from the data, default
## equal). Level 1 = the same catalog id, instance id LEVEL1_PREFIX + id. Another level = the sibling piece of that level
## (stats rolled like a race piece). Own seeded generator, so the loot stream does not change. An item with no catalog
## entry, or one that needs level 1 already, is returned as is.
static func fit(rules, item, cap: int):
	if item == null or str(item.item_id).is_empty() or str(item.id).begins_with("starter-") or rules.catalog.entry(item.item_id).is_empty():
		return item
	var own: int = rules.catalog.req_level(item.item_id)
	if own <= 1:
		return item
	var levels := allowed_levels(rules, item, cap)
	var weights = data().get("level_weights", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["gear_level", item.id])
	var total := 0.0
	for level in levels:
		total += _weight(weights, level)
	var pick: int = levels[0]
	if total > 0.0:
		var roll := rng.randf() * total
		for level in levels:
			roll -= _weight(weights, level)
			if roll < 0.0:
				pick = level
				break
	if pick == 1:
		item.id = LEVEL1_PREFIX + str(item.id)
		return item
	if pick == own:
		return item
	var piece = preload("res://logic/item_system.gd").create_item(rules, item.id, item.slot, item.tier, rng, "", sibling(rules, item.item_id, pick))
	return piece if piece != null else item


static func _weight(weights, level: int) -> float:
	return maxf(0.0, float(weights.get(str(level), 1.0))) if weights is Dictionary else 1.0


## True for a LEVEL1_PREFIX piece that cannot be a real drop: a catalog id the drop pipeline never turns into level 1 (a
## boss piece or an unknown id). Server-side sanity check for an imported profile; real drops are never flagged.
static func level1_forged(item, rules) -> bool:
	if not str(item.id).begins_with(LEVEL1_PREFIX):
		return false
	var e: Dictionary = rules.catalog.entry(item.item_id)
	return e.is_empty() or bool(e.get("no_drop", false))


## Profile load repair (called from Profile.from_dict before the gear purge): every stash / vault / worn piece for which
## level1_forged() is true loses the prefix (so the level gate and x1.0 rule no longer exempt it) and is logged. Deterministic
## and idempotent. Returns the number repaired. RESIDUAL RISK: a level-15 piece that carries the prefix but is a normal
## droppable catalog id cannot be told from a real level-1 drop by id alone. Online the profile lives on the server (a client
## cannot edit it); an offline save is the player's own.
static func repair_forged(p, rules) -> int:
	var lists: Array = [p.stash.items, p.vault.items] + p.worn_lists()
	var fixed := 0
	for list in lists:
		for item in list:
			if level1_forged(item, rules):
				item.id = str(item.id).trim_prefix(LEVEL1_PREFIX)
				if item.id.is_empty():
					item.id = "repaired-%d" % fixed
				fixed += 1
	if fixed > 0:
		print("gear_levels: repaired %d forged starter-drop- pieces" % fixed)
	return fixed


## Data check (tests): every zone has a valid gear level and the levels ascend with the zone order.
static func problems() -> Array:
	var out: Array = []
	var last := 0
	var zones = data().get("zones", {})
	for z in WorldZones.zones():
		var id := str(z.get("id", ""))
		if not (zones is Dictionary and zones.has(id)):
			if not (str(z.get("journey", "")).is_empty() and str(z.get("dev_journey", "")).is_empty()):
				out.append("%s has a journey but no gear level" % id)  # a zone with no journey yet may wait (counts as level 1, never opens)
			continue
		var level := zone_level(id)
		if level < last:
			out.append("%s gear level %d goes below the zone before it" % [id, level])
		last = maxi(last, level)
	return out
