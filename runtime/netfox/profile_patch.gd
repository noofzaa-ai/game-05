extends RefCounted
## Client side of a room snapshot: apply a CHANGED own-profile block without rebuilding the whole Profile.
## Profile.from_dict also runs the save migrations (starter kits, purges, deck repair): 8-17 ms natively, 5-10x on a
## phone, and fired 9 times in 8 s of a goblin fight (gear wear and loot moving). When the authority's block differs from
## the last applied one only in `loadout`, `stash` or `vault`, only those parts are decoded (same decoders as from_dict).
## Anything else changing, a decode failure, or a different item set in the worn gear -> returns false and the caller
## does the full rebuild, so the resulting state is identical (tests/test_profile_patch.gd compares both paths).
## Server authority is unchanged: this only reads what the authority sent.
const PATCHABLE := ["loadout", "stash", "vault"]


## Keys whose values differ between two raw profile dicts (both directions).
static func changed_keys(previous: Dictionary, raw: Dictionary) -> Array:
	var keys := []
	for key in raw:
		if not previous.has(key) or previous[key] != raw[key]:
			keys.append(key)
	for key in previous:
		if not raw.has(key):
			keys.append(key)
	return keys


## True when `profile` now equals what Profile.from_dict(raw) would have given it (for the fields online sessions copy).
static func apply(profile, previous: Dictionary, raw: Dictionary, rules, camp) -> bool:
	if profile == null or previous.is_empty() or int(raw.get("v", 0)) != 1 or int(previous.get("v", 0)) != 1:
		return false
	var keys := changed_keys(previous, raw)
	for key in keys:
		if not key in PATCHABLE:
			return false
	var Inventory = preload("res://logic/inventory.gd")
	var stacks := {}
	for material in camp.materials:
		stacks[material] = int(camp.materials[material]["stack"])
	var stash = null
	var vault = null
	var worn = null
	if "stash" in keys:
		stash = Inventory.from_dict(raw["stash"], stacks)
		if stash == null: return false
	if "vault" in keys:
		vault = Inventory.from_dict(raw["vault"], stacks)
		if vault == null: return false
		vault.capacity = camp.bank_slots
	if "loadout" in keys:
		if not raw.get("loadout") is Dictionary: return false
		worn = preload("res://logic/loadout.gd").from_dict(raw["loadout"], rules)
		if worn == null: return false
		# Same worn slots and item ids as before: only wear / refine / durability moved. A different set (gear swapped,
		# a migration the full rebuild would run on the new piece) takes the full path.
		var before = profile.loadout
		if before == null or before._equipped.size() != worn._equipped.size(): return false
		for slot in worn._equipped:
			if not before._equipped.has(slot) or before._equipped[slot].id != worn._equipped[slot].id: return false
	if stash != null: profile.stash = stash
	if vault != null: profile.vault = vault
	if worn != null: profile.loadout = worn
	return true
