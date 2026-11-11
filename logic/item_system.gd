extends RefCounted
## What can be done to equipment: create, raise the tier, enhance (+1..+10).
## All randomness comes from the RandomNumberGenerator passed in. The server passes its own, so
## players cannot influence it; tests pass a seeded one, so results repeat exactly.
## EXTENDING: new item operations (reroll a sub stat, socket a gem) become new static functions here.

const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")


## A fresh item of the given tier with its sub stats rolled.
## `item_id` names the catalog item it is (its look and set); a catalog weapon takes the catalog's weapon type.
static func create_item(rules: ItemRules, id: String, slot_id: String, tier: int, rng: RandomNumberGenerator, weapon_type: String = "", item_id: String = "") -> Item:
	var slot := rules.slot(slot_id)
	if slot.is_empty() or tier < 0 or tier >= rules.tiers.size():
		return null
	var item := Item.new()
	item.id = id
	item.slot = slot_id
	item.tier = tier
	item.main_stat = slot["main_stat"]
	item_id = preload("res://logic/armor_migration.gd").canonical(item_id,slot_id)
	var base: Dictionary = rules.catalog.entry(item_id)
	if not base.is_empty() and base["slot"] == slot_id:
		item.item_id = item_id
		if not str(base.get("main_stat", "")).is_empty(): item.main_stat=str(base.main_stat)
		if slot_id == "weapon":
			weapon_type = base["weapon_type"]
	item.weapon_type = weapon_type if slot_id == "weapon" else ""
	item.max_durability = rules.durability_max
	item.durability = rules.durability_max
	_add_substats(rules, item, int(rules.tiers[tier]["substat_count"]) - item.substats.size(), rng)
	return item


## Raises the tier by one. The main stat grows with the tier, sub stats already rolled are kept
## (and rescale with the tier), and new ones are rolled until the new tier's count is reached.
## Returns false if the item is already at the top tier or has been destroyed.
static func upgrade_tier(rules: ItemRules, item: Item, rng: RandomNumberGenerator) -> bool:
	if item.destroyed or item.tier >= rules.tiers.size() - 1:
		return false
	item.tier += 1
	_add_substats(rules, item, int(rules.tiers[item.tier]["substat_count"]) - item.substats.size(), rng)
	return true


## One enhancement attempt. `protected` means a protection item is being used: outcomes listed in
## rules.protection (default: break and down) turn into "stay".
## Returns {"outcome": "success"|"stay"|"down"|"break"|"maxed"|"invalid",
##          "level_before", "level_after", "boosted_substat" (index, or -1)}.
static func enhance(rules: ItemRules, item: Item, rng: RandomNumberGenerator, protected: bool = false) -> Dictionary:
	var result := {"outcome": "invalid", "level_before": item.level, "level_after": item.level, "boosted_substat": -1}
	if item.destroyed:
		return result
	if item.level >= rules.max_level:
		result["outcome"] = "maxed"
		return result

	var outcome := _roll_outcome(rules.odds_by_level[item.level + 1], rng)
	if protected and rules.protection.has(outcome):
		outcome = rules.protection[outcome]
	result["outcome"] = outcome

	match outcome:
		"success":
			item.level += 1
			if not item.substats.is_empty():
				var index := rng.randi_range(0, item.substats.size() - 1)
				item.substats[index]["boosts"] += 1
				result["boosted_substat"] = index
		"down":
			item.level = maxi(0, item.level - 1)
		"break":
			item.destroyed = true
	result["level_after"] = item.level
	return result


static func _roll_outcome(odds: Dictionary, rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var cumulative := 0.0
	var last := "stay"
	for outcome in ItemRules.OUTCOMES:
		var probability: float = odds.get(outcome, 0.0)
		if probability <= 0.0:
			continue
		cumulative += probability
		last = outcome
		if roll < cumulative:
			return outcome
	return last


## Rolls `count` new, distinct sub stats (never the main stat, never one the item already has).
static func _add_substats(rules: ItemRules, item: Item, count: int, rng: RandomNumberGenerator) -> void:
	var candidates: Array[String] = []
	for stat in rules.stat_ids:
		if stat == item.main_stat:
			continue
		var taken := false
		for sub in item.substats:
			taken = taken or sub["stat"] == stat
		if not taken:
			candidates.append(stat)
	for i in count:
		if candidates.is_empty():
			return
		var pick := rng.randi_range(0, candidates.size() - 1)
		item.substats.append({"stat": candidates[pick], "quality": rng.randf(), "boosts": 0})
		candidates.remove_at(pick)
