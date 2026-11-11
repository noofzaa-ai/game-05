extends RefCounted
## Boss test kit (2026-10-06, widened 2026-10-15): one of every catalog item (every weapon and every
## armor / clothing piece that has a model) waits in the camp stash, to try every outfit. What the
## character already wears is skipped. The stash grows by the kit's size so the kit never pushes
## out the room normal play has (nothing is silently dropped). Used by GameState when TEST_KIT is on
## and by tools/shots/inventory_shot.gd. TURN OFF BEFORE RELEASE (GameState.TEST_KIT).

const Camp := preload("res://logic/camp.gd")
const ItemSystem := preload("res://logic/item_system.gd")


## The catalog item ids the kit gives `profile`, in rule-book slot order then by id.
static func item_ids(profile, item_rules) -> Array[String]:
	var worn := {}
	for slot in item_rules.slots:
		for index in int(slot["count"]):
			var item = profile.loadout.item_at(str(slot["id"]), index)
			if item != null:
				worn[item.item_id] = true
	var slot_order: Array = item_rules.slots.map(func(slot: Dictionary) -> String: return str(slot["id"]))
	var ids: Array[String] = []
	for item_id in item_rules.catalog.items:
		if not worn.has(item_id):
			ids.append(str(item_id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var sa: int = slot_order.find(item_rules.catalog.entry(a)["slot"])
		var sb: int = slot_order.find(item_rules.catalog.entry(b)["slot"])
		return sa < sb if sa != sb else a < b)
	return ids


## Puts the kit in the stash (tier 0, fresh). `camp_data` is grown in memory by the kit's size and
## the stash resized (Camp.refresh). Returns how many pieces went in.
static func fill(profile, item_rules, camp_data, rng: RandomNumberGenerator) -> int:
	var ids := item_ids(profile, item_rules)
	camp_data.stash_slots += ids.size()
	Camp.refresh(profile, camp_data)
	var added := 0
	for item_id in ids:
		var slot_id: String = item_rules.catalog.entry(item_id)["slot"]
		if profile.stash.add_item(ItemSystem.create_item(item_rules, "test-" + item_id, slot_id, 0, rng, "", item_id)):
			added += 1
		else:
			push_warning("test kit: the stash is full at %s" % item_id)
	return added
