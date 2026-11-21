extends RefCounted
## Boss loot (design/gdd/boss-loot.md, Boss 2026-11-16): boss accessory sets, Relics and Boss Coins. Pure rules.
## Data: data/loot/boss_loot.json (per zone boss: coin, relic, set, chances, shop price), data/items/sets.json kind
## "boss" (steps), data/items/catalog.json (the set pieces, no_drop; "relics" with their effects), data/camp/camp.json
## (the coin and the relic are stack materials, sellable false).
## - Set: count a boss set's pieces worn on one card (earring/bracelet/ring twice: 8 at most). Steps at 2/4/6 pieces add
##   stat_mod effects; a step's numbers x tier_mul of the LOWEST tier among the N best pieces it counts (as race sets).
## - Relic: one socket on a boss set piece or a legendary item. Its effects count while the item is worn, not destroyed and
##   not broken down (durability 0). Socket/unsocket are free; unsocketing returns the relic intact to the stash.
## - Drops: on a WON run of a zone's journey, each account (Journey.boss_loot_targets) gets coins_per_kill coins (never
##   scaled), a piece_chance x factor chance of a random set piece (tier from loot.json tier_weights at the boss level),
##   a relic_chance x factor chance of the relic. The first kill (unlocks.boss_<zone> not yet set) guarantees a piece of
##   first_kill_min_tier or better. Drops go straight into the stash (the coin / relic counters never fill up; a piece
##   overflows the stash capacity like Run.death so nothing earned is lost).
## Stats: Stats.totals calls apply_stats() after gear and the generic set bonuses: (stat + adds) x (1 + muls).

const ItemSystem := preload("res://logic/item_system.gd")
const PATH := "res://data/loot/boss_loot.json"

static var _cached: Dictionary = {}


static func data() -> Dictionary:
	if _cached.is_empty():
		var text := FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		_cached = parsed if parsed is Dictionary else {"bosses": {}}
	return _cached


## The boss entry of zone `zone_id` ({} when that zone has no boss loot).
static func boss(zone_id: String) -> Dictionary:
	return data().get("bosses", {}).get(zone_id, {})


## [zone_id, entry] of the boss whose zone plays `journey_id` (["", {}] when none).
static func boss_for_journey(journey_id: String) -> Array:
	var zone: Dictionary = preload("res://logic/world_zones.gd").zone_of_journey(journey_id)
	var zone_id := str(zone.get("id", ""))
	var entry := boss(zone_id)
	return [zone_id, entry] if not entry.is_empty() else ["", {}]


## The catalog ids of a boss set's pieces, sorted (a seed always picks the same one).
static func set_pieces(rules, set_id: String) -> Array:
	var ids: Array = []
	for item_id in rules.catalog.items:
		if str(rules.catalog.items[item_id].get("set", "")) == set_id:
			ids.append(str(item_id))
	ids.sort()
	return ids


static func is_boss_piece(rules, item) -> bool:
	return item != null and not str(rules.catalog.entry(item.item_id).get("boss", "")).is_empty()


## True when `item` has a Relic socket (v1: boss set pieces and legendary items, one socket each).
static func has_socket(rules, item) -> bool:
	return item != null and not item.destroyed and (is_boss_piece(rules, item) or int(item.tier) >= rules.tiers.size() - 1)


static func is_relic(rules, relic_id: String) -> bool:
	return rules.catalog.relics.has(relic_id)


# --- set + relic stats -------------------------------------------------------------------------------------------

