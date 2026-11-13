extends RefCounted
## Deterministic identity-only migration. No RNG, new item, stat roll, money or client command.
static var _data: Dictionary = {}
static func canonical(identity: String,slot: String) -> String:
	if _data.is_empty():
		var value = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/armor_migration.json"))
		if value is Dictionary: _data=value
	if _data.get("aliases",{}).has(identity): return str(_data.aliases[identity])
	# Every retired/unknown armor identity is mapped, including IDs absent from the old catalog.
	if _data.get("plain_slots",{}).has(slot):
		if str(_data.get("allowed_armor",{}).get(identity,"")) != slot:
			return str(_data.plain_slots[slot])
	return identity
static func apply(item) -> void:
	var replacement := canonical(item.item_id,item.slot)
	if replacement==item.item_id: return
	item.item_id=replacement
	# New shoe armor uses DEF instead of the retired main MOVESPD. Keep every rolled substat.
	if item.slot == "pants": item.main_stat="HP"
	elif item.slot in ["shirt","armband","shoes"]: item.main_stat="DEF"
