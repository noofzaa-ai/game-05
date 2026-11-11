extends Node
## Client identity only. LocalSession still owns gameplay until RemoteSession integration.
signal changed

const ConnectionConfig := preload("res://client/online/connection_config.gd")
const SessionStore := preload("res://client/online/session_store.gd")
const InkUi := preload("res://client/ink_ui.gd")
const HttpAdapter := preload("res://client/online/http_adapter.gd")
const Status = preload("res://client/online/account_status.gd").Status
var status := Status.OFFLINE
var reason := "not_connected"
var auth_method := ""
var session  # NakamaSession; never print it (SDK string conversion contains tokens).
var client
var store = SessionStore.new()
var _adapter
var _generation := 0
var _cache := {}
var _config := {}
var _refresh_in := 30.0
var _started := false
var _google_session := {}
var _presence_in := 0.0
var _presence_busy := false
var _badge: Label


func _ready() -> void:
	if name == "Online":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--net-account="):
				var suffix := arg.trim_prefix("--net-account=")
				if RegEx.create_from_string("^[a-zA-Z0-9_-]{1,32}$").search(suffix) != null:
					store.path = "user://online_debug_%s.json" % suffix
		get_node("/root/Nakama").logger._level = NakamaLogger.LOG_LEVEL.NONE
		_build_badge()


func _process(delta: float) -> void:
	if _badge != null:
		var scene := get_tree().current_scene
		# Hidden in the fight and on its summary (Boss 2026-11-11: it covered the wave banner and the boss name).
		_badge.visible = scene != null and scene.scene_file_path not in ["res://scenes/title.tscn", "res://scenes/boot.tscn", "res://scenes/stage.tscn", "res://scenes/journey.tscn"]
		_badge.text = status_text()
	if status != Status.AUTHENTICATED:
		return
	_presence_in -= delta
	if _presence_in <= 0.0 and not _presence_busy:
		_presence_in = 25.0
		_presence()
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 30.0
		# Periodic bounded verification also detects a dropped network while menus/gameplay continue.
		connect_account(_config)


func status_text() -> String:
	match status:
		Status.CONNECTING:
			return "กำลังเชื่อมต่อบัญชี…"
		Status.AUTHENTICATED:
			var game = get_node_or_null("/root/GameState")
			if game != null and game.remote_session != null:
				return "ห้องออนไลน์ · เซิร์ฟเวอร์บันทึกเมื่อจบรอบ"
			return "บัญชีออนไลน์ · ตัวละครและคลังเดียวกันทั้ง solo / co-op"
	return "ยังไม่เชื่อมต่อ · ต้องต่ออินเทอร์เน็ตเพื่อเล่น"


func begin() -> void:
	if not _started:
		_started = true
		connect_account()


func use_offline() -> void:
	_generation += 1
	if _adapter != null:
		_adapter.cancel_all()
	session = null
	status = Status.OFFLINE
	reason = "chosen_offline"
	changed.emit()


func _set_offline(why: String, generation: int) -> void:
	if generation != _generation:
		return
	session = null
	status = Status.OFFLINE
	reason = why
	print("online account: offline (", why, ")")
	changed.emit()


func _make_client(config: Dictionary):
	if _adapter != null:
		_adapter.cancel_all()
		_adapter.queue_free()
	_adapter = HttpAdapter.new()
	_adapter.timeout = 10
	_adapter.logger._level = NakamaLogger.LOG_LEVEL.NONE
	add_child(_adapter)
	return NakamaClient.new(_adapter, str(config.client_key), str(config.scheme), str(config.host), int(config.port), 10)


func _unauthorized(result) -> bool:
	return result != null and result.is_exception() and result.get_exception().status_code == 401


