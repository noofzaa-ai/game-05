extends RefCounted
## Sparse state deltas against an acknowledged connection-scoped baseline.
const Wire := preload("res://logic/net_wire.gd")

static func difference(now: Dictionary, before: Dictionary, base: int, ack: int, entity_cache = null) -> Dictionary:
	var cache_key := "%d:%d:%d:%d" % [now.epoch, now.tick, int(before.get("epoch", -1)), int(before.get("tick", -1))]
	var shared: Dictionary = entity_cache.get(cache_key, {}) if entity_cache is Dictionary else {}
	if shared.is_empty() or shared.get("source_before") != before.get("entities", {}) or shared.get("source_now") != now.entities:
		shared = entity_difference(now, before)
		if entity_cache is Dictionary:
			shared["source_before"] = before.get("entities", {}).duplicate(true); shared["source_now"] = now.entities.duplicate(true)
			entity_cache[cache_key] = shared
			if entity_cache.size() > 32: entity_cache.erase(entity_cache.keys()[0])
	var changes: Dictionary = shared.changes
	var removed: Array = shared.removed
	var out := {"base": base, "tick": now.tick, "epoch": now.epoch, "ack": ack, "entities": changes, "remove": removed}
	for key in ["projectiles", "areas"]:
		if not before.has(key) or before[key] != now[key]: out[key] = now[key]
	var sets := []; var deletes := []
	_meta_diff(now.meta, before.get("meta", {}), [], sets, deletes)
	if not sets.is_empty() or not deletes.is_empty(): out["meta"] = {"set": sets, "delete": deletes}
	return out

static func entity_difference(now: Dictionary, before: Dictionary) -> Dictionary:
	var changes := {}; var removed := []
	for id in before.get("entities", {}):
		if not now.entities.has(id): removed.append(id)
	for id in now.entities:
		var row := [{}, {}]
		for group in range(2):
			for index in range(now.entities[id][group].size()):
				if not before.get("entities", {}).has(id) or before.entities[id][group][index] != now.entities[id][group][index]: row[group][index] = now.entities[id][group][index]
		if not row[0].is_empty() or not row[1].is_empty(): changes[id] = row
	return {"changes": changes, "removed": removed}

static func _meta_diff(now, before, path: Array, sets: Array, deletes: Array) -> void:
	if is_same(now, before): return
	if now is Dictionary and before is Dictionary:
		for key in before:
			if not now.has(key): deletes.append(path + [key])
		for key in now:
			if not before.has(key): sets.append([path + [key], now[key]])
			else: _meta_diff(now[key], before[key], path + [key], sets, deletes)
	elif now != before: sets.append([path, now])

static func apply(before: Dictionary, patch: Dictionary) -> Dictionary:
	if not patch.has_all(["base", "tick", "epoch", "ack", "entities", "remove"]) or not patch.entities is Dictionary or not patch.remove is Array: return {}
	var out := before.duplicate(true) if patch.base != 0 else {"entities": {}, "meta": {}, "projectiles": [], "areas": []}
	for field in ["tick", "epoch", "ack"]:
		if not patch[field] is int or patch[field] < 0: return {}
		out[field] = patch[field]
	for id in patch.remove: out.entities.erase(id)
	for id in patch.entities:
		if not id is int or id < 1 or id > 1000000: return {}
		var fields = patch.entities[id]
		if not fields is Array or fields.size() != 2: return {}
		if not out.entities.has(id):
			var body := []; var fighter := []
			body.resize(Wire.BODY_FIELDS.size()); fighter.resize(Wire.FIGHTER_FIELDS.size())
			out.entities[id] = [body, fighter]
		for group in range(2):
			if not fields[group] is Dictionary: return {}
			for index in fields[group]:
				if not index is int or index < 0 or index >= out.entities[id][group].size(): return {}
				out.entities[id][group][index] = fields[group][index]
			if out.entities[id][group].has(null): return {}
	for field in ["projectiles", "areas"]:
		if patch.has(field):
			if not patch[field] is Array or patch[field].size() > 256: return {}
			out[field] = patch[field].duplicate(true)
	if patch.has("meta"):
		var meta = patch.meta
		if not meta is Dictionary or not meta.get("set") is Array or not meta.get("delete") is Array: return {}
		for entry in meta.set:
			if not entry is Array or entry.size() != 2 or not _path(out.meta, entry[0], entry[1], false): return {}
		for path in meta.delete:
			if not _path(out.meta, path, null, true): return {}
	return out

static func _path(root: Dictionary, path, value, remove: bool) -> bool:
	if not path is Array or path.is_empty() or path.size() > 12: return false
	var target := root
	for i in range(path.size()):
		var key = path[i]
		if not key is String and not key is int: return false
		if i == path.size() - 1:
			if remove: target.erase(key)
			else: target[key] = value
		else:
			if not target.has(key): target[key] = {}
			if not target[key] is Dictionary: return false
			target = target[key]
	return true
