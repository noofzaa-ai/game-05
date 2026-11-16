extends RefCounted
## Deterministic identity-only migration. No RNG, new item, stat roll, money or client command.
static var _data: Dictionary = {}
## Boss 2026-11-16: race armour became CLASS armour. race_<race>_<class>_<armour slot> -> armour_<class>_<slot> (same
## slot, so same tier/durability/refine/sockets: only item_id changes). Pure and idempotent; the weapons keep their ids.
static var _race_armour := RegEx.create_from_string("^race_[a-z]+_(sword_shield|greatsword|longbow|magic)_(shirt|pants|armband|shoes)$")
static func canonical(identity: String,slot: String) -> String:
	var old := _race_armour.search(identity)
	if old != null:
		return "armour_%s_%s" % [old.get_string(1), old.get_string(2)]
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
