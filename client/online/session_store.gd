extends RefCounted
## Device ID and bearer tokens are credentials. Never log this object or its contents.
## Browser user:// is IndexedDB, best effort persistence; clearing site data loses device login.
var path := "user://online_account_v1.json"
var problem := ""


static func jwt_payload(token: String) -> Dictionary:
	if token.length() > 16384:
		return {}
	var parts := token.split(".")
	if parts.size() != 3:
		return {}
	var alphabet := RegEx.new()
	alphabet.compile("^[A-Za-z0-9_-]+$")
	if alphabet.search(parts[1]) == null:
		return {}
	var payload := parts[1].replace("-", "+").replace("_", "/")
	while payload.length() % 4:
		payload += "="
	var parser := JSON.new()
	if parser.parse(Marshalls.base64_to_utf8(payload)) != OK or not (parser.data is Dictionary):
		return {}
	if not (parser.data.get("exp") is float or parser.data.get("exp") is int) or not (parser.data.get("uid", "") is String):
		return {}
	return parser.data


func load_state(scope: String) -> Dictionary:
	problem = ""
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		problem = "cache_unreadable"
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not (parser.data is Dictionary):
		problem = "cache_invalid"
		return {}
	var state: Dictionary = parser.data
	if int(state.get("version", 0)) != 1 or str(state.get("device", "")).length() < 20 or state.get("scope", "") != scope:
		problem = "cache_scope_or_format"
		return {}
	# Discard malformed tokens, preserving device identity. Only the server validates signatures.
	for key in ["token", "refresh_token"]:
		if not str(state.get(key, "")).is_empty() and jwt_payload(str(state[key])).is_empty():
			state[key] = ""
	return state


func save_state(state: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	file.close()
	if OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		if FileAccess.set_unix_permissions(temporary, 384) != OK:  # owner read/write only
			DirAccess.remove_absolute(temporary)
			return false
	return DirAccess.rename_absolute(temporary, path) == OK


static func new_device() -> String:
	return "zorx-" + Crypto.new().generate_random_bytes(32).hex_encode()
