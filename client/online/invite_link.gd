extends RefCounted
## Invitation links never contain account tokens or room-admission tickets.
static func parse(value: String) -> Dictionary:
	var code := value.strip_edges()
	if code.contains("#party="): code = code.get_slice("#party=", 1)
	if RegEx.create_from_string("^[a-f0-9]{32}:[a-f0-9]{32}$").search(code) == null: return {}
	var parts := code.split(":")
	return {"room": parts[0], "invite": parts[1]}

static func create(room: String, invite: String) -> String:
	if parse(room + ":" + invite).is_empty(): return ""
	var base := str(preload("res://client/online/connection_config.gd").load_default().get("game_url", "https://zorxplay.daiyooo.com/"))
	if OS.has_feature("web"): base = str(JavaScriptBridge.eval("window.location.origin + window.location.pathname"))
	return base.get_slice("#", 0) + "#party=" + room + ":" + invite

static func consume() -> Dictionary:
	if not OS.has_feature("web"): return {}
	var value := parse(str(JavaScriptBridge.eval("window.location.hash")))
	if not value.is_empty(): JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + window.location.search)")
	return value
