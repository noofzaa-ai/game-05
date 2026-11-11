extends RefCounted
## M3-4 RPC adapter. No local profile upload/merge and no fallback to local mutations.
## M4 RemoteSession will consume these authoritative snapshots.
const Account := preload("res://client/online/online_account.gd")
var revision := 0
var _owner := ""

func fetch(account) -> Dictionary:
	return await _call(account, "zorx_profile_get_v1", {"v": 1})

## Keep this returned envelope unchanged when retrying a request after a timeout.
func prepare(command: Dictionary) -> Dictionary:
	if revision < 1: return {}
	return {"v": 1, "revision": revision, "request_id": Crypto.new().generate_random_bytes(16).hex_encode(), "command": command.duplicate(true)}

func submit(account, request: Dictionary) -> Dictionary:
	if request.is_empty(): return {"ok": false, "error": "profile_required"}
	return await _call(account, "zorx_profile_command_v1", request)

func _call(account, rpc: String, payload: Dictionary) -> Dictionary:
	if account.status != Account.Status.AUTHENTICATED or account.session == null or account.client == null:
		return {"ok": false, "error": "not_online"}
	var uid: String = account.session.user_id
	if not _owner.is_empty() and _owner != uid:
		revision = 0
		_owner = ""
		if rpc != "zorx_profile_get_v1": return {"ok": false, "error": "profile_required"}
	var response = await account.client.rpc_async(account.session, rpc, JSON.stringify(payload))
	if account.status != Account.Status.AUTHENTICATED or account.session == null or account.session.user_id != uid:
		return {"ok": false, "error": "connection_changed"}
	if response == null or response.is_exception(): return {"ok": false, "error": "unavailable"}
	var parser := JSON.new()
	if response.payload.length() > 524288 or parser.parse(response.payload) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "unavailable"}
	var data: Dictionary = parser.data
	if not (data.get("v") is int or data.get("v") is float) or data.v != 1 or not data.get("ok") is bool:
		return {"ok": false, "error": "unavailable"}
	if not data.ok:
		# Machine codes only; do not display raw backend/transport diagnostics.
		var error = data.get("error", "unavailable")
		if not error is String or RegEx.create_from_string("^[a-z_]{1,40}$").search(error) == null: error = "unavailable"
		return {"ok": false, "error": error}
	if not data.get("profile") is Dictionary or not (data.get("revision") is int or data.get("revision") is float) or data.revision < 1 or data.revision != floorf(data.revision):
		return {"ok": false, "error": "unavailable"}
	# Ignore older overlapping responses in local revision tracking.
	if _owner == uid and int(data.revision) < revision: return {"ok": false, "error": "stale_response"}
	_owner = uid
	revision = int(data.revision)
	return data
