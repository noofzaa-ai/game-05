extends RefCounted
## Nakama lease, account fences and command receipts for the Netfox Room service.
const Wire := preload("res://logic/net_wire.gd")
var tree: SceneTree
var manager
var peers := {}
var bindings := {}
var maintenance := false
var backend_url := ""
var backend_key := ""
var secret := ""
var worker_id := "staging-0"
var process_id := ""
var sent_bytes := 0
var received_bytes := 0

func start() -> bool:
	backend_url = OS.get_environment("ZORX_ROOM_NAKAMA_URL")
	if backend_url.is_empty(): return true # private-control-only M4-1 compatibility
	backend_key = OS.get_environment("ZORX_ROOM_HTTP_KEY")
	secret = OS.get_environment("ZORX_WORKER_TOKEN")
	if secret.is_empty(): secret = OS.get_environment("ZORX_NAMES_TOKEN")
	if RegEx.create_from_string("^http://(nakama|127\\.0\\.0\\.1|host\\.docker\\.internal):[0-9]+$").search(backend_url) == null or backend_key.length() < 16 or secret.length() < 32: return false
	worker_id = OS.get_environment("ZORX_ROOM_WORKER_ID")
	if worker_id.is_empty(): worker_id = "staging-0"
	process_id = Crypto.new().generate_random_bytes(16).hex_encode()
	return true

func _init(scene_tree: SceneTree, rooms) -> void:
	tree = scene_tree
	manager = rooms

func backend(payload: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 5
	tree.root.add_child(request)
	payload = payload.duplicate(true); payload.v = 1; payload.secret = secret; payload.worker = worker_id; payload.process = process_id
	var url := backend_url + "/v2/rpc/zorx_room_backend_v1?http_key=" + backend_key.uri_encode()
	var error := request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(JSON.stringify(payload)))
	if error != OK:
		request.queue_free(); return {"ok": false, "error": "unavailable"}
	var result: Array = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200: return {"ok": false, "error": "unavailable"}
	var wrapper = JSON.parse_string(result[3].get_string_from_utf8())
	if not wrapper is Dictionary or not wrapper.get("payload") is String: return {"ok": false, "error": "unavailable"}
	var value = JSON.parse_string(wrapper.payload)
	return value if value is Dictionary else {"ok": false, "error": "unavailable"}

func poll_bindings(now:int)->void:
	for id in bindings.keys():
		var binding: Dictionary = bindings[id]
		if not binding.started:
			if now - binding.created > 30000 and not binding.finishing and now >= int(binding.get("finish_retry", 0)): _finish(id, true)
		elif not manager.rooms.has(id):
			if binding.saved:
				if now - int(binding.get("ended_at", now)) < 5000: continue
				for sid in binding.peers.values():
					if peers.has(sid): peers[sid].ws.close(1000, "room ended")
				bindings.erase(id)
				continue
			if not binding.finishing and now >= int(binding.get("finish_retry", 0)): _finish(id, true)
		else:
			var room = binding.room_obj
			if binding.get("pending_companion") is Dictionary and room.lobby and room.has_connected_humans() and not binding.get("companion_accepting",false): _accept_companion(id)
			for slot in binding.offline:
				if now - int(binding.offline[slot]) >= 30000:
					if room.lobby: _leave_lobby(id, slot)
					else: room.eliminate(slot)
			if room.status == "finished" and not binding.saved and not binding.finishing and now >= int(binding.get("finish_retry", 0)): _finish(id, false)
		if not binding.saved and not binding.finishing and not binding.renewing and now - binding.renewed >= 10000: _renew(id)
		if not binding.saved and now - binding.renewed > 45000:
			for sid in binding.peers.values():
				if peers.has(sid): peers[sid].ws.close(1011, "lease unavailable")
			manager.close(id, "lease_unavailable")

func bind_redeemed(sid:int,result:Dictionary)->void:
	if not peers.has(sid): return
	var peer: Dictionary = peers[sid]
	if not result.get("ok", false): peer.ws.close(1008, "ticket invalid"); return
	var id: String = result.room
	if not bindings.has(id):
		bindings[id] = {"fence": result.fence, "capacity": int(result.capacity), "companions": result.get("companions", []).duplicate(true), "pending_companion": result.get("pending_companion"), "camp": result.get("camp", false), "diagnostic":result.get("diagnostic",false), "farm_map": result.get("farm_map", ""), "member_fences": {}, "leaving": {}, "seed": result.seed, "profiles": {}, "peers": {}, "offline": {}, "created": Time.get_ticks_msec(), "renewed": Time.get_ticks_msec(), "renewing": false, "started": false, "starting": false, "finishing": false, "saved": false, "room_obj": null}
	var binding: Dictionary = bindings[id]
	if binding.fence != result.fence or binding.saved: peer.ws.close(1008, "room closed"); return
	var slot := int(result.slot)
	if binding.peers.has(slot) and peers.has(binding.peers[slot]): peers[binding.peers[slot]].ws.close(1008, "connection replaced")
	binding.member_fences[slot] = result.get("member_fence", "")
	binding.peers[slot] = sid; binding.profiles[slot] = result.profile; binding.offline.erase(slot)
	peer.room = id; peer.slot = slot
	peer.ws.send_text(JSON.stringify({"v": 1, "ok": true, "room": id, "player_id": slot, "waiting": not binding.started}))
	if binding.started and manager.rooms.has(id):
		var room = manager.rooms[id].room
		if room.lobby and not room.connected.has(slot):
			var profiles: Array = room.owned_profiles(); profiles.append({"id": slot, "profile": result.profile})
			if not room.rebuild_lobby(profiles): peer.ws.close(1011, "room unavailable"); return
		room.presence(slot, true)
	elif (binding.camp or binding.profiles.size() == binding.capacity) and not binding.starting: _start_room(id)

