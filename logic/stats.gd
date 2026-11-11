extends RefCounted
## A character's final stats: base stats plus everything the worn equipment adds.
## Set bonuses come from the catalog (data/items/sets.json).
## EXTENDING: buffs and level scaling are added here as extra terms.

const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")


static func totals(rules: ItemRules, worn: Array[Item]) -> Dictionary:
	var result := {}
	for stat in rules.stat_ids:
		result[stat] = rules.stat_base[stat]
	for item in worn:
		if item.destroyed:
			continue
		var from_item := item.stat_totals(rules)
		for stat in from_item:
			result[stat] += from_item[stat]
	var worn_ids: Array = []
	for item in worn:
		if not item.destroyed:
			worn_ids.append(item.item_id)
	var from_sets: Dictionary = rules.catalog.set_bonus(worn_ids)
	for stat in from_sets:
		if result.has(stat):
			result[stat] += from_sets[stat]
	var mobility := preload("res://logic/equipment_mobility.gd").factors(rules,worn)
	result["EQUIPMENT_MOVE_FACTOR"] = mobility.move_factor
	result["EQUIPMENT_DODGE_FACTOR"] = mobility.dodge_factor
	return result


## MOVESPD is a percentage bonus: 20 means walking 20% faster. Feeds SimBody.move_speed_multiplier.
static func move_multiplier(totals_by_stat: Dictionary) -> float:
	return maxf(0.1, 1.0 + float(totals_by_stat.get("MOVESPD", 0.0)) / 100.0) * float(totals_by_stat.get("EQUIPMENT_MOVE_FACTOR",1.0))
