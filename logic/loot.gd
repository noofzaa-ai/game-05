extends RefCounted
## Rolls what a defeated monster drops. All randomness comes from the generator passed in (the
## server's; tests use a seeded one). The random numbers are always drawn in the same order, so a
## given seed always gives the same drops.
## EXTENDING: a new kind of drop is a new key in loot.json drop entries and a branch in roll().

const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const LootData := preload("res://logic/loot_data.gd")

# Instance IDs derive from the supplied stream without consuming extra random draws.


## Returns {"gold": int, "materials": {id: count}, "items": Array[Item]}. A monster type with no
## loot table drops nothing. `weapon_types` are the weapon styles a dropped weapon can be.
## `factor` (loot by squad size, JourneyData.loot_for) multiplies every drop chance and the gold; it never
## changes how many random numbers are drawn, so a seed gives the same stream at any factor.
static func roll(rules: ItemRules, loot: LootData, enemy_type: String, level: int, weapon_types: Array, rng: RandomNumberGenerator, factor: float = 1.0) -> Dictionary:
	var result := {"gold": 0, "materials": {}, "items": []}
	if not loot.by_enemy.has(enemy_type):
		return result
	var table: Dictionary = loot.tables[loot.by_enemy[enemy_type]]
	var gold_range: Vector2i = table["gold"]
	var base_gold := rng.randi_range(gold_range.x, gold_range.y)
	result["gold"] = roundi(float(base_gold) * (1.0 + loot.gold_per_level * float(maxi(level, 1) - 1)) * factor)
	for drop in table["drops"]:
		var happens := rng.randf() < float(drop["chance"]) * factor
		if drop.has("material"):
			var count_range: Vector2i = drop["count"]
			var count := rng.randi_range(count_range.x, count_range.y)
			if happens and count > 0:
				result["materials"][drop["material"]] = int(result["materials"].get(drop["material"], 0)) + count
		elif drop.has("item"):
			var item := _roll_item(rules, loot, level, weapon_types, rng)
			if happens and item != null:
				result["items"].append(item)
	return result


static func _roll_item(rules: ItemRules, loot: LootData, level: int, weapon_types: Array, rng: RandomNumberGenerator) -> Item:
	var tier := _roll_tier(loot.weights_for_level(level), rng)
	var instance_id := "drop-%d-%d" % [rng.seed, rng.state]
	return roll_piece(rules, instance_id, mini(tier, rules.tiers.size() - 1), level, weapon_types, rng)


## A random piece of `tier` (monster drops, treasure, challenge rewards). Boss 2026-10-15: only
## pieces that have a model drop, so the slot, the weapon type and the catalog item are drawn from
## what the catalog has for a monster of `level` (ItemCatalog.droppable): accessories, the back slot
## and weapon types with no catalog item (fists) never drop. Only a rule book with an empty catalog
## falls back to plain pieces of any slot (in proportion to how many can be worn).
static func roll_piece(rules: ItemRules, id: String, tier: int, level: int, weapon_types: Array, rng: RandomNumberGenerator) -> Item:
	var slot_ids: Array = rules.slots.map(func(slot: Dictionary) -> String: return str(slot["id"]))
	var allowed: Dictionary = rules.catalog.droppable(slot_ids, weapon_types, level)
	if allowed["slots"].is_empty():
		return _plain_piece(rules, id, tier, weapon_types, rng)
	var slot_id: String = allowed["slots"][rng.randi_range(0, allowed["slots"].size() - 1)]
	var weapon_type := ""
	if slot_id == "weapon":
		weapon_type = allowed["weapon_types"][rng.randi_range(0, allowed["weapon_types"].size() - 1)]
	else:
		rng.randi()  # keep the number of draws the same for every slot
	var choices: Array[String] = rules.catalog.candidates(slot_id, weapon_type, level)
	var item_id: String = choices[rng.randi() % choices.size()]
	return ItemSystem.create_item(rules, id, slot_id, tier, rng, weapon_type, item_id)


## A plain rolled piece (no catalog item: no model) - only when the catalog is empty.
static func _plain_piece(rules: ItemRules, id: String, tier: int, weapon_types: Array, rng: RandomNumberGenerator) -> Item:
	# The slot is chosen in proportion to how many of it can be worn (two rings: twice as likely).
	var pick := rng.randi_range(0, rules.total_slot_count() - 1)
	var slot_id := ""
	for slot in rules.slots:
		if pick < int(slot["count"]):
			slot_id = slot["id"]
			break
		pick -= int(slot["count"])
	var weapon_type := ""
	if slot_id == "weapon" and not weapon_types.is_empty():
		weapon_type = str(weapon_types[rng.randi_range(0, weapon_types.size() - 1)])
	return ItemSystem.create_item(rules, id, slot_id, tier, rng, weapon_type)


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