func _start_room(id: String) -> void:
	var binding: Dictionary = bindings[id]; binding.starting = true
	var result := await backend({"op": "camp" if binding.camp else "start", "room": id, "fence": binding.fence})
	if not result.get("ok", false): binding.starting = false; return
	var profiles := []; var ids: Array = binding.profiles.keys(); ids.sort()
	for slot in ids: profiles.append({"id": slot, "profile": binding.profiles[slot]})
	for entry in binding.get("companions", []):
		if not entry is Dictionary or not entry.has_all(["id", "slot"]) or ids.has(int(entry.slot)):
			binding.starting = false; _finish(id, true); return
		var companion = preload("res://logic/companions/roster.gd").make_profile(str(entry.id), manager.rules, manager.camp, str(entry.seed).hex_to_int() if entry.has("seed") else str(binding.seed).hex_to_int() + int(entry.slot))
		if companion == null: binding.starting = false; _finish(id, true); return
		profiles.append({"id": int(entry.slot), "profile": companion.to_dict()})
	var created: Dictionary = manager.create(id, str(binding.seed).hex_to_int(), profiles, binding.camp, binding.capacity, str(binding.get("farm_map", "")))
	if not created.get("ok", false):
		printerr("ROOM_START_REJECT ", JSON.stringify({"room":id,"error":created.get("error","unknown"),"diagnostic":binding.get("diagnostic",false)}))
		binding.starting = false
		for sid in binding.peers.values():
			if peers.has(sid):
				peers[sid].ws.send_text(JSON.stringify({"v":1,"ok":false,"terminal":true,"error":created.get("error","unknown")}))
				peers[sid].ws.close(1011, "start: " + str(created.get("error","unknown")))
		_finish(id, true)
		return
	binding.started = true; binding.room_obj = manager.rooms[id].room
	if not binding.room_obj.install_companions(binding.get("companions", [])):
		manager.close(id, "invalid_companions"); _finish(id, true); return
	binding.room_obj.require_scene_ready()
	for slot in binding.offline: binding.room_obj.presence(slot, false)

func _renew(id: String) -> void:
	var binding: Dictionary = bindings[id]; binding.renewing = true
	var result := await backend({"op": "heartbeat", "room": id, "fence": binding.fence})
	for retry in range(3):
		if result.get("error") != "conflict": break
		await tree.create_timer(0.05 * (retry + 1)).timeout
		result = await backend({"op": "heartbeat", "room": id, "fence": binding.fence})
	binding.renewing = false
	if result.get("ok", false): binding.renewed = Time.get_ticks_msec()

func _finish(id: String, aborted: bool) -> void:
	var binding: Dictionary = bindings[id]; binding.finishing = true
	var finish_started := Time.get_ticks_msec()
	var profiles: Dictionary = binding.room_obj.finalize(aborted) if binding.room_obj != null else {}
	if binding.room_obj == null:
		for slot in binding.profiles: profiles[str(slot)] = binding.profiles[slot]
	var result := await backend({"op": "finish", "room": id, "fence": binding.fence, "profiles": profiles})
	binding.finishing = false; binding.finish_retry = Time.get_ticks_msec() + 2000
	print("ROOM_FINISH ", JSON.stringify({"room":id,"ok":result.get("ok",false),"error":result.get("error",""),"elapsed_ms":Time.get_ticks_msec()-finish_started}))
	if result.get("ok", false):
		binding.saved = true; binding.ended_at = Time.get_ticks_msec()
		if binding.room_obj != null: binding.room_obj.cloud_saved = true
		else:
			for sid in binding.peers.values():
				if peers.has(sid): peers[sid].ws.close(1000, "room ended")
			bindings.erase(id)

func _drop(sid: int, now: int) -> void:
	var peer: Dictionary = peers[sid]
	if bindings.has(peer.room):
		var binding: Dictionary = bindings[peer.room]
		if binding.peers.get(peer.slot) == sid:
			binding.peers.erase(peer.slot); binding.offline[peer.slot] = now
			if manager.rooms.has(peer.room):
				if binding.get("diagnostic",false): manager.rooms[peer.room].room.require_scene_ready()
				manager.rooms[peer.room].room.presence(peer.slot, false)
	peers.erase(sid)

