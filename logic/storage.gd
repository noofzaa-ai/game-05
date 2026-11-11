extends RefCounted
## Transfers move existing ownership inside one profile transaction; never create/copy items.
static func _containers(profile, source: String) -> Array:
	if source == "stash": return [profile.stash, profile.vault]
	if source == "vault": return [profile.vault, profile.stash]
	return []

static func move_item(profile, id: String, source: String) -> Dictionary:
	var stores := _containers(profile, source)
	if stores.is_empty(): return {"ok": false, "reason": "invalid_container"}
	var at := -1
	for index in stores[0].items.size():
		if stores[0].items[index].id == id: at = index; break
	if at < 0: return {"ok": false, "reason": "item_not_in_container"}
	if stores[1].free_slots() < 1: return {"ok": false, "reason": "storage_full" if source == "stash" else "backpack_full"}
	var piece = stores[0].take_item(at)
	stores[1].items.append(piece)
	return {"ok": true, "item": id, "source": source, "destination": "vault" if source == "stash" else "stash"}

static func move_material(profile, camp, id: String, count: int, source: String) -> Dictionary:
	var stores := _containers(profile, source)
	if stores.is_empty(): return {"ok": false, "reason": "invalid_container"}
	if not camp.materials.has(id): return {"ok": false, "reason": "invalid_material"}
	if count <= 0 or count > stores[0].material_count(id) or count > stores[0].stack_size(id): return {"ok": false, "reason": "invalid_count"}
	if stores[1].room_for(id) < count: return {"ok": false, "reason": "storage_full" if source == "stash" else "backpack_full"}
	# Both quantities/capacity are validated before either side changes. No yield/network here.
	stores[0].remove_material(id, count)
	stores[1].add_material(id, count)
	return {"ok": true, "material": id, "count": count, "source": source, "destination": "vault" if source == "stash" else "stash"}