## Every boss set the worn `items` touch: [{"set_id", "name", "count", "total", "steps": [{"pieces", "name", "text",
## "active", "tier", "m", "effects" (scaled)}]}], sorted by set id. For the UI and apply_stats.
static func set_status(rules, items: Array) -> Array:
	var by_set := {}
	for item in items:
		if item == null or item.destroyed:
			continue
		var set_id := str(rules.catalog.entry(item.item_id).get("set", ""))
		if str(rules.catalog.sets.get(set_id, {}).get("kind", "")) != "boss":
			continue
		if not by_set.has(set_id):
			by_set[set_id] = []
		by_set[set_id].append(int(item.tier))
	var out: Array = []
	var ids: Array = by_set.keys()
	ids.sort()
	for set_id in ids:
		var info: Dictionary = rules.catalog.sets[set_id]
		var tiers: Array = by_set[set_id]
		tiers.sort()
		tiers.reverse()  # best first
		var steps: Array = []
		var most := 0
		for step in info.get("steps", []):
			var pieces := int(step.get("pieces", 0))
			most = maxi(most, pieces)
			var active := pieces > 0 and tiers.size() >= pieces
			var tier: int = int(tiers[mini(pieces, tiers.size()) - 1]) if not tiers.is_empty() and pieces > 0 else 0
			var tier_id := str(rules.tiers[clampi(tier, 0, rules.tiers.size() - 1)]["id"])
			var m := float(info.get("tier_mul", {}).get(tier_id, 1.0))
			steps.append({"pieces": pieces, "name": str(step.get("name", "")), "text": str(step.get("text", "")), "active": active,
				"tier": tier_id, "m": m, "effects": (step.get("effects", []) as Array).map(func(e): return scale_effect(e, m))})
		out.append({"set_id": set_id, "name": str(info.get("name", set_id)), "count": tiers.size(), "total": most, "steps": steps})
	return out


## A stat_mod with its numbers x m (the bonus part only: add x m, mul x m).
static func scale_effect(effect: Dictionary, m: float) -> Dictionary:
	var out: Dictionary = effect.duplicate(true)
	for key in ["add", "mul"]:
		if out.has(key):
			out[key] = float(out[key]) * m
	return out


## The Relic effects of the worn `items` (socketed, not destroyed, not broken down), in item order.
static func relic_effects(rules, items: Array) -> Array:
	var out: Array = []
	for item in items:
		if item == null or item.relic.is_empty() or item.destroyed or item.is_broken_down():
			continue
		out.append_array(rules.catalog.relics.get(item.relic, {}).get("effects", []))
	return out


## Every boss stat_mod that counts for the worn `items`: active set steps, then relics.
static func stat_effects(rules, items: Array) -> Array:
	var out: Array = []
	for entry in set_status(rules, items):
		for step in entry["steps"]:
			if step["active"]:
				out.append_array(step["effects"])
	out.append_array(relic_effects(rules, items))
	return out


## Adds the boss stat_mods to `totals` (stat -> value) in place: value = (value + adds) x (1 + muls).
static func apply_stats(rules, items: Array, totals: Dictionary) -> void:
	var adds := {}
	var muls := {}
	for effect in stat_effects(rules, items):
		if str(effect.get("type", "")) != "stat_mod":
			continue
		var stat := str(effect.get("stat", ""))
		if not totals.has(stat):
			continue
		adds[stat] = float(adds.get(stat, 0.0)) + float(effect.get("add", 0.0))
		muls[stat] = float(muls.get(stat, 0.0)) + float(effect.get("mul", 0.0))
	for stat in adds:
		totals[stat] = (float(totals[stat]) + float(adds[stat])) * (1.0 + float(muls[stat]))


# --- sockets -----------------------------------------------------------------------------------------------------

## relic_socket: puts one `relic_id` from the stash into `item` (stash or worn). Free.
static func socket(profile, rules, item, relic_id: String) -> Dictionary:
	if not is_relic(rules, relic_id):
		return {"ok": false, "reason": "invalid_relic"}
	if not has_socket(rules, item):
		return {"ok": false, "reason": "no_socket"}
	if not item.relic.is_empty():
		return {"ok": false, "reason": "socket_full"}
	if profile.stash.material_count(relic_id) < 1:
		return {"ok": false, "reason": "no_relic"}
	profile.stash.remove_material(relic_id, 1)
	item.relic = relic_id
	return {"ok": true, "item": item.id, "relic": relic_id}


## relic_unsocket: the item's relic goes back to the stash intact. Free.
static func unsocket(profile, item) -> Dictionary:
	if item == null or item.relic.is_empty():
		return {"ok": false, "reason": "socket_empty"}
	var relic_id: String = item.relic
	if profile.stash.add_material(relic_id, 1) != 1:
		return {"ok": false, "reason": "stash_full"}
	item.relic = ""
	return {"ok": true, "item": item.id, "relic": relic_id}


