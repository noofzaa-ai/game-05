extends RefCounted
## Authenticated RPC transport only. Server owns canonicalization and uniqueness.
signal completed(operation: String, ticket: int, result: Dictionary)

const Profile := preload("res://logic/profile.gd")
const OnlineAccount := preload("res://client/online/online_account.gd")
const CLAIM_RPC := "zorx_name_claim_v1"
const GET_RPC := "zorx_name_get_v1"
const ERRORS := ["rate_limited", "invalid_payload", "too_short", "too_long", "bad_characters", "name_taken", "conflict", "unavailable"]


func claim(account, name: String) -> Dictionary:
	var problem := Profile.name_problem(name)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return await _call(account, CLAIM_RPC, {"v": 1, "name": name})


func get_name(account) -> Dictionary:
	return await _call(account, GET_RPC, {"v": 1})


func _call(account, rpc: String, payload: Dictionary) -> Dictionary:
	if account.status != OnlineAccount.Status.AUTHENTICATED or account.session == null or account.client == null:
		return {"ok": false, "error": "not_online"}
	var user_id: String = account.session.user_id
	var result = await account.client.rpc_async(account.session, rpc, JSON.stringify(payload))
	if account.status == OnlineAccount.Status.OFFLINE or account.session == null or account.session.user_id != user_id:
		return {"ok": false, "error": "connection_changed"}
	if result == null or result.is_exception():
		return {"ok": false, "error": "unavailable"}
	var parser := JSON.new()
	if result.payload.length() > 2048 or parser.parse(result.payload) != OK or not (parser.data is Dictionary):
		return {"ok": false, "error": "unavailable"}
	var data: Dictionary = parser.data
	if not (data.get("v") is float or data.get("v") is int) or data.get("v") != 1 or not (data.get("ok") is bool) or (data.get("ok") and not data.has("name")):
		return {"ok": false, "error": "unavailable"}
	if not data.ok:
		return {"ok": false, "error": data.error if data.get("error", "") in ERRORS else "unavailable"}
	if rpc == GET_RPC and data.get("name") == null:
		return {"ok": true, "name": ""}
	if not (data.get("name") is String) or not Profile.name_problem(data.name).is_empty():
		return {"ok": false, "error": "unavailable"}
	return {"ok": true, "name": data.name}


func begin_claim(account, name: String, ticket: int) -> void:
	var result := await claim(account, name)
	completed.emit("claim", ticket, result)


func begin_get(account, ticket: int) -> void:
	var result := await get_name(account)
	completed.emit("get", ticket, result)
