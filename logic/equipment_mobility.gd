extends RefCounted
## Server-owned equipment weight. Cosmetics, durability and rarity never remove physical weight.
static func factors(rules, worn: Array) -> Dictionary:
	var config: Dictionary = rules.mobility
	var result := {"armor_penalty":0.0,"weapon_penalty":0.0,"equipment_factor":1.0,"move_factor":1.0,"dodge_factor":1.0}
	if config.is_empty() or not config.get("enabled",false): return result
	for item in worn:
		if item.destroyed: continue
		if item.slot=="weapon":
			result.weapon_penalty=float(config.weapon_penalties.get(item.weapon_type,0.0))
		elif config.slot_weights.has(item.slot):
			var entry: Dictionary = rules.catalog.entry(item.item_id)
			var kind := str(config.item_classes.get(item.item_id,config.set_classes.get(str(entry.get("set","")),str(entry.get("armor_class","")) if not str(entry.get("armor_class","")).is_empty() else "cloth")))  # a set-free piece (starter kit) uses its own armor_class
			result.armor_penalty+=float(config.slot_weights[item.slot])*float(config.armor_penalties.get(kind,0.0))
	result.equipment_factor=(1.0-float(result.armor_penalty))*(1.0-float(result.weapon_penalty))
	result.move_factor=float(config.base_move_multiplier)*float(result.equipment_factor)
	result.dodge_factor=float(config.base_dodge_multiplier)*float(result.equipment_factor)
	return result
