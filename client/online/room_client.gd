extends RefCounted
## Authenticated admission RPC only; no identity/profile is supplied by the caller.
const Account := preload("res://client/online/account_status.gd")
var last_room := ""

func create(account, capacity: int = 2, camp: bool = false, farm_map: String = "", diagnostic: bool = false, companion: String = "", companion_seed: String = "") -> Dictionary:
	var payload := {"v": 1, "capacity": capacity}
	if not companion.is_empty():
		payload.companion = companion
		payload.companion_seed = companion_seed
	if diagnostic: payload.diagnostic = true
	if camp: payload.camp = true
	if not farm_map.is_empty(): payload.farm_map = farm_map
	return await _call(account, "zorx_room_create_v1", payload)

func join(account, room: String, invite: String = "") -> Dictionary:
	var payload := {"v": 1, "room": room}
	if not invite.is_empty(): payload.invite = invite
	var result := await _call(account, "zorx_room_join_v1", payload)
	for retry in range(2):
		if result.get("error") != "conflict": break
		await Engine.get_main_loop().create_timer(.1).timeout
		result = await _call(account, "zorx_room_join_v1", payload)
	return result

func join_friend(account, friend: String) -> Dictionary:
	var payload := {"v": 1, "friend": friend}
	var result := await _call(account, "zorx_room_join_v1", payload)
	for retry in range(2):
		if result.get("error") != "conflict": break
		await Engine.get_main_loop().create_timer(.1).timeout
		result = await _call(account, "zorx_room_join_v1", payload)
	return result

func resume(account) -> Dictionary:
	return await _call(account, "zorx_room_resume_v1", {"v": 1})

func cancel_diagnostic(account) -> Dictionary:
	return await _call(account,"zorx_room_cancel_v1",{"v":1,"diagnostic":true})

func cancel(account, room: String) -> Dictionary:
	return await _call(account, "zorx_room_cancel_v1", {"v": 1, "room": room})

func _call(account, rpc: String, payload: Dictionary) -> Dictionary:
	if account == null or account.status != Account.Status.AUTHENTICATED or account.session == null: return {"ok": false, "error": "not_online"}
	var uid: String = account.session.user_id
	var result = await account.client.rpc_async(account.session, rpc, JSON.stringify(payload))
	if account.session == null or account.session.user_id != uid or account.status != Account.Status.AUTHENTICATED: return {"ok": false, "error": "connection_changed"}
	if result == null or result.is_exception(): return {"ok": false, "error": "unavailable"}
	if result.payload.length() > 4096: return {"ok": false, "error": "unavailable"}
	var data = JSON.parse_string(result.payload)
	if not data is Dictionary or data.get("v") != 1 or not data.get("ok") is bool: return {"ok": false, "error": "unavailable"}
	if data.ok and rpc != "zorx_room_cancel_v1":
		if not data.has_all(["room", "ticket", "url", "player_id", "expires"]): return {"ok": false, "error": "unavailable"}
		last_room = data.room
	return data
