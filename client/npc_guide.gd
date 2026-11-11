extends RefCounted
## Public wording only. ConfigMap content never controls gameplay or executes markup.
const FALLBACK := "res://data/ui/npc_guides.json"
static func show_for(parent: Node, key: String) -> void:
	var popup := AcceptDialog.new()
	popup.theme = preload("res://client/ink_ui.gd").make_theme()
	parent.add_child(popup)
	var defaults = JSON.parse_string(FileAccess.get_file_as_string(FALLBACK))
	apply(popup, defaults, key)
	popup.confirmed.connect(popup.queue_free)
	popup.canceled.connect(popup.queue_free)
	popup.popup_centered(Vector2i(360, 160))
	if not OS.has_feature("web"): return
	var req := HTTPRequest.new()
	req.timeout = 5.0
	req.body_size_limit = 65536
	popup.add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and is_instance_valid(popup):
			apply(popup, JSON.parse_string(body.get_string_from_utf8()), key)
		req.queue_free())
	var origin = JavaScriptBridge.eval("window.location.origin")
	if not origin is String or not origin.begins_with("https://"):
		req.queue_free()
		return
	req.request(origin + "/config/npc_guides.json?t=" + str(Time.get_unix_time_from_system()), PackedStringArray(["Cache-Control: no-cache"]))
static func apply(popup: AcceptDialog, config, key: String) -> void:
	if not config is Dictionary or config.get("version") != 1 or not config.get("guides") is Dictionary: return
	var guide = config.guides.get(key, config.guides.get("default", {}))
	if not guide is Dictionary: return
	for field in ["title", "body", "confirm"]:
		if not guide.get(field) is String or guide[field].length() > (8000 if field == "body" else 120): return
	popup.title = guide.title
	popup.dialog_text = guide.body
	popup.ok_button_text = guide.confirm
