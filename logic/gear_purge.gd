extends RefCounted
## One-time, versioned purge of the level-15 gear that already dropped into inventories (Boss 2026-11-17: "remove ALL of
## it": cards under level 15 cannot wear it and it only clutters the bag). Server-side profile migration like
## logic/armor_migration.gd: runs from Profile.from_dict (offline load, the server profile runner, rooms and the manager
## all load through it), i.e. at profile LOAD, never mid-run. After it ran, profile.migrations["gear_purge_lv15_v1"] is true
## and it never runs again, so gear that drops legitimately once the pyramid opens is never purged later.
##
## Removed (the rule is derived from the catalog: req_level > 1, no ids enumerated):
##   - stash, vault and run bag pieces with req_level > 1 whose instance id is not "starter-*" and not "tier-up-*"
##   - WORN such pieces on a card whose level is BELOW the piece's req_level; the slot is refilled with that card's starter
##     piece (a weapon slot never stays empty). Worn on a card at/above the req_level stays.
## A socketed Relic returns to the stash first. No gold or refund (Boss: delete). Removed items are logged compactly in
## profile.migrations_log["gear_purge_lv15_v1"] (cap LOG_CAP) so support can restore them.
const Profile := preload("res://logic/profile.gd")
const CardProgress := preload("res://logic/card_progress.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const ItemSystem := preload("res://logic/item_system.gd")

const KEY := "gear_purge_lv15_v1"
const TIER_UP_PREFIX := "tier-up-"
const LOG_CAP := 200


## True only for the literal boolean true; a missing or corrupted flag means "not purged yet".
static func done(p) -> bool:
	return p.migrations.get(KEY, null) is bool and p.migrations[KEY] == true


## A piece this purge would delete from a bag (worn pieces additionally need the card-level test).
static func purgeable(item, rules) -> bool:
	var id := str(item.id)
	if id.begins_with(Profile.STARTER_ID_PREFIX) or id.begins_with(TIER_UP_PREFIX):
		return false
	return rules.catalog.req_level(item.item_id) > 1


## Runs the purge once. `now` = UTC unix time for the log (-1 = the clock). Returns {"ran", "removed", "relics"}.
static func purge(p, rules, now: int = -1) -> Dictionary:
	if done(p):
		return {"ran": false, "removed": 0, "relics": 0}
	var stamp := int(Time.get_unix_time_from_system()) if now < 0 else now
	var entries: Array = []
	var relics := {"n": 0}
	for pair in [["stash", p.stash], ["vault", p.vault]]:
		_purge_bag(pair[1], pair[0], p, rules, stamp, entries, relics)
	# Worn pieces. Cards in sorted order so the result never depends on dictionary order.
	var cards: Array = p.card_gear.keys()
	cards.sort()
	for card in cards:
		var worn = p.card_gear[card]["loadout"]
		if worn == null:
			continue
		var level: int = CardProgress.level_of(p.card_deck, str(card))
		var keys: Array = worn._equipped.keys()
		keys.sort()
		for key in keys:
			var item = worn._equipped[key]
			if not purgeable(item, rules) or level >= rules.catalog.req_level(item.item_id):
				continue
			var slot_id := str(key).get_slice(":", 0)
			var index := int(str(key).get_slice(":", 1))
			worn.unequip(slot_id, index)
			_release_relic(p, item, relics)
			entries.append(_entry(item, "worn:%s:%s" % [card, slot_id], stamp))
			_refill(p, rules, str(card), slot_id, index)
	var removed := entries.size()
	if removed > 0:
		var log: Array = p.migrations_log.get(KEY, [])
		log.append_array(entries)
		p.migrations_log[KEY] = log.slice(0, LOG_CAP)
		print("gear_purge_lv15_v1 removed=%d relics_returned=%d" % [removed, relics.n])
	p.migrations[KEY] = true
	p.gear_purge_fresh = true
	return {"ran": true, "removed": removed, "relics": relics.n}


## The run bag of a run restored together with a profile that was just purged (Run.from_dict). `where` = "bag".
static func purge_bag(p, bag, rules, now: int = -1) -> int:
	var stamp := int(Time.get_unix_time_from_system()) if now < 0 else now
	var entries: Array = []
	_purge_bag(bag, "bag", p, rules, stamp, entries, {"n": 0})
	if not entries.is_empty():
		var log: Array = p.migrations_log.get(KEY, [])
		log.append_array(entries)
		p.migrations_log[KEY] = log.slice(0, LOG_CAP)
	return entries.size()


## Plain-dictionary form: loads the saved profile (which purges on load), returns the saved form again; null if invalid.
static func purge_dict(d: Dictionary, rules, camp):
	var p = Profile.from_dict(d, rules, camp)
	return p.to_dict() if p != null else null


## A saved log read back from JSON: typed again (ints stay ints), capped, non-dictionary junk dropped.
static func clean_log(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key in raw:
		if not raw[key] is Array:
			continue
		var list: Array = []
		for e in raw[key]:
			if e is Dictionary and list.size() < LOG_CAP:
				list.append({"item_id": str(e.get("item_id", "")), "tier": int(e.get("tier", 0)), "refine": int(e.get("refine", 0)), "dur": float(e.get("dur", 0.0)), "id": str(e.get("id", "")), "where": str(e.get("where", "")), "at": int(e.get("at", 0))})
		out[str(key)] = list
	return out


static func _purge_bag(bag, where: String, p, rules, stamp: int, entries: Array, relics: Dictionary) -> void:
	var kept: Array[Item] = []
	for item in bag.items:
		if purgeable(item, rules):
			_release_relic(p, item, relics)
			entries.append(_entry(item, where, stamp))
		else:
			kept.append(item)
	bag.items.assign(kept)


const Item := preload("res://logic/item.gd")


static func _release_relic(p, item, relics: Dictionary) -> void:
	if str(item.relic).is_empty():
		return
	p.stash.add_material(item.relic, 1)  # materials take no slot: always fits
	item.relic = ""
	relics.n += 1


static func _entry(item, where: String, stamp: int) -> Dictionary:
	return {"item_id": item.item_id, "tier": item.tier, "refine": item.refine_level, "dur": snappedf(item.durability, 0.1),
		"id": item.id, "where": where, "at": stamp}


## Starter piece into an emptied worn slot: the kit refill first, else a starter piece the account still holds in the stash or
## vault, else a fresh one with a fixed id (a weapon slot must never stay empty).
static func _refill(p, rules, card: String, slot_id: String, index: int) -> void:
	var worn = p.card_gear[card]["loadout"]
	p._fill_starter_kit(rules, card)
	if worn.item_at(slot_id, index) != null:
		return
	for bag in [p.stash, p.vault]:
		for at in bag.items.size():
			var held = bag.items[at]
			if held.id.begins_with(Profile.STARTER_ID_PREFIX) and held.slot == slot_id and Profile.slot_problem(card, held, rules).is_empty():
				worn.equip(bag.take_item(at), index)
				return
	var kits: Dictionary = Profile.starter_kits()
	var piece := Profile.starter_piece(rules, card, slot_id, CardDeck.gear_race(p.card_deck, card))
	var tier := 0
	for t in rules.tiers.size():
		if str(rules.tiers[t]["id"]) == str(kits.get("tier", "normal")):
			tier = t
	if piece.is_empty():
		return
	var id := "starter-purge-v1-%s-%s" % [card, slot_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var fresh = ItemSystem.create_item(rules, id, slot_id, tier, rng, "", piece)
	if fresh != null and fresh.item_id == piece:
		worn.equip(fresh, index)