## Before an item leaves the game (sold, discarded): "" when its relic (if any) can return to the stash, else a reason.
static func release_problem(profile, item) -> String:
	if item == null or item.relic.is_empty():
		return ""
	return "" if profile.stash.room_for(item.relic) >= 1 else "stash_full"


## Returns the relic of `item` (if any) to the stash. Call after release_problem() said "".
static func release(profile, item) -> void:
	if item != null and not item.relic.is_empty():
		profile.stash.add_material(item.relic, 1)
		item.relic = ""


# --- drops -------------------------------------------------------------------------------------------------------

## The level of the boss in `journey_data` (the last stage's enemy with boss: true), else the last stage's level.
static func boss_level(journey_data) -> int:
	if journey_data == null or journey_data.stages.is_empty():
		return 1
	var stage: Dictionary = journey_data.stages[-1]
	for enemy in stage.get("enemies", []):
		if bool(enemy.get("boss", false)):
			return int(enemy.get("level", stage.get("level", 1)))
	return int(stage.get("level", 1))


## One account's boss kill rewards (call only for a WON run). `first_kill`: the account had not beaten this boss yet.
## `factor`: that player's loot_by_squad factor (scales the piece and relic chances, never the coin). The draws are
## always the same four (piece roll, piece pick, tier roll, relic roll), so a seed repeats at any factor.
## Returns {"zone", "coin", "coins", "items": [Item], "relics": {id: n}, "first_kill"} ({} when the journey has no boss loot).
static func grant(profile, rules, loot, journey_data, first_kill: bool, factor: float, rng: RandomNumberGenerator, id_prefix: String = "boss") -> Dictionary:
	var found := boss_for_journey(str(journey_data.id) if journey_data != null else "")
	var entry: Dictionary = found[1]
	if entry.is_empty() or profile == null:
		return {}
	var summary := {"zone": found[0], "coin": str(entry.get("coin", "")), "coins": 0, "items": [], "relics": {}, "first_kill": first_kill}
	var coins := maxi(0, int(entry.get("coins_per_kill", 1)))
	if not summary["coin"].is_empty() and coins > 0:
		summary["coins"] = profile.stash.add_material(summary["coin"], coins)
	var pieces := set_pieces(rules, str(entry.get("set", "")))
	var piece_roll := rng.randf()
	var pick := rng.randi()
	var weights: Array = loot.weights_for_level(boss_level(journey_data)) if loot != null else []
	var tier := _roll_tier(weights, rng)
	var relic_roll := rng.randf()
	if not pieces.is_empty() and (first_kill or piece_roll < float(entry.get("piece_chance", 0.0)) * factor):
		if first_kill:
			tier = maxi(tier, _tier_index(rules, str(entry.get("first_kill_min_tier", "normal"))))
		var item_id: String = pieces[pick % pieces.size()]
		var slot := str(rules.catalog.entry(item_id)["slot"])
		var piece = ItemSystem.create_item(rules, _free_id(profile, "%s-%d" % [id_prefix, rng.seed]), slot, clampi(tier, 0, rules.tiers.size() - 1), rng, "", item_id)
		if piece != null:
			profile.stash.items.append(piece)
			profile.stash.capacity = maxi(profile.stash.capacity, profile.stash.slots_used())  # earned loot is never lost (as Run.death)
			summary["items"].append(piece)
	var relic := str(entry.get("relic", ""))
	if not relic.is_empty() and relic_roll < float(entry.get("relic_chance", 0.0)) * factor:
		if profile.stash.add_material(relic, 1) == 1:
			summary["relics"][relic] = 1
	_grant_weapons(profile, rules, entry, weights, factor, rng, id_prefix, summary)
	return summary


