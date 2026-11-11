extends RefCounted
## Only PUBLIC connection data, never DB/signing/runtime secrets.

static func load_default() -> Dictionary:
	var path := "res://data/online.local.json" if FileAccess.file_exists("res://data/online.local.json") else "res://data/online.json"
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not (parser.data is Dictionary):
		return {}
	return parser.data


static func valid(config: Dictionary) -> bool:
	var host := str(config.get("host", ""))
	var scheme := str(config.get("scheme", ""))
	var port := int(config.get("port", 0))
	if int(config.get("version", 0)) != 1 or not config.get("enabled", false):
		return false
	if host.is_empty() or host.contains("/") or host.contains(":") or host.contains("@") or host.contains(" ") or host.contains("?") or host.contains("#"):
		return false
	if scheme not in ["https", "http"] or port < 1 or port > 65535 or str(config.get("client_key", "")).is_empty():
		return false
	# HTTP is allowed only for explicit loopback/Tailscale diagnostics, never on Web.
	if scheme == "http":
		var parts := host.split(".")
		var tailscale := parts.size() == 4 and parts[0] == "100" and parts[1].is_valid_int() and int(parts[1]) >= 64 and int(parts[1]) <= 127 and parts[2].is_valid_int() and int(parts[2]) >= 0 and int(parts[2]) <= 255 and parts[3].is_valid_int() and int(parts[3]) >= 0 and int(parts[3]) <= 255
		return not OS.has_feature("web") and (host in ["127.0.0.1", "localhost"] or tailscale)
	return true


static func scope(config: Dictionary) -> String:
	return "%s://%s:%d" % [config.get("scheme", ""), config.get("host", ""), int(config.get("port", 0))]
