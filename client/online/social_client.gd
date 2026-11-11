extends RefCounted
const Account := preload("res://client/online/online_account.gd")
var friends: Array = []
var invites: Array = []

func call_rpc(account, operation: String, values: Dictionary = {}) -> Dictionary:
	if account == null or account.status != Account.Status.AUTHENTICATED or account.session == null: return {"ok": false, "error": "not_online"}
	var uid: String = account.session.user_id
	var request: Dictionary = values.duplicate(true); request.v = 1; request.op = operation
	var result = await account.client.rpc_async(account.session, "zorx_social_v1", JSON.stringify(request))
	if account.session == null or account.session.user_id != uid: return {"ok": false, "error": "connection_changed"}
	if result == null or result.is_exception() or result.payload.length() > 32768: return {"ok": false, "error": "unavailable"}
	var decoded = JSON.parse_string(result.payload)
	if not decoded is Dictionary or decoded.get("v") != 1 or not decoded.get("ok") is bool: return {"ok": false, "error": "unavailable"}
	if decoded.ok:
		if decoded.get("friends") is Array: friends = decoded.friends
		if decoded.get("invites") is Array: invites = decoded.invites
	return decoded