## Boss-unique weapons (Boss 2026-11-21; data weapon_drops [{item, chance}]): OFF until the Boss approves them, i.e. only
## when the entry also says "weapon_drops_enabled": true. Each listed weapon is an independent chance x factor roll (two
## draws each: the roll and its tier, rolled like a set piece; no first-kill guarantee). The draws come AFTER the four
## fixed ones above, so turning this on never changes the set piece / relic results of a seed.
static func _grant_weapons(profile, rules, entry: Dictionary, weights: Array, factor: float, rng: RandomNumberGenerator, id_prefix: String, summary: Dictionary) -> void:
	if not bool(entry.get("weapon_drops_enabled", false)):
		return
	for drop in Array(entry.get("weapon_drops", [])):
		if not drop is Dictionary:
			continue
		var item_id := str(drop.get("item", ""))
		var roll := rng.randf()
		var tier := _roll_tier(weights, rng)
		if item_id.is_empty() or rules.catalog.entry(item_id).is_empty() or roll >= float(drop.get("chance", 0.0)) * factor:
			continue
		var slot := str(rules.catalog.entry(item_id)["slot"])
		var weapon = ItemSystem.create_item(rules, _free_id(profile, "%s-%d-%s" % [id_prefix, rng.seed, item_id]), slot, clampi(tier, 0, rules.tiers.size() - 1), rng, "", item_id)
		if weapon != null:
			profile.stash.items.append(weapon)
			profile.stash.capacity = maxi(profile.stash.capacity, profile.stash.slots_used())
			summary["items"].append(weapon)


static func _tier_index(rules, tier_id: String) -> int:
	for i in rules.tiers.size():
		if str(rules.tiers[i]["id"]) == tier_id:
			return i
	return 0


static func _roll_tier(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight in weights:
		total += float(weight)
	var roll := rng.randf() * total
	for tier in weights.size():
		roll -= float(weights[tier])
		if roll < 0.0:
			return tier
	return maxi(0, weights.size() - 1)


## An item id no item of `profile` uses yet.
static func _free_id(profile, base: String) -> String:
	var used := {}
	var lists: Array = [profile.stash.items, profile.vault.items]
	lists.append_array(profile.worn_lists())
	for list in lists:
		for item in list:
			used[item.id] = true
	var id := base
	var n := 1
	while used.has(id):
		id = "%s-%d" % [base, n]
		n += 1
	return id


## Summary as plain data (items as dicts) for saving / the wire.
static func summary_to_dict(summary: Dictionary) -> Dictionary:
	var out := summary.duplicate(true)
	if out.has("items"):
		out["items"] = summary["items"].map(func(item): return item.to_dict())
	return out


static func summary_from_dict(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["coins"] = int(out.get("coins", 0))
	var relics := {}
	for id in out.get("relics", {}):
		relics[str(id)] = int(out["relics"][id])
	out["relics"] = relics
	out["items"] = (out.get("items", []) as Array).map(func(raw): return load("res://logic/item.gd").from_dict(raw))
	return out


# --- shop --------------------------------------------------------------------------------------------------------

## The tier a bought piece of boss `zone_id` rolls (Boss 2026-11-16): one rng draw over that boss's shop_tier_weights
## (normal has weight 0: shop pieces are only rare / epic / legendary).
## Returns -1 when the boss has no usable table.
static func shop_tier(rules, zone_id: String, rng: RandomNumberGenerator) -> int:
	var weights: Array = boss(zone_id).get("shop_tier_weights", [])
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, float(weight))
	if total <= 0.0:
		return -1
	return mini(_roll_tier(weights, rng), rules.tiers.size() - 1)


## Shop offers for every boss set piece: {"sku": "boss:<item_id>", "id", "kind": "item", "name", "slot", "price",
## "currency": coin material id, "boss": zone id, "random_tier": true}. Relics are never offered.
static func shop_offers(rules) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bosses: Dictionary = data().get("bosses", {})
	var zones: Array = bosses.keys()
	zones.sort()
	for zone_id in zones:
		var entry: Dictionary = bosses[zone_id]
		var price := int(entry.get("price_coins", 0))
		if price < 1 or str(entry.get("coin", "")).is_empty():
			continue
		for item_id in set_pieces(rules, str(entry.get("set", ""))):
			var item: Dictionary = rules.catalog.entry(item_id)
			out.append({"sku": "boss:" + item_id, "id": item_id, "kind": "item", "name": str(item.get("name", item_id)), "slot": str(item.get("slot", "")),
				"price": price, "currency": str(entry["coin"]), "boss": str(zone_id), "random_tier": true})
	return out