func _room(id: String):
	if manager.rooms.has(id): return manager.rooms[id].room
	if bindings.has(id): return bindings[id].room_obj
	return null

func _depart(id: String, sid: int, request_id: int) -> void:
	if not bindings.has(id): return
	var binding: Dictionary = bindings[id]
	var room = binding.room_obj
	if not room.lobby:
		_send(sid, Wire.CONTROL, {"id": request_id, "result": {"ok": true}}); return
	if binding.get("departing", false): return
	binding.departing = true
	var result := await backend({"op": "start", "room": id, "fence": binding.fence, "slots": room.party.members.keys()})
	binding.departing = false
	if result.get("ok", false):
		if not room.depart(): manager.close(id, "invalid_state"); result = {"ok": false, "error": "unavailable"}
	else: room.party.departing = false
	_send(sid, Wire.CONTROL, {"id": request_id, "result": result})

func _leave_lobby(id: String, slot: int, sid: int = 0, request_id: int = 0) -> void:
	if not bindings.has(id): return
	var binding: Dictionary = bindings[id]
	if binding.leaving.has(slot) or binding.room_obj == null or not binding.room_obj.lobby or not binding.room_obj.connected.has(slot): return
	binding.leaving[slot] = true
	var room = binding.room_obj
	var result := await backend({"op": "member_leave", "room": id, "fence": binding.fence, "slot": slot, "member": binding.member_fences[slot], "profile": room.trip_for(slot).profile.to_dict()})
	binding.leaving.erase(slot)
	if result.get("ok", false):
		var profiles: Array = room.owned_profiles().filter(func(profile): return profile.id != slot)
		binding.peers.erase(slot); binding.profiles.erase(slot); binding.offline.erase(slot); binding.member_fences.erase(slot)
		if binding.profiles.is_empty():
			binding.saved = true; binding.ended_at = Time.get_ticks_msec(); manager.close(id, "camp_empty")
		else: room.rebuild_lobby(profiles)
		result = {"ok": true, "left": true}
	if sid > 0 and peers.has(sid):
		_send(sid, Wire.CONTROL, {"id": request_id, "result": result})
		if result.get("ok", false):
			peers[sid].leaving = true
			peers[sid].ws.close(1000, "left party")

func _accept_companion(id: String) -> void:
	if not bindings.has(id): return
	var binding: Dictionary = bindings[id]
	if Time.get_ticks_msec() < int(binding.get("companion_retry",0)): return
	binding.companion_accepting = true
	binding.companion_retry = Time.get_ticks_msec()+1000
	var result := await backend({"op":"companion_accept","room":id,"fence":binding.fence})
	binding.companion_accepting = false
	if result.get("error")=="invite_expired": binding.pending_companion=null
	if not result.get("ok",false) or not bindings.has(id) or binding.saved: return
	var room = binding.room_obj
	if room == null or not room.lobby: return
	var entry: Dictionary = result.companion
	var profile = preload("res://logic/companions/roster.gd").make_profile(str(entry.id),manager.rules,manager.camp,str(entry.seed).hex_to_int())
	if profile == null: return
	var profiles: Array = room.owned_profiles()
	profiles.append({"id":int(entry.slot),"profile":profile.to_dict()})
	if not room.rebuild_lobby(profiles) or not room.install_companions([entry]):
		manager.close(id,"companion_join_failed"); return
	binding.companions = [entry]
	binding.pending_companion = null
func _receive(sid: int, bytes: PackedByteArray, _now: int) -> void:
	if not peers.has(sid): return
	var peer: Dictionary = peers[sid]
	var message := Wire.parse(bytes)
	if message.is_empty() or message.kind != Wire.CONTROL: return
	if message.sequence <= peer.in_seq: return
	peer.in_seq = message.sequence
	var room = _room(peer.room)
	if room == null: return
	var decoded := Wire.decode(message.body)
	if decoded.is_empty() or not decoded.value is Dictionary: return
	var value: Dictionary = decoded.value
	if value.size() == 1 and value.get("scene_ready") is int:
		room.scene_ready(peer.slot, value.scene_ready)
	elif value.get("id") is int and value.get("request") is Dictionary and value.get("epoch") is int and value.epoch >= 1:
		var result: Dictionary = room.command(peer.slot, value.id, value.request, value.epoch)
		if result.get("action") == "depart": _depart(peer.room, sid, value.id)
		elif result.get("action") == "leave": _leave_lobby(peer.room, peer.slot, sid, value.id)
		else: _send(sid, Wire.CONTROL, {"id": value.id, "result": result})

func _send(sid: int, kind: int, payload: Dictionary) -> int:
	if not peers.has(sid) or kind != Wire.CONTROL: return 0
	var peer: Dictionary = peers[sid]
	if peer.ws.get_ready_state() != WebSocketPeer.STATE_OPEN: return 0
	peer.out_seq += 1
	var packet := Wire.packet(kind, peer.out_seq, payload)
	if packet.is_empty() or peer.ws.put_packet(packet) != OK: return 0
	sent_bytes += packet.size()
	return peer.out_seq

