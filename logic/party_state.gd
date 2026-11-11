extends RefCounted
## Readiness/leadership rules; admission identity is supplied by the trusted room boundary.
var capacity := 4
var members := {}
var departing := false

func join(id: int) -> bool:
	if members.has(id): return true
	if id < 1 or id > 4 or members.size() >= capacity or departing: return false
	members[id] = {"ready": false, "connected": true}
	reset_ready()
	return true

func leave(id: int) -> void:
	members.erase(id)
	departing = false
	reset_ready()

func presence(id: int, online: bool) -> void:
	if not members.has(id): return
	members[id].connected = online
	if not online: reset_ready()

func reset_ready() -> void:
	for id in members: members[id].ready = false

func leader() -> int:
	return -1 if members.is_empty() else int(members.keys().min())

func set_ready(id: int, value: bool) -> bool:
	if not members.has(id) or not members[id].connected or departing: return false
	members[id].ready = value
	return true

func can_depart(id: int) -> bool:
	return id == leader() and not departing and not members.is_empty() and members.values().all(func(member): return member.ready and member.connected)

func view(names: Dictionary, lobby: bool) -> Dictionary:
	var roster := []
	var ids := members.keys(); ids.sort()
	for id in ids: roster.append({"id": id, "name": names.get(id, "P%d" % id), "ready": members[id].ready, "connected": members[id].connected})
	return {"leader": leader(), "capacity": capacity, "lobby": lobby, "departing": departing, "members": roster}