func connect_account(config: Dictionary = {}) -> void:
	if status == Status.CONNECTING:
		return
	_config = ConnectionConfig.load_default() if config.is_empty() else config.duplicate()
	_generation += 1
	var generation := _generation
	if not ConnectionConfig.valid(_config):
		_set_offline("not_configured", generation)
		return
	status = Status.CONNECTING
	reason = ""
	changed.emit()
	var google_required := OS.has_feature("web")
	if google_required and _google_session.is_empty():
		var raw = JavaScriptBridge.eval("JSON.stringify(window.zorxGoogleSession || null)", true)
		var decoded = JSON.parse_string(str(raw))
		if not decoded is Dictionary or not decoded.has_all(["token", "refresh_token", "user_id", "api_origin"]):
			_set_offline("google_login_required", generation)
			return
		if str(decoded.api_origin) != ConnectionConfig.scope(_config).trim_suffix(":443"):
			_set_offline("google_backend_mismatch", generation)
			return
		_google_session = decoded
		JavaScriptBridge.eval("window.zorxGoogleSession = null", true)
	if google_required:
		# Keep the legacy device account cache intact. Never merge inventories by email/name.
		store.path = "user://online_google_%s.json" % str(_google_session.user_id).sha256_text().substr(0, 24)
	_cache = store.load_state(ConnectionConfig.scope(_config))
	if not store.problem.is_empty():
		_set_offline(store.problem, generation)
		return  # Never silently replace an unreadable/different backend identity.
	if _cache.is_empty():
		_cache = {"version": 1, "scope": ConnectionConfig.scope(_config), "device": SessionStore.new_device(), "registered": false, "user_id": "", "token": "", "refresh_token": ""}
		if not store.save_state(_cache):
			_set_offline("cache_write_failed", generation)
			return
	if google_required and not _google_session.get("consumed", false):
		_cache.merge({"token": _google_session.token, "refresh_token": _google_session.refresh_token, "user_id": _google_session.user_id}, true)
		_google_session["consumed"] = true
	client = _make_client(_config)
	var candidate
	var source := "device"
	var token := str(_cache.get("token", ""))
	if not token.is_empty():
		source = "restored"
		candidate = NakamaSession.new(token, false, str(_cache.get("refresh_token", "")))
		if candidate.would_expire_in(90):
			if not candidate.refresh_token.is_empty() and not candidate.is_refresh_expired():
				source = "refresh"
				candidate = await client.session_refresh_async(candidate)
				if generation != _generation:
					return
				if candidate.is_exception():
					if not _unauthorized(candidate):
						_set_offline("refresh_unavailable", generation)
						return
					candidate = null
			else:
				candidate = null
	if candidate != null and (not candidate.valid or candidate.user_id.is_empty()):
		_set_offline("invalid_session", generation)
		return
	if candidate != null:
		var restored_account = await client.get_account_async(candidate)
		if generation != _generation:
			return
		if restored_account.is_exception():
			if not _unauthorized(restored_account):
				_set_offline("account_unavailable", generation)
				return
			candidate = null
		elif restored_account.user == null or restored_account.user.id != candidate.user_id:
			_set_offline("account_mismatch", generation)
			return
	if candidate == null:
		if google_required:
			_set_offline("google_login_required", generation)
			return
		source = "device"
		candidate = await client.authenticate_device_async(str(_cache.device), null, not bool(_cache.get("registered", false)))
		if generation != _generation:
			return
		if candidate.is_exception() or not candidate.valid or candidate.user_id.is_empty():
			_set_offline("authentication_unavailable", generation)
			return
		var account = await client.get_account_async(candidate)
		if generation != _generation:
			return
		if account.is_exception() or account.user == null or account.user.id != candidate.user_id:
			_set_offline("account_unavailable", generation)
			return
	if not str(_cache.get("user_id", "")).is_empty() and _cache.user_id != candidate.user_id:
		_set_offline("account_mismatch", generation)
		return
	_cache.merge({"registered": true, "user_id": candidate.user_id, "token": candidate.token, "refresh_token": candidate.refresh_token}, true)
	if not store.save_state(_cache):
		_set_offline("cache_write_failed", generation)
		return
	session = candidate
	status = Status.AUTHENTICATED
	reason = ""
	_refresh_in = 30.0
	auth_method = "google" if google_required else source
	print("online account: authenticated (", source, ")")
	changed.emit()


func _build_badge() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_badge = Label.new()
	_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_badge.position = Vector2(-210, 6)
	_badge.size = Vector2(420, 28)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.theme = InkUi.make_theme()
	InkUi.style_text(_badge, InkUi.GOLD, InkUi.FONT_BODY, 4)
	layer.add_child(_badge)


func _presence() -> void:
	if client == null or session == null: return
	_presence_busy = true
	await client.rpc_async(session, "zorx_social_v1", JSON.stringify({"v": 1, "op": "presence"}))
	_presence_busy = false


## Explicit account switch: discard this account's credentials before leaving the game.
func logout_to_website() -> void:
	use_offline()
	_started = false
	_google_session.clear()
	_cache.clear()
	auth_method = ""
	if FileAccess.file_exists(store.path):
		DirAccess.remove_absolute(store.path)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.zorxGoogleSession = null; window.zorxAutoEnter = false; location.replace('https://zorx.daiyooo.com/?logout=1');", true)
